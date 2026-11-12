// @ts-nocheck
import { createClient } from "npm:@supabase/supabase-js@2";
import { GoogleAuth } from "npm:google-auth-library@9";

// Stage 7, item 29. Emergency alert to EVERY user.
// Called from the app by the Educational Attaché or admin:
//   body: { title: "...", message: "...", test?: true }
// test: true sends ONLY to the caller's own phone, saves no alert and skips
// the 2-minute rule. A real alert is refused (429) if another alert was
// created less than MIN_GAP_SECONDS ago.
// The caller is identified from the login token and the role is read from
// the database (never trusted from the app). The alert is saved in the
// alerts table (shown in the app) and sent as a high-priority push on the
// Android "emergency" channel.

const SERVICE_ACCOUNT_ENV = "FIREBASE_SERVICE_ACCOUNT";
// Must match kEmergencyChannelId in lib/push.dart.
const EMERGENCY_CHANNEL = "emergency";
const PAGE = 1000;
const PARALLEL = 50;
const MIN_GAP_SECONDS = 120;

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  try {
    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // 1. Who is asking? Only attache or admin.
    const token = (req.headers.get("Authorization") ?? "").replace("Bearer ", "");
    const { data: userData, error: userErr } = await admin.auth.getUser(token);
    if (userErr || !userData.user) return json({ error: "Not signed in" }, 401);
    const callerId = userData.user.id;
    const { data: me } = await admin
      .from("profiles").select("role, fcm_token").eq("id", callerId).single();
    if (!me || (me.role !== "attache" && me.role !== "admin")) {
      return json({ error: "Not allowed" }, 403);
    }

    // 2. Check the text.
    const body = await req.json();
    const title = String(body.title ?? "").trim();
    const message = String(body.message ?? "").trim();
    if (title.length < 1 || title.length > 100) {
      return json({ error: "The title must have 1 to 100 characters" }, 400);
    }
    if (message.length < 1 || message.length > 1000) {
      return json({ error: "The message must have 1 to 1000 characters" }, 400);
    }

    const isTest = body.test === true;

    // 3. Not twice in 2 minutes (a test does not count and is not blocked).
    if (!isTest) {
      const since = new Date(Date.now() - MIN_GAP_SECONDS * 1000).toISOString();
      const { data: recent, error: recentErr } = await admin
        .from("alerts").select("id").gte("created_at", since).limit(1);
      if (recentErr) return json({ error: recentErr.message }, 500);
      if ((recent ?? []).length > 0) {
        return json({
          error: "An alert was sent less than 2 minutes ago. Wait 2 minutes before sending another one.",
        }, 429);
      }
    }

    // 4. Firebase access token.
    const raw = Deno.env.get(SERVICE_ACCOUNT_ENV);
    if (!raw) return json({ error: `Secret ${SERVICE_ACCOUNT_ENV} not found` }, 500);
    const credentials = JSON.parse(raw);
    const auth = new GoogleAuth({
      credentials,
      scopes: ["https://www.googleapis.com/auth/firebase.messaging"],
    });
    const accessToken = (await (await auth.getClient()).getAccessToken()).token;
    const url = `https://fcm.googleapis.com/v1/projects/${credentials.project_id}/messages:send`;

    async function sendTo(fcmToken: string, alertId: string) {
      const res = await fetch(url, {
        method: "POST",
        headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" },
        body: JSON.stringify({
          message: {
            token: fcmToken,
            notification: { title, body: message.slice(0, 500) },
            data: { type: "EMERGENCY_ALERT", alert_id: alertId, channel: EMERGENCY_CHANNEL },
            android: {
              priority: "high",
              notification: {
                channel_id: EMERGENCY_CHANNEL,
                notification_priority: "PRIORITY_MAX",
                visibility: "PUBLIC",
              },
            },
          },
        }),
      });
      return res.ok;
    }

    // 5. Test: only my own phone, nothing saved.
    if (isTest) {
      if (!me.fcm_token) {
        return json({ error: "This phone has no notification token yet. Open the app on your phone first." }, 400);
      }
      const ok = await sendTo(me.fcm_token, "test").catch(() => false);
      return json({ ok: true, test: true, sent: ok ? 1 : 0 });
    }

    // 6. Save it (shown in the app to everyone).
    const { data: alert, error: insErr } = await admin
      .from("alerts")
      .insert({ title, message, created_by: callerId })
      .select("id")
      .single();
    if (insErr) return json({ error: insErr.message }, 500);

    // 7. Push to every phone.
    let sent = 0;
    let failed = 0;
    let warning: string | null = null;
    for (let from = 0; ; from += PAGE) {
      const { data: people, error } = await admin
        .from("profiles")
        .select("fcm_token")
        .not("fcm_token", "is", null)
        .order("id")
        .range(from, from + PAGE - 1);
      if (error) {
        // Stop here and say so: some phones may not have received it.
        warning = `Could not read the list of users (${error.message}). ` +
          `The alert was sent to ${sent} phones only.`;
        break;
      }
      const tokens = (people ?? []).map((p) => p.fcm_token as string).filter(Boolean);
      for (let i = 0; i < tokens.length; i += PARALLEL) {
        const results = await Promise.all(
          tokens.slice(i, i + PARALLEL).map((t) => sendTo(t, String(alert.id)).catch(() => false)),
        );
        for (const ok of results) ok ? sent++ : failed++;
      }
      if (!people || people.length < PAGE) break;
    }

    await admin.from("alerts").update({ sent_count: sent }).eq("id", alert.id);
    if (warning) return json({ ok: false, sent, failed, warning });
    return json({ ok: true, sent, failed });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
