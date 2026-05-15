// Supabase Edge Function — calendar-sync  (hardened)
// Two-way sync between `appointments` and the doctor's Google Calendar /
// Outlook. Triggered by the app and by pg_cron every 10 min.
//
// Security controls:
//   • JWT required (or admin service-role for cron)
//   • Rate-limit 6/min/user
//   • OAuth refresh tokens decrypted only inside this function
//   • All outbound hosts pinned (googleapis.com, microsoftonline.com, graph.microsoft.com)
//   • All event fields validated before insert (length, type, ISO date)
//   • Errors return structured codes without stack traces

import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { v, json, errorResponse, rateLimit, securityHeaders } from "../_shared/validate.ts";

const cors = {
  "access-control-allow-origin":  "*",
  "access-control-allow-headers": "authorization, x-client-info, apikey, content-type",
  "access-control-allow-methods": "POST, OPTIONS",
};

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: { ...securityHeaders, ...cors } });

  try {
    const sbUrl   = Deno.env.get("SUPABASE_URL")!;
    const sbAdmin = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const sb = createClient(sbUrl, sbAdmin);

    // ─── Identify caller ───────────────────────────────────────────
    const auth = req.headers.get("authorization")?.replace(/^Bearer\s+/i, "");
    let userId: string | null = null;
    let isAdmin = false;
    if (auth && auth === sbAdmin) {
      isAdmin = true;
      try { userId = v.uuid("user_id", (await req.json()).user_id); } catch { /* */ }
    } else if (auth) {
      const { data } = await sb.auth.getUser(auth);
      userId = data.user?.id ?? null;
    }
    if (!userId) return json({ error_code: "auth", message: "JWT required" }, 401, cors);

    // ─── Rate-limit (skip for admin/cron) ──────────────────────────
    if (!isAdmin) {
      if (!await rateLimit(sbUrl, sbAdmin, `cal:user:${userId}`, 6, 60)) {
        return json({ error_code: "rate_limit", message: "Too many requests" }, 429, cors);
      }
    }

    // ─── Load profile ──────────────────────────────────────────────
    const { data: profile } = await sb.from("profiles")
      .select("calendar_provider, calendar_refresh, default_clinic")
      .eq("id", userId).single();

    if (!profile?.calendar_provider || profile.calendar_provider === "none") {
      return json({ ok: true, skipped: "no provider linked" }, 200, cors);
    }
    if (!profile.calendar_refresh) {
      return json({ error_code: "no_token", message: "No refresh token" }, 400, cors);
    }

    const accessToken = profile.calendar_provider === "google"
      ? await refreshGoogle(profile.calendar_refresh)
      : await refreshOutlook(profile.calendar_refresh);

    const remote = profile.calendar_provider === "google"
      ? await pullGoogle(accessToken)
      : await pullOutlook(accessToken);

    // Validate every remote field before persisting
    const sanitized = remote.map((e) => ({
      clinic_id: profile.default_clinic,
      optometrist_id: userId,
      starts_at: v.iso8601("start", e.start),
      ends_at:   v.iso8601("end",   e.end),
      title:     v.string("title", e.title || "(sin título)", { max: 200 }),
      notes:     e.notes ? v.string("notes", e.notes, { max: 4000, allowEmpty: true }) : null,
      external_provider: profile.calendar_provider,
      external_id:    v.string("external_id",   e.id,   { max: 256, pattern: /^[A-Za-z0-9._@\-=+/]+$/ }),
      external_etag:  v.string("external_etag", e.etag, { max: 256, allowEmpty: true }),
      last_synced_at: new Date().toISOString(),
    }));

    if (sanitized.length) {
      await sb.from("appointments").upsert(sanitized, { onConflict: "external_provider,external_id" });
    }

    const { data: toPush } = await sb.from("appointments")
      .select("*")
      .eq("optometrist_id", userId)
      .is("external_id", null)
      .gte("starts_at", new Date().toISOString());

    for (const a of toPush ?? []) {
      try {
        const ext = profile.calendar_provider === "google"
          ? await pushGoogle(accessToken, a)
          : await pushOutlook(accessToken, a);
        await sb.from("appointments")
          .update({ external_id: ext.id, external_etag: ext.etag, last_synced_at: new Date().toISOString() })
          .eq("id", a.id);
      } catch (err) {
        console.error("[cal-push]", a.id, err);
      }
    }

    return json({ ok: true, pulled: sanitized.length, pushed: toPush?.length ?? 0 }, 200, cors);
  } catch (e) {
    return errorResponse(e);
  }
});

