# Backup & restore drill

Run quarterly; archive the result in `docs/incidents/drills/YYYY-Qn.md`.

## Backups

- **Supabase managed**: daily logical backup, retained 7 days on free tier (30 d on Pro). Point-in-time recovery (PITR) on Pro.
- **Off-platform** (recommended once Pro): nightly `pg_dump --format=custom` to an S3 bucket with object lock + KMS encryption.
- **Storage bucket** `receipts`: replicated weekly to a second region.

Verify with:

```bash
supabase db dump --linked --file backup-$(date +%F).sql
```

## Restore drill (every quarter)

1. Spin up a fresh Supabase project (free tier).
2. Apply migrations:
   ```bash
   supabase link --project-ref <staging>
   supabase db push
   ```
3. Restore the most recent dump:
   ```bash
   psql "$STAGING_URL" < backup-YYYY-MM-DD.sql
   ```
4. Run smoke tests:
   - `select count(*) from clients;` matches production ± 1 day delta
   - RLS: log in as a doctor → can only see own clinic
   - Audit log triggers fire on a test insert
5. Time-box: full restore + smoke ≤ **2 hours** (RTO).
6. Data loss tolerance: ≤ **24 hours** (RPO on free tier, ≤ 5 min on Pro PITR).
7. Capture metrics in the drill report.

## Encryption-key rotation drill

1. Generate new key, add to Vault as `pii_encryption_key_v2`.
2. Run `select pii_decrypt(...)` against a sample row — must succeed with old key.
3. Background job: re-encrypt rows in batches of 1 000 with the new key.
4. Promote `v2` to `pii_encryption_key`, retain old as `pii_encryption_key_v1` for 30 days.
