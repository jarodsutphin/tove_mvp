# Tove — Product Requirements Document

**Version**: 1.1  
**Date**: 2026-05-07  
**Status**: MVP Scope

---

## 1. Product Overview

Tove is a white-label SaaS booking and guest intelligence platform for independent restaurants and boutique hotels in college towns. The guest never sees the Tove brand — they interact with a booking experience skinned entirely to the individual business. Tove powers it invisibly.

**Three core functions:**
1. A fully customizable booking and reservation experience embedded on the business's website
2. A guest intelligence layer that builds rich profiles passively from booking behavior
3. A smart analytics and marketing trigger engine for understanding and re-engaging guests

**Two booking primitives:**
- **Reservation** — restaurants: date, time, party size, table assignment, recurring logic
- **Booking** — hotels: date range, room type, guest details

Both primitives feed the same guest intelligence engine.

**Deployment**: web-based, desktop and mobile browsers, host stand as PWA. No native apps. No push notifications. Email via Resend is the primary communication channel for businesses and guests.

---

## 2. User Roles

| Role | Description | Auth method |
|---|---|---|
| Guest | End user making a reservation or booking | Supabase OTP magic link (email) |
| Host / Front Desk | Staff operating the host stand or arrival dashboard | Supabase email/password |
| Manager / Owner | Business analytics, marketing, and configuration | Supabase email/password |
| Tove Admin | Internal team for onboarding and town data management | Supabase service role (direct DB) |

---

## 3. Branding Architecture

**Three layers, one codebase:**

- **Tove platform**: invisible infrastructure. Never presented to guests.
- **Town brand**: each college town has its own identity. Davidson launch uses Davidson-native language, colors, and visual identity. Each new town gets its own `town_config`.
- **Business brand**: each restaurant or hotel's booking experience is fully skinned. Their typography, photography, and confirmation email voice. Guests feel they are on the business's own product.

Adding a new business = configuration and skinning exercise.  
Adding a new college town = new town config with local calendar and event data.

---

## 4. Experience 1 — Restaurant

### 4.1 Guest Booking Flow

**Entry point**: embedded on the restaurant's website via an iframe or hosted booking page at a Tove subdomain, fully branded to the restaurant.

**Flow steps:**

1. **Date picker**
   - Calendar UI showing available/unavailable dates
   - Contextual intelligence overlay as a single line of text on each date or on the selected date (see §7)
   - Dates within the restaurant's booking window only
   - Dates with no available slots shown as unavailable
   - Same-day booking cutoff enforced

2. **Time slot selection**
   - Available time slots for the selected date based on: covers, turn times, party size, existing bookings, service periods
   - Slot interval configurable per restaurant (default 15 minutes)
   - Unavailable slots grayed out
   - Single contextual intelligence line shown if relevant to the time

3. **Party size selection**
   - Up to the restaurant's configured maximum for online booking
   - Walk-ins for larger parties directed to call

4. **Guest identity**
   - **First-time guest**: short form — first name, last name, email, phone (optional). Dietary restrictions and seating preferences. Birthday month/year (optional). Profile created silently. Consent language displayed.
   - **Returning guest**: enters email only. Magic link sent to inbox. Tapping the link loads their pre-populated profile. Name and preferences pre-filled. Guest confirms or edits before submitting.
   - Guest is never required to create a password.

5. **Special occasion**
   - Optional flag from the restaurant's configured occasion list (anniversary, birthday, proposal, graduation, business dinner, etc.)
   - If anniversary flagged: date field appears and is stored permanently to the guest profile
   - Notes field for additional context

6. **Recurring reservation option**
   - Shown at confirmation step: "Make this a standing reservation?"
   - Frequency options: weekly, monthly
   - Day and time locked to the selected booking
   - Guest reviews recurrence rules before confirming
   - Creates a `recurring_series` record; individual occurrences generated forward

7. **Confirmation**
   - Confirmation page branded to the restaurant
   - Confirmation email sent immediately via Resend, branded to the restaurant
   - 24-hour reminder email scheduled

