// Supabase Edge Function — extract-receipt   (hardened)
// POST { image_base64, mime?, provider?, model? } -> { ok, provider, data }
//
// Security controls:
//   • JWT required (config.toml verify_jwt = true)
//   • Per-user + per-IP rate limit (20/min, 200/h)
//   • Strict input validation (base64 + magic-byte sniff, ≤ 8 MB)
//   • No stack traces in responses (errorResponse)
//   • Security headers on every response
//   • Auto-fallback Groq → Gemini, model-by-model

import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { EXTRACT_PROMPT } from "./prompt.ts";
import {
  v, json, errorResponse, rateLimit, clientIp, securityHeaders,
} from "../_shared/validate.ts";

const GROQ_MODELS = [
  "meta-llama/llama-4-scout-17b-16e-instruct",
  "meta-llama/llama-4-maverick-17b-128e-instruct",
];
const ALLOWED_MIMES = ["image/jpeg", "image/png", "image/webp", "image/heic"] as const;

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

    const ip      = clientIp(req);
    const sbUrl   = Deno.env.get("SUPABASE_URL")!;
    const sbAdmin = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const okIp  = await rateLimit(sbUrl, sbAdmin, `extract:ip:${ip}`,    20, 60);
    const okJwt = await rateLimit(sbUrl, sbAdmin, `extract:jwt:${jwt.slice(-24)}`, 200, 3600);
    if (!okIp || !okJwt) return json({ error_code: "rate_limit", message: "Too many requests" }, 429, cors);

    const body = await req.json().catch(() => { throw new Error("bad-json"); });
    const mime     = v.oneOf("mime",     body.mime     ?? "image/jpeg", ALLOWED_MIMES);
    const provider = v.oneOf("provider", body.provider ?? "groq",      ["groq", "gemini"] as const);
    v.base64Image("image_base64", body.image_base64, 8);   // validates type/size/magic bytes
    const b64 = body.image_base64 as string;               // already valid base64, no need to re-encode

    try {
      const raw  = provider === "gemini" ? await callGemini(b64, mime) : await callGroq(b64, mime, body.model);
      const data = parseJson(raw);
      return json({ ok: true, provider, data }, 200, cors);
    } catch (err) {
      if (provider === "groq") {
        try {
          const raw = await callGemini(b64, mime);
          return json({ ok: true, provider: "gemini", fallback: true, data: parseJson(raw) }, 200, cors);
        } catch {
          return json({ error_code: "provider_failed", message: "All providers failed" }, 502, cors);
        }
      }
      return json({ error_code: "provider_failed", message: "Provider failed" }, 502, cors);
    }
  } catch (e) {
    return errorResponse(e);
  }
});

async function callGroq(b64: string, mime: string, preferred?: string): Promise<string> {
  const key = Deno.env.get("GROQ_API_KEY");
  if (!key) throw new Error("GROQ_API_KEY not set");
  const safe = preferred && GROQ_MODELS.includes(preferred) ? preferred : undefined;
  const queue = safe ? [safe, ...GROQ_MODELS.filter(m => m !== safe)] : GROQ_MODELS;

  let lastErr: unknown;
  for (const model of queue) {
    try {
      const r = await fetch("https://api.groq.com/openai/v1/chat/completions", {
        method: "POST",
        headers: { "content-type": "application/json", authorization: `Bearer ${key}` },
        body: JSON.stringify({
          model, temperature: 0.05, max_tokens: 1024,
          messages: [{
            role: "user",
            content: [
              { type: "image_url", image_url: { url: `data:${mime};base64,${b64}` } },
              { type: "text",      text: EXTRACT_PROMPT },
            ],
          }],
        }),
      });
      if (!r.ok) { lastErr = new Error(`groq ${r.status}`); continue; }
      const j = await r.json();
      return j?.choices?.[0]?.message?.content ?? "";
    } catch (e) { lastErr = e; }
  }
  throw lastErr ?? new Error("groq: all models failed");
}

async function callGemini(b64: string, mime: string): Promise<string> {
  const key = Deno.env.get("GEMINI_API_KEY");
  if (!key) throw new Error("GEMINI_API_KEY not set");
  const r = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${key}`,
    {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        generationConfig: { temperature: 0.05, topP: 0.9 },
        contents: [{ parts: [
          { inline_data: { mime_type: mime, data: b64 } },
          { text: EXTRACT_PROMPT },
        ]}],
      }),
    },
  );
  if (!r.ok) throw new Error(`gemini ${r.status}`);
  const j = await r.json();
  return j?.candidates?.[0]?.content?.parts?.[0]?.text ?? "";
}

function parseJson(raw: string): Record<string, unknown> {
  if (!raw?.trim()) throw new Error("empty model response");
  try { return JSON.parse(raw.trim()); } catch { /* */ }
  try { return JSON.parse(raw.replace(/```json|```/gi, "").trim()); } catch { /* */ }
  const m = raw.match(/\{[\s\S]*\}/);
  if (m) { try { return JSON.parse(m[0]); } catch { /* */ } }
  throw new Error("could not parse JSON from model");
}
