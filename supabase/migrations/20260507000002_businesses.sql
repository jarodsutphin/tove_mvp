-- ============================================================
-- BUSINESSES
-- ============================================================
create table businesses (
  id                                 uuid primary key default uuid_generate_v4(),
  town_id                            uuid not null references towns(id),
  type                               text not null check (type in ('restaurant','hotel')),
  name                               text not null,
  slug                               text unique not null,
  address                            text not null,
  phone                              text,
  website                            text,
  cuisine_type                       text,
  description                        text,
  brand_config                       jsonb not null default '{}',
  booking_rules                      jsonb not null default '{}',
  special_occasion_options           jsonb not null default '[]',
  dietary_options                    jsonb not null default '[]',
  seating_preference_options         jsonb not null default '[]',
  unconfirmed_booking_policy         text not null default 'hold_table'
    check (unconfirmed_booking_policy in ('hold_table','release_after_cutoff')),
  unconfirmed_release_cutoff_minutes int,
  active                             boolean not null default true,
  created_at                         timestamptz not null default now(),
  updated_at                         timestamptz not null default now()
);

create table business_users (
  id          uuid primary key default uuid_generate_v4(),
  business_id uuid not null references businesses(id),
  user_id     uuid not null references auth.users(id),
  role        text not null check (role in ('owner','manager','host')),
  created_at  timestamptz not null default now(),
  unique(business_id, user_id)
);

create table service_periods (
  id                    uuid primary key default uuid_generate_v4(),
  business_id           uuid not null references businesses(id),
  name                  text not null,
  days_of_week          int[] not null,
  open_time             time not null,
  close_time            time not null,
  slot_interval_minutes int not null default 15,
  active                boolean not null default true
);

create table operating_hours (
  id          uuid primary key default uuid_generate_v4(),
  business_id uuid not null references businesses(id),
  day_of_week int not null check (day_of_week between 0 and 6),
  open_time   time not null,
  close_time  time not null,
  unique(business_id, day_of_week)
);

create table business_closures (
  id                     uuid primary key default uuid_generate_v4(),
  business_id            uuid not null references businesses(id),
  closure_date           date not null,
  closure_end_date       date not null,
  closure_type           text not null default 'planned'
    check (closure_type in ('planned','private_event','emergency','permanent')),
  reason                 text,
  affected_booking_count int not null default 0,
  email_sent_at          timestamptz,
  created_by             uuid references auth.users(id),
  created_at             timestamptz not null default now(),
  check (closure_end_date >= closure_date)
);