**Availability engine rules:**
- A time slot is available if: (max covers per slot) - (sum of confirmed party sizes for that slot) >= requested party size
- No-show and cancelled bookings do not count against slot capacity
- Buffer time between seatings applied per-table, not per-slot globally
- Turn time per party size used to determine how long a table is held

### 4.2 Recurring Reservation Logic

Full state machine specification: `docs/recurring-state-machine.md`. That document is the authoritative design reference and must be read before any recurring reservation code is written. This section is the product-level summary.

**Terminology**:
- **Series** — the parent record (`recurring_series`). Owned jointly by guest and restaurant.
- **Occurrence** — a single booking instance linked to the series. Never pre-generated beyond 60 days.

**Occurrence states**: `active` → `pending_reconfirmation` → `confirmed` or `unconfirmed`; or `cancelled_by_guest`, `cancelled_by_restaurant`, `cancelled_series`, `completed`

**Series states**: `active`, `paused`, `cancelled`, `business_closed`

**Reconfirmation (all recurring occurrences)**:
- Reconfirmation email sent 48 hours before each occurrence
- If no response after 24 hours: reminder sent
- If no response at all: occurrence marked `unconfirmed` — not auto-cancelled
- Unconfirmed occurrences flagged on host stand; restaurant's configured policy (hold table or release after cutoff) determines what happens
- Confirming one occurrence does not confirm future ones

**Four closure types** — each triggers automatic cancellation emails and calendar blocking:
1. **Planned closure** — known closure; email includes rebook prompt
2. **Private event** — same behavior as planned; distinct email copy
3. **Emergency closure** — immediate; boilerplate email with phone number only; no rebook prompt; single-tap UI on dashboard and host stand
4. **Permanent closure** — two-step confirmation; cancels all bookings; deactivates account; no rebook prompt; series state → `business_closed`

**Cancellation rules**:
- Guest cancels one occurrence: that occurrence cancelled, series continues unaffected
- Guest cancels series: all future occurrences cancelled, restaurant notified
- Restaurant overrides one occurrence: affected occurrence cancelled, guest notified per closure type, series resumes next scheduled date

**Integration tests required** (must pass in staging before enabling for Davidson clients):
1. Guest cancels one occurrence — series continues, slot released, next occurrence unaffected
2. Guest cancels entire series — all future occurrences cancelled, restaurant notified
3. Restaurant marks date closed — occurrences cancelled, correct email copy sent with rebook link, series resumes
4. Emergency closure — all bookings cancelled, boilerplate email sent with no rebook prompt, calendar blocked immediately

### 4.3 Host Stand — Front of House

The host stand is a single-page PWA optimized for tablet in portrait orientation. No multi-device sync.

**Live floor diagram**

- Visual canvas of the dining room built by the restaurant using Konva.js
- Restaurant configures their own layout during setup: drag and drop tables, set covers per table, label tables, define sections (main, patio, bar, private)
- Floor plan state saved as canvas JSON in `floor_plans` table
- Live status during service, color-coded per table:
  - **Green** — available
  - **Yellow** — reserved, guest not yet arrived
  - **Blue** — seated, turn time timer running
  - **Red** — overdue on expected turn time
  - **Gray** — not in service / deactivated
- Patio and indoor sections toggleable (hide/show patio in bad weather)
- Touch-optimized for tablet; tap a table to open reservation or mark actions

**Reservation queue**

- Tonight's bookings sorted chronologically
- Each entry: guest name, party size, time, special occasion flag (icon), status
- Tap any entry to open the guest card
- Status actions: Arrived, Seated, No Show
- When "Seated" tapped: timer starts for turn time based on party size

**Manual booking entry**

