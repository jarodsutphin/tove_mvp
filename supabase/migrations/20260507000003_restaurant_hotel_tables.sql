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
  blocked_end_date  date not null,
  source            text not null default 'manual'
    check (source in ('manual','ota','phone','tove_booking')),
  reason            text,
  created_at        timestamptz not null default now(),
  check (blocked_end_date >= blocked_date)
);
