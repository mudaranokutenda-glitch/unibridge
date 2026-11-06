// @ts-nocheck
import { createClient } from "npm:@supabase/supabase-js@2";

// The ONLY way staff open a student's results or passport.
// Every open is written to access_log, and the link lasts 10 minutes.
//
// Body:
//   { action: "open", kind: "RESULTS", id: <academic_results.id> }
//       attache, admin, or the rep of the student's wilaya
//   { action: "open", kind: "PASSPORT", id: <attestation_requests.id> }
//       attache or admin only (never a rep)
//   { action: "delete_passport", id: <attestation_requests.id> }
//       attache or admin, only when the request is ISSUED or REJECTED
//
// Needs sql files 01, 04, 05 and 06.

const LINK_SECONDS = 600;

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

    // 1. Who is asking, and what is their role?
    const token = (req.headers.get("Authorization") ?? "").replace("Bearer ", "");
    const { data: userData, error: userErr } = await admin.auth.getUser(token);
    if (userErr || !userData.user) return json({ error: "Not signed in" }, 401);
    const callerId = userData.user.id;

    const { data: me, error: meErr } = await admin
      .from("profiles")
      .select("role, rep_wilaya")
      .eq("id", callerId)
      .single();
    if (meErr || !me) return json({ error: "Profile not found" }, 403);
    const isStaff = me.role === "attache" || me.role === "admin";

    const { action, kind, id } = await req.json();
    if (!id) return json({ error: "id is required" }, 400);

    async function log(entry: Record<string, unknown>) {
      const { error } = await admin.from("access_log").insert({
        actor_id: callerId,
        actor_role: me.role,
        ...entry,
      });
      if (error) throw new Error(`Could not write the access log: ${error.message}`);
    }

    // 2. Open a results PDF
    if (action === "open" && kind === "RESULTS") {
      const { data: row } = await admin
        .from("academic_results")
        .select("id, user_id, file_path, academic_year")
        .eq("id", id)
        .maybeSingle();
      if (!row) return json({ error: "Not found" }, 404);

      let allowed = isStaff;
      let wilaya = null;
      if (!allowed && me.role === "rep" && me.rep_wilaya) {
        const { data: rec } = await admin
          .from("student_records")
          .select("wilaya")
          .eq("user_id", row.user_id)
          .maybeSingle();
        wilaya = rec?.wilaya ?? null;
        allowed = wilaya !== null && wilaya === me.rep_wilaya;
      }
      if (!allowed) return json({ error: "Not allowed" }, 403);

      // Log first: if the log fails, the file is not opened.
      await log({
        student_id: row.user_id,
        kind: "RESULTS_OPENED",
        document_id: row.id,
        wilaya,
        academic_year: row.academic_year,
      });
      const { data: signed, error } = await admin.storage
        .from("academic-results")
        .createSignedUrl(row.file_path, LINK_SECONDS);
      if (error) return json({ error: error.message }, 500);
      return json({ url: signed.signedUrl });
    }

    // From here on: attache and admin only.
    if (!isStaff) return json({ error: "Not allowed" }, 403);

    const { data: request } = await admin
      .from("attestation_requests")
      .select("id, user_id, status, passport_path")
      .eq("id", id)
      .maybeSingle();
    if (!request) return json({ error: "Not found" }, 404);

    // 3. Open a passport
    if (action === "open" && kind === "PASSPORT") {
      if (!request.passport_path) {
        return json({ error: "The passport scan was already deleted" }, 410);
      }
      await log({ student_id: request.user_id, kind: "PASSPORT_OPENED", document_id: request.id });
      const { data: signed, error } = await admin.storage
        .from("passports")
        .createSignedUrl(request.passport_path, LINK_SECONDS);
      if (error) return json({ error: error.message }, 500);
      return json({ url: signed.signedUrl });
    }

    // 4. Delete a passport after the request is closed
    if (action === "delete_passport") {
      if (request.status !== "ISSUED" && request.status !== "REJECTED") {
        return json({ error: "Issue or reject the request first" }, 409);
      }
      if (request.passport_path) {
        const { error } = await admin.storage.from("passports").remove([request.passport_path]);
        if (error) return json({ error: error.message }, 500);
      }
      const { error: updErr } = await admin
        .from("attestation_requests")
        .update({ passport_path: null, passport_deleted_at: new Date().toISOString() })
        .eq("id", request.id);
      if (updErr) return json({ error: updErr.message }, 500);
      await log({ student_id: request.user_id, kind: "PASSPORT_DELETED", document_id: request.id });
      return json({ ok: true });
    }

    return json({ error: "Unknown action" }, 400);
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