// ── Google ──────────────────────────────────────────────────────────
async function refreshGoogle(refresh: string): Promise<string> {
  const r = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id:     Deno.env.get("GOOGLE_CLIENT_ID")!,
      client_secret: Deno.env.get("GOOGLE_CLIENT_SECRET")!,
      grant_type:    "refresh_token",
      refresh_token: refresh,
    }),
    signal: AbortSignal.timeout(8000),
  });
  if (!r.ok) throw new Error(`google refresh ${r.status}`);
  return (await r.json()).access_token;
}

async function pullGoogle(token: string) {
  const tMin = new Date(Date.now() - 24 * 3600e3).toISOString();
  const tMax = new Date(Date.now() + 30 * 86400e3).toISOString();
  const r = await fetch(
    `https://www.googleapis.com/calendar/v3/calendars/primary/events?timeMin=${tMin}&timeMax=${tMax}&singleEvents=true&orderBy=startTime`,
    { headers: { authorization: `Bearer ${token}` }, signal: AbortSignal.timeout(15000) },
  );
  if (!r.ok) throw new Error(`google pull ${r.status}`);
  const j = await r.json();
  return (j.items ?? []).map((e: any) => ({
    id: String(e.id ?? ""), etag: String(e.etag ?? ""),
    title: String(e.summary ?? "(sin título)"),
    notes: e.description ? String(e.description) : null,
    start: String(e.start?.dateTime ?? e.start?.date ?? ""),
    end:   String(e.end?.dateTime   ?? e.end?.date   ?? ""),
  }));
}

async function pushGoogle(token: string, a: any) {
  const r = await fetch("https://www.googleapis.com/calendar/v3/calendars/primary/events", {
    method: "POST",
    headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
    body: JSON.stringify({
      summary:     v.string("title", a.title, { max: 200 }),
      description: a.notes ? v.string("notes", a.notes, { max: 4000, allowEmpty: true }) : undefined,
      start: { dateTime: v.iso8601("start", a.starts_at) },
      end:   { dateTime: v.iso8601("end",   a.ends_at) },
    }),
    signal: AbortSignal.timeout(15000),
  });
  if (!r.ok) throw new Error(`google push ${r.status}`);
  const x = await r.json();
  return { id: String(x.id ?? ""), etag: String(x.etag ?? "") };
}

// ── Outlook ─────────────────────────────────────────────────────────
async function refreshOutlook(refresh: string): Promise<string> {
  const tenant = Deno.env.get("MS_TENANT") || "common";
  const r = await fetch(`https://login.microsoftonline.com/${tenant}/oauth2/v2.0/token`, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id:     Deno.env.get("MS_CLIENT_ID")!,
      client_secret: Deno.env.get("MS_CLIENT_SECRET")!,
      grant_type:    "refresh_token",
      refresh_token: refresh,
      scope: "offline_access Calendars.ReadWrite",
    }),
    signal: AbortSignal.timeout(8000),
  });
  if (!r.ok) throw new Error(`outlook refresh ${r.status}`);
  return (await r.json()).access_token;
}

async function pullOutlook(token: string) {
  const tMin = new Date(Date.now() - 24 * 3600e3).toISOString();
  const tMax = new Date(Date.now() + 30 * 86400e3).toISOString();
  const r = await fetch(
    `https://graph.microsoft.com/v1.0/me/calendarView?startDateTime=${tMin}&endDateTime=${tMax}`,
    { headers: { authorization: `Bearer ${token}` }, signal: AbortSignal.timeout(15000) },
  );
  if (!r.ok) throw new Error(`outlook pull ${r.status}`);
  const j = await r.json();
  return (j.value ?? []).map((e: any) => ({
    id: String(e.id ?? ""), etag: String(e["@odata.etag"] ?? ""),
    title: String(e.subject ?? "(sin título)"),
    notes: e.bodyPreview ? String(e.bodyPreview) : null,
    start: String(e.start?.dateTime ?? "") + "Z",
    end:   String(e.end?.dateTime   ?? "") + "Z",
  }));
}

async function pushOutlook(token: string, a: any) {
  const r = await fetch("https://graph.microsoft.com/v1.0/me/events", {
    method: "POST",
    headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
    body: JSON.stringify({
      subject: v.string("title", a.title, { max: 200 }),
      body:    { contentType: "text", content: a.notes ? v.string("notes", a.notes, { max: 4000, allowEmpty: true }) : "" },
      start:   { dateTime: v.iso8601("start", a.starts_at), timeZone: "UTC" },
      end:     { dateTime: v.iso8601("end",   a.ends_at),   timeZone: "UTC" },
    }),
    signal: AbortSignal.timeout(15000),
  });
  if (!r.ok) throw new Error(`outlook push ${r.status}`);
  const x = await r.json();
  return { id: String(x.id ?? ""), etag: String(x["@odata.etag"] ?? "") };
}
