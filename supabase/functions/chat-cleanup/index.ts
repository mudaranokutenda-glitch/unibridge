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
//
// And it deletes "orphan" files: photos that nothing uses any more.
//   - listings: marketplace photos (deleted listings, removed photos) and old
//     profile photos (avatars/ folder, after a photo change)
//   - posters: poster images no longer used by a poster
//   - verification: student-card photos with no verification request
// Safety: only files older than ORPHAN_MIN_AGE_HOURS; nothing is deleted in a
// bucket if the database could not be read; and if a run would delete more
// than 80 % of a bucket (over 20 files), it stops and reports instead.
// Test without deleting: send {"dry_run": true}.

const KEEP_DAYS = 30;
const BATCH = 100;
const COMPILED_KEEP_HOURS = 24;
const ORPHAN_MIN_AGE_HOURS = 48;

// Every file of a bucket (all folders), with its creation date.
async function listAllFiles(admin, bucket: string, folder = "", depth = 0) {
  const files: { path: string; created: string }[] = [];
  const pageSize = 100;
  for (let offset = 0; ; offset += pageSize) {
    const { data, error } = await admin.storage
      .from(bucket)
      .list(folder, { limit: pageSize, offset });
    if (error) throw new Error(`Could not list ${bucket}/${folder}: ${error.message}`);
    for (const f of data ?? []) {
      const path = folder ? `${folder}/${f.name}` : f.name;
      if (f.id) {
        files.push({ path, created: f.created_at ?? "" });
      } else if (depth < 3) {
        files.push(...(await listAllFiles(admin, bucket, path, depth + 1)));
      }
    }
    if (!data || data.length < pageSize) break;
  }
  return files;
}

// ".../storage/v1/object/public/listings/avatars/x.jpg?t=1" -> "avatars/x.jpg"
function pathFromPublicUrl(url: unknown, bucket: string): string | null {
  if (typeof url !== "string") return null;
  const marker = `/object/public/${bucket}/`;
  const i = url.indexOf(marker);
  if (i < 0) return null;
  try {
    return decodeURIComponent(url.slice(i + marker.length).split("?")[0]);
  } catch (_e) {
    return null;
  }
}

// All rows of a table (in pages), only the given columns.
async function allRows(admin, table: string, columns: string) {
  const rows: Record<string, unknown>[] = [];
  const pageSize = 1000;
  for (let from = 0; ; from += pageSize) {
    const { data, error } = await admin
      .from(table)
      .select(columns)
      .range(from, from + pageSize - 1);
    if (error) throw new Error(`Could not read ${table}: ${error.message}`);
    rows.push(...(data ?? []));
    if (!data || data.length < pageSize) break;
  }
  return rows;
}

// The files each bucket still uses (read from the database).
async function usedFiles(admin, bucket: string): Promise<Set<string>> {
  const used = new Set<string>();
  const add = (p: string | null) => { if (p) used.add(p); };
  if (bucket === "listings") {
    for (const r of await allRows(admin, "marketplace_listings", "image_url, image_urls")) {
      add(pathFromPublicUrl(r.image_url, bucket));
      for (const u of (r.image_urls as unknown[]) ?? []) add(pathFromPublicUrl(u, bucket));
    }
    for (const r of await allRows(admin, "profiles", "profile_picture_url")) {
      add(pathFromPublicUrl(r.profile_picture_url, bucket));
    }
  } else if (bucket === "posters") {
    for (const r of await allRows(admin, "posters", "image_path")) add(r.image_path as string);
  } else if (bucket === "verification") {
    for (const r of await allRows(admin, "verification_requests", "card_photo_path")) {
      add(r.card_photo_path as string);
    }
  }
  return used;
}

// Deletes the orphan files of one bucket. Returns a small report.
async function cleanOrphans(admin, bucket: string, dryRun: boolean) {
  const used = await usedFiles(admin, bucket); // throws: nothing deleted
  const files = await listAllFiles(admin, bucket);
  const oldEnough = Date.now() - ORPHAN_MIN_AGE_HOURS * 3600 * 1000;
  const orphans = files
    .filter((f) => !used.has(f.path))
    .filter((f) => f.created && Date.parse(f.created) < oldEnough)
    .map((f) => f.path);
  const report: Record<string, unknown> = {
    files: files.length,
    used: used.size,
    orphans: orphans.length,
  };
  if (orphans.length > 20 && orphans.length > files.length * 0.8) {
    report.stopped = "would delete more than 80 % of the files: check by hand";
    return report;
  }
  if (dryRun) {
    report.would_delete = orphans.slice(0, 20);
    return report;
  }
  let removed = 0;
  for (let i = 0; i < orphans.length; i += 100) {
    const { error } = await admin.storage.from(bucket).remove(orphans.slice(i, i + 100));
    if (error) {
      report.error = error.message;
      break;
    }
    removed += Math.min(100, orphans.length - i);
  }
  report.removed = removed;
  return report;
}

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

  let dryRun = false;
  try {
    dryRun = (await req.json())?.dry_run === true;
  } catch (_e) {
    // no body: a normal nightly run
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
      .limit(dryRun ? 0 : BATCH);
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
    if (!dryRun) {
      try {
        compiledRemoved = await cleanCompiledResults(admin);
      } catch (e) {
        compiledError = String(e); // tried again tomorrow
      }
    }

    // 5. Orphan photos (nothing uses them any more).
    const orphanFiles: Record<string, unknown> = {};
    for (const bucket of ["listings", "posters", "verification"]) {
      try {
        orphanFiles[bucket] = await cleanOrphans(admin, bucket, dryRun);
      } catch (e) {
        orphanFiles[bucket] = { error: String(e).slice(0, 200) }; // tried again tomorrow
      }
    }
    console.log(JSON.stringify({ dry_run: dryRun, orphan_files: orphanFiles }));

    return json({
      ok: compiledError === null,
      cleaned,
      failed: failed.length,
      compiled_removed: compiledRemoved,
      ...(compiledError ? { compiled_error: compiledError } : {}),
      dry_run: dryRun,
      orphan_files: orphanFiles,
    });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
