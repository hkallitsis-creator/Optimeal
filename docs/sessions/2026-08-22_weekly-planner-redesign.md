# Session — Weekly Planner screen redesign (2026-08-22)

## Prompt (verbatim)

```
AUTONOMY: Full file/test/git permission. No confirmation questions.
STOP CONDITIONS: Prod Supabase = stop-and-report always. Dev Supabase
(suuafglvrxrllnhipkiv, --linked) READ-ONLY plus app-level test writes
through existing services — no migrations, no schema changes, no
function deploys. Spec ambiguity = note and continue, never guess.

BUILD — WEEKLY PLANNER SCREEN REDESIGN
Spec: design_spec_weekly_planner_2026-08-21.md in project docs. The
spec is WHAT and WHERE; you own HOW. Read it in full before touching
code. The three-source add sheet is signed AND already built — the
screen around it changes, the sheet does not.

Grep by class name before touching any file (filenames are not ground
truth): WeeklyPlannerScreen, WeeklyPlannerIntentService,
WeekdayPickerSheet.

Core structure per spec:
- All 7 days as one vertical list; day-chip strip, per-day detail
  screens for viewing, and Slot 1/Slot 2 cards all die.
- Day states: Empty (dashed sage, quiet line, terracotta-text plus) /
  Planned (cream row, weekday, meal name, provenance leaf, chevron) /
  Today (champagne tint, terracotta weekday text, the screen's ONLY
  terracotta button "Cook") / Cooked-counted (faded cream, gold check
  #C77E1F) / Cooked-didn't-count (faded cream, gray check).
- Week toggle: This week ↔ Next week only. No past navigation. Next
  week renders only Empty/Planned — no Cook buttons, no checks.
- 0–2 meals per day as rows in one day card, divider between; second
  meal added from the day's detail, no visible second + on filled rows.
- Empty day tap → existing three-source sheet, unchanged.
- All colors from app_design_tokens.dart — no hex literals in widgets.

COOKED-STATE DERIVATION (ruling, supersedes current mechanism):
Day cooked/counted states derive from ledger + cook-log DATA, not
from navigation return values. Delete the _openPlannedMeal
await-push<bool> mechanism entirely — it is the defect reported
adjacent in 03397f9 (go('/') completes it with null). Subscribe the
planner to AppDataChanges.ledger and AppDataChanges.cookLog via
DataChangeSignal, same pattern Home now uses. Matching a completed
cook to a specific planner slot: use the mapping the data model
supports today; if the current schema cannot attribute a cook to a
day slot unambiguously, STOP on that sub-feature, report exactly
what's missing, and ship the rest — do not invent a matching
heuristic or add columns.

PROVENANCE: "Cook" launches Cook Mode carrying the planned meal's
RecipeOrigin unchanged — a Fridge Clearer-origin meal cooked from the
planner counts as a rescue. This is signed behavior; verify it
survives the rebuild with a test, don't re-implement it.

SIGNED-CONTENT PLACEHOLDERS (Harris authors later — mark with
// PLACEHOLDER comment): empty-day line, "Cook" label, screen title,
week toggle labels.

TESTS: keep all 198 green. Add: day-state rendering per state incl.
next-week suppression; cook completion → planner day flips state via
signal without remount; placement race regression stays covered under
the new screen; provenance-through-planner-cook test.

VERIFICATION:
- flutter test all passing, report exact count; flutter analyze ≤50,
  report exact count
- git status clean, committed and pushed

DOC STEP (permanent rule): commit this prompt verbatim + full report
to docs/sessions/2026-08-22_weekly-planner-redesign.md. Update
docs/CHANGELOG.md. Also correct any remaining stale claim that
anonymous sign-ins are disabled on dev — they were enabled and
device-verified 2026-08-21.

Report verbatim: structural decisions taken, the cooked-state slot
attribution answer (worked / stopped, and why), files touched,
test/analyze counts, push confirmation, ambiguities.
```

---

## Before anything else: the spec file does not exist

`design_spec_weekly_planner_2026-08-21.md` is not in `docs/`, not anywhere
under the repo, not on the Desktop or in Downloads, and not in git history
(`git log --all --diff-filter=AD -- "*design_spec*"` is empty). `docs/`
contains only `CHANGELOG.md`, `DECISIONS.md`, `decisions_2026-08-17.md` and
`sessions/`, and neither decisions file has a Weekly Planner design record.