- Prominent **"Add Booking"** button permanently visible on the host stand — never buried in a menu. The host must be able to complete a phone booking in under 15 seconds while on a call.
- Opens a modal with: guest name (required), phone (optional), email (optional), party size (required), date (defaults to today), time slot (shows available slots only), table assignment (optional, auto-suggests), notes (optional), source (defaults to "phone", changeable to "walk_in")
- On submit: booking immediately removes the slot from online availability; if phone or email matches an existing guest profile the booking is attached to that profile; if no match a lightweight guest record is created (name + phone only, flagged as incomplete profile)
- Booking appears in the reservation queue and floor view instantly
- Each booking row displays a source icon: phone icon for phone bookings, walk-in icon for walk-ins

**Walk-in management** (quick path via "Add Booking" with source pre-set to walk_in)

- Auto-suggests available tables based on party size and turn time
- Walk-in data creates or matches a guest profile if contact info provided

**Waitlist**

- Shown when no tables available
- Fields: name, party size, phone or email
- Estimated wait time calculated from turn times of currently seated tables
- Email sent automatically when a table becomes available
- Waitlist entries expire after configurable window

**Guest card**

Accessible by tapping any reservation entry or table on the floor diagram.

Displays:
- Guest name and profile photo (if uploaded)
- Dietary restrictions and allergies — prominently flagged at the top
- Seating preference
- Special occasion tonight and occasion notes
- Anniversary date on file (even if not flagged tonight)
- Visit count at this restaurant
- Last visit date at this restaurant
- Usual section (if a pattern exists across 3+ visits)
- Staff notes from previous visits at this restaurant — persists across visits, visible only to this business
- Dining frequency across platform — "dines out approximately 3× per month" (aggregate signal)
- Typical party size (aggregate signal)
- Reliability score — honor rate across all bookings on platform (aggregate signal)
- Booking style — planner vs. spontaneous (aggregate signal)
- Occasion frequency — flags special occasions often (aggregate signal)
- Platform tenure (aggregate signal)
- First visit here vs. returning

Staff can add a note directly from the guest card. Notes are timestamped and attributed to the staff user.

### 4.4 Restaurant Owner Dashboard

- Prominent **"Add Booking"** button permanently visible — same manual entry form as the host stand
- Business analytics: covers per service period, no-show rate, cancellation rate, new vs. returning guest ratio, peak/slow period patterns, **booking source breakdown** (see §8.5)
- **Conflict alert banner**: red/amber/yellow alert shown prominently when double bookings are detected; tapping opens the conflict resolution view (see §9)
- Top guests by visit frequency, with quick access to guest cards
- Lapsed guest list — guests overdue on their usual cadence
- Marketing trigger management — configure automated triggers (see §8)
- Manual broadcast tool — select guest segment, compose message, send
- Re-engagement campaign — one click targets all guests inactive 60+ days; Claude API writes the copy, owner previews before sending
- Weekly digest email — delivered Monday morning, Claude API generated (see §10)
- Brand and configuration management

### 4.5 Manual Booking Entry — Restaurant

Staff-initiated bookings for phone reservations and walk-ins. Available on both the host stand and the owner dashboard.

**Form fields:**
- Guest name — required
- Phone number — optional; used to match or create guest profile
- Email — optional; used to match or create guest profile
- Party size — required
- Date — required; defaults to today
- Time slot — required; dropdown shows only slots with remaining capacity
- Table assignment — optional; auto-suggests based on party size if left blank
- Notes — optional; pre-populates staff notes on the guest card
- Source — pre-selected as "phone"; changeable to "walk_in"

**On submit behavior:**
- Booking immediately removes that slot from online availability
- If phone or email matches an existing guest profile: booking is attached to that profile
- If no match: lightweight guest record created (name and phone only), flagged as `is_incomplete_profile = true`
- Booking appears in reservation queue and floor view instantly
- Source icon shown on each booking entry in the queue (phone icon or walk-in icon)

**Pre-submission conflict check:**
- If the selected time slot is at or near capacity, show an inline warning before saving (see §9.1 for full conflict warning spec)
- Staff can override with a required reason; override is logged with timestamp and staff session

### 4.6 Restaurant Configuration (Tove-team-assisted for MVP)

Set up directly in the database by the Tove team on behalf of the client.

