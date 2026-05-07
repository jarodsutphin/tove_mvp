# Tove — Project Brief

**One-paragraph summary**: Tove is a white-label SaaS booking and guest intelligence platform for independent restaurants and boutique hotels in college towns, launching in Davidson, NC. The guest never sees the Tove brand — they book through a fully branded experience powered invisibly by Tove. The platform captures behavioral signals from every booking and surfaces them to the business as a rich guest intelligence layer: dietary restrictions, preferences, visit history, staff notes, and cross-platform behavioral signals like reliability score and dining frequency. A marketing trigger engine lets businesses re-engage their best customers automatically. Built on vanilla HTML/CSS/JS, Supabase, and Vercel.

---

## Target Clients

| Client | Type | Status |
|---|---|---|
| Davidson restaurant (TBD) | Restaurant | First target — personal network |
| Davidson Village Inn | Hotel | Second target — 18 rooms, owner-operated |

---

## Two Primitives

**Reservation** (restaurants): date, time, party size, table, recurring logic  
**Booking** (hotels): date range, room type, guest details

Both feed the same guest intelligence engine.

---

## Three User Faces

1. **Guest** — books via branded page, never sees Tove, recognized silently on return via magic link
2. **Host / Front Desk** — tablet PWA with live floor view (restaurant) or arrival dashboard (hotel), guest card on tap
3. **Owner / Manager** — analytics, marketing triggers, weekly Claude digest, brand management

---

## Stack

- Frontend: Vanilla HTML/CSS/JS — no frameworks
- Backend: Supabase (Postgres + RLS + Edge Functions + Auth + Storage)
- Deployment: Vercel
- Email: Resend
- AI: Claude API (`claude-sonnet-4-6`)
- Floor plan: Konva.js

---

## Build Sequence

| Phase | Focus | Milestone |
|---|---|---|
| 0 | Foundation, schema, seed data | Deployed + Supabase live |
| 1 | Restaurant booking flow | Guest can book, receives email |
| 2 | Host stand | Floor view, queue, walk-ins, waitlist |
| 3 | Guest intelligence card | Full card with photo + signals |
| 4 | Owner dashboard | Analytics + triggers + digest |
| 5 | Hotel booking flow | Hotel MVP live |
| 6 | Internal admin tools | Full config without SQL |

---

## Top Risks

1. RLS subquery performance on aggregate signals → mitigate with `guest_business_relationships` join table
2. Concurrent booking race condition → mitigate with atomic RPC function
3. Konva.js touch UX on iPad → validate on hardware before building full feature
4. Recurring series state complexity → document state machine before coding
5. Magic link auth latency → preserve booking state in redirect URL

---

## What Is Not Being Built in MVP

- Native apps, push notifications, payments, SMS, POS integrations
- Self-serve onboarding, multi-device sync, hotel channel manager
- Consumer aggregator, multi-property chains, OTA management
