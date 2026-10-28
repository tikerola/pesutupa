import { rpc, ApiError, isConfigured } from './api.js';
import { attachDatePicker } from './datepicker.js';

const HOUR = 3600 * 1000;
const SLOT = 30 * 60 * 1000;
const REFRESH_INTERVAL = 30 * 1000;
const MAX_MINUTES = 180;
const DEFAULT_MINUTES = 60;

const STORAGE = {
  token: 'pesutupa.token',
  expires: 'pesutupa.expires',
  apartment: 'pesutupa.apartment',
  filter: 'pesutupa.filter',
};

const state = {
  token: storageGet(STORAGE.token),
  expiresAt: storageGet(STORAGE.expires),
  day: startOfDay(new Date()),
  filter: storageGet(STORAGE.filter) || 'all',
  devices: [],
  openHour: 8,
  closeHour: 22,
  bookings: [],
  // Aikaväli, jonka varaukset on haettu (valittu päivä ± 1 päivä).
  loadedFrom: null,
  loadedTo: null,
  myBookings: [],
  lastUpdated: null,
  stale: false,
  loading: false,
  refreshSeq: 0,
  timer: null,
};

const $ = (id) => document.getElementById(id);

// ---------------------------------------------------------------------
// Apufunktiot
// ---------------------------------------------------------------------

function storageGet(key) {
  try { return localStorage.getItem(key); } catch { return null; }
}
function storageSet(key, value) {
  try {
    if (value === null || value === undefined) localStorage.removeItem(key);
    else localStorage.setItem(key, value);
  } catch { /* yksityinen selaustila tms. */ }
}

function el(tag, attrs = {}, ...children) {
  const node = document.createElement(tag);
  for (const [key, value] of Object.entries(attrs)) {
    if (value === undefined || value === null || value === false) continue;
    if (key === 'className') node.className = value;
    else if (key === 'text') node.textContent = value;
    else if (key.startsWith('on')) node.addEventListener(key.slice(2), value);
    else node.setAttribute(key, value === true ? '' : value);
  }
  for (const child of children.flat()) {
    if (child === null || child === undefined || child === false) continue;
    node.append(child instanceof Node ? child : document.createTextNode(String(child)));
  }
  return node;
}

