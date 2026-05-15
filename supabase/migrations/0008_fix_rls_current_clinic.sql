-- Fix: current_clinic() was reading clinic_id from the JWT custom claim,
-- but no custom-claim hook is configured in Supabase Auth, so the claim is
-- always absent and every INSERT/UPDATE on tenant tables fails with RLS 42501.
--
-- New behaviour: prefer the JWT claim when present (forward-compat), fall back
-- to the first membership row for the authenticated user.
create or replace function public.current_clinic()
returns uuid language sql stable as $$
  select coalesce(
    nullif(current_setting('request.jwt.claims', true)::jsonb->>'clinic_id', '')::uuid,
    (select clinic_id from memberships where user_id = auth.uid() limit 1)
  )
$$;
