-- ============================================================
-- STAFF NOTES
-- ============================================================
create table staff_notes (
  id          uuid primary key default uuid_generate_v4(),
  business_id uuid not null references businesses(id),
  guest_id    uuid not null references guests(id),
  booking_id  uuid references bookings(id),
  note        text not null,
  created_by  uuid not null references auth.users(id),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create index staff_notes_business_guest_idx on staff_notes(business_id, guest_id);


-- ============================================================
-- WAITLIST
-- ============================================================
create table waitlist (
  id             uuid primary key default uuid_generate_v4(),
  business_id    uuid not null references businesses(id),
  guest_id       uuid references guests(id),
  first_name     text not null,
  last_name      text,
  phone          text,
  email          text,
  party_size     int not null,
  preferred_date date not null,
  notified_at    timestamptz,
  status         text not null default 'waiting'
    check (status in ('waiting','notified','booked','expired')),
  created_at     timestamptz not null default now()
);


-- ============================================================
-- EMAIL LOG
-- ============================================================
create table email_log (
  id                uuid primary key default uuid_generate_v4(),
  business_id       uuid references businesses(id),
  guest_id          uuid references guests(id),
  booking_id        uuid references bookings(id),
  email_type        text not null check (email_type in (
    'booking_confirmation','reminder_24h','pre_arrival_48h',
    'marketing_trigger','weekly_digest','pre_arrival_digest',
    'reconfirmation_request','reconfirmation_reminder',
    'closure_planned','closure_private_event','closure_emergency','closure_permanent',
    'series_cancelled_guest_notification',
    'waitlist_available','conflict_alert'
  )),
  subject           text,
  resend_message_id text,
  status            text not null default 'sent',
  sent_at           timestamptz not null default now()
);


-- ============================================================
-- TRIGGER EVENTS
-- ============================================================
create table trigger_events (
  id                   uuid primary key default uuid_generate_v4(),
  trigger_id           uuid not null references marketing_triggers(id),
  guest_id             uuid not null references guests(id),
  business_id          uuid not null references businesses(id),
  fired_at             timestamptz not null default now(),
  email_log_id         uuid references email_log(id),
  converted            boolean not null default false,
  converted_booking_id uuid references bookings(id)
);


-- ============================================================
-- AGGREGATE SIGNALS
-- ============================================================
create table aggregate_signals (
  id                          uuid primary key default uuid_generate_v4(),
  guest_id                    uuid not null unique references guests(id),
  dining_frequency_per_month  numeric(4,2),
  hotel_frequency_per_year    numeric(4,2),
  typical_party_size_avg      numeric(4,2),
  typical_party_size_min      int,
  typical_party_size_max      int,
  lead_time_avg_hours         int,
  booking_style               text check (booking_style in ('planner','spontaneous','mixed')),
  daypart_preference          text check (daypart_preference in ('lunch','dinner','brunch','variable')),
  occasion_frequency_per_year numeric(4,2),
  reliability_score           numeric(3,2) check (reliability_score between 0 and 1),
  engagement_pattern          text check (engagement_pattern in ('trigger_responsive','organic','mixed')),
  platform_tenure_days        int,
  last_booking_at             timestamptz,
  recency_signal              text check (recency_signal in ('active','lapsing','lapsed')),
  total_bookings              int not null default 0,
  updated_at                  timestamptz not null default now()
);


-- ============================================================
-- GUEST BUSINESS RELATIONSHIPS
-- Denormalized join table maintained by trigger on bookings.
-- Replaces subquery joins in RLS policies for aggregate_signals
-- and guest_preferences — avoids per-row subquery cost at scale.
-- ============================================================
create table guest_business_relationships (
  guest_id         uuid not null references guests(id),
  business_id      uuid not null references businesses(id),
  first_booking_at timestamptz not null,
  last_booking_at  timestamptz not null,
  primary key (guest_id, business_id)
);

create index gbr_business_idx on guest_business_relationships(business_id);

create or replace function sync_guest_business_relationship()
returns trigger language plpgsql as $$
begin
  insert into guest_business_relationships (guest_id, business_id, first_booking_at, last_booking_at)
  values (new.guest_id, new.business_id, new.created_at, new.created_at)
  on conflict (guest_id, business_id) do update
    set last_booking_at = greatest(
      guest_business_relationships.last_booking_at,
      new.created_at
    );
  return new;
end;
$$;

create trigger bookings_sync_gbr
  after insert or update on bookings
  for each row execute function sync_guest_business_relationship();


-- ============================================================
-- BOOKING CONFLICTS
-- ============================================================
create table booking_conflicts (
  id            uuid primary key default uuid_generate_v4(),
  business_id   uuid not null references businesses(id),
  booking_id_a  uuid not null references bookings(id),
  booking_id_b  uuid not null references bookings(id),
  conflict_type text not null check (conflict_type in (
    'covers_exceeded','table_double_assigned','room_type_exceeded'
  )),
  severity      text not null check (severity in ('critical','urgent','advisory')),
  detected_at   timestamptz not null default now(),
  resolved_at   timestamptz,
  resolution    text check (resolution in ('cancelled_a','cancelled_b','moved','dismissed'))
);

create index booking_conflicts_business_idx
  on booking_conflicts(business_id)
  where resolved_at is null;


-- ============================================================
-- CLOSURE EVENTS
-- ============================================================
create table closure_events (
  id                     uuid primary key default uuid_generate_v4(),
  business_id            uuid not null references businesses(id),
  closure_date           date not null,
  closure_end_date       date not null,
  closure_type           text not null check (closure_type in (
    'planned','private_event','emergency','permanent'
  )),
  created_at             timestamptz not null default now(),
  created_by             uuid not null references auth.users(id),
  affected_booking_count int,
  email_sent_at          timestamptz,
  check (closure_end_date >= closure_date)
);

create index closure_events_business_date_idx
  on closure_events(business_id, closure_date, closure_end_date);
