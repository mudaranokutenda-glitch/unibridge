// @ts-nocheck
import { createClient } from "npm:@supabase/supabase-js@2";

// Deletes the account of the person who calls it (never anyone else).
// Needs sql/2026-11-04-delete-account.sql to be run first.
//
// Kept for the other person: finished transactions, chat text messages
// and ratings (the deleted user shows as "UniBridge user").
// Deleted: every file of the user in every bucket (see step 4).
//
// RULE: when a new bucket or a table with personal data is added, add it
// here too (files in step 4; rows through ON DELETE CASCADE in the SQL).

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

// Lists every file inside a folder and all its sub-folders.
async function listAllFiles(admin, bucket: string, folder: string) {
  const paths: string[] = [];
  const pageSize = 100;
  for (let offset = 0; ; offset += pageSize) {
    const { data, error } = await admin.storage
      .from(bucket)
      .list(folder, { limit: pageSize, offset });
    // A bucket whose SQL file was not run yet simply has no files.
    if (error && /not found/i.test(error.message)) return paths;
    if (error) throw new Error(`Could not list ${bucket}/${folder}: ${error.message}`);
    for (const f of data ?? []) {
      const path = `${folder}/${f.name}`;
      if (f.id) paths.push(path);
      else paths.push(...await listAllFiles(admin, bucket, path));
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

    // 1b. Staff accounts (attache, admin, Governor) are removed by the app
    //     owner, never from the app. The role is read from the database.
    const { data: me, error: meErr } = await admin
      .from("profiles").select("role").eq("id", userId).maybeSingle();
    if (meErr) return json({ error: meErr.message }, 500);
    if (me && ["attache", "admin", "rep"].includes(me.role)) {
      return json({ error: "Staff accounts are removed by the app owner." }, 403);
    }

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

    // 4. Delete ALL my files.
    //    listings: marketplace photos and profile photos
    const listingPhotos = await listFiles(admin, "listings", "", `${userId}_`);
    const avatarPhotos = await listFiles(admin, "listings", "avatars", `${userId}_`);
    await removeFiles(admin, "listings", [...listingPhotos, ...avatarPhotos]);

    //    Private buckets where everything of mine is in the folder <my id>/
    for (const bucket of [
      "verification",      // student cards
      "academic-results",  // results PDFs (<id>/<year>/<file>)
      "passports",         // passport scans
      "attestations",      // issued attestations
      "compiled-results",  // PDFs / CSV I built as staff
    ]) {
      await removeFiles(admin, bucket, await listAllFiles(admin, bucket, userId));
    }

    //    chat-photos: the photos I sent are in <request id>/<my id>_...
    //    The message stays, but shows "Photo removed" to the other person.
    const { data: myChats, error: chatsErr } = await admin
      .from("transaction_requests")
      .select("id")
      .or(`creator_id.eq.${userId},matched_with_id.eq.${userId}`);
    if (chatsErr) return json({ error: chatsErr.message }, 500);
    for (const chat of myChats ?? []) {
      const photos = await listFiles(admin, "chat-photos", chat.id, `${userId}_`);
      await removeFiles(admin, "chat-photos", photos);
    }
    const { error: msgErr } = await admin
      .from("messages")
      .update({ attachment_url: null, content: "Photo removed" })
      .eq("sender_id", userId)
      .eq("type", "IMAGE");
    if (msgErr) return json({ error: msgErr.message }, 500);

    // 5. Delete my private rows added on 2026-11-11 (phone, bank account,
    //    passport number, notification settings, appointments, match
    //    suggestions). They would also go with the login (on delete cascade),
    //    but deleting them first makes sure nothing stays if step 6 fails.
    for (const [table, column] of [
      ["user_phones", "user_id"],
      ["bank_accounts", "user_id"],
      ["passport_numbers", "user_id"],
      ["notification_settings", "user_id"],
      ["appointments", "student_id"],
      ["match_suggestions", "user_a"],
      ["match_suggestions", "user_b"],
    ]) {
      const { error } = await admin.from(table).delete().eq(column, userId);
      // A table that does not exist yet (SQL not run) is not an error here.
      if (error && !/does not exist|schema cache/i.test(error.message)) {
        return json({ error: `${table}: ${error.message}` }, 500);
      }
    }

    // 6. Delete the login. The database removes the profile, listings,
    //    notifications, blocks, verification requests, student record,
    //    results rows, attestation requests and consents by itself and
    //    empties my id in shared history (see the SQL files).
    //    The access log keeps its rows (nobody can delete them).
    //    Staff contacts (staff_contacts) are official contacts typed by the
    //    attaché, not linked to an account: the attaché removes them by hand.
    const { error: deleteErr } = await admin.auth.admin.deleteUser(userId);
    if (deleteErr) return json({ error: deleteErr.message }, 500);

    return json({ ok: true });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
