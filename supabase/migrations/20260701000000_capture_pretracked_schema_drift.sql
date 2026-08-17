-- Captures schema that exists live on production but has no prior migration
-- file, per the CLAUDE.md Task 1 migration-completeness audit (2026-08-17).
--
-- DELIBERATELY DATED BEFORE EVERY EXISTING MIGRATION (2026-07-01, earlier
-- than 20260728120000), not "today". Two existing migrations —
-- 20260816120000 and 20260816130000 — already ALTER TABLE
-- public.waste_ledger_events. On a genuinely fresh database, migrations run
-- in filename order, so this file MUST create that table (and everything
-- else pre-dating tracked history) before those two run, or they fail
-- immediately with "relation does not exist". Dating this "today"
-- (2026-08-17) would sort it AFTER those two and defeat the entire point of
-- this migration. This is a backfilled baseline, authored today but
-- representing schema that predates all tracked migrations.
--
-- EVIDENCE AND CONFIDENCE, per table (see chat for full citations):
--   user_meal_plans      - fully evidenced (weekly_planner_screen.dart row-mapping methods)
--   shopping_list_items  - fully evidenced (recovered from git history; feature since removed)
--   waste_ledger_events  - fully evidenced for columns actually written; RLS policy shape inferred
--   user_ledger_totals   - PARTIALLY evidenced: user_id + lifetime_ingredients_rescued are real;
--                          updated_at is a reasonable addition, not directly evidenced
--   recipes              - NO CODE EVIDENCE. Zero references anywhere in lib/. Production has 0 rows
--                          and no feature has ever designed this table's real shape. Minimal
--                          skeleton only (id/user_id/created_at) sufficient to support the
--                          documented RLS policies -- content columns are NOT invented here.
--                          Verify against the real production schema before building anything on it.
--   ingredients          - fully evidenced (supabase_ingredients_service.dart doc comment + Ingredient model)
--   ai_precision_cache   - fully evidenced (supabase/functions/ai-recipe-precision/index.ts, in-repo)
--   increment_ledger_totals() / trg_increment_ledger_totals - RECONSTRUCTED from prose description
--                          only (CLAUDE.md/docs/CHANGELOG.md describe its existence and behavior,
--                          but its real SQL was never captured anywhere). Behavior matched as closely
--                          as documented; verify against the real function before treating as authoritative.
--
-- NOT closed by this migration (flagging, not silently working around):
--   - user_profiles has documented "duplicate" live policies (an old broad ALL policy alongside
--     the 3 granular ones the existing 20260728120000 migration creates) and broader-than-needed
--     `anon` grants, neither of which has ever been captured as exact SQL anywhere. Not reproduced
--     here -- guessing at exact policy text for an already-migrated table risks introducing NEW
--     drift rather than closing the real gap. Flagged, not fixed.
--
-- NOTE: safe to re-run (IF NOT EXISTS guards; REVOKEs are no-ops in Postgres
-- if the privilege was never granted).

-- public.set_updated_at() is normally created by 20260728120000, which
-- sorts AFTER this migration -- duplicated here (identical definition,
-- `create or replace`) so the triggers below don't fail on a fresh push.
-- 20260728120000's later `create or replace` of the same function is a
-- harmless no-op redefinition.
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- =====================================================================
-- user_meal_plans
-- =====================================================================
create table if not exists public.user_meal_plans (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  day_index int not null,
  slot_index int not null,
  title text,
  source text,
  aisle_items jsonb,
  recipe_payload jsonb,
  is_cooked boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, day_index, slot_index)
);

alter table public.user_meal_plans enable row level security;

drop trigger if exists trg_user_meal_plans_set_updated_at on public.user_meal_plans;
create trigger trg_user_meal_plans_set_updated_at
before update on public.user_meal_plans
for each row
execute function public.set_updated_at();

drop policy if exists "user_meal_plans_select_own" on public.user_meal_plans;
create policy "user_meal_plans_select_own" on public.user_meal_plans for select using (user_id = auth.uid());

drop policy if exists "user_meal_plans_insert_own" on public.user_meal_plans;
create policy "user_meal_plans_insert_own" on public.user_meal_plans for insert with check (user_id = auth.uid());

