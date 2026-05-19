// DatePicker: renders an inline calendar and dispatches date selections.
// Usage: new DatePicker(containerEl, { closedDays, events, onSelect })

class DatePicker {
  constructor(container, options = {}) {
    this.container = container;
    this.today = new Date();
    this.today.setHours(0, 0, 0, 0);

    this.viewDate = new Date(this.today.getFullYear(), this.today.getMonth(), 1);
    this.selectedDate = new Date(this.today);
    this.closedDays = options.closedDays || [];  // JS day indices: 0=Sun, 1=Mon, ...
    this.events = options.events || [];           // [{ date: Date }]
    this.onSelect = options.onSelect || null;

    this.render();
  }

  get viewMonth() { return this.viewDate.getMonth(); }
  get viewYear()  { return this.viewDate.getFullYear(); }

  render() {
    const MONTH_NAMES = [
      'January','February','March','April','May','June',
      'July','August','September','October','November','December'
    ];
    const DAY_NAMES = ['MO','TU','WE','TH','FR','SA','SU'];

    const firstDay = new Date(this.viewYear, this.viewMonth, 1);
    const lastDay  = new Date(this.viewYear, this.viewMonth + 1, 0);

    // Monday-first column: JS 1(Mon)→1 … 6(Sat)→6, 0(Sun)→7
    const startCol = firstDay.getDay() === 0 ? 7 : firstDay.getDay();

    const caretSvg = `<svg class="datepicker__caret" width="14" height="14" viewBox="0 0 16 16" fill="none" aria-hidden="true">
      <path d="M3.5 5.5L8 10.5L12.5 5.5" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>
    </svg>`;

    const prevSvg = `<svg width="16" height="16" viewBox="0 0 16 16" fill="none" aria-hidden="true">
      <path d="M10 4L6 8L10 12" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>
    </svg>`;

    const nextSvg = `<svg width="16" height="16" viewBox="0 0 16 16" fill="none" aria-hidden="true">
      <path d="M6 4L10 8L6 12" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>
    </svg>`;

    let html = `
      <div class="datepicker__header">
        <div class="datepicker__month-year">
          <button class="datepicker__month-btn" type="button" aria-label="Select month">
            ${MONTH_NAMES[this.viewMonth]} ${caretSvg}
          </button>
          <button class="datepicker__year-btn" type="button" aria-label="Select year">
            ${this.viewYear} ${caretSvg}
          </button>
        </div>
        <div class="datepicker__nav">
          <button class="datepicker__nav-btn datepicker__prev" type="button" aria-label="Previous month">
            ${prevSvg}
          </button>
          <button class="datepicker__nav-btn datepicker__next" type="button" aria-label="Next month">
            ${nextSvg}
          </button>
        </div>
      </div>
      <div class="datepicker__calendar" role="grid" aria-label="${MONTH_NAMES[this.viewMonth]} ${this.viewYear}">
    `;

    // Day name headers
    DAY_NAMES.forEach(name => {
      html += `<div class="datepicker__day-name" role="columnheader">${name}</div>`;
    });

    // Leading spacer cells
    for (let i = 1; i < startCol; i++) {
      html += `<div class="datepicker__day-spacer" role="gridcell" aria-hidden="true"></div>`;
    }

    // Day cells
    for (let d = 1; d <= lastDay.getDate(); d++) {
      const date = new Date(this.viewYear, this.viewMonth, d);
      date.setHours(0, 0, 0, 0);

      const dayOfWeek  = date.getDay();
      const isPast     = date < this.today;
      const isClosed   = this.closedDays.includes(dayOfWeek);
      const isSelected = this.selectedDate && date.getTime() === this.selectedDate.getTime();
      const hasEvent   = this.events.some(ev => {
        const ed = new Date(ev.date);
        ed.setHours(0, 0, 0, 0);
        return ed.getTime() === date.getTime();
      });

      let classes = 'datepicker__day';
      if (isSelected) classes += ' is-selected';
      if (hasEvent && !isClosed) classes += ' has-event';

      const isDisabled = isPast || isClosed;

      html += `
        <button
          class="${classes}"
          type="button"
          role="gridcell"
          data-date="${date.toISOString().split('T')[0]}"
          ${isDisabled ? 'disabled aria-disabled="true"' : ''}
          aria-label="${MONTH_NAMES[this.viewMonth]} ${d}${isSelected ? ', selected' : ''}${hasEvent ? ', has event' : ''}"
          aria-pressed="${isSelected}"
        >${d}</button>
      `;
    }

    html += `</div>`;

    this.container.innerHTML = html;
    this._bindEvents();
  }

  _bindEvents() {
    this.container.querySelector('.datepicker__prev')?.addEventListener('click', () => {
      this.viewDate = new Date(this.viewYear, this.viewMonth - 1, 1);
      this.render();
    });

    this.container.querySelector('.datepicker__next')?.addEventListener('click', () => {
      this.viewDate = new Date(this.viewYear, this.viewMonth + 1, 1);
      this.render();
    });

    this.container.querySelectorAll('.datepicker__day:not([disabled])').forEach(btn => {
      btn.addEventListener('click', () => {
        const [y, m, d] = btn.dataset.date.split('-').map(Number);
        this.selectedDate = new Date(y, m - 1, d);
        this.render();
        if (this.onSelect) this.onSelect(this.selectedDate);
      });
    });
  }
}
