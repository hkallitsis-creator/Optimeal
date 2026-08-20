-- saved_recipes: the data layer behind "My recipes". UI ships in a later
-- build; this is the table + RLS only.
--
-- Follows the user_meal_plans pattern, NOT the recipes pattern. That choice
-- was made against the live dev schema, not from documentation:
--
--   GET /rest/v1/recipes?select=<col>  ->  id, user_id, created_at exist;
--                                          title/ingredients/steps/description
--                                          all 400 (no such column)
--   GET /rest/v1/user_meal_plans?...   ->  recipe_payload (jsonb) exists and
--                                          carries the whole recipe
--
-- public.recipes is a content-less placeholder that nothing in the app has
-- ever written to. Generated recipes have no server-side row and no server
-- id at all -- they exist only as a CookModeRecipePayload. So a saved recipe
-- stores the full payload inline as jsonb (identical shape to
-- user_meal_plans.recipe_payload: lib/models/cook_mode_recipe_codec.dart),
-- which is what lets a recipe be saved even though it was never a
-- recipes-table row, and lets it be reopened or scheduled into the planner
-- later with no regeneration.
--
-- NOTE: safe to re-run (IF NOT EXISTS / DROP ... IF EXISTS guards).

create table if not exists public.saved_recipes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,

  -- Recipe identity. Generated recipes have no server id, so identity is a
  -- normalized form of the title (trimmed, lowercased, whitespace collapsed)
  -- computed client-side by SavedRecipesService.recipeKeyFor -- the same
  -- notion of "the same recipe" the local Recently Cooked / cook history
  -- stores have always deduplicated on. Kept as its own column rather than
  -- read out of the payload so the uniqueness constraint below can use it.
  recipe_key text not null,

  -- Display title as saved, for listing without parsing the payload.
  title text not null,

  -- The full CookModeRecipePayload, cookModeRecipeToJson shape. Everything
  -- needed to reopen recipe details and to schedule into user_meal_plans
  -- without regenerating: ingredients, structured_ingredients, steps,
  -- kitchen_gear, base_portions, curriculum_lesson_ids, and the provenance
  -- fields.
  recipe_payload jsonb not null,

  -- Provenance, and the source of truth for the leaf badge on a saved
  -- recipe. RecipeOrigin.name, or null when the recipe predates provenance
  -- (which must read as "not a rescue", never as a guess). This duplicates
  -- recipe_payload->>'origin' on purpose: the badge and any future
  -- "show me my fridge rescues" filter should be a plain indexed column
  -- read, not a jsonb traversal. SavedRecipesService always writes the two
  -- from the same payload so they cannot drift.
  origin text,

  saved_at timestamptz not null default now(),

  -- Drives the recency sort on My recipes (most recent save/cook activity
  -- first). Bumped on re-save and on cooking the recipe -- see
  -- SavedRecipesService.touch.
  last_touched_at timestamptz not null default now(),

  -- One saved row per recipe per user. Re-saving updates in place (upsert on
  -- this constraint) rather than creating a duplicate.
  constraint saved_recipes_user_id_recipe_key_key unique (user_id, recipe_key),

  -- Mirrors the closed vocabulary of the Dart RecipeOrigin enum. Null is
  -- allowed and means "origin unknown".
  constraint saved_recipes_origin_check
    check (origin is null or origin = any (array['fridgeClearer', 'customAiRecipeCreator']))
);

-- The list query is always "this user's saved recipes, newest activity
-- first", so index exactly that.
create index if not exists idx_saved_recipes_user_last_touched
  on public.saved_recipes (user_id, last_touched_at desc);

-- Deliberately NOT stored here: any times-cooked or has-been-cooked counter.
-- That is ledger/cook-session data (waste_ledger_events, and the local cook
-- history in CookSessionStorageService) and is derived at read time by
-- SavedRecipesService. Duplicating it into this table would create a second,
-- silently-drifting source of truth for how often something was cooked.
--
-- Also deliberately absent: any row limit, and any pricing/tier column.
-- Pricing is an explicitly deferred decision (docs/DECISIONS.md).

alter table public.saved_recipes enable row level security;

-- No set_updated_at() trigger here, unlike the other owner-owned tables.
-- last_touched_at is not "when the row last changed" -- it is "when the user
-- last did something with this recipe", which only the client knows. A
-- trigger would bump it on any write at all, including a future backfill,
-- and quietly scramble the recency sort.

-- Owner-only, single ALL policy.
drop policy if exists "Users manage their own saved recipes" on public.saved_recipes;
create policy "Users manage their own saved recipes"
on public.saved_recipes
for all
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

-- Table-level grants. RLS policies and grants are two independent Postgres
-- mechanisms -- a table with a perfect policy and no GRANT still 403s on
-- every request. This project has hit that four separate times; see
-- CLAUDE.md's standing lesson. `authenticated` only, no `anon`.
grant select, insert, update, delete on public.saved_recipes to authenticated;
