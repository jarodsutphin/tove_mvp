# Tove — System Architecture

**Version**: 1.0  
**Date**: 2026-05-07

---

## 1. System Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                         Guest Browser                           │
│          Booking page (branded to restaurant/hotel)             │
│              Vanilla HTML/CSS/JS, hosted on Vercel              │
└────────────────────────┬────────────────────────────────────────┘
                         │ HTTPS
┌────────────────────────▼────────────────────────────────────────┐
│                   Supabase (backend)                            │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐  │
│  │   Postgres   │  │  Supabase    │  │   Edge Functions     │  │
│  │   + RLS      │  │    Auth      │  │  (scheduled jobs,    │  │
│  │              │  │  (OTP magic  │  │   trigger engine,    │  │
│  │              │  │   link +     │  │   email dispatch)    │  │
│  │              │  │  email/pass) │  │                      │  │
│  └──────────────┘  └──────────────┘  └──────────────────────┘  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │              Supabase Storage                            │   │
│  │         guest-photos bucket (private, RLS)               │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
         │                    │                    │
    Claude API            Resend API         External APIs
 (digest copy,          (transactional     (Open-Meteo,
  guest insights,        + marketing        Ticketmaster,
  re-engagement)         email)             Sunrise-Sunset)
```

---

## 2. Multi-Tenant Architecture

Every business on the platform has fully isolated data. The `business_id` foreign key is the isolation boundary, enforced by Supabase RLS policies on every relevant table.

**Isolation guarantees:**
- A business user can only read/write records where `business_id` matches their authenticated business
- Guest aggregate signals are readable by any business that has a booking history with that guest, but contain zero venue-specific data
- Staff notes are strictly business-scoped; guests never read them
- Guest profile photos are visible only to businesses where the guest has at least one confirmed booking

**Guest identity is cross-platform:** a single `guests` record and `aggregate_signals` record exists per email. Venue-specific history (bookings, staff notes) is scoped to each business. The two layers are architecturally separated.

---

## 3. Authentication

### Business users (staff and owners)
- Supabase Auth email/password
- Role stored in `business_users.role` (owner, manager, host)
- RLS policies join `auth.uid()` → `business_users.user_id` → `business_users.business_id`

### Guests
- Supabase Auth OTP magic link
- Email is the identity — no password ever
- **First booking**: guest completes form, profile created, `auth.users` record created, magic link not required to complete booking
- **Return booking**: guest enters email, Supabase sends OTP magic link, tap loads authenticated session, profile pre-populated
- `guests.auth_user_id` links to `auth.users.id`
- Guest session scoped to read/write their own records only

### Tove internal admin
- Direct Supabase service role key, used from Tove team's local environment or admin tooling
- No RLS bypass in production application code

---

## 4. Database Schema

```sql
-- ============================================================
-- EXTENSIONS
-- ============================================================
create extension if not exists "uuid-ossp";


-- ============================================================
-- TOWNS
-- ============================================================
create table towns (
  id         uuid primary key default uuid_generate_v4(),
  name       text not null,
  state      text not null,
  slug       text unique not null,
  config     jsonb not null default '{}',
  -- config shape: { tagline, primary_color, accent_color, hero_photo_url,
  --                 timezone, locale_notes }
  created_at timestamptz not null default now()
);

create table town_calendar_events (
  id           uuid primary key default uuid_generate_v4(),
  town_id      uuid not null references towns(id),
  event_name   text not null,
  event_type   text not null
    check (event_type in ('academic','athletics','local','holiday','other')),
  start_date   date not null,
  end_date     date not null,
  impact_level text not null
    check (impact_level in ('high_demand','closure','awareness')),
  notes        text,
  active       boolean not null default true,
  created_at   timestamptz not null default now()
);


