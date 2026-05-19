-- ============================================================
-- GUESTS
-- ============================================================
create table guests (
  id                    uuid primary key default uuid_generate_v4(),
  auth_user_id          uuid unique references auth.users(id),
  email                 text unique not null,
  first_name            text not null,
  last_name             text not null,
  phone                 text,
  birthday_month        int check (birthday_month between 1 and 12),
  birthday_year         int,
  anniversary_date      date,
  photo_path            text,
  is_incomplete_profile boolean not null default false,
  consent_given         boolean not null default false,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);

create table guest_preferences (
  id                   uuid primary key default uuid_generate_v4(),
  guest_id             uuid not null unique references guests(id),
  dietary_restrictions       text[] not null default '{}',
  seating_preferences        text[] not null default '{}',
  dining_style_preferences   text[] not null default '{}',
  communication_opt_in       boolean not null default true,
  updated_at           timestamptz not null default now()
);


-- ============================================================
-- RECURRING SERIES
-- (defined before bookings because bookings references it)
-- ============================================================
create table recurring_series (
  id                     uuid primary key default uuid_generate_v4(),
  guest_id               uuid not null references guests(id),
  business_id            uuid not null references businesses(id),
  frequency              text not null check (frequency in ('weekly','monthly')),
  day_of_week            int check (day_of_week between 0 and 6),
  day_of_month           int check (day_of_month between 1 and 28),
  preferred_time         time not null,
  party_size             int not null,
  special_occasion       text,
  seating_preference     text,
  series_state           text not null default 'active'
    check (series_state in ('active','paused','cancelled','business_closed')),
  generation_window_days int not null default 60,
  last_generated_at      timestamptz,
  start_date             date not null,
  end_date               date,
  created_at             timestamptz not null default now()
);


-- ============================================================
-- MARKETING TRIGGERS
-- (defined before bookings because bookings references it)
-- ============================================================
create table marketing_triggers (
  id           uuid primary key default uuid_generate_v4(),
  business_id  uuid not null references businesses(id),
  trigger_type text not null check (trigger_type in (
    'lapsed_regular','birthday_month','anniversary','weather',
    'seasonal_return','post_visit','first_visit_followup','manual_broadcast'
  )),
  name         text not null,
  active       boolean not null default true,
  config       jsonb not null default '{}',
  created_at   timestamptz not null default now()
);
