-- =====================================================================
-- Tietokannan sääntö- ja käyttöoikeustestit.
-- Ajetaan PAIKALLISEEN testikantaan (tests/local/docker-compose.yml):
--   docker compose -f tests/local/docker-compose.yml exec -T db \
--     psql -U postgres -v ON_ERROR_STOP=1 -f /tests/booking_rules_test.sql
-- Testi tyhjentää varaukset ja istunnot – älä aja tuotantokantaan.
-- Odottaa salasanaa 'testisalasana-123' (tests/local/20_seed_password.sql).
-- =====================================================================
\set ON_ERROR_STOP on
\set QUIET on
\pset tuples_only on
\o /dev/null
set client_min_messages = notice;

reset role;
delete from app_private.bookings;
delete from app_private.sessions;
delete from app_private.login_failures;
-- Kellonaikaan sidotut testit (esim. vuoron jatkaminen nyt) toimivat mihin
-- vuorokauden aikaan tahansa; aukioloajat testataan erikseen alempana.
update app_private.settings set open_hour = 0, close_hour = 24;

drop schema if exists test cascade;
create schema test;
grant usage on schema test to anon;

create function test.expect_error(p_sql text, p_state text, p_label text)
returns void language plpgsql as $$
begin
  begin
    execute p_sql;
  exception when others then
    if sqlstate = p_state then
      raise notice 'OK    %', p_label;
      return;
    end if;
    raise exception using errcode = 'TF001',
      message = format('FAIL  %s: odotettiin virhettä %s, saatiin %s (%s)', p_label, p_state, sqlstate, sqlerrm);
  end;
  raise exception using errcode = 'TF001',
    message = format('FAIL  %s: odotettiin virhettä %s, mutta kutsu onnistui', p_label, p_state);
end $$;

create function test.ok(p_cond boolean, p_label text)
returns void language plpgsql as $$
begin
  if p_cond is distinct from true then
    raise exception using errcode = 'TF001', message = format('FAIL  %s', p_label);
  end if;
  raise notice 'OK    %', p_label;
end $$;

grant execute on all functions in schema test to anon;

-- Aikapisteet: kuluva tasatunti, kuluvan puolen tunnin jakson alku ja huomenna klo 10 Suomen aikaa.
select date_trunc('hour', now()) as h0,
       to_timestamp(floor(extract(epoch from now()) / 1800) * 1800) as s0,
       ((now() at time zone 'Europe/Helsinki')::date + 1 + time '10:00') at time zone 'Europe/Helsinki' as base
\gset

-- Kaikki testit ajetaan selaimen roolina (anon).
set role anon;

\echo '--- Käyttöoikeudet ---'
select test.expect_error('select * from app_private.bookings', '42501', 'anon ei voi lukea varaustaulua suoraan');
select test.expect_error('select * from app_private.sessions', '42501', 'anon ei voi lukea istuntoja');
select test.expect_error('select * from app_private.settings', '42501', 'anon ei voi lukea salasanatiivistettä');
select test.expect_error($$insert into app_private.bookings (device_id, apartment_number, start_at, end_at) values (1, '9', now(), now())$$, '42501', 'anon ei voi lisätä varausta suoraan');
select test.expect_error('delete from app_private.bookings', '42501', 'anon ei voi poistaa varauksia suoraan');
select test.expect_error($$select app_private.set_shared_password('murtautuja-123')$$, '42501', 'anon ei voi vaihtaa salasanaa');
select test.expect_error($$select app_private.require_session('x')$$, '42501', 'anon ei voi kutsua sisäisiä funktioita');

