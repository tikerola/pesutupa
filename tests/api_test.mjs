// REST-rajapinnan testit: rinnakkaiset varausyritykset ja käyttöoikeudet.
//
// Paikallisesti (tests/local/docker-compose.yml käynnissä):
//   node tests/api_test.mjs
//
// Oikeaa Supabase-projektia vastaan (luo testivarauksen ~60 päivän päähän ja peruu sen):
//   PESUTUPA_SUPABASE_URL=https://xxxx.supabase.co \
//   PESUTUPA_API_KEY=<anon- tai publishable-avain> \
//   PESUTUPA_PASSWORD=<yhteinen salasana> \
//   node tests/api_test.mjs

const SUPABASE_URL = process.env.PESUTUPA_SUPABASE_URL;
const REST = SUPABASE_URL ? `${SUPABASE_URL.replace(/\/$/, '')}/rest/v1` : 'http://localhost:54321';
const KEY = process.env.PESUTUPA_API_KEY || '';
const PASSWORD = process.env.PESUTUPA_PASSWORD || 'testisalasana-123';
const PARALLEL = 20;

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

// --- Käyttöoikeudet: taulut eivät näy REST-rajapinnassa ---
for (const table of ['bookings', 'sessions', 'settings', 'devices']) {
  const res = await fetch(`${REST}/${table}?select=*`, { headers: headers() });
  check(!res.ok, `taulu ${table} ei ole luettavissa suoraan (HTTP ${res.status})`);
}
{
  const r = await rpc('set_shared_password', { p_password: 'murtautuja-12345' });
  check(!r.ok, `salasanan vaihto ei ole kutsuttavissa (HTTP ${r.status})`);
  const r2 = await rpc('list_bookings', { p_token: 'a'.repeat(64), p_from: new Date().toISOString(), p_to: new Date(Date.now() + 864e5).toISOString() });
  check(!r2.ok && r2.data?.code === '28000', 'varaukset eivät näy ilman kirjautumista');
}

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
start.setUTCHours(Math.floor(Math.random() * 20), 0, 0, 0);

const attempts = await Promise.all(
  Array.from({ length: PARALLEL }, (_, i) =>
    rpc('create_booking', {
      p_token: i % 2 ? tokA : tokB,
      p_device_id: 1,
      p_apartment_number: String(100 + i),
      p_start_at: start.toISOString(),
      p_hours: 2,
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
const dryer = await rpc('create_booking', { p_token: otherToken, p_device_id: 2, p_apartment_number: '7', p_start_at: start.toISOString(), p_hours: 1 });
check(dryer.ok, 'kuivurin voi varata samalle ajalle kuin pesukoneen');

// Listaus näyttää molemmille saman tilanteen.
const from = new Date(start.getTime() - 864e5).toISOString();
const to = new Date(start.getTime() + 864e5).toISOString();
const listA = await rpc('list_bookings', { p_token: tokA, p_from: from, p_to: to });
const listB = await rpc('list_bookings', { p_token: tokB, p_from: from, p_to: to });
check(listA.ok && listB.ok && listA.data.length === listB.data.length && listA.data.length >= 2, 'molemmat laitteet näkevät samat varaukset');

// Peruminen.
if (winner) {
  const bad = await rpc('cancel_booking', { p_token: otherToken, p_booking_id: winner.id });
  check(!bad.ok, 'toisen laitteen varausta ei voi perua');
  const good = await rpc('cancel_booking', { p_token: winnerToken, p_booking_id: winner.id });
  check(good.ok, 'oman varauksen peruminen onnistuu');
}
if (dryer.ok) {
  const r = await rpc('cancel_booking', { p_token: otherToken, p_booking_id: dryer.data[0].id });
  check(r.ok, 'testivaraukset siivottu');
}

await rpc('logout', { p_token: tokA });
await rpc('logout', { p_token: tokB });

console.log(failures ? `\n${failures} testiä epäonnistui` : '\nKaikki API-testit läpäisty');
process.exit(failures ? 1 : 0);
