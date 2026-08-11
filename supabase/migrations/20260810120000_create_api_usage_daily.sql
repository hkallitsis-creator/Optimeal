-- Create api_usage_daily: shared usage-counter table for both AI-cost
-- rate-limiting and paywall usage-cap gating (one mechanism, not two
-- competing systems — see CLAUDE.md "Monetization / paywall tier structure").
-- NOTE: This migration is safe to re-run (IF NOT EXISTS guards).

create table if not exists public.api_usage_daily (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  feature text not null,
  usage_date date not null,
  count int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, feature, usage_date)
);

create index if not exists idx_api_usage_daily_user_feature on public.api_usage_daily (user_id, feature, usage_date);

alter table public.api_usage_daily enable row level security;

-- Reuses the same set_updated_at() trigger function created by the
-- user_profiles migration.
drop trigger if exists trg_api_usage_daily_set_updated_at on public.api_usage_daily;
create trigger trg_api_usage_daily_set_updated_at
before update on public.api_usage_daily
for each row
execute function public.set_updated_at();

-- Owner-only access.
drop policy if exists "api_usage_daily_select_own" on public.api_usage_daily;
create policy "api_usage_daily_select_own"
on public.api_usage_daily
for select
using (user_id = auth.uid());

drop policy if exists "api_usage_daily_insert_own" on public.api_usage_daily;
create policy "api_usage_daily_insert_own"
on public.api_usage_daily
for insert
with check (user_id = auth.uid());

drop policy if exists "api_usage_daily_update_own" on public.api_usage_daily;
create policy "api_usage_daily_update_own"
on public.api_usage_daily
for update
using (user_id = auth.uid())
with check (user_id = auth.uid());

-- Atomic increment, callable via .rpc('increment_api_usage', ...). Runs as
-- the calling user (security invoker, the default) so RLS above still
-- applies — this only ever touches auth.uid()'s own rows.
create or replace function public.increment_api_usage(p_feature text)
returns int
language plpgsql
security invoker
as $$
declare
  v_count int;
begin
  insert into public.api_usage_daily (user_id, feature, usage_date, count)
  values (auth.uid(), p_feature, current_date, 1)
  on conflict (user_id, feature, usage_date)
  do update set count = public.api_usage_daily.count + 1, updated_at = now()
  returning count into v_count;
  return v_count;
end;
$$;
