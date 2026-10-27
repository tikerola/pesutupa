-- =====================================================================
-- Pesutuvan varausjärjestelmä – tietokantamigraatio
--
-- Rakenne:
--   * Taulut ovat skeemassa app_private, jota Supabasen REST-rajapinta
--     ei julkaise ja johon anon/authenticated-rooleilla ei ole oikeuksia.
--   * Kaikilla tauluilla on RLS päällä ilman sallivia politiikkoja
--     (lisäsuoja, jos oikeuksia joskus vahingossa annettaisiin).
--   * Selain käyttää vain public-skeeman SECURITY DEFINER -funktioita
--     (login, logout, get_devices, list_bookings, my_bookings,
--     create_booking, extend_booking, cancel_booking). Jokainen niistä
--     tarkistaa istunnon ja säännöt itse.
--   * Päällekkäiset varaukset estetään exclusion constraintilla, joten
--     samanaikaisista yrityksistä vain yksi voi onnistua.
--
-- Aja tiedosto kerran Supabasen SQL Editorissa (tai `supabase db push`).
-- Aseta sen jälkeen yhteinen salasana:
--   select app_private.set_shared_password('oma-pitkä-salasana');
-- =====================================================================

begin;

create extension if not exists pgcrypto with schema extensions;
create extension if not exists btree_gist with schema extensions;

create schema if not exists app_private;
revoke all on schema app_private from public;
do $$
begin
  -- Supabasessa nämä roolit ovat aina olemassa.
  execute 'revoke all on schema app_private from anon, authenticated';
end $$;

-- ---------------------------------------------------------------------
-- Taulut
-- ---------------------------------------------------------------------

create table app_private.devices (
  id     smallint primary key,
  name   text    not null unique check (char_length(name) between 1 and 50),
  active boolean not null default true
);

insert into app_private.devices (id, name) values
  (1, 'Pesukone'),
  (2, 'Kuivuri')
on conflict (id) do nothing;

-- Yksirivinen asetustaulu.
create table app_private.settings (
  id                   boolean primary key default true constraint settings_singleton check (id),
  password_hash        text,
  session_days         integer not null default 30 check (session_days between 1 and 365),
  booking_horizon_days integer not null default 90 check (booking_horizon_days between 1 and 365)
);

insert into app_private.settings default values on conflict (id) do nothing;

-- Laitekohtaiset istunnot. Itse tunnistetta ei tallenneta, vain sen SHA-256-tiiviste.
create table app_private.sessions (
  id         uuid primary key default gen_random_uuid(),
  token_hash bytea       not null unique,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null
);

create index sessions_expires_at_idx on app_private.sessions (expires_at);

-- Epäonnistuneet kirjautumisyritykset arvaamisen hidastamiseksi.
create table app_private.login_failures (
  id           bigint generated always as identity primary key,
  client_key   text        not null,
  attempted_at timestamptz not null default now()
);

create index login_failures_attempted_at_idx on app_private.login_failures (attempted_at);

create table app_private.bookings (
  id               uuid primary key default gen_random_uuid(),
  device_id        smallint    not null references app_private.devices (id),
  apartment_number text        not null,
  start_at         timestamptz not null,
  end_at           timestamptz not null,
  created_at       timestamptz not null default now(),
  -- Istunto (= laite), jolla varaus tehtiin. Vain sama istunto voi perua tai jatkaa.
  session_id       uuid references app_private.sessions (id) on delete set null,

  constraint bookings_apartment_format check (
    apartment_number ~ '^[0-9A-ZÅÄÖåäö][0-9A-ZÅÄÖåäö -]{0,9}$' and apartment_number ~ '[0-9]'
  ),
  constraint bookings_positive_duration check (end_at > start_at),
  -- Varaukset ovat kokonaisia tunteja. Suomen aikavyöhykkeen siirtymät ovat
  -- tasatunteja, joten UTC-tasatunti on myös paikallinen tasatunti.
  constraint bookings_whole_hours check (
    extract(epoch from start_at) % 3600 = 0 and extract(epoch from end_at) % 3600 = 0
  ),
  -- Uusi varaus on enintään 3 h (tarkistetaan create_booking-funktiossa).
  -- Jatkaminen tunti kerrallaan voi pidentää vuoroa; tämä on vain järkevyysraja.
  constraint bookings_sanity_duration check (end_at - start_at <= interval '12 hours'),
  -- Ei päällekkäisiä varauksia samalle laitteelle. Atominen myös rinnakkaisissa pyynnöissä.
  constraint bookings_no_overlap exclude using gist (
    device_id with =,
    tstzrange(start_at, end_at, '[)') with &&
  )
);

create index bookings_session_id_idx on app_private.bookings (session_id);
create index bookings_device_apartment_idx on app_private.bookings (device_id, apartment_number, start_at);

