# Tove — Phased Build Plan

**Version**: 1.1  
**Date**: 2026-05-07  
**First milestone**: One Davidson restaurant live with booking flow, host stand, and guest intelligence card  
**Second milestone**: Davidson Village Inn live with direct booking flow and arrival dashboard

---

## Phase 0 — Foundation (Week 1)

Everything that has to exist before any feature can be built.

**Deliverables:**
- [ ] GitHub repo created, Vercel project connected, auto-deploy on push to main
- [ ] Supabase project created (Davidson production)
- [ ] Full schema applied via SQL migration (`docs/architecture.md §4`), including:
  - `bookings.source` (online/phone/walk_in/ota), `is_override`, `override_reason`, `override_by`, `override_at`
  - `guests.is_incomplete_profile`
  - `guest_business_relationships` table with trigger on bookings insert/update
  - `booking_conflicts` table
- [ ] RLS policies applied and verified, including `guest_business_relationships`
- [ ] Supabase Storage `guest-photos` bucket created, storage RLS policies applied
- [ ] All Edge Function stubs created (body: `return new Response('ok')`), including `generate-recurring-occurrences`, `send-reconfirmation-requests`, `send-reconfirmation-reminders`, `process-closure-event`
- [ ] Environment variables set in Vercel dashboard
- [ ] Base frontend structure created: `/public`, `/js/lib`, `/css/base`
- [ ] `supabase.js` client module initialized with anon key
- [ ] Davidson town record seeded
- [ ] Davidson town calendar events seeded (academic calendar, athletics, local events)
- [ ] One test business record seeded for development

**Done when**: `supabase.from('businesses').select('*')` returns the test business from the browser console on the deployed Vercel URL.

---

## Phase 1 — Restaurant Booking Flow (Weeks 2–4)

**Goal**: A guest can complete a full restaurant reservation on a branded booking page and receive a confirmation email.

**Deliverables:**

*Availability engine*
- [ ] `availability.js`: given a business_id, date, and party_size, returns available time slots
  - Reads `service_periods`, `operating_hours`, `business_closures`, `bookings`
  - Applies max covers per slot, turn times per party size, buffer logic
  - Slots with zero remaining capacity omitted
- [ ] Slot availability rechecked server-side at booking submission (race condition guard via Postgres transaction)

*Guest booking page (`/booking/[business-slug]/`)*
- [ ] Brand config applied to page via `brand.js` on load
- [ ] `date-picker.js`: calendar UI, unavailable dates grayed out, contextual intelligence line shown
- [ ] `time-picker.js`: available slot grid for selected date and party size
- [ ] Guest identity step:
  - New guest: name, email, phone (optional), birthday (optional), dietary restrictions, seating preference, consent checkbox
  - Returning guest: email field → magic link sent → profile pre-populated on return
- [ ] `magic-link.js`: OTP dispatch via Supabase Auth, polling for session, redirect back to in-progress booking with profile loaded
- [ ] Special occasion step: occasion type dropdown, notes field, anniversary date field (conditional)
- [ ] Confirmation page: branded, booking summary, option to add to calendar (ICS link)

*Recurring reservations — prerequisite gate*
- [ ] **`docs/recurring-state-machine.md` reviewed and confirmed complete** — this is a hard gate. No recurring reservation code is written until this check is done. The document defines all occurrence states, series states, closure behaviors, reconfirmation flow, and required integration tests.

*Recurring reservations — booking flow*
- [ ] `recurring.js`: post-booking prompt — "Make this standing?" — frequency selection, confirmation of recurrence terms
- [ ] Booking submission: insert to `recurring_series` with `series_state='active'`, insert first occurrence to `bookings` with `source='recurring'`, `occurrence_state='active'`
- [ ] Recurring series displayed in guest profile management page with cancel/pause controls

