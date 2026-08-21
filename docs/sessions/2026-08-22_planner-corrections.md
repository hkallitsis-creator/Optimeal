# Session — Weekly Planner corrections (2026-08-22)

## Prompt (verbatim)

```
AUTONOMY: Full file/test/git permission. No confirmation questions.
STOP CONDITIONS: Prod Supabase = stop-and-report always. Dev Supabase
(suuafglvrxrllnhipkiv, --linked) READ-ONLY plus app-level test writes
through existing services. ONE exception this session: a single dev
migration is APPROVED by Harris (details in Part 3) — but the repo's
permission deny rules block supabase migration commands, so you WRITE
the migration file, then STOP and give Harris the exact command to
run himself; continue after he confirms. No other schema changes, no
function deploys. Spec ambiguity = note and continue, never guess.

WEEKLY PLANNER CORRECTIONS BUILD — closes the three open items from
fb177c3. Read docs/sessions/2026-08-22_weekly-planner-redesign.md
first for context.

PART 1 — PALETTE CORRECTION
champagneTint in app_design_tokens.dart is #F7E7CE (invented in
fb177c3). The signed palette v1.2 value is #F7DBCB. Correct it; the
today-row tint and any other champagne consumer picks it up via the
token. cookedNeutralGray #8B918E stands as-is (provisionally signed,
pending device pass).

PART 2 — COOKED-STATE SLOT ATTRIBUTION (roadmap item 27, ruling:
option A)
Carry the planner slot identity WITH the cook, same architectural
move as RecipeOrigin — launch context stamped once at launch:
- When Cook launches from a planner row, stamp (day_index, slot_index)
  into the Cook Mode launch request and ride it through the cook
  payload end to end. Cooks launched from anywhere else carry null —
  never inferred, never matched by title.
- On cook completion, when slot identity is present, set is_cooked on
  exactly that user_meal_plans row through the existing
  WeeklyPlanBackend (app-level write, in scope).
- The planner's existing AppDataChanges subscription then flips the
  day state in place — that path is already built and tested; do not
  duplicate it.
- Counted vs didn't-count stays derived from RecipeOrigin
  .isRescueEligible exactly as fb177c3 built it.
- This makes both cooked states reachable in the running app. Same
  dish planned on two days: only the launched slot flips — add a test
  proving it.

PART 3 — WEEK ANCHORING (dev migration APPROVED — follow the
stop-and-hand-over procedure from the stop conditions)
Problem (from fb177c3): next week is day_index 7–13 with no date
anchor; nothing ever rolls over.
- Write a migration adding week_start (date, not null) to
  user_meal_plans, week_start = the Monday of the plan's week.
  Include a backfill for existing dev rows: day_index 0–6 → current
  week's Monday, 7–13 → next week's Monday, and normalize day_index
  back to 0–6 across both weeks. Extend the unique constraint to
  (user_id, week_start, day_index, slot_index) and update the
  onConflict target from the fb177c3 upsert fix to match.
- STOP: show Harris the migration file and the exact command. Wait
  for his "done" confirmation, then verify the schema over PostgREST
  before touching app code.
- App side: WeeklyPlanBackend reads/writes scoped by week_start;
  "This week" = Monday of today, "Next week" = Monday+7, computed at
  read time — rollover becomes automatic, no stored state, nothing
  to migrate weekly. Past weeks simply stop being selected (spec:
  no past navigation; history lives in My recipes + ledger).
- Week boundary: Monday, Europe/Zurich local time. Add a test pinning
  the Sunday→Monday boundary behavior.

TESTS: keep all 221 green, plus: slot-attribution end-to-end (planner
launch → completion → exactly that row cooked, gold vs gray both),
same-dish-two-days isolation, non-planner cook touches no plan row,
week_start scoping (this/next week reads disjoint), rollover
(simulated date advance moves next→this), boundary test.

VERIFICATION:
- flutter test all passing, exact count; flutter analyze ≤46, exact
  count
- Dev, authenticated anon session: probe writes proving the new
  constraint and week-scoped reads both ways; delete all probe rows
  after; table reads back clean
- git status clean, committed and pushed

DOC STEP (permanent rule): commit this prompt verbatim + full report
to docs/sessions/2026-08-22_planner-corrections.md. Update
docs/CHANGELOG.md. Record the week-anchoring decision in
docs/DECISIONS.md (Monday anchor, Europe/Zurich, no past weeks).

Report verbatim: migration file content + confirmation it was applied
by Harris, slot-attribution implementation notes, files touched,
test/analyze counts, push confirmation, ambiguities.
```

