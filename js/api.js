// Supabasen REST-rajapinnan (PostgREST) RPC-kutsut ilman erillistä kirjastoa.

const config = window.PESUTUPA_CONFIG || {};
const REST_URL = config.restUrl || `${String(config.supabaseUrl || '').replace(/\/$/, '')}/rest/v1`;
const KEY = config.supabaseKey || '';

export const isConfigured = Boolean(config.restUrl || (config.supabaseUrl && !config.supabaseUrl.includes('your-project')));

export class ApiError extends Error {
  constructor(message, code, status) {
    super(message);
    this.code = code;
    this.status = status;
  }

  get isSessionError() {
    return this.code === '28000';
  }

  get isConflict() {
    return this.code === '23P01';
  }
}

// Tietokantafunktiot palauttavat näillä koodeilla käyttäjälle tarkoitetun suomenkielisen viestin.
const USER_MESSAGE_CODES = new Set(['P0001', '23P01', '22023', '28000']);

function friendlyMessage(code, message) {
  if (USER_MESSAGE_CODES.has(code) && message) return message;
  if (code === 'PGRST202') return 'Palvelinta ei ole vielä määritetty (tietokantafunktiota ei löydy).';
  return 'Palvelinvirhe. Yritä hetken kuluttua uudelleen.';
}

export async function rpc(name, params = {}) {
  const headers = { 'Content-Type': 'application/json', Accept: 'application/json' };
  if (KEY) {
    headers.apikey = KEY;
    // Vanha anon-avain on JWT ja kulkee myös Authorization-otsakkeessa; uusi publishable-avain ei.
    if (KEY.startsWith('eyJ')) headers.Authorization = `Bearer ${KEY}`;
  }

  let response;
  try {
    response = await fetch(`${REST_URL}/rpc/${name}`, {
      method: 'POST',
      headers,
      body: JSON.stringify(params),
      cache: 'no-store',
    });
  } catch {
    throw new ApiError('Yhteys palvelimeen epäonnistui. Tarkista verkkoyhteys ja yritä uudelleen.', 'network', 0);
  }

  const text = await response.text();
  let data = null;
  try {
    data = text ? JSON.parse(text) : null;
  } catch {
    data = null;
  }

  if (!response.ok) {
    const code = data && data.code;
    throw new ApiError(friendlyMessage(code, data && data.message), code || 'http', response.status);
  }
  return data;
}