-- ============================================================
-- BUSINESSES
-- ============================================================
create table businesses (
  id                        uuid primary key default uuid_generate_v4(),
  town_id                   uuid not null references towns(id),
  type                      text not null check (type in ('restaurant','hotel')),
  name                      text not null,
  slug                      text unique not null,
  address                   text not null,
  phone                     text,
  website                   text,
  cuisine_type              text,
  description               text,
  brand_config              jsonb not null default '{}',
  -- brand_config shape: { logo_url, primary_color, accent_color,
  --                        font_family, hero_photo_url,
  --                        confirmation_email_tone }
  booking_rules             jsonb not null default '{}',
  -- booking_rules shape: { advance_window_days, same_day_cutoff_hours,
  --                         max_online_party_size, min_cancel_notice_hours,
  --                         no_show_policy_text }
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
  id           uuid primary key default uuid_generate_v4(),
  business_id  uuid not null references businesses(id),
  closure_date date not null,
  reason       text,
  created_at   timestamptz not null default now()
);


-- ============================================================
-- RESTAURANT-SPECIFIC
-- ============================================================
create table restaurant_tables (
  id          uuid primary key default uuid_generate_v4(),
  business_id uuid not null references businesses(id),
  label       text not null,
  covers      int not null,
  section     text not null,
  active      boolean not null default true
);

