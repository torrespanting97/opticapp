-- ════════════════════════════════════════════════════════════════════
-- 0004_appointments_enhance.sql
-- • oauth_states: temp table for PKCE OAuth handshake
-- • appointments: reminder-sent flags
-- ════════════════════════════════════════════════════════════════════

-- ── OAuth PKCE handshake state ─────────────────────────────────────
create table if not exists oauth_states (
  state          text        primary key,
  user_id        uuid        not null references auth.users(id) on delete cascade,
  provider       text        not null check (provider in ('google','outlook')),
  code_verifier  text        not null,
  expires_at     timestamptz not null default (now() + interval '10 minutes'),
  created_at     timestamptz          default now()
);
-- Only the row owner can read (edge functions use service role)
alter table oauth_states enable row level security;
create policy "oauth_states_self" on oauth_states
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ── Reminder tracking columns ──────────────────────────────────────
alter table appointments
  add column if not exists reminder_24h_sent boolean default false,
  add column if not exists reminder_1h_sent  boolean default false;