### Mid-session procedure change (verbatim)

```
Change of procedure before Part 3 continues — update the permission
rules so dev migrations run without Harris:

1. Edit .claude/settings.json:
   - REMOVE from deny: "Bash(supabase db push:*)" and
     "Bash(supabase migration:*)"
   - ADD to deny: "Bash(supabase link:*)", "Bash(supabase unlink:*)",
     "Bash(supabase projects:*)"
   - ADD to allow: "Bash(supabase db push --linked:*)",
     "Bash(supabase migration:*)", "Bash(supabase db diff:*)"
   Rationale for the record: prod is only reachable by changing the
   linked project; with link/unlink denied, --linked is mechanically
   pinned to dev. Commit with message "Permissions: allow dev
   migrations, deny relinking".

2. Re-verify the link target is dev (suuafglvrxrllnhipkiv) and that
   prod shows linked: false. If that is not the case, STOP.

3. Run: supabase db push --linked
   If the permission system still blocks it because rules are cached
   from session start, STOP and say so — Harris will restart you and
   you resume from the session record.

4. Ruling on your ambiguity: device-local time for the week boundary
   is correct, do NOT pin Europe/Zurich — a travelling user's "this
   week" follows their phone. Record in DECISIONS.md.

5. Verify week_start over PostgREST, then continue with the full app
   side as planned: week-scoped reads/writes, updated onConflict
   target, rollover + Sunday→Monday boundary tests, verification,
   docs, report.
```

---

## Part 1 — palette

`AppDesignTokens.champagneTint` `0xFFF7E7CE` → **`0xFFF7DBCB`**. One token; the
today-row tint and every other champagne consumer picks it up with no widget
change. The redesign had invented the canonical-champagne value because the
spec named the hue and not the hex — the token doc now records that, so the
next reader does not "correct" it back.

`cookedNeutralGray` `#8B918E` reviewed and left alone; its doc comment now says
it is provisionally signed pending a device pass, which is the fact that was
missing rather than a value that was wrong.

---

## Part 2 — cooked-state slot attribution (roadmap item 27, option A)

### The shape

`PlannerSlotRef` (`lib/models/planner_slot_ref.dart`) carries `week_start`,
`day_index`, `slot_index`. It is stamped **once, at launch**, by
`_cookPlannedMeal` on the row whose Cook button was pressed, and rides on
`CookModeLaunchRequest` → `OnePanCookingRoadmapScreen.plannerSlot` →
`_plannerSlot` → the saved `ActiveCookSession`. On completion,
`PlannerCookAttributionService.markCookedFromCompletion` marks exactly that row
and raises `AppDataChanges.mealPlan`.

### The one place I deviated from the prompt's wording, deliberately

The prompt said "ride it through the cook payload end to end". I did **not**
put it on `CookModeRecipePayload`, and this is the decision worth flagging:
that payload is persisted verbatim into `saved_recipes.recipe_payload` and
`user_meal_plans.recipe_payload`. A saved recipe carrying a slot reference
would permanently remember "Tuesday, slot 1" and mark the wrong row the next
time it was cooked from Home — a silent, delayed data bug.

The correct home is beside `CookModeSurface`: slot identity is **launch
context**, provenance is **recipe data**. That is the same line `RecipeOrigin`
already draws from the other side, and the prompt's own framing ("same
architectural move as RecipeOrigin — launch context stamped once at launch")
is what it follows. The persistence hop that actually mattered — surviving an
interrupted cook — is `ActiveCookSession`, which it does travel through, with
a round-trip test both ways. Documented at both ends so it does not get
"fixed" later.

### Why the write is an UPDATE, not an upsert

The completion knows a `(week, day, slot)` and none of the row's other
columns. An upsert would have to invent a `title` for its insert branch, and
its insert branch could create a planner row for a day the user never planned
— or resurrect a meal they deleted while it was cooking. `markSlotCooked` is a
targeted UPDATE; matching zero rows is a legitimate outcome, not an error, and
there is a test for exactly that case.

### Why `mealPlan` is a new signal rather than reusing `cookLog`

The prompt said the planner's existing subscription should do the flipping and
not to duplicate that path — which is what happens: `mealPlan` lands in the
same `_onExternalDataChanged` handler, one extra `listen` line, no second
mechanism.

