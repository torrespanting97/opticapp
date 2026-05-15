// Supabase Edge Function — geocode  (hardened)
// POST { query } -> { ok, cached, lat, lng }
//
// Security controls:
//   • JWT required
//   • Rate-limit 30/min/IP, 500/h/JWT  (Nominatim courtesy)
//   • Query sanitised to printable Latin-1 + diacritics, ≤ 200 chars
//   • Cache lookup before remote call
//   • Outbound URL pinned to nominatim.openstreetmap.org (no SSRF surface)

import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { v, json, errorResponse, rateLimit, clientIp, securityHeaders } from "../_shared/validate.ts";

const cors = {
  "access-control-allow-origin":  "*",
  "access-control-allow-headers": "authorization, x-client-info, apikey, content-type",
  "access-control-allow-methods": "POST, OPTIONS",
};

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: { ...securityHeaders, ...cors } });
  if (req.method !== "POST")    return json({ error_code: "method", message: "POST only" }, 405, cors);

  try {
    const jwt = req.headers.get("authorization")?.replace(/^Bearer\s+/i, "");
    if (!jwt) return json({ error_code: "auth", message: "JWT required" }, 401, cors);

    const sbUrl   = Deno.env.get("SUPABASE_URL")!;
    const sbAdmin = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const ip = clientIp(req);
    if (!await rateLimit(sbUrl, sbAdmin, `geo:ip:${ip}`,                30, 60) ||
        !await rateLimit(sbUrl, sbAdmin, `geo:jwt:${jwt.slice(-24)}`,  500, 3600)) {
      return json({ error_code: "rate_limit", message: "Too many requests" }, 429, cors);
    }

    const body  = await req.json().catch(() => { throw new Error("bad-json"); });
    const query = v.string("query", body.query, {
      min: 4, max: 200,
      pattern: /^[\p{L}\p{N}\s.,#°/'\-()]+$/u,  // letters, digits, common punctuation only
    });

    const sb = createClient(sbUrl, sbAdmin);
    const key = query.toLowerCase();

    const { data: cached } = await sb.from("geocode_cache").select("lat,lng").eq("query", key).maybeSingle();
    if (cached) return json({ ok: true, cached: true, ...cached }, 200, cors);

    const url = `https://nominatim.openstreetmap.org/search?format=jsonv2&limit=1&countrycodes=mx&q=${encodeURIComponent(query)}`;
    const nom = await fetch(url, {
      headers: { "user-agent": "salud-visual-saas/1.0 (contact: security@saludvisual.app)" },
      signal:  AbortSignal.timeout(8000),
    });
    if (!nom.ok) return json({ error_code: "upstream", message: `nominatim ${nom.status}` }, 502, cors);
    const arr = await nom.json();
    if (!Array.isArray(arr) || arr.length === 0) {
      return json({ ok: false, error_code: "no_results", message: "No results" }, 404, cors);
    }

    const lat = parseFloat(arr[0].lat);
    const lng = parseFloat(arr[0].lon);
    if (!Number.isFinite(lat) || !Number.isFinite(lng) ||
        lat < -90 || lat > 90 || lng < -180 || lng > 180) {
      return json({ error_code: "bad_response", message: "Invalid coordinates" }, 502, cors);
    }

    await sb.from("geocode_cache").upsert({ query: key, lat, lng });
    return json({ ok: true, cached: false, lat, lng }, 200, cors);
  } catch (e) {
    return errorResponse(e);
  }
});
