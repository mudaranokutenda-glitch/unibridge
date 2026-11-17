# UniBridge to-do list (work from top to bottom)

## Working rules
- One item at a time. Show a plan first and wait for my OK.
- Any SQL goes in the sql/ folder (dated file name). Do not run it. I run it in Supabase.
- After each item: run flutter analyze, tick the item here, and tell me how to test it.
- For anything with passports, results or attestations: follow "Roles and sensitive data" in CLAUDE.md. Show me the security rules and a test checklist before I run any SQL.
- Do not guess the look of the app. Use plain Material widgets until I send the design brief (items F5 and F6).

## In progress
- (nothing)

## A. Foundations (everything below needs these)
- [x] A1. Roles (sql/2026-11-05-01-roles.sql): profiles.role is 'student' (default), 'rep', 'attache' or 'admin'. Add profiles.rep_wilaya (the one wilaya a rep looks after). Only I change role and rep_wilaya, by SQL. Add SQL functions is_staff() (true for attache or admin) and is_rep_for(wilaya) for use in the security rules. Nobody can change their own role.
- [x] A2. (built 2026-11-05, test with TESTING.md) One shared list of the 58 wilayas of Algeria, used as a dropdown everywhere a wilaya is chosen.
- [x] A3b. (built 2026-11-05, test with TESTING.md) Consent screen before the first upload of any personal document, saying who can see what, with the date of consent stored. The text must say plainly: the educational attaché (everything), the representative of my wilaya (results only), and the app administrator (who can technically access files in storage).
- [x] A4. (built 2026-11-05, test with TESTING.md) Delete my account: removes my records and all my files. Files must be deleted with the Storage API from an Edge Function, because deleting rows in storage.objects with SQL does not delete the files.

## B. Student space
- [x] B1. (built 2026-11-05, test with TESTING.md) Student record form, one per student: first name, last name, program, level, start year, current academic year, phone, wilaya (dropdown), inscription number, expected finish year. A student sees and edits only their own.
- [x] B2. (built 2026-11-05, test with TESTING.md) Results upload: PDF only, max 10 MB, for an academic year and semester. Private bucket academic-results, path <user_id>/<academic_year>/<file>. A student sees, opens and deletes only their own.
- [ ] B3. (YOU: follow TESTING.md part B) Test with two student accounts: the second must NOT be able to list or open the first one's files or record.

## C. Attestation de bourse (student and educational attaché)
- [x] C1. (built 2026-11-05, test with TESTING.md) A student asks for an attestation: uploads a passport photo or PDF after giving consent. Private bucket passports. Status: PENDING, IN_REVIEW, ISSUED, REJECTED (with a note).
- [x] C2. (built 2026-11-05, test with TESTING.md) Screen for attache and admin only: list of requests, open the passport, change the status, upload the issued attestation (PDF) to a private bucket attestations. The student gets a notification (notifications table) and can download only their own attestation.
- [x] C3. (built 2026-11-05, test with TESTING.md) After a request is ISSUED, the passport scan is deleted (immediately by staff, or automatically after 30 days; I will confirm the period with the attaché).

## D. Staff dashboards
- [x] D1. (built 2026-11-05, test with TESTING.md) List of students with filters for wilaya and academic year. attache and admin see all wilayas. A rep sees only students of their own wilaya, and never passports or attestations.
- [x] D2. (built 2026-11-05, test with TESTING.md) Compile per wilaya: choose a wilaya and an academic year. One PDF is built: a cover page with the list of students, then each student's results. Do it in a Supabase Edge Function using pdf-lib. The function must check that the caller is attache, admin, or a rep for that wilaya. Store the PDF in a private bucket compiled-results and return a link valid for 1 hour. Warn me about memory and time limits, and work in chunks if needed.
- [x] D3. (built 2026-11-05, test with TESTING.md) Final list of all students (columns decided by the attaché), exportable as PDF or CSV. attache and admin only.
- [x] D4. (built 2026-11-05, test with TESTING.md) Access log: record who opened a passport or a student's results, and when. Nobody can edit or delete log rows.

