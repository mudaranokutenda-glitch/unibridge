# Setup and test: items A1 to E3 (built 5 November 2026)

Do the steps in this order. Each step says what you should see.
If something gives an error, stop and paste the error to Claude.

---

## Step 1. Run the SQL files (Supabase → SQL Editor)

Open each file, copy everything, paste it into a new query, press **Run**.
Each one should end with "Success". Run them **in this order**:

| # | File | What it adds |
|---|------|--------------|
| 1 | `sql/2026-10-30-chat-photos.sql` | Only if the bucket `chat-photos` does not exist yet |
| 2 | `sql/2026-11-01-report-block.sql` | Only if the tables `user_reports` / `user_blocks` do not exist yet |
| 3 | `sql/2026-11-04-delete-account.sql` | Only if you have not run it yet (safe to run again) |
| 4 | `sql/2026-11-05-01-roles.sql` | role, rep_wilaya, is_staff(), is_rep_for(), my_role(), the 58 wilayas |
| 5 | `sql/2026-11-05-02-wilayas.sql` | Turns typed wilayas into "16 - Alger"; only the list is allowed now |
| 6 | `sql/2026-11-05-03-consent.sql` | Table document_consents |
| 7 | `sql/2026-11-05-04-student-space.sql` | Tables student_records, academic_results + bucket academic-results |
| 8 | `sql/2026-11-05-05-attestations.sql` | Table attestation_requests + buckets passports, attestations |
| 9 | `sql/2026-11-05-06-access-log.sql` | Table access_log (cannot be edited or deleted) |
| 10 | `sql/2026-11-05-07-posters.sql` | Table posters + public bucket posters |
| 11 | `sql/2026-11-05-09-compiled-results.sql` | Private bucket compiled-results |

File **08** (passport cleanup) comes later, in Step 3.

If file 5 says **"profiles.wilaya is not a text column"**, stop and tell Claude.

---

## Step 2. Deploy the Edge Functions (terminal, in the project folder)

```
supabase functions deploy staff-documents --use-api
supabase functions deploy staff-reports --use-api
supabase functions deploy purge-passports --use-api
supabase functions deploy delete-account --use-api
supabase functions deploy push-notification --use-api
```

`delete-account` and `push-notification` were changed. The other three are new.

---

## Step 3. Schedule the nightly passport cleanup

1. Open `sql/2026-11-05-08-passport-cleanup.sql` in the SQL Editor (not in VS Code).
2. In the editor, replace `PASTE_YOUR_SECRET` with your CRON_SECRET value. Do not save the real value in the file.
3. Run it. Then run `select jobname, schedule from cron.job;`. You should see `purge-passports | 30 2 * * *`.
4. The passport is kept 30 days after issue. To change it after you talk to the attaché:
   `supabase secrets set PASSPORT_KEEP_DAYS=14` (any number of days).

---

## Step 4. Give the roles (SQL Editor)

Find the ids in Table Editor → profiles.

```sql
update public.profiles set role = 'admin'   where id = 'YOUR-ID';
update public.profiles set role = 'attache' where id = 'ATTACHE-ID';
update public.profiles set role = 'rep', rep_wilaya = '16 - Alger' where id = 'REP-ID';
```

For testing you need 4 accounts: **you (admin)**, **Student A**, **Student B**, and **Rep**.
Make the Rep's wilaya the same as Student A's wilaya, and different from Student B's.

---

## Step 5. Start the app

```
flutter run
```

---

## Step 6. Tests

Tick each line. Lines in **bold** are security tests: they MUST fail for the wrong person.

### A1. Roles
In the SQL Editor, run tests **T1 to T7** at the bottom of `sql/2026-11-05-01-roles.sql`.
- [ ] Every test gives the result written next to it.

