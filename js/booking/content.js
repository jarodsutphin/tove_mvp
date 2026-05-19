window.CONTENT = {

  BUSINESS: {
    name: 'Kindred',
    address: '131 N Main St. Davidson, NC 28036',
    mapsUrl: 'https://maps.google.com/?q=131+N+Main+St+Davidson+NC+28036',
    mapsEmbedUrl: 'https://maps.google.com/maps?q=Kindred+131+N+Main+St+Davidson+NC+28036&z=16&output=embed',
    instagramUrl: '#',
    orderOnlineUrl: '#',
    orderOnlineLabel: 'Order Online',
    navLinks: [
      { label: 'Events',       href: '#' },
      { label: 'Menu',         href: '#' },
      { label: 'Shop',         href: '#' },
      { label: 'Jobs',         href: '#' },
      { label: 'Reservations', href: '#' },
      { label: 'Press',        href: '#' },
    ],
  },

  BOOKING: {
    heroEyebrow: 'Reserve a Table',
    heroTitle: "We can’t wait to see you!",
    todayLabel: 'Today',
    timesHeader: 'Available times',
    timesSub: 'Within 2 hours of your preferred time',
    reserveCtaLabel: 'Reserve table',
    reserveCtaDisabledLabel: 'Reserve table — select a time to continue',
  },

  FINALIZE: {
    heroEyebrow: 'Reserve a Table',
    heroTitle: 'Almost there!',
    holdTimerLabel: (time) => `Holding table for ${time} min`,
    holdExpiredMessage: 'Hold expired — please start over',
    holdDurationSeconds: 600,
    finalizeCtaLabel: 'Finalize reservation',
    finalizeCtaDisabledLabel: 'Finalize reservation — enter your name and contact info to continue',
    dietarySectionTitle: 'Dietary restrictions',
    dietarySectionOptional: '(optional)',
    dietaryOtherPlaceholder: 'Add additional restrictions',
    occasionSectionTitle: 'Special occasion',
    occasionOtherPlaceholder: 'Add occasion',
  },

  DIETARY: [
    { value: 'peanuts_tree_nuts', label: 'Peanuts/tree nuts' },
    { value: 'fish',              label: 'Fish' },
    { value: 'milk_dairy',        label: 'Milk/dairy' },
    { value: 'shellfish',         label: 'Shellfish' },
    { value: 'eggs',              label: 'Eggs' },
    { value: 'sesame',            label: 'Sesame' },
    { value: 'wheat_gluten',      label: 'Wheat/gluten' },
    { value: 'kosher',            label: 'Kosher' },
    { value: 'soy',               label: 'Soy' },
    { value: 'halal',             label: 'Halal' },
  ],

  OCCASIONS: [
    { value: 'birthday',            label: 'Birthday' },
    { value: 'retirement',          label: 'Retirement' },
    { value: 'anniversary',         label: 'Anniversary' },
    { value: 'promotion_new_job',   label: 'Promotion/new job' },
    { value: 'graduation',          label: 'Graduation' },
    { value: 'business_meeting',    label: 'Business meeting' },
    { value: 'engagement_proposal', label: 'Engagement/proposal' },
    { value: 'date_night',          label: 'Date night' },
    { value: 'baby_shower',         label: 'Baby shower' },
  ],

  CONFIRMATION: {
    heroEyebrow: 'Reserve a Table',
    heroTitle: 'Reserved!',
    addToCalendarLabel: 'Add to calendar',
    shareLabel: 'Share',
    recurringToggleLabel: 'Make a recurring reservation?',
    recurringSheetTitle: 'Recurring reservation',
    recurringSheetIntro: "Choose how often you want to come back to your favorite spots. We’ll send a reminder <strong>4 days</strong> before your scheduled visit. Edit or cancel reservations anytime in your account.",
    recurringFrequencies: [
      { value: 'weekly',    label: 'Every week on a Friday',                    defaultChecked: false },
      { value: 'monthly',   label: 'Every month on a Friday',                   defaultChecked: true  },
      { value: 'quarterly', label: 'Every three months on a Friday',            defaultChecked: false },
      { value: 'annual',    label: 'This date annually for a special occasion', defaultChecked: false },
    ],
    sheetConfirmLabel: 'Confirm',
    recurringSheetDisclaimer: "This recurring reservation will be subject to change based on closures or unforeseen events. For annual reservations, your specific date may fall on a day we cannot accommodate. We’ll contact you before your visit to adjust the date of your reservation.",
    toveCardMessage: 'This reservation can be managed in the account we created for you.',
    toveCardCtaLabel: 'Manage reservation',
    toveCardFinePrint: 'Your <a href="#" class="tove-card__link">Tove account</a> manages your reservations, profile, and personal information. You can edit or delete your account anytime.',
    menuSectionHeader: 'Get ready for your visit',
    menuSectionSub: 'Menu items and availability subject to change',
  },

  FOOTER: {
    address: '131 N Main St. Davidson, NC 28036',
    mapsUrl: 'https://maps.google.com/?q=131+N+Main+St+Davidson+NC+28036',
    hours: [
      'Tues – Sat 5pm–10pm + Sun 5pm–9pm',
      'Brunch: Sat–Sun 11am–2pm',
    ],
  },

  EVENTS: [
    { date: '2026-05-10', name: 'Davidson College Day',          time: '10 a.m.' },
    { date: '2026-05-15', name: 'Main Street Block Party',       time: '2 p.m.'  },
    { date: '2026-05-16', name: 'Live Music at Summit Coffee',   time: '7 p.m.'  },
    { date: '2026-05-17', name: 'Davidson College Commencement', time: '10 a.m.' },
    { date: '2026-05-24', name: 'Brickhouse Farmers Market',     time: '8 a.m.'  },
    { date: '2026-05-31', name: 'Davidson Farmers Market',       time: '8 a.m.'  },
  ],

};

