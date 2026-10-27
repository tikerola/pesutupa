-- =====================================================================
-- Varattava aika klo 8.00–22.00 (Suomen aikaa).
--
-- * Asetukset: app_private.settings.open_hour / close_hour / time_zone.
-- * create_booking hylkää varaukset, jotka eivät mahdu aukioloaikaan.
-- * extend_booking ei jatka vuoroa sulkemisajan yli.
-- * Uusi funktio public.get_booking_hours kertoo käyttöliittymälle ajat.
--
-- Aja tämä Supabasen SQL Editorissa aiempien migraatioiden jälkeen
-- ja ennen kuin julkaiset uuden käyttöliittymän.
--
-- Aikojen muuttaminen myöhemmin:
--   update app_private.settings set open_hour = 7, close_hour = 23;
-- =====================================================================

begin;

alter table app_private.settings
  add column open_hour  integer not null default 8  check (open_hour between 0 and 23),
  add column close_hour integer not null default 22 check (close_hour between 1 and 24),
  add column time_zone  text    not null default 'Europe/Helsinki',
  add constraint settings_open_before_close check (open_hour < close_hour);

-- Varattavan ajan alku ja loppu sille paikalliselle päivälle, johon p_at osuu.
create function app_private.booking_window(p_at timestamptz, out opens_at timestamptz, out closes_at timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  select ((p_at at time zone s.time_zone)::date + make_interval(hours => s.open_hour))  at time zone s.time_zone,
         ((p_at at time zone s.time_zone)::date + make_interval(hours => s.close_hour)) at time zone s.time_zone
  from app_private.settings s
  where s.id;
$$;

revoke execute on function app_private.booking_window(timestamptz) from public;
do $$
begin
  execute 'revoke execute on function app_private.booking_window(timestamptz) from anon, authenticated';
end $$;

create function public.get_booking_hours(p_token text)
returns table (open_hour integer, close_hour integer)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform app_private.require_session(p_token);
  return query select s.open_hour, s.close_hour from app_private.settings s where s.id;
end;
$$;

revoke execute on function public.get_booking_hours(text) from public;
grant execute on function public.get_booking_hours(text) to anon, authenticated;

create or replace function public.create_booking(
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
  v_open_hour   integer;
  v_close_hour  integer;
  v_opens_at    timestamptz;
  v_closes_at   timestamptz;
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

  select s.booking_horizon_days, s.open_hour, s.close_hour
    into v_horizon, v_open_hour, v_close_hour
  from app_private.settings s where s.id;

  if p_start_at > now() + make_interval(days => v_horizon) then
    raise exception using errcode = 'P0001',
      message = format('Varauksen voi tehdä enintään %s päivää etukäteen.', v_horizon);
  end if;

  v_end := p_start_at + make_interval(mins => p_minutes);

  select w.opens_at, w.closes_at into v_opens_at, v_closes_at from app_private.booking_window(p_start_at) w;
  if p_start_at < v_opens_at or v_end > v_closes_at then
    raise exception using errcode = 'P0001',
      message = format('Pesutupaa voi varata vain klo %s.00–%s.00.', v_open_hour, v_close_hour);
  end if;

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

create or replace function public.extend_booking(p_token text, p_booking_id uuid)
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
  v_session   uuid := app_private.require_session(p_token);
  v_start     timestamptz;
  v_end       timestamptz;
  v_closes_at timestamptz;
begin
  select b.start_at, b.end_at into v_start, v_end
  from app_private.bookings b
  where b.id = p_booking_id and b.session_id = v_session
  for update;

  if v_end is null then
    raise exception using errcode = 'P0001',
      message = 'Varausta ei löytynyt, tai se ei ole tällä laitteella tehty varaus.';
  end if;

  if now() >= v_end then
    raise exception using errcode = 'P0001', message = 'Vuoro on jo päättynyt. Tee tarvittaessa uusi varaus.';
  end if;

  if now() < v_end - interval '1 hour' then
    raise exception using errcode = 'P0001', message = 'Vuoroa voi jatkaa vasta vuoron viimeisen tunnin aikana.';
  end if;

  select w.closes_at into v_closes_at from app_private.booking_window(v_start) w;
  if v_end + interval '1 hour' > v_closes_at then
    raise exception using errcode = 'P0001',
      message = format('Vuoroa ei voi jatkaa klo %s jälkeen.', to_char(v_closes_at at time zone (select s.time_zone from app_private.settings s where s.id), 'FMHH24.MI'));
  end if;

  begin
    update app_private.bookings b
       set end_at = b.end_at + interval '1 hour'
     where b.id = p_booking_id;
  exception
    when exclusion_violation then
      raise exception using errcode = '23P01',
        message = 'Seuraava tunti on jo varattu, joten vuoroa ei voi jatkaa.';
    when check_violation then
      raise exception using errcode = 'P0001', message = 'Vuoroa ei voi jatkaa enempää.';
  end;

  return query
    select b.id, b.device_id, b.apartment_number, b.start_at, b.end_at, true
    from app_private.bookings b where b.id = p_booking_id;
end;
$$;

notify pgrst, 'reload schema';

commit;
