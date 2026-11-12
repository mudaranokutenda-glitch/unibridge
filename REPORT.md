# Big update report (11 November 2026, branch `big-update`)

All 9 stages are built, one git commit per stage. `flutter analyze`: **0 errors, 0 warnings** in `lib/` (only the 6 old "info" hints).
Nothing was run on Supabase and no function was deployed: you do that with the steps below.

**Important: do parts 1 and 2 BEFORE you install the new app on any phone.** The new app reads the new tables. Without them, lists stay empty or show errors.

---

## 1. Deploy the Edge Functions FIRST (terminal, in the project folder)

```
supabase functions deploy chat-cleanup --no-verify-jwt --use-api
supabase functions deploy new-request-push --no-verify-jwt --use-api
supabase functions deploy push-notification --no-verify-jwt --use-api
supabase functions deploy emergency-alert --use-api
supabase functions deploy staff-reports --use-api
supabase functions deploy delete-account --use-api
supabase functions deploy notify-chat-message --use-api
```

- **New:** chat-cleanup, new-request-push and emergency-alert.
- **Changed:**
  - chat-cleanup also deletes files older than 24 hours in `compiled-results`.
  - new-request-push sends nothing if the creator posted another request in the last 10 minutes or has 3 or more open requests.
  - emergency-alert: 2-minute rule, "test to myself", and a warning if not every phone was reached.
  - staff-reports: wilaya filter, bank column, log written before each student's files are read, spreadsheet-formula protection.
  - delete-account: new tables; staff accounts get "Staff accounts are removed by the app owner."
  - push-notification and notify-chat-message: Android channel "general".
- `--no-verify-jwt` is only for the three functions that the database calls with the `x-cron-secret` header. They check that secret themselves.
- No new secret is needed. They use the existing `CRON_SECRET` and `FIREBASE_SERVICE_ACCOUNT`.

## 2. Run the SQL files (Supabase → SQL Editor, in this exact order)

Every file is safe to run twice and deletes no data, except the optional file 99.
The 2026-11-05 files (TESTING.md Step 1) and `sql/2026-11-06-requests-realtime.sql` must already be run.

| # | File | What it adds |
|---|------|--------------|
| 1 | `sql/2026-11-11-01-no-student-id-at-signup.sql` | inscription_number in profiles may be empty; new profiles store NULL |
| 2 | `sql/2026-11-11-02-phone.sql` | Private table user_phones, phone format check, student_wilaya() |
| 3 | `sql/2026-11-11-03-cron-secret.sql` | **Type your real CRON_SECRET in place of `PASTE_YOUR_SECRET` in the SQL Editor only.** Never save it in the file. It is stored once in Supabase Vault |
| 4 | `sql/2026-11-11-04-chat-rules.sql` | Only text and photos; chat closed after your rating; archived_at |
| 5 | `sql/2026-11-11-05-chat-cleanup.sql` | ended_at, nightly job chat-cleanup (03:00 UTC) |
| 6 | `sql/2026-11-11-06-new-request-push.sql` | notification_settings, push when a request is posted (a failed push never blocks posting) |
| 7 | `sql/2026-11-11-07-match-suggestions.sql` | Suggested matching (same two users at most once in 24 hours, never again after a decline) |
| 8 | `sql/2026-11-11-08-student-private-info.sql` | Gender, bank_accounts, passport_numbers, new access log kinds |
| 9 | `sql/2026-11-11-09-staff-contacts.sql` | Staff contacts |
| 10 | `sql/2026-11-11-10-guide-and-help.sql` | Guide (4 empty sections and private bucket guide) and Help (FAQ) |
| 11 | `sql/2026-11-11-11-appointments.sql` | Appointments with the Educational Attaché (at most 3 active per student) |
| 12 | `sql/2026-11-11-12-attestation-entry-date.sql` | Date of entry into Algeria (required for new requests) |
| 13 | `sql/2026-11-11-13-staff-tools.sql` | Search, student details (logged), dashboard, alerts table |
| 14 | `sql/2026-11-11-14-governor-tools.sql` | Results tracker, users without a record, bank accounts (logged) |
| 15 | `sql/2026-11-11-15-match-hardening.sql` | Your file: match_request with a block check, rate_transaction search path |
| 16 | `sql/2026-11-11-16-push-trigger-vault.sql` | Your file: the push trigger reads the secret from the Vault |
| 17 | `sql/2026-11-11-17-open-request-limit.sql` | At most 3 open requests per user |
| 99 | `sql/2026-11-11-99-optional-clear-old-student-ids.sql` | **OPTIONAL, LAST, cannot be undone.** Empties the old student IDs in profiles |

**After 14, 16 and 17**, run this once (it removes table rights the app never needs):

```sql
revoke truncate, references, trigger
  on public.bank_accounts, public.passport_numbers, public.alerts, public.user_phones
  from authenticated;
```

Then check the jobs:

```sql
select jobname, schedule from cron.job;
```

You should see `chat-cleanup | 0 3 * * *`, next to the old `purge-passports`.

Then run the tests in `sql/tests/` (read `sql/tests/README.md` first). Every line must say PASS.
Then TESTING.md part G and part H.

## 3. Things you must add by hand