### A2. Wilayas
- [ ] Profile tab: the wilaya is now a dropdown with 58 items ("01 - Adrar" … "58 - El Meniaa"). Save, then reopen: the choice is still there.
- [ ] Your old wilaya was converted (for example "alger" became "16 - Alger"). If your old wilaya was unclear, the field is empty: choose one.
- [ ] Requests tab: the wilaya filter shows the new names.
- [ ] **SQL test T2 in `02-wilayas.sql` gives an error (a typed wilaya is refused).**

### A3b. Consent
- [ ] Profile → Student space → My results → Upload: the consent screen opens first. "Continue" only works after you tick the box.
- [ ] Press "Not now": nothing is uploaded.
- [ ] After you agree, Student space shows "You agreed on <today>". The next upload does not ask again.
- [ ] Get verified → Send for review also asks for consent first (if not given yet).
- [ ] Table Editor → document_consents has one row with today's date.
- [ ] **A brand-new account that never agreed cannot upload results or a passport, even without the screen (the database refuses it).**

### B1. Student record (Student A, then Student B)
- [ ] Profile → Student space → My student record: fill every field, Save, then reopen. Everything is still there.
- [ ] A wrong phone ("abc") or a finish year before the start year cannot be saved.
- [ ] Student B fills in their own record too.

### B2. Results (Student A)
- [ ] Upload a PDF for 2025-2026, Semester 1. It appears in the list. Tap it: it opens.
- [ ] Choosing a non-PDF file, or a PDF over 10 MB, is refused.
- [ ] Delete it: it disappears, and Storage → academic-results has no file left for it.
- [ ] Upload one again (you need it for the D tests).

### B3. Second student must NOT see the first (log in as Student B)
- [ ] **My student record shows only B's own record, never A's.**
- [ ] **My results shows only B's files.**
- [ ] **SQL Editor (replace the ids). Each must return 0 rows or an error:**
  ```sql
  begin;
    set local role authenticated;
    set local request.jwt.claims = '{"sub":"STUDENT-B-ID","role":"authenticated"}';
    select * from public.student_records where user_id = 'STUDENT-A-ID';
    select * from public.academic_results where user_id = 'STUDENT-A-ID';
    select * from public.attestation_requests where user_id = 'STUDENT-A-ID';
    select * from storage.objects where bucket_id in ('academic-results','passports','attestations')
      and name like 'STUDENT-A-ID/%';
    select * from public.access_log;
    select * from public.document_consents where user_id = 'STUDENT-A-ID';
  rollback;
  ```
- [ ] **Same block, but try to change A's record. It must say UPDATE 0:**
  `update public.student_records set phone = '0000000000' where user_id = 'STUDENT-A-ID';`
- [ ] **Student B has no "Students", "Attestation requests" or "Posters" buttons in Profile.**

### C1. Ask for an attestation (Student A)
- [ ] Student space → Attestation de bourse → Ask: choose a passport photo or PDF. The status shows "Sent, waiting".
- [ ] The button now says "You already have a request in progress" (only one at a time).

### C2. Staff handles it (log in as admin or attaché)
- [ ] Profile shows "Staff (admin)" with the buttons Students, Attestation requests, Final list, Posters, Access log.
- [ ] Attestation requests → open A's request → Open passport. It opens in the browser.
- [ ] Mark as being reviewed. **Student A gets a notification** (bell, and a push if the phone has notifications on). Tapping it opens the attestation screen.
- [ ] Upload attestation (PDF) and issue. A gets "Your attestation de bourse is ready", and in Student space "Download my attestation" works.
- [ ] Try a second request and Reject it with a note. A sees "Not accepted" and the note.
- [ ] **Student B does not see A's attestation (B3 SQL block above).**
- [ ] **Rep: no "Attestation requests" button. In the SQL Editor as the Rep, `select * from attestation_requests` returns 0 rows.**
- [ ] **Rep and students cannot call set_attestation_status (as Student A in the SQL Editor: `select set_attestation_status('REQUEST-ID','ISSUED')` gives an error).**

