# Tove — Recurring Reservation State Machine

**Version**: 1.0  
**Date**: 2026-05-07  
**Status**: Design complete — must be reviewed before any recurring reservation code is written  
**Prerequisite for**: Phase 1 recurring reservation implementation

---

## 1. Terminology

| Term | Definition |
|---|---|
| **Series** | The parent recurring reservation. Owned jointly by guest and restaurant. One record in `recurring_series`. |
| **Occurrence** | A single instance of a series on a specific date. Stored as an individual `bookings` record linked to the series via `series_id`. |
| **Affected occurrence** | A single occurrence that is cancelled while the parent series remains active. |
| **Generation window** | Occurrences are generated no more than 60 days forward by the nightly Edge Function. The full series is never pre-generated. |

---

## 2. Occurrence States

```
active
  │
  ├─── 48h before ────────────────► pending_reconfirmation
  │                                        │
  │                                   guest confirms ──► confirmed
  │                                        │
  │                                   no response 24h later (reminder sent)
  │                                        │
  │                                   no response at all ──► unconfirmed (NOT auto-cancelled)
  │
  ├─── guest cancels this occurrence ─────────────────────► cancelled_by_guest
  │
  ├─── restaurant blocks/closes this date ────────────────► cancelled_by_restaurant
  │
  ├─── entire series cancelled ───────────────────────────► cancelled_series
  │
  └─── date passes ───────────────────────────────────────► completed
```

| State | Description |
|---|---|
| `active` | Confirmed upcoming occurrence; reconfirmation not yet sent |
| `pending_reconfirmation` | Reconfirmation email sent 48h before; awaiting guest response |
| `confirmed` | Guest explicitly reconfirmed; no further action needed |
| `unconfirmed` | Guest did not respond to reconfirmation by time of reservation. **Not auto-cancelled.** Flagged visually on host stand. Restaurant's configured policy determines whether to hold or release the table. |
| `cancelled_by_guest` | Guest cancelled this occurrence only; series remains active |
| `cancelled_by_restaurant` | Restaurant cancelled this occurrence via closure or override; series remains active |
| `cancelled_series` | Entire series cancelled; this occurrence is part of the cancellation |
| `completed` | Occurrence date has passed |

---

## 3. Series States

| State | Description |
|---|---|
| `active` | Series running normally; occurrences generating within the 60-day window |
| `paused` | Temporarily paused by guest; no occurrences generating; resumes on guest action |
| `cancelled` | Permanently ended by guest or restaurant; no future occurrences generate |
| `business_closed` | Business marked permanently closed; all future occurrences cancelled; series state terminal |

---

## 4. State Transition Rules

### Occurrence transitions

| Trigger | From state | To state | Series effect |
|---|---|---|---|
| Nightly Edge Function generates occurrence | — | `active` | No change |
| 48h before date, reconfirmation sent | `active` | `pending_reconfirmation` | No change |
| Guest confirms via email link | `pending_reconfirmation` | `confirmed` | No change |
| 24h passes with no response | `pending_reconfirmation` | `pending_reconfirmation` (reminder sent) | No change |
| Guest never responds | `pending_reconfirmation` | `unconfirmed` | No change |
| Guest cancels single occurrence | `active`, `pending_reconfirmation`, `confirmed` | `cancelled_by_guest` | Series stays `active` |
| Restaurant marks date closed | `active`, `pending_reconfirmation`, `confirmed` | `cancelled_by_restaurant` | Series stays `active` |
| Restaurant emergency closure | any non-terminal state | `cancelled_by_restaurant` | Series stays `active` |
| Restaurant permanent closure | any non-terminal state | `cancelled_by_restaurant` | Series → `business_closed` |
| Guest cancels entire series | any non-terminal state | `cancelled_series` | Series → `cancelled` |
| Restaurant cancels series | any non-terminal state | `cancelled_series` | Series → `cancelled` |
| Date passes | any non-terminal state | `completed` | No change |

### Series transitions

| Trigger | From state | To state |
|---|---|---|
| Guest pauses series | `active` | `paused` |
| Guest resumes series | `paused` | `active` |
| Guest cancels series | `active`, `paused` | `cancelled` |
| Restaurant cancels series | `active`, `paused` | `cancelled` |
| Business permanent closure | `active`, `paused` | `business_closed` |

