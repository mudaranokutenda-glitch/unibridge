-- A2. Wilaya is chosen from the fixed list of 58, never typed.
-- Run AFTER 2026-11-05-01-roles.sql (it uses is_valid_wilaya()).
-- Run this once in the Supabase SQL Editor. It is safe to run again.
--
-- 1. Old typed values ("alger", "Bejaia ", "16") become the official
--    form ("16 - Alger"). Values that match nothing become 'OTHER'
--    (= not chosen yet), so those users simply pick again in the app.
-- 2. From now on profiles.wilaya must be 'OTHER' or one of the 58.

-- Stop here if profiles.wilaya is not a plain text column.
do $$
begin
  if (select data_type from information_schema.columns
      where table_schema = 'public' and table_name = 'profiles'
        and column_name = 'wilaya') not in ('text', 'character varying') then
    raise exception 'profiles.wilaya is not a text column. Do not continue: tell Claude.';
  end if;
end $$;

begin;

-- Lower case, no accents, no dashes or apostrophes: "Béjaïa" -> "bejaia"
create or replace function public.wilaya_key(w text)
returns text
language sql
immutable
as $$
  select regexp_replace(
    translate(lower(trim(coalesce(w, ''))),
              'éèêëàâäîïôöûüùçñ', 'eeeeaaaiioouuucn'),
    '[^a-z0-9]', '', 'g');
$$;

-- Turns an old typed value into the official form, or null if unknown.
create or replace function public.official_wilaya(w text)
returns text
language plpgsql
immutable
as $$
declare
  k text := public.wilaya_key(w);
  names text[] := array[
    'Adrar', 'Chlef', 'Laghouat', 'Oum El Bouaghi', 'Batna', 'Béjaïa',
    'Biskra', 'Béchar', 'Blida', 'Bouira', 'Tamanrasset', 'Tébessa',
    'Tlemcen', 'Tiaret', 'Tizi Ouzou', 'Alger', 'Djelfa', 'Jijel',
    'Sétif', 'Saïda', 'Skikda', 'Sidi Bel Abbès', 'Annaba', 'Guelma',
    'Constantine', 'Médéa', 'Mostaganem', 'M''Sila', 'Mascara', 'Ouargla',
    'Oran', 'El Bayadh', 'Illizi', 'Bordj Bou Arréridj', 'Boumerdès',
    'El Tarf', 'Tindouf', 'Tissemsilt', 'El Oued', 'Khenchela',
    'Souk Ahras', 'Tipaza', 'Mila', 'Aïn Defla', 'Naâma', 'Aïn Témouchent',
    'Ghardaïa', 'Relizane', 'Timimoun', 'Bordj Badji Mokhtar',
    'Ouled Djellal', 'Béni Abbès', 'In Salah', 'In Guezzam', 'Touggourt',
    'Djanet', 'El M''Ghair', 'El Meniaa'
  ];
  i int;
  official text;
begin
  if public.is_valid_wilaya(w) then
    return w;
  end if;
  -- A few common other spellings
  k := case k
         when 'algiers' then 'alger'
         when 'alger' then 'alger'
         when 'bougie' then 'bejaia'
         when 'tizi' then 'tiziouzou'
         when 'tipasa' then 'tipaza'
         when 'msila' then 'msila'
         when 'bba' then 'bordjbouarreridj'
         when 'sba' then 'sidibelabbes'
         when 'elmeniaa' then 'elmeniaa'
         when 'elmenia' then 'elmeniaa'
         when 'elmghair' then 'elmghair'
         when 'oumelbouaghi' then 'oumelbouaghi'
         else k
       end;
  for i in 1 .. 58 loop
    official := lpad(i::text, 2, '0') || ' - ' || names[i];
    if k = public.wilaya_key(names[i])
       or k = i::text
       or k = lpad(i::text, 2, '0')
       or k = public.wilaya_key(official) then
      return official;
    end if;
  end loop;
  return null;
end;
$$;

-- 1. Convert old values
update public.profiles
set wilaya = coalesce(public.official_wilaya(wilaya), 'OTHER')
where wilaya is distinct from 'OTHER'
  and not public.is_valid_wilaya(coalesce(wilaya, ''));

-- 2. Only the list (or 'OTHER' = not chosen) from now on
alter table public.profiles
  drop constraint if exists profiles_wilaya_check,
  add constraint profiles_wilaya_check
    check (wilaya is null or wilaya = 'OTHER' or public.is_valid_wilaya(wilaya));

commit;

-- TESTS
-- T1. See what everyone has now (expect only 'OTHER' or 'NN - Name'):
-- select wilaya, count(*) from public.profiles group by wilaya order by wilaya;
--
-- T2. A typed value is refused (expect ERROR ... profiles_wilaya_check):
-- begin;
--   update public.profiles set wilaya = 'alger' where id = 'STUDENT-A-ID';
-- rollback;