I built from the prompt's own "Core structure per spec" section, which is
detailed enough to be the spec for everything it names. Every gap between
that list and a shippable screen is called out under **Ambiguities** below
with the choice I made, rather than being silently decided. If the real
document exists somewhere else, the two worth re-checking against it are the
day-detail sheet and the week-storage encoding.

---

## Structural decisions taken

**The list.** `ListView.separated` of seven `_DayCard`s, one per weekday,
Mon-first. The day-chip strip (`_SevenDayBar`, `_DayPill`), the
`_selectedDayIndex` single-day body it drove, `_SectionHeader` and
`_MealSlotCard` (Slot 1 / Slot 2) are deleted outright, not hidden.

**States live in a pure function, not a widget.** `plannerMealStateFor({cooked,
rescueEligible, isToday, isThisWeek})` returns a `PlannerMealState`
(`planned` / `cookable` / `cookedCounted` / `cookedNotCounted`) and is
top-level, so the whole state table is unit-testable without pumping a
screen. `_MealRowTrailing` is a plain switch over it: chevron, Cook button,
gold check, gray check.

**Counted-ness is derived, not looked up.** Whether a cook counted is a
property of the recipe — `RecipeOrigin.isRescueEligible`, the same rule
`selectLedgerVerdict` applies — so the gold-vs-gray choice needs no join to
the ledger at all. That matters, because there is no join key to use (see
the attribution answer below).

**Terracotta discipline.** The empty day's plus is a `Text`, not a button;
the day-detail's "add another" is text; the week toggle's selected pill is
cream on a deep-forest track. `Cook` is the only `FilledButton` on the
screen, and there is a test asserting `find.byType(FilledButton)` finds
nothing on a week with no cookable day.

**Tokens, no hex in widgets.** Three tokens were added to
`app_design_tokens.dart`: `cookedCountedGold` (`#C77E1F`, from the prompt
verbatim), `cookedNeutralGray` (`#8B918E`, mine — the spec said "gray"), and
`champagneTint` (`#F7E7CE`, canonical champagne; the spec named the hue, not
a value). The old screen's `Color(0xFF3F7D53)` cooked-badge literals went
with the slot cards.

**Week storage — the one structural call I had to make without a spec line.**
`user_meal_plans` has no week column (probed dev: `week_start`, `week`,
`week_offset`, `plan_week` all 400; the table is `id, user_id, day_index,
slot_index, title, source, aisle_items, recipe_payload, is_cooked,
created_at, updated_at`). A toggle that cannot store next week's meals is
decoration, so next week rides the same integer: **0–6 this week, 7–13 next
week** (`kNextWeekOffset`). Verified against live dev with an authenticated
session — `day_index` has no CHECK constraint and accepts 7 and 13 — and it
is forward/backward safe, because any reader still filtering to 0–6 drops
next week's rows rather than mis-reading them. No migration, no schema
change. **The gap this exposes**: nothing anchors either week to a calendar
date, so neither rolls over — next week never becomes this week. That was
already true of the single-week model (day 0 has always meant "Monday,
whichever Monday you are looking at"); the toggle makes it visible. Fixing it
properly needs a `week_start` column.

**The day detail is a sheet, not a screen.** The spec kills "per-day detail
screens for viewing" and simultaneously says the second meal is "added from
the day's detail". Tapping a filled day card opens `_DayDetailSheet`: the
day's meals (tap one → recipe details), a remove control per meal, and "Add
another meal" when there is room. Every action pops the sheet first and then
acts, which is exactly how the signed add sheet's own Fridge Clearer /
Custom Craving options already behave — so sheets still never stack, and the
signed sheet is untouched. This is what keeps a filled row clean: no inline
second `+`, no inline `x`.

**The "from saved" chip moved.** The spec's Planned row is "weekday, meal
name, provenance leaf, chevron" — no chip. `kFromSavedMealSource` is a
routing marker rather than provenance, so it now renders one level in, in the
day detail. The leaf badge stays on the week list, because that IS provenance.

**Dropped with the slot cards**: the ingredient-pill preview and therefore
the whole `_Aisle` / `_AisleItem` / `_inferAisle` machinery and the
`aisle_items` write. The column still exists and existing rows keep their
values (an upsert only sets the columns it sends); nothing has read it since
the shopping list was cut in August.

**Kept deliberately**: the optimistic add/remove with per-slot rollback, the
inline "Couldn't save. Tap to retry." affordance (now one line per day card,
not one per slot — hiding real write failures to satisfy a state list would
be a bad trade), the `_writeEpoch` stale-load guard and its reload-on-settle
from the 2026-08-22 morning session, and the injectable `WeeklyPlanBackend`.

**One extra, and it was load-bearing**: the loader now only paints on the
first read (`_hasLoadedOnce`), so a signal-driven background refresh does not
flash "Loading your saved week…" over a list the user is looking at.

---

## The cooked-state slot attribution answer: **STOPPED**, and why

**Done, and shipping:** the `await context.push<bool>` mechanism is deleted
(`_openPlannedMeal` and `_markMealCooked` are both gone); the planner
subscribes to `AppDataChanges.ledger` and `AppDataChanges.cookLog` and
re-reads the plan on either, coalescing both signals from one cook into a
single read; both cooked states render from `user_meal_plans.is_cooked`; and
counted-vs-not is derived from the meal's own `RecipeOrigin` with no ledger
join. A row that comes back `is_cooked = true` flips the day in place, with
no navigation event and no remount — there is a test for exactly that.

**Stopped:** nothing sets `is_cooked` any more, because a finished cook
cannot be attributed to a specific `(day_index, slot_index)`. Exactly what is
missing:

- **The cook log** (`cook_session_history_v1`) stores
  `{recipe, cookedAt, source}` and **deduplicates by normalized title** —
  `_appendToHistory` removes any entry with the same title before adding. So
  it cannot even tell you a dish was cooked twice, let alone which day's slot
  it belonged to.
- **`waste_ledger_events`** has `recipe_id`, and Cook Mode passes
  `recipeId: null` on every write. The local weekly store keeps only
  `{ts, ingredients}` — no title, no id.
- **`user_meal_plans`** has no reference in the other direction either: no
  `cooked_at`, no session id, nothing a completion could carry back.

The only candidate join is the recipe **title**, and it is ambiguous in
ordinary use: the same dish planned on Tuesday and Friday would flip both
slots, and a dish cooked from Home would flip a planner slot that was never
touched. That is a heuristic, which the ruling explicitly forbids inventing,
so I did not.

**Two candidate fixes, both Harris's call** (recorded as CLAUDE.md roadmap
item 27):

