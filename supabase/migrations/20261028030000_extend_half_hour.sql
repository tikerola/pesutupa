-- =====================================================================
-- Vuoroa voi jatkaa 30 minuutilla tai tunnilla (päätetty 28.10.2026).
-- Esim. klo 21.30 päättyvää vuoroa voi jatkaa puolella tunnilla klo 22 asti.
--
-- Muuttaa vain extend_booking-funktiota. Tauluihin ja olemassa oleviin
-- varauksiin ei kosketa.
--
-- Uudessa funktiossa on parametri p_minutes (30 tai 60, oletus 60), joten
-- vanha käyttöliittymä toimii edelleen. Aja tämä Supabasen SQL Editorissa
-- ENNEN kuin uusi käyttöliittymä julkaistaan.
-- =====================================================================

begin;

drop function if exists public.extend_booking(text, uuid);

create function public.extend_booking(p_token text, p_booking_id uuid, p_minutes integer default 60)
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
  v_extra     interval;
begin
  if p_minutes is null or p_minutes not in (30, 60) then
    raise exception using errcode = 'P0001', message = 'Vuoroa voi jatkaa 30 minuutilla tai tunnilla.';
  end if;
  v_extra := make_interval(mins => p_minutes);

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
  if v_end + v_extra > v_closes_at then
    raise exception using errcode = 'P0001',
      message = format('Vuoroa ei voi jatkaa klo %s jälkeen.', to_char(v_closes_at at time zone (select s.time_zone from app_private.settings s where s.id), 'FMHH24.MI'));
  end if;

  begin
    update app_private.bookings b
       set end_at = b.end_at + v_extra
     where b.id = p_booking_id;
  exception
    when exclusion_violation then
      raise exception using errcode = '23P01',
        message = case when p_minutes = 60
          then 'Seuraava tunti ei ole kokonaan vapaa, joten vuoroa ei voi jatkaa tunnilla.'
          else 'Seuraava puoli tuntia on jo varattu, joten vuoroa ei voi jatkaa.' end;
    when check_violation then
      raise exception using errcode = 'P0001', message = 'Vuoroa ei voi jatkaa enempää.';
  end;

  return query
    select b.id, b.device_id, b.apartment_number, b.start_at, b.end_at, true
    from app_private.bookings b where b.id = p_booking_id;
end;
$$;

revoke execute on function public.extend_booking(text, uuid, integer) from public;
grant execute on function public.extend_booking(text, uuid, integer) to anon, authenticated;

notify pgrst, 'reload schema';

commit;
