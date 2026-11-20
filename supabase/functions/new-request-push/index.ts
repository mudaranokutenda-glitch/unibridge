// @ts-nocheck
import { createClient } from "npm:@supabase/supabase-js@2";
import { GoogleAuth } from "npm:google-auth-library@9";

// Stage 4, item 17. Called by the database once per new request
// (sql/2026-11-11-06-new-request-push.sql) with the x-cron-secret header.
// Sends "New request: Send 50 USD" to every phone EXCEPT:
//   the creator, people who switched "New request notifications" off,
//   and people blocked with the creator.
// No inbox (notifications) row is created per user.
//
// Anti-spam: NO push at all if the creator posted another request in the
// last 10 minutes, or has 3 or more OPEN requests (this one included).

const SERVICE_ACCOUNT_ENV = "FIREBASE_SERVICE_ACCOUNT";
const PAGE = 1000; // profiles read per page
const PARALLEL = 50; // pushes sent at the same time
const MIN_GAP_MINUTES = 10;
const MAX_OPEN_FOR_PUSH = 3;

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function formatAmount(a: unknown) {
  const n = Number(a);
  if (!Number.isFinite(n)) return String(a);
  return String(n); // 50 -> "50", 12.5 -> "12.5"
}

Deno.serve(async (req) => {
  const secret = Deno.env.get("CRON_SECRET");
  if (!secret || req.headers.get("x-cron-secret") !== secret) {
    return json({ error: "Not allowed" }, 401);
  }

  try {
    const { request_id } = await req.json();
    if (!request_id) return json({ error: "request_id is required" }, 400);

    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const { data: r, error: rErr } = await admin
      .from("transaction_requests")
      .select("id, creator_id, type, amount, currency, status")
      .eq("id", request_id)
      .maybeSingle();
    if (rErr || !r) return json({ error: "Request not found" }, 404);
    if (r.status !== "OPEN") return json({ skipped: "Not open" });

    // Anti-spam checks (on the creator).
    const since = new Date(Date.now() - MIN_GAP_MINUTES * 60 * 1000).toISOString();
    const { count: recent, error: recentErr } = await admin
      .from("transaction_requests")
      .select("id", { count: "exact", head: true })
      .eq("creator_id", r.creator_id)
      .neq("id", r.id)
      .gte("created_at", since);
    if (recentErr) return json({ error: recentErr.message }, 500);
    const { count: open, error: openErr } = await admin
      .from("transaction_requests")
      .select("id", { count: "exact", head: true })
      .eq("creator_id", r.creator_id)
      .eq("status", "OPEN");
    if (openErr) return json({ error: openErr.message }, 500);
    if ((recent ?? 0) > 0 || (open ?? 0) >= MAX_OPEN_FOR_PUSH) {
      return json({ skipped: "rate limited" });
    }

    // Who does NOT get it.
    const skip = new Set<string>([r.creator_id]);
    const { data: off } = await admin
      .from("notification_settings")
      .select("user_id")
      .eq("new_requests", false);
    for (const o of off ?? []) skip.add(o.user_id);
    const { data: blocks } = await admin
      .from("user_blocks")
      .select("blocker_id, blocked_id")
      .or(`blocker_id.eq.${r.creator_id},blocked_id.eq.${r.creator_id}`);
    for (const b of blocks ?? []) {
      skip.add(b.blocker_id);
      skip.add(b.blocked_id);
    }

    // Firebase access token.
    const raw = Deno.env.get(SERVICE_ACCOUNT_ENV);
    if (!raw) return json({ error: `Secret ${SERVICE_ACCOUNT_ENV} not found` }, 500);
    const credentials = JSON.parse(raw);
    const auth = new GoogleAuth({
      credentials,
      scopes: ["https://www.googleapis.com/auth/firebase.messaging"],
    });
    const accessToken = (await (await auth.getClient()).getAccessToken()).token;
    const url = `https://fcm.googleapis.com/v1/projects/${credentials.project_id}/messages:send`;

    // Same words as in the app: the creator SENDS, so they look for
    // "anyone to receive" (and the other way round).
    const who = r.type === "SEND" ? "Anyone to receive" : "Anyone to send";
    const body = `${who} ${formatAmount(r.amount)} ${r.currency}`;

    async function sendTo(token: string) {
      const res = await fetch(url, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${accessToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          message: {
            token,
            notification: { title: "New request", body },
            data: { type: "NEW_REQUEST", request_id: String(r.id), channel: "general" },
            android: {
              // Deliver at once (even when the phone is sleeping), with the
              // phone's default notification sound.
              priority: "HIGH",
              notification: {
                channel_id: "general",
                default_sound: true,
                notification_priority: "PRIORITY_HIGH",
              },
            },
          },
        }),
      });
      return res.ok;
    }

    let sent = 0;
    let failed = 0;
    for (let from = 0; ; from += PAGE) {
      const { data: people, error } = await admin
        .from("profiles")
        .select("id, fcm_token")
        .not("fcm_token", "is", null)
        .order("id")
        .range(from, from + PAGE - 1);
      if (error) return json({ error: error.message, sent }, 500);
      const tokens = (people ?? [])
        .filter((p) => p.fcm_token && !skip.has(p.id))
        .map((p) => p.fcm_token as string);
      for (let i = 0; i < tokens.length; i += PARALLEL) {
        const results = await Promise.all(
          tokens.slice(i, i + PARALLEL).map((t) => sendTo(t).catch(() => false)),
        );
        for (const ok of results) ok ? sent++ : failed++;
      }
      if (!people || people.length < PAGE) break;
    }
    return json({ ok: true, sent, failed });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