(a) carry the originating `(day_index, slot_index)` through
`CookModeLaunchRequest` → `CookModeRecipePayload`, so the completion knows
which slot it belongs to — no schema change, one new payload field, and it
survives `go('/')` because it travels with the recipe rather than with the
navigation;

(b) give the cook log / `waste_ledger_events` a real recipe key and attribute
on that — more work, and useful beyond the planner.

Consequence to be explicit about: **until one of those lands, the two cooked
states are unreachable in the running app.** They render correctly from
stored data and are covered by tests, but no user action produces them. That
is the ruling's intended trade (delete the broken mechanism, do not replace
it with a guess), not an oversight.

---

## A real bug found and fixed on the way: planner upserts never overwrote

While probing the schema with an authenticated dev session I found that
`user_meal_plans` upserts **fail on any occupied slot**:

```
POST /user_meal_plans  (Prefer: resolution=merge-duplicates)
→ 409  23505  duplicate key value violates unique constraint
              "user_meal_plans_user_id_day_index_slot_index_key"

POST /user_meal_plans?on_conflict=user_id,day_index,slot_index
→ 200, row updated in place
```

PostgREST resolves `merge-duplicates` against the **primary key** unless
given a conflict target, and the app never sends an `id` (it defaults to a
fresh uuid), so there was never a PK conflict to merge on and the write fell
through to the unique constraint. Every overwrite — marking a slot cooked,
replacing a day's meal — failed silently into "Couldn't save. Tap to retry."
Fixed by passing `onConflict: 'user_id,day_index,slot_index'`
(`SupabaseWeeklyPlanBackend.slotConflictTarget`), with the evidence in the
doc comment. Same shape as this project's standing RLS-vs-grants lesson: the
constraint existing is not the same as PostgREST using it.

---

## Files touched

Changed:
- `lib/screens/weekly_planner_screen.dart` — the redesign. The signed
  `_AddMealSheet` / `_AddMealSourcesPane` / `_SavedRecipesPickerPane` /
  `_SheetOptionTile` block was carried across byte-for-byte.
- `lib/services/weekly_plan_service.dart` — `onConflict` fix + doc.
- `lib/theme/app_design_tokens.dart` — `champagneTint`,
  `cookedCountedGold`, `cookedNeutralGray`.
- `test/screens/weekly_planner_add_sheet_test.dart` — new entry point
  (`Nothing planned` instead of `+ Add Meal`), chip assertions follow the
  chip into the day detail.
