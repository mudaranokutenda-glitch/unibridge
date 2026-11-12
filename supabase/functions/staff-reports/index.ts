// @ts-nocheck
import { createClient } from "npm:@supabase/supabase-js@2";
import { PDFDocument, StandardFonts, rgb } from "npm:pdf-lib@1.17.1";

// D2 + D3. Builds PDFs (and a CSV) for staff, stores them in the private
// bucket compiled-results and returns a link valid for 1 hour.
//
// Body:
//   { action: "compile", wilaya: "16 - Alger", academic_year: "2025-2026", part: 1 }
//       attache, admin, or the rep of that wilaya.
//       Cover page with the list of students, then each student's results.
//   { action: "final_list", format: "pdf" | "csv", wilaya?: "16 - Alger",
//     include_bank?: true }
//       attache and admin only. All students, or one wilaya. With
//       include_bank, the bank account column is added and the export is
//       written to access_log as FINAL_LIST_EXPORTED_WITH_BANK.
//
// LIMITS (Supabase Edge Functions): about 256 MB of memory, a short CPU
// time per request and a wall-clock limit. Merging big PDFs is heavy, so a
// wilaya is split into PARTS: at most MAX_STUDENTS_PER_PART students and
// about MAX_BYTES_PER_PART of result files per part. The app asks for
// part 1, 2, 3 ... one after the other. If a part still fails, lower
// these two numbers and deploy again.
//
// Needs sql files 01, 04, 06 and 09.

const MAX_STUDENTS_PER_PART = 8;
const MAX_BYTES_PER_PART = 15 * 1024 * 1024;
const LINK_SECONDS = 3600;

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

// The standard PDF font only knows Latin letters (é, è, à ... are fine).
function safe(text: unknown): string {
  return String(text ?? "")
    .replace(/[\r\n\t]+/g, " ")
    .replace(/[^\x20-\x7E\xA0-\xFF]/g, "?");
}

function fullName(s) {
  return `${s.last_name} ${s.first_name}`;
}

// Removes the caller's older files so the bucket does not keep growing.
async function removeOldFiles(admin, folder: string, prefix: string) {
  const { data } = await admin.storage.from("compiled-results").list(folder, { limit: 1000 });
  const old = (data ?? []).filter((f) => f.id && f.name.startsWith(prefix))
    .map((f) => `${folder}/${f.name}`);
  if (old.length > 0) await admin.storage.from("compiled-results").remove(old);
}

async function storeAndSign(admin, path: string, bytes: Uint8Array, contentType: string) {
  const { error } = await admin.storage
    .from("compiled-results")
    .upload(path, bytes, { contentType, upsert: true });
  if (error) throw new Error(`Could not save the file: ${error.message}`);
  const { data, error: signErr } = await admin.storage
    .from("compiled-results")
    .createSignedUrl(path, LINK_SECONDS);
  if (signErr) throw new Error(signErr.message);
  return data.signedUrl;
}

// Writes lines of a table on A4 pages, adding pages when one is full.
function drawTable(pdf, font, bold, title: string, subtitle: string,
                   columns: { label: string; width: number }[], rows: string[][],
                   landscape = false) {
  const [w, h] = landscape ? [842, 595] : [595, 842];
  const size = landscape ? 7.5 : 9;
  const lineH = size + 5;
  let page = null;
  let y = 0;

  function cell(p, text: string, x: number, yy: number, width: number, f) {
    let t = safe(text);
    while (t.length > 1 && f.widthOfTextAtSize(t, size) > width - 4) t = t.slice(0, -1);
    p.drawText(t, { x, y: yy, size, font: f });
  }

  function newPage(first: boolean) {
    page = pdf.addPage([w, h]);
    y = h - 40;
    if (first) {
      page.drawText(safe(title), { x: 30, y, size: 15, font: bold });
      y -= 18;
      page.drawText(safe(subtitle), { x: 30, y, size: 9, font, color: rgb(0.35, 0.35, 0.35) });
      y -= 22;
    }
    let x = 30;
    for (const c of columns) {
      cell(page, c.label, x, y, c.width, bold);
      x += c.width;
    }
    y -= 4;
    page.drawLine({ start: { x: 30, y }, end: { x: w - 30, y }, thickness: 0.5 });
    y -= lineH;
  }

  newPage(true);
  for (const r of rows) {
    if (y < 40) newPage(false);
    let x = 30;
    r.forEach((v, i) => {
      cell(page, v, x, y, columns[i].width, font);
      x += columns[i].width;
    });
    y -= lineH;
  }
  if (rows.length === 0) page.drawText("No students.", { x: 30, y, size, font });
}