**Terminal states** (no transitions out): `cancelled`, `business_closed`, `completed`, `cancelled_by_guest`, `cancelled_by_restaurant`, `cancelled_series`

---

## 5. Closure Types

### 5.1 Planned Closure

Restaurant marks a specific date as closed in advance (holiday, renovation, staff event).

**Triggers**: Staff creates a `closure_events` record with `closure_type = 'planned'`

**Behavior**:
1. `process-closure-event` Edge Function fires immediately
2. All occurrences on that date → `cancelled_by_restaurant`
3. All one-time bookings on that date → `cancelled`
4. Email to all affected guests: *"[Restaurant Name] will be closed on [Date]. We look forward to seeing you again soon — click here to find your next available time."* (includes rebook link)
5. Series states unchanged — all affected series resume on next scheduled date
6. Closure date immediately blocked in booking calendar — no new bookings accepted
7. `affected_booking_count` written to `closure_events` record

**Email type**: `closure_planned`

---

### 5.2 Private Event Closure

Restaurant blocks a date for a private event.

**Triggers**: Staff creates a `closure_events` record with `closure_type = 'private_event'`

**Behavior**: Identical to Planned Closure in all technical respects.

**Email copy differs**: *"[Restaurant Name] is fully reserved for a private event on [Date]. We hope to see you soon — click here to find your next available time."* (includes rebook link)

**Email type**: `closure_private_event`

---

### 5.3 Emergency Closure

Restaurant triggers an unplanned same-day or immediate closure (illness, equipment failure, weather).

**Triggers**: Staff taps the emergency closure button on the dashboard or host stand. Requires one confirmation tap. Fires immediately on confirm.

**Behavior**:
1. All bookings for that date cancelled immediately — recurring and one-time
2. `occurrence_state` of affected occurrences → `cancelled_by_restaurant`
3. Email to all affected guests with boilerplate copy only: *"Due to an unforeseen circumstance, [Restaurant Name] will be closed on [Date]. Please call us directly at [phone] for more information."*
4. Phone number pulled from `businesses.phone`
5. **No rebook prompt** — restaurant does not know when they will reopen
6. Calendar blocked immediately
7. Series states unchanged — series resumes next scheduled date

**Email type**: `closure_emergency`

**UI requirement**: Emergency closure button is always visible at the top of the dashboard and host stand. Must complete in a single confirmation tap. Never buried in a menu.

---

### 5.4 Permanent Closure

Restaurant marks themselves as permanently closed.

**Triggers**: Staff selects "Permanently Close Business" from dashboard settings. Requires an explicit confirmation step: *"Are you sure? This will cancel all upcoming bookings and cannot be undone."* Two-step confirmation.

**Behavior**:
1. All future confirmed bookings cancelled — recurring and one-time
2. All `occurrence_state` values set to `cancelled_by_restaurant`
3. All `recurring_series.series_state` set to `business_closed`
4. Email to all affected guests: *"[Restaurant Name] will be permanently closing. We're grateful for your support and hope to have served you well."* No rebook prompt.
5. Business account deactivated — `businesses.active = false`
6. No new bookings accepted; calendar shows as permanently closed
7. Guest profiles retained with the business relationship marked inactive in `guest_business_relationships`

**Email type**: `closure_permanent`

---

## 6. Reconfirmation Flow

All recurring reservation occurrences require guest reconfirmation 48 hours before the scheduled date.

```
T-48h  ─── reconfirmation email sent ──► occurrence_state: pending_reconfirmation
               (reconfirmation_sent_at populated)

T-24h  ─── if still pending_reconfirmation:
           │   reminder email sent ──► (reconfirmation_reminder_sent_at populated)
           │   occurrence_state stays: pending_reconfirmation

T-0    ─── if still pending_reconfirmation:
           └── occurrence_state → unconfirmed
               (NOT cancelled — host decides based on configured policy)
```

**If guest confirms at any point**: `occurrence_state → confirmed`, `confirmed_at` populated. No further reconfirmation action for this occurrence.

**Reconfirmation email content**:
- Booking details: date, time, party size, restaurant name
- Single prominent confirm button
- Cancel this occurrence link
- Cancel entire series link

**Reconfirmation scope**: per-occurrence only. Confirming one occurrence does not confirm future occurrences.

---

## 7. Unconfirmed Occurrence Policy

