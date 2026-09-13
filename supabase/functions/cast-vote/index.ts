import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = (origin: string) => ({
  "Access-Control-Allow-Origin": origin,
  "Access-Control-Allow-Headers": "authorization, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Vary": "Origin",
});
const json = (origin: string, status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { ...corsHeaders(origin), "Content-Type": "application/json" } });
async function hmac(value: string, secret: string) {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const digest = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, "0")).join("");
}
Deno.serve(async (req) => {
  const allowedOrigin = Deno.env.get("SITE_ORIGIN") ?? "";
  const origin = req.headers.get("origin") ?? "";
  if (!allowedOrigin || origin !== allowedOrigin) return json(allowedOrigin || "null", 403, { error: "origin_not_allowed" });
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: corsHeaders(origin) });
  if (req.method !== "POST") return json(origin, 405, { error: "method_not_allowed" });
  const authHeader = req.headers.get("authorization") ?? "";
  if (!authHeader.startsWith("Bearer ")) return json(origin, 401, { error: "authentication_required" });
  let body: { portalId?: string; score?: number; turnstileToken?: string; eventId?: string };
  try { body = await req.json(); } catch { return json(origin, 400, { error: "invalid_json" }); }
  if (!body.portalId?.match(/^[0-9a-f-]{36}$/i) || !Number.isInteger(body.score) || body.score! < 1 || body.score! > 5)
    return json(origin, 422, { error: "invalid_vote" });
  if (!body.turnstileToken || body.turnstileToken.length > 2048) return json(origin, 422, { error: "turnstile_required" });
  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const turnstileSecret = Deno.env.get("TURNSTILE_SECRET")!;
  const hashSecret = Deno.env.get("HASH_SECRET")!;
  const expectedHostname = Deno.env.get("SITE_HOSTNAME")!;
  const userClient = createClient(supabaseUrl, anonKey, { global: { headers: { Authorization: authHeader } } });
  const { data: { user }, error: userError } = await userClient.auth.getUser();
  if (userError || !user?.email_confirmed_at) return json(origin, 401, { error: "verified_email_required" });
  const ip = req.headers.get("cf-connecting-ip") ?? "unknown";
  const ua = req.headers.get("user-agent") ?? "unknown";
  const [ipHash, uaHash] = await Promise.all([hmac(ip, hashSecret), hmac(ua, hashSecret)]);
  const verify = await fetch("https://challenges.cloudflare.com/turnstile/v0/siteverify", {
    method: "POST", headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ secret: turnstileSecret, response: body.turnstileToken, remoteip: ip, idempotency_key: body.eventId ?? crypto.randomUUID() })
  });
  const challenge = await verify.json();
  if (!challenge.success || (expectedHostname && challenge.hostname !== expectedHostname))
    return json(origin, 403, { error: "bot_check_failed" });
  const admin = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: allowed, error: rateError } = await admin.rpc("consume_rate_limit", {
    p_actor: user.id, p_ip_hash: ipHash, p_user_agent_hash: uaHash, p_event: "vote_attempt", p_window_seconds: 600, p_limit: 12
  });
  if (rateError) return json(origin, 500, { error: "rate_limit_unavailable" });
  if (!allowed) return json(origin, 429, { error: "rate_limited" });
  const eventId = body.eventId?.match(/^[0-9a-f-]{36}$/i) ? body.eventId : crypto.randomUUID();
  const { data: voteId, error } = await admin.rpc("cast_verified_vote", {
    p_reader: user.id, p_portal: body.portalId, p_score: body.score,
    p_event_id: eventId, p_ip_hash: ipHash, p_user_agent_hash: uaHash
  });
  if (error) {
    const known = ["reader_not_verified", "portal_not_open", "invalid_score"].find((x) => error.message.includes(x));
    return json(origin, known ? 403 : 500, { error: known ?? "vote_failed" });
  }
  return json(origin, 200, { voteId, eventId, updated: true });
});