alter table app_private.devices        enable row level security;
alter table app_private.settings       enable row level security;
alter table app_private.sessions       enable row level security;
alter table app_private.login_failures enable row level security;
alter table app_private.bookings       enable row level security;

-- ---------------------------------------------------------------------
-- Sisäiset apufunktiot (eivät näy REST-rajapinnassa)
-- ---------------------------------------------------------------------

-- Palauttaa voimassa olevan istunnon id:n tai nostaa virheen 28000.
create or replace function app_private.require_session(p_token text)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if p_token is not null and p_token ~ '^[0-9a-f]{64}$' then
    select s.id into v_id
    from app_private.sessions s
    where s.token_hash = extensions.digest(p_token, 'sha256')
      and s.expires_at > now();
  end if;

  if v_id is null then
    raise exception using
      errcode = '28000',
      message = 'Istunto on vanhentunut. Kirjaudu uudelleen.';
  end if;

  return v_id;
end;
$$;

-- Asiakkaan tunniste kirjautumisyritysten rajoittamiseen.
create or replace function app_private.client_key()
returns text
language sql
stable
set search_path = ''
as $$
  select coalesce(
    nullif(h ->> 'cf-connecting-ip', ''),
    nullif(btrim(split_part(coalesce(h ->> 'x-forwarded-for', ''), ',', 1)), ''),
    'unknown'
  )
  from (select nullif(current_setting('request.headers', true), '')::json as h) headers;
$$;

-- Ylläpitäjä asettaa tai vaihtaa yhteisen salasanan SQL Editorissa:
--   select app_private.set_shared_password('uusi-salasana');
--   select app_private.set_shared_password('uusi-salasana', true);  -- kirjaa myös kaikki laitteet ulos
create or replace function app_private.set_shared_password(p_password text, p_end_sessions boolean default false)
returns text
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_password is null or char_length(p_password) < 10 then
    raise exception 'Salasanan pitää olla vähintään 10 merkkiä pitkä.';
  end if;

  update app_private.settings
     set password_hash = extensions.crypt(p_password, extensions.gen_salt('bf', 10))
   where id;

  if p_end_sessions then
    update app_private.sessions set expires_at = now() where expires_at > now();
  end if;

  return 'Salasana asetettu.';
end;
$$;

-- ---------------------------------------------------------------------
-- Julkinen rajapinta (RPC)
-- ---------------------------------------------------------------------

-- Kirjautuminen yhteisellä salasanalla. Palauttaa JSONin eikä nosta virhettä,
-- jotta epäonnistunut yritys ehtii tallentua rajoitusta varten.
-- p_previous_token: laitteen aiempi (myös vanhentunut) tunniste. Jos se löytyy,
-- istunto uusitaan, jolloin laitteella tehdyt varaukset pysyvät omina.
create or replace function public.login(p_password text, p_previous_token text default null)
returns json
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_client         text := app_private.client_key();
  v_failures_here  integer;
  v_failures_total integer;
  v_hash           text;
  v_days           integer;
  v_token          text;
  v_expires        timestamptz;
  v_session        uuid;
begin
  delete from app_private.login_failures where attempted_at < now() - interval '1 day';

  select count(*) filter (where f.client_key = v_client), count(*)
    into v_failures_here, v_failures_total
  from app_private.login_failures f
  where f.attempted_at > now() - interval '15 minutes';

  if v_failures_here >= 10 or v_failures_total >= 200 then
    return json_build_object('ok', false, 'error', 'too_many_attempts');
  end if;

  select s.password_hash, s.session_days into v_hash, v_days
  from app_private.settings s
  where s.id;

  if v_hash is null then
    return json_build_object('ok', false, 'error', 'not_configured');
  end if;

  if p_password is null
     or char_length(p_password) > 200
     or extensions.crypt(p_password, v_hash) <> v_hash then
    insert into app_private.login_failures (client_key) values (v_client);
    return json_build_object('ok', false, 'error', 'invalid_password');
  end if;

  -- Siivous: pitkään vanhentuneet istunnot.
  delete from app_private.sessions where expires_at < now() - interval '90 days';

  v_token   := encode(extensions.gen_random_bytes(32), 'hex');
  v_expires := now() + make_interval(days => v_days);

  if p_previous_token is not null and p_previous_token ~ '^[0-9a-f]{64}$' then
    update app_private.sessions
       set token_hash = extensions.digest(v_token, 'sha256'),
           expires_at = v_expires
     where token_hash = extensions.digest(p_previous_token, 'sha256')
    returning id into v_session;
  end if;

  if v_session is null then
    insert into app_private.sessions (token_hash, expires_at)
    values (extensions.digest(v_token, 'sha256'), v_expires);
  end if;

  return json_build_object('ok', true, 'token', v_token, 'expires_at', v_expires);
end;
$$;

