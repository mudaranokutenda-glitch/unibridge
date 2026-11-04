// @ts-nocheck
import { createClient } from "npm:@supabase/supabase-js@2";

// Deletes the account of the person who calls it (never anyone else).
// Needs sql/2026-11-04-delete-account.sql to be run first.
//
// Kept for the other person: finished transactions, chat messages,
// chat photos and ratings (the deleted user shows as "UniBridge user").

const ACTIVE_STATUSES = ["MATCHED", "SENDER_DONE", "RECEIVER_DONE", "DISPUTED"];

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

// Lists every file in a folder of a bucket whose name starts with `prefix`.
async function listFiles(admin, bucket: string, folder: string, prefix: string) {
  const paths: string[] = [];
  const pageSize = 100;
  for (let offset = 0; ; offset += pageSize) {
    const { data, error } = await admin.storage
      .from(bucket)
      .list(folder, { limit: pageSize, offset, search: prefix });
    if (error) throw new Error(`Could not list ${bucket}/${folder}: ${error.message}`);
    for (const f of data ?? []) {
      // Folders have no id. Only keep real files that start with the prefix.
      if (f.id && f.name.startsWith(prefix)) {
        paths.push(folder ? `${folder}/${f.name}` : f.name);
      }
    }
    if (!data || data.length < pageSize) break;
  }
  return paths;
}

async function removeFiles(admin, bucket: string, paths: string[]) {
  for (let i = 0; i < paths.length; i += 100) {
    const { error } = await admin.storage.from(bucket).remove(paths.slice(i, i + 100));
    if (error) throw new Error(`Could not delete files in ${bucket}: ${error.message}`);
  }
}

Deno.serve(async (req) => {
  try {
    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // 1. Who is asking? (the app passes the logged-in user's token)
    const token = (req.headers.get("Authorization") ?? "").replace("Bearer ", "");
    const { data: userData, error: userErr } = await admin.auth.getUser(token);
    if (userErr || !userData.user) return json({ error: "Not signed in" }, 401);
    const userId = userData.user.id;

    // 2. Refuse while a transaction is in progress
    const { data: active, error: activeErr } = await admin
      .from("transaction_requests")
      .select("id")
      .or(`creator_id.eq.${userId},matched_with_id.eq.${userId}`)
      .in("status", ACTIVE_STATUSES)
      .limit(1);
    if (activeErr) return json({ error: activeErr.message }, 500);
    if (active && active.length > 0) {
      return json({
        error: "ACTIVE_TRANSACTION",
        message: "Finish or resolve your open transactions first.",
      }, 409);
    }

    // 3. Cancel my OPEN requests so nobody can match with them
    const { error: cancelErr } = await admin
      .from("transaction_requests")
      .update({ status: "CANCELLED" })
      .eq("creator_id", userId)
      .eq("status", "OPEN");
    if (cancelErr) return json({ error: cancelErr.message }, 500);

    // 4. Delete my files (listing photos, profile photos, student cards).
    //    Chat photos stay with the chat for the other person.
    const listingPhotos = await listFiles(admin, "listings", "", `${userId}_`);
    const avatarPhotos = await listFiles(admin, "listings", "avatars", `${userId}_`);
    await removeFiles(admin, "listings", [...listingPhotos, ...avatarPhotos]);

    const cardPhotos = await listFiles(admin, "verification", userId, "");
    await removeFiles(admin, "verification", cardPhotos);

    // 5. Delete the login. The database removes the profile, listings,
    //    notifications, blocks and verification requests by itself and
    //    empties my id in shared history (see the SQL file).
    const { error: deleteErr } = await admin.auth.admin.deleteUser(userId);
    if (deleteErr) return json({ error: deleteErr.message }, 500);

    return json({ ok: true });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