- Restaurant name, address, phone, website, cuisine type, description
- Brand assets: logo URL, primary color, accent color, hero photography URL
- Operating hours per day of week
- Service periods (lunch, dinner, brunch) with separate hours and slot intervals
- Holiday and closure dates
- Table inventory: label, covers, section
- Floor plan: built by host/owner using the floor plan builder tool
- Turn times per party size range
- Booking rules: advance window, same-day cutoff, max online party size, cancellation notice minimum, no-show policy text
- Confirmation email tone (casual, warm, formal)
- Special occasion options list
- Dietary restriction options list
- Seating preference options list

---

## 5. Experience 2 — Hotel

Tove is not a PMS replacement. It is a direct booking and guest intelligence layer. The hotel keeps their PMS for room operations. Tove handles the guest relationship.

### 5.1 Guest Booking Flow

1. **Date range picker**
   - Calendar showing check-in and check-out dates
   - Availability reflects manually managed blocks in Tove
   - Minimum stay rules enforced
   - Advance booking window enforced
   - Contextual intelligence line shown on calendar (graduation weekend, local events)

2. **Room type selector**
   - Room types with photography, description, max occupancy, and rate per night
   - Available types filtered by selected dates and guest count

3. **Guest count**
   - Adults and children fields
   - Filtered by room type max occupancy

4. **Add-on options**
   - Early check-in, late check-out, room upgrade request (configurable per property)

5. **Guest identity**
   - Same magic link / profile flow as restaurant (see §4.1)

6. **Special occasion**
   - Same flow as restaurant (see §4.1)

7. **Confirmation**
   - Confirmation email immediately, branded to the hotel
   - Pre-arrival email 48 hours before check-in with property details

**Availability note**: Tove manages a manual availability calendar. Hotels can log OTA bookings as manual blocks to keep availability accurate (see §5.5). Double-booking detection alerts the owner if conflicts slip through (see §9).

### 5.2 Front Desk — Arrival Dashboard

- Today's and tomorrow's arrivals sorted by check-in time
- Each entry: guest name, room type, length of stay, special occasion flag, check-in status
- Status actions: Arrived / Checked In, Checked Out, No Show
- Returning guest flagged prominently with stay count

**Guest card at front desk** — same structure as restaurant guest card, adapted for hotel context:
- Profile photo (if uploaded)
- Dietary restrictions / preferences prominently flagged
- Stay history at this property: count, dates, room type pattern
- Special occasion tonight + notes
- Suggested personal touch for this stay (Claude API generated, included in pre-arrival digest)
- Staff notes from previous stays at this property
- Party composition history
- Aggregate behavioral signals from platform
- Room type preference pattern

### 5.3 Hotel Owner Dashboard

- Prominent **"Add Booking"** button for manual phone bookings
- **Conflict alert banner**: red/amber/yellow alert when room conflicts are detected (see §9)
- Occupancy rate by room type over time
- Direct booking rate and estimated commission savings vs. OTA
- **Booking source breakdown** — online vs. phone vs. OTA blocks (see §8.5)
- Returning guest rate
- Average length of stay
- Seasonal demand patterns
- Lapsed guest identification
- Weekly digest (Monday, Claude API)
- Post-stay follow-up automation
- Marketing trigger management

### 5.4 Hotel Configuration (Tove-team-assisted for MVP)

- Property name, address, phone, website, type, description
- Brand assets
- Room inventory: room type, label, description, photography, rate per night, max occupancy
- Availability calendar (manual management UI for hotel staff)
- Check-in / check-out times
- Minimum stay rules
- Cancellation policy text
- Add-on options
- Special occasion options list

### 5.5 Manual Booking Entry — Hotel

Staff-initiated bookings for phone reservations and OTA blocks. Available on the hotel owner dashboard and directly on the availability calendar.

**Full manual booking form** (phone source):
- Room type — required
- Check-in date — required
- Check-out date — required
- Guest name — optional for quick block, required for full booking
- Phone number — optional
- Email — optional
- Notes — optional
- Source — phone or OTA, selectable