create or replace function public.logout(p_token text)
returns void
language sql
security definer
set search_path = ''
as $$
  delete from app_private.sessions
  where p_token ~ '^[0-9a-f]{64}$'
    and token_hash = extensions.digest(p_token, 'sha256');
$$;

create or replace function public.get_devices(p_token text)
returns table (id smallint, name text)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform app_private.require_session(p_token);
  return query
    select d.id, d.name from app_private.devices d where d.active order by d.id;
end;
$$;

create or replace function public.list_bookings(p_token text, p_from timestamptz, p_to timestamptz)
returns table (
  id               uuid,
  device_id        smallint,
  apartment_number text,
  start_at         timestamptz,
  end_at           timestamptz,
  is_own           boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_session uuid := app_private.require_session(p_token);
begin
  if p_from is null or p_to is null or p_to <= p_from or p_to - p_from > interval '15 days' then
    raise exception using errcode = '22023', message = 'Virheellinen aikaväli.';
  end if;

  return query
    select b.id, b.device_id, b.apartment_number, b.start_at, b.end_at,
           coalesce(b.session_id = v_session, false)
    from app_private.bookings b
    join app_private.devices d on d.id = b.device_id and d.active
    where b.start_at < p_to and b.end_at > p_from
    order by b.device_id, b.start_at;
end;
$$;

-- Tällä laitteella tehdyt varaukset, jotka eivät ole vielä päättyneet.
create or replace function public.my_bookings(p_token text)
returns table (
  id               uuid,
  device_id        smallint,
  apartment_number text,
  start_at         timestamptz,
  end_at           timestamptz,
  is_own           boolean
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
    select b.id, b.device_id, b.apartment_number, b.start_at, b.end_at, true
    from app_private.bookings b
    where b.session_id = v_session and b.end_at > now()
    order by b.start_at;
end;
$$;

create or replace function public.create_booking(
  p_token            text,
  p_device_id        integer,
  p_apartment_number text,
  p_start_at         timestamptz,
  p_hours            integer
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

  if p_hours is null or p_hours < 1 or p_hours > 3 then
    raise exception using errcode = 'P0001', message = 'Varauksen kesto voi olla 1–3 tuntia.';
  end if;

  if p_start_at is null or extract(epoch from p_start_at) % 3600 <> 0 then
    raise exception using errcode = 'P0001', message = 'Varauksen pitää alkaa tasatunnilta.';
  end if;

  if p_start_at < date_trunc('hour', now()) then
    raise exception using errcode = 'P0001', message = 'Mennyttä aikaa ei voi varata.';
  end if;

  select s.booking_horizon_days into v_horizon from app_private.settings s where s.id;
  if p_start_at > now() + make_interval(days => v_horizon) then
    raise exception using errcode = 'P0001',
      message = format('Varauksen voi tehdä enintään %s päivää etukäteen.', v_horizon);
  end if;

  v_end := p_start_at + make_interval(hours => p_hours);

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

-- Oman vuoron jatkaminen tunnilla. Sallittu vuoron viimeisen tunnin aikana,
-- jos seuraava tunti on vapaa (exclusion constraint varmistaa tämän atomisesti).
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
  v_session uuid := app_private.require_session(p_token);
  v_end     timestamptz;
begin
  select b.end_at into v_end
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

create or replace function public.cancel_booking(p_token text, p_booking_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session uuid := app_private.require_session(p_token);
begin
  delete from app_private.bookings b
  where b.id = p_booking_id
    and b.session_id = v_session
    and b.end_at > now();

  if not found then
    raise exception using errcode = 'P0001',
      message = 'Varausta ei voitu perua: sitä ei löytynyt, se on jo päättynyt tai se ei ole tällä laitteella tehty varaus.';
  end if;
end;
$$;

-- ---------------------------------------------------------------------
-- Käyttöoikeudet
-- ---------------------------------------------------------------------

revoke all on all tables in schema app_private from public;
revoke all on all sequences in schema app_private from public;
revoke execute on all functions in schema app_private from public;

do $$
declare
  f text;
begin
  execute 'revoke all on all tables in schema app_private from anon, authenticated';
  execute 'revoke all on all sequences in schema app_private from anon, authenticated';
  execute 'revoke execute on all functions in schema app_private from anon, authenticated';

  foreach f in array array[
    'public.login(text, text)',
    'public.logout(text)',
    'public.get_devices(text)',
    'public.list_bookings(text, timestamptz, timestamptz)',
    'public.my_bookings(text)',
    'public.create_booking(text, integer, text, timestamptz, integer)',
    'public.extend_booking(text, uuid)',
    'public.cancel_booking(text, uuid)'
  ] loop
    execute format('revoke execute on function %s from public', f);
    execute format('grant execute on function %s to anon, authenticated', f);
  end loop;
end $$;

commit;