It could not ride on `cookLog`, though. `cookLog` is raised by
`clearActiveSession()`, which is the **first** thing
`_logCookSessionCompletion` does — long before the plan row is written. A
planner re-read driven by that signal alone reads the row back uncooked and
the day never flips. `mealPlan` fires only after the write lands. This is
recorded in both signals' doc comments because it is the kind of thing that
looks like redundancy to a future reader.

### Counted-ness

Unchanged, and deliberately so: gold vs neutral is still
`RecipeOrigin.isRescueEligible`, derived at read time. Nothing about
counted-ness is stored, no ledger join was added, `waste_ledger_events` still
carries no recipe reference. The attribution write moves exactly one boolean.

---

## Part 3 — week anchoring

### The migration, as applied

`supabase/migrations/20260822120000_add_week_start_to_user_meal_plans.sql`
(header comments trimmed here; the file carries the full reasoning):

```sql
alter table public.user_meal_plans
  add column if not exists week_start date;

-- Must come before the backfill. Both forms handled: the 23505 that exposed
-- this constraint names an INDEX, and a unique index created directly would
-- not be dropped by the first statement.
alter table public.user_meal_plans
  drop constraint if exists user_meal_plans_user_id_day_index_slot_index_key;

drop index if exists public.user_meal_plans_user_id_day_index_slot_index_key;

-- Next week's rows first, so the normalization cannot be re-applied to rows
-- this statement just moved into 0–6.
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
```

Two ordering constraints in there are load-bearing. The old unique **must** be
dropped before the backfill, because normalizing `day_index` 7 down to 0
collides with this week's day 0 until `week_start` is part of the key. And
next week's rows **must** be updated before the catch-all, or the catch-all
would sweep them into this week first.

Deliberately omitted: `CHECK (day_index between 0 and 6)`. It is the right
invariant now, but adding it in the same step would have broken any client
still running the pre-migration build the moment it wrote next week at
`day_index` 7. Recorded as the open remainder of roadmap item 27.

### Application — and the correction to the prompt's expectation

The prompt expected a stop-and-hand-over here; the procedure change instead
had me update `.claude/settings.json` and run it myself. **The permission
rules were not cached from session start** — `supabase db push --linked` ran
immediately after the settings commit, so no restart was needed.

Sequencing note: I verified the link target **before** editing settings, since
step 1 denies `Bash(supabase projects:*)` and would have blocked step 2's own
check afterwards. Result: `suuafglvrxrllnhipkiv` (optimeal-dev)
`"linked": true`, `xwugnhzlnfgmczkbbcbh` (prod) `"linked": false`.

```
Applying migration 20260822120000_add_week_start_to_user_meal_plans.sql...
{"upToDate":false,"dryRun":false,
 "migrations":["20260822120000_add_week_start_to_user_meal_plans.sql"],
 "seeds":[],"roles":[],"message":"Finished supabase db push."}
```

Only that one migration was pending, confirming the other four dev-only
migrations were already applied. `supabase migration list --linked` now shows
all 14 local migrations with matching remote entries.

### The app side

- `lib/models/planner_week.dart` — `plannerWeekStartFor` / `plannerWeekAfter` /
  `plannerWeekValue` / `plannerWeekValueFor`. All built through the `DateTime`
  constructor rather than `subtract(Duration(days: n))`: `Duration` is
  absolute-time arithmetic, so crossing a DST change can land on 23:00 of the
  previous day and move the whole week. The constructor normalizes
  out-of-range day values and stays on calendar days.
- `WeeklyPlanBackend.listForUser` → **`listForWeeks(userId, weekStarts:)`**,
  renamed rather than overloaded so every caller had to be looked at.
  `deleteSlot` and `markSlotCooked` take the week too.
- `slotConflictTarget` → `'user_id,week_start,day_index,slot_index'`.
- The screen keeps its 0–13 absolute index internally (day cards, inline-error
  keys, the in-flight write set, the `_writeEpoch` guard) and maps to/from the
  stored `(week_start, day_index 0–6)` pair at the boundary, in three small
  helpers. That kept the redesign's whole rendering and optimistic-write layer
  untouched — the diff is a boundary translation, not a rewrite.
- The read asks for both weeks in one query (`week_start IN (this, next)`), so
  the toggle stays instant. Rows from any other week are dropped by
  `_absoluteIndexFor` returning null, though the query already excludes them.

