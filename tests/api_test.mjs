// REST-rajapinnan testit: rinnakkaiset varausyritykset ja käyttöoikeudet.
//
// Paikallisesti (tests/local/docker-compose.yml käynnissä) ajetaan kaikki testit:
//   node tests/api_test.mjs
//
// Tuotantoa (oikeaa Supabase-projektia) vastaan ajetaan vain tarkistukset, jotka
// eivät kirjoita kantaan mitään: ei kirjautumista, ei varauksia, ei
// salasanayrityksiä. Salasanaa ei tarvita.
//   PESUTUPA_SUPABASE_URL=https://xxxx.supabase.co //   PESUTUPA_API_KEY=<anon- tai publishable-avain> //   node tests/api_test.mjs

import { randomBytes } from 'node:crypto';

const SUPABASE_URL = process.env.PESUTUPA_SUPABASE_URL;
const REST = SUPABASE_URL ? `${SUPABASE_URL.replace(/\/$/, '')}/rest/v1` : 'http://localhost:54321';
const KEY = process.env.PESUTUPA_API_KEY || '';
const PASSWORD = 'testisalasana-123'; // vain paikallinen testikanta
const PARALLEL = 20;
const LOCAL = ['localhost', '127.0.0.1', '[::1]'].includes(new URL(REST).hostname);

let failures = 0;
function check(cond, label) {
  console.log(`${cond ? 'OK  ' : 'FAIL'}  ${label}`);
  if (!cond) failures++;
}

function headers() {
  const h = { 'Content-Type': 'application/json' };
  if (KEY) {
    h.apikey = KEY;
    if (KEY.startsWith('eyJ')) h.Authorization = `Bearer ${KEY}`;
  }
  return h;
}

async function rpc(name, body) {
  const res = await fetch(`${REST}/rpc/${name}`, { method: 'POST', headers: headers(), body: JSON.stringify(body) });
  const text = await res.text();
  let data = null;
  try { data = text ? JSON.parse(text) : null; } catch { data = text; }
  return { status: res.status, ok: res.ok, data };
}

console.log(LOCAL ? `Paikallinen testikanta (${REST}): kaikki testit\n` : `Tuotanto (${REST}): vain lukevat tarkistukset, kantaan ei kirjoiteta\n`);

// --- Käyttöoikeudet (eivät kirjoita mitään) ---
for (const table of ['bookings', 'sessions', 'settings', 'devices', 'login_failures']) {
  const res = await fetch(`${REST}/${table}?select=*`, { headers: headers() });
  check(!res.ok, `taulu ${table} ei ole luettavissa suoraan (HTTP ${res.status})`);
}
{
  // Funktio ei näy rajapinnassa lainkaan, joten kutsu ei voi muuttaa mitään.
  const r = await rpc('set_shared_password', { p_password: 'x' });
  check(!r.ok && r.status === 404, `salasanan vaihto ei ole kutsuttavissa (HTTP ${r.status})`);
}
{
  // Satunnainen, olematon istuntotunniste: istuntotarkistus hylkää kutsun ennen
  // kuin mitään kirjoitetaan.
  const fake = randomBytes(32).toString('hex');
  const now = new Date();
  const later = new Date(now.getTime() + 864e5);
  const far = new Date(now.getTime() + 60 * 864e5);
  far.setUTCHours(9, 0, 0, 0);
  const calls = [
    ['list_bookings', { p_token: fake, p_from: now.toISOString(), p_to: later.toISOString() }, 'varaukset eivät näy'],
    ['my_bookings', { p_token: fake }, 'omat varaukset eivät näy'],
    ['get_devices', { p_token: fake }, 'laitteet eivät näy'],
    ['get_booking_hours', { p_token: fake }, 'aukioloajat eivät näy'],
    ['create_booking', { p_token: fake, p_device_id: 1, p_apartment_number: '1', p_start_at: far.toISOString(), p_minutes: 60 }, 'varausta ei voi tehdä'],
    ['extend_booking', { p_token: fake, p_booking_id: '00000000-0000-0000-0000-000000000000' }, 'varausta ei voi jatkaa'],
    ['cancel_booking', { p_token: fake, p_booking_id: '00000000-0000-0000-0000-000000000000' }, 'varausta ei voi poistaa'],
  ];
  for (const [name, body, label] of calls) {
    const r = await rpc(name, body);
    check(!r.ok && r.data?.code === '28000', `${label} ilman kirjautumista (${name}: HTTP ${r.status})`);
  }
}