*Recurring reservations — occurrence lifecycle*
- [ ] `generate-recurring-occurrences` Edge Function: nightly, generates occurrences within 60-day window per active series; skips dates with `closure_events`; sets `occurrence_state='active'`
- [ ] `send-reconfirmation-requests` Edge Function: daily, finds recurring occurrences 48h out, sends reconfirmation email (`reconfirmation_request`), sets `occurrence_state='pending_reconfirmation'`
- [ ] `send-reconfirmation-reminders` Edge Function: daily, finds occurrences 24h out still `pending_reconfirmation`, sends reminder email (`reconfirmation_reminder`)
- [ ] On no response: nightly scan sets `occurrence_state='unconfirmed'` for overdue `pending_reconfirmation` occurrences
- [ ] Unconfirmed occurrences display with amber indicator and "Awaiting Confirmation" label on host stand queue and guest card
- [ ] Restaurant-configurable unconfirmed policy: `hold_table` or `release_after_cutoff` with configurable minutes (set in business config by Tove team)

*Recurring reservations — closures*
- [ ] Closure type selector on restaurant dashboard: planned, private event, emergency; permanent closure is a separate confirmation flow in settings
- [ ] `process-closure-event` Edge Function fires on `closure_events` insert; atomically cancels all affected bookings; sends correct email per `closure_type` (see `docs/recurring-state-machine.md §5`)
- [ ] Planned and private event closure emails include rebook prompt linking to booking page
- [ ] Emergency closure email: boilerplate only, phone number from business record, no rebook prompt
- [ ] Emergency closure UI: prominent button at top of dashboard and host stand; single confirmation tap; never in a menu
- [ ] Permanent closure: two-step confirmation modal; cancels all future bookings; sets `businesses.active=false`; sets all active series to `series_state='business_closed'`
- [ ] Closure dates immediately blocked in booking calendar after `process-closure-event` runs

*Recurring reservations — cancellations*
- [ ] Guest cancels one occurrence: occurrence → `cancelled_by_guest`; series unchanged; slot released
- [ ] Guest cancels entire series: all future non-terminal occurrences → `cancelled_series`; series → `cancelled`; restaurant notified via dashboard alert + email
- [ ] Restaurant overrides one occurrence: occurrence → `cancelled_by_restaurant`; series unchanged; guest notified per closure type

*Recurring reservations — integration tests (staging gate)*
- [ ] **T1**: Guest cancels one occurrence — series active, next occurrence unaffected, slot released
- [ ] **T2**: Guest cancels entire series — all future occurrences cancelled, restaurant notified
- [ ] **T3**: Restaurant planned closure with active series — occurrence cancelled, `closure_planned` email with rebook link sent, series resumes next date
- [ ] **T4**: Emergency closure — all bookings cancelled, `closure_emergency` email sent (boilerplate + phone, no rebook), calendar blocked

All four T1–T4 tests must pass in staging before recurring reservations are enabled for any Davidson client.

*Email (via Edge Function + Resend)*
- [ ] `send-booking-confirmation` Edge Function: triggers on booking insert, sends branded confirmation email
- [ ] `send-booking-reminder` Edge Function: runs every 5 min, sends 24h reminder to upcoming reservations

*Contextual intelligence*
- [ ] `contextual-intel.js`: assembles and returns single highest-priority signal string
- [ ] Open-Meteo integration (no key, cached 1h)
- [ ] Sunrise-Sunset API integration (cached by date)
- [ ] Town calendar query (Supabase)
- [ ] Scarcity signal (live availability query)
- [ ] Ticketmaster integration (24h cache)

*Manual booking entry — restaurant*
- [ ] "Add Booking" button permanently visible on host stand page and owner dashboard (not in a menu)
- [ ] `manual-booking.js`: modal form — name (required), phone (optional), email (optional), party size (required), date (default today), time slot (available slots only), table (optional, auto-suggest), notes (optional), source (default "phone", changeable to "walk_in")
- [ ] Guest match logic: if phone or email matches existing guest, attach booking; else create lightweight guest record with `is_incomplete_profile = true`
- [ ] Booking submission goes through the same atomic RPC function as online bookings — availability rechecked inside the transaction
- [ ] On success: booking appears in queue and floor view immediately; `guest_business_relationships` updated via trigger
- [ ] Source icon displayed on each reservation queue row (phone icon / walk-in icon)
- [ ] `is_incomplete_profile` flag cleared when the guest later completes a full online booking

