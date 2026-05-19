-- ============================================================
-- BOOKINGS
-- ============================================================
create table bookings (
  id                   uuid primary key default uuid_generate_v4(),
  business_id          uuid not null references businesses(id),
  guest_id             uuid not null references guests(id),
  booking_type         text not null check (booking_type in ('reservation','hotel_booking')),
  status               text not null default 'confirmed' check (status in (
    'pending','confirmed','arrived','seated','checked_in',
    'completed','cancelled','no_show'
  )),

  -- Restaurant reservation fields
  reservation_date     date,
  reservation_time     time,
  party_size           int,
  table_id             uuid references restaurant_tables(id),
  seated_at            timestamptz,
  vacated_at           timestamptz,

  -- Hotel booking fields
  check_in_date        date,
  check_out_date       date,
  room_inventory_id    uuid references room_inventory(id),
  room_assigned        text,
  adults               int,
  children             int,

  -- Shared fields
  special_occasion     text,
  occasion_notes       text,
  anniversary_date     date,
  guest_notes          text,
  add_ons              jsonb not null default '{}',
  source               text not null default 'online'
    check (source in ('online','phone','walk_in','ota','recurring')),
  is_override          boolean not null default false,
  override_reason      text,
  override_by          uuid references auth.users(id),
  override_at          timestamptz,
  marketing_trigger_id uuid references marketing_triggers(id),
  device_type          text,
  lead_time_hours      int,

  -- Recurring series
  series_id                       uuid references recurring_series(id),
  is_series_override              boolean not null default false,
  occurrence_state                text check (occurrence_state in (
    'active','pending_reconfirmation','confirmed','unconfirmed',
    'cancelled_by_guest','cancelled_by_restaurant','cancelled_series','completed'
  )),
  reconfirmation_sent_at          timestamptz,
  reconfirmation_reminder_sent_at timestamptz,
  confirmed_at                    timestamptz,

  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now()
);

create index bookings_business_date_idx
  on bookings(business_id, reservation_date)
  where booking_type = 'reservation';

create index bookings_business_checkin_idx
  on bookings(business_id, check_in_date)
  where booking_type = 'hotel_booking';

create index bookings_guest_idx on bookings(guest_id);
create index bookings_series_idx on bookings(series_id) where series_id is not null;