1. **The emergency sound file is missing.**
   - For now, the "emergency" channel uses the phone's alarm sound.
   - To use your own sound:
     1. Put the file at `android/app/src/main/res/raw/emergency_alert.mp3`. The name must be lower case with no spaces. Create the `raw` folder if needed.
     2. In `lib/push.dart`, set `kEmergencySoundFileAdded = true` and change `kEmergencyChannelId` to `'emergency2'`.
     3. In `supabase/functions/emergency-alert/index.ts`, change `EMERGENCY_CHANNEL` to `"emergency2"`, then deploy emergency-alert again.
   - The new name is needed because Android keeps the first sound of a channel forever.
2. **Contacts.** Log in as attaché or admin: Student space → Contacts → pencil → +.
   - Add the Educational Attaché, and every Governor with their wilaya, phone (+213… or +263…) and email.
3. **Guide texts.** Student space → Guide for new students → open each section (Police, Bank, Bourse, Medical) → +.
4. **Help questions.** Student space → Help → +.
5. **Roles.** As before, in SQL:
   ```sql
   update profiles set role = 'rep', rep_wilaya = '16 - Alger' where id = '...';
   update profiles set role = 'attache' where id = '...';
   ```
6. **Privacy page.** Upload the new `docs/privacy-policy.html` (English and French) wherever your Play Store privacy link points.
7. **The app.** Run `flutter pub get`, then `flutter run`.
   - The `flutter_local_notifications` package was added and `geolocator` was removed.
   - The Android build now uses "core library desugaring". It is in `android/app/build.gradle.kts`, and `flutter_local_notifications` needs it.

## 4. Assumptions (the safest choice where something was unclear)

**Sign-up and profile**
- **handle_new_user is not in the project files**, so I did not rewrite it. A small trigger on `profiles` stores `inscription_number = NULL` for every new profile, whatever handle_new_user sends.
- **Phone number.** It is stored in a new private table `user_phones`, because it is asked on the set-up page, before a student record exists.
  - `student_records.phone` stays, with the same format check. The check uses `NOT VALID`, so old rows are not changed; they must match only when edited.
  - "The student's wilaya" for the Governor rules is the wilaya of the student record, or the profile wilaya if there is no record yet.
- If the `user_phones` table does not exist yet, the set-up page skips the phone check instead of locking everybody out.

**Bank account and passport number**
- **They are in separate tables that only the student can read directly.** The attaché and Governors read them only through database functions that write the access log at the same time: `staff_student_details`, `rep_bank_accounts`, and `staff-reports` with the bank column. A plain table read cannot write a log row, so this is the only way to make sure every view is logged.
- The Governor results tracker shows only "uploaded or not" (no file), so it is not logged. Opening a results file is still logged, as before.

**Matching**
- **"A declined pair is not suggested again" = the same two users.**
- **When both accept a suggestion,** the older request becomes MATCHED with the other person, and the other person's own opposite request is set to CANCELLED, because the exchange now happens in one chat. Only one live suggestion per request, oldest matching request first.
- The match itself is done directly in `respond_match_suggestion`, not through `match_request`, because `match_request` is not in the project files. It sends MATCH_FOUND notifications to both people.
- **New-request push:** batched sends from an Edge Function instead of an FCM topic. A topic cannot leave out the creator, people who switched it off, or blocked users.

**Chat**
- **End date of a request:** a new column `ended_at`, set automatically when the status becomes COMPLETED or CANCELLED. For requests that ended before this update, it is their last change date (`updated_at`). The 30 days count from there.
- "Chat closed after rating" is also enforced in the database: no new message after you rated.

**Notifications and alerts**
- `flutter_local_notifications` is **pinned to 22.3.3**. Version 23 needs Android compileSdk 37 and AGP 9.1.1, and this project uses AGP 9.1.0. An upgrade could break your build.
- **Notification texts written by the server are in English only:** match suggestions, appointments, new requests and pushes. The database does not know each user's language. All in-app texts are in English and French.
- **Emergency alerts** are sent from the Edge Function `emergency-alert`, which checks the role in the database. The alert is saved in `alerts`. The home screen shows a red banner with the newest alert from the last 3 days. Every user can read alerts; nobody can write them from the app.

**Student space and staff data**
- **Staff contacts** can be read by every signed-in user, because they are the official numbers to call. Only the attaché or admin can change them. Their phone numbers must also start with +213 or +263.
- **Guide PDFs** are in a private bucket `guide`, readable by signed-in users, with links valid for 1 hour.
- **Appointments.** Times are shown in the phone's time. The notification texts use Algiers time.
- **Consent.** The consent text now names the Governor, the bank account and the passport number, so its version changed. Every student is asked to agree once more before their next upload.

**Other**
- The old My requests screen stays, because tapping a request notification still opens it.
- Your private file `sql/2026-11-05-roles.sql` contains real account ids, so I **did not commit it**. It stays only on your computer.
- The Governor screens were built together with the attaché screens in `lib/staff_tools.dart`, so their app code is in the "Stage 7" commit. The "Stage 8" commit holds the Governor SQL and tests.
- 156 older texts (Student space, staff screens, posters, consent) were missing French. All of them were added, so every `tr()` text now has French.

## 5. Not finished / not checked

- **Nothing was tested on a phone or on the live database.** That needs your accounts and Supabase. Use TESTING.md part G and the `sql/tests/` files.
- The Edge Functions were not run or type-checked here (that is Deno code). VS Code may show red marks in them; that is the usual known issue.
- The emergency sound file is missing (part 3, item 1).
- Only Android was set up for the new notifications. iOS would need its own setup later.
- TODO item B3 (the two-student test from the 5 November work) is still yours to do.
- If the set-up page runs before SQL file 02 exists, students can't save a phone there. Run the SQL first, as in part 2.
