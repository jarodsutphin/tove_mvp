-- ============================================================
-- HELPER FUNCTIONS
-- ============================================================
create or replace function auth_business_id()
returns uuid language sql stable as $$
  select business_id from business_users where user_id = auth.uid() limit 1;
$$;

create or replace function auth_guest_id()
returns uuid language sql stable as $$
  select id from guests where auth_user_id = auth.uid() limit 1;
$$;


-- ============================================================
-- RLS — TOWNS (read-only, public)
-- ============================================================
alter table towns enable row level security;

create policy "anyone_reads_towns" on towns
  for select using (true);

alter table town_calendar_events enable row level security;

create policy "anyone_reads_town_calendar" on town_calendar_events
  for select using (true);


-- ============================================================
-- RLS — BUSINESSES
-- ============================================================
alter table businesses enable row level security;

create policy "business_users_read_own_business" on businesses
  for select using (id = auth_business_id());

create policy "public_reads_active_businesses" on businesses
  for select using (active = true);


-- ============================================================
-- RLS — BUSINESS_USERS
-- ============================================================
alter table business_users enable row level security;

create policy "users_read_own_membership" on business_users
  for select using (user_id = auth.uid());


-- ============================================================
-- RLS — BUSINESS CONFIG TABLES (service_periods, operating_hours,
--        business_closures, restaurant_tables, floor_plans,
--        turn_times, room_inventory, hotel_availability_blocks)
-- ============================================================
alter table service_periods enable row level security;

create policy "business_users_read_own_service_periods" on service_periods
  for select using (business_id = auth_business_id());

create policy "business_users_write_own_service_periods" on service_periods
  for all using (business_id = auth_business_id());

create policy "public_reads_active_service_periods" on service_periods
  for select using (active = true);

alter table operating_hours enable row level security;

create policy "business_users_read_own_hours" on operating_hours
  for select using (business_id = auth_business_id());

create policy "business_users_write_own_hours" on operating_hours
  for all using (business_id = auth_business_id());

create policy "public_reads_operating_hours" on operating_hours
  for select using (true);

alter table business_closures enable row level security;

create policy "business_users_read_own_closures" on business_closures
  for select using (business_id = auth_business_id());

create policy "business_users_write_own_closures" on business_closures
  for all using (business_id = auth_business_id());

alter table restaurant_tables enable row level security;

create policy "business_users_read_own_tables" on restaurant_tables
  for select using (business_id = auth_business_id());

create policy "business_users_write_own_tables" on restaurant_tables
  for all using (business_id = auth_business_id());

create policy "public_reads_active_tables" on restaurant_tables
  for select using (active = true);

alter table floor_plans enable row level security;

create policy "business_users_read_own_floor_plans" on floor_plans
  for select using (business_id = auth_business_id());

create policy "business_users_write_own_floor_plans" on floor_plans
  for all using (business_id = auth_business_id());

alter table turn_times enable row level security;

create policy "business_users_read_own_turn_times" on turn_times
  for select using (business_id = auth_business_id());

create policy "business_users_write_own_turn_times" on turn_times
  for all using (business_id = auth_business_id());

alter table room_inventory enable row level security;

create policy "business_users_read_own_rooms" on room_inventory
  for select using (business_id = auth_business_id());

create policy "business_users_write_own_rooms" on room_inventory
  for all using (business_id = auth_business_id());

create policy "public_reads_active_rooms" on room_inventory
  for select using (active = true);

alter table hotel_availability_blocks enable row level security;

create policy "business_users_read_own_blocks" on hotel_availability_blocks
  for select using (business_id = auth_business_id());

create policy "business_users_write_own_blocks" on hotel_availability_blocks
  for all using (business_id = auth_business_id());


-- ============================================================
-- RLS — GUESTS
-- ============================================================
alter table guests enable row level security;

create policy "guests_read_own" on guests
  for select using (auth_user_id = auth.uid());

create policy "guests_update_own" on guests
  for update using (auth_user_id = auth.uid());

create policy "business_reads_own_guests" on guests
  for select using (
    exists (
      select 1 from guest_business_relationships gbr
      where gbr.guest_id = guests.id
        and gbr.business_id = auth_business_id()
    )
  );


-- ============================================================
-- RLS — GUEST_PREFERENCES
-- ============================================================
alter table guest_preferences enable row level security;