\echo '--- Kirjautuminen ja istunnot ---'
select test.ok((public.login('väärä-salasana') ->> 'ok')::boolean = false, 'väärä salasana hylätään');
select test.ok((public.login(null) ->> 'ok')::boolean = false, 'tyhjä salasana hylätään');
select public.login('testisalasana-123') ->> 'token' as tok_a \gset
select public.login('testisalasana-123') ->> 'token' as tok_b \gset
select test.ok(:'tok_a' ~ '^[0-9a-f]{64}$', 'oikea salasana antaa istuntotunnisteen');
select test.ok(:'tok_a' <> :'tok_b', 'jokainen kirjautuminen saa oman tunnisteen');
select test.expect_error($$select * from public.list_bookings('abc', now(), now() + interval '1 day')$$, '28000', 'virheellinen tunniste hylätään');
select test.expect_error($$select * from public.list_bookings(null, now(), now() + interval '1 day')$$, '28000', 'puuttuva tunniste hylätään');
select test.expect_error($$select * from public.create_booking(repeat('a', 64), 1, '9', date_trunc('hour', now()) + interval '1 day', 60)$$, '28000', 'arvattu tunniste ei kelpaa varaukseen');
select test.ok((select count(*) from public.get_devices(:'tok_a')) = 2, 'laitteet: Pesukone ja Kuivuri');

\echo '--- Varauksen kesto ja ajankohta ---'
select test.ok((select count(*) from public.create_booking(:'tok_a', 1, '9', :'base'::timestamptz, 180)) = 1, '3 tunnin varaus onnistuu');
select test.expect_error(format('select * from public.create_booking(%L, 2, %L, %L, 240)', :'tok_a', '9', :'base'), 'P0001', '4 tunnin varaus hylätään');
select test.expect_error(format('select * from public.create_booking(%L, 2, %L, %L, 0)', :'tok_a', '9', :'base'), 'P0001', '0 tunnin varaus hylätään');
select test.expect_error(format('select * from public.create_booking(%L, 2, %L, %L, -60)', :'tok_a', '9', :'base'), 'P0001', 'negatiivinen kesto hylätään');
select test.expect_error(format('select * from public.create_booking(%L, 2, %L, %L::timestamptz + interval ''15 minutes'', 60)', :'tok_a', '9', :'base'), 'P0001', 'muu kuin tasa- tai puolitunti hylätään');
select test.expect_error(format('select * from public.create_booking(%L, 2, %L, %L::timestamptz - interval ''1 hour'', 60)', :'tok_a', '9', :'h0'), 'P0001', 'mennyt aika hylätään');
select test.expect_error(format('select * from public.create_booking(%L, 2, %L, now() + interval ''200 days'', 60)', :'tok_a', '9'), 'P0001', 'liian kaukainen aika hylätään');
select test.expect_error(format('select * from public.create_booking(%L, 99, %L, %L, 60)', :'tok_a', '9', :'base'), 'P0001', 'tuntematon laite hylätään');
select test.expect_error(format('select * from public.create_booking(%L, 2, %L, %L, 60)', :'tok_a', 'abc', :'base'), 'P0001', 'asunnon numero ilman numeroa hylätään');
select test.expect_error(format('select * from public.create_booking(%L, 2, %L, %L, 60)', :'tok_a', '', :'base'), 'P0001', 'tyhjä asunnon numero hylätään');
select test.ok((select apartment_number from public.create_booking(:'tok_b', 2, '  a   12 ', :'base'::timestamptz + interval '6 hours', 60)) = 'A 12', 'asunnon numero normalisoidaan (A 12)');
select test.ok((select end_at - start_at from public.create_booking(:'tok_b', 2, '30', :'base'::timestamptz + interval '8 hours 30 minutes', 30)) = interval '30 minutes', '30 minuutin varaus puolelta tunnilta onnistuu');
select test.ok((select end_at from public.create_booking(:'tok_b', 1, '30', :'base'::timestamptz + interval '8 hours 30 minutes', 90)) = :'base'::timestamptz + interval '10 hours', '1,5 tunnin varaus (8.30–10.00) onnistuu');
select test.expect_error(format('select * from public.create_booking(%L, 2, %L, %L, 45)', :'tok_a', '9', :'base'), 'P0001', '45 minuutin kesto hylätään');
select test.expect_error(format('select * from public.create_booking(%L, 2, %L, %L, 210)', :'tok_a', '9', :'base'), 'P0001', '3,5 tunnin varaus hylätään');
select public.cancel_booking(:'tok_b', b.id) from public.my_bookings(:'tok_b') b where b.apartment_number = '30';

