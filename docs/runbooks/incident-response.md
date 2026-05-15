# Incident response runbook

Severity tiers and target times (ISO 27035, NIST 800-61):

| Sev | Definition                                         | Detect→Triage | Containment | Disclosure |
|-----|----------------------------------------------------|---------------|-------------|------------|
| S1  | Confirmed PHI breach / RCE / data loss             | 15 min        | 1 h         | 72 h (GDPR/LFPDPPP) |
| S2  | Auth bypass, privilege escalation, prolonged DoS   | 30 min        | 4 h         | as required |
| S3  | Limited scope vulnerability, no exploitation       | 4 h           | 7 d         | optional |
| S4  | Cosmetic / informational                           | next biz day  | 30 d        | none |

## On-call roles

- **Incident Commander** — owns the bridge, time-boxes the response.
- **Tech Lead** — drives investigation and remediation.
- **Comms** — drafts customer, regulator (INAI/GDPR DPA), and internal notices.
- **Scribe** — captures every action with UTC timestamps in `docs/incidents/YYYY-MM-DD-<slug>.md`.

## Step-by-step

1. **Acknowledge** the alert in `#sec-ops` within the SLA above.
2. **Open the incident channel** `#inc-YYYY-MM-DD-<slug>`, page roles.
3. **Snapshot evidence** — Supabase logs, edge function logs, audit_log rows, traffic captures. Copy to a write-once S3 bucket with object lock.
4. **Contain** — rotate suspected keys/tokens (Supabase, Groq, Gemini, Google/MS OAuth), revoke sessions via `update sessions set revoked_at = now()`, block IPs at Cloudflare.
5. **Eradicate** — patch root cause, run `0002_security.sql` constraints in `EXPLAIN` mode to confirm no bypass, redeploy.
6. **Recover** — restore from PITR if data was corrupted (`docs/runbooks/restore-drill.md`).
7. **Notify**:
   - Affected users within 72 h (GDPR Art. 33 / LFPDPPP §20).
   - INAI (MX) and the lead EU DPA if PHI was exposed.
   - Customers per contract.
8. **Post-mortem** — blameless write-up within 5 business days. Update threat model in `docs/SECURITY.md`.

## Useful queries

```sql
-- Recent failed logins per IP
select ip, count(*) from auth_attempts
  where at > now() - interval '1 hour' and not succeeded
  group by ip order by count desc;

-- All exports of client data in the past 24 h
select * from audit_log
  where action = 'export' and at > now() - interval '24 hours';

-- Force-logout everyone in a clinic
update sessions set revoked_at = now()
  where user_id in (
    select user_id from memberships where clinic_id = '<uuid>'
  );
```
