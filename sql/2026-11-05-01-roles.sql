-- A1. Roles: student (default), rep, attache, admin.
-- Run this once in the Supabase SQL Editor. It is safe to run again.
--
-- What it adds:
--   profiles.role        'student' | 'rep' | 'attache' | 'admin'
--   profiles.rep_wilaya  the one wilaya a rep looks after, e.g. '16 - Alger'
--   is_valid_wilaya(w)   true only for one of the 58 official wilayas
--   is_staff()           true if the logged-in user is attache or admin
--   is_rep_for(w)        true if the logged-in user is the rep of wilaya w
--   my_role()            the logged-in user's own role and rep_wilaya
--
-- Only the owner changes role and rep_wilaya, here in the SQL Editor.
-- A trigger stops any app user from changing them, even on their own row.

begin;

-- ---------------------------------------------------------------
-- 1. The 58 wilayas (official number + name). The app uses the same
--    list for its dropdown (item A2). Never typed by hand.
-- ---------------------------------------------------------------
create or replace function public.is_valid_wilaya(w text)
returns boolean
language sql
immutable
as $$
  select w = any (array[
    '01 - Adrar', '02 - Chlef', '03 - Laghouat', '04 - Oum El Bouaghi',
    '05 - Batna', '06 - Béjaïa', '07 - Biskra', '08 - Béchar',
    '09 - Blida', '10 - Bouira', '11 - Tamanrasset', '12 - Tébessa',
    '13 - Tlemcen', '14 - Tiaret', '15 - Tizi Ouzou', '16 - Alger',
    '17 - Djelfa', '18 - Jijel', '19 - Sétif', '20 - Saïda',
    '21 - Skikda', '22 - Sidi Bel Abbès', '23 - Annaba', '24 - Guelma',
    '25 - Constantine', '26 - Médéa', '27 - Mostaganem', '28 - M''Sila',
    '29 - Mascara', '30 - Ouargla', '31 - Oran', '32 - El Bayadh',
    '33 - Illizi', '34 - Bordj Bou Arréridj', '35 - Boumerdès', '36 - El Tarf',
    '37 - Tindouf', '38 - Tissemsilt', '39 - El Oued', '40 - Khenchela',
    '41 - Souk Ahras', '42 - Tipaza', '43 - Mila', '44 - Aïn Defla',
    '45 - Naâma', '46 - Aïn Témouchent', '47 - Ghardaïa', '48 - Relizane',
    '49 - Timimoun', '50 - Bordj Badji Mokhtar', '51 - Ouled Djellal', '52 - Béni Abbès',
    '53 - In Salah', '54 - In Guezzam', '55 - Touggourt', '56 - Djanet',
    '57 - El M''Ghair', '58 - El Meniaa'
  ]);
$$;

grant execute on function public.is_valid_wilaya(text) to anon, authenticated;

-- ---------------------------------------------------------------
-- 2. New columns on profiles
-- ---------------------------------------------------------------
alter table public.profiles
  add column if not exists role text not null default 'student',
  add column if not exists rep_wilaya text;

alter table public.profiles
  drop constraint if exists profiles_role_check,
  add constraint profiles_role_check
    check (role in ('student', 'rep', 'attache', 'admin'));

-- A rep must have exactly one valid wilaya. Everyone else has none.
alter table public.profiles
  drop constraint if exists profiles_rep_wilaya_check,
  add constraint profiles_rep_wilaya_check
    check (
      (role = 'rep' and rep_wilaya is not null and public.is_valid_wilaya(rep_wilaya))
      or (role <> 'rep' and rep_wilaya is null)
    );

-- ---------------------------------------------------------------
-- 3. Nobody can give themselves a role
--    - New profiles always start as student with no rep_wilaya.
--    - App users (roles anon / authenticated) can never change
--      role or rep_wilaya. The SQL Editor (owner) still can.
-- ---------------------------------------------------------------
create or replace function public.protect_profile_role()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    new.role := 'student';
    new.rep_wilaya := null;
  elsif (new.role is distinct from old.role
         or new.rep_wilaya is distinct from old.rep_wilaya)
        and current_user in ('anon', 'authenticated') then
    raise exception 'Only the owner can change role or rep_wilaya';
  end if;
  return new;
end;
$$;

drop trigger if exists protect_profile_role on public.profiles;
create trigger protect_profile_role
before insert or update on public.profiles
for each row execute function public.protect_profile_role();

