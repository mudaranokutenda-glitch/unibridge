# UniBridge to-do list (work from top to bottom)

## Working rules
- One item at a time. Show a plan first and wait for my OK.
- Any SQL goes in the sql/ folder (dated file name). Do not run it. I run it in Supabase.
- After each item: run flutter analyze, tick the item here, and tell me how to test it.
- For anything with passports, results or attestations: follow "Roles and sensitive data" in CLAUDE.md. Show me the security rules and a test checklist before I run any SQL.
- Do not guess the look of the app. Use plain Material widgets until I send the design brief (items F5 and F6).

## In progress
- [ ] Chat extras: photo (done, needs testing), share my location once, download the chat as a text file

## A. Foundations (everything below needs these)
- [ ] A1. Roles: profiles.role is 'student' (default), 'rep', 'attache' or 'admin'. Add profiles.rep_wilaya (the one wilaya a rep looks after). Only I change role and rep_wilaya, by SQL. Add SQL functions is_staff() (true for attache or admin) and is_rep_for(wilaya) for use in the security rules. Nobody can change their own role.
- [ ] A2. One shared list of the 58 wilayas of Algeria, used as a dropdown everywhere a wilaya is chosen.
- [ ] A3. Terms and privacy screen, and a consent screen shown before the first upload of any personal document. The text must say plainly who can see what: the educational attaché (everything), the representative of my wilaya (results only), and the app administrator (who can technically access files in storage). Store the date of consent.
- [ ] A4. Delete my account: removes my records and all my files. Files must be deleted with the Storage API from an Edge Function, because deleting rows in storage.objects with SQL does not delete the files.

## B. Student space
- [ ] B1. Student record form, one per student: first name, last name, program, level, start year, current academic year, phone, wilaya (dropdown), inscription number, expected finish year. A student sees and edits only their own.
- [ ] B2. Results upload: PDF only, max 10 MB, for an academic year and semester. Private bucket academic-results, path <user_id>/<academic_year>/<file>. A student sees, opens and deletes only their own.
- [ ] B3. Test with two student accounts: the second must NOT be able to list or open the first one's files or record.

## C. Attestation de bourse (student and educational attaché)
- [ ] C1. A student asks for an attestation: uploads a passport photo or PDF after giving consent. Private bucket passports. Status: PENDING, IN_REVIEW, ISSUED, REJECTED (with a note).
- [ ] C2. Screen for attache and admin only: list of requests, open the passport, change the status, upload the issued attestation (PDF) to a private bucket attestations. The student gets a notification (notifications table) and can download only their own attestation.
- [ ] C3. After a request is ISSUED, the passport scan is deleted (immediately by staff, or automatically after 30 days; I will confirm the period with the attaché).

## D. Staff dashboards
- [ ] D1. List of students with filters for wilaya and academic year. attache and admin see all wilayas. A rep sees only students of their own wilaya, and never passports or attestations.
- [ ] D2. Compile per wilaya: choose a wilaya and an academic year. One PDF is built: a cover page with the list of students, then each student's results. Do it in a Supabase Edge Function using pdf-lib. The function must check that the caller is attache, admin, or a rep for that wilaya. Store the PDF in a private bucket compiled-results and return a link valid for 1 hour. Warn me about memory and time limits, and work in chunks if needed.
- [ ] D3. Final list of all students (columns decided by the attaché), exportable as PDF or CSV. attache and admin only.
- [ ] D4. Access log: record who opened a passport or a student's results, and when. Nobody can edit or delete log rows.

## E. Sliding posters
- [ ] E1. Table posters: title, image, optional link, start date, end date, position 1 to 4, active. Public bucket posters. Only attache and admin add, edit or delete. At most 4 active at once.
- [ ] E2. Home screen carousel at the top: slides by itself every 4 seconds, can be swiped, shows dots, tap opens the link or the full poster. Hidden when there are no posters. Image ratio 16:9.
- [ ] E3. Screen for attache and admin to add, order and remove posters.

## F. Before launch
- [ ] F1. Report and block a user
- [ ] F2. Fingerprint or face unlock
- [ ] F3. Request filters: type, currency, wilaya
- [ ] F4. Languages (English first, then French and Arabic) and dark mode
- [ ] F5. Polish marketplace, chat and other screens. WAIT for my design brief.
- [ ] F6. Redesign: bottom navigation and new look. WAIT for my design brief.
- [ ] F7. Release preparation: app name and ID, icon, signing key, Play Store listing, privacy policy link
- [ ] F8. Before real students use it: upgrade Supabase to Pro (no pausing, 100 GB storage). Turn on two-step login for my GitHub, Supabase, Firebase and Google accounts.

## Done
- [x] Sign-up, Google login, requests, matching, chat, confirm/dispute, ratings
- [x] Marketplace with photos, categories, sold items
- [x] Push notifications for chat messages
- [x] Profile cards, verification requests, automatic exchange rates
- [x] Split main.dart into several files