*Conflict detection — restaurant*
- [ ] Atomic booking RPC function (`create_booking`): after availability check, also check if adding this booking would create a `covers_exceeded` or `table_double_assigned` conflict; return conflict warning payload rather than inserting if detected
- [ ] Pre-submission conflict warning UI: inline modal showing current vs. max covers, two options — "Choose a different time" or "Override and proceed"
- [ ] Override path: requires non-empty `override_reason` text; sets `is_override = true`, `override_by`, `override_at` on the booking record
- [ ] `scan-booking-conflicts` Edge Function (daily 2:30am): scans all confirmed restaurant bookings within 14 days; inserts new `booking_conflicts` records; skips conflicts already recorded
- [ ] Severity assignment: `detected_at` within 24h of `reservation_date` = critical; within 7 days = urgent; 8–14 days = advisory
- [ ] Conflict alert banner on host stand and owner dashboard: color-coded by highest active severity; hidden when all conflicts resolved
- [ ] Conflict resolution panel: tap banner → shows conflicting bookings side by side → options: cancel A, cancel B, move, dismiss; each updates `booking_conflicts.resolution` and `resolved_at`
- [ ] Conflict alert email (Resend): sent to business owner when nightly scan finds new unresolved conflicts; includes conflict list and direct link to resolution view

**Done when**: A guest can book a table at the test restaurant, receive a confirmation email, receive a 24h reminder, the contextual intelligence line appears on the date picker, and a staff member can enter a phone booking from the host stand that immediately blocks the slot from online availability.

---

## Phase 2 — Host Stand (Weeks 5–8)

**Goal**: A host can use the floor view and reservation queue to run an entire dinner service on a tablet.

**Deliverables:**

*Floor plan builder (setup tool)*
- [ ] Konva.js loaded and initialized on `/host/` in "setup mode"
- [ ] Drag-and-drop table placement on canvas
- [ ] Table configuration panel: label, covers, section
- [ ] Section definitions: main, patio, bar, private
- [ ] Canvas JSON serialized and saved to `floor_plans`
- [ ] Floor plan loaded from `floor_plans` on next session

*Live service view (`/host/`)*
- [ ] Floor diagram rendered from saved Konva canvas
- [ ] Each table node colored by live status (green/yellow/blue/red/gray)
- [ ] Status derived from: tonight's bookings with arrival/seated/vacated timestamps
- [ ] Turn time timer: starts when "Seated" tapped, table turns red when elapsed
- [ ] Patio section toggle (hide/show)
- [ ] Tap table → opens guest card if reserved; opens assign-table prompt if walk-in

*Reservation queue*
- [ ] Tonight's confirmed bookings in time order, alongside the floor diagram
- [ ] Each row: name, party size, time, occasion icon, status badge
- [ ] Status action buttons: Arrived, Seated, No Show
- [ ] Updates write to `bookings.status`, `seated_at`, `vacated_at`
- [ ] Tap row → opens guest card

*Walk-in management*
- [ ] "Add Walk-in" button → modal: name, party size, phone/email optional
- [ ] Auto-suggests available table based on party size and turn time
- [ ] Inserts booking with `source = 'walk_in'` via the manual booking modal
- [ ] If phone/email provided: match or create guest profile

*Waitlist*
- [ ] "Add to Waitlist" button → name, party size, phone or email required
- [ ] Estimated wait calculation from seated table turn timers
- [ ] `waitlist_available` email sent when a suitable table opens (Edge Function)
- [ ] Waitlist status management: notified, booked, expired

**Done when**: A host can run a full dinner service on the tablet — floor view with live status, queue, walk-ins, waitlist — without leaving the page.

---

## Phase 3 — Guest Intelligence Card (Weeks 9–10)

**Goal**: The guest card surfaces the full intelligence profile on tap at the host stand.

**Deliverables:**