## E. Sliding posters
- [x] E1. (built 2026-11-05, test with TESTING.md) Table posters: title, image, optional link, start date, end date, position 1 to 4, active. Public bucket posters. Only attache and admin add, edit or delete. At most 4 active at once.
- [x] E2. (built 2026-11-05, test with TESTING.md) Home screen carousel at the top: slides by itself every 4 seconds, can be swiped, shows dots, tap opens the link or the full poster. Hidden when there are no posters. Image ratio 16:9.
- [x] E3. (built 2026-11-05, test with TESTING.md) Screen for attache and admin to add, order and remove posters.

## G. Big update (built 2026-11-11 on branch big-update, test with TESTING.md part G)
- [x] G1. Sign-up with email and password only (Google kept); student ID removed from sign-up and profile screens.
- [x] G2. "Set up your profile" page: photo, wilaya, phone number (cannot be skipped).
- [x] G3. Edit profile: photo, wilaya, city, phone number.
- [x] G4. Phone format +213 / +263 (app and database), stored in private table user_phones.
- [x] G5. Arabic removed (a phone saved on Arabic goes back to English).
- [x] G6. Location sharing removed (button, geolocator package, Android permission).
- [x] G7. Chat allows only text and photos (database rule).
- [x] G8. "Download chat" removed (file_picker kept: Student space and staff use it).
- [x] G9. Rate the other person after COMPLETED; the chat is then closed for you.
- [x] G10. Cancelled requests shown in red.
- [x] G11. Chats auto-cleaned 30 days after COMPLETED / CANCELLED (photos, messages); request row and ratings kept.
- [x] G12. Home: profile bar with frame, posters (3 s), My requests (live), New unmatched requests.
- [x] G13. Rates icon at the top right (My requests icon removed).
- [x] G14. Bottom bar: Requests, Marketplace, Student space, Profile.
- [x] G15. Marketplace reloads when the tab is opened, and pull to refresh.
- [x] G16. Notifications in the phone's notification bar while the app is open; channels "general" and "emergency".
- [x] G17. Push to everyone when a new request is posted; switch "New request notifications" in Profile.
- [x] G18. Suggested matching (same amount and currency, opposite type, both must accept, 24 h).
- [x] G19. Student record: gender, bank account number (20 digits).
- [x] G20. Passport number (private table).
- [x] G21. Contacts: Educational Attaché and Governors (call, WhatsApp, email).
- [x] G22. Guide for new students (Police, Bank, Bourse, Medical) with optional PDFs.
- [x] G23. Help: frequently asked questions with search.
- [x] G24. Appointments with the Educational Attaché.
- [x] G25. Attestation de bourse needs the passport file AND the date of entry into Algeria.
- [x] G26. Attaché: search students on the server; student details (logged).
- [x] G27. Final list: filter by wilaya, with or without the bank account column (logged).
- [x] G28. List of all Governors' contacts.
- [x] G29. Emergency alert to every user (confirmation, server check, alerts table, banner).
- [x] G30. Attaché dashboard: students per wilaya and total.
- [x] G31. Governor: results tracker.
- [x] G32. Governor: number of students and users without a student record.
- [x] G33. Governor: contact the attaché and students of their wilaya.
- [x] G34. Governor: bank accounts of their wilaya (view only, logged).
- [x] G35. Governor: dashboard of their wilaya.
- [x] G36. Terms and privacy updated in English and French (app and docs/privacy-policy.html).
- [x] G37. delete-account, CLAUDE.md, TODO.md and TESTING.md updated.
- [x] G38. PASS/FAIL tests in sql/tests/.
- [ ] G39. (YOU) Add android/app/src/main/res/raw/emergency_alert.mp3, then follow REPORT.md part 3.
- [ ] G40. (YOU) Run the SQL, deploy the functions and do the tests in TESTING.md part G.