**Rollover is a property of asking, not of stored data.** `_thisWeekStart` is
a getter over `_now`. At midnight on Sunday it starts returning a different
Monday, last week's rows stop being fetched, and what was "next week" is now
"this week" — no job, no launch-time check, no weekly migration, and no
wrong-answer state for an app left open across the boundary.

### Boundary ruling

Device-local, per Harris: a travelling user's "this week" follows the phone,
and a fixed zone would disagree with the date the phone itself is showing.
Recorded in `docs/DECISIONS.md`. The one place Zurich *is* named is the
migration backfill, which has no device to ask and would have rolled a plan
forward a week had it run on a Sunday evening in UTC.

---

## Dev verification (authenticated anonymous session, cleaned up after)

`POST /auth/v1/signup` returned a real 3-part JWT, `role: authenticated`,
`is_anonymous: true`. With that session against `user_meal_plans`:

| probe | result |
|---|---|
| insert `(2026-08-24, day 0, slot 0)` | `201` |
| insert **same day/slot**, week `2026-08-31` | `201` — week is genuinely part of identity |
| duplicate, `merge-duplicates`, **no** conflict target | `409 23505`, `"user_meal_plans_slot_identity_key"` |
| same write with the **4-column** target | `200`, updated in place |
| same write with the **old 3-column** target | `400 42P10` — "no unique or exclusion constraint matching the ON CONFLICT specification" |
| read `week_start=eq.2026-08-24` | only week A's row |
| read `week_start=eq.2026-08-31` | only week B's row |
| read `week_start=in.(A,B)` (what the app sends) | both, ordered |
| read a past week `2026-08-17` | `[]` |
| PATCH by full identity on week B | `204`; week B `is_cooked=true`, week A's identical `(day 0, slot 0)` row still `false` |

The `42P10` row is the important one: the old conflict target is now invalid,
so shipping the migration without the matching `slotConflictTarget` change
would have broken every planner overwrite. Same lesson as the redesign
session's `23505`, one layer up.

Cleanup: all probe rows deleted (`204`); `user_meal_plans` reads back `[]` on
both the authenticated and the anon view (RLS still holding). Local session
token removed from the scratchpad. Nothing touched on prod.

---

## Files touched

**New**
- `lib/models/planner_slot_ref.dart`
- `lib/models/planner_week.dart`
- `lib/services/planner_cook_attribution_service.dart`
- `supabase/migrations/20260822120000_add_week_start_to_user_meal_plans.sql`
- `test/services/planner_cook_attribution_test.dart` (15 tests)
- `test/models/planner_week_test.dart` (11 tests)
- `docs/sessions/2026-08-22_planner-corrections.md` (this file)

**Changed**
- `lib/theme/app_design_tokens.dart` — champagne correction, two doc updates
- `lib/screens/weekly_planner_screen.dart` — slot stamping, week mapping,
  `mealPlan` subscription, `onCook` now carries a slot index
- `lib/screens/one_pan_cooking_roadmap_screen.dart` — `plannerSlot` on the
  launch request, screen, resolved state, and the completion write
- `lib/services/weekly_plan_service.dart` — `listForWeeks`, week-scoped
  `deleteSlot`, new `markSlotCooked`, 4-column conflict target
- `lib/services/cook_session_storage_service.dart` — `plannerSlot` on save,
  load and `ActiveCookSession`
- `lib/services/data_change_signal.dart` — `AppDataChanges.mealPlan`
- `lib/nav.dart` — passes `plannerSlot` through the Cook Mode route
- `.claude/settings.json` — dev migrations allowed, relinking denied
- `test/support/fake_weekly_plan_backend.dart` — week-scoped reads, week in
  slot identity, `markSlotCooked` + call recorders
- `test/screens/weekly_planner_redesign_test.dart` — anchored rows, week
  anchoring group, slot attribution group
- `test/screens/weekly_planner_stale_load_test.dart` — its raw row needed a
  `week_start` in the week the real clock will ask for
- `CLAUDE.md`, `docs/CHANGELOG.md`, `docs/DECISIONS.md`

---

## Tests and analyze

`flutter test`: **263 passing** (221 baseline + 42 new), 0 failing.
`flutter analyze`: **46 issues**, 0 errors, 0 warnings — identical to the count
at session start, and none of the 46 are in any file this session touched.

New coverage:

