-- Create user_profiles table for persisted onboarding/profile data.
-- NOTE: This migration is safe to re-run (IF NOT EXISTS guards).

create table if not exists public.user_profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  name text,
  language text not null default 'en',
  dietary_preference text,
  allergies text[] not null default '{}'::text[],
  allergies_custom text,
  portion_size int,
  skill_level text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.user_profiles enable row level security;

-- Ensure updated_at is maintained automatically.
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_user_profiles_set_updated_at on public.user_profiles;
create trigger trg_user_profiles_set_updated_at
before update on public.user_profiles
for each row
execute function public.set_updated_at();

-- Owner-only access.
drop policy if exists "user_profiles_select_own" on public.user_profiles;
create policy "user_profiles_select_own"
on public.user_profiles
for select
using (id = auth.uid());

drop policy if exists "user_profiles_insert_own" on public.user_profiles;
create policy "user_profiles_insert_own"
on public.user_profiles
for insert
with check (id = auth.uid());

drop policy if exists "user_profiles_update_own" on public.user_profiles;
create policy "user_profiles_update_own"
on public.user_profiles
for update
using (id = auth.uid())
with check (id = auth.uid());