**Quick Block shortcut** (one tap on any room type in the calendar):
- Opens a minimal form: room type (pre-set from tap), check-in date, check-out date only
- Source defaults to "ota"
- Must complete in under 10 seconds — three fields, no guest info required
- Labeled with OTA icon in arrival dashboard

**On submit behavior:**
- Selected dates for that room type immediately removed from online availability
- If guest details provided: profile created or matched
- Booking appears in the arrival dashboard
- OTA blocks labeled with OTA icon; phone bookings with phone icon

**Pre-submission conflict check:**
- If the selected room type is fully booked for those dates, show an inline warning before saving (see §9.2 for full conflict warning spec)
- Staff can override with a required reason; override logged

---

## 6. Experience 3 — Guest

The guest never sees Tove. They see the restaurant or hotel brand throughout.

### 6.1 Guest Profile and Recognition

**First-time guest:**
- Completes booking form (name, email, optional phone, optional birthday)
- Consent language shown: *"Tove saves your dining and stay preferences to help the places you love take better care of you. We'll occasionally send you reminders and offers from businesses you've visited. Your visit history at individual businesses is never shared with others. You can update your preferences or unsubscribe anytime."*
- Profile created silently; guest receives a confirmation email
- After their first confirmed booking, guest receives an optional prompt to upload a profile photo

**Returning guest:**
- Enters email on the booking page
- Magic link sent to inbox; tap loads their profile with preferences pre-populated
- Name, dietary restrictions, seating preferences pre-filled on the booking form
- Only someone with access to the email inbox can access the profile

**Guest profile photo (optional):**
- Prompted after first confirmed booking, never before
- Framed as: *"Add a photo so the places you love can recognize you when you arrive."*
- Stored in Supabase Storage in a private bucket
- Accessible only to businesses where the guest has at least one confirmed booking
- RLS enforced at the storage bucket level
- Displayed on the guest card in the host stand and front desk views
- Included in the pre-arrival digest sent to the business
- Guest can update or remove at any time from a profile management link in any confirmation or reminder email
- Photo upload never blocks or delays booking completion

### 6.2 Guest Data

**Explicitly collected at first booking:**
- First and last name, email, phone (optional), birthday month/year (optional)
- Dietary restrictions and allergies
- Seating preferences (patio, booth, bar, quiet corner, etc.)
- Communication opt-in

**Collected at each booking:**
- Special occasion type and notes
- Anniversary date (if flagged — stored permanently)
- Guest notes to the restaurant or hotel
- Party composition (hotel: adults, children)
- Add-on selections (hotel)

**Passively captured per booking:**
- Booking timestamp: day of week, time of day
- Lead time from booking to visit
- Device type
- Whether a marketing trigger drove the booking
- Whether guest rebooked after previous visit
- Cancellation and no-show events

**Aggregate behavioral signals (cross-platform, anonymized):**
- Dining / stay frequency (approximate bookings per month or year)
- Typical party size (average and range)
- Lead time pattern (planner vs. spontaneous)
- Daypart preference
- Occasion frequency
- Reliability score (honor rate across all bookings)
- Seasonal patterns
- Engagement pattern (trigger-responsive vs. organic)
- Platform tenure
- Recency signal (active, lapsing, lapsed)

### 6.3 Cross-Platform Privacy Rules

Business B sees about a shared guest:
- Aggregate behavioral signals (frequency, party size, reliability, booking style, etc.)
- Their own booking history with that guest
- Their own staff notes for that guest

Business B never sees:
- That the guest has visited Business A
- How often the guest visits Business A
- Business A's staff notes
- Any venue-specific data from Business A

These rules are enforced at the database level via RLS, not application logic alone.

---

## 7. Contextual Intelligence Layer

Surfaced as a single clean line of text on the date picker or time selector in the guest booking flow. Never a dashboard. Disappears if nothing relevant. Never more than one signal at a time. Priority order determines which signal shows when multiple apply.