*Guest card component (`guest-card.js`)*
- [ ] Profile photo: loaded from Supabase Storage signed URL if `photo_path` is set; placeholder avatar if not
- [ ] Dietary restrictions and allergies: prominent flag at top
- [ ] Seating preference
- [ ] Tonight's special occasion and notes
- [ ] Anniversary date if on file
- [ ] Visit count at this restaurant (count of `bookings` for this business + guest)
- [ ] Last visit date at this restaurant
- [ ] Usual section (most common section across 3+ visits — computed query)
- [ ] Staff notes from previous visits: chronological list with timestamps
- [ ] Add note inline: text input, save button, writes to `staff_notes`
- [ ] Aggregate signals section: dining frequency, typical party size, reliability score, booking style, occasion frequency, platform tenure, recency signal
- [ ] "First visit here" vs. "Returning" label

*Aggregate signals engine*
- [ ] `compute-aggregate-signals` Edge Function (daily): for each guest with recent activity, compute all fields in `aggregate_signals` from their full `bookings` history across all businesses
  - Dining frequency: confirmed + completed restaurant bookings / time span
  - Reliability score: (completed + arrived) / (confirmed - cancelled) across all bookings
  - Booking style: median lead_time_hours < 24 = spontaneous; > 72 = planner
  - Party size: avg and range from all bookings
  - Occasion frequency: bookings with special_occasion set / total bookings per year
  - Recency: last_booking_at < 30 days = active; 30-60 = lapsing; > 60 = lapsed

*Guest photo upload*
- [ ] Post-booking confirmation page: optional photo upload prompt shown after first confirmed booking
- [ ] Photo upload UI: tap to select, preview, confirm; framed as "Help the places you love recognize you"
- [ ] Upload to Supabase Storage at `guest-photos/{guest_id}/profile.jpg`
- [ ] `guests.photo_path` updated on successful upload
- [ ] Guest profile management page (`/profile/`): update or remove photo, update preferences, unsubscribe from communications
- [ ] Profile management link in every confirmation and reminder email footer

**Done when**: Tapping any guest at the host stand surfaces their complete intelligence card including photo, preferences, visit history, staff notes, and all aggregate signals.

---

## Phase 4 — Restaurant Owner Dashboard (Weeks 11–12)

**Goal**: Restaurant owner has a working analytics view and can manage marketing triggers.

**Deliverables:**

*Analytics dashboard*
- [ ] Covers per service period over time (line/bar chart, vanilla JS canvas or lightweight lib)
- [ ] No-show and cancellation rates (rolling 30/60/90 days)
- [ ] New vs. returning guest ratio
- [ ] Peak and slow period heatmap (day of week × time of day)
- [ ] **Booking source breakdown**: covers by source (online/phone/walk_in) as percentage and absolute; trend over time
- [ ] Top guests by visit frequency (list with quick-access guest cards)
- [ ] Lapsed guest list (guests past their usual cadence)

*Marketing triggers*
- [ ] Trigger management UI: list of trigger types, enable/disable, configure each
- [ ] `evaluate-triggers` Edge Function: daily evaluation of all active triggers across all businesses
  - Lapsed regular: compares last booking date to dining_frequency_per_month
  - Birthday month: checks birthday_month 3 weeks out
  - Anniversary: checks stored anniversary dates 3 weeks out
  - Post-visit follow-up: fires 48h after completed booking
  - First visit follow-up: fires 24h after first-ever booking at this business

*Manual broadcast + re-engagement*
- [ ] Segment selector: pre-defined segments from PRD §8.2
- [ ] Manual compose with Claude API copy assistance (async — user sees loading state)
- [ ] Re-engagement campaign: one click → Claude API generates copy → preview → send
- [ ] All outbound emails logged to `email_log`, trigger events logged to `trigger_events`

*Weekly digest*
- [ ] `send-weekly-digest` Edge Function (Monday 7am): for each active business, compile stats, call Claude API, send via Resend

**Done when**: Owner can view their analytics, configure and activate at least three trigger types, and send a manual broadcast.

---

## Phase 5 — Hotel Booking Flow (Weeks 13–15)

**Goal**: Davidson Village Inn can accept direct bookings with working guest intelligence.

**Deliverables:**

*Hotel booking page*
- [ ] Date range picker with availability calendar
- [ ] Room type cards: photography, description, max occupancy, rate per night
- [ ] Guest count selector (adults, children) filtered by room max occupancy
- [ ] Add-on options
- [ ] Guest identity flow (same magic link system as restaurant)
- [ ] Special occasion step
- [ ] Confirmation page and email branded to the hotel
- [ ] Pre-arrival email: `send-hotel-pre-arrival` Edge Function (48h before check-in)

