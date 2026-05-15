// Supabase Edge Function — oauth-start
// Generates a PKCE code_verifier + challenge, stores the state in oauth_states,
// and returns the Google (or Outlook) authorization URL for the client to open.
//
// POST /functions/v1/oauth-start
// Body: { provider: "google" | "outlook" }
// Auth: Bearer <user JWT>
// Returns: { url: "https://accounts.google.com/..." }

import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { v, json, errorResponse, rateLimit, securityHeaders } from "../_shared/validate.ts";

const cors = {
  "access-control-allow-origin":  "*",
  "access-control-allow-headers": "authorization, x-client-info, apikey, content-type",
  "access-control-allow-methods": "POST, OPTIONS",
};

// ── PKCE helpers ──────────────────────────────────────────────────────────
function base64url(buf: ArrayBuffer): string {
  return btoa(String.fromCharCode(...new Uint8Array(buf)))
    .replace(/\+/g, "-").replace(/\//g, "_").replace(/=/g, "");
}

async function generatePkce(): Promise<{ verifier: string; challenge: string }> {
  const verifier = base64url(crypto.getRandomValues(new Uint8Array(32)));
  const digest   = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(verifier));
  const challenge = base64url(digest);
  return { verifier, challenge };
}

// ── Allowed redirect URI (must match Google Console & Azure) ──────────────
const REDIRECT_URI = `${Deno.env.get("SUPABASE_URL")}/functions/v1/oauth-callback`;

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: { ...securityHeaders, ...cors } });

  try {
    const sbUrl   = Deno.env.get("SUPABASE_URL")!;
    const sbAdmin = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const sb      = createClient(sbUrl, sbAdmin);

    // ── Auth ───────────────────────────────────────────────────────
    const jwt = req.headers.get("authorization")?.replace(/^Bearer\s+/i, "");
    if (!jwt) return json({ error_code: "auth", message: "JWT required" }, 401, cors);
    const { data: { user } } = await sb.auth.getUser(jwt);
    if (!user) return json({ error_code: "auth", message: "Invalid JWT" }, 401, cors);

    // ── Rate-limit ─────────────────────────────────────────────────
    if (!await rateLimit(sbUrl, sbAdmin, `oauth:user:${user.id}`, 5, 60)) {
      return json({ error_code: "rate_limit", message: "Too many requests" }, 429, cors);
    }

    // ── Parse body ─────────────────────────────────────────────────
    const body     = await req.json();
    const provider = v.oneOf("provider", body.provider, ["google", "outlook"] as const);

    // ── Generate PKCE ──────────────────────────────────────────────
    const { verifier, challenge } = await generatePkce();
    const state = crypto.randomUUID();

    await sb.from("oauth_states").insert({
      state,
      user_id: user.id,
      provider,
      code_verifier: verifier,
    });

    // ── Build authorization URL ────────────────────────────────────
    let authUrl: string;

    if (provider === "google") {
      const params = new URLSearchParams({
        client_id:             Deno.env.get("GOOGLE_CLIENT_ID")!,
        redirect_uri:          REDIRECT_URI,
        response_type:         "code",
        scope:                 "openid email https://www.googleapis.com/auth/calendar",
        access_type:           "offline",
        prompt:                "consent",
        state,
        code_challenge:        challenge,
        code_challenge_method: "S256",
      });
      authUrl = `https://accounts.google.com/o/oauth2/v2/auth?${params}`;
    } else {
      const tenant = Deno.env.get("MS_TENANT") || "common";
      const params = new URLSearchParams({
        client_id:             Deno.env.get("MS_CLIENT_ID")!,
        redirect_uri:          REDIRECT_URI,
        response_type:         "code",
        scope:                 "offline_access Calendars.ReadWrite User.Read",
        state,
        code_challenge:        challenge,
        code_challenge_method: "S256",
      });
      authUrl = `https://login.microsoftonline.com/${tenant}/oauth2/v2.0/authorize?${params}`;
    }

    return json({ url: authUrl }, 200, cors);
  } catch (e) {
    return errorResponse(e);
  }
});
