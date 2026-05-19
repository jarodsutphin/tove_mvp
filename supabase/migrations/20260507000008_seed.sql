-- ============================================================
-- SEED — Davidson, NC town record
-- ============================================================
insert into towns (id, name, state, slug, config) values (
  uuid_generate_v4(),
  'Davidson',
  'NC',
  'davidson-nc',
  '{
    "tagline": "Davidson, NC",
    "timezone": "America/New_York",
    "locale_notes": "College town, Davidson College campus. Strong event-driven demand around athletics, commencement, and alumni weekends."
  }'
);


-- ============================================================
-- SEED — Davidson academic calendar + key events (2025–2026)
-- ============================================================
with t as (select id from towns where slug = 'davidson-nc')
insert into town_calendar_events (town_id, event_name, event_type, start_date, end_date, impact_level, notes) values
  ((select id from t), 'Davidson College Fall Semester Start',  'academic',  '2025-08-27', '2025-08-27', 'high_demand',  'Move-in weekend, families in town'),
  ((select id from t), 'Davidson College Homecoming',           'athletics', '2025-10-04', '2025-10-05', 'high_demand',  'Alumni weekend, games, events on Main St'),
  ((select id from t), 'Davidson College Fall Break',           'academic',  '2025-10-09', '2025-10-12', 'awareness',    'Reduced student traffic'),
  ((select id from t), 'Davidson College Thanksgiving Break',   'academic',  '2025-11-26', '2025-11-30', 'awareness',    'Campus quiet'),
  ((select id from t), 'Davidson College Fall Semester End',    'academic',  '2025-12-12', '2025-12-12', 'awareness',    'Finals week ends, students leave'),
  ((select id from t), 'Davidson College Spring Semester Start','academic',  '2026-01-21', '2026-01-21', 'high_demand',  'Students return'),
  ((select id from t), 'Davidson College Spring Break',        'academic',  '2026-03-07', '2026-03-15', 'awareness',    'Reduced student traffic'),
  ((select id from t), 'Davidson College Commencement',        'academic',  '2026-05-15', '2026-05-16', 'high_demand',  'Highest demand weekend of year — families, alumni'),
  ((select id from t), 'Davidson College Commencement Weekend','academic',  '2026-05-13', '2026-05-14', 'high_demand',  'Pre-commencement dinners, reunions'),
  ((select id from t), 'Davidson 4th of July',                 'local',     '2026-07-04', '2026-07-04', 'high_demand',  'Town celebration, Main St closed'),
  ((select id from t), 'Davidson College Parents Weekend',     'academic',  '2025-10-17', '2025-10-19', 'high_demand',  'Families on campus, high restaurant demand'),
  ((select id from t), 'Davidson Farmers Market Season',       'local',     '2025-04-05', '2025-11-22', 'awareness',    'Saturday mornings downtown, drives lunch traffic'),
  ((select id from t), 'Christmas in Davidson',                'local',     '2025-12-06', '2025-12-06', 'high_demand',  'Annual town celebration, Main Street event'),
  ((select id from t), 'Davidson College Alumni Weekend',      'academic',  '2026-05-13', '2026-05-16', 'high_demand',  'Overlaps commencement, highest demand period of year');


-- ============================================================
-- SEED — Test business (Davidson restaurant placeholder)
-- ============================================================
with t as (select id from towns where slug = 'davidson-nc')
insert into businesses (
  town_id, type, name, slug, address, phone,
  brand_config, booking_rules,
  special_occasion_options, dietary_options, seating_preference_options
) values (
  (select id from t),
  'restaurant',
  'Test Restaurant',
  'test-restaurant',
  '123 Main Street, Davidson, NC 28036',
  '704-555-0100',
  '{
    "primary_color": "#1a1a1a",
    "accent_color": "#c8a96e",
    "font_family": "Georgia, serif",
    "hours_display": "Tues–Sat 5pm–10pm + Sun 5pm–9pm",
    "confirmation_email_tone": "warm"
  }',
  '{
    "advance_window_days": 60,
    "same_day_cutoff_hours": 2,
    "max_online_party_size": 10,
    "min_cancel_notice_hours": 24,
    "no_show_policy_text": "We hold reservations for 15 minutes past the reservation time."
  }',
  '["Birthday","Anniversary","Date Night","Business Dinner","Celebration"]',
  '["Vegetarian","Vegan","Gluten-Free","Dairy-Free","Nut Allergy","Shellfish Allergy"]',
  '["No preference","Inside","Patio","Bar","Private dining room"]'
);
