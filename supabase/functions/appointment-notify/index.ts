// appointment-notify — SUPERSEDED
//
// WhatsApp + email notifications are now handled by the Python notify
// service (notify_service/) via a pg_net trigger (0006_notify_service.sql).
//
// This stub is kept so existing invocations don't 404.
// It returns a 200 with a redirect hint and does nothing else.

import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { json, securityHeaders } from "../_shared/validate.ts";

const cors = {
  "access-control-allow-origin":  "*",
  "access-control-allow-headers": "authorization, x-client-info, apikey, content-type",
  "access-control-allow-methods": "POST, OPTIONS",
};

serve((req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: { ...securityHeaders, ...cors } });
  return json(
    { ok: true, note: "Notifications are handled by the Python notify service via DB trigger." },
    200,
    cors,
  );
});