drop policy if exists "user_meal_plans_update_own" on public.user_meal_plans;
create policy "user_meal_plans_update_own" on public.user_meal_plans for update using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "user_meal_plans_delete_own" on public.user_meal_plans;
create policy "user_meal_plans_delete_own" on public.user_meal_plans for delete using (user_id = auth.uid());

-- Documented as "policies and grants both confirmed correctly aligned" --
-- authenticated only, no anon over-grant.
grant select, insert, update, delete on public.user_meal_plans to authenticated;

-- =====================================================================
-- shopping_list_items
-- =====================================================================
create table if not exists public.shopping_list_items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  ingredient_name text not null,
  source text,
  updated_at timestamptz not null default now(),
  unique (user_id, ingredient_name)
);

alter table public.shopping_list_items enable row level security;

drop trigger if exists trg_shopping_list_items_set_updated_at on public.shopping_list_items;
create trigger trg_shopping_list_items_set_updated_at
before update on public.shopping_list_items
for each row
execute function public.set_updated_at();

drop policy if exists "shopping_list_items_select_own" on public.shopping_list_items;
create policy "shopping_list_items_select_own" on public.shopping_list_items for select using (user_id = auth.uid());

drop policy if exists "shopping_list_items_insert_own" on public.shopping_list_items;
create policy "shopping_list_items_insert_own" on public.shopping_list_items for insert with check (user_id = auth.uid());

drop policy if exists "shopping_list_items_update_own" on public.shopping_list_items;
create policy "shopping_list_items_update_own" on public.shopping_list_items for update using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "shopping_list_items_delete_own" on public.shopping_list_items;
create policy "shopping_list_items_delete_own" on public.shopping_list_items for delete using (user_id = auth.uid());

-- Documented as "policies and grants both confirmed correctly aligned" --
-- authenticated only, no anon over-grant. Feature is cut app-side (see
-- CLAUDE.md 2026-08-17), table retained per explicit instruction.
grant select, insert, update, delete on public.shopping_list_items to authenticated;

-- =====================================================================
-- waste_ledger_events
-- Original (pre-idempotency-key, pre-fridge_countdown) shape -- migrations
-- 20260816120000 and 20260816130000 below alter this forward.
-- =====================================================================
create table if not exists public.waste_ledger_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  source text not null,
  recipe_id text,
  ingredients_rescued text[],
  ingredients_count int,
  created_at timestamptz not null default now(),
  constraint waste_ledger_events_source_check
    check (source = any (array['fridge_clearer', 'cook_mode', 'custom_ai_recipe']))
);

alter table public.waste_ledger_events enable row level security;

-- Documented as a single policy ("1 policy") -- a combined owner-scoped
-- ALL policy, not 4 separate command policies.
drop policy if exists "waste_ledger_events_owner_all" on public.waste_ledger_events;
create policy "waste_ledger_events_owner_all" on public.waste_ledger_events
for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Documented as "policy correct; same anon-too-broad gap as user_profiles"
-- -- reproducing that known, accepted, not-yet-fixed gap faithfully rather
-- than silently tightening it while doing an unrelated task.
grant select, insert, update, delete on public.waste_ledger_events to anon, authenticated;

-- =====================================================================
-- user_ledger_totals
-- Columns: user_id + lifetime_ingredients_rescued are real (evidenced in
-- ledger_service.dart). updated_at is a reasonable addition for the
-- trigger below, not directly evidenced -- flagged.
-- =====================================================================
create table if not exists public.user_ledger_totals (
  user_id uuid primary key references auth.users (id) on delete cascade,
  lifetime_ingredients_rescued int not null default 0,
  updated_at timestamptz not null default now()
);

alter table public.user_ledger_totals enable row level security;

drop policy if exists "user_ledger_totals_select_own" on public.user_ledger_totals;
create policy "user_ledger_totals_select_own" on public.user_ledger_totals for select using (user_id = auth.uid());

-- Fixed live 2026-08-15: no INSERT/UPDATE/DELETE grant to anon/authenticated
-- -- writes happen only via the SECURITY DEFINER trigger below.
grant select on public.user_ledger_totals to authenticated;
revoke insert, update, delete on public.user_ledger_totals from anon, authenticated;

