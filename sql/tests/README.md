# SQL tests (PASS / FAIL / SKIP)

These tests check the database security rules. They are plain SQL files that you run in the
Supabase SQL Editor. **They never save anything**: all changes are undone at the end.

## Step 1: the four test accounts (once)

The tests need four real accounts. **They must be four different accounts**: the tests check
what one person can and cannot see of another, so two roles on one account would prove nothing
(the setup check refuses it). Use throw-away accounts if you can.

| Key | Who | Must be |
|---|---|---|
| `STUDENT_A` | Student A | role `student`, with a **student record** (saved in the app), in the Governor's wilaya |
| `STUDENT_B` | Student B | role `student`, in a **different wilaya** from the Governor |
| `GOVERNOR` | the Governor | role `rep`, and `rep_wilaya` **equal to Student A's wilaya** |
| `ATTACHE` | the Educational Attaché | role `attache`. **It can be your own `admin` account** (admin counts as the attaché) |

Student A and Student B must not have blocked each other.

1. Open `00-test-accounts.sql` **in the Supabase SQL Editor** (not in VS Code).
2. In the editor only, replace `STUDENT-A-EMAIL`, `STUDENT-B-EMAIL`, `GOVERNOR-EMAIL` and
   `ATTACHE-EMAIL` with the four login emails. Press **Run**. The four saved rows are shown.
3. You never have to do this again. Running it a second time just updates the emails.

The emails are kept in a private table `test_support.accounts` that the app (signed in or not)
cannot read. **Never save your real emails in the file in the project.** If you want a local copy
with your emails, name it `00-test-accounts.local.sql`: git ignores that name.

**Before launch, run `99-remove-test-accounts.sql`.** It drops the schema `test_support`, and the
emails with it. Nothing else is touched.

## Step 2: run a test file

1. Run the SQL files from `sql/` first (see REPORT.md part 2, files 01 to 17).
2. Open a test file in the SQL Editor, paste it, and press **Run**. **There is nothing to
   replace**: the test finds the four accounts by their emails and uses their ids by itself.

## How to read the result

The last step of every file raises an error **on purpose**, and the result is inside the error
message. This is also what undoes everything. You will see something like:

```
RESULT SUMMARY: 24 PASS, 0 FAIL, 1 SKIP
PASS T0 profiles.inscription_number may be empty
PASS T1 phone format: ...
SKIP T4 gender must be MALE or FEMALE -> Student A has no student record
...
```

- **Every line must say PASS.** If a line says **FAIL**, the text after `->` says what really
  happened (for example `refused with the wrong error 23505 (...)`). Send that line to Claude.
- **SKIP** means a check could not be done (the text after `->` says why, for example
  "run file 17 first"). A SKIP is not a pass. Fix the reason and run the file again.
- **"Success. No rows returned" and no result lines means NOTHING was checked.** Something
  stopped the run before the summary, or the file was not run completely. Run it again, and
  make sure you pressed Run on the whole file (nothing selected, or everything selected).
- **`SETUP PROBLEM: ...`** (one line, no tests run) says exactly what is wrong: `00` was not run,
  an email was not found in `auth.users`, an account has no profile or the wrong role, two
  accounts are the same, or a wilaya does not match. Fix it and run again.

A "must be refused" check passes **only** if it fails with the expected error code (for example
`42501` = not allowed by the security rules, `23514` = a check rule, `P0001` = a message written
by our own functions). Any other error is a FAIL, so a typo in a test cannot give a false PASS.

## The files

| File | What it does |
|---|---|
| `00-test-accounts.sql` | run once: saves the four test emails in `test_support.accounts` |
| `2026-11-11-02-phone-tests.sql` | phone format, who can read or change a phone |
| `2026-11-11-04-05-chat-tests.sql` | secret not readable, only text and photos, chat closed after rating and after the 30-day clean-up |
| `2026-11-11-06-07-notifications-matching-tests.sql` | notification settings, suggested matching, only the two people can answer |
| `2026-11-11-08-11-student-info-tests.sql` | bank account, passport number, contacts, guide, help, appointments, attaché and Governor limits |
| `2026-11-11-12-attestation-tests.sql` | date of entry and passport file are required |
| `2026-11-11-13-staff-tools-tests.sql` | search, student details (logged), dashboard, access log, alerts |
| `2026-11-11-14-governor-tests.sql` | Governor tools only for their own wilaya, bank list is logged |
| `2026-11-11-18-storage-and-anon-tests.sql` | private files (passports, results, attestations, chat photos), signed-out access, and that the tester emails are private |
| `2026-11-11-19-hardening-tests.sql` | blocked users, 24-hour rule, declined pairs, 3 open requests, 3 active appointments |
| `2026-11-16-01-members-tests.sql` | membership approval: unapproved students are locked out of the Student space, who may approve, the backfill, asking again. Needs `sql/2026-11-16-01-members.sql`. Extra need: Student A's profile wilaya is the Governor's wilaya and Student B's is another |
| `2026-11-17-01-access-log-screen-tests.sql` | the "Recent access" function: only attaché and admin, the 100-row limit, the two filters, no direct read of the table. Needs `sql/2026-11-17-01-access-log-screen.sql` |
| `2026-11-18-01-settings-expiry-notifications-tests.sql` | the four files of 2026-11-18: a user deletes only their own notification, app_settings cannot be changed from the app, OPEN requests older than 48 hours are cancelled (and stay out of the open list), the setting is used, a student cannot set cancel_reason, the attestation step dates. Needs `sql/2026-11-18-01` to `-04` |
| `99-remove-test-accounts.sql` | run before launch: removes the tester emails |

Notes:
- A student **can** delete their own results file (it is a feature). Nobody can delete passports,
  attestations or chat photos. The Educational Attaché **can** read attestation files (staff upload
  them) but never passports or results directly.
- File 19 needs files 07, 11, 15 and 17. If one was not run yet, its checks say SKIP.
- Inside a test, the open requests of Student A and B are cancelled, and their old suggestions,
  blocks and active appointments are removed, so the tests are not disturbed by your own
  testing. This is undone at the end too.
- Fake file rows are added to `storage.objects` for the storage test. No real file is created or
  touched. The test sets `storage.allow_delete_query` only inside itself, so that the security
  rules (and not Supabase's block on direct deletes) decide.
- If you get "permission denied for schema pg_temp", tell Claude: the result table can be
  changed to a normal table that is created and undone inside the same run.
