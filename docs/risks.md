# Tove — Technical Risk Assessment

**Version**: 1.0  
**Date**: 2026-05-07

Risks that should be validated or mitigated before committing to the dependent feature build. Ordered by priority — validate the highest-ranked risks first.

---

## Risk 1 — Aggregate Signals RLS Query Performance

**Description**: The RLS policies for `aggregate_signals` and `guest_preferences` authorize access by checking for the existence of a matching booking in the `bookings` table. This means every row-level read runs a subquery against `bookings`. At low volume this is fine. As the platform grows and a single guest has hundreds of bookings, this subquery cost multiplies across every row fetched in a host stand guest card load.

**Likelihood**: Medium — only a problem at scale, but worth getting right early since fixing RLS is a migration  
**Impact**: High — slow guest cards degrade the host stand experience in real service  

**Mitigation**: Create a `guest_business_relationships` join table with `(guest_id, business_id)` pairs, populated and maintained by a Postgres trigger on `bookings` insert/update. Replace the subquery in RLS policies with a direct lookup against this join table. Indexed lookup replaces an aggregating subquery.

```sql
create table guest_business_relationships (
  guest_id    uuid not null references guests(id),
  business_id uuid not null references businesses(id),
  first_booking_at timestamptz not null,
  last_booking_at  timestamptz not null,
  primary key (guest_id, business_id)
);
-- RLS policy becomes:
-- exists (select 1 from guest_business_relationships
--         where guest_id = aggregate_signals.guest_id
--           and business_id = auth_business_id())
```

**Action**: Build with the join table from the start (Phase 0).

---

## Risk 2 — Concurrent Booking Race Condition

**Description**: Two guests completing bookings for the last available slot at the same time. The availability check (read) and booking insert (write) are two separate operations. A naive implementation can double-book a slot.

**Likelihood**: Low at Davidson launch volumes; medium once live and a popular slot fills up  
**Impact**: High — double-booked slot damages trust and requires manual intervention at service

**Mitigation**: Wrap slot availability check and booking insert in a Postgres transaction with a `FOR UPDATE` lock on a slot-level advisory lock, or use a database function that atomically checks and inserts. The booking submission Edge Function (or Supabase RPC) should perform both operations in a single transaction.

```sql
-- Option: use pg_advisory_xact_lock keyed on (business_id, date, time)
-- or use a serializable transaction isolation level on the insert RPC
create or replace function create_booking(...)
returns bookings language plpgsql as $$
begin
  -- Recheck availability inside the transaction
  if (select remaining_covers(...)) < p_party_size then
    raise exception 'slot_full';
  end if;
  insert into bookings (...) values (...) returning *;
end;
$$;
```

**Action**: Implement as an RPC function in Phase 1, not as a client-side insert.

---

## Risk 3 — Konva.js Floor Plan Builder on Tablet

**Description**: The floor plan builder is a drag-and-drop canvas tool that needs to work well on an iPad touchscreen. Konva.js is designed for this but the UX quality depends heavily on touch event handling — pinch-to-zoom, drag handles, tap vs. drag disambiguation — all of which behave differently on touch vs. mouse.

**Likelihood**: High — touch canvas tools are reliably harder than they appear  
**Impact**: Medium — a bad builder experience slows onboarding but doesn't block the booking flow

**Mitigation**: Prototype the floor plan builder on actual iPad hardware (not browser DevTools device simulation) in the first week of Phase 2 before building the full feature. Validate: table drag, tap to select, covers input, section assignment. Adjust touch hit targets (minimum 44px) and touch event handlers before building the service view on top of it.

**Action**: Add "iPad hardware test" as a gating requirement for the Phase 2 floor plan builder milestone.

---

## Risk 4 — Recurring Reservation Series Logic Complexity

**Description**: The recurring series feature involves the most complex domain logic in the product. There are two independent state machines (occurrence states × series states), four distinct closure types each with different email copy and rebook-prompt rules, a reconfirmation flow with reminder logic, an unconfirmed policy that varies per restaurant, a 60-day generation window, and edge cases including double-closure on the same date and confirmed occurrences being overridden. Every path must leave data in a consistent state and trigger the correct email.

**Likelihood**: High — scheduling logic is inherently edge-case-heavy  
**Impact**: Medium-High — bugs affect the most valuable guests on the platform (regulars with standing reservations) and can result in no-shows, phantom bookings, or guests receiving wrong email copy (e.g. a rebook prompt in an emergency closure email)

**State machine**: Fully documented in `docs/recurring-state-machine.md`. This document defines all states, transitions, closure behaviors, reconfirmation flow, unconfirmed policy, generation window logic, and edge cases. It is the implementation contract.

**Occurrence states**: `active`, `pending_reconfirmation`, `confirmed`, `unconfirmed`, `cancelled_by_guest`, `cancelled_by_restaurant`, `cancelled_series`, `completed`

**Series states**: `active`, `paused`, `cancelled`, `business_closed`

**Closure types**: `planned`, `private_event`, `emergency`, `permanent` — each with distinct email copy and rebook-prompt behavior

