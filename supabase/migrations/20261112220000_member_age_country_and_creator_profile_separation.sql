-- Keep general membership details separate from optional talent/work profiles.
alter table public.member_private_details
  alter column gender drop not null,
  alter column birth_date drop not null,
  add column if not exists age integer,
  add column if not exists country text;

alter table public.member_private_details
  drop constraint if exists member_private_details_age_check,
  add constraint member_private_details_age_check
    check (age is null or age between 1 and 120),
  drop constraint if exists member_private_details_country_check,
  add constraint member_private_details_country_check
    check (country is null or char_length(btrim(country)) between 2 and 100);
