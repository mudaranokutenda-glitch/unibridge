# SQL tests (PASS / FAIL)

One test file for each file in `sql/` from 2026-11-11.

How to run a test file:
1. Run its SQL file first (for example `2026-11-11-02-phone.sql`).
2. Open the test file in the Supabase SQL Editor (not in VS Code).
3. In the editor only, replace the placeholders with real ids from Table Editor → profiles:
   - `STUDENT-A-ID`: a student (role student) with a student record in the Governor's wilaya
   - `STUDENT-B-ID`: another student, in a DIFFERENT wilaya from the Governor
   - `GOVERNOR-ID`: a user with role `rep` (the Governor of Student A's wilaya)
   - `ATTACHE-ID`: a user with role `attache` (or `admin`)
4. Press Run. Every check prints a line starting with **PASS** or **FAIL** in the Messages / Notices panel.
5. Every file ends with `rollback`, so nothing is saved.

Every line must say PASS. If one says FAIL, stop and send the line to Claude.

Some checks need data first (for example Student A must have saved a phone in the app). A check prints **SKIP** when that data is missing.