**Mitigation**:
1. `docs/recurring-state-machine.md` is complete and reviewed before any recurring code is written — enforced as a build plan prerequisite
2. Generate occurrences at most 60 days forward via nightly Edge Function; never pre-generate the full series
3. The `process-closure-event` Edge Function executes all cancellations atomically — no partial closure state possible
4. Before sending any closure email, check `email_log` to avoid duplicate sends (e.g., if both a planned and emergency closure fire on the same date)
5. All four integration tests in `docs/recurring-state-machine.md §10` must pass in staging before the feature is enabled for Davidson clients

**Action**: State machine is documented. Build plan enforces it as a code prerequisite. Validate all four integration tests in staging before enabling for any Davidson client.

---

## Risk 5 — Magic Link Auth UX Latency

**Description**: The returning guest flow requires: enter email → receive magic link email → open email → tap link → return to booking. If email delivery is slow (>30 seconds), or if the guest's browser blocks the magic link redirect back to the in-progress booking, the experience breaks.

**Likelihood**: Medium — email delivery via Supabase Auth + Resend is typically fast, but not guaranteed  
**Impact**: High at the guest-facing booking moment — a confused or interrupted returning guest abandons the booking

**Mitigation**:
1. Use a prominent "Check your inbox — magic link sent" UI state with a countdown and "Resend" button after 30 seconds
2. Encode the in-progress booking state (business slug, selected date/time/party size) in the magic link redirect URL so the guest lands exactly where they left off
3. Set magic link expiry to 10 minutes (longer than default) to reduce re-send frustration
4. Test the full flow on mobile Safari — the most common use case — before launch

**Action**: Build the magic link re-entry flow with booking state preservation in Phase 1.

---

## Risk 6 — Guest Photo Storage and RLS Correctness

**Description**: Guest profile photos are personal and access must be tightly controlled. The storage RLS policy authorizes a business to read a photo based on a join through `guests` → `bookings`. A misconfigured policy could expose photos to unauthorized businesses or block legitimate access at the host stand.

**Likelihood**: Low — Supabase Storage RLS is well-defined — but the join is a non-trivial policy  
**Impact**: High — unauthorized photo access is a privacy violation

**Mitigation**:
1. Test the storage RLS policy explicitly with three scenarios: (a) business with a confirmed booking reads photo — should succeed; (b) business with no booking history reads photo — should fail; (c) guest reads own photo — should succeed
2. Use signed URLs (not public URLs) for photo delivery. Signed URLs are generated server-side and expire (1h TTL is fine for host stand use).
3. If the storage RLS join proves unreliable, fall back to: store photo access authorization in `guest_business_relationships` and gate on that table instead.

**Action**: Validate all three RLS scenarios in Phase 3 before enabling photo upload in the guest booking flow.

---

## Risk 7 — Claude API Latency in the Weekly Digest and Pre-Arrival Digest

**Description**: The weekly digest and pre-arrival digest are generated by Claude API calls inside Edge Functions. A single Claude call can take 5–15 seconds. If an Edge Function times out before the response arrives, the digest is not sent. Supabase Edge Functions have a 150-second wall-clock limit, so a single call is fine, but a function processing 10 businesses in sequence could time out.

**Likelihood**: Medium — scales with number of active businesses  
**Impact**: Low — a missed weekly digest is a nuisance, not a critical failure

**Mitigation**:
1. Fan out digest generation: the scheduled function inserts a job record per business into a `digest_jobs` queue table, then a separate Edge Function (or background task) processes one business at a time
2. Alternatively, use Supabase's `pg_net` extension to fire individual HTTP calls per business in parallel from the scheduler
3. Implement retry logic: if a digest email fails, retry on next daily run before marking as failed

**Action**: Design the weekly digest Edge Function with fan-out from the beginning (Phase 4).

---

## Risk 8 — Hotel Double-Booking Without Channel Manager

**Description**: This is a known and accepted MVP limitation. The hotel manually manages availability in Tove and accepts the OTA double-booking risk. Davidson Village Inn has 18 rooms and limited OTA volume, making this operationally manageable.

**Likelihood**: Low for Davidson Village Inn specifically  
**Impact**: Medium — a double-booked room requires a manual guest resolution conversation

**Mitigation**:
1. Clear onboarding language: "Update your Tove availability calendar any time you receive an OTA booking."
2. Make availability blocking as frictionless as possible — one tap on the calendar to block a date per room type
3. Consider a "quick block" shortcut at the top of the hotel dashboard: "Received an OTA booking? Block a room." — two taps, done

**Action**: Design the availability management UI around the "just got an Airbnb booking, need to block it in Tove" workflow. Validate this with Davidson Village Inn owner before launching.

---

## Risk 9 — Ticketmaster API Free Tier Rate Limits

**Description**: Ticketmaster's free Discovery API tier has rate limits. If the contextual intelligence module makes uncached calls for every booking page load, it will hit the limit quickly once traffic grows.

**Likelihood**: High without mitigation  
**Impact**: Low — Ticketmaster is the lowest-priority signal source; graceful fallback leaves the signal line blank

**Mitigation**:
1. Cache Ticketmaster responses in localStorage with a 24-hour TTL keyed by `(lat, lng, date_range)`
2. Pre-fetch once per day from the `evaluate-triggers` Edge Function and store results in a `cached_town_events` Supabase table — all booking page loads read from the cache, not Ticketmaster directly
3. The contextual intelligence module falls back gracefully (returns null) if Ticketmaster is unavailable or rate-limited

**Action**: Implement server-side Ticketmaster caching in Phase 0 or Phase 1 before traffic starts.
