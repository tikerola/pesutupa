-- Paikallista testausta varten: jäljittelee Supabasen valmiita rooleja ja skeemoja.
-- ÄLÄ aja tätä oikeassa Supabase-projektissa.
create role anon nologin noinherit;
create role authenticated nologin noinherit;
create role service_role nologin noinherit bypassrls;
create role authenticator noinherit login password 'authenticator';
grant anon, authenticated, service_role to authenticator;

create schema extensions;
grant usage on schema extensions to anon, authenticated, service_role;
grant usage on schema public to anon, authenticated, service_role;

-- Merkitsee kannan paikalliseksi testikannaksi. Tietokantatesti
-- (tests/db/booking_rules_test.sql) ei suostu toimimaan ilman tätä.
alter database postgres set pesutupa.test_database = 'on';