create policy "guests_read_own_prefs" on guest_preferences
  for select using (guest_id = auth_guest_id());

create policy "guests_write_own_prefs" on guest_preferences
  for all using (guest_id = auth_guest_id());

create policy "business_reads_guest_prefs" on guest_preferences
  for select using (
    exists (
      select 1 from guest_business_relationships gbr
      where gbr.guest_id = guest_preferences.guest_id
        and gbr.business_id = auth_business_id()
    )
  );


-- ============================================================
-- RLS — RECURRING_SERIES
-- ============================================================
alter table recurring_series enable row level security;

create policy "guests_read_own_series" on recurring_series
  for select using (guest_id = auth_guest_id());

create policy "guests_write_own_series" on recurring_series
  for all using (guest_id = auth_guest_id());

create policy "business_reads_own_series" on recurring_series
  for select using (business_id = auth_business_id());

create policy "business_writes_own_series" on recurring_series
  for all using (business_id = auth_business_id());


-- ============================================================
-- RLS — BOOKINGS
-- ============================================================
alter table bookings enable row level security;

create policy "business_reads_own_bookings" on bookings
  for select using (business_id = auth_business_id());

create policy "business_writes_own_bookings" on bookings
  for all using (business_id = auth_business_id());

create policy "guests_read_own_bookings" on bookings
  for select using (guest_id = auth_guest_id());

create policy "guests_cancel_own_bookings" on bookings
  for update using (
    guest_id = auth_guest_id()
    and status = 'confirmed'
  );


-- ============================================================
-- RLS — STAFF_NOTES
-- ============================================================
alter table staff_notes enable row level security;

create policy "business_users_staff_notes" on staff_notes
  for all using (business_id = auth_business_id());


-- ============================================================
-- RLS — WAITLIST
-- ============================================================
alter table waitlist enable row level security;

create policy "business_users_read_waitlist" on waitlist
  for select using (business_id = auth_business_id());

create policy "business_users_write_waitlist" on waitlist
  for all using (business_id = auth_business_id());


-- ============================================================
-- RLS — MARKETING_TRIGGERS
-- ============================================================
alter table marketing_triggers enable row level security;

create policy "business_users_read_triggers" on marketing_triggers
  for select using (business_id = auth_business_id());

create policy "business_users_write_triggers" on marketing_triggers
  for all using (business_id = auth_business_id());


-- ============================================================
-- RLS — TRIGGER_EVENTS
-- ============================================================
alter table trigger_events enable row level security;

create policy "business_users_read_trigger_events" on trigger_events
  for select using (business_id = auth_business_id());


-- ============================================================
-- RLS — EMAIL_LOG
-- ============================================================
alter table email_log enable row level security;

create policy "business_users_read_email_log" on email_log
  for select using (business_id = auth_business_id());


-- ============================================================
-- RLS — AGGREGATE_SIGNALS
-- ============================================================
alter table aggregate_signals enable row level security;

create policy "guests_read_own_signals" on aggregate_signals
  for select using (guest_id = auth_guest_id());

create policy "business_reads_guest_signals" on aggregate_signals
  for select using (
    exists (
      select 1 from guest_business_relationships gbr
      where gbr.guest_id = aggregate_signals.guest_id
        and gbr.business_id = auth_business_id()
    )
  );


-- ============================================================
-- RLS — GUEST_BUSINESS_RELATIONSHIPS
-- ============================================================
alter table guest_business_relationships enable row level security;

create policy "business_reads_own_gbr" on guest_business_relationships
  for select using (business_id = auth_business_id());

create policy "guests_read_own_gbr" on guest_business_relationships
  for select using (guest_id = auth_guest_id());


-- ============================================================
-- RLS — BOOKING_CONFLICTS
-- ============================================================
alter table booking_conflicts enable row level security;

create policy "business_users_read_conflicts" on booking_conflicts
  for select using (business_id = auth_business_id());

create policy "business_users_write_conflicts" on booking_conflicts
  for all using (business_id = auth_business_id());


-- ============================================================
-- RLS — CLOSURE_EVENTS
-- ============================================================
alter table closure_events enable row level security;

create policy "business_users_read_closures" on closure_events
  for select using (business_id = auth_business_id());

create policy "business_users_write_closures" on closure_events
  for all using (business_id = auth_business_id());
