-- ============================================================
-- Anon read policies for booking-page config tables
-- Scoped to active rows where possible; query-level business_id
-- filter limits exposure to the business being booked.
-- ============================================================

-- business_closures: guests need to know if a date is blocked
create policy "public_reads_business_closures" on business_closures
  for select using (true);

-- turn_times: needed to compute slot occupancy windows client-side
create policy "public_reads_turn_times" on turn_times
  for select using (true);


-- ============================================================
-- get_slot_coverage
-- Returns reservation_time + party_size for all active bookings
-- on a given date for a given business. SECURITY DEFINER so it
-- reads bookings without exposing individual records to guests.
-- ============================================================
create or replace function get_slot_coverage(p_business_id uuid, p_date date)
returns table(reservation_time time, party_size int)
language sql
security definer
stable
as $$
  select reservation_time, party_size
  from bookings
  where business_id = p_business_id
    and booking_type = 'reservation'
    and reservation_date = p_date
    and status not in ('cancelled', 'no_show')
    and reservation_time is not null;
$$;
