// Muutoshistoria-sivu. Käyttää samaa selaimeen tallennettua kirjautumista
// kuin varaussivu, joten erillistä kirjautumista ei tarvita.
import { rpc, ApiError, isConfigured } from './api.js';

const STORAGE = { token: 'pesutupa.token', expires: 'pesutupa.expires' };
const LOG_ACTIONS = { created: 'Varaus tehty', extended: 'Vuoroa jatkettu', deleted: 'Varaus poistettu' };

const $ = (id) => document.getElementById(id);
let devices = new Map();

function storageGet(key) {
  try { return localStorage.getItem(key); } catch { return null; }
}

function el(tag, attrs = {}, ...children) {
  const node = document.createElement(tag);
  for (const [key, value] of Object.entries(attrs)) {
    if (value === undefined || value === null || value === false) continue;
    if (key === 'className') node.className = value;
    else if (key === 'text') node.textContent = value;
    else node.setAttribute(key, value === true ? '' : value);
  }
  for (const child of children.flat()) {
    if (child === null || child === undefined || child === false) continue;
    node.append(child instanceof Node ? child : document.createTextNode(String(child)));
  }
  return node;
}

const weekdayFmt = new Intl.DateTimeFormat('fi-FI', { weekday: 'short' });
const fmtTime = (d) => `${d.getHours()}.${String(d.getMinutes()).padStart(2, '0')}`;
const fmtShortDate = (d) => `${d.getDate()}.${d.getMonth() + 1}.`;
const fmtDayShort = (d) => `${weekdayFmt.format(d)} ${fmtShortDate(d)}`;
const sameDay = (a, b) => a.toDateString() === b.toDateString();

function fmtRange(s, e) {
  if (sameDay(s, e)) return `${fmtTime(s)}–${fmtTime(e)}`;
  return `${fmtShortDate(s)} ${fmtTime(s)} – ${fmtShortDate(e)} ${fmtTime(e)}`;
}
function fmtLogTime(d) {
  const year = d.getFullYear() !== new Date().getFullYear() ? d.getFullYear() : '';
  return `${fmtShortDate(d)}${year} klo ${fmtTime(d)}`;
}

// Tekijää ei yksilöidä: kerrotaan vain, oliko se tämä laite, ylläpito tai
// (poistoissa) varauksen tekijä vai joku muu. Palauttaa null, jos ei kerrottavaa.
function actorText(row) {
  if (row.by_admin) return 'Ylläpito';
  if (row.actor_is_me) return 'Tämä laite';
  if (row.action === 'deleted') return row.actor_is_owner ? 'Varauksen tekijä' : 'Joku muu kuin varauksen tekijä';
  return null;
}

function showNotice(text) {
  $('history-refresh').hidden = true;
  $('history-list').replaceChildren(
    el('p', { className: 'empty', text }),
    el('p', {}, el('a', { className: 'button primary', href: './', text: 'Siirry kirjautumaan' })));
}

function renderRows(rows) {
  if (!rows.length) {
    $('history-list').replaceChildren(el('p', { className: 'empty', text: 'Ei muutoksia 90 päivän ajalta.' }));
    return;
  }
  $('history-list').replaceChildren(el('ol', { className: 'history-list' }, rows.map((row) => {
    const start = new Date(row.start_at);
    const end = new Date(row.end_at);
    const actor = actorText(row);
    const time = row.action === 'extended' && row.previous_end_at
      ? `${fmtRange(start, end)} (ennen ${fmtTime(new Date(row.previous_end_at))})`
      : fmtRange(start, end);
    return el('li', { className: `history-item action-${row.action}` },
      el('p', { className: 'history-title' },
        el('span', { className: 'history-action', text: LOG_ACTIONS[row.action] || row.action }),
        el('time', { className: 'history-time', datetime: row.logged_at, text: fmtLogTime(new Date(row.logged_at)) })),
      el('dl', {},
        el('div', {}, el('dt', { text: 'Laite' }), el('dd', { text: devices.get(Number(row.device_id)) || `Laite ${row.device_id}` })),
        el('div', {}, el('dt', { text: 'Asunto' }), el('dd', { text: row.apartment_number })),
        el('div', {}, el('dt', { text: 'Varausaika' }), el('dd', {},
          el('span', { className: 'nowrap', text: fmtDayShort(start) }), ' ', el('span', { className: 'nowrap', text: time }))),
        actor && el('div', {}, el('dt', { text: 'Tekijä' }), el('dd', { text: actor }))));
  })));
}

async function load() {
  const token = storageGet(STORAGE.token);
  const expires = storageGet(STORAGE.expires);
  if (!token || !expires || new Date(expires) <= new Date()) {
    showNotice('Kirjaudu ensin sisään, niin näet muutoshistorian.');
    return;
  }

  const button = $('history-refresh');
  button.hidden = false;
  button.disabled = true;
  $('history-list').setAttribute('aria-busy', 'true');
  try {
    const [rows, deviceRows] = await Promise.all([
      rpc('list_booking_log', { p_token: token }),
      devices.size ? null : rpc('get_devices', { p_token: token }),
    ]);
    if (deviceRows) devices = new Map(deviceRows.map((d) => [Number(d.id), d.name]));
    renderRows(rows);
  } catch (error) {
    if (error instanceof ApiError && error.isSessionError) {
      showNotice('Kirjautuminen on vanhentunut. Kirjaudu uudelleen, niin näet muutoshistorian.');
      return;
    }
    $('history-list').replaceChildren(el('p', { className: 'empty', text: `Muutoshistoriaa ei voitu ladata. (${error.message})` }));
  } finally {
    button.disabled = false;
    $('history-list').setAttribute('aria-busy', 'false');
  }
}

$('history-refresh').addEventListener('click', load);
if (isConfigured) load();
else showNotice('Sovellusta ei ole vielä määritetty.');
