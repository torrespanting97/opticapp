// appointment-remind — SUPERSEDED
//
// Reminders are now handled by the Python notify service /remind endpoint,
// called by pg_cron every 30 min (see 0006_notify_service.sql).
//
// This stub is kept so existing cron entries don't 404 during migration.

import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { json, securityHeaders } from "../_shared/validate.ts";

serve((_req) =>
  json(
    { ok: true, note: "Reminders are handled by the Python notify service." },
    200,
  ),
);
