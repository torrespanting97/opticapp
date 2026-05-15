# 👁️ Salud Visual — Optometry SaaS

A medium-to-large-scale, **$0/month** SaaS for optometrists & optical shops.
One codebase → **iOS, Android, Windows `.exe`, macOS, Linux, Web** — login from the host’s account so the same user gets a portable mobile app for in-house visits and a desktop console for reporting.

## ✨ Core features

### 🧑‍⚕️ Clinical
- **Client (patient) records** — full demographics, address, photo, signature.
- **Historical lens prescriptions** — every `Rx` (ESF/CYL/EJE/ADD, DIP, ALT, ADD) is versioned with date; auto-diff vs. previous Rx (myopia progression, astigmatism drift, presbyopia onset).
- **Glasses used** — armazón model, color, measurements (aro/puente/varilla), material (CR-39 / Policarbonato / Hi-Index), treatments (AR / AR Blue / Fotocromático), date dispensed.
- **AI receipt scanner** — photograph a hand-written Orden de Pedido → Groq Llama-4 (primary) or Gemini 2.5 Flash (fallback) extracts every field into a structured form for review. Template-aware prompt (already in `docs/AI_PROMPT.md`).
- **Auto-generated client report** — gauges (myopia / astigmatism severity), face-shape → frame recommendation, lens-type SVG visualization, printable in carta (US Letter) format.
- **Medical flags** — diabetes / hypertension banner on every screen of the file.

### 💳 Financial
- **Per-client wallet & credit tracking** — every order generates a ledger: cost / down-payment / debt / weekly payment plan.
- **Aging report** — who owes how much, days overdue, suggested next contact date.
- **Payment recording** — cash, transfer, Stripe Connect link (optional, pay-per-transaction).
- **Daily / monthly / per-promoter statistics** — gross, net, by lab, by municipality.

### 📅 Appointments
- **Two-way Google Calendar** sync (Google Identity OAuth, free).
- **Two-way Outlook / Microsoft 365** sync via Microsoft Graph (free).
- **Host preference** — each doctor picks Google *or* Outlook in settings; clinics with multiple optometrists each have their own calendar.
- **In-app schedule** with day / week / month views, drag-to-reschedule, SMS / WhatsApp reminders (optional Twilio).
- **Walk-in queue** for in-shop traffic.

### 🗺️ Coverage map
- **MapLibre GL** + OpenStreetMap tiles (free, no key).
- **Nominatim** geocoding of `calle + colonia + municipio` → pins.
- **Heat-map of clients** with debt color-coded (green = paid, yellow = < 500, red = ≥ 500 MXN).
- **Service-area polygon** — quickly see which municipios you cover; spot growth gaps.

### 📊 In-house management
- **Lab orders** dashboard (Indigo / Optimarket / Optikal MTY / FED), folio-lab tracking, micas / bisel / maquila costs.
- **Promoter performance** (BH / AM / JR / VR / MG / LM / SL / CP).
- **Stock-light** module for frames (optional).
- **CSV / Excel export** for the accountant.

### 🔐 Multi-tenant
- Every row has `clinic_id`; **Postgres Row-Level Security** enforces isolation.
- A *host* (clinic owner) invites optometrists & promoters by email; the **same login works on phone + .exe**.
- Roles: `owner`, `optometrist`, `promoter`, `receptionist`, `viewer`.

## 🧱 Stack & free-tier limits

| Layer | Tech | Free tier ceiling |
|---|---|---|
| Client (all platforms) | **Flutter 3.x** | — |
| State | Riverpod 2 | — |
| Local DB / offline | **Drift** (SQLite) + outbox queue | — |
| Backend | **Supabase** | 500 MB DB · 1 GB storage · 50k MAU · 2 GB egress |
| Edge functions | Deno / Supabase Functions | 500 k invocations / mo |
| AI vision | **Groq** (Llama 4 Scout / Maverick) | ~14 400 req/day |
| AI fallback | **Gemini 2.5 Flash** | 1 500 req/day |
| Maps | **MapLibre GL** + OSM tiles | unlimited fair-use |
| Geocoding | **Nominatim** (self-host or `nominatim.openstreetmap.org`) | 1 req/sec public |
| Calendar | Google Calendar API + Microsoft Graph | free |
| Payments | Stripe Connect | pay-per-txn (no fixed) |
| CI/CD | GitHub Actions | 2 000 min/mo |
| Web landing | Cloudflare Pages | unlimited |

> **Total fixed monthly cost: USD $0** until you grow past ~50 k monthly active users.

## 🗂️ Repository layout

```
opitc_app/
├── app/                        # Flutter project (mobile + desktop + web)
│   ├── lib/
│   │   ├── main.dart
│   │   ├── app.dart
│   │   ├── core/               # theme, router, supabase client, env
│   │   ├── features/
│   │   │   ├── auth/
│   │   │   ├── clients/
│   │   │   ├── orders/         # ← Orden de Pedido (Nueva tab)
│   │   │   ├── prescriptions/  # Rx history & report
│   │   │   ├── scanner/        # AI photo → fields
│   │   │   ├── appointments/   # Google + Outlook
│   │   │   ├── wallet/         # credit/debt ledger
│   │   │   ├── map/            # coverage map
│   │   │   └── stats/          # dashboards
│   │   └── data/
│   ├── pubspec.yaml
│   └── windows/ macos/ linux/ android/ ios/ web/
├── supabase/
│   ├── migrations/             # SQL schema + RLS
│   ├── functions/
│   │   ├── extract-receipt/    # Groq + Gemini OCR proxy
│   │   ├── calendar-sync/      # Google + Outlook sync
│   │   └── geocode/            # Nominatim proxy w/ cache
│   └── config.toml
├── docs/
│   ├── ARCHITECTURE.md
│   ├── DATA_MODEL.md
│   ├── AI_PROMPT.md            # the template-aware extraction prompt
│   ├── DEPLOY.md
│   └── ROADMAP.md
└── .github/workflows/
    ├── flutter-build.yml       # builds .apk, .ipa, .exe, web
    └── supabase-deploy.yml
```

## 🚀 Quick start

```powershell
# 1. Backend
cd supabase
supabase start                  # local Postgres + Auth
supabase db reset               # apply migrations + seed
supabase functions serve

# 2. App (Windows .exe)
cd ..\app
flutter pub get
flutter run -d windows

# 3. App (Android)
flutter run -d <device>
```

See **`docs/DEPLOY.md`** for production deployment (Supabase Cloud + Cloudflare Pages + GitHub Actions).
