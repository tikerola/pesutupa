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

-- Aikapisteet: kuluva tasatunti ja huominen sama tunti.
select date_trunc('hour', now()) as h0,
       date_trunc('hour', now()) + interval '1 day' as base
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
select test.expect_error($$select * from public.create_booking(repeat('a', 64), 1, '9', date_trunc('hour', now()) + interval '1 day', 1)$$, '28000', 'arvattu tunniste ei kelpaa varaukseen');
select test.ok((select count(*) from public.get_devices(:'tok_a')) = 2, 'laitteet: Pesukone ja Kuivuri');

\echo '--- Varauksen kesto ja ajankohta ---'
select test.ok((select count(*) from public.create_booking(:'tok_a', 1, '9', :'base'::timestamptz, 3)) = 1, '3 tunnin varaus onnistuu');
select test.expect_error(format('select * from public.create_booking(%L, 2, %L, %L, 4)', :'tok_a', '9', :'base'), 'P0001', '4 tunnin varaus hylätään');
select test.expect_error(format('select * from public.create_booking(%L, 2, %L, %L, 0)', :'tok_a', '9', :'base'), 'P0001', '0 tunnin varaus hylätään');
select test.expect_error(format('select * from public.create_booking(%L, 2, %L, %L, -1)', :'tok_a', '9', :'base'), 'P0001', 'negatiivinen kesto hylätään');
select test.expect_error(format('select * from public.create_booking(%L, 2, %L, %L::timestamptz + interval ''30 minutes'', 1)', :'tok_a', '9', :'base'), 'P0001', 'muu kuin tasatunti hylätään');
select test.expect_error(format('select * from public.create_booking(%L, 2, %L, %L::timestamptz - interval ''1 hour'', 1)', :'tok_a', '9', :'h0'), 'P0001', 'mennyt aika hylätään');
select test.expect_error(format('select * from public.create_booking(%L, 2, %L, now() + interval ''200 days'', 1)', :'tok_a', '9'), 'P0001', 'liian kaukainen aika hylätään');
select test.expect_error(format('select * from public.create_booking(%L, 99, %L, %L, 1)', :'tok_a', '9', :'base'), 'P0001', 'tuntematon laite hylätään');
select test.expect_error(format('select * from public.create_booking(%L, 2, %L, %L, 1)', :'tok_a', 'abc', :'base'), 'P0001', 'asunnon numero ilman numeroa hylätään');
select test.expect_error(format('select * from public.create_booking(%L, 2, %L, %L, 1)', :'tok_a', '', :'base'), 'P0001', 'tyhjä asunnon numero hylätään');
select test.ok((select apartment_number from public.create_booking(:'tok_b', 2, '  a   12 ', :'base'::timestamptz + interval '6 hours', 1)) = 'A 12', 'asunnon numero normalisoidaan (A 12)');

\echo '--- Päällekkäisyydet ---'
select test.expect_error(format('select * from public.create_booking(%L, 1, %L, %L::timestamptz + interval ''1 hour'', 1)', :'tok_b', '12', :'base'), '23P01', 'päällekkäinen varaus samalle laitteelle hylätään');
select test.expect_error(format('select * from public.create_booking(%L, 1, %L, %L::timestamptz - interval ''1 hour'', 2)', :'tok_b', '12', :'base'), '23P01', 'osittain päällekkäinen varaus hylätään');
select test.ok((select count(*) from public.create_booking(:'tok_b', 2, '12', :'base'::timestamptz + interval '1 hour', 1)) = 1, 'sama aika toiselle laitteelle onnistuu');
select test.ok((select count(*) from public.create_booking(:'tok_b', 1, '12', :'base'::timestamptz + interval '3 hours', 1)) = 1, 'heti perään alkava varaus onnistuu (ei päällekkäinen)');

\echo '--- Kolmen tunnin raja vierekkäisillä varauksilla ---'
select test.expect_error(format('select * from public.create_booking(%L, 1, %L, %L::timestamptz - interval ''1 hour'', 1)', :'tok_a', '9', :'base'), 'P0001', 'saman asunnon vierekkäinen lisätunti (yht. 4 h) hylätään');

\echo '--- Listaus ---'
select test.ok((select count(*) from public.list_bookings(:'tok_a', :'base'::timestamptz - interval '1 day', :'base'::timestamptz + interval '1 day')) = 4, 'kaikki varaukset näkyvät kaikille');
select test.ok((select count(*) from public.list_bookings(:'tok_a', :'base'::timestamptz - interval '1 day', :'base'::timestamptz + interval '1 day') where is_own) = 1, 'omat varaukset tunnistetaan (A)');
select test.ok((select count(*) from public.my_bookings(:'tok_b')) = 3, 'omat varaukset -lista (B)');
select test.expect_error(format('select * from public.list_bookings(%L, now(), now() + interval ''30 days'')', :'tok_a'), '22023', 'liian pitkä listausväli hylätään');

\echo '--- Peruminen ---'
select id as a_booking from public.my_bookings(:'tok_a') limit 1 \gset
select test.expect_error(format('select public.cancel_booking(%L, %L)', :'tok_b', :'a_booking'), 'P0001', 'toisen laitteen varausta ei voi perua');
select test.expect_error(format('select public.cancel_booking(%L, %L)', repeat('0', 64), :'a_booking'), '28000', 'varaus-ID ilman istuntoa ei riitä perumiseen');
select test.ok((select count(*) from public.list_bookings(:'tok_a', :'base'::timestamptz - interval '1 day', :'base'::timestamptz + interval '1 day') where id = :'a_booking') = 1, 'varaus on yhä olemassa epäonnistuneen perumisen jälkeen');
select public.cancel_booking(:'tok_a', :'a_booking');
select test.ok((select count(*) from public.my_bookings(:'tok_a')) = 0, 'oma varaus peruttu');
select test.ok((select count(*) from public.create_booking(:'tok_b', 1, '12', :'base'::timestamptz + interval '1 hour', 2)) = 1, 'peruttu aika vapautuu muille');

\echo '--- Vuoron jatkaminen ---'
select id as a_now from public.create_booking(:'tok_a', 1, '9', :'h0'::timestamptz, 1) \gset
select test.expect_error(format('select * from public.extend_booking(%L, %L)', :'tok_b', :'a_now'), 'P0001', 'toisen laitteen vuoroa ei voi jatkaa');
select test.ok((select end_at from public.extend_booking(:'tok_a', :'a_now')) = :'h0'::timestamptz + interval '2 hours', 'vuoron jatkaminen tunnilla onnistuu, kun seuraava tunti on vapaa');
select test.expect_error(format('select * from public.extend_booking(%L, %L)', :'tok_a', :'a_now'), 'P0001', 'jatkaminen ei onnistu ennen vuoron viimeistä tuntia');
select id as a_now2 from public.create_booking(:'tok_a', 2, '9', :'h0'::timestamptz, 1) \gset
select test.ok((select count(*) from public.create_booking(:'tok_b', 2, '12', :'h0'::timestamptz + interval '1 hour', 1)) = 1, 'toinen asunto varaa seuraavan tunnin');
select test.expect_error(format('select * from public.extend_booking(%L, %L)', :'tok_a', :'a_now2'), '23P01', 'jatkaminen estyy, jos seuraava tunti on varattu');

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
drop schema test cascade;
\echo '=== Kaikki tietokantatestit läpäisty ==='