\echo '--- Päällekkäisyydet ---'
select test.expect_error(format('select * from public.create_booking(%L, 1, %L, %L::timestamptz + interval ''1 hour'', 60)', :'tok_b', '12', :'base'), '23P01', 'päällekkäinen varaus samalle laitteelle hylätään');
select test.expect_error(format('select * from public.create_booking(%L, 1, %L, %L::timestamptz - interval ''1 hour'', 120)', :'tok_b', '12', :'base'), '23P01', 'osittain päällekkäinen varaus hylätään');
select test.ok((select count(*) from public.create_booking(:'tok_b', 2, '12', :'base'::timestamptz + interval '1 hour', 60)) = 1, 'sama aika toiselle laitteelle onnistuu');
select test.ok((select count(*) from public.create_booking(:'tok_b', 1, '12', :'base'::timestamptz + interval '3 hours', 60)) = 1, 'heti perään alkava varaus onnistuu (ei päällekkäinen)');

\echo '--- Kolmen tunnin raja vierekkäisillä varauksilla ---'
select test.expect_error(format('select * from public.create_booking(%L, 1, %L, %L::timestamptz - interval ''1 hour'', 60)', :'tok_a', '9', :'base'), 'P0001', 'saman asunnon vierekkäinen lisätunti (yht. 4 h) hylätään');

\echo '--- Listaus ---'
select test.ok((select count(*) from public.list_bookings(:'tok_a', :'base'::timestamptz - interval '1 day', :'base'::timestamptz + interval '1 day')) = 4, 'kaikki varaukset näkyvät kaikille');
select test.ok((select count(*) from public.list_bookings(:'tok_a', :'base'::timestamptz - interval '1 day', :'base'::timestamptz + interval '1 day') where is_own) = 1, 'omat varaukset tunnistetaan (A)');
select test.ok((select count(*) from public.my_bookings(:'tok_b')) = 3, 'omat varaukset -lista (B)');
select test.expect_error(format('select * from public.list_bookings(%L, now(), now() + interval ''30 days'')', :'tok_a'), '22023', 'liian pitkä listausväli hylätään');

\echo '--- Poistaminen ---'
select id as a_booking from public.my_bookings(:'tok_a') limit 1 \gset
select test.expect_error(format('select public.cancel_booking(%L, %L)', repeat('0', 64), :'a_booking'), '28000', 'varaus-ID ilman istuntoa ei riitä poistoon');
select test.ok((select count(*) from public.list_bookings(:'tok_a', :'base'::timestamptz - interval '1 day', :'base'::timestamptz + interval '1 day') where id = :'a_booking') = 1, 'varaus on yhä olemassa epäonnistuneen poiston jälkeen');
select public.cancel_booking(:'tok_b', :'a_booking');
select test.ok((select count(*) from public.my_bookings(:'tok_a')) = 0, 'toisen laitteen varauksen voi poistaa');
select test.expect_error(format('select public.cancel_booking(%L, %L)', :'tok_a', :'a_booking'), 'P0001', 'jo poistettua varausta ei voi poistaa uudelleen');
select test.ok((select count(*) from public.create_booking(:'tok_b', 1, '12', :'base'::timestamptz + interval '1 hour', 120)) = 1, 'poistettu aika vapautuu muille');
reset role;
insert into app_private.bookings (device_id, apartment_number, start_at, end_at)
values (2, '77', :'h0'::timestamptz - interval '3 hours', :'h0'::timestamptz - interval '2 hours')
returning id as past_booking \gset
set role anon;
select test.expect_error(format('select public.cancel_booking(%L, %L)', :'tok_a', :'past_booking'), 'P0001', 'päättynyttä varausta ei voi poistaa');