Deno.serve(async (req) => {
  try {
    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const token = (req.headers.get("Authorization") ?? "").replace("Bearer ", "");
    const { data: userData, error: userErr } = await admin.auth.getUser(token);
    if (userErr || !userData.user) return json({ error: "Not signed in" }, 401);
    const callerId = userData.user.id;

    const { data: me } = await admin
      .from("profiles")
      .select("role, rep_wilaya")
      .eq("id", callerId)
      .single();
    if (!me) return json({ error: "Profile not found" }, 403);
    const isStaff = me.role === "attache" || me.role === "admin";

    const body = await req.json();
    const stamp = new Date().toISOString().slice(0, 16).replace("T", " ");

    // ---------------- D2: compile one wilaya ----------------
    if (body.action === "compile") {
      const wilaya = String(body.wilaya ?? "");
      const year = String(body.academic_year ?? "");
      const part = Math.max(1, Number(body.part ?? 1) | 0);
      if (!/^\d{2} - /.test(wilaya) || !/^\d{4}-\d{4}$/.test(year)) {
        return json({ error: "Choose a wilaya and an academic year" }, 400);
      }
      const allowed = isStaff || (me.role === "rep" && me.rep_wilaya === wilaya);
      if (!allowed) return json({ error: "Not allowed" }, 403);

      const { data: students, error: sErr } = await admin
        .from("student_records")
        .select("user_id, first_name, last_name, inscription_number, program, level, academic_year")
        .eq("wilaya", wilaya)
        .order("last_name")
        .order("first_name");
      if (sErr) return json({ error: sErr.message }, 500);

      const ids = (students ?? []).map((s) => s.user_id);
      const { data: results, error: rErr } = ids.length === 0 ? { data: [] } : await admin
        .from("academic_results")
        .select("id, user_id, semester, file_path, size_bytes")
        .eq("academic_year", year)
        .in("user_id", ids)
        .order("semester");
      if (rErr) return json({ error: rErr.message }, 500);

      const byStudent = new Map();
      for (const r of results ?? []) {
        if (!byStudent.has(r.user_id)) byStudent.set(r.user_id, []);
        byStudent.get(r.user_id).push(r);
      }
      // Students of this wilaya in that year, or who uploaded results for it.
      const list = (students ?? []).filter((s) => s.academic_year === year || byStudent.has(s.user_id));

      // Split into parts (same split every call, so part numbers are stable).
      const parts: any[][] = [[]];
      let bytes = 0;
      for (const s of list) {
        const size = (byStudent.get(s.user_id) ?? []).reduce((a, r) => a + (r.size_bytes ?? 0), 0);
        const current = parts[parts.length - 1];
        if (current.length > 0 &&
            (current.length >= MAX_STUDENTS_PER_PART || bytes + size > MAX_BYTES_PER_PART)) {
          parts.push([]);
          bytes = 0;
        }
        parts[parts.length - 1].push(s);
        bytes += size;
      }
      const totalParts = parts.length;
      if (part > totalParts) return json({ error: "No such part" }, 400);

      const pdf = await PDFDocument.create();
      const font = await pdf.embedFont(StandardFonts.Helvetica);
      const bold = await pdf.embedFont(StandardFonts.HelveticaBold);

      // Cover: the full list on part 1, this part's students on the others.
      const coverStudents = part === 1 ? list : parts[part - 1];
      drawTable(
        pdf, font, bold,
        `Results ${year} - ${wilaya}`,
        `Part ${part} of ${totalParts} - ${list.length} students - built ${stamp} UTC`,
        [
          { label: "No.", width: 30 },
          { label: "Name", width: 170 },
          { label: "Inscription", width: 90 },
          { label: "Program", width: 130 },
          { label: "Level", width: 60 },
          { label: "Results", width: 55 },
        ],
        coverStudents.map((s) => [
          String(list.indexOf(s) + 1),
          fullName(s),
          s.inscription_number,
          s.program,
          s.level,
          String((byStudent.get(s.user_id) ?? []).length),
        ]),
      );

      for (const s of parts[part - 1]) {
        const files = byStudent.get(s.user_id) ?? [];
        const sep = pdf.addPage([595, 842]);
        sep.drawText(safe(fullName(s)), { x: 40, y: 760, size: 20, font: bold });
        sep.drawText(safe(`Inscription: ${s.inscription_number}`), { x: 40, y: 732, size: 11, font });
        sep.drawText(safe(`${s.program} - ${s.level}`), { x: 40, y: 714, size: 11, font });
        sep.drawText(safe(files.length === 0
          ? `No results uploaded for ${year}.`
          : `${files.length} file(s) for ${year}: ${files.map((f) => f.semester).join(", ")}`),
          { x: 40, y: 690, size: 11, font });

        for (const f of files) {
          try {
            const { data: blob, error } = await admin.storage.from("academic-results").download(f.file_path);
            if (error) throw error;
            const src = await PDFDocument.load(new Uint8Array(await blob.arrayBuffer()), {
              ignoreEncryption: true,
            });
            const pages = await pdf.copyPages(src, src.getPageIndices());
            pages.forEach((p) => pdf.addPage(p));
          } catch (_) {
            const bad = pdf.addPage([595, 842]);
            bad.drawText(safe(`Could not read the ${f.semester} file of ${fullName(s)}.`),
              { x: 40, y: 760, size: 12, font });
          }
        }

        await admin.from("access_log").insert({
          actor_id: callerId,
          actor_role: me.role,
          student_id: s.user_id,
          kind: "RESULTS_COMPILED",
          wilaya,
          academic_year: year,
        });
      }

      const code = wilaya.slice(0, 2);
      const prefix = `results_${code}_${year}_`;
      if (part === 1) await removeOldFiles(admin, callerId, prefix);
      const url = await storeAndSign(
        admin,
        `${callerId}/${prefix}part${part}_${Date.now()}.pdf`,
        await pdf.save(),
        "application/pdf",
      );
      return json({ url, part, total_parts: totalParts, students: list.length });
    }

    // ---------------- D3: final list of all students ----------------
    if (body.action === "final_list") {
      if (!isStaff) return json({ error: "Not allowed" }, 403);
      const format = body.format === "csv" ? "csv" : "pdf";

      const includeBank = body.include_bank === true;
      const wilayaFilter = typeof body.wilaya === "string" && body.wilaya ? body.wilaya : null;

      let query = admin.from("student_records").select("*");
      if (wilayaFilter) query = query.eq("wilaya", wilayaFilter);
      const { data: students, error } = await query
        .order("wilaya")
        .order("last_name")
        .order("first_name");
      if (error) return json({ error: error.message }, 500);

      // Bank accounts (only when asked; the export is logged below).
      const bank = new Map<string, string>();
      if (includeBank && (students ?? []).length > 0) {
        const ids = students.map((s) => s.user_id);
        for (let i = 0; i < ids.length; i += 500) {
          const { data: accounts, error: bErr } = await admin
            .from("bank_accounts")
            .select("user_id, account_number")
            .in("user_id", ids.slice(i, i + 500));
          if (bErr) return json({ error: bErr.message }, 500);
          for (const a of accounts ?? []) bank.set(a.user_id, a.account_number);
        }
      }

      // Columns of the final list. The attaché decides: change them here.
      // (narrower columns when the bank account is added, to fit the page)
      const w = includeBank
        ? { name: 72, wilaya: 85, program: 75 }
        : { name: 90, wilaya: 95, program: 110 };
      const columns = [
        { label: "No.", width: 26, get: (_s, i) => String(i + 1) },
        { label: "Last name", width: w.name, get: (s) => s.last_name },
        { label: "First name", width: w.name, get: (s) => s.first_name },
        { label: "Inscription", width: 70, get: (s) => s.inscription_number },
        { label: "Wilaya", width: w.wilaya, get: (s) => s.wilaya },
        { label: "Program", width: w.program, get: (s) => s.program },
        { label: "Level", width: 60, get: (s) => s.level },
        { label: "Year", width: 52, get: (s) => s.academic_year },
        { label: "Start", width: 34, get: (s) => String(s.start_year) },
        { label: "Finish", width: 36, get: (s) => String(s.expected_finish_year) },
        { label: "Phone", width: 80, get: (s) => s.phone },
        ...(includeBank
          ? [{ label: "Bank account", width: 112, get: (s) => bank.get(s.user_id) ?? "" }]
          : []),
      ];
      const rows = (students ?? []).map((s, i) => columns.map((c) => String(c.get(s, i) ?? "")));

      // Every export is logged; the one with bank accounts has its own kind.
      const { error: logErr } = await admin.from("access_log").insert({
        actor_id: callerId,
        actor_role: me.role,
        kind: includeBank ? "FINAL_LIST_EXPORTED_WITH_BANK" : "FINAL_LIST_EXPORTED",
        wilaya: wilayaFilter,
      });
      if (logErr) return json({ error: `Could not write the access log: ${logErr.message}` }, 500);

      await removeOldFiles(admin, callerId, "final_list_");
      let bytes: Uint8Array;
      if (format === "csv") {
        const esc = (v: string) => /[",;\n]/.test(v) ? `"${v.replace(/"/g, '""')}"` : v;
        const lines = [columns.map((c) => c.label), ...rows].map((r) => r.map(esc).join(","));
        // The BOM makes Excel read the accents correctly.
        bytes = new TextEncoder().encode("﻿" + lines.join("\r\n"));
      } else {
        const pdf = await PDFDocument.create();
        const font = await pdf.embedFont(StandardFonts.Helvetica);
        const bold = await pdf.embedFont(StandardFonts.HelveticaBold);
        drawTable(pdf, font, bold, "Final list of students",
          `${wilayaFilter ?? "All wilayas"} - ${rows.length} students - built ${stamp} UTC`,
          columns, rows, true);
        bytes = await pdf.save();
      }
      const url = await storeAndSign(
        admin,
        `${callerId}/final_list_${Date.now()}.${format}`,
        bytes,
        format === "csv" ? "text/csv" : "application/pdf",
      );
      return json({ url });
    }

    return json({ error: "Unknown action" }, 400);
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