The restaurant configures what happens when a guest doesn't respond to reconfirmation. Set in `businesses.unconfirmed_booking_policy`.

| Policy | Behavior |
|---|---|
| `hold_table` | Table held for the full turn time. Host sees `unconfirmed` flag on guest card and queue entry. |
| `release_after_cutoff` | Table released `businesses.unconfirmed_release_cutoff_minutes` before reservation time. Slot becomes available for walk-ins. Occurrence state stays `unconfirmed` — not cancelled. |

In both cases, unconfirmed occurrences are visually distinct on the host stand (amber indicator, "Awaiting Confirmation" label).

---

## 8. Cancellation Behaviors Summary

### Guest cancels a single occurrence
- Occurrence: `cancelled_by_guest`
- Series: no change, remains `active`
- Slot: released to online availability immediately
- Restaurant: sees cancellation in queue and floor view immediately
- Email to restaurant: notification (existing booking status update, no new email type needed)

### Guest cancels entire series
- All future non-terminal occurrences: `cancelled_series`
- Series: `cancelled`
- All future slots: released to online availability
- Restaurant: dashboard alert + email notification
- Email to restaurant: *"[Guest name] has cancelled their standing reservation. All future occurrences have been removed."*

### Restaurant overrides a single occurrence
- Occurrence: `cancelled_by_restaurant`
- Series: no change, remains `active`
- Guest: receives appropriate closure email based on `closure_type`
- Series resumes on next scheduled date automatically

---

## 9. Generation Window

The `generate-recurring-occurrences` Edge Function runs nightly at midnight.

**Logic per active series**:
1. Find the latest generated occurrence date (`last_generated_at` on `recurring_series`)
2. Calculate the next occurrence date(s) within the 60-day forward window
3. For each date in the window:
   - Skip if a `closure_events` record exists for that date at this business
   - Skip if an occurrence already exists for this `(series_id, reservation_date)`
   - Insert a new `bookings` record with:
     - `source = 'recurring'`
     - `series_id` set
     - `occurrence_state = 'active'`
     - `status = 'confirmed'`
4. Update `recurring_series.last_generated_at`

**Never generates occurrences for series in `paused`, `cancelled`, or `business_closed` states.**

---

## 10. Required Integration Tests

All four tests must pass in staging before recurring reservations are enabled for Davidson clients.

| Test | Setup | Expected outcome |
|---|---|---|
| **T1** — Guest cancels one occurrence | Active series with 4 future occurrences | Cancelled occurrence: `cancelled_by_guest`. Series: `active`. Next occurrence: `active`. Slot released. Remaining 3 occurrences unaffected. |
| **T2** — Guest cancels entire series | Active series with 4 future occurrences | All 4 occurrences: `cancelled_series`. Series: `cancelled`. All slots released. Restaurant receives notification. |
| **T3** — Restaurant marks date closed (planned) | Active series; occurrence exists on the closure date | Occurrence: `cancelled_by_restaurant`. Series: `active`. Guest receives `closure_planned` email with rebook link. Series resumes on next date. Calendar blocks the date. |
| **T4** — Emergency closure triggered | 3 bookings on today's date (1 recurring, 2 one-time) | All 3 cancelled. `closure_emergency` email sent to all 3 guests — boilerplate copy, phone number, no rebook prompt. Calendar blocked. Nightly scan runs the next night, series for the recurring booking remains `active`. |

---

## 11. Edge Cases

| Scenario | Behavior |
|---|---|
| Guest reconfirms after reminder but before T-0 | `occurrence_state → confirmed`; no further emails for this occurrence |
| Restaurant blocks a date that has no series occurrence | Normal closure behavior; no series-specific logic runs |
| Series `end_date` passes | Nightly generator finds no dates to generate; series effectively ends naturally without state change — occurrences are just not created |
| Guest tries to rebook a cancelled series | Series state is `cancelled`; no new occurrences generate; guest must create a new series |
| Business closure date overlaps a series occurrence that is already `confirmed` | Occurrence still cancelled; `confirmed_at` is retained for historical record but `occurrence_state` overwritten to `cancelled_by_restaurant` |
| Two closure events on the same date (e.g. planned already exists, then emergency triggered) | Emergency closure wins; existing planned cancellation emails already sent; emergency email suppressed for guests already notified (check `email_log` before sending) |
