# UniBridge

Flutter app (Android first) for students in Algeria. Two people match, chat, exchange money outside the app, and both must confirm before it counts. The app never holds money. It also has a student marketplace.

The owner is a beginner. Explain changes in simple words, make small changes, and never leave the app broken.

## Stack
- Flutter. All screens are currently in lib/main.dart (to be split into several files).
- Supabase (project ref lhdkzcsaqlhswyytirxb): Postgres, Auth (email + Google), Realtime chat, Storage.
- Firebase (project unibridge-29f11): push notifications only.
- Edge Functions in supabase/functions: notify-chat-message, push-notification, update-rates (hourly exchange rates).

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