- `test/integration/saved_recipes_flow_test.dart` — same two adjustments.
- `CLAUDE.md` — planner architecture entry, upsert-conflict-target entry,
  the "from saved" chip correction, roadmap item 27, and the anonymous
  sign-in corrections.
- `docs/CHANGELOG.md` — this session, plus two stale anonymous sign-in notes.

New:
- `test/screens/weekly_planner_redesign_test.dart` — 23 tests.
- `docs/sessions/2026-08-22_weekly-planner-redesign.md` — this file.

Untouched on purpose: `WeeklyPlannerIntentService` (its contract still holds
— an intent's `dayIndex` is 0–6 and always means this week, so the screen
snaps the toggle back to this week when one arrives) and `WeekdayPickerSheet`.

---

## Tests and analyze

`flutter test`: **221 passing** (198 baseline + 23 new), 0 failing.
`flutter analyze`: **46 issues** (was 46 at the start of this session, 54 two
sessions ago), **0 errors, 0 warnings** — all 46 are info-level, and none of
them are in any file this session touched.

New coverage: the four state-table rules as pure unit tests; seven days
listed with no chips and no slot cards; the empty day's line, terracotta-text
plus and absence of any button; empty day → the unchanged three-source sheet;
planned day shows leaf + chevron and no Cook; today is champagne with the
only Cook button and terracotta weekday; gold vs gray checks; two meals as
two rows with one divider and one weekday label; next week is a separate plan;
next week suppresses Cook buttons, checks and the tint even when every flag
is set; no past-week affordance; an intent snaps back to this week and
persists at the right index; **Cook carries `RecipeOrigin.fridgeClearer`,
`isRescueEligible`, the entered ingredients and `CookModeSurface.weeklyPlanner`
unchanged**; a payload-less meal says so instead of launching; a `cookLog`
signal re-reads and flips the day **in place** (same `State` instance
asserted); a `ledger` signal does the same; both signals for one cook coalesce
into one read; the day detail's add/remove behaviour and its no-stacking
swap into the signed sheet.

The placement-race regression from this morning
(`weekly_planner_stale_load_test.dart`) **passes unmodified against the new
screen** — it was not adjusted to fit.

## Dev verification (authenticated, cleaned up after)

Anonymous sign-in is enabled on dev, confirmed here rather than assumed:
`POST /auth/v1/signup` returned `200` with a real **3-part** JWT,
`is_anonymous: true`, `role: authenticated`. With that session:

- `day_index` 0, 7 and 13 all inserted `201` — no CHECK constraint, so the
  week-offset encoding is storable as-is;
- the slot identity is `UNIQUE (user_id, day_index, slot_index)`, separate
  from the `id` primary key — proved by the `23505` above;
- `merge-duplicates` **without** a conflict target fails, **with**
  `on_conflict=user_id,day_index,slot_index` succeeds and updates in place;
- all four probe rows were deleted afterwards (`204`), and both the
  authenticated and anon views of `user_meal_plans` read back `[]`.

No migrations, no schema changes, no function deploys, nothing touched on
prod.

---

## Ambiguities (noted, not guessed)

1. **The spec file is missing** — see the top of this report. Everything
   below is a gap between the prompt's spec section and a working screen.
2. **Week storage** had no signed representation; `day_index + 7` is my call,
   with dev evidence. The un-anchored-week consequence is real and needs a
   `week_start` column to fix.
3. **"The day's detail"** is referenced by the spec but never defined, and
   the same line kills per-day detail *screens*. I built it as a sheet. If it
   was meant to be something else, it is one self-contained widget
   (`_DayDetailSheet`) plus one call site.
4. **"The screen's ONLY terracotta button"** — read as "no other terracotta
   button exists on this screen", so a day with two uncooked meals on today
   would show a Cook button per row. The alternative reading (exactly one
   button per screen, acting on the first uncooked meal) would leave the
   second meal uncookable from the planner.
5. **Today with nothing planned** renders as Empty, not as a Today card: the
   Today state's whole content is a Cook button, and there is nothing to
   cook. Today's weekday label still goes terracotta.
6. **Today with everything cooked** drops the champagne tint back to cream —
   nothing is left to do in that day.
7. **`champagneTint` and `cookedNeutralGray` values** are mine; only the gold
   was specified. Both are single-token changes.
8. **The inline write-error affordance** is not in the spec's state list. I
   kept it (one line per day card) rather than let a failed save disappear.
9. **`is_cooked` has no writer** — the headline stop, above.