-- ---------------------------------------------------------------
-- 4. Helper functions for security rules (RLS) and the app.
--    security definer: they read profiles directly, but they only
--    ever look at the logged-in user's own row (auth.uid()).
-- ---------------------------------------------------------------
create or replace function public.is_staff()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role in ('attache', 'admin')
  );
$$;

create or replace function public.is_rep_for(w text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'rep' and rep_wilaya = w
  );
$$;

-- The app calls this to know which screens to show. Showing or hiding a
-- screen is not security: the RLS rules using is_staff() / is_rep_for() are.
create or replace function public.my_role()
returns table (role text, rep_wilaya text)
language sql
stable
security definer
set search_path = public
as $$
  select p.role, p.rep_wilaya from public.profiles p where p.id = auth.uid();
$$;

revoke execute on function public.is_staff() from public;
revoke execute on function public.is_rep_for(text) from public;
revoke execute on function public.my_role() from public, anon;
grant execute on function public.is_staff() to anon, authenticated;
grant execute on function public.is_rep_for(text) to anon, authenticated;
grant execute on function public.my_role() to authenticated;

commit;

-- ---------------------------------------------------------------
-- HOW THE OWNER SETS STAFF (run by hand when needed, not part of this file)
-- ---------------------------------------------------------------
-- update public.profiles set role = 'admin'   where id = 'USER-ID-HERE';
-- update public.profiles set role = 'attache' where id = 'USER-ID-HERE';
-- update public.profiles set role = 'rep', rep_wilaya = '16 - Alger' where id = 'USER-ID-HERE';
-- Back to student (rep_wilaya must be emptied at the same time):
-- update public.profiles set role = 'student', rep_wilaya = null where id = 'USER-ID-HERE';

-- ---------------------------------------------------------------
-- TESTS (run each block on its own in the SQL Editor after the file above)
-- Replace STUDENT-A-ID and STUDENT-B-ID with two real student ids from
-- the profiles table. Every block ends with rollback, so nothing is saved.
-- ---------------------------------------------------------------
-- T1. Everyone is a student now (expect one row: student | <count>)
-- select role, count(*) from public.profiles group by role;
--
-- T2. Student A tries to make themselves admin (expect ERROR "Only the owner...")
-- begin;
--   set local role authenticated;
--   set local request.jwt.claims = '{"sub":"STUDENT-A-ID","role":"authenticated"}';
--   update public.profiles set role = 'admin' where id = 'STUDENT-A-ID';
-- rollback;
--
-- T3. Student A tries to set their own rep_wilaya (expect ERROR)
-- begin;
--   set local role authenticated;
--   set local request.jwt.claims = '{"sub":"STUDENT-A-ID","role":"authenticated"}';
--   update public.profiles set rep_wilaya = '16 - Alger' where id = 'STUDENT-A-ID';
-- rollback;
--
-- T4. Student A tries to change student B's role (expect ERROR or "UPDATE 0")
-- begin;
--   set local role authenticated;
--   set local request.jwt.claims = '{"sub":"STUDENT-A-ID","role":"authenticated"}';
--   update public.profiles set role = 'admin' where id = 'STUDENT-B-ID';
-- rollback;
--
-- T5. Student A still sees false from the helpers (expect false | false | student)
-- begin;
--   set local role authenticated;
--   set local request.jwt.claims = '{"sub":"STUDENT-A-ID","role":"authenticated"}';
--   select public.is_staff(), public.is_rep_for('16 - Alger'), (select role from public.my_role());
-- rollback;
--
-- T6. A rep without a wilaya, or with a typed wilaya, is refused (expect ERROR both times)
-- begin;
--   update public.profiles set role = 'rep' where id = 'STUDENT-A-ID';
-- rollback;
-- begin;
--   update public.profiles set role = 'rep', rep_wilaya = 'alger' where id = 'STUDENT-A-ID';
-- rollback;
--
-- T7. The owner can make a rep, and the helpers then say yes (expect true for 16, false for 31)
-- begin;
--   update public.profiles set role = 'rep', rep_wilaya = '16 - Alger' where id = 'STUDENT-A-ID';
--   set local role authenticated;
--   set local request.jwt.claims = '{"sub":"STUDENT-A-ID","role":"authenticated"}';
--   select public.is_rep_for('16 - Alger'), public.is_rep_for('31 - Oran'), public.is_staff();
-- rollback;
