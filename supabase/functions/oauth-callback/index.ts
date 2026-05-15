// Supabase Edge Function — oauth-callback
// Receives the OAuth redirect from Google/Outlook, exchanges the code for
// tokens, stores the refresh_token in profiles, and redirects the app via
// deep link: salud-visual://oauth-success or salud-visual://oauth-error
//
// GET /functions/v1/oauth-callback?code=...&state=...

import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { v } from "../_shared/validate.ts";

const REDIRECT_URI = `${Deno.env.get("SUPABASE_URL")}/functions/v1/oauth-callback`;
const APP_SCHEME   = "salud-visual";

function redirect(path: string): Response {
  return new Response(null, {
    status: 302,
    headers: { location: `${APP_SCHEME}://${path}` },
  });
}

function htmlPage(title: string, body: string): Response {
  return new Response(
    `<!doctype html><html lang="es"><head><meta charset="utf-8"><title>${title}</title>
     <style>body{font-family:sans-serif;display:flex;align-items:center;justify-content:center;height:100vh;margin:0}
     .card{padding:2rem;border-radius:12px;box-shadow:0 4px 24px #0002;max-width:360px;text-align:center}</style>
     </head><body><div class="card">${body}</div></body></html>`,
    { status: 200, headers: { "content-type": "text/html; charset=utf-8" } },
  );
}

serve(async (req) => {
  const url    = new URL(req.url);
  const code   = url.searchParams.get("code");
  const state  = url.searchParams.get("state");
  const errMsg = url.searchParams.get("error_description") ?? url.searchParams.get("error");

  if (errMsg) return redirect(`oauth-error?msg=${encodeURIComponent(errMsg)}`);
  if (!code || !state) {
    return htmlPage("Error", "<h2>Parámetros inválidos</h2><p>Faltan code o state.</p>");
  }

  const sbUrl   = Deno.env.get("SUPABASE_URL")!;
  const sbAdmin = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const sb      = createClient(sbUrl, sbAdmin);

  try {
    // ── Look up state record ───────────────────────────────────────
    const { data: stateRow, error: stErr } = await sb
      .from("oauth_states")
      .select("user_id, provider, code_verifier, expires_at")
      .eq("state", state)
      .single();

    if (stErr || !stateRow) {
      return redirect(`oauth-error?msg=${encodeURIComponent("Estado inválido o expirado")}`);
    }
    if (new Date(stateRow.expires_at) < new Date()) {
      await sb.from("oauth_states").delete().eq("state", state);
      return redirect(`oauth-error?msg=${encodeURIComponent("Sesión OAuth expirada. Inténtalo de nuevo.")}`);
    }

    const { user_id, provider, code_verifier } = stateRow;

    // ── Exchange code for tokens ───────────────────────────────────
    let refreshToken: string;

    if (provider === "google") {
      const r = await fetch("https://oauth2.googleapis.com/token", {
        method: "POST",
        headers: { "content-type": "application/x-www-form-urlencoded" },
        body: new URLSearchParams({
          code,
          client_id:     Deno.env.get("GOOGLE_CLIENT_ID")!,
          client_secret: Deno.env.get("GOOGLE_CLIENT_SECRET")!,
          redirect_uri:  REDIRECT_URI,
          grant_type:    "authorization_code",
          code_verifier,
        }),
        signal: AbortSignal.timeout(10000),
      });
      if (!r.ok) {
        const t = await r.text();
        console.error("[oauth-callback] google token error", r.status, t);
        return redirect(`oauth-error?msg=${encodeURIComponent("Error al obtener tokens de Google")}`);
      }
      const tokens = await r.json();
      if (!tokens.refresh_token) {
        return redirect(`oauth-error?msg=${encodeURIComponent("Google no devolvió refresh_token. Revoca el acceso en tu cuenta e intenta de nuevo.")}`);
      }
      refreshToken = tokens.refresh_token;
    } else {
      // Outlook / Microsoft Graph
      const tenant = Deno.env.get("MS_TENANT") || "common";
      const r = await fetch(`https://login.microsoftonline.com/${tenant}/oauth2/v2.0/token`, {
        method: "POST",
        headers: { "content-type": "application/x-www-form-urlencoded" },
        body: new URLSearchParams({
          code,
          client_id:     Deno.env.get("MS_CLIENT_ID")!,
          client_secret: Deno.env.get("MS_CLIENT_SECRET")!,
          redirect_uri:  REDIRECT_URI,
          grant_type:    "authorization_code",
          code_verifier,
          scope:         "offline_access Calendars.ReadWrite User.Read",
        }),
        signal: AbortSignal.timeout(10000),
      });
      if (!r.ok) {
        const t = await r.text();
        console.error("[oauth-callback] outlook token error", r.status, t);
        return redirect(`oauth-error?msg=${encodeURIComponent("Error al obtener tokens de Microsoft")}`);
      }
      const tokens = await r.json();
      refreshToken = tokens.refresh_token;
    }

    // ── Persist refresh token ──────────────────────────────────────
    await sb.from("profiles").update({
      calendar_provider: provider,
      calendar_refresh:  refreshToken,
    }).eq("id", user_id);

    // ── Clean up state ─────────────────────────────────────────────
    await sb.from("oauth_states").delete().eq("state", state);

    return redirect("oauth-success");
  } catch (e) {
    console.error("[oauth-callback] unexpected", e);
    return redirect(`oauth-error?msg=${encodeURIComponent("Error inesperado. Intenta de nuevo.")}`);
  }
});
