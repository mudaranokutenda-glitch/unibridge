// @ts-nocheck
import { createClient } from "npm:@supabase/supabase-js@2";

// Stage 2, item 11. Called every night by the database
// (sql/2026-11-11-05-chat-cleanup.sql) with the x-cron-secret header.
//
// For requests COMPLETED or CANCELLED more than KEEP_DAYS (30) days ago:
//   1. delete their chat photos with the Storage API (bucket chat-photos,
//      folder <request id>/),
//   2. delete their messages,
//   3. set archived_at, so the app hides them.
// The request row and the ratings are KEPT. DISPUTED requests are never touched.
//
// It also deletes every file older than 24 hours in the private bucket
// compiled-results (results PDFs and final lists built by staff-reports,
// one folder per staff user), with the Storage API.

const KEEP_DAYS = 30;
const BATCH = 100;
const COMPILED_KEEP_HOURS = 24;

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

async function listFolder(admin, bucket: string, folder: string) {
  const paths: string[] = [];
  const pageSize = 100;
  for (let offset = 0; ; offset += pageSize) {
    const { data, error } = await admin.storage
      .from(bucket)
      .list(folder, { limit: pageSize, offset });
    if (error) throw new Error(`Could not list ${bucket}/${folder}: ${error.message}`);
    for (const f of data ?? []) {
      if (f.id) paths.push(`${folder}/${f.name}`);
    }
    if (!data || data.length < pageSize) break;
  }
  return paths;
}

// Lists the files of one folder with their creation date.
async function listFilesWithDate(admin, bucket: string, folder: string) {
  const files: { path: string; created: string }[] = [];
  const pageSize = 100;
  for (let offset = 0; ; offset += pageSize) {
    const { data, error } = await admin.storage
      .from(bucket)
      .list(folder, { limit: pageSize, offset });
    if (error) throw new Error(`Could not list ${bucket}/${folder}: ${error.message}`);
    for (const f of data ?? []) {
      if (f.id) files.push({ path: `${folder}/${f.name}`, created: f.created_at ?? "" });
    }
    if (!data || data.length < pageSize) break;
  }
  return files;
}

// Deletes the compiled-results files older than 24 hours.
async function cleanCompiledResults(admin) {
  const bucket = "compiled-results";
  const cutoff = Date.now() - COMPILED_KEEP_HOURS * 3600 * 1000;
  // The top level holds one folder per staff user (folders have no id).
  const folders: string[] = [];
  for (let offset = 0; ; offset += 100) {
    const { data, error } = await admin.storage.from(bucket).list("", { limit: 100, offset });
    if (error) throw new Error(`Could not list ${bucket}: ${error.message}`);
    for (const f of data ?? []) if (!f.id) folders.push(f.name);
    if (!data || data.length < 100) break;
  }
  let removed = 0;
  for (const folder of folders) {
    const old = (await listFilesWithDate(admin, bucket, folder))
      .filter((f) => f.created && Date.parse(f.created) < cutoff)
      .map((f) => f.path);
    for (let i = 0; i < old.length; i += 100) {
      const { error } = await admin.storage.from(bucket).remove(old.slice(i, i + 100));
      if (error) throw new Error(`Could not delete files in ${bucket}: ${error.message}`);
      removed += Math.min(100, old.length - i);
    }
  }
  return removed;
}

Deno.serve(async (req) => {
  // Only the database (which knows the secret) may call this.
  const secret = Deno.env.get("CRON_SECRET");
  if (!secret || req.headers.get("x-cron-secret") !== secret) {
    return json({ error: "Not allowed" }, 401);
  }

  try {
    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );
    const cutoff = new Date(Date.now() - KEEP_DAYS * 24 * 3600 * 1000).toISOString();

    const { data: rows, error } = await admin
      .from("transaction_requests")
      .select("id")
      .in("status", ["COMPLETED", "CANCELLED"])
      .is("archived_at", null)
      .lt("ended_at", cutoff)
      .limit(BATCH);
    if (error) return json({ error: error.message }, 500);

    let cleaned = 0;
    const failed: string[] = [];
    for (const r of rows ?? []) {
      try {
        // 1. Photos (files must be deleted with the Storage API).
        const files = await listFolder(admin, "chat-photos", r.id);
        for (let i = 0; i < files.length; i += 100) {
          const { error: rmErr } = await admin.storage
            .from("chat-photos")
            .remove(files.slice(i, i + 100));
          if (rmErr) throw new Error(rmErr.message);
        }
        // 2. Messages.
        const { error: delErr } = await admin
          .from("messages")
          .delete()
          .eq("request_id", r.id);
        if (delErr) throw new Error(delErr.message);
        // 3. Hide the request (row and ratings stay).
        const { error: upErr } = await admin
          .from("transaction_requests")
          .update({ archived_at: new Date().toISOString() })
          .eq("id", r.id)
          .in("status", ["COMPLETED", "CANCELLED"]);
        if (upErr) throw new Error(upErr.message);
        cleaned++;
      } catch (_e) {
        failed.push(r.id); // tried again tomorrow
      }
    }

    // 4. Old compiled results and final lists (kept 24 hours).
    let compiledRemoved = 0;
    let compiledError: string | null = null;
    try {
      compiledRemoved = await cleanCompiledResults(admin);
    } catch (e) {
      compiledError = String(e); // tried again tomorrow
    }

    return json({
      ok: compiledError === null,
      cleaned,
      failed: failed.length,
      compiled_removed: compiledRemoved,
      ...(compiledError ? { compiled_error: compiledError } : {}),
    });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