if (!LOCAL) {
  console.log(failures ? `\n${failures} testiä epäonnistui` : '\nKaikki tuotannon tarkistukset läpäisty');
  console.log('Kirjautuminen, varaukset ja rinnakkaisuus testataan vain paikallisesti.');
  process.exit(failures ? 1 : 0);
}

// ===== Tästä eteenpäin vain paikallinen testikanta: kirjoittaa kantaan. =====

// --- Kirjautuminen ---
const wrong = await rpc('login', { p_password: 'väärä-salasana' });
check(wrong.ok && wrong.data?.ok === false, 'väärä salasana hylätään');
const a = await rpc('login', { p_password: PASSWORD });
const b = await rpc('login', { p_password: PASSWORD });
check(a.data?.ok === true && b.data?.ok === true, 'kaksi laitetta kirjautuu sisään');
if (!a.data?.ok || !b.data?.ok) {
  console.log('Kirjautuminen epäonnistui, testejä ei voi jatkaa:', a.data, b.data);
  process.exit(1);
}
const tokA = a.data.token;
const tokB = b.data.token;

// --- Rinnakkaiset varausyritykset samaan aikaan ---
const start = new Date();
start.setUTCDate(start.getUTCDate() + 55 + Math.floor(Math.random() * 30));
// 6–15 UTC = noin 8–19 Suomen aikaa, joten 2 tunnin varaus mahtuu klo 8–22 väliin.
start.setUTCHours(6 + Math.floor(Math.random() * 10), Math.random() < 0.5 ? 0 : 30, 0, 0);

const attempts = await Promise.all(
  Array.from({ length: PARALLEL }, (_, i) =>
    rpc('create_booking', {
      p_token: i % 2 ? tokA : tokB,
      p_device_id: 1,
      p_apartment_number: String(100 + i),
      p_start_at: start.toISOString(),
      p_minutes: 120,
    }),
  ),
);
const successes = attempts.filter((r) => r.ok);
const conflicts = attempts.filter((r) => r.data?.code === '23P01');
check(successes.length === 1, `${PARALLEL} rinnakkaisesta yrityksestä täsmälleen yksi onnistuu (onnistui ${successes.length})`);
check(conflicts.length === PARALLEL - 1, `muut saavat päällekkäisyysvirheen (${conflicts.length})`);

const winner = successes[0]?.data?.[0];
const winnerToken = attempts.indexOf(successes[0]) % 2 ? tokA : tokB;
const otherToken = winnerToken === tokA ? tokB : tokA;

// Toinen laite samaan aikaan onnistuu.
const dryer = await rpc('create_booking', { p_token: otherToken, p_device_id: 2, p_apartment_number: '7', p_start_at: start.toISOString(), p_minutes: 60 });
check(dryer.ok, 'kuivurin voi varata samalle ajalle kuin pesukoneen');

// Listaus näyttää molemmille saman tilanteen.
const from = new Date(start.getTime() - 864e5).toISOString();
const to = new Date(start.getTime() + 864e5).toISOString();
const listA = await rpc('list_bookings', { p_token: tokA, p_from: from, p_to: to });
const listB = await rpc('list_bookings', { p_token: tokB, p_from: from, p_to: to });
check(listA.ok && listB.ok && listA.data.length === listB.data.length && listA.data.length >= 2, 'molemmat laitteet näkevät samat varaukset');

// Poistaminen: kuka tahansa kirjautunut voi poistaa minkä tahansa tulevan varauksen.
if (winner) {
  const anonymous = await rpc('cancel_booking', { p_token: 'f'.repeat(64), p_booking_id: winner.id });
  check(!anonymous.ok && anonymous.data?.code === '28000', 'varausta ei voi poistaa ilman kirjautumista');
  const other = await rpc('cancel_booking', { p_token: otherToken, p_booking_id: winner.id });
  check(other.ok, 'toisen laitteen varauksen voi poistaa');
  const again = await rpc('cancel_booking', { p_token: winnerToken, p_booking_id: winner.id });
  check(!again.ok, 'poistettua varausta ei voi poistaa uudelleen');
}
if (dryer.ok) {
  const r = await rpc('cancel_booking', { p_token: otherToken, p_booking_id: dryer.data[0].id });
  check(r.ok, 'testivaraukset siivottu');
}

await rpc('logout', { p_token: tokA });
await rpc('logout', { p_token: tokB });

console.log(failures ? `\n${failures} testiä epäonnistui` : '\nKaikki API-testit läpäisty');
process.exit(failures ? 1 : 0);
