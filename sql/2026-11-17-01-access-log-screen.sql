-- "Recent access" screen: the access log can be read ONLY through a function.
-- Run AFTER 2026-11-16-01-members.sql (any time after file 08 works: it needs the access_log
-- table, is_staff(), student_records and profiles). Safe to run twice. Deletes nothing.
--
-- WHO CAN DO WHAT
--   recent_access(person, kind)
--     attache / admin       : call it (it checks is_staff() inside)
--     Governors, students   : "Not allowed"
--     signed out            : cannot even run it
--   the table access_log
--     nobody from the app can read it directly any more (the rule is revoked below).
--     The Edge Functions (service role) and the logging functions (security definer)
--     keep working. The table still cannot be changed or deleted by anyone.
--   To undo the revoke later:  grant select on public.access_log to authenticated;
--
-- WHAT THE FUNCTION RETURNS (at most 100 rows, newest first)
--   when, who (name and role), what (kind), which student (name), wilaya, academic year.
--   Never a phone, a bank account, a passport number, an email or a file path:
--   the log does not hold them and the function does not read them.
--   person : optional text. Rows where the NAME of the actor or of the student contains it.
--   kind   : optional. Only rows of this kind.

begin;

create or replace function public.recent_access(
  p_person text default null,
  p_kind   text default null
)
returns table (
  id            bigint,
  created_at    timestamptz,
  actor_id      uuid,
  actor_name    text,
  actor_role    text,
  kind          text,
  student_id    uuid,
  student_name  text,
  wilaya        text,
  academic_year text
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  q text := lower(nullif(trim(coalesce(p_person, '')), ''));
begin
  if not public.is_staff() then
    raise exception 'Not allowed';
  end if;

  return query
  select x.id, x.created_at, x.actor_id, x.actor_name, x.actor_role, x.kind,
         x.student_id, x.student_name, x.wilaya, x.academic_year
  from (
    select l.id,
           l.created_at,
           l.actor_id,
           -- automatic jobs (cleanup) have no person
           case when l.actor_role = 'system' then null else ap.full_name::text end as actor_name,
           l.actor_role::text as actor_role,
           l.kind::text as kind,
           l.student_id,
           coalesce(
             nullif(trim(coalesce(r.last_name, '') || ' ' || coalesce(r.first_name, '')), ''),
             sp.full_name::text
           ) as student_name,
           l.wilaya::text as wilaya,
           l.academic_year::text as academic_year
    from public.access_log l
    left join public.profiles ap on ap.id = l.actor_id
    left join public.student_records r on r.user_id = l.student_id
    left join public.profiles sp on sp.id = l.student_id
    where p_kind is null or l.kind = p_kind
  ) x
  where q is null
     or position(q in lower(coalesce(x.actor_name, ''))) > 0
     or position(q in lower(coalesce(x.student_name, ''))) > 0
  order by x.created_at desc, x.id desc
  limit 100;
end;
$$;

revoke execute on function public.recent_access(text, text) from public, anon;
grant execute on function public.recent_access(text, text) to authenticated;

-- The app reads the log only through the function above.
revoke select on public.access_log from authenticated;

commit;