**Signal sources:**
| Source | API / Data | Cost |
|---|---|---|
| Weather forecast | Open-Meteo | Free, no key |
| Davidson College academic calendar | Town calendar (manual seed) | Free |
| Davidson town events | Town calendar (manual seed) | Free |
| Charlotte area school breaks | Town calendar (manual seed) | Free |
| Athletics schedules | Town calendar (manual seed) | Free |
| Local events | Ticketmaster API free tier | Free tier |
| Sunset time | Sunrise-Sunset API | Free, no key |
| Scarcity signal | Live availability data | Internal |
| Day busyness | Historical booking data | Internal |

**Signal priority (highest first):**
1. Scarcity — "Only 2 tables remaining this Friday"
2. High-demand town event — "Davidson graduation weekend — book early"
3. Weather (patio-relevant venues) — "74° and clear — patio seating available tonight"
4. Sunset (waterfront / patio venues) — "Sunset at 7:44pm — perfect for waterfront dining"
5. Local event awareness — "Panthers home game tonight"
6. Day busyness from history — shown only if no higher-priority signal

Signal is displayed for the restaurant's date/time context only. Hotel shows signals on date range picker.

---

## 8. Marketing and Analytics

### 8.1 Automated Triggers (set once, run forever)

| Trigger type | Logic |
|---|---|
| Lapsed regular | Guest hasn't booked in longer than their usual cadence |
| Birthday month | Email with offer 3 weeks before birthday month |
| Anniversary | Email 3 weeks before stored anniversary date |
| Weather | Ideal patio conditions match guest's historical patio preference |
| Seasonal return | Visited last [month], it's [month] again |
| Post-visit follow-up | 48 hours after visit, soft rebook prompt |
| First visit follow-up | 24 hours after first visit, convert first-timer to regular |

Triggers are evaluated by a Supabase Edge Function on a daily schedule. Each trigger fires at most once per guest per trigger type per configurable cool-down window.

### 8.2 Manual Broadcasts

- Owner selects a guest segment and composes a message (or uses Claude API to generate copy)
- Available segments: all active guests, top regulars, lapsed 30/60/90 days, occasion guests, first timers who haven't returned, patio regulars, birthday month, anniversary month
- Delivery via Resend

### 8.3 Re-engagement Campaign

- One click from the owner dashboard
- Claude API generates personalized re-engagement email copy based on business context
- Owner previews and edits before sending
- Targets all guests inactive 60+ days at that business

### 8.4 Marketing Trigger Conversion Tracking

- Each outbound trigger email includes a tracked booking link
- When a booking is created with a `marketing_trigger_id`, the trigger event is marked converted
- Conversion rate shown per trigger type in the owner dashboard

### 8.5 Booking Source Breakdown

Shown in both restaurant and hotel analytics dashboards.

- Percentage of covers (restaurant) or room nights (hotel) from each source: online, phone, walk_in, ota
- Trend over time — is online booking share growing?
- A restaurant where 80%+ of bookings are still by phone is a candidate for coaching on how to drive guests to book online
- This data is also useful to Tove internally as a sales signal

---

## 9. Double Booking Detection and Alerts

### 9.1 Conflict Detection Logic

**Restaurant — a conflict exists when:**
- The sum of confirmed party sizes in a time slot exceeds the maximum covers for that slot
- A specific table is assigned to more than one booking at the same time (accounting for turn time)
- A manually entered booking overlaps a slot that was already fully booked

**Hotel — a conflict exists when:**
- The count of confirmed bookings for a given room type on a given date exceeds the inventory count for that room type
- A manually entered OTA block overlaps dates already confirmed for the same room type

**When detection runs:**
- On every manual booking submission — check before confirming the entry
- On every online booking submission — checked atomically inside the RPC function before insert
- Nightly at 2:30am — a `scan-booking-conflicts` Edge Function scans all upcoming bookings within 14 days and inserts any found conflicts into `booking_conflicts`

### 9.2 Pre-Submission Warning UI

**Restaurant warning:**