function startOfDay(d) {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate());
}
function addDays(d, n) {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate() + n);
}
function isSameDay(a, b) {
  return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
}
// Suomen aikavyöhykkeen poikkeamat ovat tasatunteja, joten puolen tunnin jaksot voidaan laskea epoch-ajasta.
function floorSlot(d) {
  return new Date(Math.floor(d.getTime() / SLOT) * SLOT);
}
// Varattavan ajan alku ja loppu valitulle päivälle (esim. klo 8.00 ja 22.00).
function opensAt(day) {
  return new Date(day.getFullYear(), day.getMonth(), day.getDate(), state.openHour);
}
function closesAt(day) {
  return new Date(day.getFullYear(), day.getMonth(), day.getDate(), state.closeHour);
}
// Varattavat alkamisajat: puolen tunnin välein aukioloajan sisällä.
function startSlotsOfDay(day) {
  const result = [];
  const end = closesAt(day).getTime();
  for (let t = opensAt(day).getTime(); t < end; t += SLOT) result.push(new Date(t));
  return result;
}
function dayKey(d) {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

function fmtTime(d) {
  return `${d.getHours()}.${String(d.getMinutes()).padStart(2, '0')}`;
}
function fmtShortDate(d) {
  return `${d.getDate()}.${d.getMonth() + 1}.`;
}
function fmtFullDate(d) {
  return `${d.getDate()}.${d.getMonth() + 1}.${d.getFullYear()}`;
}
const weekdayFmt = new Intl.DateTimeFormat('fi-FI', { weekday: 'short' });
const longDateFmt = new Intl.DateTimeFormat('fi-FI', { weekday: 'long', day: 'numeric', month: 'numeric', year: 'numeric' });
function fmtDayShort(d) {
  return `${weekdayFmt.format(d)} ${fmtShortDate(d)}`;
}
function fmtDayLong(d) {
  const today = startOfDay(new Date());
  const suffix = isSameDay(d, today) ? ' (tänään)' : isSameDay(d, addDays(today, 1)) ? ' (huomenna)' : '';
  return longDateFmt.format(d) + suffix;
}
function fmtRange(s, e) {
  if (isSameDay(s, e)) return `${fmtTime(s)}–${fmtTime(e)}`;
  if (e.getTime() === addDays(startOfDay(s), 1).getTime()) return `${fmtTime(s)}–24.00`;
  return `${fmtShortDate(s)} ${fmtTime(s)} – ${fmtShortDate(e)} ${fmtTime(e)}`;
}
function durationLabel(minutes) {
  if (minutes < 60) return `${minutes} min`;
  if (minutes === 60) return '1 tunti';
  return `${String(minutes / 60).replace('.', ',')} tuntia`;
}

function deviceName(id) {
  const device = state.devices.find((d) => d.id === Number(id));
  return device ? device.name : `Laite ${id}`;
}

function parseBooking(row) {
  return {
    id: row.id,
    deviceId: Number(row.device_id),
    apartment: row.apartment_number,
    start: new Date(row.start_at),
    end: new Date(row.end_at),
    isOwn: Boolean(row.is_own),
  };
}

function isBusy(deviceId, start, end) {
  return state.bookings.some((b) => b.deviceId === deviceId && b.start < end && b.end > start);
}

// ---------------------------------------------------------------------
// Ilmoitukset
// ---------------------------------------------------------------------

let messageTimer = null;
function showMessage(text, type = 'success') {
  const box = $('message');
  clearTimeout(messageTimer);
  box.setAttribute('role', type === 'error' ? 'alert' : 'status');
  box.className = `message ${type}`;
  box.textContent = text;
  box.hidden = false;
  if (type === 'success') messageTimer = setTimeout(() => { box.hidden = true; }, 10000);
}
function clearMessage() {
  clearTimeout(messageTimer);
  $('message').hidden = true;
}
function showFieldError(id, text) {
  const node = $(id);
  node.textContent = text || '';
  node.hidden = !text;
}

// ---------------------------------------------------------------------
// Kirjautuminen
// ---------------------------------------------------------------------

function showLogin(notice) {
  stopPolling();
  $('app-view').hidden = true;
  $('header-nav').hidden = true;
  $('login-view').hidden = false;
  if (notice) showMessage(notice, 'error');
  $('password').focus();
}

async function onLogin(event) {
  event.preventDefault();
  const password = $('password').value;
  showFieldError('login-error', '');
  if (!password) {
    showFieldError('login-error', 'Kirjoita salasana.');
    return;
  }

  const button = $('login-button');
  button.disabled = true;
  button.textContent = 'Kirjaudutaan…';
  try {
    const result = await rpc('login', { p_password: password, p_previous_token: state.token || null });
    if (!result || !result.ok) {
      const errors = {
        invalid_password: 'Väärä salasana.',
        too_many_attempts: 'Liian monta epäonnistunutta yritystä. Odota 15 minuuttia ja yritä uudelleen.',
        not_configured: 'Salasanaa ei ole vielä asetettu. Ota yhteyttä ylläpitäjään.',
      };
      showFieldError('login-error', errors[result && result.error] || 'Kirjautuminen epäonnistui.');
      return;
    }
    state.token = result.token;
    state.expiresAt = result.expires_at;
    storageSet(STORAGE.token, state.token);
    storageSet(STORAGE.expires, state.expiresAt);
    $('password').value = '';
    clearMessage();
    await enterApp();
  } catch (error) {
    showFieldError('login-error', error.message);
  } finally {
    button.disabled = false;
    button.textContent = 'Kirjaudu';
  }
}

function onSessionExpired() {
  // Tunniste säilytetään, jotta uudelleenkirjautuminen voi uusia saman istunnon
  // ja laitteella tehdyt varaukset pysyvät omina.
  state.expiresAt = null;
  storageSet(STORAGE.expires, null);
  showLogin('Istunto on vanhentunut. Kirjaudu uudelleen.');
}

async function onLogout() {
  if (!window.confirm('Kirjaudutaanko ulos?')) return;

  const token = state.token;
  state.token = null;
  state.expiresAt = null;
  state.myBookings = [];
  storageSet(STORAGE.token, null);
  storageSet(STORAGE.expires, null);
  try { await rpc('logout', { p_token: token }); } catch { /* istunto vanhenee joka tapauksessa */ }
  showLogin();
  showMessage('Olet kirjautunut ulos.');
}

// ---------------------------------------------------------------------
// Tietojen lataus
// ---------------------------------------------------------------------

async function enterApp() {
  $('login-view').hidden = true;
  $('app-view').hidden = false;
  $('header-nav').hidden = false;

  if (!state.devices.length) {
    try {
      const [devices, hours] = await Promise.all([
        rpc('get_devices', { p_token: state.token }),
        rpc('get_booking_hours', { p_token: state.token }),
      ]);
      state.devices = devices.map((d) => ({ id: Number(d.id), name: d.name }));
      if (hours && hours[0]) {
        state.openHour = Number(hours[0].open_hour);
        state.closeHour = Number(hours[0].close_hour);
      }
    } catch (error) {
      if (error instanceof ApiError && error.isSessionError) return onSessionExpired();
      $('calendars').replaceChildren(
        el('div', { className: 'card' },
          el('p', { text: `Laitetietojen lataus epäonnistui: ${error.message}` }),
          el('button', { type: 'button', className: 'button', text: 'Yritä uudelleen', onclick: () => enterApp() })),
      );
      $('calendars').setAttribute('aria-busy', 'false');
      return;
    }
    if (state.filter !== 'all' && !state.devices.some((d) => String(d.id) === state.filter)) state.filter = 'all';
    renderDeviceControls();
  }

  await refresh();
  startPolling();
}

async function refresh() {
  if (!state.token) return;
  const seq = ++state.refreshSeq;
  const day = state.day;
  state.loading = true;
  $('calendars').setAttribute('aria-busy', 'true');
  renderFreshness();

  try {
    const [bookings, mine] = await Promise.all([
      rpc('list_bookings', {
        p_token: state.token,
        p_from: addDays(day, -1).toISOString(),
        p_to: addDays(day, 2).toISOString(),
      }),
      rpc('my_bookings', { p_token: state.token }),
    ]);
    if (seq !== state.refreshSeq) return;
    state.bookings = bookings.map(parseBooking);
    state.myBookings = mine.map(parseBooking);
    state.loadedFrom = addDays(day, -1);
    state.loadedTo = addDays(day, 2);
    state.lastUpdated = new Date();
    state.stale = false;
  } catch (error) {
    if (seq !== state.refreshSeq) return;
    if (error instanceof ApiError && error.isSessionError) return onSessionExpired();
    state.stale = true;
    state.loadError = error.message;
  } finally {
    if (seq === state.refreshSeq) {
      state.loading = false;
      $('calendars').setAttribute('aria-busy', 'false');
    }
  }
  render();
}

function startPolling() {
  stopPolling();
  state.timer = setInterval(() => {
    if (document.visibilityState === 'visible') refresh();
  }, REFRESH_INTERVAL);
}
function stopPolling() {
  clearInterval(state.timer);
  state.timer = null;
}

document.addEventListener('visibilitychange', () => {
  if (document.visibilityState === 'visible' && state.timer) refresh();
});
window.addEventListener('online', () => { if (state.timer) refresh(); });

// Onko valitun päivän varaukset jo haettu (edellinen haku kattaa myös
// viereiset päivät, joten nuolilla siirtyminen näkyy heti).
function hasDataFor(day) {
  return Boolean(state.loadedFrom) && state.loadedFrom <= day && addDays(day, 1) <= state.loadedTo;
}

function setDay(day) {
  state.day = startOfDay(day);
  if (state.token) state.loading = true; // ettei hetkellistä "ei voitu ladata" -tekstiä näy
  render();
  refresh();
}

// ---------------------------------------------------------------------
// Näkymät
// ---------------------------------------------------------------------

function render() {
  renderDate();
  renderFreshness();
  renderCalendars();
  renderBookingForm();
  renderOwnBookings();
}

function renderDate() {
  $('booking-hours-hint').textContent = `Varattavissa klo ${state.openHour}.00–${state.closeHour}.00.`;
  const text = fmtFullDate(state.day);
  $('date-button-text').textContent = text;
  $('booking-date-text').textContent = text;
  $('date-button').setAttribute('aria-label', `Valitse päivä, valittuna ${text}`);
  $('booking-date-button').setAttribute('aria-label', `Varauksen päivä, valittuna ${text}`);
  $('date-label').textContent = fmtDayLong(state.day);
}

function renderFreshness() {
  const node = $('freshness');
  const dataForDay = hasDataFor(state.day);
  node.classList.toggle('stale', state.stale && !state.loading);
  $('calendars').classList.toggle('stale', state.stale && !state.loading);
  if (state.loading && !dataForDay) {
    node.textContent = ''; // latausympyrä näkyy kalenterin kohdalla
  } else if (state.stale) {
    node.textContent = state.lastUpdated && dataForDay
      ? `Varaustilannetta ei voitu päivittää. Näkymä on klo ${fmtTime(state.lastUpdated)} tilanne ja voi olla vanhentunut. (${state.loadError})`
      : `Varaustilannetta ei voitu ladata. (${state.loadError})`;
  } else if (state.lastUpdated) {
    node.textContent = `Varaustilanne päivitetty klo ${fmtTime(state.lastUpdated)}:${String(state.lastUpdated.getSeconds()).padStart(2, '0')}. Päivittyy automaattisesti.`;
  } else {
    node.textContent = '';
  }
}

function renderDeviceControls() {
  const filter = $('device-filter');
  const options = [{ value: 'all', label: 'Molemmat' }, ...state.devices.map((d) => ({ value: String(d.id), label: d.name }))];
  filter.replaceChildren(
    el('legend', { className: 'visually-hidden', text: 'Näytettävä laite' }),
    ...options.map((o) =>
      el('label', {},
        el('input', {
          type: 'radio', name: 'device-filter', value: o.value, checked: state.filter === o.value,
          onchange: () => { state.filter = o.value; storageSet(STORAGE.filter, o.value); renderCalendars(); },
        }),
        el('span', { text: o.label }))),
  );

  const group = $('booking-device');
  group.replaceChildren(
    el('legend', { text: 'Laite' }),
    ...state.devices.map((d, i) =>
      el('label', {},
        el('input', { type: 'radio', name: 'booking-device', value: String(d.id), checked: i === 0, onchange: () => renderBookingForm() }),
        d.name)),
  );
}

function buildRows(deviceId) {
  const dayStart = state.day;
  const dayEnd = addDays(state.day, 1);
  const open = opensAt(state.day);
  const close = closesAt(state.day);
  const nowSlot = floorSlot(new Date());
  const rows = [];

  // Vapaat ajat näytetään vain siltä osin kuin ne ovat vielä varattavissa
  // ja osuvat varattavaan aikaan.
  const pushGap = (s, e) => {
    const start = new Date(Math.max(s, nowSlot, open));
    const end = new Date(Math.min(e, close));
    if (end > start) rows.push({ type: 'free', start, end });
  };

  const list = state.bookings
    .filter((b) => b.deviceId === deviceId && b.start < dayEnd && b.end > dayStart)
    .sort((a, b) => a.start - b.start);

  let cursor = dayStart;
  for (const b of list) {
    if (b.start > cursor) pushGap(cursor, b.start);
    rows.push({ type: 'booking', booking: b, start: b.start, end: b.end });
    if (b.end > cursor) cursor = b.end;
  }
  if (cursor < dayEnd) pushGap(cursor, dayEnd);
  return rows;
}

function renderCalendars() {
  const container = $('calendars');
  const devices = state.filter === 'all' ? state.devices : state.devices.filter((d) => String(d.id) === state.filter);
  container.classList.toggle('two', devices.length > 1);

  if (!hasDataFor(state.day)) {
    // Valitun päivän tietoja ei ole: ei näytetä vapaita aikoja arvauksena.
    // Pidetään alueen korkeus ennallaan, ettei sivu hypi latauksen aikana.
    if (container.querySelector('.device-calendar')) container.style.minHeight = `${container.offsetHeight}px`;
    container.replaceChildren(state.loading
      ? el('div', { className: 'card loading-card', role: 'status' },
        el('span', { className: 'spinner', 'aria-hidden': 'true' }),
        el('span', { text: 'Ladataan varaustilannetta…' }))
      : el('div', { className: 'card' },
        el('p', { text: 'Varaustilannetta ei voitu ladata.' }),
        el('button', { type: 'button', className: 'button', text: 'Yritä uudelleen', onclick: () => { state.loading = true; renderCalendars(); refresh(); } })));
    return;
  }
  container.style.minHeight = '';

  const now = new Date();
  container.replaceChildren(...devices.map((device) => {
    const allRows = buildRows(device.id);
    const heading = el('h2', { id: `cal-h-${device.id}` }, el('span', { className: 'device-badge', 'aria-hidden': 'true' }), device.name);

    if (!allRows.some((row) => row.type === 'booking')) {
      const firstFree = allRows.find((row) => row.type === 'free');
      return el('section', { className: 'card device-calendar', 'data-device': String(device.id), 'aria-labelledby': `cal-h-${device.id}` },
        heading,
        el('div', { className: 'no-bookings' },
          el('p', { text: 'Ei varauksia.' }),
          firstFree && el('button', {
            type: 'button', className: 'button small',
            'aria-label': `Varaa ${device.name}`,
            text: 'Varaa',
            onclick: () => prefillBooking(device.id, firstFree.start),
          })));
    }

    const rows = allRows.map((row) => {
      if (row.type === 'booking') {
        const b = row.booking;
        const ended = b.end <= now;
        const status = ended ? 'Päättynyt' : b.isOwn ? 'Oma varaus' : 'Varattu';
        const cls = ended ? 'slot-past' : b.isOwn ? 'slot-own' : 'slot-booked';
        const statusCls = ended ? 'status-past' : b.isOwn ? 'status-own' : 'status-booked';
        return el('tr', { className: cls },
          el('td', { className: 'col-apartment', text: b.apartment }),
          el('td', { className: 'col-time', text: fmtRange(b.start, b.end) }),
          el('td', { className: 'col-status' },
            el('span', { className: 'slot-actions' },
              el('span', { className: `status ${statusCls}`, text: status }),
              !ended && el('button', {
                type: 'button', className: 'button small danger',
                'aria-label': `Poista asunnon ${b.apartment} varaus ${fmtRange(b.start, b.end)}`,
                text: 'Poista',
                onclick: (e) => onCancel(b, e.currentTarget),
              }))));
      }
      return el('tr', { className: 'slot-free' },
        el('td', { className: 'col-apartment' }, el('span', { 'aria-hidden': 'true', text: '–' })),
        el('td', { className: 'col-time', text: fmtRange(row.start, row.end) }),
        el('td', { className: 'col-status' },
          el('span', { className: 'slot-actions' },
            el('span', { className: 'status status-free', text: 'Vapaa' }),
            el('button', {
              type: 'button', className: 'button small',
              'aria-label': `Varaa ${device.name} alkaen klo ${fmtTime(row.start)}`,
              text: 'Varaa',
              onclick: () => prefillBooking(device.id, row.start),
            }))));
    });

    return el('section', { className: 'card device-calendar', 'data-device': String(device.id), 'aria-labelledby': `cal-h-${device.id}` },
      heading,
      el('table', { className: 'slots' },
        el('caption', { className: 'visually-hidden', text: `${device.name}: varaukset ${fmtDayLong(state.day)}` }),
        el('thead', {}, el('tr', {},
          el('th', { scope: 'col', text: 'Asunto' }),
          el('th', { scope: 'col', text: 'Varausaika' }),
          el('th', { scope: 'col', className: 'col-status', text: 'Tila' }))),
        el('tbody', {}, rows)));
  }));
}

// ---------------------------------------------------------------------
// Varauslomake
// ---------------------------------------------------------------------

function selectedDeviceId() {
  const checked = document.querySelector('input[name="booking-device"]:checked');
  return checked ? Number(checked.value) : null;
}

function prefillBooking(deviceId, start) {
  const radio = document.querySelector(`input[name="booking-device"][value="${deviceId}"]`);
  if (radio) radio.checked = true;
  renderBookingForm(start.getTime());
  $('booking-section').scrollIntoView({ behavior: 'smooth', block: 'start' });
  $('booking-apartment').value ? $('booking-hours').focus({ preventScroll: true }) : $('booking-apartment').focus({ preventScroll: true });
}

function renderBookingForm(preferredStart) {
  const deviceId = selectedDeviceId();
  const startSelect = $('booking-start');
  const durationSelect = $('booking-hours');
  const previousStart = preferredStart ?? Number(startSelect.value);
  const previousMinutes = Number(durationSelect.value) || DEFAULT_MINUTES;
  const nowSlot = floorSlot(new Date());
  const known = hasDataFor(state.day);

  const options = startSlotsOfDay(state.day)
    .filter((h) => h >= nowSlot)
    .map((h) => {
      const busy = known && deviceId !== null && isBusy(deviceId, h, new Date(h.getTime() + SLOT));
      return el('option', { value: String(h.getTime()), disabled: busy, text: busy ? `${fmtTime(h)} (varattu)` : fmtTime(h) });
    });

  const free = options.filter((o) => !o.disabled);
  if (!free.length) {
    startSelect.replaceChildren(el('option', { value: '', text: options.length ? 'Ei vapaita aikoja' : 'Ei enää varattavissa' }));
  } else {
    startSelect.replaceChildren(...options);
    const keep = free.find((o) => Number(o.value) === previousStart);
    startSelect.value = (keep || free[0]).value;
  }

  const start = startSelect.value ? new Date(Number(startSelect.value)) : null;
  const durationOptions = [];
  for (let minutes = 30; minutes <= MAX_MINUTES; minutes += 30) {
    const end = start ? new Date(start.getTime() + minutes * 60 * 1000) : null;
    const afterClose = Boolean(start) && end > closesAt(state.day);
    const busy = !start || afterClose || (known && isBusy(deviceId, start, end));
    const note = afterClose ? ` (yli klo ${state.closeHour}.00)` : busy && start ? ' (ei vapaana)' : '';
    durationOptions.push(el('option', { value: String(minutes), disabled: busy, text: durationLabel(minutes) + note }));
  }
  durationSelect.replaceChildren(...durationOptions);
  const valid = durationOptions.filter((o) => !o.disabled).map((o) => Number(o.value));
  const fallback = valid.includes(DEFAULT_MINUTES) ? DEFAULT_MINUTES : valid.at(-1) ?? DEFAULT_MINUTES;
  durationSelect.value = String(valid.includes(previousMinutes) ? previousMinutes : fallback);
  durationSelect.disabled = !start;
  $('booking-submit').disabled = !start;

  renderBookingSummary();
}

function renderBookingSummary() {
  const deviceId = selectedDeviceId();
  const startValue = $('booking-start').value;
  const node = $('booking-summary');
  if (!startValue || deviceId === null) {
    node.textContent = 'Valitulle päivälle ei ole enää vapaita aikoja. Valitse toinen päivä.';
    return;
  }
  const start = new Date(Number(startValue));
  const end = new Date(start.getTime() + Number($('booking-hours').value) * 60 * 1000);
  node.textContent = `Varaat: ${deviceName(deviceId)}, ${fmtDayShort(start)} klo ${fmtRange(start, end)}.`;
}

const APARTMENT_PATTERN = /^[0-9A-ZÅÄÖ][0-9A-ZÅÄÖ -]{0,9}$/;

async function onBookingSubmit(event) {
  event.preventDefault();
  showFieldError('booking-error', '');

  const deviceId = selectedDeviceId();
  const apartment = $('booking-apartment').value.trim().replace(/\s+/g, ' ').toUpperCase();
  const startValue = $('booking-start').value;
  const minutes = Number($('booking-hours').value);

  if (deviceId === null) return showFieldError('booking-error', 'Valitse laite.');
  if (!startValue) return showFieldError('booking-error', 'Valitse alkamisaika.');
  if (!apartment) {
    $('booking-apartment').focus();
    return showFieldError('booking-error', 'Kirjoita asunnon numero.');
  }
  if (!APARTMENT_PATTERN.test(apartment) || !/[0-9]/.test(apartment)) {
    $('booking-apartment').focus();
    return showFieldError('booking-error', 'Tarkista asunnon numero (esimerkiksi 9 tai A 12).');
  }

  const start = new Date(Number(startValue));
  const button = $('booking-submit');
  button.disabled = true;
  button.textContent = 'Tallennetaan…';
  try {
    const rows = await rpc('create_booking', {
      p_token: state.token,
      p_device_id: deviceId,
      p_apartment_number: apartment,
      p_start_at: start.toISOString(),
      p_minutes: minutes,
    });
    if (!Array.isArray(rows) || rows.length !== 1) throw new ApiError('Varauksen tallennus epäonnistui. Yritä uudelleen.', 'unexpected', 0);
    const saved = parseBooking(rows[0]);
    storageSet(STORAGE.apartment, saved.apartment);
    showMessage(`Varaus tallennettu: ${deviceName(saved.deviceId)}, ${fmtDayShort(saved.start)} klo ${fmtRange(saved.start, saved.end)}, asunto ${saved.apartment}.`);
    window.scrollTo({ top: 0, behavior: 'smooth' });
    await refresh();
  } catch (error) {
    if (error instanceof ApiError && error.isSessionError) return onSessionExpired();
    showFieldError('booking-error', error.message);
    if (error instanceof ApiError && error.isConflict) await refresh();
  } finally {
    button.textContent = 'Varaa';
    button.disabled = !$('booking-start').value;
  }
}

// ---------------------------------------------------------------------
// Omat varaukset
// ---------------------------------------------------------------------

function renderOwnBookings() {
  const container = $('own-list');
  if (!state.lastUpdated) {
    container.replaceChildren(el('p', { className: 'empty', text: 'Ladataan…' }));
    return;
  }
  if (!state.myBookings.length) {
    container.replaceChildren(el('p', { className: 'empty', text: 'Ei tulevia varauksia tällä laitteella.' }));
    return;
  }

  const now = new Date();
  container.replaceChildren(el('div', { className: 'own-list' }, state.myBookings.map((b) => {
    const ongoing = b.start <= now && now < b.end;
    const extendBy = ongoing ? extendOptions(b, now) : [];
    return el('article', { className: 'own-item', 'aria-label': `${deviceName(b.deviceId)} ${fmtDayShort(b.start)} ${fmtRange(b.start, b.end)}` },
      el('dl', {},
        el('div', {}, el('dt', { text: 'Laite' }), el('dd', { text: deviceName(b.deviceId) })),
        el('div', {}, el('dt', { text: 'Päivä' }), el('dd', { text: fmtDayShort(b.start) })),
        el('div', {}, el('dt', { text: 'Asunto' }), el('dd', { text: b.apartment })),
        el('div', {}, el('dt', { text: 'Varausaika' }), el('dd', { text: fmtRange(b.start, b.end) + (ongoing ? ' (käynnissä)' : '') }))),
      el('div', { className: 'actions' },
        ...extendBy.map((minutes) => el('button', {
          type: 'button', className: 'button small',
          text: minutes === 60 ? 'Jatka tunnilla' : 'Jatka 30 min',
          onclick: (e) => onExtend(b, minutes, e.currentTarget),
        })),
        el('button', { type: 'button', className: 'button small danger', text: 'Poista varaus', onclick: (e) => onCancel(b, e.currentTarget) })));
  })));
}

async function onCancel(booking, button) {
  const label = `${deviceName(booking.deviceId)} ${fmtDayShort(booking.start)} klo ${fmtRange(booking.start, booking.end)}`;
  if (!window.confirm(`Haluatko varmasti poistaa asunnon ${booking.apartment} varauksen?\n\n${label}`)) return;
  button.disabled = true;
  button.textContent = 'Poistetaan…';
  try {
    await rpc('cancel_booking', { p_token: state.token, p_booking_id: booking.id });
    showMessage(`Asunnon ${booking.apartment} varaus poistettu: ${label}. Aika on nyt vapaana.`);
  } catch (error) {
    if (error instanceof ApiError && error.isSessionError) return onSessionExpired();
    showMessage(error.message, 'error');
  }
  await refresh();
}

// Jatkovaihtoehdot (minuutteina) käynnissä olevalle omalle vuorolle: vain
// vuoron viimeisen tunnin aikana ja vain sen verran kuin vapaata aikaa on
// ennen sulkemisaikaa tai saman laitteen seuraavaa varausta. Tietokanta
// tarkistaa saman vielä tallennettaessa.
function extendOptions(booking, now) {
  if (now.getTime() < booking.end.getTime() - HOUR) return [];
  let limit = closesAt(startOfDay(booking.start)).getTime();
  if (hasDataFor(startOfDay(booking.end))) {
    for (const other of state.bookings) {
      if (other.deviceId === booking.deviceId && other.id !== booking.id && other.start >= booking.end) {
        limit = Math.min(limit, other.start.getTime());
      }
    }
  }
  const room = limit - booking.end.getTime();
  return [30, 60].filter((minutes) => minutes * 60 * 1000 <= room);
}

async function onExtend(booking, minutes, button) {
  button.disabled = true;
  button.textContent = 'Jatketaan…';
  try {
    const rows = await rpc('extend_booking', { p_token: state.token, p_booking_id: booking.id, p_minutes: minutes });
    const updated = parseBooking(rows[0]);
    showMessage(`Vuoroa jatkettu. ${deviceName(updated.deviceId)} on varattu klo ${fmtTime(updated.end)} asti.`);
  } catch (error) {
    if (error instanceof ApiError && error.isSessionError) return onSessionExpired();
    showMessage(error.message, 'error');
  }
  await refresh();
}

// ---------------------------------------------------------------------
// Käynnistys
// ---------------------------------------------------------------------

function init() {
  $('login-form').addEventListener('submit', onLogin);
  $('logout-button').addEventListener('click', onLogout);
  $('prev-day').addEventListener('click', () => setDay(addDays(state.day, -1)));
  $('next-day').addEventListener('click', () => setDay(addDays(state.day, 1)));
  attachDatePicker($('date-button'), { getValue: () => state.day, onSelect: setDay });
  attachDatePicker($('booking-date-button'), {
    getValue: () => state.day,
    getMin: () => new Date(),
    onSelect: (d) => { showFieldError('booking-error', ''); setDay(d); },
  });
  $('booking-start').addEventListener('change', () => renderBookingForm());
  $('booking-hours').addEventListener('change', renderBookingSummary);
  $('booking-form').addEventListener('submit', onBookingSubmit);
  $('booking-form').addEventListener('change', () => showFieldError('booking-error', ''));
  $('booking-apartment').value = storageGet(STORAGE.apartment) || '';

  if (!isConfigured) {
    showMessage('Sovellusta ei ole vielä määritetty: js/config.js puuttuu tai sisältää esimerkkiarvot.', 'error');
    return;
  }

  const valid = state.token && state.expiresAt && new Date(state.expiresAt) > new Date();
  if (valid) enterApp();
  else showLogin();
}

init();
