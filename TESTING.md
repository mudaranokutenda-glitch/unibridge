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
- [ ] Requests tab: the carousel appears at the top. Add a 2nd poster: it slides every 3 seconds, you can swipe it, and the dots follow.
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


---
---

# Part G. Big update (built 11 November 2026, branch big-update)

First do everything in **REPORT.md** parts 1-3 (SQL, functions, sound file), then `flutter run`.

You need these accounts:
- **Admin** (you) or **Attaché** (role `attache`)
- **Governor A**: role `rep`, `rep_wilaya` = Student A's wilaya
- **Governor B**: role `rep`, another wilaya (for the "must NOT" tests)
- **Student A** (wilaya of Governor A), **Student B** (another wilaya)
- One **brand-new** email account

Lines in **bold** are security tests: they MUST fail for the wrong person.

### SQL tests (SQL Editor)
For each file in `sql/tests/` (see `sql/tests/README.md`): replace the ids, run, and check that every line says PASS.
- [ ] 2026-11-11-02-phone-tests.sql
- [ ] 2026-11-11-04-05-chat-tests.sql
- [ ] 2026-11-11-06-07-notifications-matching-tests.sql
- [ ] 2026-11-11-08-11-student-info-tests.sql
- [ ] 2026-11-11-12-attestation-tests.sql
- [ ] 2026-11-11-13-staff-tools-tests.sql
- [ ] 2026-11-11-14-governor-tests.sql

### Stage 1. Login, profile, language
- [ ] G1. Sign-up shows only name, email and password (no inscription number). Google sign-in still works.
- [ ] G1. In Table Editor → profiles, the new account's `inscription_number` is empty (NULL).
- [ ] G2. The brand-new account sees "Set up your profile" at once: photo, wilaya, phone. No back arrow; the back button does nothing; Save stays grey until all three are filled. "Log out" works.
- [ ] G2. An existing account with no phone sees the page once at the next start, then never again.
- [ ] G3/G4. Profile tab: change the phone to `0555123456` → refused with the red message. `+213555123456` → saved. Reopen: still there.
- [ ] G4. Student space → My student record: the phone must also start with +213 or +263.
- [ ] G5. Profile → Language shows only English and Français. A phone that was on Arabic opens in English.
- [ ] **G4. Student B never sees Student A's phone anywhere in the app (profile card, chat, marketplace).**

### Stage 2. Requests and chat
- [ ] G6. The chat has no location button. An old location message shows "[Location]" and cannot be tapped.
- [ ] G7/G8. The chat has only the photo button and the text box. No download icon at the top.
- [ ] G9. Finish a request (both confirm). Each person sees the rating box in the chat and a "Rate" button on the row in My requests. After rating: "This chat is closed." and no text box.
- [ ] G10. A cancelled request shows a red bar on the side and a red "Cancelled".
- [ ] G11. Clean-up (no need to wait 30 days): in the SQL Editor run
  `update transaction_requests set ended_at = now() - interval '31 days' where id = 'A-COMPLETED-REQUEST-ID';`
  then Supabase → Edge Functions → chat-cleanup → send a test request with the header `x-cron-secret`. The request disappears from both lists, its messages are gone, its photos are gone from Storage → chat-photos, and the rating still counts on the profile.
- [ ] G11. A DISPUTED request with an old `ended_at` is NOT cleaned.

### Stage 3. Home and navigation
- [ ] G12. Requests tab, from the top: profile bar (gold frame if verified, blue otherwise), posters sliding every 3 seconds, "My requests", "New unmatched requests" with Match.
- [ ] G12. With two phones: post a request on one; it appears at the top of the other one's list within a second, without pulling down.
- [ ] G13. The icon at the top right opens Exchange rates. There is no "My requests" icon any more.
- [ ] G14. Bottom bar: Requests, Marketplace, Student space, Profile. Profile has no "Student space" button.
- [ ] G15. Post a listing on phone 1; on phone 2 open the Marketplace tab: it appears. Pulling down also refreshes.

