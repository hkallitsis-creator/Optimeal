-- Create fridge_items: user-logged fridge contents backing the Fridge
-- Countdown feature (decaying-freshness "N items expiring soon" chip on
-- Home). See CLAUDE.md "Retention Features Backlog" item 1.
-- NOTE: This migration is safe to re-run (IF NOT EXISTS guards).
--
-- IMPORTANT (lesson from api_usage_daily, 2026-08-11): RLS policies alone
-- do NOT grant table-level access — Postgres checks both, and a table with
-- perfect RLS but no GRANT still 403s for every request. This migration
-- includes explicit GRANTs so that bug isn't repeated here.

create table if not exists public.fridge_items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  ingredient_name text not null,
  added_date date not null default current_date,
  estimated_shelf_life_days int not null default 5,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_fridge_items_user on public.fridge_items (user_id);

alter table public.fridge_items enable row level security;

-- Reuses the same set_updated_at() trigger function created by the
-- user_profiles migration.
drop trigger if exists trg_fridge_items_set_updated_at on public.fridge_items;
create trigger trg_fridge_items_set_updated_at
before update on public.fridge_items
for each row
execute function public.set_updated_at();

-- Owner-only access.
drop policy if exists "fridge_items_select_own" on public.fridge_items;
create policy "fridge_items_select_own"
on public.fridge_items
for select
using (user_id = auth.uid());

drop policy if exists "fridge_items_insert_own" on public.fridge_items;
create policy "fridge_items_insert_own"
on public.fridge_items
for insert
with check (user_id = auth.uid());

drop policy if exists "fridge_items_update_own" on public.fridge_items;
create policy "fridge_items_update_own"
on public.fridge_items
for update
using (user_id = auth.uid())
with check (user_id = auth.uid());

drop policy if exists "fridge_items_delete_own" on public.fridge_items;
create policy "fridge_items_delete_own"
on public.fridge_items
for delete
using (user_id = auth.uid());

-- Table-level grants (RLS restricts to owned rows on top of this).
grant select, insert, update, delete on public.fridge_items to authenticated;