-- RECONSTRUCTED, not copied from a real source -- CLAUDE.md/docs/CHANGELOG.md
-- describe this function's existence and behavior (SECURITY DEFINER,
-- AFTER INSERT on waste_ledger_events, increments the rescued count) but
-- its real SQL was never captured verbatim anywhere. Verify against the
-- real function before relying on this being byte-identical to production.
create or replace function public.increment_ledger_totals()
returns trigger
language plpgsql
security definer
as $$
begin
  insert into public.user_ledger_totals (user_id, lifetime_ingredients_rescued, updated_at)
  values (new.user_id, coalesce(new.ingredients_count, 0), now())
  on conflict (user_id)
  do update set
    lifetime_ingredients_rescued = public.user_ledger_totals.lifetime_ingredients_rescued + coalesce(new.ingredients_count, 0),
    updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_increment_ledger_totals on public.waste_ledger_events;
create trigger trg_increment_ledger_totals
after insert on public.waste_ledger_events
for each row
execute function public.increment_ledger_totals();

-- =====================================================================
-- recipes
-- NO CODE EVIDENCE for content columns -- production has 0 rows, nothing
-- in the app reads or writes this table, and no feature has ever designed
-- its real shape. Minimal skeleton only, sufficient to support the
-- documented RLS policies. Do not treat this as the real production
-- schema -- verify/design for real before building "Save if you liked it"
-- (CLAUDE.md roadmap) against this table.
-- =====================================================================
create table if not exists public.recipes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users (id) on delete cascade,
  created_at timestamptz not null default now()
);

alter table public.recipes enable row level security;

drop policy if exists "recipes_select_own" on public.recipes;
create policy "recipes_select_own" on public.recipes for select using (user_id = auth.uid());

drop policy if exists "recipes_select_public" on public.recipes;
create policy "recipes_select_public" on public.recipes for select using (user_id is null);

drop policy if exists "recipes_insert_own" on public.recipes;
create policy "recipes_insert_own" on public.recipes for insert with check (user_id = auth.uid());

drop policy if exists "recipes_update_own" on public.recipes;
create policy "recipes_update_own" on public.recipes for update using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "recipes_delete_own" on public.recipes;
create policy "recipes_delete_own" on public.recipes for delete using (user_id = auth.uid());

-- Documented live gap: authenticated only ever had SELECT, no
-- INSERT/UPDATE/DELETE grant, making the owner-write policies above
-- unreachable via the Data API today. Reproduced faithfully (SELECT only)
-- -- this is the known, still-open bug CLAUDE.md roadmap item 22 depends on
-- fixing, not something to silently correct here.
grant select on public.recipes to authenticated, anon;

-- =====================================================================
-- ingredients
-- =====================================================================
create table if not exists public.ingredients (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  category text,
  badge text,
  prep_tip text,
  pinch_tip text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.ingredients enable row level security;

-- Documented as "3 redundant SELECT policies" live -- reproducing the
-- functional access (public read) with one clean policy rather than
-- guessing at 3 distinct historical definitions.
drop policy if exists "ingredients_select_public" on public.ingredients;
create policy "ingredients_select_public" on public.ingredients for select using (true);

-- Fixed live 2026-08-15: SELECT retained, INSERT/UPDATE/DELETE revoked.
grant select on public.ingredients to anon, authenticated;
revoke insert, update, delete on public.ingredients from anon, authenticated;

-- =====================================================================
-- ai_precision_cache
-- =====================================================================
create table if not exists public.ai_precision_cache (
  id uuid primary key default gen_random_uuid(),
  cache_key text not null unique,
  heat_spec jsonb,
  salt_timing jsonb,
  knife_cut_spec jsonb,
  swiss_substitutes jsonb,
  base_ratios jsonb,
  acid_balance_note jsonb,
  hit_count int not null default 0,
  last_used_at timestamptz,
  created_at timestamptz not null default now()
);

alter table public.ai_precision_cache enable row level security;

-- Documented as "0 policies (correct default-deny)" -- deliberately no
-- policies created. Only service_role (which bypasses RLS) touches this
-- table, matching api_call_cost_log's pattern.
-- Fixed live 2026-08-15: no grants to anon/authenticated at all.
grant select, insert, update, delete on public.ai_precision_cache to service_role;
revoke select, insert, update, delete on public.ai_precision_cache from anon, authenticated;