### Stage 4. Notifications and matching
- [ ] G16. With the app OPEN, have someone send you a chat message: it shows in the phone's notification bar (not only inside the app).
- [ ] G16. Android Settings → Apps → UniBridge → Notifications shows two categories: General and Emergency alerts.
- [ ] G17. Student A posts a request: Student B gets "New request: Send 50 USD". Student A gets nothing.
- [ ] G17. Student B turns off Profile → "New request notifications"; A posts again; B gets nothing.
- [ ] **G17. If A blocked B, B does not get A's new requests.**
- [ ] G18. A posts SEND 50 USD, B posts RECEIVE 50 USD: both get "A match is available" and see a "Suggested matches" card on the home screen.
- [ ] G18. Only A accepts: "Waiting for the other student". Then B accepts: the chat opens; A's request is MATCHED with B, and B's own request becomes Cancelled.
- [ ] G18. Decline instead: the card disappears. Posting the same pair again creates no new suggestion.
- [ ] G18. After 24 hours (or set `expires_at` to the past in the SQL Editor) the card disappears and Accept says it has expired.
- [ ] **G18. Two users who blocked each other are never suggested.**

### Stage 5. Student information
- [ ] G19. My student record: Gender (Male/Female), bank account field (digits only, counter 0/20, notice under it). 19 digits cannot be saved.
- [ ] G20. Passport number: letters become capitals; 5 characters or "AB-123" cannot be saved.
- [ ] **G19/G20. Student B never sees Student A's bank account or passport number (SQL test file 08-11).**
- [ ] **G20. A Governor never sees any passport number, in the app or in SQL.**
- [ ] G21. Attaché: Student space → Contacts → pencil → add the attaché and two Governors for Student A's wilaya. Student A sees the attaché and BOTH Governors; call, WhatsApp and email open the right apps.
- [ ] **G21. Student B (other wilaya) does not see Governor A's contact under "Contact your Governor". A student cannot add a contact.**
- [ ] G22. The guide shows Police, Bank, Bourse, Medical ("Coming soon"). The attaché adds an item with a PDF; a student opens it. The PDF link stops working after 1 hour.
- [ ] G23. Help: the attaché adds 3 questions; search finds them by a word of the answer.
- [ ] G24. Student A asks for an appointment (date, time, reason). The attaché gets a notification, opens Profile → Appointments and proposes another time. A is notified and accepts the time. The attaché is notified.
- [ ] G24. Decline with a note: A sees "Declined" and the note.
- [ ] **G24. Student B and Governors see no appointments of Student A.**

### Stage 6. Attestation de bourse
- [ ] G25. Ask for an attestation: first the date of entry, then the passport file. Without the date nothing is sent.
- [ ] G25. The attaché sees the date on the request.
- [ ] **G25. In SQL, a request without the date is refused (test file 12).**

### Stage 7. Educational Attaché
- [ ] G26. Profile → Search students: an empty search is refused; search by part of a name, by inscription number, by wilaya. Tap a result: record, phone, bank account, passport number and results.
- [ ] G26. Profile → Access log shows "Opened student details" with your name and the time.
- [ ] G27. Final list: one wilaya, CSV without bank → no bank column. With the switch on → a warning, then a "Bank account" column. The access log shows "Exported final list with bank accounts".
- [ ] G28. "Governors' contacts" lists all Governors.
- [ ] G29. Emergency alert: write a title and a message → confirmation → sent. Every phone rings on the Emergency channel (alarm sound until you add the mp3), the home screen shows a red banner, and Alerts lists it.
- [ ] **G29. A student or a Governor calling emergency-alert gets "Not allowed" (they have no button; in SQL `insert into alerts` is refused).**
- [ ] G30. Dashboard: one line per wilaya and the total.

### Stage 8. Governor (log in as Governor A)
- [ ] G31. Results tracker: choose a year and a semester; students who uploaded have a green tick, the others a red cross.
- [ ] G32. The dashboard shows only your wilaya. "No student record yet" lists users of your wilaya without a record, with call / WhatsApp buttons.
- [ ] G33. "Contact the Educational Attaché" opens the contacts. Students → tap a student → call / WhatsApp buttons.
- [ ] G34. Bank accounts lists your wilaya's students and accounts. The attaché's Access log shows "Opened the bank account list" for you.
- [ ] **G31-G34. Log in as Governor B: Student A is in none of these lists (results tracker, without record, bank accounts, dashboard).**
- [ ] **G34. Governor A cannot see Student B's bank account or phone (SQL test file 14).**

### Stage 9. Terms, privacy, delete account
- [ ] G36. Profile → Terms and privacy, in English and in French: the "Who can see what" list matches this test list; chats are kept 30 days after a request ends.
- [ ] G36. Upload the new `docs/privacy-policy.html` wherever your Play Store privacy link points.
- [ ] G37. Delete a throw-away account that has a phone, bank account, passport number, appointment and a suggestion: Table Editor has no rows left for it in user_phones, bank_accounts, passport_numbers, notification_settings, appointments, match_suggestions.