### C3. Passport deletion
- [ ] On the issued request, press "Delete passport scan now". The button changes to "Passport scan deleted on <date>", and the file is gone from Storage → passports.
- [ ] Automatic deletion: in the SQL Editor run
  `update attestation_requests set issued_at = now() - interval '31 days' where id = 'ANOTHER-ISSUED-ID';`
  then wait for 02:30 UTC, or in Supabase → Edge Functions → purge-passports, send a test request with the header `x-cron-secret`. The passport is deleted.

### D1. Students list
- [ ] Admin: Students shows everyone. The wilaya and year filters work.
- [ ] Rep: Students shows ONLY students of the rep's wilaya (A, not B). The wilaya cannot be changed.
- [ ] Tap Student A → results list → tap a file: it opens.
- [ ] **Rep opening Student B's results is impossible: B is not in the list, and in the SQL Editor as the Rep, `select * from student_records where user_id='STUDENT-B-ID'` returns 0 rows.**

### D2. Compile results PDF
- [ ] Students → choose a wilaya AND a year → "Compile results PDF" → Build part 1 → Open.
- [ ] The PDF has a cover page with the list, then a page per student followed by their results.
- [ ] Rep can compile their own wilaya. **Rep compiling another wilaya gets "Not allowed".**
- [ ] The link stops working after 1 hour.
- [ ] Limits: if a part fails with a time or memory error, open `supabase/functions/staff-reports/index.ts`, make `MAX_STUDENTS_PER_PART` smaller (for example 4), and deploy again.

### D3. Final list
- [ ] Admin: Final list → Export as PDF opens a landscape table. Export as CSV downloads a file that opens in Excel with correct accents.
- [ ] Ask the attaché which columns they want. They are listed in `staff-reports/index.ts` under "Columns of the final list".
- [ ] **A rep or student calling it gets "Not allowed".**

### D4. Access log
- [ ] Admin → Access log shows every "Opened passport", "Opened results", "Compiled results", "Exported final list" and "Deleted passport", with who and when.
- [ ] **SQL Editor (as postgres, even you): `delete from access_log;` and `update access_log set kind = 'X';` both give "The access log cannot be changed or deleted".**

### E1–E3. Posters
- [ ] Admin → Posters → + : choose a 16:9 image, a title, an optional link, dates, position 1, Active. Save.
- [ ] Requests tab: the carousel appears at the top. Add a 2nd poster: it slides every 4 seconds, you can swipe it, and the dots follow.
- [ ] Tap: opens the link, or the full poster if there is no link.
- [ ] A 2nd active poster with the same position is refused with a clear message (so at most 4 active).
- [ ] Turn all posters off: the carousel disappears.
- [ ] Delete a poster: the image is gone from Storage → posters.
- [ ] **Student: no Posters button; in the SQL Editor as a student, `insert into posters ...` gives an error.**

### A4. Delete account (use a throw-away account)
Give it: a profile photo, a listing with a photo, a chat photo, a student record, a results PDF, a passport request.
- [ ] Profile → Delete my account → type DELETE. The app returns to the login screen.
- [ ] Storage: nothing left in its folder in listings, verification, academic-results, passports, attestations, or its photos in chat-photos.
- [ ] The other person in that chat sees "Photo removed" instead of the photo. The text messages are still there.
- [ ] Table Editor: no rows left for it in student_records, academic_results, attestation_requests, document_consents. access_log rows stay (on purpose).

---

## Good to know

- New texts are in English. French and Arabic translations for these screens can be added later in `lib/l10n.dart`.
- The public privacy page `docs/privacy-policy.html` and the in-app privacy text were updated. Upload the new page wherever your Play Store privacy link points.
- The 58-wilaya list is in two places that must match: `lib/wilayas.dart` and `is_valid_wilaya()` in `sql/2026-11-05-01-roles.sql`.
