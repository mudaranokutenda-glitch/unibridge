# UniBridge

Flutter app (Android first) for students in Algeria. Two people match, chat, exchange money outside the app, and both must confirm before it counts. The app never holds money. It also has a student marketplace.

The owner is a beginner. Explain changes in simple words, make small changes, and never leave the app broken.

## Stack
- Flutter. Screens are split into files in lib/ (home, requests, chat, marketplace, profiles, student_space, student_info, staff, staff_tools, ...).
- Languages: English and French only, through tr() in lib/l10n.dart (Arabic was removed on 2026-11-11).
- Supabase (project ref lhdkzcsaqlhswyytirxb): Postgres, Auth (email + Google), Realtime chat, Storage.
- Firebase (project unibridge-29f11): push notifications only.
- Edge Functions in supabase/functions: notify-chat-message, push-notification, update-rates (hourly exchange rates), delete-account, staff-documents, staff-reports, purge-passports, chat-cleanup (nightly), new-request-push, emergency-alert.
- Functions called by the database (cron or triggers) check the x-cron-secret header. The secret is stored once in Supabase Vault (sql/2026-11-11-03-cron-secret.sql) and read with public.cron_secret().

## Commands
- `flutter analyze` after every change. No errors allowed in lib/ (ignore "info" hints).
- `flutter run` and `supabase functions deploy NAME --use-api`: the owner runs these, not you.

## Database
Tables: profiles, transaction_requests, messages, ratings, marketplace_listings, notifications, exchange_rates, verification_requests.
Logic is in SQL functions called with supabase.rpc: match_request, confirm_transaction, open_dispute, rate_transaction, cancel_request, get_public_profiles.
Request status: OPEN -> MATCHED -> SENDER_DONE / RECEIVER_DONE -> COMPLETED (or DISPUTED, CANCELLED). Both sides must confirm.
Storage buckets: listings (public photos), verification (private student cards, only the owner may read).

## Rules
- Never put a secret in any file: no service_role key, no Firebase service-account file, no CRON_SECRET value. SQL files use the placeholder PASTE_YOUR_SECRET.
- Never change the live Supabase project yourself. Put every database change in a new file in sql/ named with the date (for example sql/2026-11-02-chat-photos.sql). The owner reads it and runs it in the Supabase SQL Editor.
- Other users must not read private profile columns (fcm_token, student ID, flags). Show other people only through get_public_profiles. Do not reopen column access.
- Users may update only wilaya, location, profile_picture_url and fcm_token on their own profile. Verification and trust score are changed only by the owner.
- Never add a feature that holds or moves money.
- Marketplace cards must not show ratings (the owner removed them on purpose).
- One feature per change. Show a short plan first for anything bigger than a few lines.
- Harmless known issues: VS Code errors inside supabase/functions/**/index.ts (that is Deno code), and test/widget_test.dart (old sample).
messages columns: id, request_id, sender_id, type (enum message_type: TEXT, IMAGE, DOCUMENT, LOCATION, CONTACT, QUICK_REPLY, SYSTEM), content, attachment_url, created_at.

## Roles and sensitive data
- profiles.role is 'student' (default), 'rep', 'attache' or 'admin'. A rep also has profiles.rep_wilaya. Only the owner changes them, in SQL. A user must never be able to update their own role or rep_wilaya.
- The staff are the Educational Attaché of Zimbabwe (role attache), the wilaya representatives (role rep) and the owner (role admin). The attaché's office is in the embassy, but this is not an embassy app.
- Security is enforced in the database rules (RLS). Hiding a button in the app is not security.
- Student results, passports and attestations are private files in private buckets. A student sees only their own. attache and admin see all. A rep sees student records and results only for their own wilaya, never passports or attestations. Nobody else.
- Never make those buckets public. Never put file paths or signed links in notifications, logs or chat.
- Signed links last at most 1 hour.
- Deleting rows from storage.objects with SQL does not delete the file. Delete files with the Storage API from an Edge Function.
- Wilaya is always chosen from the fixed list of 58, never typed.
- A student's inscription number and phone are never shown to other students.
- For every new table or bucket, show me the security rules and a test checklist (what a second student must NOT be able to do) before I run the SQL.
- Whenever a new bucket or a table with personal data is added, also update the delete-account function so it removes that user's files and rows.

## Words used in the app
- The wilaya representative is called "Governor" in the app (database role 'rep'). The educational attaché is "Educational Attaché" (role 'attache'). The admin is the owner.

## Security rules (added 2026-11-11, apply to every change)
- Row-level security on every new table. Checks use is_staff() and is_rep_for(wilaya) in the database, never the app.
- Bank account number (table bank_accounts): readable only by the student, attache/admin, and the Governor of that student's wilaya.
- Passport number (table passport_numbers) and passport files: readable only by the student and attache/admin. Never by a Governor.
- Phone numbers (table user_phones, and student_records.phone): never readable by other students. Only the student, attache/admin, and the Governor of that student's wilaya.
- None of these ever appear in get_public_profiles, notifications, logs or chat.
- Every time staff or a Governor views or exports bank accounts, passport numbers, passport files or results, write a row to access_log. That is why staff and Governors read bank accounts and passport numbers only through security definer functions that write the log (staff_student_details, rep_bank_accounts, staff-reports), never directly from the tables.
- Edge Functions identify the caller from the login token and read the role from the database. Signed links last at most 1 hour.
- Never delete existing user data in a migration (an exception goes in its own optional file).
- Phone numbers must match ^\+(263|213)[0-9]{8,10}$ (app and database, function is_valid_phone).
- Chats (messages and photos) are deleted 30 days after a request is COMPLETED or CANCELLED (chat-cleanup). The request row and ratings stay. DISPUTED requests are never cleaned.