\echo '--- Vuoron jatkaminen ---'
select id as a_now from public.create_booking(:'tok_a', 1, '9', :'s0'::timestamptz, 60) \gset
select test.expect_error(format('select * from public.extend_booking(%L, %L)', :'tok_b', :'a_now'), 'P0001', 'toisen laitteen vuoroa ei voi jatkaa');
select test.ok((select end_at from public.extend_booking(:'tok_a', :'a_now')) = :'s0'::timestamptz + interval '2 hours', 'vuoron jatkaminen tunnilla onnistuu, kun seuraava tunti on vapaa');
select test.expect_error(format('select * from public.extend_booking(%L, %L)', :'tok_a', :'a_now'), 'P0001', 'jatkaminen ei onnistu ennen vuoron viimeistä tuntia');
select id as a_now2 from public.create_booking(:'tok_a', 2, '9', :'s0'::timestamptz, 60) \gset
select test.ok((select count(*) from public.create_booking(:'tok_b', 2, '12', :'s0'::timestamptz + interval '1 hour', 60)) = 1, 'toinen asunto varaa seuraavan tunnin');
select test.expect_error(format('select * from public.extend_booking(%L, %L)', :'tok_a', :'a_now2'), '23P01', 'jatkaminen estyy, jos seuraava tunti on varattu');

\echo '--- Varattava aika klo 8–22 ---'
reset role;
update app_private.settings set open_hour = 8, close_hour = 22;
set role anon;
select test.ok((select open_hour = 8 and close_hour = 22 from public.get_booking_hours(:'tok_a')), 'aukioloajat luettavissa (8–22)');
select test.expect_error(format('select * from public.create_booking(%L, 2, %L, %L::timestamptz - interval ''2 hours 30 minutes'', 60)', :'tok_b', '40', :'base'), 'P0001', 'klo 7.30 alkava varaus hylätään');
select test.ok((select count(*) from public.create_booking(:'tok_b', 2, '40', :'base'::timestamptz - interval '2 hours', 60)) = 1, 'klo 8.00 alkava varaus onnistuu');
select test.ok((select count(*) from public.create_booking(:'tok_b', 2, '41', :'base'::timestamptz + interval '10 hours 30 minutes', 90)) = 1, 'klo 22.00 päättyvä varaus onnistuu');
select test.expect_error(format('select * from public.create_booking(%L, 1, %L, %L::timestamptz + interval ''11 hours'', 90)', :'tok_b', '40', :'base'), 'P0001', 'klo 22 jälkeen päättyvä varaus hylätään');
select test.expect_error(format('select * from public.create_booking(%L, 1, %L, %L::timestamptz + interval ''12 hours'', 60)', :'tok_b', '40', :'base'), 'P0001', 'klo 22 alkava varaus hylätään');
select public.cancel_booking(:'tok_b', b.id) from public.my_bookings(:'tok_b') b where b.apartment_number in ('40', '41');
select test.expect_error(format('select * from public.get_booking_hours(%L)', repeat('0', 64)), '28000', 'aukioloajat eivät näy ilman istuntoa');
reset role;
update app_private.settings set open_hour = 0, close_hour = 24;
set role anon;

\echo '--- Uloskirjautuminen ja istunnon uusiminen ---'
select public.login('testisalasana-123', :'tok_a') ->> 'token' as tok_a2 \gset
select test.ok((select count(*) from public.my_bookings(:'tok_a2')) = 2, 'uusittu istunto säilyttää omat varaukset');
select test.expect_error(format('select * from public.my_bookings(%L)', :'tok_a'), '28000', 'vanha tunniste lakkaa toimimasta uusimisen jälkeen');
select public.logout(:'tok_b');
select test.expect_error(format('select * from public.my_bookings(%L)', :'tok_b'), '28000', 'uloskirjautunut tunniste ei toimi');

\echo '--- Kirjautumisyritysten rajoitus ---'
select count(*) from (select public.login('väärin-' || g) from generate_series(1, 10) g) x \gset
select test.ok((public.login('testisalasana-123') ->> 'error') = 'too_many_attempts', 'liian monen virheen jälkeen kirjautuminen estetään hetkeksi');

reset role;
delete from app_private.bookings;
delete from app_private.sessions;
delete from app_private.login_failures;
update app_private.settings set open_hour = 8, close_hour = 22;
drop schema test cascade;
\echo '=== Kaikki tietokantatestit läpäisty ==='
