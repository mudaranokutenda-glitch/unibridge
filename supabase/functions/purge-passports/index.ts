// @ts-nocheck
import { createClient } from "npm:@supabase/supabase-js@2";

// C3. Called every night by the database (sql/2026-11-05-08-passport-cleanup.sql).
// Deletes passport scans of requests ISSUED more than PASSPORT_KEEP_DAYS
// days ago (default 30). Files are deleted with the Storage API.

const SYSTEM_ID = "00000000-0000-0000-0000-000000000000";

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
    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );
    const keepDays = Number(Deno.env.get("PASSPORT_KEEP_DAYS") ?? "30") || 30;
    const cutoff = new Date(Date.now() - keepDays * 24 * 3600 * 1000).toISOString();

    const { data: rows, error } = await admin
      .from("attestation_requests")
      .select("id, user_id, passport_path")
      .eq("status", "ISSUED")
      .lt("issued_at", cutoff)
      .not("passport_path", "is", null)
      .limit(500);
    if (error) return json({ error: error.message }, 500);

    let deleted = 0;
    for (const r of rows ?? []) {
      const { error: rmErr } = await admin.storage.from("passports").remove([r.passport_path]);
      if (rmErr) continue; // try again tomorrow
      await admin
        .from("attestation_requests")
        .update({ passport_path: null, passport_deleted_at: new Date().toISOString() })
        .eq("id", r.id);
      await admin.from("access_log").insert({
        actor_id: SYSTEM_ID,
        actor_role: "system",
        student_id: r.user_id,
        kind: "PASSPORT_DELETED",
        document_id: r.id,
      });
      deleted++;
    }
    return json({ ok: true, deleted, keepDays });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
