# Deployment

## 0. Prereqs

- **Supabase CLI** ≥ 1.180 (`npm i -g supabase`)
- **Flutter** ≥ 3.22 (`flutter doctor`)
- **GitHub** repo with these secrets:
  - `SUPABASE_PROJECT_REF`
  - `SUPABASE_ACCESS_TOKEN`
  - `SUPABASE_DB_PASSWORD`
  - `GROQ_API_KEY`
  - `GEMINI_API_KEY`
  - `GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET`
  - `MS_CLIENT_ID` / `MS_CLIENT_SECRET`

## 1. Create the Supabase project

```bash
supabase login
supabase projects create salud-visual --region us-east-1   # free tier
supabase link --project-ref <YOUR_REF>
supabase db push                                            # apply migrations
supabase functions deploy extract-receipt
supabase functions deploy calendar-sync
supabase functions deploy geocode

# Secrets (server-only, never bundled)
supabase secrets set GROQ_API_KEY=...
supabase secrets set GEMINI_API_KEY=...
supabase secrets set GOOGLE_CLIENT_ID=...
supabase secrets set GOOGLE_CLIENT_SECRET=...
supabase secrets set MS_CLIENT_ID=...
supabase secrets set MS_CLIENT_SECRET=...
supabase secrets set MS_TENANT=common
```

## 2. Schedule the calendar sync (free `pg_cron`)

```sql
select cron.schedule(
  'calendar-sync-10min', '*/10 * * * *',
  $$ select net.http_post(
       'https://<REF>.functions.supabase.co/calendar-sync',
       headers => '{"authorization":"Bearer <SERVICE_ROLE_KEY>"}'
     ); $$
);
```

## 3. Build the apps

### Windows portable .exe
```powershell
cd app
flutter config --enable-windows-desktop
flutter build windows --release `
  --dart-define=SUPABASE_URL=https://<REF>.supabase.co `
  --dart-define=SUPABASE_ANON_KEY=<anon>
# Output: build\windows\x64\runner\Release\salud_visual.exe
```
Zip the entire `Release\` folder and ship it — runs on any Windows 10/11
machine. (Optional: package as MSIX for signed install.)

### Android
```powershell
flutter build apk --release `
  --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
```

### Web (free Cloudflare Pages)
```powershell
flutter build web --release `
  --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
npx wrangler pages deploy build\web --project-name salud-visual
```

## 4. OAuth redirect URIs

Add these to Google Cloud Console and Azure AD:

| Platform | Redirect URI |
|---|---|
| Web      | `https://<your-domain>/auth/callback` |
| Desktop  | `http://localhost:54324/auth/callback` |
| Mobile   | `mx.saludvisual.app://auth/callback` |

## 5. Free-tier capacity planning

| Resource | Free limit | When to upgrade |
|---|---|---|
| Postgres DB | 500 MB | ~250 k orders w/ images in Storage, not DB |
| Storage (receipt photos) | 1 GB | move old photos to Cloudflare R2 (also free) |
| MAU (auth) | 50 000 | very generous for a per-clinic SaaS |
| Edge invocations | 500 k/mo | ~16 k/day — comfortably > combined Groq+Gemini quotas |
| Egress | 2 GB/mo | enable on-device caching (already in design) |
