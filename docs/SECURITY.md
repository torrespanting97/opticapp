# Security & Compliance

Salud Visual stores **regulated health data** (prescription history) and
**financial data** (per-client credit ledger). This document captures the
threat model, the concrete controls implemented, and the mapping to common
SaaS compliance frameworks.

> Scope: ISO/IEC 27001:2022 · SOC 2 Type II (Security & Confidentiality TSC) ·
> HIPAA Technical Safeguards (45 CFR §164.312) ·
> GDPR (EU 2016/679) · LFPDPPP (Mexico) · PCI DSS 4.0 SAQ-A
> (we never touch raw card numbers — handled by Stripe).

---

## 1. Threat model (STRIDE)

| Threat | Vector | Mitigation |
|---|---|---|
| **S**poofing | Stolen password, phishing | Supabase Auth + email verification, optional 2FA (TOTP), biometric unlock on mobile, short-lived JWTs (1 h) + refresh-token rotation. |
| **T**ampering | Modified mobile binary, MITM | TLS 1.2+ everywhere, certificate pinning on mobile, code signing on `.exe`/MSIX, integrity check of `extract-receipt` payload (SHA-256 in audit log). |
| **R**epudiation | "I never created that order" | Immutable `audit_log` table (append-only via RLS); every write captures `user_id`, `ip`, `user_agent`, `before`, `after`. |
| **I**nformation disclosure | Stolen DB dump, log leakage | pgcrypto column encryption for `clients.phone`, `clients.street`, `profiles.calendar_refresh`. PII redaction in logs. Storage bucket private + signed URLs (5-min TTL). |
| **D**enial of service | Brute-force, scraper bots | Per-IP + per-user rate limits in `rate_limit` table; login lockout after 5 failures / 15 min; Cloudflare in front of web build. |
| **E**levation of privilege | Role bypass, SQL injection | RLS on every table, **parameterised queries only**, no string concat in edge functions; service-role key only in functions, **never** in client; `security definer` SQL fns drop search_path. |

---

## 2. Control implementation

### 2.1 Identity & access (ISO A.5.16, A.5.17, A.8.5 · SOC 2 CC6 · HIPAA §164.312(a))

| Control | Where |
|---|---|
| Strong password policy (≥ 12 chars, mixed) | Supabase Auth config + Flutter validator |
| MFA (TOTP) | Supabase Auth |
| Email verification before first login | Supabase Auth |
| Short-lived access tokens (1 h) + rotated refresh | Supabase Auth defaults |
| Biometric unlock on mobile (`local_auth`) | `app/lib/core/security/biometric_gate.dart` |
| Role-based access (`owner`/`optometrist`/`promoter`/`receptionist`/`viewer`) | `memberships.role` + RLS |
| Just-in-time clinic switch via signed RPC | `select_clinic()` SQL fn |
| Session expiry on idle (15 min mobile, 30 min desktop) | Flutter `IdleWatcher` |
| Account lockout after 5 failed logins / 15 min | `auth_attempts` table + trigger |

### 2.2 Data protection at rest (ISO A.8.24 · SOC 2 CC6.1 · HIPAA §164.312(a)(2)(iv))

| Field | Method |
|---|---|
| `clients.phone`, `clients.street`, `clients.email` | pgcrypto `pgp_sym_encrypt()` with per-clinic key derived from app secret |
| `profiles.calendar_refresh` (OAuth refresh token) | pgcrypto symmetric, key in Supabase Vault |
| Receipt images | Supabase Storage **private** bucket + 5-min signed URLs; SHA-256 stored in `orders.receipt_sha256` |
| Backups | Daily PITR, AES-256 at rest (Supabase platform) |
| Device-side cache (Drift) | SQLCipher-enabled (`drift` w/ `sqlcipher_flutter_libs`); key in OS keychain via `flutter_secure_storage` |

### 2.3 Data protection in transit (ISO A.8.20 · HIPAA §164.312(e))

- TLS 1.2+ enforced everywhere; HSTS on web build.
- HTTP→HTTPS redirect on Cloudflare Pages.
- Mobile builds pin the Supabase project certificate (`network_security_config.xml` on Android, `NSAppTransportSecurity` on iOS).

### 2.4 Input validation & injection defence (ISO A.8.28 · SOC 2 CC8.1 · OWASP ASVS 4.0)

All untrusted input passes through `supabase/functions/_shared/validate.ts`
(server) **and** `app/lib/core/security/validators.dart` (client).

Defences applied:

| Class | Defence |
|---|---|
| SQL injection | Only `sb.from().eq()` builders or `prepare()`; **no `.rpc()` with raw concat**; `security definer` fns set `search_path = pg_catalog, public`. |
| NoSQL / JSONB injection | JSON parsed via `JSON.parse`, then **whitelist-keyed** before insert. |
| XSS | All Flutter widgets escape by default; HTML/PDF reports run through DOMPurify-equivalent on the rare server-side render. |
| Stored XSS in client name | Strip control chars + length cap 120 + `name` shown via `Text()` (no `Html()`). |
| HTML injection in CSV export | RFC 4180 quoting + leading `=`, `+`, `-`, `@` prefixed with `'` (Excel formula injection). |
| Path traversal | Storage keys constructed server-side as `clinic_id/order_id/uuid.jpg`; client cannot choose path. |
| SSRF (edge fns calling external URLs) | Outbound calls only to hard-coded allow-list (Groq, Gemini, Google, Microsoft, Nominatim). User-supplied URLs are **rejected**. |
| ReDoS | Regexes constant-time and length-capped before match. |
| Unicode normalisation | All text NFKC + zero-width char strip. |
| Image upload | MIME sniffed (magic bytes), max 8 MB, max 4096×4096, re-encoded to JPEG server-side → metadata stripped. |
| File-type smuggling | EXIF stripped on upload via `flutter_image_compress`. |
| Mass-assignment | Whitelist of allowed columns per endpoint; extra keys are dropped. |
| Open redirect | Only same-origin or pre-registered scheme (`mx.saludvisual.app://`). |

