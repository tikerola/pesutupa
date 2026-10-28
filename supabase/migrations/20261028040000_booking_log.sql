-- =====================================================================
-- Muutosloki (päätetty 28.10.2026): varausten luonnit, jatkot ja poistot
-- kirjataan, ja loki näkyy kaikille kirjautuneille sovelluksessa.
--
-- - Tekijä on laite (istunto), ei henkilö: yhteisellä salasanalla
--   henkilöä ei voi tunnistaa. Laite näytetään lyhyenä tunnisteena,
--   josta istuntoa ei voi päätellä.
-- - Rivit säilytetään 90 päivää.
-- - Olemassa oleviin varauksiin ei kosketa. Ne kirjataan lokiin
--   "Varaus tehty" -riveinä alkuperäisellä tekoajalla ja tekijälaitteella.
--
-- Aja tämä Supabasen SQL Editorissa aiempien migraatioiden jälkeen.
-- =====================================================================

begin;

create table app_private.booking_log (
  id               bigint generated always as identity primary key,
  logged_at        timestamptz not null default now(),
  action           text        not null check (action in ('created', 'extended', 'deleted')),
  booking_id       uuid        not null,
  device_id        smallint    not null,
  apartment_number text        not null,
  start_at         timestamptz not null,
  end_at           timestamptz not null,
  -- Jatkossa vuoron aiempi päättymisaika.
  previous_end_at  timestamptz,
  -- Laite, joka teki muutoksen (null = ylläpito SQL Editorissa).
  actor_session    uuid,
  -- Laite, jolla varaus alun perin tehtiin.
  owner_session    uuid
);
create index booking_log_logged_at_idx on app_private.booking_log (logged_at);

alter table app_private.booking_log enable row level security;
revoke all on app_private.booking_log from public;
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke all on app_private.booking_log from anon, authenticated';
  end if;
end $$;

-- Kirjaa muutoksen. Poistossa tekijä tulee asetuksesta, jonka
-- cancel_booking asettaa transaktion ajaksi.
create function app_private.log_booking_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid;
begin
  if tg_op = 'INSERT' then
    insert into app_private.booking_log (action, booking_id, device_id, apartment_number, start_at, end_at, actor_session, owner_session)
    values ('created', new.id, new.device_id, new.apartment_number, new.start_at, new.end_at, new.session_id, new.session_id);

    -- Siivous: yli 90 päivää vanhat rivit.
    delete from app_private.booking_log where logged_at < now() - interval '90 days';
    return new;

  elsif tg_op = 'UPDATE' then
    -- Uloskirjautuminen tyhjentää varauksen istunnon; sitä ei kirjata.
    if new.end_at is distinct from old.end_at or new.start_at is distinct from old.start_at then
      insert into app_private.booking_log (action, booking_id, device_id, apartment_number, start_at, end_at, previous_end_at, actor_session, owner_session)
      values ('extended', new.id, new.device_id, new.apartment_number, new.start_at, new.end_at, old.end_at, new.session_id, new.session_id);
    end if;
    return new;

  else
    v_actor := nullif(current_setting('pesutupa.actor_session', true), '')::uuid;
    insert into app_private.booking_log (action, booking_id, device_id, apartment_number, start_at, end_at, actor_session, owner_session)
    values ('deleted', old.id, old.device_id, old.apartment_number, old.start_at, old.end_at, v_actor, old.session_id);
    return old;
  end if;
end;
$$;

revoke execute on function app_private.log_booking_change() from public;

-- Jo olemassa olevat varaukset lokiin (luettu vain, varauksiin ei kosketa).
insert into app_private.booking_log (logged_at, action, booking_id, device_id, apartment_number, start_at, end_at, actor_session, owner_session)
select b.created_at, 'created', b.id, b.device_id, b.apartment_number, b.start_at, b.end_at, b.session_id, b.session_id
from app_private.bookings b
where b.created_at > now() - interval '90 days'
  and not exists (select 1 from app_private.booking_log l where l.booking_id = b.id and l.action = 'created')
order by b.created_at;

create trigger bookings_log
after insert or update or delete on app_private.bookings
for each row execute function app_private.log_booking_change();

-- Poisto kertoo lokille, mikä laite poisti varauksen.
create or replace function public.cancel_booking(p_token text, p_booking_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session uuid := app_private.require_session(p_token);
begin
  perform set_config('pesutupa.actor_session', v_session::text, true);

  delete from app_private.bookings b
  where b.id = p_booking_id
    and b.end_at > now();

  if not found then
    raise exception using errcode = 'P0001',
      message = 'Varausta ei voitu poistaa: se on jo poistettu tai päättynyt.';
  end if;
end;
$$;

-- Lyhyt laitetunniste, esim. "7F3A". Ei paljasta istuntoa eikä tunnistetta.
create function app_private.device_label(p_session uuid)
returns text
language sql
immutable
set search_path = ''
as $$
  select case when p_session is null then null
              else upper(substr(encode(extensions.digest('pesutupa-laite:' || p_session::text, 'sha256'), 'hex'), 1, 4)) end;
$$;
revoke execute on function app_private.device_label(uuid) from public;

-- Muutosloki uusin ensin, enintään 200 riviä.
create function public.list_booking_log(p_token text)
returns table (
  logged_at        timestamptz,
  action           text,
  device_id        smallint,
  apartment_number text,
  start_at         timestamptz,
  end_at           timestamptz,
  previous_end_at  timestamptz,
  actor            text,
  actor_is_me      boolean,
  actor_is_owner   boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_session uuid := app_private.require_session(p_token);
begin
  return query
    select l.logged_at, l.action, l.device_id, l.apartment_number, l.start_at, l.end_at, l.previous_end_at,
           coalesce(app_private.device_label(l.actor_session), 'ylläpito'),
           coalesce(l.actor_session = v_session, false),
           coalesce(l.actor_session = l.owner_session, false)
    from app_private.booking_log l
    where l.logged_at > now() - interval '90 days'
    order by l.logged_at desc, l.id desc
    limit 200;
end;
$$;

revoke execute on function public.list_booking_log(text) from public;
grant execute on function public.list_booking_log(text) to anon, authenticated;

notify pgrst, 'reload schema';

commit;
