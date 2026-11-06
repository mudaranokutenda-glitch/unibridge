// @ts-nocheck
import { createClient } from "npm:@supabase/supabase-js@2";
import { GoogleAuth } from "npm:google-auth-library@9";

// If your Firebase secret has a different name (see: supabase secrets list),
// change this one line.
const SERVICE_ACCOUNT_ENV = "FIREBASE_SERVICE_ACCOUNT";

const TITLES: Record<string, string> = {
  MATCH_FOUND: "Someone matched your request",
  CONFIRMATION_NEEDED: "Please confirm",
  TRANSACTION_COMPLETED: "Transaction complete",
  DISPUTE_OPENED: "Dispute opened",
  VERIFIED_BADGE_AWARDED: "You are verified",
  ATTESTATION_UPDATE: "Attestation de bourse",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  // Only the database (which knows the secret) may call this.
  const secret = Deno.env.get("CRON_SECRET");
  if (!secret || req.headers.get("x-cron-secret") !== secret) {
    return json({ error: "Not allowed" }, 401);
  }

  try {
    const { user_id, type, content } = await req.json();
    if (!user_id) return json({ error: "user_id is required" }, 400);

    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const { data: profile } = await admin
      .from("profiles")
      .select("fcm_token")
      .eq("id", user_id)
      .single();
    if (!profile?.fcm_token) {
      return json({ skipped: "User has no device token" });
    }

    const raw = Deno.env.get(SERVICE_ACCOUNT_ENV);
    if (!raw) return json({ error: `Secret ${SERVICE_ACCOUNT_ENV} not found` }, 500);
    const credentials = JSON.parse(raw);
    const auth = new GoogleAuth({
      credentials,
      scopes: ["https://www.googleapis.com/auth/firebase.messaging"],
    });
    const client = await auth.getClient();
    const accessToken = (await client.getAccessToken()).token;

    const fcmRes = await fetch(
      `https://fcm.googleapis.com/v1/projects/${credentials.project_id}/messages:send`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${accessToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          message: {
            token: profile.fcm_token,
            notification: {
              title: TITLES[String(type)] ?? "UniBridge",
              body: String(content ?? "").slice(0, 150),
            },
            data: { type: String(type ?? "") },
          },
        }),
      },
    );
    const result = await fcmRes.json();
    return json({ ok: fcmRes.ok, result }, fcmRes.ok ? 200 : 502);
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});