import { createClient } from "npm:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

async function verifyTelegramInitData(initData: string, botToken: string) {
  if (!initData || !botToken) return null;
  const params = new URLSearchParams(initData);
  const hash = params.get("hash");
  const authDate = Number(params.get("auth_date") || 0);
  if (!hash || !authDate || Math.abs(Date.now() / 1000 - authDate) > 86400) return null;
  params.delete("hash");
  const dataCheck = [...params.entries()].sort(([a], [b]) => a.localeCompare(b)).map(([k, v]) => `${k}=${v}`).join("\n");
  const enc = new TextEncoder();
  const key = await crypto.subtle.importKey("raw", enc.encode("WebAppData"), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const secret = await crypto.subtle.sign("HMAC", key, enc.encode(botToken));
  const hmacKey = await crypto.subtle.importKey("raw", secret, { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const digest = new Uint8Array(await crypto.subtle.sign("HMAC", hmacKey, enc.encode(dataCheck)));
  const expected = [...digest].map((b) => b.toString(16).padStart(2, "0")).join("");
  if (expected.length !== hash.length || !crypto.subtle) return null;
  let diff = 0;
  for (let i = 0; i < expected.length; i++) diff |= expected.charCodeAt(i) ^ hash.charCodeAt(i);
  if (diff !== 0) return null;
  try {
    const user = JSON.parse(params.get("user") || "{}");
    return user?.id ? String(user.id) : null;
  } catch {
    return null;
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const callbackSecret = Deno.env.get("ONCLICKA_CALLBACK_SECRET") || "";
  const botToken = Deno.env.get("TELEGRAM_BOT_TOKEN") || "";
  const db = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false } });

  // OnClicka calls this endpoint after its view-confirmation event.
  if (req.method === "GET") {
    const url = new URL(req.url);
    const pathToken = url.pathname.split("/").filter(Boolean).at(-1) || "";
    const userId = url.searchParams.get("USERID") || url.searchParams.get("userid") || "";
    if (!callbackSecret || pathToken !== callbackSecret) return json({ error: "Not found" }, 404);
    if (!/^\d{3,30}$/.test(userId)) return json({ error: "Invalid USERID" }, 400);
    const { error } = await db.from("onclicka_confirmed_views").insert({ telegram_user_id: userId });
    if (error) return json({ error: "Could not store confirmation" }, 500);
    return json({ ok: true });
  }

  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
  let body: Record<string, unknown>;
  try { body = await req.json(); } catch { return json({ error: "Invalid JSON" }, 400); }
  const telegramUserId = await verifyTelegramInitData(String(body.initData || ""), botToken);
  if (!telegramUserId) return json({ error: "Telegram session verification failed. Open the Mini App from Telegram." }, 401);
  const action = String(body.action || "");
  const videoId = String(body.videoId || "");
  if (!/^[0-9a-f-]{36}$/i.test(videoId)) return json({ error: "Invalid video ID" }, 400);

  if (action === "status") {
    const { data, error } = await db.from("sv_reward_unlocks").select("completed_ads,unlocked_until").eq("telegram_user_id", telegramUserId).eq("video_id", videoId).maybeSingle();
    if (error) return json({ error: "Could not read unlock status" }, 500);
    const expiry = data?.unlocked_until ? Date.parse(data.unlocked_until) : 0;
    return json({ completedAds: data?.completed_ads || 0, unlockedUntil: expiry > Date.now() ? expiry : 0 });
  }

  if (action === "claim") {
    // Only a confirmation inserted by the private OnClicka callback can be consumed.
    const { data: pending, error: readError } = await db.from("onclicka_confirmed_views")
      .select("id").eq("telegram_user_id", telegramUserId).is("claimed_at", null)
      .order("received_at", { ascending: true }).limit(1).maybeSingle();
    if (readError) return json({ error: "Could not check ad confirmation" }, 500);
    if (!pending) return json({ confirmed: false }, 200);
    const { data: claimed, error: claimError } = await db.from("onclicka_confirmed_views")
      .update({ claimed_at: new Date().toISOString() }).eq("id", pending.id).is("claimed_at", null).select("id").maybeSingle();
    if (claimError) return json({ error: "Could not claim ad confirmation" }, 500);
    if (!claimed) return json({ confirmed: false }, 200);

    const { data: current, error: currentError } = await db.from("sv_reward_unlocks")
      .select("completed_ads,unlocked_until").eq("telegram_user_id", telegramUserId).eq("video_id", videoId).maybeSingle();
    if (currentError) return json({ error: "Could not update reward progress" }, 500);
    const now = Date.now();
    const currentExpiry = current?.unlocked_until ? Date.parse(current.unlocked_until) : 0;
    if (currentExpiry > now) return json({ confirmed: true, completedAds: 0, unlockedUntil: currentExpiry });
    const completedAds = Math.min(2, Number(current?.completed_ads || 0) + 1);
    const unlockedUntil = completedAds >= 2 ? now + 5 * 60 * 60 * 1000 : null;
    const { error: saveError } = await db.from("sv_reward_unlocks").upsert({
      telegram_user_id: telegramUserId,
      video_id: videoId,
      completed_ads: unlockedUntil ? 0 : completedAds,
      unlocked_until: unlockedUntil ? new Date(unlockedUntil).toISOString() : null,
      updated_at: new Date().toISOString(),
    }, { onConflict: "telegram_user_id,video_id" });
    if (saveError) return json({ error: "Could not save reward progress" }, 500);
    return json({ confirmed: true, completedAds: unlockedUntil ? 2 : completedAds, unlockedUntil: unlockedUntil || 0 });
  }

  return json({ error: "Unknown action" }, 400);
});
