# Architecture

## 1. Topology

```
                ┌──────────────────────────────────────────────────────┐
                │              FLUTTER CLIENT (one codebase)            │
                │   Android · iOS · Windows.exe · macOS · Linux · Web   │
                │                                                       │
                │  Riverpod state · Drift (SQLite offline) · Outbox     │
                └──────────────┬───────────────────────────────────────┘
                               │  HTTPS + JWT
                               ▼
       ┌────────────────────────────────────────────────────────────────┐
       │                       SUPABASE (free tier)                      │
       │                                                                 │
       │  ┌─────────┐  ┌──────────┐  ┌──────────┐  ┌───────────────┐    │
       │  │  Auth   │  │ Postgres │  │  Storage │  │ Edge Functions│    │
       │  │ (email, │  │  + RLS   │  │ (receipt │  │   (Deno)      │    │
       │  │  OAuth) │  │          │  │  images) │  │               │    │
       │  └─────────┘  └──────────┘  └──────────┘  └──────┬────────┘    │
       └────────────────────────────────────────────────────┼───────────┘
                                                            │
        ┌───────────────────────────────────────────────────┼─────────────┐
        ▼                          ▼                        ▼             ▼
   Groq (Llama-4)          Gemini 2.5 Flash         Google Calendar  MS Graph
   vision OCR              vision OCR fallback      (per-doctor      (Outlook)
                                                    OAuth)
                                                            ▲
                                                            │
                                                       Nominatim
                                                       (geocoding)
                                                            ▲
                                                            │
                                                       MapLibre GL
                                                       + OSM tiles
```

## 2. Authentication

- **Supabase Auth** with email + password and Google OAuth.
- One **`profiles`** row per user, linked to one or more **`clinics`** via **`memberships(role)`**.
- The mobile and the desktop `.exe` share the same login: when a host signs in on the phone *and* the laptop, both clients receive the same `clinic_id` claims and see the same data live (Supabase Realtime).
- A *portable mode* is shipped as a single signed `.exe` (`flutter build windows` → `msix` optional) — opens, prompts login, syncs.

## 3. Multi-tenant isolation (RLS)

Every business table has a `clinic_id uuid not null`. The RLS policy template:

```sql
create policy "tenant read"   on <table> for select  using (clinic_id = current_clinic());
create policy "tenant insert" on <table> for insert  with check (clinic_id = current_clinic());
create policy "tenant update" on <table> for update  using (clinic_id = current_clinic());
```

`current_clinic()` is a `security definer` SQL function that reads the JWT claim `clinic_id` set on login (or via a clinic-switch RPC for users belonging to multiple clinics).

## 4. Offline-first

1. **Drift** holds a full mirror of *current clinic* data on device.
2. Mutations are written locally and pushed to a **`outbox`** table.
3. A background isolate flushes the outbox to Supabase whenever connectivity returns (mirrors the queue pattern already in the HTML template).
4. On reconnect, Supabase Realtime streams changes back to all clients.

## 5. AI receipt extraction (Edge Function)

`POST /functions/v1/extract-receipt`

```jsonc
{
  "image_base64": "...",     // JPEG/PNG/WEBP/HEIC
  "mime": "image/jpeg",
  "provider": "groq" | "gemini",   // optional — default: groq, fallback gemini
  "model": "..."             // optional
}
```

Returns the **exact** JSON schema defined in `docs/AI_PROMPT.md`
(matches every field of the existing HTML form so the Nueva-Orden screen
can be filled with one click).

API keys live in Supabase secrets, never on the client.

## 6. Calendar sync (Edge Function)

`POST /functions/v1/calendar-sync`

- Each `profiles` row stores `calendar_provider` (`google` | `outlook` | `none`) and an encrypted refresh token (`profiles.calendar_refresh`).
- The function:
  1. exchanges the refresh token for an access token,
  2. pulls upcoming events into `appointments`,
  3. pushes locally-created `appointments` into the provider,
  4. uses ETags / `updatedMin` for incremental sync (free quota-friendly).
- Triggered on demand from the app **and** by a Postgres `pg_cron` job every 10 min.

## 7. Coverage map

- Client addresses are geocoded **once** on insert by the `geocode` edge function, which calls Nominatim and caches results in `geocode_cache(query, lat, lng)`.
- The Flutter map screen renders pins with `flutter_map` + MapLibre style; debt-colored markers; cluster by zoom.
- A *service-area* polygon can be drawn by the host; the map highlights clients inside vs. outside.

## 8. Reporting

- All reports (the green/navy "Reporte Cliente" in the HTML) are rendered in Flutter using the same layout, then exported via the `printing` package → PDF / printer.
- Server-side scheduled aggregates land in `stats_daily` (materialised view refreshed by `pg_cron`).

## 9. Payments & wallet

- `wallet_ledger(client_id, kind, amount, ref_order_id, ts)` — append-only.
- `kind` ∈ `{order_charge, payment_cash, payment_transfer, payment_stripe, adjustment, refund}`.
- Per-client balance = `sum(amount)` (charges +, payments −).
- Optional **Stripe Connect** payment links per order; webhook → ledger row.

## 10. Security checklist

- All AI keys / Stripe / Calendar secrets in **Supabase Vault**, never bundled in the app.
- HTTPS everywhere; cert pinning on mobile.
- Refresh-token rotation; biometric unlock on mobile (`local_auth`).
- PII export & delete endpoints (LFPDPPP / GDPR readiness).