*Hotel availability management*
- [ ] Hotel admin UI: calendar view, click a date to block/unblock per room type
- [ ] Writes to `hotel_availability_blocks`
- [ ] Minimum stay enforcement on date range picker
- [ ] Booking unavailable if any date in range has a block for the selected room type

*Arrival dashboard*
- [ ] Today's and tomorrow's arrivals list
- [ ] Check-in status actions: Arrived, Checked Out, No Show
- [ ] Returning guest flag (stay count > 1)
- [ ] Guest card (same component as restaurant, with hotel-specific history)

*Pre-arrival digest (hotel)*
- [ ] `send-pre-arrival-digest` Edge Function (daily 8am): for each returning guest checking in tomorrow, generate Claude API digest and send to hotel owner

*Manual booking entry and OTA blocks — hotel*
- [ ] "Add Booking" button permanently visible on hotel owner dashboard
- [ ] Hotel manual booking form: room type (required), check-in date (required), check-out date (required), guest name (optional), phone (optional), email (optional), notes (optional), source (phone or ota, selectable)
- [ ] **Quick Block** shortcut: visible on each room type in the availability calendar — tap opens a minimal 3-field form (room type pre-set, check-in, check-out only); source defaults to "ota"; must complete in under 10 seconds
- [ ] On submit: selected dates for that room type removed from online availability immediately
- [ ] OTA icon shown on arrival dashboard entries with `source = 'ota'`; phone icon for `source = 'phone'`
- [ ] Guest match/create logic same as restaurant (is_incomplete_profile when no profile exists)
- [ ] **Booking source breakdown** on hotel owner dashboard: room nights by source (online/phone/ota) as percentage and absolute
- [ ] Hotel conflict detection in `create_booking` RPC: check `room_type_exceeded` conflict before inserting
- [ ] Hotel pre-submission conflict warning: inline modal with room type inventory count (e.g. "3 of 3 king rooms booked for these dates")
- [ ] Override path with required reason, same audit logging as restaurant
- [ ] `scan-booking-conflicts` Edge Function already covers hotel: `room_type_exceeded` conflicts detected in same nightly scan
- [ ] Hotel conflict alert banner on owner dashboard with severity colors
- [ ] Hotel conflict resolution panel: same side-by-side UI as restaurant

**Done when**: Davidson Village Inn can accept a direct booking, enter OTA blocks via quick block in under 10 seconds, manage availability, check guests in and out, receive a pre-arrival digest for returning guests, and see a conflict alert if any room type is double-booked.

---

## Phase 6 — Internal Admin Tools (Week 16)

**Goal**: Tove team can manage town data and business configuration without direct database access.

**Deliverables:**

- [ ] `/admin/` page with Tove-team-only auth guard
- [ ] Town calendar management: CRUD for `town_calendar_events`
- [ ] Business configuration management: edit `businesses` record, brand config, booking rules
- [ ] Business user management: create accounts, assign roles
- [ ] Room inventory management: CRUD for `room_inventory`
- [ ] Restaurant table management: CRUD for `restaurant_tables`

**Done when**: Tove team can fully configure a new business without writing SQL.

---

## Milestone Summary

| Milestone | Phase | Target |
|---|---|---|
| Restaurant MVP live | Phases 0–3 | Booking flow + host stand + guest card |
| Owner dashboard live | Phase 4 | Analytics + triggers + weekly digest |
| Hotel MVP live | Phase 5 | Hotel booking + arrival dashboard |
| Admin tooling complete | Phase 6 | Full internal config without SQL |

---

## What Is Explicitly Not In This Plan

- Self-serve business onboarding (phase 2 — after multi-town expansion begins)
- SMS triggers (phase 2 — Twilio)
- POS integrations (phase 2)
- Multi-device host stand sync (phase 2)
- Hotel channel manager / PMS integration (phase 2)
- Payment processing (phase 2)
- Second college town rollout (after one full Davidson academic year)