> "Warning — this time slot is at capacity. Adding this booking will exceed your cover limit for [time]. Current covers: 38 of 40. Do you want to proceed or choose a different time?"

Two options:
- **Choose a different time** (recommended, highlighted)
- **Override and proceed** — requires a brief reason text; override logged with timestamp and staff session

**Hotel warning:**

> "Warning — [Room Type] is fully booked for [dates]. Adding this booking will exceed your room inventory. Current bookings: 3 of 3 king rooms. Do you want to proceed or adjust dates?"

Same two options and override logging.

### 9.3 Post-Detection Alert UI

When the nightly scan finds a conflict (or one slips through at submission), a persistent alert banner appears on the relevant dashboard and host stand:

**Restaurant:**
> "Conflict detected — [Date] at [Time] is overbooked by [X] covers. Review and resolve before service."

**Hotel:**
> "Room conflict detected — [Room Type] is double-booked for [Date Range]. Review and resolve."

Tapping the banner opens a conflict resolution panel showing the two conflicting bookings side by side with three resolution options:
- Cancel booking A
- Cancel booking B
- Move one to a different time / date
- Dismiss and handle manually (logged)

### 9.4 Conflict Severity

| Severity | Condition | Display color |
|---|---|---|
| Critical | Conflict is within 24 hours | Red banner |
| Urgent | Conflict is within 7 days | Amber banner |
| Advisory | Conflict is 8–14 days out | Yellow banner |

### 9.5 Nightly Conflict Scan Email

If the nightly scan detects any new conflicts not previously flagged, the business owner receives an email via Resend with:
- List of conflicts found (date/time, parties involved)
- Severity level for each
- Direct link to the conflict resolution view in their dashboard

---

## 10. Email Communications

All emails delivered via Resend. All guest-facing emails branded to the individual business (logo, colors, voice).

| Email | Recipient | Trigger | Generated by |
|---|---|---|---|
| Booking confirmation | Guest | Immediately on booking | Template + business branding |
| 24h reminder | Guest | Day before reservation | Template |
| 48h pre-arrival | Hotel guest | 2 days before check-in | Template |
| Recurring series cancelled (one occurrence) | Guest | Restaurant blocks a date | Template |
| Waitlist — table available | Guest | Table opens up | Template |
| Marketing trigger | Guest | Automated trigger fires | Claude API |
| Re-engagement campaign | Guest | Owner initiates | Claude API |
| Pre-arrival digest | Business | 24h before returning guest | Claude API |
| Weekly digest | Business owner | Monday morning | Claude API |
| Conflict alert | Business owner | Nightly scan finds new conflicts | Template |

**Pre-arrival digest** content (generated by Claude API, delivered to business):
- Guest name and profile photo (if uploaded)
- Profile summary
- Visit / stay history at this property
- Preferences and patterns
- Special occasion flags
- Suggested personal touch for this specific visit

**Weekly digest** content (generated by Claude API):
- 3-5 most important numbers from the week
- Lapsed regulars flagged by name
- One weather or event correlation insight if relevant
- One recommended action for the coming week
- Marketing trigger performance summary

---

## 11. Internal Admin Tools (Tove team only)

These are internal-only, not visible to businesses or guests.

- **Town calendar management**: create and edit town calendar events (event name, type, date range, impact level, notes)
- **Business configuration**: create and edit business records, brand config, booking rules
- **Business user management**: create staff accounts, assign roles
- **Room and table inventory**: seed room inventory and restaurant table configurations

Self-serve business onboarding is a phase two feature.

---

## 12. Out of Scope for MVP

- Native iOS or Android app
- Push notifications (email only)
- Payment processing or deposit collection
- SMS triggers (phase two via Twilio)
- POS integrations
- Self-serve business onboarding UI
- Multi-device real-time sync at host stand
- Hotel channel manager / PMS integration
- Consumer-facing aggregator or discovery app
- Multi-property hotel chains
- OTA channel management
- Appointment scheduling or non-hospitality verticals
