-- Cleanup of database objects orphaned by features that were cut from the
-- app. All three items below were verified against the live dev project
-- (ref suuafglvrxrllnhipkiv) before this migration was written, not assumed
-- from documentation:
--
--   supabase inspect db table-stats --linked
--     -> public.shopping_list_items exists, 0 rows
--     -> public.fridge_items        exists, 0 rows
--
-- and by grepping lib/ + test/ for live references:
--     -> "shopping_list_items": zero references anywhere outside
--        supabase/migrations
--     -> "fridge_items": one prose mention in a code comment
--        (one_pan_cooking_roadmap_screen.dart), no query, no model, no service
--
-- NOTE: safe to re-run (IF EXISTS guards throughout).

-- =====================================================================
-- 1. shopping_list_items
-- =====================================================================
-- The Weekly Planner shopping list was cut on 2026-08-17 and removed from
-- the UI the same day. The table, its RLS policies and its migration were
-- kept in place at the time in case the feature came back. It has not, and
-- nothing in the app reads or writes it. Dropping the table drops its RLS
-- policies, its unique constraint, its indexes and its updated_at trigger
-- with it; public.set_updated_at() is shared with other tables and is
-- deliberately NOT dropped.
drop table if exists public.shopping_list_items;

-- =====================================================================
-- 2. fridge_items
-- =====================================================================
-- Backed Fridge Countdown, the decaying-freshness Home chip. That feature
-- was replaced by the two-case fridge nudge notification and its last code
-- (FridgeCountdownSheet, then FridgeCountdownService, then the
-- CookModeSurface/ChefRecipeSurface.fridgeCountdown enum members) was
-- deleted across 2026-08-17/18. Database objects were deliberately left
-- alone then -- "database changes are a separate, later decision". This is
-- that decision.
drop table if exists public.fridge_items;

-- =====================================================================
-- 3. The orphaned 'fridge_countdown' value in waste_ledger_events' CHECK
-- =====================================================================
-- Added by 20260816130000 so Fridge Countdown cooks could be logged
-- distinguishably. Nothing can produce that value any more: the enum member
-- that generated it is gone, and as of the recipe-provenance change the only
-- source value the app ever writes is 'fridge_clearer'.
--
-- waste_ledger_events itself survives, so the constraint is redefined rather
-- than dropped outright. 'cook_mode' and 'custom_ai_recipe' are deliberately
-- retained even though the app no longer writes them either: historical rows
-- on production use 'cook_mode', and narrowing the constraint further would
-- make this migration unsafe there. Only the genuinely orphaned value is
-- removed.
--
-- Guarded: on a database that still holds fridge_countdown rows this would
-- fail the constraint validation, so those rows are reported rather than
-- silently rewritten. Dev has 0 rows in this table (verified above).
do $$
declare
  orphaned_rows bigint;
begin
  select count(*) into orphaned_rows
  from public.waste_ledger_events
  where source = 'fridge_countdown';

  if orphaned_rows > 0 then
    raise exception
      'waste_ledger_events still has % row(s) with source=''fridge_countdown''; '
      'decide how to migrate them before narrowing the CHECK constraint.',
      orphaned_rows;
  end if;
end $$;

alter table public.waste_ledger_events
  drop constraint if exists waste_ledger_events_source_check;

alter table public.waste_ledger_events
  add constraint waste_ledger_events_source_check
  check (source = any (array['fridge_clearer', 'cook_mode', 'custom_ai_recipe']));
