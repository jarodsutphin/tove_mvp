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
