// Kevyt suomenkielinen päivämäärävalitsin. Selaimen oma valitsin näyttää
// kuukaudet ja viikonpäivät selaimen kielellä, joten käytetään omaa.

const MONTHS = [
  'Tammikuu', 'Helmikuu', 'Maaliskuu', 'Huhtikuu', 'Toukokuu', 'Kesäkuu',
  'Heinäkuu', 'Elokuu', 'Syyskuu', 'Lokakuu', 'Marraskuu', 'Joulukuu',
];
const WEEKDAYS = ['ma', 'ti', 'ke', 'to', 'pe', 'la', 'su'];
const WEEKDAYS_LONG = ['maanantai', 'tiistai', 'keskiviikko', 'torstai', 'perjantai', 'lauantai', 'sunnuntai'];

function startOfDay(d) {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate());
}
function addDays(d, n) {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate() + n);
}
function sameDay(a, b) {
  return a && b && a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
}
function weekdayIndex(d) {
  return (d.getDay() + 6) % 7; // maanantai = 0
}

function make(tag, props = {}, ...children) {
  const node = document.createElement(tag);
  for (const [key, value] of Object.entries(props)) {
    if (value === undefined || value === null || value === false) continue;
    if (key === 'className') node.className = value;
    else if (key === 'text') node.textContent = value;
    else if (key.startsWith('on')) node.addEventListener(key.slice(2), value);
    else node.setAttribute(key, value === true ? '' : value);
  }
  node.append(...children.filter(Boolean));
  return node;
}

/**
 * Liittää valitsimen painikkeeseen. Ponnahdusikkuna sijoitetaan painikkeen
 * vanhempaan elementtiin, jonka pitää olla position: relative.
 *   getValue(): valittu päivä (Date)
 *   getMin():   aikaisin valittava päivä tai null
 *   onSelect(date)
 */
export function attachDatePicker(button, { getValue, getMin = () => null, onSelect }) {
  const wrapper = button.parentElement;
  let popup = null;
  let viewMonth = null;

  button.setAttribute('aria-haspopup', 'dialog');
  button.setAttribute('aria-expanded', 'false');

  function isDisabled(date) {
    const min = getMin();
    return Boolean(min) && date < startOfDay(min);
  }

  function onOutside(event) {
    if (!wrapper.contains(event.target)) close(false);
  }

  function close(returnFocus) {
    if (!popup) return;
    popup.remove();
    popup = null;
    button.setAttribute('aria-expanded', 'false');
    document.removeEventListener('pointerdown', onOutside, true);
    if (returnFocus) button.focus();
  }

  function select(date) {
    if (isDisabled(date)) return;
    close(true);
    onSelect(date);
  }

  function showMonth(year, month, focusDate) {
    viewMonth = new Date(year, month, 1);
    render(focusDate);
  }

  function render(focusDate) {
    const year = viewMonth.getFullYear();
    const month = viewMonth.getMonth();
    const selected = getValue();
    const today = startOfDay(new Date());
    const daysInMonth = new Date(year, month + 1, 0).getDate();
    const offset = weekdayIndex(viewMonth);
    const prevDisabled = isDisabled(new Date(year, month, 0));

    const cells = [];
    for (let i = 0; i < offset; i++) cells.push(make('td'));
    for (let day = 1; day <= daysInMonth; day++) {
      const date = new Date(year, month, day);
      const disabled = isDisabled(date);
      const classes = ['dp-day', sameDay(date, selected) && 'is-selected', sameDay(date, today) && 'is-today'].filter(Boolean).join(' ');
      cells.push(make('td', {},
        make('button', {
          type: 'button',
          className: classes,
          'data-day': String(date.getTime()),
          'aria-label': `${WEEKDAYS_LONG[weekdayIndex(date)]} ${day}.${month + 1}.${year}${sameDay(date, today) ? ', tänään' : ''}`,
          'aria-pressed': sameDay(date, selected) ? 'true' : 'false',
          disabled,
          tabindex: '-1',
          text: String(day),
          onclick: () => select(date),
        })));
    }
    while (cells.length % 7) cells.push(make('td'));

    const rows = [];
    for (let i = 0; i < cells.length; i += 7) rows.push(make('tr', {}, ...cells.slice(i, i + 7)));

    popup.replaceChildren(
      make('div', { className: 'dp-header' },
        make('button', {
          type: 'button', className: 'dp-nav', 'aria-label': 'Edellinen kuukausi', text: '‹', disabled: prevDisabled,
          onclick: () => showMonth(year, month - 1),
        }),
        make('h2', { className: 'dp-title', 'aria-live': 'polite', text: `${MONTHS[month]} ${year}` }),
        make('button', {
          type: 'button', className: 'dp-nav', 'aria-label': 'Seuraava kuukausi', text: '›',
          onclick: () => showMonth(year, month + 1),
        })),
      make('table', { className: 'dp-grid', role: 'grid' },
        make('thead', {}, make('tr', {}, ...WEEKDAYS.map((w, i) => make('th', { scope: 'col', abbr: WEEKDAYS_LONG[i], text: w })))),
        make('tbody', {}, ...rows)),
      make('div', { className: 'dp-footer' },
        make('button', { type: 'button', className: 'button small', text: 'Sulje', onclick: () => close(true) })),
    );

    // Näppäimistöllä liikuttava päivä: annettu, valittu, tänään tai kuukauden ensimmäinen.
    const target = [focusDate, selected, today, viewMonth].find((d) => d && d.getMonth() === month && d.getFullYear() === year && !isDisabled(d));
    const days = [...popup.querySelectorAll('.dp-day:not([disabled])')];
    const active = (target && days.find((b) => Number(b.dataset.day) === startOfDay(target).getTime())) || days[0];
    if (active) {
      active.tabIndex = 0;
      if (focusDate) active.focus();
    }
  }

  function onKeydown(event) {
    if (event.key === 'Escape') {
      event.preventDefault();
      close(true);
      return;
    }
    const current = event.target.closest('.dp-day');
    if (!current) return;
    const moves = { ArrowLeft: -1, ArrowRight: 1, ArrowUp: -7, ArrowDown: 7 };
    if (!(event.key in moves)) return;
    event.preventDefault();
    const next = addDays(new Date(Number(current.dataset.day)), moves[event.key]);
    if (isDisabled(next)) return;
    showMonth(next.getFullYear(), next.getMonth(), next);
  }

  function open() {
    const value = getValue();
    popup = make('div', { className: 'dp-popup', role: 'dialog', 'aria-label': 'Valitse päivä', onkeydown: onKeydown });
    wrapper.append(popup);
    button.setAttribute('aria-expanded', 'true');
    document.addEventListener('pointerdown', onOutside, true);
    showMonth(value.getFullYear(), value.getMonth(), value);
  }

  button.addEventListener('click', () => (popup ? close(true) : open()));

  return {
    close: () => close(false),
    refresh: () => { if (popup) render(); },
  };
}
