-- Anchors every Weekly Planner week to a real calendar date — planner
-- corrections build, 2026-08-22. DEV ONLY (not pushed to prod, same as
-- 20260818120000, 20260820120000, 20260820130000, 20260821120000).
--
-- Why: `user_meal_plans` has only `day_index`, and day 0 has always meant
-- "Monday, whichever Monday you happen to be looking at". Nothing anchored a
-- plan to a date, so nothing ever rolled over. The 2026-08-22 redesign made
-- that visible rather than causing it: with a this-week/next-week toggle and
-- no week column, next week had to ride the same integer (0–6 this week, 7–13
-- next, `kNextWeekOffset`), and "next week" never became "this week" — last
-- week's meals simply sat there labelled as this week's.
--
-- The fix is a stored week anchor plus a read-time computation, not stored
-- state that has to be advanced: `week_start` is the MONDAY of the plan's
-- week, and the app asks for "the Monday of today" and "that Monday + 7" every
-- time it reads. Rollover then happens by itself, at midnight on Sunday, with
-- nothing to migrate weekly and no background job. Past weeks stop being
-- selected rather than being deleted — there is deliberately no past
-- navigation (history lives in My recipes and the Waste Ledger), but the rows
-- stay, which keeps this migration non-destructive and leaves a past-weeks
-- feature possible later.
--
-- Week boundary: **Monday, Europe/Zurich** (Swiss-first launch). The backfill
-- below computes "this week's Monday" in that zone explicitly rather than in
-- the database's UTC, so a migration run late on a Sunday evening Zurich time
-- does not roll the whole plan forward a week. `date_trunc('week', ...)`
-- returns Monday in Postgres.
--
-- Backfill: day_index 0–6 -> this week's Monday; day_index 7–13 -> next week's
-- Monday, with day_index normalized back down to 0–6. After this, day_index
-- means the same thing on every row again, and the offset encoding is gone.
--
-- Slot identity becomes (user_id, week_start, day_index, slot_index). The old
-- unique constraint has to be DROPPED BEFORE the backfill: normalizing
-- day_index 7 down to 0 collides with this week's day 0 under the old
-- three-column constraint, and only stops colliding once week_start is part of
-- the key. `SupabaseWeeklyPlanBackend.slotConflictTarget` must be updated to
-- match, or every overwrite of an occupied slot fails 23505 again — see the
-- 2026-08-22 conflict-target fix for why PostgREST needs to be told.
--
-- Deliberately NOT added here: a CHECK (day_index between 0 and 6). It is the
-- right invariant now, but adding it in the same step would break any client
-- still running the pre-migration build the moment it wrote next week at
-- day_index 7. Worth adding once the app change has shipped and settled.
--
-- Re-runnable: IF NOT EXISTS / IF EXISTS guards throughout, and the backfill
-- only touches rows whose week_start is still null.

alter table public.user_meal_plans
  add column if not exists week_start date;

-- Must come before the backfill — see the note above. Both forms are handled:
-- the 23505 that exposed this constraint on 2026-08-22 names an INDEX, and a
-- unique index created directly (rather than via a table constraint) would not
-- be dropped by the first statement. Dropping a constraint already drops its
-- index, so the second statement is a no-op in the normal case.
alter table public.user_meal_plans
  drop constraint if exists user_meal_plans_user_id_day_index_slot_index_key;

drop index if exists public.user_meal_plans_user_id_day_index_slot_index_key;

-- Next week's rows first, so the day_index normalization cannot be re-applied
-- to rows this statement just moved into 0–6.
update public.user_meal_plans
set week_start =
      (date_trunc('week', (now() at time zone 'Europe/Zurich'))::date + 7),
    day_index = day_index - 7
where week_start is null
  and day_index between 7 and 13;

update public.user_meal_plans
set week_start = date_trunc('week', (now() at time zone 'Europe/Zurich'))::date
where week_start is null;

alter table public.user_meal_plans
  alter column week_start set not null;

create unique index if not exists user_meal_plans_slot_identity_key
  on public.user_meal_plans (user_id, week_start, day_index, slot_index);