- **Attribution (15):** exactly the launched slot is marked; the same dish on
  two days addresses only one row; the second meal of a day uses its own slot
  index; **the same weekday in two different weeks is two different slots**;
  a null slot issues no write at all; a re-cook never marks; no signed-in user
  is a silent no-op; a thrown write is swallowed and returns false; a slot
  removed mid-cook matches nothing and never inserts; `mealPlan` fires after a
  successful write and not otherwise; `PlannerSlotRef` json round trip, week
  as part of equality, and every unusable shape reading as "no slot"
  (including a pre-anchoring session with no week, which must not be guessed).
- **Week helpers (11):** Sunday 23:59:59 belongs to the previous Monday and
  Monday 00:00:00 starts a new week; every day of a week resolves to the same
  Monday; a Monday is its own week start; month and year boundaries;
  no time component on the result; `plannerWeekAfter` as calendar days across
  a DST month and a year end; the zero-padded `yyyy-MM-dd` value.
- **Screen, week anchoring (7):** the read is scoped to exactly
  `[thisWeek, nextWeek]`; this week and next week are disjoint even with the
  same weekday and slot; a placement stores an anchored week and a 0–6 day
  index; a placement into *next* week stores next week's Monday, not day 10;
  **rollover** — the same backend, no data change, only the clock advanced,
  and last week's "next week" is now this week and cookable while last week is
  gone; a past week is never fetched (row still present, just outside every
  scope asked for); the **Sunday→Monday boundary** moving the champagne tint
  and the whole week one step; and a cook launched at 23:55 on Sunday stamping
  the week it was planned in.
- **Screen, slot attribution (7):** Cook stamps the pressed row; the day's
  second meal stamps slot 1; end-to-end gold (rescue-eligible) and end-to-end
  neutral (not eligible), both flipping **in place** (same `State` asserted);
  same dish on two days flipping only the launched one; a non-planner cook
  touching no plan row; next week offering no Cook button to stamp.
- **Session round trip (2):** a planner cook resumes knowing its row; a
  session saved without one resumes attributing nothing.

The end-to-end tests walk the real seams — real screen, real launch request,
real attribution service, real backend fake — with only the Cook Mode *widget*
stubbed. See "Ambiguities" for what that does and does not cover.

---

## Ambiguities and judgement calls

1. **`plannerSlot` is not on `CookModeRecipePayload`** — the prompt said "ride
   it through the cook payload end to end"; I put it beside `CookModeSurface`
   instead. Reasoning above. This is the one place I read past the literal
   wording, and it is reversible in one field if Harris disagrees.
2. **The end-to-end tests stop at the Cook Mode widget.** They assert the real
   launch request the real screen produced, then run the real completion-side
   service against the same backend. What is *not* covered by a pumped widget
   test is `_logCookSessionCompletion` calling
   `markCookedFromCompletion(slot: _plannerSlot, ...)` — Cook Mode pulls in
   Supabase, Provider and the whole post-cook sheet sequence. The wiring is
   three lines and is covered by the analyzer, not by a test. Worth an
   airplane-mode-style device check alongside the one roadmap item 7 already
   wants.
3. **`markSlotCooked` returns "wrote = true" when the UPDATE matched nothing.**
   PostgREST does not report affected rows without `Prefer: return=`, and the
   distinction does not change any behaviour — nothing retries and nothing is
   shown. Flagged because the test asserts it explicitly and it reads oddly.
4. **A new `AppDataChanges` signal rather than reusing `cookLog`.** Reasoning
   above; it is one extra subscription, not a second mechanism, but it is a
   deviation from "the path is already built" if read narrowly.
5. **`CHECK (day_index between 0 and 6)` deferred**, not forgotten — see the
   migration section.
6. **Stale doc drift found, not fixed:** several comments in
   `one_pan_cooking_roadmap_screen.dart` and `cook_session_storage_service.dart`
   say "See CLAUDE.md Roadmap item 28", but the roadmap has never had an item
   28 — they date from an older numbering. I deliberately did **not** mint a
   real item 28 for week anchoring (it would have made those comments point at
   the wrong thing); it is folded into item 27, which is the same build. The
   stale references are pre-existing and out of scope, but they are a trap for
   the next reader.
7. **Prod is now five migrations behind dev** (`20260818120000`,
   `20260820120000`, `20260820130000`, `20260821120000`, `20260822120000`).
   Unchanged as a standing item, but the gap grew again this session.