create table floor_plans (
  id          uuid primary key default uuid_generate_v4(),
  business_id uuid not null references businesses(id),
  name        text not null default 'Main Floor',
  canvas_json jsonb not null default '{}',
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create table turn_times (
  id           uuid primary key default uuid_generate_v4(),
  business_id  uuid not null references businesses(id),
  min_covers   int not null,
  max_covers   int not null,
  turn_minutes int not null,
  unique(business_id, min_covers, max_covers)
);


-- ============================================================
-- HOTEL-SPECIFIC
-- ============================================================
create table room_inventory (
  id               uuid primary key default uuid_generate_v4(),
  business_id      uuid not null references businesses(id),
  room_type        text not null,
  label            text not null,
  description      text,
  rate_per_night   numeric(10,2),
  max_occupancy    int not null,
  photography_urls text[] not null default '{}',
  active           boolean not null default true
);

create table hotel_availability_blocks (
  id                uuid primary key default uuid_generate_v4(),
  business_id       uuid not null references businesses(id),
  room_inventory_id uuid not null references room_inventory(id),
  blocked_date      date not null,
  reason            text,
  created_at        timestamptz not null default now()
);


-- ============================================================
-- GUESTS
-- ============================================================
create table guests (
  id             uuid primary key default uuid_generate_v4(),
  auth_user_id   uuid unique references auth.users(id),
  email          text unique not null,
  first_name     text not null,
  last_name      text not null,
  phone          text,
  birthday_month int check (birthday_month between 1 and 12),
  birthday_year  int,
  photo_path            text,
  -- photo_path: Supabase Storage path, e.g. "guest-photos/{guest_id}/profile.jpg"
  -- null if guest has not uploaded a photo
  is_incomplete_profile boolean not null default false,
  -- true when guest record was created from a staff manual booking entry (name+phone only)
  -- cleared when guest completes a full online booking
  consent_given  boolean not null default false,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

create table guest_preferences (
  id                   uuid primary key default uuid_generate_v4(),
  guest_id             uuid not null unique references guests(id),
  dietary_restrictions text[] not null default '{}',
  seating_preferences  text[] not null default '{}',
  communication_opt_in boolean not null default true,
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
  -- config shape varies by type:
  -- lapsed_regular: { lapse_threshold_days, cooldown_days }
  -- birthday_month: { lead_weeks, offer_text }
  -- anniversary:    { lead_weeks, offer_text }
  -- post_visit:     { delay_hours }
  -- first_visit:    { delay_hours }
  created_at   timestamptz not null default now()
);


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
  -- Occurrence-level state (null for non-recurring bookings)
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

-- Trigger: keep guest_business_relationships current on every bookings insert/update
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
  -- critical = within 24h, urgent = within 7 days, advisory = 8-14 days
  detected_at   timestamptz not null default now(),
  resolved_at   timestamptz,
  resolution    text check (resolution in ('cancelled_a','cancelled_b','moved','dismissed'))
);

create index booking_conflicts_business_idx
  on booking_conflicts(business_id)
  where resolved_at is null;


-- ============================================================
-- CLOSURE EVENTS
-- Audit log of every closure action taken by a restaurant.
-- process-closure-event Edge Function fires on insert.
-- ============================================================
create table closure_events (
  id                    uuid primary key default uuid_generate_v4(),
  business_id           uuid not null references businesses(id),
  closure_date          date not null,
  closure_type          text not null check (closure_type in (
    'planned','private_event','emergency','permanent'
  )),
  created_at            timestamptz not null default now(),
  created_by            uuid not null references auth.users(id),
  affected_booking_count int,
  email_sent_at         timestamptz
);

create index closure_events_business_date_idx on closure_events(business_id, closure_date);
```

---

## 5. Row Level Security Policies

RLS is enabled on all tables. The service role bypasses RLS (used only by Tove internal admin tooling and Edge Functions via the service key).

### Helper function

```sql
-- Returns the business_id for the currently authenticated business user
create or replace function auth_business_id()
returns uuid language sql stable as $$
  select business_id from business_users where user_id = auth.uid() limit 1;
$$;

-- Returns the guest_id for the currently authenticated guest
create or replace function auth_guest_id()
returns uuid language sql stable as $$
  select id from guests where auth_user_id = auth.uid() limit 1;
$$;
```

### businesses

```sql
alter table businesses enable row level security;

create policy "business_users_read_own_business" on businesses
  for select using (id = auth_business_id());
```

### business_users

```sql
alter table business_users enable row level security;

create policy "users_read_own_membership" on business_users
  for select using (user_id = auth.uid());
```

### service_periods, operating_hours, business_closures, restaurant_tables, floor_plans, turn_times, room_inventory, hotel_availability_blocks

```sql
-- Pattern: business user reads own business's records only
-- Shown here for restaurant_tables; apply the same pattern to all above tables

alter table restaurant_tables enable row level security;

create policy "business_users_read_own_tables" on restaurant_tables
  for select using (business_id = auth_business_id());

create policy "business_users_write_own_tables" on restaurant_tables
  for all using (business_id = auth_business_id());
```

### guests

```sql
alter table guests enable row level security;

-- Guest reads/updates own record
create policy "guests_read_own" on guests
  for select using (auth_user_id = auth.uid());

create policy "guests_update_own" on guests
  for update using (auth_user_id = auth.uid());

-- Business users read guests with whom they have a booking history
create policy "business_reads_own_guests" on guests
  for select using (
    exists (
      select 1 from bookings b
      where b.guest_id = guests.id
        and b.business_id = auth_business_id()
    )
  );

-- Guests can be created during booking flow (unauthenticated insert via service role in Edge Function)
```

### guest_preferences

```sql
alter table guest_preferences enable row level security;

create policy "guests_read_own_prefs" on guest_preferences
  for select using (guest_id = auth_guest_id());

create policy "guests_write_own_prefs" on guest_preferences
  for all using (guest_id = auth_guest_id());

create policy "business_reads_guest_prefs" on guest_preferences
  for select using (
    exists (
      select 1 from bookings b
      where b.guest_id = guest_preferences.guest_id
        and b.business_id = auth_business_id()
    )
  );
```

### bookings

```sql
alter table bookings enable row level security;

-- Business users read/write their own business's bookings
create policy "business_reads_own_bookings" on bookings
  for select using (business_id = auth_business_id());

create policy "business_writes_own_bookings" on bookings
  for all using (business_id = auth_business_id());

-- Guests read their own bookings across all businesses
create policy "guests_read_own_bookings" on bookings
  for select using (guest_id = auth_guest_id());

-- Guests can cancel their own bookings
create policy "guests_cancel_own_bookings" on bookings
  for update using (
    guest_id = auth_guest_id()
    and status = 'confirmed'
  );
```

### staff_notes

```sql
alter table staff_notes enable row level security;

-- Business users only, scoped to their business — guests never read staff notes
create policy "business_users_staff_notes" on staff_notes
  for all using (business_id = auth_business_id());
```

### aggregate_signals

```sql
alter table aggregate_signals enable row level security;

-- Guests read own signals
create policy "guests_read_own_signals" on aggregate_signals
  for select using (guest_id = auth_guest_id());

-- Business users read signals for guests who have booked with them
-- The aggregate_signals table contains zero venue-specific data, so this is safe
create policy "business_reads_guest_signals" on aggregate_signals
  for select using (
    exists (
      select 1 from bookings b
      where b.guest_id = aggregate_signals.guest_id
        and b.business_id = auth_business_id()
    )
  );
```

### marketing_triggers, trigger_events, email_log, waitlist, booking_conflicts

Business-scoped: standard pattern (business_id = auth_business_id()).

### guest_business_relationships

```sql
alter table guest_business_relationships enable row level security;

-- Business users read relationships for their own business
create policy "business_reads_own_gbr" on guest_business_relationships
  for select using (business_id = auth_business_id());

-- Guests read their own relationships (to see which businesses know them)
create policy "guests_read_own_gbr" on guest_business_relationships
  for select using (guest_id = auth_guest_id());
```

**Note**: Now that `guest_business_relationships` exists, the RLS policies for `aggregate_signals`, `guests`, and `guest_preferences` that currently use a subquery against `bookings` should be updated to join against `guest_business_relationships` instead for better query performance at scale.

### Supabase Storage — guest-photos bucket

```sql
-- Bucket is private (not public)
-- Objects stored at path: guest-photos/{guest_id}/profile.jpg

-- Policy: business user can read a guest photo if that guest
-- has at least one confirmed booking at their business
create policy "business_reads_guest_photo"
  on storage.objects for select
  using (
    bucket_id = 'guest-photos'
    and exists (
      select 1
      from guests g
      join bookings b on b.guest_id = g.id
      where g.id::text = (storage.foldername(name))[1]
        and b.business_id = auth_business_id()
        and b.status in ('confirmed','arrived','seated','checked_in','completed')
    )
  );

-- Policy: guest can read and update their own photo
create policy "guest_reads_own_photo"
  on storage.objects for select
  using (
    bucket_id = 'guest-photos'
    and (storage.foldername(name))[1] = auth_guest_id()::text
  );

create policy "guest_writes_own_photo"
  on storage.objects for insert with check (
    bucket_id = 'guest-photos'
    and (storage.foldername(name))[1] = auth_guest_id()::text
  );

create policy "guest_deletes_own_photo"
  on storage.objects for delete
  using (
    bucket_id = 'guest-photos'
    and (storage.foldername(name))[1] = auth_guest_id()::text
  );
```

---

## 6. Supabase Edge Functions

All Edge Functions run on the Deno runtime. Scheduled functions use pg_cron via the Supabase Dashboard or the `pg_cron` extension.

| Function | Schedule | Purpose |
|---|---|---|
| `send-booking-reminder` | Every 5 min | Query confirmed bookings in next 24h; send reminder if not already sent |
| `send-hotel-pre-arrival` | Every 5 min | Query hotel check-ins in next 48h; send pre-arrival email if not sent |
| `compute-aggregate-signals` | Daily 2am | Recompute aggregate signals for all guests with a booking in the past 90 days |
| `scan-booking-conflicts` | Daily 2:30am | Scan all confirmed bookings within 14 days; insert new conflicts to `booking_conflicts`; email owner if new conflicts found |
| `evaluate-triggers` | Daily 6am | Check lapsed regular, birthday month, anniversary, seasonal return triggers |
| `send-weekly-digest` | Monday 7am | Generate and send weekly digest for all active businesses via Claude API |
| `send-pre-arrival-digest` | Daily 8am | Generate and send pre-arrival digest for returning guests checking in tomorrow |
| `generate-recurring-occurrences` | Daily midnight | Generate next occurrence for all active series within 60-day window; skips closure-blocked dates; sets `source='recurring'`, `occurrence_state='active'` |
| `send-reconfirmation-requests` | Daily 10am | Find recurring occurrences 48h out with `occurrence_state='active'`; send reconfirmation email; set `occurrence_state='pending_reconfirmation'` |
| `send-reconfirmation-reminders` | Daily 10am | Find occurrences 24h out still `pending_reconfirmation`; send reminder; update `reconfirmation_reminder_sent_at` |
| `process-closure-event` | On insert to `closure_events` | Atomically cancel all affected bookings; send correct email copy per closure_type; block calendar; update `affected_booking_count` |
| `expire-waitlist` | Daily 10pm | Mark waitlist entries as expired if preferred_date has passed |

---

## 7. Frontend Structure

No build tooling. No frameworks. Organized as modular vanilla JS files loaded via `<script type="module">`.

```
/public
  /booking
    /[business-slug]
      index.html          ← guest booking page (restaurant or hotel)
  /host
    index.html            ← host stand PWA
  /owner
    index.html            ← owner/manager dashboard
  /admin
    index.html            ← internal Tove admin tools
  /profile
    index.html            ← guest profile management page

/js
  /lib
    supabase.js           ← Supabase client init
    resend.js             ← email dispatch helpers (called from Edge Functions, not browser)
  /booking
    availability.js       ← slot availability logic
    date-picker.js
    time-picker.js
    guest-form.js
    magic-link.js
    contextual-intel.js   ← fetches and displays contextual signal
    confirmation.js
    recurring.js
  /host
    floor-plan.js         ← Konva.js canvas
    reservation-queue.js
    guest-card.js
    manual-booking.js     ← staff manual booking entry modal (phone + walk-in)
    walk-in.js
    waitlist.js
  /owner
    analytics.js
    triggers.js
    broadcast.js
    conflict-alerts.js    ← conflict banner, resolution panel
  /admin
    town-calendar.js
    business-config.js
  /shared
    brand.js              ← applies brand_config to DOM
    api.js                ← Supabase query helpers
    auth.js               ← auth state helpers
    conflict-check.js     ← shared pre-submission conflict detection logic (used by manual-booking.js and booking RPC)

/css
  /base
    reset.css
    typography.css
    tokens.css            ← CSS custom properties for brand theming
  /components
    (per-component stylesheets)
  /pages
    booking.css
    host.css
    owner.css
```

**Brand theming**: The `brand.js` module reads `brand_config` from the business record and sets CSS custom properties on `:root`. All component styles reference these tokens. Swapping a business's brand = one function call.

---

## 8. External API Integrations

### Open-Meteo (weather)
- No API key required
- Endpoint: `https://api.open-meteo.com/v1/forecast`
- Params: lat/long from business address, hourly temperature and weather code
- Cache: 1-hour TTL client-side
- Used to generate patio and weather contextual signals

### Sunrise-Sunset API
- No API key required
- Endpoint: `https://api.sunrise-sunset.org/json`
- Params: lat/long, date
- Cache: per-date, indefinite
- Used for sunset-time contextual signals at patio/waterfront venues

### Ticketmaster API (free tier)
- Endpoint: Discovery API `/events.json`
- Params: latlong, radius, date range
- Cache: 24-hour TTL, stored in a `cached_events` local table or localStorage
- Graceful fallback: if Ticketmaster unavailable, omit events signal

### Claude API (`claude-sonnet-4-6`)
- Used in: weekly digest, pre-arrival digest, re-engagement campaign copy, manual broadcast copy assistance
- All calls are server-side from Edge Functions — API key never in browser
- Async calls only — no synchronous Claude API call blocks a guest-facing UI action

---

## 9. Contextual Intelligence Engine

Runs client-side at booking time. Assembles signals from:
1. Live availability data (Supabase query — scarcity signal)
2. Historical booking data (Supabase query — day busyness)
3. Town calendar events (Supabase query — local events)
4. Open-Meteo (API call, cached)
5. Sunrise-Sunset API (API call, cached by date)
6. Ticketmaster (API call, 24h cache)

Returns the single highest-priority signal as a plain text string. Returns null if no relevant signal. The UI displays the string only if non-null.

Priority order: scarcity → high-demand town event → weather → sunset → local event → day busyness.

---

## 10. Deployment

- **Repository**: GitHub, single repo
- **Hosting**: Vercel, connected to GitHub main branch, auto-deploy on push
- **Environment variables**: set in Vercel dashboard
  - `SUPABASE_URL`
  - `SUPABASE_ANON_KEY` (browser-safe)
  - `SUPABASE_SERVICE_ROLE_KEY` (Edge Functions only, never browser)
  - `RESEND_API_KEY` (Edge Functions only)
  - `CLAUDE_API_KEY` (Edge Functions only)
  - `TICKETMASTER_API_KEY`
- **Supabase**: project hosted on Supabase cloud, Davidson production instance