## M. Student space membership approval (built 2026-11-16 on branch pending-builds-2)
- [x] M1. SQL sql/2026-11-16-01-members.sql: table space_members, is_member(), request_membership(), decide_membership(), pending_members(); restrictive rules so the Student space (contacts, guide, help, appointments, record, results, bank account, passport number, attestation requests and the two private upload buckets) opens only for APPROVED members and staff; backfill makes every existing account APPROVED.
- [x] M2. App: "Join the student space" / "Waiting for approval" / "Not approved" screens in the Student space tab (lib/members.dart); "Join requests" screen for Governors, attaché and admin with Approve and Reject.
- [x] M3. Notifications MEMBERSHIP_UPDATE (request, approved, not approved); push-notification title; delete-account removes the row.
- [x] M4. SQL tests sql/tests/2026-11-16-01-members-tests.sql.
- [x] M6. "Recent access" screen for attaché and admin (Student space; also the Profile button): the last 100 rows of access_log with a filter by person and by kind, read only through the SQL function recent_access() (sql/2026-11-17-01-access-log-screen.sql). The app can no longer read the table directly. Test: sql/tests/2026-11-17-01-access-log-screen-tests.sql.
- [ ] M5. (YOU) Run sql/2026-11-16-01-members.sql after file 17, deploy push-notification and delete-account, run the test file, then test with three accounts (new student, Governor, attaché).

## F. Before launch
- [ ] F5. Polish marketplace, chat and other screens. WAIT for my design brief.
- [ ] F6. New look (colours, fonts, icons): WAIT for my design brief.
- [ ] F8. Before real students use it: upgrade Supabase to Pro (no pausing, 100 GB storage). Turn on two-step login for my GitHub, Supabase, Firebase and Google accounts.

## H. Launch checklist
- [ ] H1. Member approval tested with three accounts (new student, Governor, attaché).
- [ ] H2. Phone test with fake documents.
- [ ] H3. Notifications tested on a second phone.
- [ ] H4. Two-step login turned on for GitHub, Supabase, Firebase and Google.
- [ ] H5. Supabase Pro.
- [ ] H6. Written agreement from the attaché.
- [ ] H7. Contacts, guide and FAQ filled in.
- [ ] H8. Privacy page published.
- [ ] H9. Pilot with 5 to 10 students from Annaba.
- [ ] H10. Lawyer review.
- [ ] H11. Release (Play Store or APK).
- [ ] H12. Emergency sound file.

## I. Meetings (later, postponed)
Postponed: not started. A meeting is only a link (no video inside the app). Needs the member approval (section M) first.
- [ ] I1. (postponed) SQL: table meetings (title, description, date and time, duration, platform, https join link, cancelled) with rules: attaché and admin add, change and cancel; approved members and staff read; no delete.
- [ ] I2. (postponed) Meetings screen in the Student space: Upcoming and Past, a Join button that opens the link, and Add, edit and cancel for attaché and admin.
- [ ] I3. (postponed) Notifications: one push when a meeting is posted or cancelled, and a reminder 1 hour before the start.
- [ ] I4. (postponed) SQL tests for the meetings rules (a student cannot add or change a meeting, links that are not https are refused).

## Done
- [x] Sign-up, Google login, requests, matching, chat, confirm/dispute, ratings
- [x] Marketplace with photos, categories, sold items
- [x] Push notifications for chat messages
- [x] Profile cards, verification requests, automatic exchange rates
- [x] Split main.dart into several files
- [x] Chat extras: photo (location sharing and chat download removed on 2026-11-11)
- [x] A3a. Terms and privacy screen
- [x] F1. Report and block a user
- [x] F2. Fingerprint or face unlock
- [x] F3. Request filters: type, currency, wilaya
- [x] F4. Languages (English and French; Arabic removed on 2026-11-11) and dark mode
- [x] F6 (part). Bottom navigation: Requests, Marketplace, Student space, Profile (Rates is the icon at the top of Requests)
- [x] F7. Release preparation: app name and ID, icon, signing key, Play Store listing, privacy policy link