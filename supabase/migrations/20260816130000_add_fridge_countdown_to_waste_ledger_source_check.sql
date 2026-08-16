-- Adds 'fridge_countdown' as a valid waste_ledger_events.source value.
--
-- Fridge Countdown's "Use Tonight" cooks are rescue-eligible (same as
-- Fridge Clearer — both generate a recipe directly from what's actually in
-- the user's fridge) but were previously logged under the generic 'cook_mode'
-- literal along with every other Cook Mode entry path, indistinguishable
-- from non-rescue-eligible surfaces (Weekly Planner, Custom AI Recipe
-- Creator). See CLAUDE.md Roadmap item 28 for the full source-accuracy fix
-- this is part of. 'cook_mode' is left in the constraint (not removed) —
-- historical rows already use it, and removing it isn't part of this fix.

alter table public.waste_ledger_events
  drop constraint waste_ledger_events_source_check;

alter table public.waste_ledger_events
  add constraint waste_ledger_events_source_check
  check (source = any (array['fridge_clearer', 'cook_mode', 'custom_ai_recipe', 'fridge_countdown']));
