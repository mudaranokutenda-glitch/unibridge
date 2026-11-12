// @ts-nocheck
import { createClient } from "npm:@supabase/supabase-js@2";
import { GoogleAuth } from "npm:google-auth-library@9";

// If your Firebase secret has a different name (see: supabase secrets list),
// change this one line.
const SERVICE_ACCOUNT_ENV = "FIREBASE_SERVICE_ACCOUNT";

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  try {
    const { request_id, message } = await req.json();
    if (!request_id || !message) {
      return json({ error: "request_id and message are required" }, 400);
    }

    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // 1. Who is sending? (the app passes the logged-in user's token)
    const token = (req.headers.get("Authorization") ?? "").replace("Bearer ", "");
    const { data: userData, error: userErr } = await admin.auth.getUser(token);
    if (userErr || !userData.user) return json({ error: "Not signed in" }, 401);
    const senderId = userData.user.id;

    // 2. Find the other person in this transaction
    const { data: reqRow, error: reqErr } = await admin
      .from("transaction_requests")
      .select("creator_id, matched_with_id")
      .eq("id", request_id)
      .single();
    if (reqErr || !reqRow) return json({ error: "Request not found" }, 404);

    if (senderId !== reqRow.creator_id && senderId !== reqRow.matched_with_id) {
      return json({ error: "Not part of this transaction" }, 403);
    }
    const recipientId =
      senderId === reqRow.creator_id ? reqRow.matched_with_id : reqRow.creator_id;
    if (!recipientId) return json({ skipped: "No other participant yet" });

      // 3. Their device token, and the sender's name
    const { data: recipient } = await admin
      .from("profiles").select("fcm_token").eq("id", recipientId).single();
    const { data: sender } = await admin
      .from("profiles").select("full_name").eq("id", senderId).single();
    if (!recipient?.fcm_token) {
      return json({ skipped: "Recipient has no device token" });
    }

    // 4. Get a Firebase access token from the stored service account
    const raw = Deno.env.get(SERVICE_ACCOUNT_ENV);
    if (!raw) return json({ error: `Secret ${SERVICE_ACCOUNT_ENV} not found` }, 500);
    const credentials = JSON.parse(raw);
    const auth = new GoogleAuth({
      credentials,
      scopes: ["https://www.googleapis.com/auth/firebase.messaging"],
    });
    const client = await auth.getClient();
    const accessToken = (await client.getAccessToken()).token;

    // 5. Send the push
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
            token: recipient.fcm_token,
            notification: {
              title: sender?.full_name || "New message",
              body: String(message).slice(0, 100),
            },
            data: { request_id: String(request_id), channel: "general" },
            android: { notification: { channel_id: "general" } },
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

