// Päivittäinen tuotannon savutesti, joka pitää samalla ilmaisen
// Supabase-projektin aktiivisena (.github/workflows/keepalive.yml).
//
// 1. Kirjautuu sisään yhteisellä salasanalla (luo istunnon).
// 2. Hakee laitteet ja tämän päivän varaukset (vain luku).
// 3. Kirjautuu ulos (poistaa istunnon).
//
// Varauksiin ei kosketa, eikä tuotantoon jää mitään pysyvää. Salasanaa ja
// istuntotunnistetta ei tulosteta.
//
//   PESUTUPA_SUPABASE_URL=https://xxxx.supabase.co \
//   PESUTUPA_API_KEY=<julkinen avain> \
//   PESUTUPA_PASSWORD=<yhteinen salasana> \
//   node tests/keepalive.mjs
//
// Paikallisesti: PESUTUPA_REST_URL=http://localhost:54321 PESUTUPA_PASSWORD=testisalasana-123 node tests/keepalive.mjs

const SUPABASE_URL = (process.env.PESUTUPA_SUPABASE_URL || '').replace(/\/$/, '');
const REST = process.env.PESUTUPA_REST_URL || (SUPABASE_URL ? `${SUPABASE_URL}/rest/v1` : '');
const KEY = process.env.PESUTUPA_API_KEY || '';
const PASSWORD = process.env.PESUTUPA_PASSWORD || '';

function fail(message) {
  console.error(`VIRHE: ${message}`);
  process.exit(1);
}

if (!REST) fail('PESUTUPA_SUPABASE_URL puuttuu.');
if (!PASSWORD) fail('PESUTUPA_PASSWORD puuttuu. Lisää salasana GitHubin salaisuudeksi (README, kohta 4.1).');

function headers() {
  const h = { 'Content-Type': 'application/json' };
  if (KEY) {
    h.apikey = KEY;
    if (KEY.startsWith('eyJ')) h.Authorization = `Bearer ${KEY}`;
  }
  return h;
}

async function rpc(name, body) {
  let res;
  try {
    res = await fetch(`${REST}/rpc/${name}`, { method: 'POST', headers: headers(), body: JSON.stringify(body) });
  } catch (error) {
    throw new Error(`${name}: yhteys epäonnistui (${error.cause?.code || error.message})`);
  }
  const text = await res.text();
  let data = null;
  try { data = text ? JSON.parse(text) : null; } catch { data = text; }
  if (!res.ok) throw new Error(`${name}: HTTP ${res.status} ${data?.message || ''}`.trim());
  return data;
}

let token = null;
try {
  const login = await rpc('login', { p_password: PASSWORD });
  if (!login?.ok) {
    const reasons = {
      invalid_password: 'väärä salasana. Onko yhteinen salasana vaihdettu? Päivitä GitHubin salaisuus PESUTUPA_PASSWORD.',
      too_many_attempts: 'liian monta virheellistä kirjautumisyritystä. Yritä myöhemmin uudelleen.',
    };
    throw new Error(`Kirjautuminen epäonnistui: ${reasons[login?.error] || login?.error || 'tuntematon syy'}`);
  }
  token = login.token;
  console.log('OK    kirjautuminen');

  const devices = await rpc('get_devices', { p_token: token });
  if (!Array.isArray(devices) || devices.length === 0) throw new Error('Laitteita ei löytynyt.');
  console.log(`OK    laitteet (${devices.length})`);

  const from = new Date();
  from.setHours(0, 0, 0, 0);
  const to = new Date(from.getTime() + 864e5);
  const bookings = await rpc('list_bookings', { p_token: token, p_from: from.toISOString(), p_to: to.toISOString() });
  if (!Array.isArray(bookings)) throw new Error('Varauslistaus palautti odottamattoman vastauksen.');
  console.log(`OK    päivän varaukset (${bookings.length})`);
} catch (error) {
  console.error(`VIRHE: ${error.message}`);
  process.exitCode = 1;
} finally {
  if (token) {
    try {
      await rpc('logout', { p_token: token });
      console.log('OK    uloskirjautuminen');
    } catch (error) {
      console.error(`VIRHE: uloskirjautuminen epäonnistui (${error.message}). Istunto vanhenee itsestään 30 päivässä.`);
      process.exitCode = 1;
    }
  }
}

if (!process.exitCode) console.log('\nTuotanto toimii.');