### 2.5 Logging, monitoring & audit (ISO A.8.15, A.8.16 · SOC 2 CC7.2 · HIPAA §164.312(b))

- `audit_log` table (see migration 0002) — append-only via RLS, daily partition.
- Captures: `actor`, `action`, `target_table`, `target_id`, `before_jsonb`, `after_jsonb`, `ip`, `ua`, `at`.
- Edge-function logs forwarded to Supabase Logs; **PII redacted** (`__REDACTED__` for phone/email patterns).
- Real-time alert (Supabase Webhook → Slack) on:
  - 5+ failed logins from same IP in 5 min
  - Privilege escalation (`memberships.role` upgrade)
  - Mass export (`> 500` rows in 1 min)
  - Edge-function 5xx rate > 1 %

### 2.6 Backup & recovery (ISO A.8.13 · SOC 2 CC9.1 · HIPAA §164.308(a)(7))

- Supabase daily backups + 7-day PITR (free tier) → 30-day on Pro.
- Quarterly **restore drill** documented in `docs/runbooks/restore-drill.md` (template provided).
- Per-clinic export endpoint (`/functions/v1/export-clinic-data`) for **data portability** (GDPR Art. 20 / LFPDPPP).

### 2.7 Secure development lifecycle (ISO A.8.25–A.8.30 · SOC 2 CC8.1)

- Dependabot weekly PRs (npm, Dart, Deno).
- **CodeQL** scanning workflow (`.github/workflows/codeql.yml`).
- **Gitleaks** secret-scan pre-commit + CI.
- All `.env*` and `env.json` git-ignored; secrets only in Supabase Vault / GitHub Secrets.
- Code review required for `main`; signed commits enforced.

### 2.8 Privacy rights (GDPR Art. 15–22 · LFPDPPP Art. 22–27)

| Right | How |
|---|---|
| Access | Clinic owner exports any client's data via `/clients/:id/export`. |
| Rectification | Standard UI edit. |
| Erasure ("derecho de cancelación") | `delete_client(id)` RPC — anonymises name/phone/email, keeps Rx for the legally required 5 years (NOM-007-SSA3-2011). |
| Objection ("derecho de oposición") | `clients.opted_out boolean` — excludes from analytics & marketing. |
| Portability | JSON export endpoint. |
| Consent record | `consents(client_id, kind, version, given_at, ip)` — stored at first capture. |

### 2.9 Vendor & sub-processor list (SOC 2 CC9.2)

| Vendor | Purpose | Data | Region |
|---|---|---|---|
| Supabase | DB / Auth / Storage / Functions | All | US East |
| Groq | Vision OCR | Receipt image (transient, no retention per policy) | US |
| Google AI (Gemini) | Vision OCR fallback | Receipt image (≤ 24 h cache) | US |
| Google Workspace | Calendar API | Appointment titles + times | US/EU |
| Microsoft Graph | Calendar API | Appointment titles + times | US/EU |
| OpenStreetMap | Map tiles | Pseudonymised lat/lng | EU |
| Cloudflare Pages | Static hosting | None (build artefacts) | Global |
| Stripe | Optional payments | Card data (we never touch it) | US/EU |

A signed Data Processing Agreement (DPA) is on file with each.

---

## 3. Compliance matrix

| Framework | Section | Implemented in |
|---|---|---|
| **ISO 27001:2022** | A.5 Org · A.6 People · A.7 Physical (vendor) · A.8 Tech | this doc · `0002_security.sql` · `_shared/validate.ts` |
| **SOC 2 (Security TSC)** | CC1–CC9 | this doc · `audit_log` · CI |
| **HIPAA Technical Safeguards** | §164.312 (a)(b)(c)(d)(e) | encryption + audit + integrity + access |
| **GDPR** | Art. 5, 25, 32 | minimisation, encryption, breach 72 h |
| **LFPDPPP** (MX) | Arts. 6, 19, 22–27 | aviso de privacidad · ARCO rights |
| **NOM-007-SSA3** (MX) | Retención 5 años de expediente clínico | logical delete only |
| **PCI DSS SAQ-A** | 4.0 | Stripe-hosted fields only |
| **OWASP ASVS 4.0** | L2 baseline | validator + RLS + headers |

---

## 4. Incident response

See `docs/runbooks/incident-response.md`. Highlights:

1. **Detect** — alert via Slack / email.
2. **Triage** — assign Severity 1–4 within 30 min.
3. **Contain** — disable affected user / rotate keys via `supabase secrets set`.
4. **Eradicate & recover** — patch, redeploy, restore from PITR if needed.
5. **Notify** — within 72 h to authority (IFT-INAI in MX) and affected users if PII exposed (LFPDPPP Art. 20).
6. **Post-mortem** — blameless, public for paying clinics.

---

## 5. Responsible disclosure

`/.well-known/security.txt`:

```
Contact: mailto:security@saludvisual.example
Expires: 2027-12-31T23:59:59Z
Preferred-Languages: es, en
Canonical: https://saludvisual.example/.well-known/security.txt
Policy: https://saludvisual.example/security-policy
```
