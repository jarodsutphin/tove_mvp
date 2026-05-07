# Tove MVP

Hospitality intelligence and booking platform for independent restaurants and boutique hotels, launching in Davidson, NC.

## Stack
- **Frontend**: Vanilla HTML, CSS, JavaScript — no frameworks, no build tooling
- **Backend**: Supabase (Postgres + RLS + Edge Functions + Auth)
- **Storage**: Supabase Storage (guest profile photos)
- **Deployment**: Vercel via GitHub auto-deploy
- **Email**: Resend
- **AI**: Claude API — `claude-sonnet-4-6`
- **Floor plan**: Konva.js
- **Weather**: Open-Meteo (no API key required)
- **Events**: Ticketmaster API free tier
- **Sunset**: Sunrise-Sunset API (no API key required)

## Key Decisions
- Multi-tenant: all business data isolated by `business_id` via Supabase RLS
- **Guest auth**: Supabase OTP magic link — email is identity, no passwords ever
- **Business auth**: Supabase email/password for staff accounts
- **Guest privacy**: aggregate behavioral signals are cross-platform; venue-specific booking history is never exposed to other businesses
- **Guest photos**: stored in Supabase Storage; visible only to businesses where the guest has a confirmed booking history — enforced via RLS on the storage bucket
- **Host stand**: single device per service — no multi-device real-time sync in MVP
- **Hotel availability**: manual management only, no PMS or channel manager integration
- **Business onboarding**: Tove-team-assisted for MVP, no self-serve UI

## Docs
- `docs/prd.md` — Product Requirements Document
- `docs/architecture.md` — System architecture, Supabase schema, RLS strategy
- `docs/build-plan.md` — Phased build plan
- `docs/risks.md` — Technical risk assessment
- `.bmad/project-brief.md` — One-page project summary

## URLs
- **Vercel**: https://tove-mvp.vercel.app
- **Supabase**: https://zgjtjbwrnfkfjrwfefby.supabase.co
- **GitHub**: https://github.com/jarodsutphin/tove_mvp

## Project Context
- First restaurant target: Davidson, NC (personal network)
- First hotel target: Davidson Village Inn (18 rooms, owner-operated)
- MVP milestone 1: one Davidson restaurant live with booking flow, host stand, guest intelligence card
- MVP milestone 2: Davidson Village Inn live with direct booking flow and arrival dashboard
- College town expansion: one full Davidson academic year before next town rollout
