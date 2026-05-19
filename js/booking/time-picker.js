// TimePicker: populates a dropdown panel with half-hour time slots.
// Usage: new TimePicker(panelEl, { slots, onSelect })

class TimePicker {
  constructor(panel, options = {}) {
    this.panel = panel;
    this.slots = options.slots || [
      '11:00 AM','11:30 AM','12:00 PM','12:30 PM',
      '1:00 PM', '1:30 PM', '2:00 PM', '2:30 PM',
      '3:00 PM', '3:30 PM', '4:00 PM', '4:30 PM',
      '5:00 PM', '5:30 PM', '6:00 PM', '6:30 PM',
      '7:00 PM', '7:30 PM', '8:00 PM', '8:30 PM',
      '9:00 PM', '9:30 PM',
    ];
    this.selected = null;
    this.onSelect = options.onSelect || null;
    this._render();
  }

  _render() {
    this.panel.innerHTML = this.slots.map(slot =>
      `<div class="dropdown__option${this.selected === slot ? ' is-selected' : ''}"
            role="option"
            aria-selected="${this.selected === slot}"
            data-value="${slot}">${slot}</div>`
    ).join('');

    this.panel.querySelectorAll('.dropdown__option').forEach(opt => {
      opt.addEventListener('click', () => {
        this.selected = opt.dataset.value;
        this._render();
        if (this.onSelect) this.onSelect(this.selected);
      });
    });
  }
}
