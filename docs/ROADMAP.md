# Roadmap

> Status as of this iteration — see `docs/ARCHITECTURE.md` and `app/lib/**` for
> the shipped code, and `db/migrations/` + Supabase project `rcldmmanvvtkkrbwpkgk`
> for the live backend.

## Phase 1 — MVP (4–6 weeks)
- [x] Schema + RLS multi-tenant
- [x] Edge functions: `extract-receipt`, `geocode`, `calendar-sync`
- [x] Flutter shell (mobile + Windows)
- [x] Login + clinic onboarding (`signup_screen.dart`, RPC `create_clinic`)
- [x] Nueva Orden — full form parity with HTML template (`new_order_screen.dart`)
- [x] Save to Supabase + offline outbox (`data/outbox.dart`, wired in `orders_repo`)
- [x] AI scanner end-to-end (Groq → form fill via `extractedReceiptProvider`)
- [x] Cliente search + Rx history list (`clients_screen.dart`, `client_detail_screen.dart`)
- [x] Reporte cliente (PDF via `printing`, `report_screen.dart`)

## Phase 2 — Clinical depth (4 weeks)
- [x] Rx diff between visits (OD/OI ESF progression `CustomPaint` chart in report)
- [x] Face-shape → recommended frame chip set (`recommendation_engine.dart`)
- [x] Lens recommendation engine from Rx (material / design / AR / photochromic)
- [ ] Frame inventory (light) — barcode scan with `mobile_scanner`

## Phase 3 — Financial & ops (4 weeks)
- [x] Wallet ledger UI + per-client statement (`wallet_screen.dart`, `client_statement_screen.dart`)
- [ ] Stripe Connect payment links (optional)
- [ ] Aging report + WhatsApp reminders (Twilio free trial)
- [ ] Promoter performance dashboard

## Phase 4 — Appointments & maps (3 weeks)
- [ ] Google Calendar OAuth flow
- [ ] Microsoft Graph OAuth flow
- [x] Two-way sync UI + manual trigger (`appointments_screen.dart` → `calendar-sync` edge fn)
- [x] Coverage map with circle layer fed by `client_balances` (`coverage_map_screen.dart`)
- [ ] Walk-in queue (in-shop)

## Phase 5 — Polish & growth
- [x] Spanish + English i18n scaffolding (`core/i18n.dart`)
- [ ] Role-based UI (owner / promoter sees less) — owner-only gate done for audit
- [x] Biometric unlock on mobile (`core/security/biometric_gate.dart`)
- [x] Audit log + viewer screen (`features/audit/audit_log_screen.dart`, RLS owner-only)
- [ ] Backup / export ZIP
- [ ] PWA installer for the web build
- [ ] MSIX-signed Windows installer

## Stretch — additional optometrist tooling
- Pupillary distance from selfie (MediaPipe FaceMesh — runs on-device, free)
- Snellen / Ishihara test screens for tablet-assisted triage
- Patient self-check-in QR
- Bulk lens-order export to lab portal (Indigo / FED)

## Live infra checklist

| Item | Status |
|---|---|
| Supabase project `rcldmmanvvtkkrbwpkgk` | live |
| Migrations `0001_init` … `0005_advisor_fixes` | applied |
| Migration `0006_rpcs` (`next_order_folio`, `create_clinic`) | applied |
| RLS on every public table | enforced |
| `audit_log` monthly partitions | created |
| Advisor security findings | all addressed |
