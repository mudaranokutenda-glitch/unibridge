# SQL tests (PASS / FAIL / SKIP)

These tests check the database security rules. They are plain SQL files that you run in the
Supabase SQL Editor. **They never save anything**: all changes are undone at the end.

## The four test accounts

The tests need real accounts (ids from Table Editor → profiles). Use throw-away accounts if you can.

| Placeholder | Who | Must be |
|---|---|---|
| `STUDENT-A-ID` | Student A | role `student`, with a **student record** (saved in the app), in the Governor's wilaya |
| `STUDENT-B-ID` | Student B | role `student`, in a **different wilaya** from the Governor |
| `GOVERNOR-ID` | the Governor | role `rep`, and `rep_wilaya` **equal to Student A's wilaya** |
| `ATTACHE-ID` | the Educational Attaché | role `attache` (or `admin`) |

Student A and Student B must not have blocked each other, and must be two different accounts.

## How to run a test file

1. Run the SQL files from `sql/` first (see REPORT.md part 2, files 01 to 17).
2. Open the test file **in the Supabase SQL Editor** (not in VS Code).
3. In the editor only, replace the placeholders with the real ids (Find and Replace works).
   Never save the real ids into the file in the project.
4. Press **Run**.

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
- **`SETUP PROBLEM: ...`** (one line, no tests run) means a placeholder was not replaced, an
  account does not exist, or a role or wilaya is wrong. Fix it and run again.

A "must be refused" check passes **only** if it fails with the expected error code (for example
`42501` = not allowed by the security rules, `23514` = a check rule, `P0001` = a message written
by our own functions). Any other error is a FAIL, so a typo in a test cannot give a false PASS.

## The files

| File | Checks |
|---|---|
| `2026-11-11-02-phone-tests.sql` | phone format, who can read or change a phone |
| `2026-11-11-04-05-chat-tests.sql` | secret not readable, only text and photos, chat closed after rating and after the 30-day clean-up |
| `2026-11-11-06-07-notifications-matching-tests.sql` | notification settings, suggested matching, only the two people can answer |
| `2026-11-11-08-11-student-info-tests.sql` | bank account, passport number, contacts, guide, help, appointments, attaché and Governor limits |
| `2026-11-11-12-attestation-tests.sql` | date of entry and passport file are required |
| `2026-11-11-13-staff-tools-tests.sql` | search, student details (logged), dashboard, access log, alerts |
| `2026-11-11-14-governor-tests.sql` | Governor tools only for their own wilaya, bank list is logged |
| `2026-11-11-18-storage-and-anon-tests.sql` | private files (passports, results, attestations, chat photos) and signed-out access |
| `2026-11-11-19-hardening-tests.sql` | blocked users, 24-hour rule, declined pairs, 3 open requests, 3 active appointments |

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
