-- =====================================================================
-- Puolen tunnin varausjaksot.
--
-- * Varaus voi alkaa ja päättyä tasa- tai puolelta tunnilta.
-- * Kesto 30 min – 3 h puolen tunnin välein.
-- * create_booking ottaa keston minuutteina (p_minutes) tuntien sijaan.
--
-- Aja tämä Supabasen SQL Editorissa alkuperäisen migraation jälkeen.
-- Aja ENNEN kuin julkaiset uuden käyttöliittymän: vanha käyttöliittymä
-- ei toimi tämän jälkeen, uusi ei toimi ilman tätä.
-- =====================================================================

begin;

alter table app_private.bookings drop constraint bookings_whole_hours;
alter table app_private.bookings add constraint bookings_half_hours check (
  extract(epoch from start_at) % 1800 = 0 and extract(epoch from end_at) % 1800 = 0
);

drop function public.create_booking(text, integer, text, timestamptz, integer);

create function public.create_booking(
  p_token            text,
  p_device_id        integer,
  p_apartment_number text,
  p_start_at         timestamptz,
  p_minutes          integer
)
returns table (
  id               uuid,
  device_id        smallint,
  apartment_number text,
  start_at         timestamptz,
  end_at           timestamptz,
  is_own           boolean
)
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_session     uuid := app_private.require_session(p_token);
  v_apartment   text;
  v_end         timestamptz;
  v_horizon     integer;
  v_block_start timestamptz;
  v_block_end   timestamptz;
  v_min         timestamptz;
  v_max         timestamptz;
  v_id          uuid;
begin
  if not exists (select 1 from app_private.devices d where d.id = p_device_id and d.active) then
    raise exception using errcode = 'P0001', message = 'Valittua laitetta ei löydy.';
  end if;

  v_apartment := upper(regexp_replace(btrim(coalesce(p_apartment_number, '')), '\s+', ' ', 'g'));
  if v_apartment !~ '^[0-9A-ZÅÄÖåäö][0-9A-ZÅÄÖåäö -]{0,9}$' or v_apartment !~ '[0-9]' then
    raise exception using errcode = 'P0001', message = 'Tarkista asunnon numero (esimerkiksi 9 tai A 12).';
  end if;

  if p_minutes is null or p_minutes < 30 or p_minutes > 180 or p_minutes % 30 <> 0 then
    raise exception using errcode = 'P0001', message = 'Varauksen kesto voi olla 30 minuutista 3 tuntiin puolen tunnin välein.';
  end if;

  if p_start_at is null or extract(epoch from p_start_at) % 1800 <> 0 then
    raise exception using errcode = 'P0001', message = 'Varauksen pitää alkaa tasa- tai puolelta tunnilta.';
  end if;

  -- Kuluvan puolen tunnin jakson voi vielä varata.
  if p_start_at < to_timestamp(floor(extract(epoch from now()) / 1800) * 1800) then
    raise exception using errcode = 'P0001', message = 'Mennyttä aikaa ei voi varata.';
  end if;

  select s.booking_horizon_days into v_horizon from app_private.settings s where s.id;
  if p_start_at > now() + make_interval(days => v_horizon) then
    raise exception using errcode = 'P0001',
      message = format('Varauksen voi tehdä enintään %s päivää etukäteen.', v_horizon);
  end if;

  v_end := p_start_at + make_interval(mins => p_minutes);

  -- Saman asunnon vierekkäiset varaukset samalle laitteelle lasketaan yhdeksi
  -- vuoroksi, jotta kolmen tunnin rajaa ei kierretä pilkkomalla varausta.
  v_block_start := p_start_at;
  v_block_end   := v_end;
  loop
    select min(b.start_at), max(b.end_at) into v_min, v_max
    from app_private.bookings b
    where b.device_id = p_device_id
      and b.apartment_number = v_apartment
      and b.start_at <= v_block_end
      and b.end_at >= v_block_start;

    exit when v_min is null or (v_min >= v_block_start and v_max <= v_block_end);
    v_block_start := least(v_block_start, v_min);
    v_block_end   := greatest(v_block_end, v_max);
  end loop;

  if v_block_end - v_block_start > interval '3 hours' then
    raise exception using errcode = 'P0001',
      message = 'Asunnolla on jo varaus tämän ajan vieressä. Yhtäjaksoinen varaus voi olla enintään 3 tuntia. Vuoroa voi jatkaa tunnilla vuoron aikana, jos seuraava tunti on vapaa.';
  end if;

  begin
    insert into app_private.bookings (device_id, apartment_number, start_at, end_at, session_id)
    values (p_device_id, v_apartment, p_start_at, v_end, v_session)
    returning app_private.bookings.id into v_id;
  exception when exclusion_violation then
    raise exception using errcode = '23P01',
      message = 'Valittu aika on jo varattu. Valitse toinen aika.';
  end;

  return query
    select b.id, b.device_id, b.apartment_number, b.start_at, b.end_at, true
    from app_private.bookings b where b.id = v_id;
end;
$$;

revoke execute on function public.create_booking(text, integer, text, timestamptz, integer) from public;
grant execute on function public.create_booking(text, integer, text, timestamptz, integer) to anon, authenticated;

-- PostgREST lukee funktioiden muutokset heti.
notify pgrst, 'reload schema';

commit;
