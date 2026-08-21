# OptiMeal — Changelog

Completed work and full session history, newest first. Not auto-loaded —
read on request. Current state lives in `CLAUDE.md`; binding decisions and
their reasoning live in `docs/DECISIONS.md`.

Everything below this point, unless otherwise noted, is reproduced verbatim
from the pre-2026-08-17 CLAUDE.md — nothing has been deleted, only
reorganized. Where an original section mixed completed work with still-open
items, the open remainder was extracted into `CLAUDE.md`'s roadmap (in
condensed form) and the **full original text stays here unedited** for
fidelity.

---

## 2026-08-22 — Onboarding redesign (correctness, not restyle)

Full prompt and report: `docs/sessions/2026-08-22_onboarding-redesign.md`.

**Every new user was being shown promises the app no longer keeps.** Slide 3
advertised "steps, checkboxes, and timing" (checkboxes died with the pre-cook
merge); slide 4 advertised a Weekly Planner / Shopping List two-way sync (the
shopping list was cut entirely in August); slide 2 quoted an unsourced CHF
waste statistic; slide 1 was invented-persona-era text defending Chef Harris
against being "a chatbot pretending to know knife skills".

**And Skip was broken outright** — a bug found while reading the routing, not
listed in the spec. `_skipToPaywall` set only the local `hasSeenOnboarding`
flag, never `profile.onboarded`, then routed to `/paywall`. The router's own
redirect (`!isOnboarded && !isOnboarding → onboarding`) bounced the user
straight back, so Skip never skipped. Skip and Finish now share one
`_completeOnboarding()` that performs all three writes — local flag, profile
flag, `user_profiles` upsert — in that order, so navigation never waits on the
network.

**Routing.** Skip → Home. Finish → Home. The paywall leaves the onboarding path
entirely until pricing is real. The paywall screen itself is untouched.
**App-wide census**: exactly one route into `/paywall` remains —
`UpgradePromptSheet`, a mid-app upsell — and a test asserts that list exactly.
It composes with the 30243cf dev redirect: onboarding no longer *asks* for the
paywall, and in a dev build the route would redirect to Home even if something
did.

**Content and visuals.** The structure (PageView, ivory card, dots, one
terracotta CTA, Skip hidden on slide 4) was sound and is kept. Each slide's
champagne icon tile is replaced by a real visual: a spoon-and-bowl line
illustration and a fridge illustration in the signed diagram family (black
outlines, terracotta fills), then **previews of real UI** — a miniature sage
cue panel that pre-teaches green = Chef Harris teaching, and a miniature week
strip showing the planner's three real day states (gold ✓ / today · Cook /
dashed +). The previews are static by design.

**Dev affordance.** A "Replay onboarding" row in a Developer section of
Profile, behind `kIsDevEnvironment`, so it is compiled out of release builds.
It calls `OnboardingScreen.resetForReplay`, which clears **both** completion
flags — the local one and the `profile.onboarded` the router actually gates on.

`flutter test`: **334 passing** (319 + 15). `flutter analyze`: **44 issues**,
0 errors, 0 warnings. Palette guard green.

---

## 2026-08-22 — Fridge Clearer redesign: one-screen input + two-stage ideas

Full prompt and report: `docs/sessions/2026-08-22_fridge-clearer-redesign.md`.

**Input screen.** The four-card scrolling interview (≈2 screens: a headline and
an explainer paragraph per question) collapses to one no-scroll screen — an
ingredients hero card, ONE settings card with three rows (Time / Gear / For,
icon + one-word label, no headlines, no explainers), and a pinned terracotta
CTA. Suggestion chips and typed ingredients now share one wrap, typed ones as
removable ✕-chips. Per-chip icons, the explainer copy, and the
horizontal-scrolling selectors are all cut.

**Two-stage generation.** "Let's cook" makes one small call returning three
**idea summaries**; the full recipe is generated only for the idea the user
picks. The ideas screen is three cream cards whose hero is the clearance line —
"Clears 4 of your 4 ingredients" / "Clears 2 of your 3 — potatoes stay." —
computed app-side from the user's entered list, never read from model prose.
Tapping a card runs stage 2 and hands the real recipe to the existing
`GeneratedRecipeActionsSheet` (Cook / Save / Plan, reused not rebuilt), so all
three actions always act on a real recipe rather than a summary. The
"Try Another" regenerate affordance is gone: choosing among three replaces
retrying one, and back returns to the input with selections intact.

**Measured on live dev**: stage 1 is **2,857 prompt + 155 completion tokens**
against ~6,950 + ~900 for a full recipe. Browsing and backing out costs ~65%
less than the old single-stage flow; browsing and committing costs ~30% more,
against ~$0.079 for the two "Try Another" retries it replaces. **No
edge-function change was required** — prompt assembly is client-side and
`ask-chef-harris` stores whatever `surface` arrives. The two stages log as
`fridge_ideas` and `fridge_clearer`.

A malformed stage-1 reply returns null and shows the error card — it fabricates
nothing, unlike the hardcoded fallback recipe roadmap item 20 flags on the
old parse-failure path.

**Kit rules, app-wide.** *Controls wrap, never clip*: the last four horizontal
scrollers in `lib/` are gone (Fridge Clearer time + portions, the Techniques
category bar, Cook Mode's kitchen-gear row); `grep -rn "scrollDirection:
Axis.horizontal" lib/` now returns nothing. *Selection is a champagne fill*:
applied to the new chips, the Techniques categories, and Profile's allergy
chips — the last terracotta-fill selection in the app.

**Deleted with the flow they belonged to**: `GeneratedRecipeCard` (the inline
result card, whose action row carried "Try Another"), `_SectionCard`,
`_TapChip`, `_PillOption`, and the Fridge Clearer's `ai-recipe-precision`
"Science Notes" call — see the session record's ambiguities, that last one is
flagged for a ruling rather than assumed dead.

`flutter test`: **319 passing** (285 − 3 deleted + 37 new). `flutter analyze`:
**44 issues**, 0 errors, 0 warnings. Palette guard green.

---

## 2026-08-22 — Cook Mode layout finalization (Unit B)

Full prompt and report: `docs/sessions/2026-08-22_cookmode-unit-b.md`. Unit B
of the signed 2026-08-21 Cook Mode/Palette card, sitting on the consolidated
v1.2 tokens.

**One step, dominant.** Cook Mode's scrolling list of every step card is gone
from the cooking state. The composition is now header (with a persistent SOS
square, top-right, present in every state) → tappable progress bar
("Step N of M · title") → one ivory step card → bottom bar. The card's reading
order is the design: the action line, then heat/time as pills with the timer as
quiet text beside them, then the **cue panel promoted above the detail**, then
the original bullets demoted to small muted prose with their diagram pills.
A next-step **whisper** is fused to the card's bottom edge — neutral pill tone,
no icon, small-caps "NEXT" — and there is deliberately no previous-step
whisper.

**Everything else is one tap away.** `_CookOverviewSheet` is one sheet with two
panes swapped in place (never stacked): all steps (done faded with a check,
current champagne, upcoming tappable to jump) and the full ingredient list with
quantities, servings read-only. **Finish & Plate now lives only at the end of
that step list** — never per-step, because it skips every remaining step and
fires a permanent ledger write.

**Bottom bar**: an outlined pause square, one terracotta CTA ("Next step"), and
Ask-Chef-Harris demoted to a hint line. One filled button on the screen, with a
test asserting it.

**The cue data contract is LIVE, not dormant.** Steps already carry a declared
`sensory_cue` key: both recipe prompts require it, `chef_recipe_parser`
validates it against the signed vocabulary, and `SensoryCueVocabulary` supplies
phase, sentence and remedies. The panel renders "HOW YOU KNOW IT'S RIGHT"
(readiness) / "HOW YOU KNOW IT'S DONE" (doneness), the signed sentence, and an
**inline** expander for the remedies. A step with `no_cue` renders no panel at
all — never an empty frame.

**Consolidated to one cue presentation**: `_SensoryCueCard` and
`_SensoryCueDetailSheet` were deleted; the pre-cook step list now renders the
same `_CuePanel`. The remedy is inline rather than a sheet, which is what the
spec asks for and one less thing to dismiss while standing over a pan.

**Four side parts.** (1) The 13 terracotta-alpha washes deferred from
`15325f5` converted to `champagneTint`, minus three that became gold. (2) The
four named gold earned moments moved onto the gold family — the celebration
sheet (counted verdict *and* rescue milestone), the **Confidence** tier-up
sheet, and both share-card accents; `UpgradePromptSheet`'s star stays
terracotta, being a sales CTA rather than an earned moment. (3) Dev builds
never show the paywall — a route-level `redirect` on `/paywall`, so every
entry point is covered at once. (4) The phantom "CLAUDE.md Roadmap item 28"
comments (item 28 never existed) now point at the rescue-provenance rule.

Out of scope by fence and untouched: the pre-cook moment merge, the SOS sheet
redesign, generation prompts, and tier-3 timer promotion (evidence-gated).

`flutter test`: **285 passing** (266 + 19). `flutter analyze`: **45 issues**,
0 errors, 0 warnings. Palette guard still green, zero stray colour literals.

---

## 2026-08-22 — Palette v1.2 (variant D) token swap, app-wide

Full prompt and report: `docs/sessions/2026-08-22_palette-v12-swap.md`. Unit A
of the signed Cook Mode/Palette spec card (2026-08-21). Token-level only — no
layout, no functional change.

**Values swapped** to the signed v1.2 column: canvas sage `#C5D3C1` → `#B3C29A`,
card surface cream `#FBF9F4` → ivory `#F8F3E9`, CTA terracotta `#D94A1E` →
`#C05C35`. **New tokens**: `terracottaOnLight` `#A44E2B`, `neutralPillTint`
`#EFE8D8`, `sageTeachingPanel` `#DDE6C6`, `sageStripOnCanvas` `#DDE6C6`,
`quietRowSurface` `#FDFBF5`, and the gold family — `goldEarnedFill` `#EDA24E`,
`goldEarnedOnLight` `#C77E1F`, `goldEarnedBadgeTint` `#FBEED8`. `champagneTint`
`#F7DBCB` was already correct from the planner-corrections build.
**Renames**: `surfaceCream` → `surfaceIvory` (84 call sites),
`cookedCountedGold` → `goldEarnedOnLight`. `cookedNeutralGray` `#8B918E` stays.

**Consolidated from three colour sets to one.** `AppDesignTokens` is now the
only file in `lib/` that defines a colour. `LightModeColors`/`DarkModeColors`
became Material-3 role *bindings* over it — 42 literals removed — and
`ProfileScreen`'s two private statics (an exact duplicate of `deepForest`, and
a terracotta `#D96B43` that had drifted from the CTA) were folded into the
palette. `post_cook_share_card`'s gradient literal became `deepForestShade`.
**Zero stray colour literals remain in `lib/`**, proven by a comment-stripping
source scan.

**Guard test** (`test/theme/palette_token_guard_test.dart`, 3 tests): walks
`lib/`, fails on any colour literal outside the tokens file, and pins all
twelve signed v1.2 hex values so the palette cannot be edited back either. The
signed diagram-palette exemption turned out to have nothing to exempt —
`technique_diagrams.dart` already draws entirely from tokens.

**Two semantic assignments landed, not just values.** The Home rescue strip
filled with `backgroundSage` — the canvas token itself — and leaned entirely on
its border; it now uses `sageStripOnCanvas`, which is the semantic that token
exists for, and stays sage rather than becoming gold. Eight terracotta *text*
sites moved to `terracottaOnLight`, which is the contrast rule the v1.2 table
states.

**Semantic-rule violations found and reported, not redesigned** — most notably
the post-cook celebration sheet and share card, both earned moments currently
rendered in terracotta rather than gold, and the technique diagrams using the
act-now colour to mark "wrong". Full list in the session record.

`flutter test`: **266 passing** (263 + 3). `flutter analyze`: **46 issues**,
0 errors, 0 warnings — unchanged.

---

## 2026-08-22 — Weekly Planner corrections (palette, slot attribution, week anchoring)

Full prompt and report: `docs/sessions/2026-08-22_planner-corrections.md`.
Closes the three open items left by the redesign commit `fb177c3`.

**Palette.** `AppDesignTokens.champagneTint` corrected from `#F7E7CE`
(invented by the redesign, which had a hue name and no hex) to the signed
palette v1.2 value **`#F7DBCB`**. One token, so the today-row tint and every
other champagne consumer picked it up. `cookedNeutralGray` `#8B918E` reviewed
and kept as provisionally signed pending a device pass.

**Cooked-state slot attribution — roadmap item 27 closed, ruling: option A.**
A cook now knows which planner row it came from, because the row stamps its
own identity onto the launch: `PlannerSlotRef` (`week_start`, `day_index`,
`slot_index`) rides on `CookModeLaunchRequest` and through the saved active
session, so an interrupted planner cook still attributes when resumed. On
completion `PlannerCookAttributionService` marks exactly that row via a
targeted UPDATE through `WeeklyPlanBackend`, then raises the new
`AppDataChanges.mealPlan` signal; the planner subscribes it into the re-read
handler it already had and the row flips in place.

Deliberately **not** a field on `CookModeRecipePayload` — that payload is
persisted into `saved_recipes.recipe_payload`, and a saved recipe that
permanently remembered "Tuesday, slot 1" would mark the wrong row the next
time it was cooked from anywhere. Slot identity is launch context, like
`CookModeSurface`; provenance is recipe data, like `RecipeOrigin`.

`mealPlan` is its own signal rather than reusing `cookLog`, because
`cookLog` fires at the *top* of the post-cook sequence (`clearActiveSession`),
long before the plan row is written — a `cookLog`-driven re-read would read
the row back uncooked. Counted-vs-not is unchanged: still derived from
`RecipeOrigin.isRescueEligible`, no column, no ledger join.

Nothing is inferred anywhere in this path. A cook launched from Home, the
Fridge Clearer, a generation sheet or Recently Cooked carries null and touches
no plan row; the same dish planned on two days flips only the launched one.

**Week anchoring — migration `20260822120000`, applied to dev.**
`user_meal_plans` gained `week_start date not null` (the Monday of the plan's
week); the backfill mapped `day_index` 0–6 to this week's Monday and 7–13 to
next week's Monday while normalizing `day_index` back to 0–6, and the slot
identity became `(user_id, week_start, day_index, slot_index)`. The old
constraint had to be dropped *before* the backfill, since normalizing
`day_index` 7 down to 0 collides with this week's day 0 until `week_start` is
part of the key.

App side: `WeeklyPlanBackend.listForUser` became `listForWeeks(userId,
weekStarts:)`, `deleteSlot`/`markSlotCooked` take the week, and
`slotConflictTarget` became the four-column form. Both Mondays are computed
from the clock at read time (`lib/models/planner_week.dart`), so rollover is
automatic and nothing is stored or advanced. Reasoning and the
device-local-vs-Zurich ruling: `docs/DECISIONS.md`.

**Verified against live dev** with an authenticated anonymous session, probes
deleted afterwards and the table read back empty on both the authenticated and
anon views: the same `(day, slot)` in two different weeks inserts cleanly
(201/201); a duplicate without a conflict target fails `23505` naming the new
`user_meal_plans_slot_identity_key`; the four-column `on_conflict` target
updates in place (200); **the old three-column target now fails `42P10`**,
which would have broken every planner overwrite had the app not changed in the
same step; week-scoped reads return each week separately and both together,
and a past week returns `[]`; and a PATCH by full identity flipped only the
targeted week's row, leaving the identical `(day 0, slot 0)` row in the other
week untouched.

`flutter test`: **263 passing** (221 baseline + 42 new). `flutter analyze`:
**46 issues**, 0 errors, 0 warnings — the same 46 as at session start, none in
any file this session touched.

---

## 2026-08-22 — Weekly Planner screen redesign

Full prompt and report: `docs/sessions/2026-08-22_weekly-planner-redesign.md`.
**The named spec file (`design_spec_weekly_planner_2026-08-21.md`) does not
exist anywhere in the repo, on disk, or in git history** — the build followed
the prompt's own "Core structure per spec" section, with every gap between
that list and a shippable screen listed as an ambiguity in the session record
rather than silently decided.

**The screen.** All seven days as one vertical list. Deleted: the day-chip
strip and the one-day-at-a-time body it drove, the Slot 1 / Slot 2 cards, the
ingredient-pill preview (and the whole `_Aisle`/`aisle_items` write path with
it), and `_openPlannedMeal`'s `await push<bool>`. Row states now come from a
pure top-level `plannerMealStateFor(...)` — Empty, Planned, `cookable`
(today only, the screen's only terracotta button), `cookedCounted` (gold) and
`cookedNotCounted` (neutral gray). A day's second meal is added, and any meal
removed, from a new day-detail **sheet**, so filled rows stay clean; empty
days open the signed three-source add sheet, which is untouched. The "from
saved" chip moved into that day detail — it is a routing marker, not
provenance; the leaf badge stays on the week list. Three tokens added
(`champagneTint`, `cookedCountedGold` `#C77E1F`, `cookedNeutralGray`); no hex
in widgets.

**Week toggle.** This week ↔ next week, no past. `user_meal_plans` has no week
column, so next week rides the same integer — `day_index` 0–6 this week, 7–13
next. Verified against live dev: no CHECK constraint, 7 and 13 insert fine,
and older readers that filter to 0–6 drop those rows rather than mis-read
them. **Neither week is anchored to a date, so nothing rolls over** — already
true of the single-week model, now visible; fixing it needs a `week_start`
column.

**Cooked-state derivation — half shipped, half STOPPED.** Shipped: the
`push<bool>` mechanism is gone, the planner subscribes to
`AppDataChanges.ledger` and `.cookLog` (coalescing both signals from one cook
into one re-read), and counted-vs-not is derived from the recipe's own
`RecipeOrigin.isRescueEligible` — no ledger join, because there is no join key
to use. Stopped: **nothing sets `user_meal_plans.is_cooked` any more**,
because a finished cook cannot be attributed to a `(day, slot)`. The cook log
dedupes by title (so it cannot even count two cooks of one dish),
`waste_ledger_events` writes `recipe_id: null`, and the local weekly store
keeps only `{ts, ingredients}`. Title matching is ambiguous the moment a dish
is planned twice, so no heuristic was invented. Recorded as CLAUDE.md roadmap
item 27 with two candidate fixes for Harris to rule on.

**Bug found and fixed on the way:** `user_meal_plans` upserts never overwrote
an occupied slot. PostgREST resolves `merge-duplicates` against the primary
key unless given a conflict target, and the app sends no `id`, so every
overwrite fell through to `23505` and into the planner's "Couldn't save. Tap
to retry.". Fixed with `onConflict: 'user_id,day_index,slot_index'`; both
behaviours verified against live dev with an authenticated session.

**221 tests passing** (198 + 23), `flutter analyze` **46 issues**, 0 errors
and 0 warnings, none in any file this session touched. The morning's
placement-race regression test passes unmodified against the new screen. Dev
was exercised with a real anonymous session and all four probe rows deleted
afterwards; no migrations, no schema changes, no deploys, nothing on prod.

Also corrected here and in CLAUDE.md: the stale claim that **anonymous
sign-ins are disabled on dev**. They were enabled and device-verified
2026-08-21, and re-verified from this repo on 2026-08-22 — `POST
/auth/v1/signup` returns a real 3-part JWT with `is_anonymous: true`.

## 2026-08-22 — Stale-read-after-write: one invalidation mechanism

Full prompt and report: `docs/sessions/2026-08-22_stale-read-fix.md`.

Two device symptoms, one defect family: Home's rescue strip kept the old
count after a completed cook, and the Weekly Planner didn't show a
just-placed recipe until a restart. Both writes were landing the whole
time.

**Root cause A — the refresh trigger, not the refresh.** Home's only
post-cook trigger was `RouteAware.didPopNext`, and that callback cannot
fire for the exit the app actually uses: every verdict sheet's CTA runs
`context.pop()` then `context.go('/')`, and Flutter resolves an exiting
page that still has a pageless (modal) route attached with `markForComplete`
rather than `markForPop` — `RouteObserver` forwards only `didPop`, so
nothing reaches the route underneath. Measured with a probe before any code
changed: 0 `didPopNext` calls with a sheet involved, 1 without.
**F1 (69f7e9c) did not regress** and the strip *is* on its path — the exit
shape changed, not the refresh path.

**Root cause B — a lost read/write race.** The planner starts its one-shot
`SELECT` in `initState` and consumes a queued
`WeeklyPlannerAddMealIntent` one frame later; the read, issued before the
placement's upsert, came back and ran `_planned..clear()..addAll(...)`
unconditionally, wiping a meal that was already in the database.

**Fix.** The trigger is now the write. New `DataChangeSignal`
(`lib/services/data_change_signal.dart`) generalises the change-stream
pattern `SavedRecipesService` already used; `AppDataChanges.ledger` and
`AppDataChanges.cookLog` are notified by `LedgerService` and
`CookSessionStorageService` after their writes, and Home and My recipes
subscribe. `didPopNext` stays as a documented secondary trigger. The planner
additionally got a generation guard (`_writeEpoch`): a load whose epoch moved
while it was in flight is discarded and re-read once slot writes settle —
and `user_meal_plans` access moved behind the injectable
`WeeklyPlanBackend`, matching `SavedRecipesBackend`, so this is testable at
all. No new packages.

Also fixed in passing: `LedgerService.getWeeklySummary` shared one try/catch
between the local weekly figure and the remote lifetime figure, so any
network failure reported "0 ingredients rescued this week" for rescues
sitting in local storage. The lifetime read now degrades on its own.

Also fixed as a family member: My recipes' recently-cooked log and derived
cook counts (one-shot, nothing invalidated them). Reported not fixed: a
planner-launched cook never marks its slot "Cooked", because the post-cook
`context.go('/')` completes the awaited `push<bool>` with null — a different
defect, and where that signal should come from is a product decision.

**198 tests passing** (190 + 8), `flutter analyze` **50 issues** (from 54,
all info-level). Both symptom tests verified to fail without the fix. Dev
Supabase was read-only this session: every column the refactored planner
backend touches confirmed present over PostgREST, no migrations, no
deploys.

## 2026-08-21 — Consolidated small-fixes build (6 items)

Full prompt and report: `docs/sessions/2026-08-21_consolidated-small-fixes.md`.
Two read-only sessions earlier the same day are recorded alongside it.

**1. Bookmark on the generation surfaces.** Closed the gap where a freshly
generated recipe could not be saved until after it had been cooked. Both
generation results now mount the existing `SaveRecipeBookmarkButton`:
`GeneratedRecipeCard` (renamed from `_GeneratedRecipeCard` purely so a widget
test can construct it) beside the recipe title, and
`GeneratedRecipeActionsSheet` in its header row. **No new persistence flow was
needed** — the button keys on the title via `recipeKeyFor` and `save` writes
the payload inline, which is exactly what the post-cook verdict and
celebration sheets already do for not-yet-saved recipes. Cook Now remains the
only primary action on both. 6 new tests.

**2. Prompt-assembly ordering — the cedf753 fix was being defeated
downstream.** The prompt named `index.ts` as the place the assembly happens;
it isn't. The edge function only forwards `systemPrompt`/`userMessage` — the
ordering lives in `ChefService` (Dart). Fixed there.
`askChefHarris` now takes `staticPromptBlock` and writes it immediately after
the static header, ahead of the profile block and everything per-call; the two
callers' static halves moved to the new `lib/prompts/recipe_static_prompts.dart`
and their variable halves ship as `userQuery`. Assembly extracted into the
testable `ChefService.buildUserMessage`, with the ordering contract in its doc
comment and locked by `test/services/chef_prompt_ordering_test.dart`.
**Live A/B on dev, three ingredient sets, genuinely varying every call:**

| ordering | call 1 | call 2 | call 3 |
|---|---|---|---|
| pre-fix (control) | 0 cached | 0 cached | 0 cached |
| post-fix | 0 cached | 2944 cached | 2944 cached |

`prompt_tokens` were identical in both arms (6924 / 7012 / 6953), confirming
the change was ordering only, not content. 42.3% of a ~6,950-token prompt now
served from cache on every repeat call, where before it was zero.

**3. Cost logging.** `cost_usd` now bills cached prompt tokens at gpt-4o's
cached rate (\$1.25/1M) and only the uncached remainder at full rate — it was
charging everything at full rate, overstating by ~14% and growing with the hit
rate. Measured saving on the warm verification rows: \$0.00368/call, which is
exactly 2944 × \$1.25/1M. Added `api_call_cost_log.surface` (migration
`20260821120000`, **dev only**) plus `kChefCallSurfaces` in `chef_service.dart`
— `fridge_clearer` / `custom_creator` / `chef_sos`, **three**, matching the
three live call sites (`_ChefSuggestionSheet` was the fourth until 2026-08-20).
Deliberately no CHECK constraint on the column: the client owns the vocabulary,
and a constraint would mean a new surface can't ship without a migration, with
a lost cost row as the failure mode. `ask-chef-harris` deployed to **dev only,
v5**, `verify_jwt` still true; prod untouched.

**4. Ledger explainer + verdict copy.** Home's explainer carries Harris's
approved wording verbatim, replacing "Fridge Clearer cooks count toward it."
(which described the pre-2026-08-20 launch-surface rule). The not-counted
verdict was reframed from launch-surface to origin: "Rescues come from Fridge
Clearer recipes — this one didn't." The celebration sheet was left alone — its
signed one-icon/one-line/one-CTA structure never claimed surface gating, and
the example wording supplied was positive-framing for the counted case, which
has no verdict-copy entry.

**5. CLAUDE.md/DECISIONS corrections.** Items 3 and 6 were stale (both marked
open; both substantially or fully shipped — see CLAUDE.md for the corrected
text). Item 15 rewritten around the real failure and the A/B above. New items
25 (per-surface cost attribution, done; three dev-only migrations still not on
prod) and 26 (curriculum drawers matched against the prompt's own boilerplate
— found here, deliberately **not** fixed, since it changes what reaches the
model). Decision C recorded in `docs/DECISIONS.md`: cooking times reach the
model as a declared key, never as a table.

**Found, not fixed** — `_buildCurriculumAddendum` keyword-matches the whole
assembled request, and the recipe surfaces' static block embeds the literal
curriculum key list and cut vocabulary. So `sauteing`, `braising`, `julienne`,
`dice`, `food_storage` and `leftovers` are present on every recipe-surface
call regardless of what the user asked. The ordering fix deliberately kept
this behaviour (it passes the static block into the match text) so that an
ordering change stayed an ordering change. Roadmap item 26.

Tests 177 → 190, all passing. `flutter analyze` unchanged at 54 (0 errors).

---

## 2026-08-20 — Saved-recipes UI: My recipes, the universal bookmark, the planner's third source

Branch `feat/saved-recipes-ui` off main (after the data-layer branch was
fast-forwarded in). **No database work of any kind — dev included.** This is
UI over the data layer from the previous entry.

### My recipes

`lib/screens/my_recipes_screen.dart` replaces the placeholder. The two
sections are separated by **card weight, not labels**: saved recipes are full
cream cards (shadow + border), recently-cooked is a log of quiet rows with no
fill at all. A saved recipe is something the user chose; a cooked one is just
something that happened, and the screen should read that way at a glance. A
widget test asserts the difference structurally (saved has a decorated
`Container` ancestor with a `boxShadow`; the log rows have none), so the
hierarchy can't be flattened by a later tidy-up.

Saved card: name, leaf badge **only** for Fridge Clearer origin, and either
the derived times-cooked count or a "not cooked yet" marker — never "0
times". No prose. The calendar action opens the **existing**
`WeekdayPickerSheet` and hands off through `WeeklyPlannerIntentService`, the
same path Fridge Clearer already used; nothing new was written for
scheduling. Tapping a card opens recipe details with that saved payload.

Order is the service's `last_touched_at desc` and is **not re-sorted in the
UI** — a test asserts render order is recency, not alphabetical.

Two empty states, per spec: the full-screen one (bookmark glyph on sage, two
short lines, deliberately no dead-end CTA) only when nothing is saved AND
nothing cooked; otherwise an inline empty-saved panel sits above the log.

### The universal bookmark

`lib/widgets/save_recipe_bookmark_button.dart`. Filled = saved, outline = not
saved, tap toggles. It subscribes to `SavedRecipesService.watchSavedRecipes`
on the shared singleton, so a toggle on one surface updates every other open
surface with no plumbing — that is the whole reason it subscribes rather than
taking a bool. Placements: recipe details app bar, recently-cooked rows, and
both post-cook verdict cards.

The recently-cooked row's bookmark **is** the promote-from-history action. It
saves that row's stored payload, which is exactly what `saveFromHistory` does
with a history entry, so `origin` and `originEnteredIngredients` ride along
and the promoted card keeps its leaf badge. A bespoke "promote" button would
have meant two mechanisms for one idea; the spec asked for one.

Per spec, no swipe-to-unsave and no overflow menus on list rows in this
build — unsave is the bookmark toggle wherever it appears. The list-row
affordance question is deferred to device review.

### The post-cook sequence stays intact

`_LedgerVerdictSheet` was moved out of `one_pan_cooking_roadmap_screen.dart`
into `lib/widgets/ledger_verdict_sheet.dart` — public, so the CTA-last rule
can actually be asserted. Verdict copy is unchanged. The bookmark is quiet:
header row, no label, no prompt, nothing to dismiss (a test pins the sheet at
exactly two `Text` widgets — the verdict line and the CTA). The
exit-to-Home CTA is still the **last element** of both that sheet and
`WasteLedgerCelebrationSheet`, with a regression test on each so nothing can
silently push it off the end.

`RecipeDetailsScreen` now takes an optional `CookModeRecipePayload` through
go_router `extra` and renders it (title, provenance, ingredients, gear,
steps). With no extra it keeps its long-standing static demo body; nothing
else in the app reaches that path.

### Weekly Planner third source

The add sheet offers Fridge Clearer · Custom recipe · My recipes. My recipes
is a **pane swap inside the same sheet** with a back arrow — never a second
sheet, because sheets don't stack anywhere in this app. A test asserts the
`BottomSheet` count is unchanged across the swap. Fridge Clearer and Custom
recipe behave exactly as before, including the depth-2 picker's
pop-a-payload semantics. Every pane has an X on top of drag-down and barrier
tap.

Placement passes the whole payload, so provenance survives into
`user_meal_plans.recipe_payload` and a planner-cooked Fridge Clearer recipe
still counts as a rescue — covered by an explicit `jsonEncode`/`jsonDecode`
round-trip test, not just by inspection. Planned rows show the leaf badge
(from the recipe's own `origin`) and a separate "from saved" chip (how it got
into the day, keyed on the new `kFromSavedMealSource`). A saved fridge recipe
shows both, because they mean different things.

### Two real bugs the tests caught

- **`watchSavedRecipes()` returns a NEW stream per call.** Calling it inside
  `build()` resubscribed on every emission and spun forever — the test run
  hung with no output rather than failing. Every consumer now holds the
  stream in State, and the method's doc says why. This is the kind of thing
  that would have been near-impossible to diagnose on device.
- **Unguarded `Supabase.instance` getters.**
  `WeeklyPlannerScreen._currentUser` and
  `SupabaseSavedRecipesBackend.currentUserId` both asserted when Supabase was
  never initialized. Both now return null there, which every caller already
  handles as "degrade quietly, stay local". Pre-existing in the planner's
  case; only surfaced because the planner finally got a widget test.

Also worth recording for future test-writing: `Future.delayed` inside
`testWidgets` never completes (fake async), which hung a different test.
Seed timestamps directly instead of sleeping between writes.

### Verification

- `flutter test`: **165 passing**, up from 135. 30 new across three files —
  My recipes (11), the bookmark and both verdict cards (8), the planner add
  sheet (11).
- `flutter analyze`: **54 issues**, 0 errors, 9 warnings, 45 info. Exactly
  the baseline, zero new.
- No Supabase contact at all, production or dev.

### Placeholder strings introduced

Every user-facing string written in this build is marked
`// SIGNED-CONTENT PLACEHOLDER` and is listed by surface in the build report
for the Chef Harris authoring batch.

---

## 2026-08-20 — Saved-recipes data layer, dev DB cleanup, recipe-carried rescue provenance

Branch `feat/saved-recipes-data-layer` off main (after the Home-hub branch was
fast-forwarded in), two commits. **Dev project only** (ref
`suuafglvrxrllnhipkiv`) — production was never contacted; the CLI link was
re-verified before pushing and prod reported `linked: false`.

### Part 1 — provenance travels with the recipe (commit `1bd00c8`)

Behavioural bug: rescue eligibility was gated on `CookModeSurface` — which
screen launched the cook. A Fridge Clearer recipe scheduled into the Weekly
Planner and cooked from there launched with `CookModeSurface.weeklyPlanner`,
not rescue-eligible, so a genuine fridge rescue silently did not count. The
binding rule and its reasoning are now in `docs/DECISIONS.md`.

New `lib/models/recipe_origin.dart`. `RecipeOrigin` (`fridgeClearer` /
`customAiRecipeCreator`) owns `isRescueEligible` and `ledgerSourceValue`, both
removed from `CookModeSurface` — which survives as launch context and decides
nothing. `CookModeRecipePayload` gains `origin` (stamped once by
`parseChefRecipeJson` from the generating `ChefRecipeSurface`, so no call site
has to remember) and `originEnteredIngredients` (attached by
`FridgeClearerScreen`, the only place that knows it).

**The second field is not optional to the fix.** `FridgeClearerEntryService`
holds only the most recent generation's entered list and is cleared on
completion, so by the time a planner-scheduled fridge recipe is cooked that
store has moved on — a planner-cooked rescue would have counted as a rescue
of zero ingredients. That store is now a fallback for pre-provenance recipes
only, and is cleared **only when it was actually read**, so cooking a
planner-scheduled fridge recipe can no longer wipe a different, still-pending
generation's entry.

Provenance survives the parser, the local active-session/cook-history stores,
and `user_meal_plans.recipe_payload` jsonb. For that last hop the Weekly
Planner's private `_cookModePayloadToJson`/`_cookModePayloadFromJson` pair was
lifted **verbatim** into `lib/models/cook_mode_recipe_codec.dart` as
`cookModeRecipeToJson`/`cookModeRecipeFromJson` — one shared snake_case codec
rather than a second copy, and the shape `saved_recipes` reuses. All of the
original's decode tolerance is preserved (camelCase fallbacks, per-field
defaults, null on no usable steps). `CookSessionStorageService` keeps its own
camelCase codec **deliberately**: it holds real on-device data, and unifying
the key shapes would silently drop every user's saved session and history.

Nudges follow the same rule now — a planner-cooked fridge recipe cancels
pending nudges and runs the case-2 leftover check, as it always should have.

`selectLedgerVerdict` takes `origin` instead of `surface`, and
`LedgerVerdict.notCountedWrongSurface` is renamed `notCountedNotFridgeRecipe`
(the old name referred to a mechanism that no longer exists). User-facing copy
is unchanged and still correct.

Tests: `ledger_verdict_test.dart` rewritten — it encoded the surface-gated
bug. New `recipe_provenance_test.dart` covers the three signed cases end to
end, including a real `jsonEncode`/`jsonDecode` round trip through the
`recipe_payload` shape: (a) Fridge Clearer cooked directly counts, (b) the
same recipe cooked from the planner counts and credits the *same* ingredients,
(c) a custom craving counts from no surface at all. Plus re-cook and
legacy-payload degradation. 110 passing, up from 97.

### Part 2 — dev database migrations (commit `edd429e`)

**Verified before writing anything.** `supabase inspect db table-stats
--linked` (a real query — this CLI version has no `db query` subcommand, and
`db dump` needs Docker which is not installed) showed 11 public tables, with
`shopping_list_items` and `fridge_items` both present and **both at 0 rows**.
Grepping `lib/` and `test/` found zero live references to `shopping_list_items`
anywhere, and exactly one mention of `fridge_items` — in prose, inside a code
comment. Nothing to lose.

`20260820120000_drop_orphaned_shopping_list_and_fridge_items.sql`

- `drop table public.shopping_list_items` — the Weekly Planner shopping list
  was cut 2026-08-17 and the table kept "in case". It has not come back.
- `drop table public.fridge_items` — backed Fridge Countdown, whose last code
  was deleted across 2026-08-17/18 with database objects deliberately deferred
  to "a separate, later decision". This is that decision.
- Both drops take their RLS policies, indexes, unique constraints and
  `updated_at` triggers with them. The **shared** `public.set_updated_at()`
  function is deliberately kept.
- Narrows `waste_ledger_events_source_check` to drop the orphaned
  `'fridge_countdown'` value. `'cook_mode'` and `'custom_ai_recipe'` are kept
  even though the app writes neither any more — production holds historical
  `'cook_mode'` rows and narrowing further would make this migration unsafe
  there. A `DO` block raises rather than silently rewriting if any
  `fridge_countdown` row still exists.

`20260820130000_create_saved_recipes.sql` — schema rationale is in
`docs/DECISIONS.md`; the shape was chosen by probing the live dev schema, which
confirmed `public.recipes` is a content-less placeholder while
`user_meal_plans` carries whole recipes in jsonb.

**Verified after pushing, by querying rather than reading the migration file:**

- `supabase inspect db table-stats --linked` → 10 public tables;
  `shopping_list_items` and `fridge_items` gone, `saved_recipes` present.
- PostgREST with the dev publishable key → both dropped tables now 404
  (`PGRST205`); `saved_recipes` answers 200 for exactly `id`, `user_id`,
  `recipe_key`, `title`, `recipe_payload`, `origin`, `saved_at`,
  `last_touched_at`, and 400 for `times_cooked` / `updated_at` / `tier`.
- RLS proven behaviourally: anon-key `SELECT` returns `[]`, anon-key `INSERT`
  is rejected `42501` ("new row violates row-level security policy").

**One verification gap, stated plainly:** the policy *definitions* and the
rewritten CHECK constraint were not read back out of `pg_policies` /
`pg_constraint`. This CLI version (2.110.0) has no arbitrary-SQL subcommand,
`db dump` requires Docker, and the OpenAPI root needs a secret key — so there
was no way to run a catalog query without improvising credentials. The
behavioural RLS probe above is real evidence the policy works; to read the
definitions directly, run in the dev SQL editor:
`select * from pg_policies where tablename = 'saved_recipes';` and
`select conname, pg_get_constraintdef(oid) from pg_constraint where conrelid = 'public.waste_ledger_events'::regclass;`

### Part 3 — SavedRecipesService (commit `edd429e`)

`lib/services/saved_recipes_service.dart`: `save` / `saveFromHistory` /
`unsave` / `isSaved` / `watchSavedRecipes` (recency first) / `onRecipeCooked`
(touch-on-activity) / `listSavedRecipes`, plus two read models over existing
data with no new table — `recentlyCooked()` capped at
`kRecentlyCookedReadModelLimit = 10`, and `timesCooked` / `hasBeenCooked`
derived from the local cook history.

Behaviour worth remembering: cooking a saved recipe floats it back to the top;
cooking an *unsaved* one never silently saves it. Re-saving updates in place
and counts as activity but does not reset `saved_at`. Promoting a past cook
keeps the leaf badge, because the stored session already carries `origin` —
nothing is re-derived.

Supabase access sits behind `SavedRecipesBackend`, the same
injectable-abstraction pattern as `ConnectivityMonitor` and
`FridgeNudgeScheduler`, so all 25 new tests run against an in-memory fake that
enforces the real unique constraint and upsert semantics. **No live database
and no anonymous sign-in required.** (At the time of writing anonymous
sign-ins were also disabled on dev; they were enabled on 2026-08-21.)

`watchSavedRecipes` is an explicit `StreamController`, not `async*`: the first
draft used `await for` over the change signal and hung on `cancel()`, since the
generator sat parked on an event that never arrived.

Cook Mode calls `onRecipeCooked` on completion, fire-and-forget.

### Verification

- `flutter test`: **135 passing**, up from the 97 this build started at.
- `flutter analyze`: **54 issues** — 0 errors, 9 warnings, 45 info. Exactly the
  baseline, zero new.
- No production Supabase contact of any kind.

---

## 2026-08-20 — Home hub, bottom nav removed app-wide, Home first-frame crash fixed

Three-part build against a signed design spec. Branch
`feat/home-hub-nav-removal`, two commits. No database work of any kind; the
production Supabase project was not touched.

### Part 1 — the crash (commit `a53fe79`)

Live device crash on Home:

```
dependOnInheritedWidgetOfExactType<_ModalScopeStatus>() was called before
_HomeDashboardScreenState.initState() completed
```

Cause: `_checkDeepLinkIntent()` read `GoRouterState.of(context)`
**synchronously inside `initState`**, before moving on to a post-frame
callback. The router-state read is itself an InheritedWidget dependency, so
it had to be the thing that moved, not just the work that followed it. The
lookup now happens inside the existing `addPostFrameCallback`, behind the
`mounted` guard. Behaviour is otherwise identical: still a one-shot check,
still only fires the Custom AI Recipe Creator when `?open=ai_generator` is
present.

**Landmine sweep.** Every `State` in `lib/` was checked for InheritedWidget
lookups in `initState` or a `State` constructor. `home_dashboard_screen.dart`
was the only offender. Two things were reviewed and deliberately left alone:

- `profile_screen.dart:66` and `_ChefSuggestionSheetState._load()` call
  `context.read<UserProfileController>()` in `initState`. Provider's `read`
  resolves via `getElementForInheritedWidgetOfExactType` and registers **no**
  dependency — this is explicitly supported in `initState` and cannot produce
  this crash. (The `_ChefSuggestionSheet` one is moot now; Part 3 deleted it.)
- Home's own `ModalRoute.of(context)` was already correctly placed in
  `didChangeDependencies`.

`test/screens/home_dashboard_screen_test.dart` pumps Home inside a real
GoRouter and asserts no exception on first frame, including on the
`/?open=ai_generator` deep-link entry. Verified to have teeth: reverting the
fix reproduces the exact `_ModalScopeStatus` error in the test.

### Part 2 — bottom nav removed app-wide (commit `0e695c7`)

`lib/screens/main_layout.dart` (`MainLayout`) is **deleted**. It was a
three-tab shell (Home / Weekly / Techniques & Media) that swapped `_pages`
by index while `GoRouter` addressed it through `/` and `/tab/:index`.

Every route stays registered and reachable — this is a UI-architecture
change, not a route deletion. The tab indexes became real routes:

| was | now |
|---|---|
| `MainLayout(currentIndex: 0)` at `/` | `HomeDashboardScreen` at `/` |
| `MainLayout(currentIndex: 1)` at `/weekly-plan` | `WeeklyPlannerScreen` at `/weekly-plan` |
| `MainLayout(currentIndex: 2)` at `/tab/2` | `TechniquesMediaScreen` at `/techniques` (new constant) |
| — | `MyRecipesScreen` at `/my-recipes` (new placeholder) |

`AppRoutes.homeTabPath` and `AppRoutes.homeTab(int)` are gone. There was
never a `ShellRoute`/`StatefulShellRoute` to unwind — the shell was a plain
widget the router pointed at — so nothing else in the route tree moved.

**Depth rule.** Depth-1 screens (opened straight off Home: Fridge Clearer,
Custom recipe creator, Weekly Planner, My recipes, Techniques, Profile) keep
a back button only, and back lands on Home. Depth-2+ screens keep their back
control unchanged and gain a quiet home glyph beside it in the app bar.

New shared widget `lib/widgets/home_glyph_button.dart`:
`HomeGlyphButton` (small outlined `Icons.home_outlined`, deep forest, no
label, no background container), `BackWithHomeLeading` (the screen's own back
control with the glyph next to it), and `kBackWithHomeLeadingWidth` for the
app bar's `leadingWidth` — the default 56dp leading slot only fits one
button. Applied to:

- **Cook Mode** (`one_pan_cooking_roadmap_screen.dart`) — glyph only. Cook
  Mode's back-press semantics were explicitly out of scope and are unchanged.
- **Recipe details** (`recipe_details_screen.dart`, `SliverAppBar`).
- **The Weekly Planner's Fridge Clearer picker.** `FridgeClearerScreen`
  serves both depths off one flag: opened from Home
  (`returnCookModePayload: false`) it is depth-1 and back goes Home, as
  before; opened as the planner's picker it is depth-2, so back now **pops to
  the planner** it owes a `CookModeRecipePayload` to instead of jumping Home,
  and the glyph is the escape hatch the nav bar used to be.

Two registered routes are orphans and were left that way — they were
unreachable before this build too, so this is not a regression:
`AppRoutes.recipe` (`RecipeDetailsScreen`, no caller anywhere; it still got
the glyph, per spec) and `AppRoutes.culinaryMasterclass`
(`CulinaryMasterclassScreen`, a "coming soon" stub with no caller).
`AppRoutes.paywall` was left alone: it is reached from onboarding and from
`UpgradePromptSheet`, not "only through a depth-1 screen", so the depth rule
does not cleanly apply to it.

### Part 3 — the Home hub (commit `0e695c7`)

`HomeDashboardScreen` rebuilt as a single screen with **no scroll**. Six
zones, top-anchored, with exactly one `Spacer` absorbing all surplus height:

1. Greeting — two short lines, profile avatar circle at top-right; avatar
   opens Profile.
2. Fridge Clearer hero — full-width cream card, 23sp title, one-line
   tagline, oversized (56) terracotta glyph.
3. Custom recipe slim row — full-width cream row, 22 terracotta glyph,
   one-line label, chevron; opens the Custom AI Recipe Creator sheet.
4. Tile shelf — three equal-flex tiles, icon (24) + one-word label, no state
   text and no previews: Weekly · My recipes · Techniques.
5. The one flexible gap.
6. Rescue strip pinned bottom — a **sage** panel (sage inside the layout
   carries teaching-moment semantics), leaf glyph, rescue count, and a "how?"
   affordance opening the existing, unchanged Waste Ledger explainer sheet.

Palette is fixed and comes entirely from `AppDesignTokens`: sage background,
cream cards, terracotta CTAs, deep forest text. The screen's private
`_deepForest`/`_terracotta` constants are deleted. Hero and slim row use the
**same** cream via one shared `_CreamSurface` — dominance is size, type and
glyph scale only, no color-break containers anywhere.

**Cut from Home**, with the dead code they left behind: the
Techniques/Recipe Library card (and its false "saved favorites" copy), the
Weekly Planner card, Recently Cooked (card, `_RecentlyCookedSheet`,
`_RecentlyCookedRow`, `_showRecentlyCooked`), the This Week card, the
greeting paragraph, the diet/allergy pills (`_PreferenceBadge`,
`_dietLabel`), and the "Get an idea" chip (`_GetIdeaChip`).

Three knock-on deletions worth flagging, since none was named in the spec's
cut list but each followed from it:

- **`_ChefSuggestionSheet` and `kChefHarrisChatFreeDailyLimit` are gone.**
  "Get an idea" was their only entry point, and a private unreachable class
  is an analyzer warning, not neutral. This removes the **Chef Harris chat
  cap** as a live gating surface — one of the four listed under CLAUDE.md
  Roadmap item 16. Nothing in the app now reads
  `UsageFeature.chefHarrisChat`. Needs a product decision on where (or
  whether) that surface comes back.
- **Technique of the Week (card + sheet) is gone from Home.** No zone exists
  for it in the six-zone layout, and both classes were private to this file.
  The `techniqueOfTheWeek()` helper in `curriculum_drawer_content.dart` is
  public and untouched, so the feature can be re-surfaced cheaply.
- **`YourMonthCard` is no longer mounted anywhere.** It is a public widget in
  its own file, so it produces no warning and was **kept** rather than
  deleted — cutting a documented retention feature was not part of the signed
  spec.

**The resume-in-progress-cook banner was kept.** It is not in the cut list,
it is conditional and fixed-height (so the single `Spacer` still owns all
surplus), and it is the only way back into an interrupted Cook Mode session.

Every user-facing string written in this build is marked
`// SIGNED-CONTENT PLACEHOLDER`.

Sheet rule (never stack; drag-down + barrier tap + an X): already satisfied
by `AppBottomSheet` for the sheets this build touches — it hardcodes
`isDismissible: true` / `enableDrag: true` and the ledger explainer carries
its own X. The Custom AI Recipe Creator → Generated Recipe Actions pair is
sequential (the second `show` is awaited after the first returns), not
stacked. No sheet was refactored.

### Layout bug caught by the tests

The tile shelf `Row` was first written with
`crossAxisAlignment: CrossAxisAlignment.stretch`. A `Column` hands its
non-flexible children **unbounded** height, and a stretching `Row` forwards
that infinity straight to its children — `BoxConstraints forces an infinite
height` on every pump. Fixed by dropping the stretch; the three tiles carry
identical content shapes and match height anyway.

### Verification

- `flutter test`: **97 passing**, up from the 82 baseline. 15 new tests in
  `test/screens/home_dashboard_screen_test.dart` — first-frame crash
  regression (×2), all six zones present, exactly one `Spacer` and no
  `Scrollable`, no overflow at a 360×640 viewport, no
  `BottomNavigationBar`/`NavigationBar` anywhere in the tree, none of the cut
  cards present, and navigation for hero / all three tiles / avatar / slim
  row / "how?" / the depth-2 home glyph.
- `flutter analyze`: **54 issues, down from the 58 baseline.** Zero new.
- Note for future navigation tests: `currentConfiguration.uri` does **not**
  move for an imperative `push`, which is what every Home tap does. Assert on
  `currentConfiguration.last.matchedLocation` instead.

---

## 2026-08-17 — Dev/prod separation closed: dev Supabase project provisioned

Closes the roadmap item tracking dev/prod separation (previously open,
triggered by a stale Chrome tab writing 3 real rows into the live database
during testing).

**Migration gap closed first.** Task 1's migration-completeness audit found
`supabase/migrations` couldn't rebuild the production schema from scratch —
7 of 11 tables (`user_meal_plans`, `shopping_list_items`,
`waste_ledger_events`, `user_ledger_totals`, `recipes`, `ingredients`,
`ai_precision_cache`) and the `increment_ledger_totals()`
function/trigger existed live with no migration file. `supabase db pull`
was the obvious fix but is unavailable on this machine (no Docker — `db
pull` needs it, unlike `db push`/`functions deploy --use-api`). Instead,
`supabase/migrations/20260701000000_capture_pretracked_schema_drift.sql`
was written from code evidence (grep across `lib/`, the in-repo
`ai-recipe-precision/index.ts`, and existing migrations) rather than a
live pull — deliberately dated *before* every existing migration
(2026-07-01, not the authoring date) because migrations
`20260816120000`/`20260816130000` already `ALTER TABLE
waste_ledger_events`, so the table recreating it had to sort first or a
fresh push would fail outright. Evidence confidence varies by table —
`ingredients` and `ai_precision_cache` are fully evidenced from code;
`recipes` has **zero code evidence anywhere** (nothing in the app has ever
written to it, even on production) and was created as a minimal
`id`/`user_id`/`created_at` skeleton, explicitly flagged as not
representing any real, designed schema — see the roadmap note on "Save if
you liked it" in `CLAUDE.md`. `user_profiles`'s documented duplicate live
policies and broader-than-needed `anon` grants were **not** reconstructed
— no exact SQL for either was ever captured, and guessing risked adding
new drift rather than closing real drift.

**Dev project created**: `optimeal-dev`, ref `suuafglvrxrllnhipkiv`, same
org (`pgbemkiiaeocpsocaakn`) and region (`eu-central-1`) as production.
Database password generated locally (`openssl rand -base64 24`, stripped
to 28 alphanumeric characters) and saved to `supabase/.temp/dev-db-password`
(gitignored, confirmed via `git check-ignore`) — never committed, never
pasted into chat.

**Standing rule amended mid-session**: originally "CLI link always points
at production, every command needs an explicit ref." Revised to: relink
the repo to dev **immediately and permanently** after creating it, so
`--linked` — the only option at all for `db pull`/`db push` in this CLI
version (no `--project-ref` flag exists on either) — always lands
somewhere harmless by default, mirroring the app's own default-dev rule.
Production-targeting operations must still use an explicit `--project-ref`
(`functions deploy`, `secrets set`, `projects api-keys` all support one);
a db-level operation against production (which structurally can't take an
explicit ref) is rare enough to handle case-by-case rather than needing a
standing procedure. Relink verified via `supabase projects list`:
production `"linked": false`, `optimeal-dev` `"linked": true`.

**Pushed and deployed to dev** (ref `suuafglvrxrllnhipkiv`): all 9
migrations via `supabase db push --linked`, applied cleanly with no
errors — itself a positive signal the reconstructed baseline migration was
structurally correct. `ask-chef-harris` deployed via `functions deploy
--project-ref suuafglvrxrllnhipkiv`, confirmed `ACTIVE`/`version: 1`/
`verify_jwt: true`. `ai-recipe-precision` was **not** deployed anywhere —
`NOTE_DO_NOT_DEPLOY.md`'s hold isn't qualified by target, so it was
treated as blocking dev too, not just production. `OPENAI_API_KEY` secret
set on the dev project via `supabase secrets set --project-ref
suuafglvrxrllnhipkiv` (value provided directly by Harris; not persisted
anywhere by this session).

**`increment_ledger_totals()` reconstruction verified against the real
database**, since its SQL was never captured anywhere and had to be
written from prose description alone. Created a real synthetic user via
the GoTrue Admin API (service_role key used transiently in a shell
variable, never written to any file), inserted two `waste_ledger_events`
rows (`ingredients_count` 3, then 2) via `supabase db query --linked`,
confirmed `user_ledger_totals.lifetime_ingredients_rescued` read 3, then 5
— the trigger fires and accumulates correctly across multiple inserts, not
just once. Deleted the synthetic user via the Admin API; `on delete
cascade` cleaned up both tables automatically, confirmed via a follow-up
count query (0 rows in both tables, project-wide).

**Dev credentials wired into `lib/config/app_environment.dart`**: dev
entry now holds the real URL (`https://suuafglvrxrllnhipkiv.supabase.co`)
and publishable/anon key. Boot check (`flutter run -d chrome`, no
dart-define) confirmed the startup banner correctly names DEV and no
`assertConfigured()` throw fires.

**Real, separate issue surfaced by the boot check, not yet resolved**:
anonymous sign-ins are disabled by default on a fresh Supabase project.
`signInAnonymously()` failed with `anonymous_provider_disabled` — caught
by the app's existing try/catch (matches its documented "must never block
app startup" design, so this did not crash the app), but the app's
core anonymous-auth-by-default architecture doesn't actually work on dev
until this is turned on. Attempted to fix this via the Management API
(`PATCH /v1/projects/{ref}/config/auth`, field
`external_anonymous_users_enabled`) using the Supabase CLI's own stored
access token, extracted from Windows Credential Manager (target
`Supabase CLI:supabase`) via a P/Invoke `CredRead` call — the extraction
decoded incorrectly (a struct-marshaling issue, not a permissions one)
and the resulting PATCH failed with `401 JWT could not be decoded`. Not
pursued further — reverse-engineering another app's stored OAuth token via
low-level Win32 struct debugging for a one-field toggle was judged past
the point of a reasonable automated attempt. **Needs a manual one-time
toggle**: Supabase Dashboard → `suuafglvrxrllnhipkiv` project →
Authentication → Sign In / Providers → enable "Allow anonymous sign-ins".
**Resolved 2026-08-21**: the toggle was turned on and device-verified.
Re-verified 2026-08-22 from this repo — `POST /auth/v1/signup` against dev
returns a real 3-part JWT with `is_anonymous: true`, `role: authenticated`.

**`flutter analyze`/`flutter test` unaffected throughout**: 59 issues / 22
passing, matching the pre-existing baseline at every checkpoint in this
work.

---

## 2026-08-17 (later same day) — Documentation residuals fixed; shopping list removed from the app

### Documentation residuals (Task 1)

- Added a line to `CLAUDE.md`'s Working conventions calling out the six
  Swiss-worded strings as deliberate, not a bug, pointing here for context.
- Rewrote the pricing parenthetical in `docs/DECISIONS.md`'s Monetization
  section (the only edit made to that section since it was moved verbatim
  — everything else in it is still untouched) so it reads unambiguously:
  pricing is deliberately deferred, the 15 CHF/month and ~135 CHF/year
  figures are placeholders in code, not decisions, and no price has been
  committed to.
- Reviewed the "Curriculum content strategy (decided 2026-08-10)" section
  (marked superseded earlier this same day) for any binding decision that
  wasn't specifically about video or photography. **Two survived**: (1)
  primary teaching emphasis stays on text + timing inside Cook Mode, the
  browsable Techniques & Media hub is supplementary; (2) no vector/animated
  diagrams for now (distinct from the new decision to build *static*
  SVG diagrams). Both moved to `docs/DECISIONS.md` under "Techniques &
  Media hub — content strategy." The rest of that section (real still
  photos, `externalVideoUrl`, the photo/video presence-handling
  requirement) really was only about video/photography and stays marked
  superseded, further below.

### Shopping list removed from Weekly Planner (Task 2)

The shopping list feature (cut per `docs/decisions_2026-08-17.md` item 3)
was removed from `lib/screens/weekly_planner_screen.dart`. **The
`shopping_list_items` table, its RLS policies, and its migration were left
untouched** — the table stays in place with any existing data intact; the
app simply no longer reads or writes it.

**Removed** (all shopping-list-only, confirmed via full-file usage trace
before deleting anything):
- `_upsertShoppingListItemsForMeal` and `_deleteShoppingListItemsNoLongerNeeded`
  — the two methods that wrote to `shopping_list_items`, plus all 6 call
  sites across `_optimisticallyAddMeal`, `_optimisticallyRemoveMeal`, and
  `_retrySlot`'s two retry branches (comments referencing the
  now-nonexistent "shopping-list sync"/"shopping-list cleanup" step were
  updated at the same time, not left dangling).
- `_showCombinedShoppingList` — built the combined/merged aisle map and
  opened the sheet.
- The AppBar shopping-cart icon button ("View combined shopping list") and
  the bottom-of-list "🛒 View Combined Shopping List" `FilledButton` — the
  feature's only two entry points.
- `_ShoppingListSheet` (the whole modal widget, `byAisle`/`hasAnyMeals`,
  including its "Back to planner" button).
- `_mergeAisleItems` — the same-name-ingredient-summing logic. Confirmed
  orphaned: its only caller was `_showCombinedShoppingList`; nothing else
  in the file merges `_AisleItem`s across meals.
- `_AisleExt` (the `_Aisle.label` extension, "Produce"/"Dairy"/"Meat"/
  "Pantry") — confirmed orphaned: its only caller was inside
  `_ShoppingListSheet`.
- `_AisleItem.amount` and `_AisleItem.unit` fields, and the corresponding
  `amount: ing.amount, unit: ing.unit` arguments in
  `_aisleItemsFromIngredients`. These existed solely to feed
  `_mergeAisleItems`'s same-unit summing math — confirmed via full-file
  grep that they were never read anywhere else, and confirmed the JSON
  round-trip to `user_meal_plans` (`_plannedMealToPlanRow`/
  `_plannedMealFromPlanRow`) never serialized them in the first place (only
  `aisle`/`item`/`qty` are persisted), so removing them changes no
  persisted-data shape and no other surface's behavior.
- Now-unused imports: `package:provider/provider.dart`,
  `package:optimeal/theme.dart`, and
  `package:optimeal/state/ingredient_prep_controller.dart` — each
  confirmed to have zero remaining references anywhere else in the file
  after the above removals (in `theme.dart`'s case, its only user was
  `AppSizing.primaryButtonHeight`, used exclusively by the two removed
  buttons).

**Kept — shared with something that is not the shopping list, per
instruction:**
- `_AisleItem` (now just `aisle`, `item`, `qty` — `amount`/`unit`
  removed), `_Aisle` (the 4-value enum: produce/dairy/meat/pantry),
  `_aisleItemsFromIngredients`, and `_inferAisle` — all still used to
  build the small ingredient-pill preview shown on each day's meal card
  (`meal!.aisleItems.take(4)`, `weekly_planner_screen.dart` around the
  `_MealSlotCard` build method) and to round-trip `_PlannedMeal.aisleItems`
  through `user_meal_plans` persistence (`_plannedMealToPlanRow`/
  `_plannedMealFromPlanRow`). Neither of those is the shopping list — the
  meal-card preview is a different, purely visual feature (what's in this
  planned meal), and the persistence layer is core to Weekly Planner
  working at all. Left in place.
- `IngredientPrepController` itself (the underlying state class in
  `lib/state/ingredient_prep_controller.dart`) — only its *import into this
  file* was removed as unused; the controller class is still live and
  shared with Cook Mode's ingredient checklist elsewhere in the app.
  Nothing about the controller itself was touched.

**Verification**: `flutter analyze` — 59 issues, down from the 61 baseline
(2 fewer `prefer_const_constructors` info-level suggestions that existed
on the now-deleted AppBar button and FilledButton went with them; no new
issues introduced). `flutter test` — 22/22 passing, unchanged (no test
ever covered the shopping list feature).

Also updated: `CLAUDE.md`'s "Ingredient data" bullet and its RLS table row
for `shopping_list_items`, both now described as "table retained, no live
UI surface" rather than "live feature, cut but not yet removed."

---

## 2026-08-17 — CLAUDE.md split into three documents; 17 August decision record applied

`CLAUDE.md` (187,787 characters) was split into `CLAUDE.md` (current state
only, target under 40,000 characters), `docs/DECISIONS.md` (binding
decisions and reasoning), and this file (completed work and session
history). The 17 August 2026 decision record
(`docs/decisions_2026-08-17.md`, copied into the repo from
`C:\Users\hkall\Desktop\optimeal_decisions_2026-08-17.md` — note its own
header: "Reconstructed from session notes after the chat transcript became
unavailable... Harris to verify each line against his own recollection")
was applied in the same pass.

### Cut (per `docs/decisions_2026-08-17.md`, item 3)

- **Shopping list** (Weekly Planner) — cut 2026-08-17. Reason on record:
  none stated beyond "needs removal" — the decision record doesn't capture
  why. Still live in the code as of this writing; the app itself has not
  been changed, only the roadmap/decision record. Full reasoning, if it
  matters later, needs to come from Harris.
- **Video / media content** — cut 2026-08-17. Reason: superseded by
  deterministic SVG diagrams (see `docs/DECISIONS.md`, "Visual assets").
  This also supersedes the entire "Curriculum content strategy" decision
  from 2026-08-10 (photos + optional external video link) — that section
  is preserved in full further below, marked superseded, not deleted.
- **Fridge tab** — cut 2026-08-17. Reason: replaced by a single local
  notification (see `docs/DECISIONS.md`, "Fridge tab replacement"). This
  was never a literally-built tab in the app — it refers to the "persistent
  Fridge entry point on Home" direction that had been floated (but not
  committed to) as the fix for Fridge Countdown's cold-start dead end (see
  Retention Features Backlog item 1 below).
- **Pasteurisation equivalence table** — dropped 2026-08-17. Reason: the
  interim flag-only rule ("flag a temperature below the instantaneous
  minimum with no hold time stated") becomes the permanent rule instead of
  building a full equivalence table. See `docs/DECISIONS.md`, "Pasteurisation
  rule."
- **Cut reference photo library** — cut 2026-08-17, specifically as a photo
  shoot. Reason: superseded by deterministic SVG diagrams, same as video
  content above.

### Completed (per `docs/decisions_2026-08-17.md`, items 1 and 2)

**Sensory cue vocabulary — DONE.** 26 entries drafted, reviewed and
re-voiced by Harris, signed. Schema gained two fields, both forced by
Harris's own handwritten entries: `phase` (separates *readiness* — is the
pan hot enough to receive food, fires before the timer starts — from
*doneness*, which fires when the timer ends; same vocabulary, opposite ends
of a step) and `if_overshot` ("you have gone too far," distinct from "not
ready yet" — overshooting is the more common beginner failure, so this
field may teach more than the other one). A `no_cue` escape value is
required, exactly like the explicit `none` in the cut vocabulary — without
it a thin list forces bad matches, and a wrong cue is worse than a missing
one. `juices_run_clear` is mandatory on poultry and pork steps; absence is
a validator flag regardless of stated time. Once cut and re-voiced, this
becomes a data file, not prompt text — adding a cue later is a content
edit, not a code change and not a prompt rewrite. Source documents:
`OptiMeal_Sensory_Cues_Draft.pdf` and `sensory Cue Vocabulary.pdf`, both in
the project files, signed copy included.

**Cooking times table — SIGNED.** Size scaling expressed as band shifts,
not multipliers: half thickness → down one band, double → up one band,
triple → up two bands. One-band compatibility tolerance confirmed.
Whole-muscle vs minced distinction confirmed as a real split in the table.
Open sub-question, not yet resolved: confirm with Harris whether anything
remains to be written by hand, or whether this is now fully closed (see
`docs/decisions_2026-08-17.md`'s "Vacation deliverables" list).

### Also closed in this pass (verification-driven, not part of the 17 August decision record)

- **Pluralization Audit** (originally its own top-level section) — verified
  2026-08-17 that all 4 flagged sites are already fixed in the running
  code: `home_dashboard_screen.dart:332` (`'$_weeklyIngredientsRescued
  ingredient${_weeklyIngredientsRescued == 1 ? '' : 's'} rescued so
  far.'`), `home_dashboard_screen.dart:470` (`'Lifetime: $lifetimeCount
  ingredient${lifetimeCount == 1 ? '' : 's'} rescued'`),
  `home_dashboard_screen.dart:432` (`'$weeklyCount ingredient${weeklyCount
  == 1 ? '' : 's'} rescued so far this week.'`), and
  `waste_ledger_celebration_sheet.dart:78` (`'Lifetime:
  $lifetimeIngredientsRescued ingredient${lifetimeIngredientsRescued == 1 ?
  '' : 's'} rescued'`). All four now use the exact `${count == 1 ? '' :
  's'}` pattern the original audit itself recommended. The full original
  audit (with its original, now-stale line numbers) is preserved below for
  reference. The 4 "latent risk" items it also flagged (constants that are
  currently ≥2 and would silently break if ever tuned to 1) were **not**
  independently re-verified — they're a different, still-real class of
  risk, not part of what was confirmed fixed.
- **Design Polish Backlog item 6** (the 18-site `backgroundColor` batch
  fix) — verified 2026-08-17 that every in-scope `AppBottomSheet.show` call
  site across all 9 affected files already has `backgroundColor:
  AppDesignTokens.surfaceCream` set. This work is done; the original
  section (preserved below) still frames it as outstanding — that framing
  is stale as of this verification. Item 4 in the same original section
  (`_sageBackground`) was checked too and is **not** stale — still open,
  moved to `CLAUDE.md`'s roadmap as instructed.
- **Duplicate "READ THIS FIRST" marker removed.** The two session-summary
  sections below both originally carried a "— READ THIS FIRST" heading
  marker. Per instruction, the marker is removed from both as they move
  here — CHANGELOG entries are historical by definition, so no section in
  this file carries that marker.
- **Recipes-table missing-grant fact deduplicated.** This fact previously
  appeared near-verbatim in four places in CLAUDE.md (Current architecture
  facts, Supabase RLS status, Roadmap item 16's audit table, and Roadmap
  item 20). It's now stated exactly once, in `CLAUDE.md`'s "Current
  architecture facts," and referenced (not restated) from `CLAUDE.md`'s
  "Save if you liked it" roadmap item. The original repeated instances are
  preserved as-is in the historical sections below, since they're part of
  the verbatim record of what was written at the time.

---

## Session summary — 2026-08-16

Device-testing session on a physical Pixel 7 Pro (previously untested — see
prior sessions' repeated "compiles clean, never clicked through" caveats on
several of these same features). Covers the cut-vocabulary/curriculum-
declared-key work (schema, prompt, and UI changes not previously recorded
anywhere in this file — this section is the first record of them), plus a
cost/model investigation triggered by Harris questioning an OpenAI charge.
No code changes in this closing pass itself — see the git log for the
session's actual commits.

### Shipped and verified on-device this session

- **Cut vocabulary renders in the UI.** `ingredientCutVocabulary` /
  `ingredientCutDefinitions` / `ingredientCutLabel` (`lib/models/recipe_model.dart`)
  back a tappable pill on each ingredient row in Cook Mode
  (`_IngredientChecklistRow`, `one_pan_cooking_roadmap_screen.dart`) that
  opens a plain-text definition sheet. Explicit `'none'` cut values are
  suppressed from rendering (no grey "none" pill) but retained in the parsed
  model and in storage — real structured data, just not shown when it
  carries no useful information.
- **Model-declared `curriculum_lesson_id` replaces keyword matching.** The
  model now names which curriculum drawer a recipe teaches directly
  (`_readDeclaredCurriculumLessonId`, `lib/services/chef_recipe_parser.dart`),
  validated against `ChefService.curriculumDrawerKeys` — an unrecognized or
  missing value is treated as no lesson at all, never guessed. **5/5 real
  on-device generations declared a valid key, zero rejections logged**, and
  `WhatYouLearnedSheet` fired correctly on every completed cook with `ids`
  matching the declared key exactly (`sauteing`, `sauteing`, `sauteing`,
  `deep_frying`, `roasting` across the session's 5 generations). Replaces
  the old approach of keyword-matching the recipe's own generated text,
  which had no way to tell a genuine technique match from an accidental one.
- **Waste Ledger rescue-eligibility gating (`CookModeSurface`, Roadmap item
  28) confirmed correct live** — not just by code trace, by real device
  behavior: Custom AI Recipe Creator cooks correctly skipped the ledger
  write 3/3 times (`surface=CookModeSurface.customAiRecipeCreator
  isReCook=false`), a Recently Cooked re-open correctly skipped it too
  (`surface=null isReCook=true`), and the one genuinely rescue-eligible
  Fridge Clearer cook proceeded without hitting a skip line.
- **Finish & Plate mid-cook skip-ahead (Roadmap item 28) confirmed
  reachable and safe on-device**: reachable from an active cook (not only
  once every step is checked), the confirmation sheet appears, and
  cancelling it returns cleanly to Cook Mode with nothing fired.
- **Chef Harris SOS is grounded**: during a live cook, SOS correctly
  answered about the actual current step and referenced the live timer —
  confirms the `recipeContext`/`conversationHistory` parameters on
  `ChefService.askChefHarris` are doing real work, not just present in the
  signature.
- **The cut-sequencing rule** (ingredients added in the same step must have
  comparable cook times, or be staggered/split — added to the recipe
  generation prompt this session) **held across every generation tested**
  this session — no observed same-step pairing of mismatched cook-time
  ingredients.

### Added this session, not yet exercised

- **Positive-path ledger success log** (`_logCookSessionCompletion`,
  `one_pan_cooking_roadmap_screen.dart`) — on a real `LedgerCompletionSuccess`,
  now `debugPrint`s the recipe title, the credited ingredients, and the
  ingredients present in the recipe but excluded by
  `LedgerService.freshProduceOnly` (computed as the diff, so the exclusion
  is visible directly in the log, not inferred from a low total). Not yet
  seen fire on a real successful write in a device session.
- **Rejection logging on `_readDeclaredCurriculumLessonId`** — three
  distinct `debugPrint` cases (field absent, present but not a string,
  present but not in `ChefService.curriculumDrawerKeys`), each naming the
  raw value and the recipe title. Not yet exercised because this session's
  5/5 generations all declared valid keys — the rejection paths themselves
  remain unobserved on a real device.
- **`minced` cut definition reworded** to drop named ingredients ("garlic
  and ginger") that read wrong when only one of them is actually in the
  recipe — now describes the cut itself only. Not yet visually re-confirmed
  on-device after the wording change (the pill/sheet mechanism itself was
  device-verified earlier in the session, before this specific wording fix).

### Still unverified on device

- **Post-cook sequence surviving a failed ledger write.** Roadmap item 27's
  design (a failed `waste_ledger_events` insert falls through rather than
  aborting What You Learned / Confidence Climb / the share card / navigation
  home) has not been exercised against a real failure — an airplane-mode
  test was planned but not performed this session. Still only verified by
  code trace, same caveat item 27 already carried.

### Findings recorded this session (investigation only, most led to no code change)

- **The deployed app has always called `gpt-4o`, never `gpt-4o-mini`.**
  `ChefService.askChefHarris` never sends a `model` field in its request
  payload, on any surface (Fridge Clearer, Custom AI Recipe Creator, home
  dashboard suggestion, SOS all share the one method) — the
  `ask-chef-harris` edge function hardcodes `resolvedModel` to default to
  `'gpt-4o'` whenever `model` is absent (`supabase/functions/ask-chef-harris/index.ts:110-111`).
  `gpt-4o-mini` is whitelisted and reachable in the code (left over from the
  2026-08-11 side-by-side trial, verdict: keep `gpt-4o` — see Roadmap item
  5) but nothing in the shipped app has ever actually requested it.
  Cost logging in `api_call_cost_log` uses the same `resolvedModel` value
  to pick rates as to make the call, so the rates always match the model
  genuinely invoked — verified against a real logged row
  (`prompt_tokens=6034, completion_tokens=636` → computed $0.02144, matching
  the logged `est_cost_usd` exactly). **This was a corrected assumption on
  Harris's part, not a code bug** — the logging is accurate.
- **Per-call cost rose from ~$0.0146 (2026-08-13's first real logged row) to
  ~$0.0226 (this session) because input tokens grew from ~3,344 to ~6,034**
  across this session's prompt additions (the cut vocabulary schema, the
  `ingredients_added`/sequencing rule, the `curriculum_lesson_id` field).
  Prompt growth is the cost driver, not a model change — ties directly into
  the payload-size instrumentation already in `ChefService.askChefHarris`
  (see Roadmap item 5's prompt-size measurement work).
- **The always-on system prompt is ~7,095 characters** (persona +
  curriculum core + difficulty rules, `chef_service.dart`'s `_systemPersona`
  + `_curriculumCore` + `_recipeDifficultyByKitchenConfidence`) **and is
  sent byte-identical on every call, including SOS** — already documented
  in Roadmap item 14 (prompt caching, investigated and closed 2026-08-15 as
  "real but small money on the table, not worth chasing further at current
  scale"). Recording again here because the revised break-even figure below
  changes the scale argument that closure rested on — worth Harris's own
  call on whether to revisit, not decided here.
- **Revised break-even: roughly 240 generations/month per subscriber**, down
  from the 400/month figure Harris had been tracking — driven by the same
  per-call cost increase above (higher real cost per call means fewer calls
  needed to justify a subscription). This is Harris's own tracked economics
  figure, not something previously recorded in this file.
- **The always-on system prompt contains four hardcoded food examples**,
  sent regardless of what's actually being cooked: the onion-caramelization
  witty-remark example (`_systemPersona`, "Don't rush the onions..."), the
  rice/risotto few-shot SOS reply ("That's rice that got impatient..."),
  the sautéed-onions few-shot step-bullet example, and the
  omelette/buttered-pasta reference in the Advanced/Confident difficulty
  rule (dishes to avoid defaulting to). **One of these — the rice/risotto
  example — surfaced inappropriately during a live SOS session about a
  mushroom/spinach/potato dish**, confirmed live, not just theorized. Not
  fixed this session — report only.
- **`LedgerService.freshProduceOnly` excluded potatoes from a Fridge
  Clearer cook of mushroom, spinach, and potatoes — confirmed live.** This
  is the existing, intentional `_pantryStapleKeywords` design
  (`lib/services/ledger_service.dart` — potato is explicitly listed under
  "Long-life alliums & roots," added deliberately in the 2026-08-06 session
  alongside onion/garlic/ginger). Not a coding defect — it's behaving
  exactly as designed — but Harris is now flagging the real live behavior
  (potatoes genuinely at risk of spoiling don't count as "rescued") as
  worth reconsidering as a product decision, not something to silently
  leave as settled. Not changed this session.

## Session summary — 2026-08-06

A long Claude Code session did a large batch of fixes, one architecture-debt
pass, one new feature, and a general bug-hunt. Below is organized by
**confidence**, since that matters more than a flat changelog: what's
actually been seen working, what was fixed in response to a live bug report
but not re-tested after the fix, and what was implemented but never clicked
through in the running app at all. **Don't assume anything in the second or
third category works until you've actually checked it.**

The post-cook "What You Learned" card feature and the Cook Mode Finish &
Plate bottom-bar states (both described in older versions of this doc as
"actively in progress") are now built, and the two bugs that were blocking
them are fixed and confirmed (see below) — that whole feature area is done,
not in-progress.

### Confirmed working (live-tested this session, or backed by real runtime logs)

- **Onboarding flow end-to-end**, including the new `mounted` guards added
  around its async profile-save/navigation — confirmed via real console logs
  showing multiple successful completions ("Onboarding complete", "Supabase
  upsert success").
- **The curriculum-drawer matching → `WhatYouLearnedSheet` data pipeline** —
  confirmed via real console logs from an actual cook session: a
  braised-chicken-and-cabbage recipe correctly matched `[stir_frying,
  sauteing, pan_searing]` and the sheet resolved 3 lessons. The *data* side
  of this feature works; see below for the rendering bug that was on top of
  it (now fixed).
- **Recipe difficulty now actually reaches the AI.** `chef_service.dart` had
  a fully-written "match recipe difficulty to kitchen confidence" constraint
  (`_recipeDifficultyByKitchenConfidence`) that was never included in the
  `systemPrompt` payload — the user-message told the AI to follow rules that
  didn't exist in what it actually received. Fixed by appending it to the
  system prompt. This is a live AI-behavior change; worth confirming
  generated recipes for "Beginner" vs. "Advanced" kitchen confidence actually
  read as different complexity now.

### Fixed in response to a live bug report — NOT yet re-confirmed after the fix

- **"Yellow line" overflow on `WhatYouLearnedSheet`.** No `SingleChildScrollView`
  wrapping its content — with 2 expandable technique cards, content taller
  than the modal's available space had nowhere to go, triggering Flutter's
  overflow warning stripes. Fixed by wrapping in `SingleChildScrollView`.
- **Resume Cooking banner surviving a finished cook session.**
  `_persistActiveSession()` re-saves progress on every app-lifecycle pause
  (tab switch, backgrounding) as long as cooking had started — and that flag
  is deliberately never cleared after finishing (it's what keeps the Finish
  & Plate UI showing). So finishing correctly cleared the saved session, but
  the next tab-switch silently wrote it right back. Fixed by guarding
  `_persistActiveSession()` with the existing `_ledgerSessionLogged` flag.
- **Start Cooking required scrolling to find.** It was only in
  `_StartCookingCard`, buried below the ingredients checklist. Added it to
  the persistent bottom bar (`_StartCookingBottomBar`) next to SOS, matching
  the pattern already used for Finish & Plate. (The original in-body card
  was left in place too — redundant but harmless.)
- **Onion/garlic counted as "rescued" in Waste Ledger messaging.**
  `LedgerService._pantryStapleKeywords` already existed to exclude long-life
  staples (oil, salt, rice, etc.) from "Nice rescue!" messaging, but didn't
  include onion/garlic/ginger/potato/shallot, which last weeks. Added them,
  with a guard so spring/green onions (genuinely perishable) still count.
- **What You Learned's expanded text was one dense unformatted paragraph.**
  Extracted the parsing/rendering into `lib/widgets/curriculum_drawer_content.dart`
  (shared with the new Technique of the Week feature, see below) — the
  expanded view now renders as labeled bullet sections with
  temperatures/durations bolded inline, parsed from the existing
  `LABEL: sentence. sentence.` drawer format (source text itself untouched,
  since it also feeds the AI prompt).
- **"Got it" button on `WhatYouLearnedSheet` used the wrong brand color**
  (`deepForest` — every other primary button in the app, including the
  sibling "Nice!" button on the Waste Ledger sheet, uses `ctaTerracotta`).
  Fixed to match.

### Implemented this session — compiles clean, but never clicked through in the running app

**Status re-checked 2026-08-11, directly against current source (not
assumed from this doc)** — see the "Status check" list further down for
the full verification, but the short version: ingredient-schema and
Technique of the Week are both still exactly as described below (real,
correct code, still never live-tested end-to-end). Cook Mode step
auto-scroll (further down in this doc, under its own heading) is
**definitively fixed**, resolving the old open contradiction — see that
section for the full trace.

- **Ingredient-schema architecture debt** (was roadmap item 3):
  - Fixed the Cook Mode ingredient checklist keying "prepped" state by the
    *live-rescaled display string* instead of the ingredient's stable name —
    checking an item off, then changing portions, silently un-checked it.
    Also means Cook Mode's checked-state should now actually sync with
    Weekly Planner's shopping-list checkmarks (both key by name now; they
    never matched before since one used a quantity-embedded string).
  - **The big one**: Weekly Planner's Supabase persistence
    (`_cookModePayloadToJson`/`_cookModePayloadFromJson`) only wrote
    `{title, ingredients, kitchen_gear, steps}` — dropping
    `structuredIngredients`/`basePortions`/`description`/`curriculumLessonIds`
    on every save. Any planned meal, from any source, became permanently
    unscalable the moment it was saved and reloaded. Now round-trips fully.
  - Weekly Planner's 3rd "Add meal" fast path (Discount/Deal Meal) never
    asked the AI for structured ingredients at all (prompt only requested
    plain strings) — portion scaling was structurally impossible there, not
    just failure-prone. Prompt + parser now match the other two fast paths.
  - Deleted dead `Recipe`/`RecipeStep`/`.scaledTo()` from `recipe_model.dart`
    (fully unused, would've been a second competing "recipe" concept
    alongside the live `CookModeRecipePayload`/`RecipeIngredient` pattern).
    `RecipeIngredient` itself is very much alive and used throughout.
  - Weekly Planner's shopping list now merges/sums same-named ingredients
    across meals (real qty+unit math where units match, readable combined
    fragments otherwise) instead of listing duplicates.
- **"Technique of the Week" home card** (was roadmap item 4): a compact card
  below the 6-action grid (deliberately not above it — didn't want to undo
  the scroll-fit work, see below) that rotates weekly through all 23
  technique/reference drawer keys (deterministic by ISO week number, no
  stored state) and opens the shared drawer-content sheet on tap.
- **Recipe generation speed** (was roadmap item 5 — this parallelization fix
  is done and confirmed live-tested, but the item itself was reopened
  2026-08-10 with further findings/next steps — see Roadmap item 5 below,
  don't treat this as fully closed): in Fridge Clearer,
  `getPrecisionData` and `askChefHarris` were fully sequential despite being
  completely independent (the recipe prompt never depends on the precision
  result) — now run concurrently. Also capped reference-drawer prompt
  injection at 3 matches in `_buildCurriculumAddendum` (it already capped
  technique matches at 3 but the reference-drawer loop right next to it had
  no cap at all — worst case, one message could inject all 7 reference
  drawers). No edge function changes — still a generic proxy, no caching
  added (would be a separate, bigger piece of work).
- **Home dashboard layout tightening** (small-screen scroll fit): reduced
  `childAspectRatio` 0.78→0.95 plus header/grid/card padding. By the numbers,
  Pixel 7 (412×915) should now fit the header + 6-card grid + bottom nav with
  no scrolling; iPhone SE (375×667) is meaningfully closer but likely still
  needs a little scroll — closing that fully would mean cutting visible
  content (e.g. the diet/allergy chip row), not just tightening spacing, so
  it wasn't done without checking in first. **Not verified against real
  devices**, only worked out from the actual layout code's exact values —
  no browser automation was available this session to check visually.
- **General bug-hunt findings**, beyond the items above:
  - Deleted `lib/screens/dashboard_screen.dart` (`DashboardScreen`) — a
    fully-built duplicate of the home grid, never routed to anywhere.
  - Deleted `lib/screens/checklist_screen.dart` (`ChecklistScreen`) — a
    standalone checklist with fake local-only XP that reset every mount,
    superseded by the real Weekly Planner checklist, never routed to.
  - Deleted `UserProfileController.completeOnboarding()` — never called
    anywhere (onboarding builds its own profile update inline instead).
  - `UserProfileService.save()` caught all exceptions and returned
    normally either way, so if a `SharedPreferences` write ever failed, the
    Profile screen's explicit "Save" button still showed "Profile saved!".
    `save()`/`updateProfile()` now return whether the write actually
    succeeded, and Profile's Save button shows a real error on failure.
    (Left onboarding's own profile-save alone — it has a deliberate,
    already-commented "non-fatal, must still complete onboarding" design.)
  - The paywall-unreachable bug — see "Current architecture facts" above.
  - Checked and found NOT a live issue: `shopping_list_items` Supabase table
    drops `qty` on write (true, but nothing ever reads that column back —
    only `ingredient_name` is ever selected — so it has zero observable
    effect; not worth the churn to fix). The "secure account" confirmation
    UX flagged as possibly-flaky around Supabase's email-confirmation
    setting — but this doc already documents that exact flow as tested
    end-to-end and confirmed working, so trusted that over a code-only guess.

### Cook Mode step auto-scroll — RESOLVED 2026-08-11: definitively fixed, not a bug

The older version of this doc listed this as "not yet started" while later
noting the source looked already wired — an open, unresolved contradiction.
**Resolved 2026-08-11 via a full code trace, not a guess**: both trigger
paths funnel through `_advanceToNextStep()`
(`one_pan_cooking_roadmap_screen.dart`) — the timer-driven auto-advance
(`_onActiveTimerDone` → `_advanceToNextStep`) and the manual "Next Step"
button (`onNextPressed` → `_toggleStepComplete` → `_advanceToNextStep`,
when the active step is the one being marked done). `_advanceToNextStep()`
always calls `_scrollToActiveStep()` via `_postFrame`, which resolves
`_stepKeys[idx].currentContext` and calls `Scrollable.ensureVisible(...)`.
Confirmed each `_stepKeys[i]` is genuinely attached as the `key:` of its
`_CookStepCard`, inside an **eagerly-built** `SliverChildListDelegate.fixed`
(not lazy — so the context always exists once the screen is up), inside a
real `CustomScrollView`. No gaps anywhere in the chain — this is not a bug.
Not separately visually re-confirmed in a running browser (no browser
automation available this session either), but the mechanism is structurally
complete and uses a standard, reliable Flutter API — high confidence.

### What next session should verify first, in order

1. Re-test the two fixed live-reported bugs: yellow-line overflow on What
   You Learned, and the Resume Cooking banner clearing correctly after a
   finished + backgrounded session.
2. Re-test the 4 UX polish items (Start Cooking button reachability,
   onion/garlic no longer in rescue messaging, What You Learned's new
   bulleted formatting, Got it button color).
3. Confirm the paywall is now actually reachable via onboarding's Skip
   button (this was a real, previously-silent gap in the live paywall).
4. Cook a full recipe through Weekly Planner (any of the 3 "Add meal" fast
   paths), save the day's plan, reload the app, and confirm the portion
   stepper still works on that planned meal (this is the persistence fix —
   never actually clicked through, only verified by reading the round-trip
   code both directions).
5. Check the combined shopping list with 2+ meals sharing an ingredient and
   confirm it shows one merged line, not duplicates.
6. Decide on Cook Mode step auto-scroll (see above).
7. Home dashboard scroll fit on a real small phone if possible (SE-class
   screen) — decide whether the current "close but not quite zero-scroll"
   result is acceptable or worth cutting content for.

## Roadmap history — full original text (pre-2026-08-17)

Open items were extracted into `CLAUDE.md`'s roadmap in condensed form; a few items (marked DECISION-flavored) were extracted into `docs/DECISIONS.md` instead. Everything below is the unedited original, item numbers as originally written.

1. ~~Confirm What You Learned + Finish & Plate fixes~~ — done, see session
   summary above (bugs found along the way are fixed, pending re-test)
2. Cook Mode step auto-scroll — status unclear, see above, needs a decision
3. ~~Architecture debt: ingredient-schema inconsistency + dead
   `ai-recipe-voice` call~~ — done, see session summary above
4. ~~"Technique of the Week" rotating home card~~ — done, see session
   summary above
5. Recipe generation speed — **step (1) shipped 2026-08-11, verdict:
   `max_tokens` alone is NOT the bottleneck — move to step (2) next
   session.** Added `max_tokens: 1200` to the `ask-chef-harris` OpenAI call
   in `supabase/functions/ask-chef-harris/index.ts` (now the single
   source — see path note near the top of this doc), deployed via
   `supabase functions deploy ask-chef-harris --project-ref
   xwugnhzlnfgmczkbbcbh --use-api` — confirmed live via `supabase functions
   list` showing `version: 2` and a matching `updated_at`. Harris then ran
   two real generations in the live app (Chrome DevTools): 16.54s and
   5.92s — too noisy on n=2 to call. **Followed up same session with a
   proper read**: a standalone Node script
   (`time_ask_chef_harris.mjs`, scratchpad — not committed, reproducible
   from the payload shape documented here if needed again) fired 5
   sequential calls directly at the deployed edge function, replicating
   `ChefService.askChefHarris`'s real payload (`_systemPersona` +
   `_curriculumCore` + `_recipeDifficultyByKitchenConfidence` as
   `systemPrompt`, `forceJsonObject: true`, `temperature: 0.25`) with 5
   different dishes but matched-complexity prompts (5 ingredients each,
   same schema block, same portions/time/cookware) so results were
   comparable rather than apples-to-oranges. Result: **7.11s average,
   5.72–9.86s spread, stddev 1.46s** (5/5 succeeded). Modestly below the
   single 9.4s baseline sample, but the decisive finding is that actual
   completions were **1840–2254 chars (~460–565 tokens) — well under the
   1200-token cap**. The cap never actually engages for a typical
   generation, so it structurally cannot explain the faster (or slower)
   runs; the 5.7–9.9s spread is pure OpenAI response-time variance. Per
   the plan agreed with Harris going in: this counts as inconclusive/
   "doesn't move the needle," so **stop tuning `max_tokens` further** —
   it's still a reasonable safety cap against a runaway worst-case
   completion, just not a lever for the typical-case latency Harris is
   actually feeling. Also explicitly re-checked the "is it still running
   sequentially" alternate hypothesis Harris raised: read
   `fridge_clearer_screen.dart` lines 547–559 directly — `precisionCardsFuture`
   and `replyFuture` are both still fired before either is awaited, so the
   2026-08-06 concurrency fix is intact, not regressed; not the
   bottleneck. **Next session: move straight to step (2), the
   `gpt-4o-mini` trial** — compare real outputs side-by-side against
   `gpt-4o` for voice/quality before committing, per the original plan.
   The 2026-08-06 fix
   (parallelized `getPrecisionData`/`askChefHarris`, capped prompt
   injection) is real and confirmed live-tested (~9.4s / ~4.7s running
   concurrently, not sequentially — see monetization section's live-test
   note above), but Harris reported it still doesn't *feel* faster, which
   is expected — that fix reduced wall time from sequential (~14s) to
   concurrent (~9.4s, bounded by the slower call), not down to something
   snappy. Investigated further this session, found:
   - `ask-chef-harris` edge function source is in-repo at
     `supabase/functions/ask-chef-harris/index.ts` (worth knowing — unlike
     most edge functions, this one *is* checked in, not just
     Dashboard-only). It calls OpenAI `gpt-4o`, **no `max_tokens` cap, no
     caching, not streamed** — a single blocking request/response. This is
     the actual critical-path call (always the slower of the two, so it's
     the only one worth optimizing — speeding up `ai-recipe-precision`
     alone wouldn't move total wait time since they run concurrently).
   - `ai-recipe-precision`'s edge function source is **not** in this repo
     (only `ask-chef-harris`'s is) — couldn't inspect its model/config
     directly.
   - The `ai_precision_cache` table (see RLS section above) is **confirmed
     actually in use**, not dead: 38 real rows via `supabase db query
     --linked`, most recent from earlier today (2026-08-10). So
     `ai-recipe-precision` already gets real caching benefit on repeat
     ingredient combos — this is a second, independent confirmation that
     `supabase db query --linked "<SQL>"` works for read-only checks
     against the live project without needing Docker/local Postgres.
   - Recommended next steps, in order: (1) ~~cap `max_tokens` on the
     `ask-chef-harris` OpenAI call~~ — **done 2026-08-11, see above**; (2)
     ~~trial swapping `gpt-4o` → `gpt-4o-mini`~~ — **done 2026-08-11,
     verdict: keep `gpt-4o`, see below**; (3) still NOT a quick
     win, re-investigated 2026-08-11: streaming `ask-chef-harris`.
     **Revised understanding** — the transport layer is more feasible than
     first thought: `functions_client` (the package behind
     `Supabase.instance.client.functions.invoke`) has real built-in SSE
     support (confirmed by reading its actual source,
     `functions_client-2.6.4/lib/src/functions_client.dart` — a
     `text/event-stream` response hands back the raw byte stream directly
     instead of buffering it). **But three other genuine sub-problems
     remain, one of which is out of scope for a quick change**: (a) the
     edge function needs to call OpenAI with `stream: true` and forward
     the SSE stream through Deno — tractable; (b) the package's own doc
     comment is explicit that true incremental delivery **on web**
     requires adding the `fetch_client` package and reconfiguring
     `Supabase.initialize(...)` to use it as the **global** HTTP client —
     since this app is currently only tested via `flutter run -d chrome`
     (no Mac/Android device connected on this machine, per Roadmap item
     8), that's a real blast-radius change touching every Supabase call
     (auth, postgrest, storage, realtime), not a local tweak; (c) still
     unchanged from the original note — `forceJsonObject: true` means
     OpenAI streams raw JSON text token-by-token, not structured deltas,
     so progressively rendering "title first, then steps" needs either a
     tolerant partial-JSON parser or a redesigned line-delimited output
     schema (which would itself need output-format quality testing,
     losing the "zero quality risk" framing), plus the recipe screen
     currently parses one complete JSON string at the end and would need
     real UI work to render partial state. Verdict unchanged: worth doing
     as a real, dedicated future feature — not something to half-build
     inside this latency investigation.
   - **`gpt-4o` vs `gpt-4o-mini` side-by-side trial, done 2026-08-11 —
     verdict: keep `gpt-4o`.** Whitelisted an optional `model` field on
     `ask-chef-harris` (`supabase/functions/ask-chef-harris/index.ts`,
     restricted to `['gpt-4o', 'gpt-4o-mini']` so a caller can never point
     the proxy at an arbitrary model string; defaults to `gpt-4o` when
     omitted, so this is backward-compatible and left in place — harmless,
     useful for any future re-test) and deployed it (now `version: 3`).
     Ran the same 3 comparable dishes through both models via a standalone
     script and built a side-by-side comparison page:
     https://claude.ai/code/artifact/1bfc279f-a030-4921-b6de-6b769709b4b8
     (private artifact — full recipes, timings, and the recommendation
     below). **Speed**: `gpt-4o-mini` averaged 7.55s vs `gpt-4o`'s 8.25s on
     this 3-run sample — about 0.7s faster, smaller than the ±1.5s
     run-to-run noise already established for `gpt-4o` alone, i.e. not a
     clear win. **Quality**: consistent, real voice cost across all 3
     dishes — `gpt-4o-mini`'s recipe descriptions lean generic ("deliciously
     simple!", "in no time!") where `gpt-4o` reaches for something specific
     to the dish ("thyme makes it timeless"); steps are also a shade less
     technically precise (e.g. `gpt-4o` gives "skin-side down, 4 min, then
     flip," `gpt-4o-mini` gives the same step as a looser "sauté until
     browned (~5 min)"). One `gpt-4o-mini` run also had a minor
     schema-consistency slip (a step said "season with salt and pepper"
     but neither was in that run's ingredients list). Given Chef Harris's
     voice/personality is core to the app's identity, not just flavor
     text, a ~0.7s gain isn't worth trading it away — **not switching the
     default.** Move to step (3) (streaming) only as a real future
     project, not urgently — see above.
   - `supabase functions deploy <name>` **confirmed working 2026-08-11**
     with the now-linked CLI — see "Correction 2026-08-10" note near the
     top of this doc for the exact command and the required `--use-api`
     flag.
   - **`ai-recipe-precision` timed the same way, 2026-08-11**: 5-run
     average **3.32s** (2.44–4.17s spread, stddev 0.70s), clearly faster
     than `ask-chef-harris`'s 7.11s average. Since the two run concurrently
     (confirmed intact, see above), the user's actual floor is set by
     `ask-chef-harris` — `ai-recipe-precision` is not worth optimizing
     further right now; it's already well under the other call's time.
   - **Prompt input size measured directly, 2026-08-11**, via a standalone
     script (`tool/measure_prompt_size.dart`, deleted after use — imported
     the real `chefTechniqueDrawers`/`chefReferenceDrawers`/etc. maps and
     ran an exact copy of `_buildCurriculumAddendum`'s matching logic
     against 7 realistic Fridge Clearer-style prompts). Findings: the
     fixed system prompt (persona + curriculum core + difficulty rules) is
     **7095 chars (~1774 tokens)** on its own — a substantial baseline
     even before any per-call addition. The curriculum addendum (injected
     into the **user** message, not the system prompt — worth correcting
     that assumption for next time) added another 0–2009 chars (~0–500
     tokens) depending on genuine keyword matches. Combined input landed
     around **7900–9900 chars (~2000–2500 tokens)** — real, but not large
     enough on its own to be the dominant driver of the 5.7–9.9s
     *completion*-inclusive latency measured earlier (prompt/input
     processing is materially faster than output decode for GPT-4o-class
     models; the output side is still the bigger lever).
   - **Real bug found and fixed along the way, 2026-08-11**: the
     `central_european` cuisine-profile match in `_buildCurriculumAddendum`
     triggered on the bare word `'swiss'` — but `FridgeClearerScreen._buildCookModePrompt`
     always includes the literal boilerplate phrase "Context (Swiss home
     kitchen):" (correct, since this is a Swiss-first app), so that cuisine
     block was being injected into **every single Fridge Clearer call**
     regardless of what was actually being cooked — not genuine relevance
     matching, just an accidental self-match on the app's own boilerplate.
     Confirmed via the measurement script: 3 of 7 test prompts matched
     nothing else and still got a 1021-char addendum purely from this.
     Fixed in `chef_service.dart`'s `cuisineAliases` map: replaced the bare
     `'swiss'` trigger with more specific phrases (`'swiss cuisine'`,
     `'swiss dish'`, `'swiss recipe'`, `'swiss classic'`) so genuine "make
     this taste Swiss" intent still matches without the unconditional tax.
     Re-ran the measurement script after the fix — the 3 previously-affected
     prompts now correctly show 0-char addenda. This was also a mild
     quality/correctness issue independent of latency: every recipe
     (including e.g. an Asian stir-fry request) was getting a central-
     European cuisine profile block injected into its prompt for no reason.
   - **Added permanent lightweight instrumentation**: `ChefService.askChefHarris`
     now `debugPrint`s the real `systemPrompt`/`userMessage` char counts (and
     an estimated token count) right before every real call, so future
     prompt-bloat regressions are visible in the console without needing a
     one-off measurement script again.
   - **Perceived-latency UI improvement, 2026-08-11 (small, parallel task,
     not blocking the investigation above)**: `_InlineGeneratingCard` in
     `fridge_clearer_screen.dart` (the loading card shown during Fridge
     Clearer generation) was a static "Chef Harris is thinking…" line with
     a spinner. Converted to a `StatefulWidget` that rotates through 4
     status messages ("Checking your ingredients…" → "Thinking through
     techniques…" → "Balancing the flavors…" → "Plating the details…")
     every ~2.2s via a `Timer.periodic` + `AnimatedSwitcher` crossfade.
     Doesn't change actual latency — improves how the existing ~7-10s wait
     *feels*. Only wired into Fridge Clearer so far (the flagship AI-
     generation flow this whole investigation centers on) — the same
     pattern could be reused for the other `askChefHarris` call sites
     (Custom AI Recipe Creator, Weekly Planner, home dashboard Chef
     Suggestion, Cook Mode SOS) if it reads well here first; deliberately
     kept local to this file rather than extracted into a shared widget
     until there's a second real call site for it.
6. Real payment provider integration (RevenueCat, confirmed 2026-08-10) —
   tier structure, pricing logic, and the full gating stack are now built
   end-to-end against mock/sandbox entitlement state (same session) — see
   "Monetization / paywall tier structure" above for the full spec and
   build status. Real Apple Developer + Play Console + RevenueCat account
   setup is **deliberately deferred by Harris's own choice**, not blocked —
   revisit once he's actually approaching real-tester distribution and has
   resolved the OptiMeal-vs-Empyria trademark question. Until then: (a) the
   `api_usage_daily` migration still needs manual application to the live
   Supabase project, (b) none of the gating/mock-purchase flow has been
   live-tested in a running app yet. The route-to-paywall bug is fixed.
7. **Post-cook shareable recap card** (added 2026-08-10) — a growth/
   acquisition feature, not just retention: after a cook session completes
   (same moment as the Waste Ledger celebration sheet + What You Learned
   sheet), offer a lightweight, visually clean, screenshot-worthy card
   summarizing that session ("I rescued 4 ingredients and learned to
   braise") with a native share-sheet action, styled to look good posted as
   a share/story rather than just an in-app confirmation. Reuses data
   already available at that point — ingredients rescued from
   `LedgerService.logCompletion`'s per-session result, technique(s) learned
   from the same curriculum-matching pipeline that already feeds
   `WhatYouLearnedSheet` — no new data capture needed, so this is low
   effort. Natural extension of "Rescue Streaks You Can't See Until You
   Look" in the Retention Features Backlog below — keep them visually and
   conceptually consistent when that item gets built. Slotted in roughly
   alongside/just after the payment-provider scaffolding work (item 6
   above), not blocked by it.
8. Apple/Google OAuth account linking (needs native iOS/Android config —
   also likely blocked on this being a Windows dev machine with no Mac for
   iOS and no Android device/emulator currently connected; check `flutter
   devices` before assuming either platform is testable here)
9. Deep link fix for the email-confirmation redirect (see Auth section
   above) — same native-platform-config caveat as #8
10. Lower priority / not urgent: rate limiting on Edge Functions, separate dev
    vs. production Supabase projects before real testers, privacy policy
    covering Swiss FADP + EU GDPR, Supabase Storage bucket policies (once
    profile photos/recipe images are added), duplicate RLS policy cleanup
    (cosmetic, see RLS section above). **Also pre-launch, added 2026-08-13**:
    `ChefService.askChefHarris` (`lib/services/chef_service.dart`) catches
    its own network/request errors internally and returns a friendly
    fallback string rather than throwing — good UX, but it means
    `UsageCapService.increment(...)` at all four call sites still fires even
    on the rare call that fails before ever reaching OpenAI (Supabase
    Functions invoke itself failing, e.g. a network blip), since the
    increment happens unconditionally right as the call is fired, not
    contingent on it actually succeeding. Harmless today — Harris is the
    only user, so a failed call burning his own quota is a non-issue. Once
    caps gate paying subscribers (Roadmap item 6), it becomes a real
    problem: a failed call would burn a paying user's quota for nothing.
    Same class of "does the counter accurately reflect real cost/value
    delivered" question as the cache-hit-inflation check done the same
    session (that one came back clean — see item 11 follow-up above; this
    one hasn't been fixed, just flagged). Fix shape, not yet designed in
    detail: distinguish "the edge function was reached and OpenAI was
    actually called" from "the client got a usable response," and only
    increment on the former — needs `askChefHarris` to expose that
    distinction to callers first, which it currently doesn't.
11. **OpenAI cost visibility and investigation — BUILT + investigated
    2026-08-13** (Harris reported inconsistent OpenAI charges while testing,
    most recently 0.11 CHF for one session, sometimes charged per session
    and sometimes not). Confirmed current `gpt-4o` pricing before building
    anything: $2.50/1M input tokens, $10.00/1M output (gpt-4o-mini:
    $0.15/$0.60) — same rates already in use for the 2026-08-11
    `gpt-4o`-vs-`gpt-4o-mini` trial, still current.
    - **`ask-chef-harris` edge function** (`supabase/functions/ask-chef-harris/index.ts`)
      now captures OpenAI's real `usage` field (`prompt_tokens`/
      `completion_tokens` — actual counts, not an estimate) from every
      response: logs `model`/tokens/`est_cost_usd` server-side via
      `console.log` (visible in Dashboard → Edge Functions → Logs, no CLI
      `logs` subcommand exists to pull this from the terminal — checked,
      `supabase functions --help` lists no `logs` subcommand) and now also
      returns `usage`+`model` in the JSON response body (additive — existing
      `content` field unchanged, nothing else depends on the response shape
      changing). **Deployed** via `supabase functions deploy ask-chef-harris
      --project-ref xwugnhzlnfgmczkbbcbh --use-api` — confirmed live via
      `supabase functions list` showing `version: 4` (was 3) with a matching
      `updated_at`.
    - **`ChefService.askChefHarris`** (`lib/services/chef_service.dart`) now
      reads that real `usage`/`model` back and logs an accurate per-call
      cost (`_logEstimatedCost`), replacing the old input-only char/4
      estimate — falls back to that old estimate (clearly labeled
      "INPUT ONLY, char-count estimate") only if a caller somehow still hits
      a pre-deploy cached function version.
    - **`ai-recipe-precision` cache hit/miss — now distinguishable, and
      confirmed genuinely working.** `AiRecipeService.getPrecisionData`
      (`lib/services/ai_recipe_service.dart`) already received a `source`
      field ('cache'/'generated') from the edge function but never logged
      it — now logs `CACHE HIT — no new OpenAI call, ~$0 marginal cost` vs
      `CACHE MISS (generated)` explicitly. (Can't get real token counts here
      the way `ask-chef-harris` now does — `ai-recipe-precision`'s edge
      function source isn't in this repo, see Roadmap item 5 — so the
      cache-miss case still only logs a rough char-count estimate of the
      request payload, clearly labeled as such.) **Verified against real
      live data** via `supabase db query --linked`: `ai_precision_cache` has
      47 rows total, 12 of them reused at least once, 14 total cache hits
      (sum of `hit_count`) — caching is real and working, saving roughly a
      fifth of what would otherwise be new OpenAI calls, not dead/decorative.
    - **Grants-bug cross-reference — checked, verdict: could NOT have caused
      missing OpenAI charges.** Traced the actual code path first rather
      than assuming: every usage-cap check (`UsageCapService.getUsageCount`
      and its `getTodayCount`/`getRollingWeekCount`/`getLifetimeCount`
      wrappers) fails open by returning `0` on any error — and all three
      gate call sites (`fridge_clearer_screen.dart`,
      `custom_ai_recipe_creator_sheet.dart`, `home_dashboard_screen.dart`)
      only skip the AI call when the *cap is exceeded*, never when the
      *check itself* errors. So even during the confirmed 2026-08-10 window
      when `increment_api_usage`/`api_usage_daily` were 403ing (grants bug,
      see monetization section), the fail-open design meant those 403s could
      only ever cause **undercounted usage tracking**, never a **blocked AI
      call** — the real `ask-chef-harris`/`ai-recipe-precision` calls (and
      their real OpenAI cost) would have fired regardless. Confirmed this
      empirically too, not just by code trace: queried the live
      `api_usage_daily` table — it has real rows for 2026-08-11 (post-fix)
      but **zero rows for 2026-08-10** (the day the 403s were live), which
      is exactly the fail-open signature (tracking silently didn't happen
      that day, calls still did). **So the grants bug is ruled out as the
      explanation for inconsistent charges.** More likely explanations,
      not yet confirmed: (a) not every test "session" actually triggers an
      AI call at all (Cook Mode, Waste Ledger, and browsing are all free and
      AI-free by design — see tier structure above); (b) OpenAI's own
      billing-dashboard display can lag actual usage; (c) genuine token-count
      variance between sessions (a longer conversation/recipe naturally
      costs more) is expected, not a bug. The new per-call cost logging
      above is the tool to actually pin this down next — watch the console
      during a real test session and compare against what shows up on the
      OpenAI billing page afterward.
    - **Follow-up, same day (2026-08-13): the debug-mode bypass (item 12)
      turned out to silently break usage tracking entirely.** Harris caught
      this live: ran 5 real Fridge Clearer generations, `api_usage_daily`
      showed nothing for that day. Root cause, confirmed by tracing before
      changing anything: all four `UsageCapService.instance.increment(...)`
      call sites were wrapped in `if (!isPro) { increment(...) }`, and
      item 12's bypass makes `isPro()` always `true` in debug builds — so
      the block never opened, in every debug session since item 12 shipped.
      **Fixed**: un-nested `increment(...)` from `if (!isPro)` at all four
      sites (`fridge_clearer_screen.dart`, `home_dashboard_screen.dart`,
      `custom_ai_recipe_creator_sheet.dart`, `fridge_countdown_sheet.dart`)
      — tracking now fires unconditionally; only the cap *check* (whether to
      block/show an upgrade prompt) stays gated on `isPro`. Confirmed live
      after the fix: `api_usage_daily.fridge_clearer_generation` = 6 for
      2026-08-13 after 6 real generations.
    - **Cache-hit-inflates-counter — checked, ruled out.** Grepped
      `ai_recipe_service.dart` (owns the cached `ai-recipe-precision` path):
      zero references to `UsageCapService` anywhere in it. The
      `fridgeClearerGeneration` increment lives only in
      `fridge_clearer_screen.dart`, tied to the `askChefHarris` call, which
      is never cached — so the counter reflects one real attempted OpenAI
      call per generation regardless of whether the separate, parallel
      precision-data call was a cache hit or miss. Not overstating spend.
      (Narrower, related gap flagged but not fixed: `askChefHarris` catches
      its own network errors internally and returns a fallback string
      instead of throwing, so the increment still fires even in the rare
      case where the Supabase Functions invoke itself fails before ever
      reaching OpenAI. See the new pre-launch item below.)
    - **Durable per-call cost history — BUILT 2026-08-13 (Option A of three
      considered).** Neither the edge function's `console.log` nor
      `ChefService`'s `debugPrint` survive past their ephemeral log/console
      — `api_usage_daily` only ever stored a count, no cost. Considered
      writing the durable record from the client instead (rejected: would
      inherit the exact "client-side state silently breaks tracking" failure
      class this whole investigation started from) or extending
      `api_usage_daily` with aggregate cost columns (rejected: only daily
      totals, no per-call detail, same client-write-gap risk if the
      increment stayed client-triggered). Went with a dedicated table
      written server-side instead, fully decoupled from client entitlement/
      debug logic:
      - **`api_call_cost_log`** (migration
        `20260813120000_create_api_call_cost_log.sql`): `user_id,
        function_name, model, prompt_tokens, completion_tokens,
        input_rate_per_million, output_rate_per_million, cost_usd,
        created_at`. Storing the per-row rate alongside the computed cost
        (not just the final number) means old rows stay individually
        verifiable even after pricing constants are updated later. RLS
        enabled, **zero policies or grants for `authenticated`/`anon`** —
        this is pure observability for Harris, not a user-facing feature, so
        it deliberately does NOT copy `api_usage_daily`'s owner-scoped grant
        pattern; matches `ai_precision_cache`'s existing service-role-only
        design instead (see Supabase RLS status section above).
      - **`ask-chef-harris` redeployed** (`version: 5`) to write a row after
        every real OpenAI response: decodes `user_id` from the `sub` claim
        of the already-`verify_jwt`-validated Authorization header (no extra
        network round-trip needed), inserts via a raw `fetch` to
        `/rest/v1/api_call_cost_log` using the service role key (mirrors the
        file's existing fetch-to-OpenAI style rather than adding a
        `supabase-js` dependency for one insert), wrapped in try/catch so a
        logging failure can never turn into a failed recipe response.
      - **Pricing centralized, one named place per runtime** (can't
        literally be one file across Dart/Deno): `OPENAI_PRICING_PER_MILLION_TOKENS`
        in `supabase/functions/ask-chef-harris/index.ts` (authoritative —
        this copy is what actually gets persisted) and
        `_openAiPricingPerMillionTokens` in `chef_service.dart` (drives only
        the client-side console fallback estimate). Both carry a "rates
        checked 2026-08-13" dated comment and explicitly cross-reference
        each other — update both together when rates change.
      - **Deployment — confirmed, no Dashboard steps needed.** Both the
        migration (`supabase db push`) and the function redeploy
        (`supabase functions deploy ask-chef-harris --use-api`) used the
        same CLI paths already proven earlier this session — nothing here
        required manual Supabase Dashboard involvement.
      - **Live-tested end to end, with one real bug caught along the way.**
        First test (5 real generations after deploying): `api_usage_daily`
        incremented correctly, but `api_call_cost_log` had **zero rows**.
        Root cause: `service_role` had no INSERT/SELECT grant on the new
        table — `bypassrls` only skips RLS *policies*, it does not grant
        table-level SQL privileges on its own, and the migration correctly
        locked out `authenticated`/`anon` but never explicitly granted
        `service_role` either. **This is the exact same root-cause class as
        the `api_usage_daily` grants bug from 2026-08-11**, which CLAUDE.md
        already documented as a lesson to apply going forward — missed here
        despite that. Fixed via a follow-up migration
        (`20260813130000_fix_api_call_cost_log_service_role_grants.sql`,
        `grant select, insert on public.api_call_cost_log to service_role`),
        pushed, confirmed via `information_schema.role_table_grants`.
        **Re-tested after the fix — confirmed working**: one real row
        landed — `gpt-4o, prompt_tokens=3344, completion_tokens=627,
        cost_usd=0.01463` — consistent with the ~0.11 CHF Harris had seen
        across a multi-call session. **Updated lesson**: when locking a
        table to service-role-only, explicitly check/grant `service_role`
        itself, not just confirm `authenticated`/`anon` are locked out —
        those are two independent things to verify, not one.
12. **Debug-mode bypass for usage caps and paywall — BUILT 2026-08-13,
    caused a real regression the same day (see item 11 follow-up above).**
    Single-point fix: `EntitlementService.isPro()`
    (`lib/services/entitlement_service.dart`) now returns `true`
    immediately whenever `kDebugMode` is true, before any RevenueCat/mock
    check. This works cleanly because every gate in the app already follows
    the same `isPro = await EntitlementService.instance.isPro(); if
    (!isPro) { check usage cap / show upgrade prompt }` pattern (confirmed
    by reading all three real gate call sites — Fridge Clearer's weekly cap,
    Custom AI Recipe Creator's 2-free-lifetime gate, Chef Harris chat's
    daily cap — plus the post-cook upgrade nudge) — so one change at the
    entitlement source transparently unlocks all of them at once, without
    touching `UsageCapService` or any individual screen. Zero effect on
    release builds: `kDebugMode` is a compile-time constant, `false` there,
    so this entire branch is dead code in release. **What this missed**: the
    same `if (!isPro)` blocks also gated `UsageCapService.increment(...)` at
    all four call sites, not just the cap checks — so this bypass silently
    stopped all usage tracking in debug builds too, not just the caps it was
    meant to bypass. Fixed same day (item 11 follow-up) by un-nesting the
    increment calls so tracking and gating no longer share a conditional.
    `flutter analyze` clean. **Live-tested 2026-08-13**: confirmed the caps
    themselves still bypass correctly in debug builds (6 Fridge Clearer
    generations in one day, no upgrade prompt), and confirmed tracking now
    survives the bypass too.

    **Recorded as a known, accepted risk — 2026-08-15, at Harris's explicit
    instruction, not as a new finding.** A `kDebugMode` bypass on this
    exact entitlement path has already silently broken usage tracking on
    this project once (the "What this missed" paragraph above, same day it
    shipped). The design itself is unchanged and still correct for what
    it's for — but recording the precedent explicitly here means any
    future change to `isPro()`, or anything else gated the same way, should
    treat "does this interact badly with the debug bypass" as a real
    question to ask, not something to discover live again. This is a
    decision being kept, not a bug being reopened.
13. **Recipe variety — BUILT 2026-08-13, follow-up fix same day after the
    first pass failed live-testing.** First pass: root cause found by
    reading the actual prompt-building code rather than assuming — neither
    AI-generation flow ever told the model to avoid repeating past dishes.
    `home_dashboard_screen.dart`'s `_buildHistoryAwarePrompt` used cook
    history to find a *pattern* and explicitly asked the AI to build ON it
    — the opposite of an anti-repeat instruction — and its only real
    repeat-avoidance (`_previousSuggestions`) was in-memory, reset every
    time the sheet closed. Fridge Clearer's `excludeTitle` only ever
    excluded the immediately-previous "Try Another" title. Fix: an optional
    `recentDishTitles` parameter on `ChefService.askChefHarris`, sourced
    from `CookSessionStorageService().loadCookHistory()`.

    **That first pass didn't work.** Harris ran 5 consecutive Fridge Clearer
    generations with the same ingredients and got the same egg-and-potato
    bake 5 times under different names (Frittata → Hash → Bake → Skillet →
    Bake). Root cause, confirmed by tracing the actual call chain before
    changing anything: `CookSessionStorageService.addRecentlyCooked()` (what
    populates the history `recentDishTitles` read from) is only called from
    `one_pan_cooking_roadmap_screen.dart:301`, inside Cook Mode's `initState`
    — i.e. only when a recipe is actually *opened in Cook Mode*, never when
    it's merely *generated*. Fridge Clearer's "Generate"/"Try Another"
    buttons never touch that history at all unless the user proceeds into
    Cook Mode. So across 5 generations in one sitting, `recentDishTitles`
    had nothing from those 5 generations to exclude against. Second failure
    mode, same test: even title-string exclusion wouldn't have been enough
    on its own — the model was dodging it by renaming the same dish concept
    each time.

    **Follow-up fix, same day:**
    - **`RecentGenerationsService`** (`lib/services/recent_generations_service.dart`,
      new file) — an in-memory singleton (`instance` pattern, matching
      `EntitlementService`/`UsageCapService`) tracking dish titles generated
      this app session, most-recent-first, capped at 20, case-insensitive
      dedup. Deliberately **not** stored in a screen's `State` (dies on
      navigation, defeating the point) and deliberately **not** merged into
      `CookSessionStorageService` (that service's persisted-cooked-only
      semantics are a different lifetime/meaning — conflating the two would
      just recreate the "two mechanisms drift" problem elsewhere). A
      singleton was the only shape that satisfies both real constraints:
      survives navigating away and back, and is shared across every surface
      that generates recipes. Not persisted to disk — resets on a full app
      restart, which is fine, its job is only to catch immediate repeats
      within one running session.
    - **Format-level exclusion.** Title exclusion alone can't stop a rename;
      `ChefService` now also extracts known dish-format keywords (frittata,
      bake, hash, skillet, casserole, stir-fry, curry, soup, salad, pasta,
      pizza, roast, etc. — see `_knownDishFormats`) from the same recent-titles
      list and, when found, adds a second explicit instruction naming the
      *format* itself as off-limits, not just the literal title. This is a
      hand-maintained keyword list, not a real classifier — considered and
      rejected a model-returned `format` JSON field instead (see below).
      Gated behind a new `excludeDishFormats` param (default `true`).
    - **Considered and rejected: model-returned `format` field instead of a
      keyword list.** Would need a schema change + defensive parsing (this
      project has already seen JSON-mode schema-consistency slips from the
      model, e.g. the 2026-08-11 gpt-4o-mini trial), doesn't help
      retroactively against already-persisted cook-history titles, and —
      decisively — home dashboard's Chef Harris Suggestion is deliberately
      **non-JSON** (`forceJsonObject: false`, prose the user reads directly),
      so a schema field can't cover that surface at all without a much
      bigger redesign. Token cost was a wash either way (~5-10 tokens for a
      field vs. negligible keyword-scan cost) so wasn't the deciding factor.
    - **`_previousSuggestions` deleted, merged into `recentDishTitles`.**
      `_ChefSuggestionSheetState` no longer keeps its own in-memory list or
      appends a separate freeform "don't suggest again" text block — both
      reading and writing now go through `RecentGenerationsService.instance`,
      same as every other surface, so there's one mechanism instead of two
      that could silently drift apart.
    - **Scope: Fridge Clearer, home dashboard, and Weekly Planner's Deal
      Meal fast path** (`weekly_planner_screen.dart` — the only
      Weekly-Planner-owned generation call; its other 2 "Add meal" paths
      delegate to Fridge Clearer/Custom AI Recipe Creator, which are wired
      separately) **get both title AND format exclusion.** Weekly Planner's
      Deal Meal makes 2 `askChefHarris` calls per generation — exclusion
      only applies to the first (dish-selection) call, since the second
      just builds Cook Mode steps for whatever dish the first already
      picked; nothing left to vary there.
    - **Custom AI Recipe Creator gets title exclusion only —
      `excludeDishFormats: false` explicitly passed at its call site.**
      Deliberate: a user typing "frittata" into that sheet is explicitly
      requesting that format, and format-excluding it based on their own
      recent history would fight their own input. It still both reads from
      and writes to the shared `RecentGenerationsService` (so its outputs
      count toward variety pressure on other surfaces, and vice versa) —
      just without the format-level constraint applied to its own prompt.
    - **Not wired, out of scope this round**: `fridge_countdown_sheet.dart`'s
      "Use Tonight" — same underlying gap (shares Fridge Clearer's weekly
      cap, generates via `askChefHarris` directly), flagged but not
      requested.
    - Debug logging now prints the full `recentDishTitles` array (not just
      a count) plus the detected format list and the `excludeDishFormats`
      flag on every call — `ChefService.askChefHarris variety: excluding N
      recent dish title(s) from this prompt: [...] | excluding N dish
      format(s): [...] (excludeDishFormats=...)`.
    - `flutter analyze`: 0 errors project-wide (same 65 pre-existing
      style-level infos/warnings as before this session, none new).
      **Not yet live-tested against this specific failure mode** — next
      step is re-running the same 5-in-a-row Fridge Clearer test Harris
      just ran and confirming both the console log and the actual dishes
      show real variety this time.
14. **OpenAI prompt caching — INVESTIGATED AND CLOSED 2026-08-15. Not open,
    deprioritized — do not reopen unless generation volume grows by two
    orders of magnitude.** Originally added 2026-08-13 on the hypothesis
    that the system prompt might need reordering for caching to engage.
    Investigated directly against the actual code (`chef_service.dart:486`)
    rather than left as a hypothesis: **the system prompt is already a
    clean, 1,774-token static prefix, byte-for-byte identical on every
    call (`const systemPrompt = ...`), and already correctly positioned
    first** in the `messages` array sent to OpenAI (`ask-chef-harris/index.ts`).
    No restructuring is needed for that part — the original framing (that
    the curriculum addendum being in the user message meant the system
    message's own ordering needed fixing) was based on an inference that
    didn't hold up once the actual code was read: the addendum was never
    in the system message to begin with, so the boundary was already
    clean. OpenAI's requirements (verified against current docs, not
    memory): automatic for `gpt-4o`+, no code/parameter changes needed,
    ~1,024-token minimum, 128-token increments, exact-prefix match, 50%
    discount on cached input tokens — this prompt already clears the
    minimum by a comfortable margin.
    **Estimated saving, if the cache is actually hitting: ~$0.0022/call,
    ~$2.22/month at 1,000 generations/month.** Real but small.
    **Unverified, and not worth verifying at this volume**: nothing in
    this codebase captures OpenAI's `prompt_tokens_details.cached_tokens`
    field (checked `ask-chef-harris/index.ts`'s logging and
    `api_call_cost_log`'s columns — grepped the whole repo for
    `cached_tokens`, zero matches), so there's no way to confirm from
    existing data whether caching is actually engaging today. Capturing
    that field would be a small, additive logging change (not a prompt
    change) that would answer this definitively — **explicitly not worth
    doing at current volume**, per the dollar figures above. A secondary,
    smaller opportunity was also found (the JSON schema block +
    guidelines in each surface's own `_buildCookModePrompt`-equivalent are
    textually static per surface but currently interleaved with per-call
    values, so they can't benefit from caching as written) — **not
    pursued, and explicitly not to be pursued without a deliberate
    decision**: it would mean touching content across the 4 duplicated
    schema blocks, which is exactly the kind of prompt change this
    project has already seen have real, unintended quality effects (the
    `'swiss'` cuisine bug, the `gpt-4o-mini` voice trial) — not neutral
    reordering. **Closed as: correctly structured already, real but small
    money on the table, not worth chasing further at current scale.**
15. **Safety validator for Chef Harris output — added 2026-08-15. HIGH
    PRIORITY, PRE-LAUNCH BLOCKER.** Right now there is no check of any kind
    between OpenAI's raw output and what the user sees — `ChefService.askChefHarris`
    (`lib/services/chef_service.dart`) returns the trimmed response text
    straight through (only checked for non-emptiness), and every caller
    consumes it directly. For a cooking app generating actual temperatures,
    times, and storage/reheat instructions, a food-safety error reaching a
    real user is a liability question, not just a quality one — a different
    risk class from the voice/quality tuning in Roadmap item 5. The system
    prompt already contains a short "CORE FOOD SAFETY (non-negotiable)"
    block (danger zone, raw-protein handling, cooling times — see
    `_curriculumCore` in `chef_service.dart`), but that's pre-generation
    guidance only, never checked against what actually comes back.
    Likely architecture: a deterministic rules layer for well-defined,
    enumerable hazards, plus a model-review backstop call for cases the
    rules layer can't anticipate. On a flag, prefer regeneration or
    correction injection over an outright block — consistent with this
    app's existing fail-forward pattern (`UsageCapService`'s fail-open
    design, `askChefHarris`'s own internal error fallback strings) — a hard
    block on a false positive would be a worse outcome than a corrected
    recipe. **The actual hazard list is Harris's to supply** (professional
    culinary knowledge) — do not invent or expand it unprompted.
    **Shares an interception point with a future "teaching corpus
    constraint layer"** (keeping AI-generated technique guidance consistent
    with the curriculum drawers) — design the hook to serve both, not just
    food safety.

    **Where this would actually sit (found via a 2026-08-15 read-only
    architecture pass, not yet scoped into an implementation plan):**
    there is no existing single choke point. Four independent surfaces each
    call `askChefHarris` and parse its raw string into a `CookModeRecipePayload`
    (the typed recipe model, defined in `one_pan_cooking_roadmap_screen.dart`
    despite the filename) via their **own separately duplicated**
    `_parseCookModeRecipe` private method: `fridge_clearer_screen.dart`,
    `custom_ai_recipe_creator_sheet.dart`, `fridge_countdown_sheet.dart`
    (Use Tonight), and `weekly_planner_screen.dart` (Deal Meal fast path's
    2nd call). Display after parsing also diverges by surface — some route
    through the shared `GeneratedRecipeActionsSheet` widget (Fridge
    Countdown; Home's Custom AI Craving entry point), some display inline
    in their own screen/sheet (Fridge Clearer; Weekly Planner's Deal Meal
    sheet), and some silently add straight to the weekly plan with **no**
    review screen at all (Weekly Planner's Custom AI Craving and
    fridge-picker entry points) — so a "show the corrected version" UX
    doesn't have a consistent landing spot today. Building one real choke
    point means: (a) extracting the 4 duplicated parsers into one shared
    `parse` function (worthwhile cleanup on its own), (b) calling
    validation immediately after that shared parse succeeds, before any of
    the 4 surfaces branch into their different display/persist paths, (c)
    deciding what regeneration means for the 2 surfaces that never show a
    review screen today, and (d) deciding whether `_ChefSuggestionSheet`
    (Home's free-text suggestion) and `_ChefSosSheet` (Cook Mode's SOS
    chat, mid-cook — arguably the single highest safety-relevance surface,
    since it's live troubleshooting) are in scope, since both return
    unstructured prose (`forceJsonObject: false`), not a `CookModeRecipePayload`,
    so the same field-level rules layer can't apply to them directly.
    Also out of this chokepoint entirely: `AiRecipeService`/
    `ai-recipe-precision`'s "precision cards" (heat spec, salt timing, etc.)
    are a separate AI call with separate parsing — safety-adjacent content
    that reaches the user through a different path, worth a scoping
    decision alongside the above rather than assuming it's covered.
    **Nothing awkward found on the streaming/caching/optimistic-UI front**:
    `askChefHarris` isn't streamed today (see Roadmap item 5, step 3 —
    still a future project) and nothing renders partial/unvalidated content
    before a full response is parsed — `setState` only happens after
    parsing succeeds. Do factor in, for whenever streaming ships: an
    incremental UI would need to either buffer the full response behind
    validation anyway or design the validator to work incrementally — not
    a today problem, but a real one for that project once it starts.
    Not yet scoped into a concrete implementation plan or started.

    **Shared-parser refactor (prerequisite for this item) — device-tested
    and ACCEPTED 2026-08-15.** `parseChefRecipeJson` (`chef_recipe_parser.dart`)
    is live at all 4 call sites. Device-test breakdown, recorded honestly
    rather than as a blanket "passed":
    - **Fridge Clearer** — ran clean, console-verified: 2 generations, both
      parsed, curriculum tags resolved, `WhatYouLearnedSheet` resolved 4
      lessons, no exceptions.
    - **Fridge Countdown** — not run. Blocked by the cold-start dead end
      documented under Retention Features Backlog item 1 (no way to seed a
      first fridge item without one already existing). Coverage substituted
      by the unit test suite below plus a direct code-read confirming
      `fridge_countdown_sheet.dart:183` passes `readDescription: false`.
    - **Custom AI Recipe Creator, both entry points (Home + Weekly Planner)**
      — ran, completed visually, recipe landed correctly in Weekly
      Planner's Tuesday slot. Console wasn't attached (stale browser tab) —
      **verified instead via `api_usage_daily`**: `custom_ai_recipe_creator`
      showed count=2 for the test session, confirming both passes really
      generated, independent of console visibility.
    - **Weekly Planner Deal Meal** — not run, and not going to be: this
      surface is being removed (see the new Deal Meal removal item below).
    - **Malformed-response coverage (originally checklist item 9)** —
      replaced by `test/services/chef_recipe_parser_test.dart`, 11/11
      passing: valid JSON, non-JSON text, non-object JSON, empty steps,
      missing ingredients/kitchen_gear/title, and both flags in both
      states.
    - **Cook Mode portion stepper (checklist item 7) — PARTLY VERIFIED,
      not fully.** Not systematically exercised on every surface this
      pass. Recorded honestly per Harris's instruction rather than rounded
      up to "verified" — the earlier code trace (this same item, above)
      showing the stepper gates on `structuredIngredients` and never on
      `basePortions` keeps the risk assessed as low, but "low risk" is not
      the same claim as "checked."
    **Accepted on this basis** — the frozen files are unfrozen; further
    work on them no longer needs to route back through this checklist.
16. **`ai-recipe-precision` source is not in this repo and is currently
    unauditable — added 2026-08-15. HIGH PRIORITY.** Confirmed live and
    real (not dead code, not bypassed — see the 2026-08-15 generation-path
    report): `AiRecipeService.getPrecisionData()` makes a genuine
    `functions.invoke('ai-recipe-precision', ...)` call, and `supabase
    functions list --project-ref xwugnhzlnfgmczkbbcbh` confirms it's
    `ACTIVE`, `version: 2`, deployed. The problem is narrower than "does it
    work" — its actual implementation cannot be read or diffed from this
    codebase at all, unlike `ask-chef-harris` (checked into
    `supabase/functions/ask-chef-harris/index.ts`). That means any
    food-safety-relevant logic inside it (it returns heat specs, salt
    timing, knife-cut specs — all safety-adjacent) is currently unreviewable,
    and it sits **entirely outside** the safety-validator chokepoint
    described in Roadmap item 15 (which only covers `askChefHarris`'s
    `CookModeRecipePayload` output). **Confirmed available, not yet run**:
    the Supabase CLI has a real `supabase functions download` subcommand
    (`supabase functions download ai-recipe-precision --project-ref
    xwugnhzlnfgmczkbbcbh --use-api`, run from the repo root) that should
    pull it down to `supabase/functions/ai-recipe-precision/`, mirroring
    the same relative-path convention already confirmed for `deploy` (see
    "What this is" section, top of this doc). Needs no new
    access — same already-linked, already-authenticated CLI used all
    session. **Not yet run** — whether the download comes back as
    readable original source or a bundled/minified blob is unknown until
    someone actually does it; flagging that uncertainty rather than
    assuming either way. **Also flagged, not fixed**: `ai-recipe-precision`
    has `verify_jwt: false` while `ask-chef-harris` has `verify_jwt: true`
    — an asymmetry in auth requirements between the app's two edge
    functions, noticed while confirming the above via `functions list`.
    Not investigated further — flagging as a possible cost/security
    exposure (an unauthenticated function is callable by anyone with the
    project's anon key, not just this app's real users) to confirm, not
    asserting it's actually a problem yet.

    **Source downloaded and read 2026-08-15 — findings below, source is now
    in this repo but under a deploy hold.** Ran
    `supabase functions download ai-recipe-precision --project-ref
    xwugnhzlnfgmczkbbcbh --use-api` from the repo root; it now lives at
    `supabase/functions/ai-recipe-precision/index.ts` +`deno.json`.
    **Came back as clean, readable, hand-authored TypeScript** — not a
    bundled/minified blob, comments intact (including one noting a prior
    schema-alignment fix to `ai_precision_cache`'s columns). **Has NOT been
    deployed from and must not be** — `supabase/functions/ai-recipe-precision/NOTE_DO_NOT_DEPLOY.md`
    documents the hold until Harris reviews it.
    - **What it returns**: `heatLevel`, `heatReason`, `knifeCutSpecMm`,
      `saltTiming`, `acidBalanceNote`, `substituteSwiss`, `baseRatios` — all
      cooking-technique guidance (heat/timing/ratios), **no explicit
      food-safety framing at all**. Unlike `ask-chef-harris`'s system
      prompt (which has a dedicated "CORE FOOD SAFETY" block — danger
      zone, raw-protein handling, cooling times), this function's system
      prompt only asks for technical culinary precision ("Be technical and
      specific — temperatures, timings, physical cues, ratios. No generic
      filler.") — no safety instruction, no hazard check, no validation of
      any kind on the model's output before it's cached and returned. Its
      `heatLevel`/`heatReason` fields are cooking-technique heat (e.g.
      "medium-high" pan heat), not a food-safety internal-temperature
      check — worth being precise about that distinction when scoping
      Roadmap item 15, since this function is real safety-adjacent content
      with materially less scrutiny on it than the main recipe path, not more.
    - **Auth — confirmed real exposure, not just a `verify_jwt` label.**
      The handler performs **no authentication check of its own** anywhere
      in the code — no reading or validating an `Authorization` header at
      all — and it initializes its Supabase client with the **service role
      key** (full DB privileges) regardless of caller. Combined with
      `verify_jwt: false` at the platform level, this means anyone with
      the project's public anon key (necessarily embedded in the shipped
      app, not a secret) can call this function directly — bypassing the
      Flutter app, `EntitlementService`, and `UsageCapService` entirely —
      and trigger either a cache read or a real billed OpenAI call, with
      zero rate limiting or identity check server-side. This is a genuine
      cost/abuse exposure, not a theoretical one: the client-side usage
      caps this project relies on for cost control (see "Monetization"
      section above) provide **no protection at all** against direct calls
      to this specific function. Not fixed — report only, flagging
      severity higher than the original "possible exposure to confirm"
      framing now that the code itself has been read.

    **Follow-up investigation, same day (2026-08-15) — service-role DB
    access, cache-poisoning risk, client auth header, and least-privilege
    question, all answered from code, no live exploit attempted:**
    - **Every DB operation the service-role client makes** (all three
      target `ai_precision_cache`, no other table): (1) `SELECT` filtered
      by `cache_key` — a SHA-256 hash of `{ingredients (sorted), method,
      protein, cutStyle}`, i.e. **entirely caller-controlled**, no
      user/session component; (2) `UPDATE` of `hit_count`/`last_used_at`,
      same caller-controlled `cache_key` filter; (3) `INSERT` on a cache
      miss, writing that same `cache_key` plus whatever the LLM returned
      (`JSON.parse(llmJson.choices[0].message.content)`, only a
      compile-time TypeScript type annotation, **zero runtime validation**
      of field types/content before it's written). **Also confirmed**: the
      function's `PrecisionRequest` interface only reads `ingredients`,
      `method`, `protein`, `cutStyle` from the request body — it silently
      **ignores** every profile/safety field the Dart client actually
      sends (`userSafetyContext`, `dietaryPreference`, `allergies`,
      `profileSafetyHash`, `servings` — see `_buildPrecisionRequestBody` in
      `ai_recipe_service.dart`). The client goes to the trouble of building
      a dietary/allergy safety context and sending it; **the deployed
      function never reads it.** Sharpens the earlier "no food-safety
      framing" finding — it's not just that the prompt lacks a safety
      instruction, the safety-relevant input path from the client is
      wired to nothing server-side.
    - **Cache poisoning — YES, structurally confirmed via code (not via an
      actual live attack — none was attempted).** The cache key has no
      per-user or per-session component, and reads are a plain
      key-equality lookup — any two callers whose `{ingredients, method,
      protein, cutStyle}` hash the same get the same cached row, full
      stop. A caller cannot write arbitrary text directly (there's no raw
      pass-through insert), but `ingredients`/`method`/`protein`/`cutStyle`
      are free-form strings concatenated straight into the OpenAI user
      prompt (`Ingredients: ${ingredients.join(', ')}\nMethod: ${method}...`),
      a standard prompt-injection surface — and whatever the model returns
      is cached with no validation. An unauthenticated caller can (a)
      deliberately target a predictable, realistic ingredient/method
      combination a real user is likely to request later, and (b) attempt
      to steer the model's `heatLevel`/`heatReason`/`saltTiming`/etc. text
      via injection in those fields. If that steering succeeds even
      partially, the result is cached and **will** be served verbatim to
      the next real user who happens to send the same combination —
      there's no mechanism that could prevent it structurally. Whether a
      given injection attempt succeeds against the model is inherently
      variable; that the *pathway* exists with no barriers is not in
      question.
    - **Flutter client auth header — confirmed via the actual SDK source,
      not assumption.** Traced the real call chain in the local pub cache
      (`supabase-2.13.4/lib/src/supabase_client.dart` +
      `auth_http_client.dart`, `functions_client-2.6.4/lib/src/functions_client.dart`):
      `SupabaseClient.functions` is constructed with `httpClient:
      _authHttpClient`, and `AuthHttpClient.send()` calls `_getAccessToken()`
      — which returns `auth.currentSession?.accessToken` (**live**,
      refreshing it first if expired) — and injects it as `Authorization:
      Bearer <token>` on every outgoing request via `putIfAbsent` (only
      applied if not already set, and nothing in this app sets a static
      Authorization header, so it always applies). Since this app signs in
      anonymously at startup, every real user always has a live, valid
      session JWT attached to every `ai-recipe-precision` call already,
      today, unconditionally — the same mechanism `ask-chef-harris`
      (`verify_jwt: true`) already relies on and which works fine for this
      anonymous-first app. **Flipping `verify_jwt: true` on
      `ai-recipe-precision` would very likely not break real users** —
      not flipped, per instruction; this is code-level evidence, not a
      live test, and doesn't account for every edge case (e.g. a session
      that failed to establish at all, which falls back to sending the
      anon key itself — also a valid project JWT, so likely still accepted,
      but genuinely untested).
    - **Is the service-role key actually required? No — only the current
      lack of RLS policies makes it required.** Per the existing RLS
      section above, `ai_precision_cache` has **zero policies for
      `authenticated`/`anon`** — that's the only reason this function
      can't use the anon key today; its actual operations (3 simple
      operations against 1 table, no cross-table access, no columns
      suggesting per-user sensitivity — no `user_id` column at all) don't
      inherently need service-role privilege. Switching to the anon key
      plus a scoped RLS policy on just this table would reduce blast
      radius (service role bypasses RLS on *every* table in the project;
      anon key + a scoped policy would confine this function to the one
      table it's supposed to touch) — but would NOT by itself fix the cost
      exposure above, since that's about who can invoke the function at
      all, not what it's allowed to do once invoked. Config/schema change,
      not made — report only.

    **RLS/grants audit, 2026-08-15 — real finding, not just confirmation.**
    Queried the live project directly (`supabase db query --linked`, read
    -only, no changes made): every one of the 11 `public`-schema tables
    currently exposed via the Data API has **RLS enabled** — none exposed
    with RLS disabled.

    | table | RLS enabled | policy count |
    |---|---|---|
    | `ai_precision_cache` | true | 0 |
    | `api_call_cost_log` | true | 0 |
    | `api_usage_daily` | true | 3 |
    | `fridge_items` | true | 4 |
    | `ingredients` | true | 3 |
    | `recipes` | true | 4 |
    | `shopping_list_items` | true | 5 |
    | `user_ledger_totals` | true | 1 |
    | `user_meal_plans` | true | 5 |
    | `user_profiles` | true | 6 |
    | `waste_ledger_events` | true | 1 |

    For `ai_precision_cache` specifically: **RLS enabled + 0 policies means
    default-deny for every non-bypassing role** — confirms scenario (a),
    not (b): the edge function's `service_role` key (which has
    `BYPASSRLS`) is currently the only door, regardless of grants. **But
    the grants themselves turned out to be wrong, and that's the real
    finding.** Checked `information_schema.role_table_grants` directly:
    `anon` and `authenticated` both have full **SELECT, INSERT, UPDATE,
    DELETE** on `ai_precision_cache` — not just the harmless
    REFERENCES/TRIGGER/TRUNCATE this table's documented design calls for
    (contradicts this doc's own earlier claim of "zero policies or grants
    for authenticated/anon" — that claim was wrong, now corrected here).
    Checked `api_call_cost_log` (the other 0-policy table) as a control:
    it's correct — `anon`/`authenticated` have only REFERENCES/TRIGGER/
    TRUNCATE there, `service_role` has the real INSERT/SELECT, exactly as
    documented and as the 2026-08-13 fix migration intended. So this is
    specific to `ai_precision_cache`, not a systemic pattern across both
    service-role-only tables — likely the same "inherited default
    privileges, never explicitly revoked" root cause already documented
    for the `api_usage_daily` grants bug (2026-08-11), just never caught
    here because RLS happened to mask it.
    **Practical risk today**: not exploitable via the Data API right now
    — RLS's default-deny holds regardless of the stray grants. **Latent
    risk**: RLS enabled is the *only* thing preventing it. If RLS were
    ever disabled on this table by accident (a migration mistake, a
    Dashboard misclick, anything) — with zero code change anywhere else —
    `anon`/`authenticated` would immediately have full read/write on this
    table via the Data API, no edge function or prompt injection needed,
    exactly the more-direct poisoning path this was checked to rule out.
    **Fixed 2026-08-15**, with explicit approval — see "Supabase RLS
    status" section above for the exact command run and the confirmed
    post-fix grants.

    **Design warning — do not "fix" the discarded safety fields by just
    reading them.** The client sends `userSafetyContext`, `allergies`, and
    `dietaryPreference` to `ai-recipe-precision`, and the function discards
    all of it (see above). That looks like a simple oversight to patch, but
    it structurally isn't: the cache key is a content hash of
    `{ingredients, method, protein, cutStyle}` with **no user component at
    all**. If the function were changed to actually use allergy/diet
    context without also changing the cache key, the *first* user who
    triggers a generation for a given ingredient combination would get a
    response personalized to their allergies — and that response would
    then be cached and served to every *other* user who happens to request
    the same ingredients, regardless of their own allergies. **This is
    worst for `substituteSwiss`** specifically — the one field whose
    entire purpose is allergy/diet-driven substitution — a cached
    substitution chosen for one user's allergy could be served as neutral
    "helpful" advice to a user with a different or no allergy. Any future
    change making this function allergy-aware **must change the cache-key
    derivation first** (e.g. fold a hash of the safety-relevant profile
    fields into the key, same pattern `ChefService`'s
    `_hashSafetyRelevantProfileFields` already uses client-side) — reading
    the fields without that is not a partial fix, it's a new bug.

    **`verify_jwt: true` — one more consequence to record before flipping
    it, not a blocker, just don't be surprised by it.** `main()` wraps
    `signInAnonymously()` in try/catch specifically so a failure there
    never blocks app startup (see Auth section above) — meaning a user
    whose anonymous sign-in failed has no session and therefore no real
    JWT. Today, `ai-recipe-precision` still serves them fine (no
    `verify_jwt` gate). After flipping it to `true`, those specific users
    would lose precision cards — a feature that works for them today would
    stop, silently from their side (no error UI exists for this
    specifically). Acceptable and reversible from the Dashboard in
    seconds, but worth having written down so it isn't a surprise
    if/when someone asks "why did precision cards stop for some users."

17. **Fridge Clearer fabricates a fallback recipe on parse failure instead
    of showing "no recipe" — added 2026-08-15. Prerequisite for Roadmap
    item 15.** Confirmed via the 2026-08-15 shared-parser report: of the 4
    recipe-generating surfaces, 3 (Custom AI Recipe Creator, Fridge
    Countdown, Weekly Planner's Deal Meal path) already show an error
    message and no recipe when `_parseCookModeRecipe` returns null. Fridge
    Clearer (`fridge_clearer_screen.dart:592-617`) is the outlier — on
    null it silently constructs a hardcoded 2-step generic "recipe" and
    displays that instead, meaning it structurally cannot represent "no
    recipe to show" today. This blocks the safety validator's hard-fail
    mode (Roadmap item 15) on this specific surface, since hard-fail
    depends on being able to show nothing. **Turns out to be a small fix,
    not new UI**: the screen already has `_generationError` (state
    var) and `_InlineErrorCard` (already rendered at `:869-871`, already
    wired to a retry callback) — used today for actual exceptions (the
    outer catch block, `:694`) but never reached by the parse-failure
    branch specifically, which currently never sets `_generationError` and
    instead falls through to building the fallback recipe. Fixing this
    means replacing the fallback-recipe construction with setting
    `_generationError` and leaving `_generatedRecipe` null — reusing
    existing, already-correct UI, not building anything new. Not started.
18. ~~**Weekly Planner's Deal Meal path is hardcoded to 2 servings.**~~
    **CLOSED BY REMOVAL, 2026-08-15 — not fixed, the surface it lived on no
    longer exists.** See the Deal Meal removal entry after item 20 for the
    full removal record. Original text kept below for history.

    Added 2026-08-15. `_buildCookModePrompt`
    (`weekly_planner_screen.dart:1539-1573`) hardcodes `'Scale realistic
    quantities for 2 people.'` directly in the prompt text and never reads
    `profile.householdServings` or asks the user for a size — unlike the
    other 3 recipe-generating surfaces, which all take a real `portions`
    parameter sourced from the household profile. Confirmed (2026-08-15)
    this is why `_parseCookModeRecipe`'s `basePortions: structuredIngredients.isEmpty
    ? null : 2` hardcodes `2` too — it's downstream of the prompt, not an
    independent bug. Low urgency: doesn't crash or mislead silently (the
    "2 people" assumption is at least consistent between prompt and
    parser), just doesn't respect household size for this one fast path.
19. ~~**Weekly Planner's Deal Meal path bypasses `UsageCapService` entirely.**~~
    **CLOSED BY REMOVAL, 2026-08-15 — the cap gap is fully closed, not
    patched.** Confirmed the same day, re-checking the full `askChefHarris`
    call-site inventory after removal: the only uncapped call remaining
    app-wide is Cook Mode's SOS chat, which is uncapped **by design**
    (Harris's own 2026-08-10 decision — SOS stays free-forever as part of
    Cook Mode). No part of this cap gap survives anywhere else. Original
    text kept below for history.

    Added 2026-08-15. Confirmed via a
    full app-wide grep for `UsageCapService.instance.increment` (2026-08-15,
    during the shared-parser refactor session): there are exactly 4 call
    sites — `fridge_clearer_screen.dart:455`, `custom_ai_recipe_creator_sheet.dart:156`,
    `fridge_countdown_sheet.dart:165`, `home_dashboard_screen.dart:1288` —
    and **zero** in `weekly_planner_screen.dart`. Deal Meal generation
    (`_DealMealSuggestionSheetState`) makes **two** real `askChefHarris`
    calls per generation (dish selection, then Cook Mode steps for that
    dish — see Roadmap item 18) and neither one increments any cap. This
    is a real, live paywall/cost hole, not a hypothetical: a free user can
    generate unlimited Deal Meals, at two full OpenAI calls each, with zero
    usage tracking and no cap ever triggering. Not fixed — report only.
    Fix shape not yet designed; at minimum needs a `UsageFeature` decision
    (its own bucket, or share `fridgeClearerGeneration` like Fridge
    Countdown does) before wiring `increment(...)` calls in analogous to
    the other 4 surfaces.

    **Correction, same day**: an earlier draft of this session's report
    also claimed Deal Meal bypasses `RecentGenerationsService` (the
    recipe-variety fix, Roadmap item 13). **That claim was wrong and was
    corrected before being added here** — verified directly against
    `weekly_planner_screen.dart:1637-1662`: the dish-selection call (the
    only one of the two calls where variety actually matters — the second
    just builds steps for whatever dish the first already picked) both
    reads `recentDishTitles` (merging `RecentGenerationsService.instance.recent()`
    with cook history, same pattern as the other 3 surfaces) and calls
    `RecentGenerationsService.instance.record(parsed.title)` afterward.
    Deal Meal's variety coverage is actually correct and complete. Noting
    the correction here, not just in conversation, so this doesn't get
    "rediscovered" as a bug later from a stale summary. The one genuine
    `RecentGenerationsService` gap remains what Roadmap item 13 already
    documents: Fridge Countdown's "Use Tonight" neither reads nor writes
    it at all (separate from this item, already tracked, priority already
    raised 2026-08-15 under Retention Features Backlog item 1).

    **Recorded as a risk, not a neutral description — 2026-08-15, at
    Harris's explicit instruction.** `UsageCapService`'s cap-check fails
    open (`getUsageCount`/its wrappers `catch` any error and `return 0`,
    meaning a throw during the check is treated as "under the cap" and the
    generation proceeds — see `usage_cap_service.dart`). Fail-open is the
    right call for a feature flag; **it is the wrong default for a spend
    limit**, and combined with two other holes, there are currently
    **three separate ways past the cap**, not one:
    1. The fail-open catch itself — any transient error during the check
       (not the increment, the *check*) silently lets the generation
       through uncapped.
    2. Deal Meal's total bypass, documented above in this same item — the
       cap is never even consulted for that surface.
    3. The entire mechanism is client-side. `UsageCapService`'s check and
       `EntitlementService.isPro()`'s gate both run in the Flutter app —
       there is no server-side enforcement anywhere. A modified client, or
       any direct call to `ask-chef-harris`/`ai-recipe-precision` outside
       the app entirely (see Roadmap item 16's auth findings — the latter
       has no auth check of its own at all), bypasses all three of the
       above simultaneously, by construction, not as an edge case.
    None of these three are fixed. Recording them together because they
    compound — a single fix to any one of them still leaves the other two
    fully open. **Update 2026-08-15**: hole #2 (Deal Meal's total bypass)
    is closed by removal, per this item's header above. Holes #1
    (fail-open catch) and #3 (client-side-only enforcement) are general
    architecture facts, not tied to Deal Meal — they remain fully open for
    every surface that still exists.
20. **"Save if you liked it" — save custom creations plus feedback — added
    2026-08-15. Not started.** A real planned feature that never made it
    into this doc until now (surfaced when Harris referenced it by a
    roadmap number that had drifted from what's actually here — see the
    working-convention note below). Lets a user save a generated recipe
    they liked, plus feedback on it. No design/scope beyond that one-line
    description exists yet — not scoped into surfaces, data shape, or UI.

    **Blocker, discovered before this item existed on paper**: this
    feature will need to write to the `recipes` table, whose owner-write
    RLS policies are already correct (`auth.uid() = user_id` on INSERT/
    UPDATE/DELETE, confirmed via `pg_policies` — see "Supabase RLS status"
    above) but **currently unreachable**: `authenticated` is missing the
    INSERT/UPDATE/DELETE grants those policies assume exist — only a
    SELECT grant is present. Whoever builds this feature will write
    correct-looking policies (they already exist!) and watch every save
    silently fail via the Data API, because the actual blocker is one
    level up, at the grant layer, not the policy layer. Confirmed via grep
    that nothing client-side touches `.from('recipes')` today, so this
    table is genuinely dead/unused right now, not actively broken — but it
    will need exactly this fix as a prerequisite the moment this item
    starts: `grant insert, update, delete on public.recipes to authenticated;`
    (not run — this item hasn't started).
21. **Post-cook finish flow — UX gap, two halves, added 2026-08-15 from
    live device testing.** (1) After the Waste Ledger celebration → What
    You Learned → share card sequence finishes, the app sits idle on the
    finish screen doing nothing — it should return to Home once the share
    card is dismissed. (2) Separately: if the user skips or misses the
    share card, that card is lost the moment the sheet closes — it should
    be saved somewhere for a while so they can share it later (after
    eating, for example) instead of only existing in that one moment.
    Product decision, not designed or implemented here.
22. **Custom AI Craving via Weekly Planner writes silently, no
    confirmation — open product question, added 2026-08-15.** The
    generated recipe lands directly in the day slot; the user never sees
    or approves the title before it's placed. **Linked to Roadmap item
    15**: this is the same silent-write path already flagged there as
    having nowhere to display a corrected recipe if the safety validator
    ever flags one and wants to show a regenerated/corrected version
    instead of just blocking. Whether to add a confirmation step is
    Harris's call — not designed or implemented here.
23. **Custom AI Craving sheet's prompt-guidance copy needs a rewrite —
    added 2026-08-15.** The title copy ("Type a dish, craving, or diet —
    I'll generate a precise Cook Mode recipe"), the placeholder example
    text, and the four quick-pick chips all read awkwardly, and the promise
    the copy makes ("precise") isn't one Harris is sure he agrees with.
    Flagged as copy to rewrite — not rewritten here.
24. **"Custom AI Craving" as a feature name reads awkwardly — naming
    question, added 2026-08-15.** Not a task, not designed or resolved
    here — Harris's call on a replacement name, if any.
25. **Weekly Planner's "Supermarket Discount Meal" (Deal Meal) — REMOVED
    2026-08-15, product decision.** Assumed local supermarket discount
    data, which doesn't generalize to a European or global launch without
    far more machinery than it was worth. The `deals` table it tried first
    never existed (confirmed earlier this session and in prior sessions);
    its only real data source was a fallback query against the shared
    `ingredients` table's `badge` column — no dedicated schema, so nothing
    is orphaned at the database level.

    **Removed**: `_DealMealSuggestionSheet` + `_DealMealSuggestionSheetState`
    (`weekly_planner_screen.dart`, was `:1443-1857`, ~415 lines — dish
    selection, Cook Mode step generation, and the sheet's own UI, all in
    one self-contained block), `_showDiscountMealFromDealsForDay()` (was
    `:829-859`), the `onDiscountMeal` callback wiring in `_showAddMealSheet()`,
    the "Supermarket Discount Meal" tile in `_AddMealOptionsSheet` (trimmed
    from 3 options to 2, the class itself kept), `ChefRecipeSurface.weeklyPlannerDealMeal`
    (`chef_recipe_parser.dart`), and `_AisleExt.fromLabel` (a small
    aisle-name-parsing helper that existed only to support this feature's
    JSON parsing — found as a second-order dead-code effect while removing
    the rest, not on the original approved list, but genuinely unreachable
    the moment its only caller was gone). Also removed 5 now-unused imports
    from `weekly_planner_screen.dart` (`chef_recipe_parser.dart`,
    `chef_service.dart`, `cook_session_storage_service.dart`,
    `recent_generations_service.dart`, `state/user_profile_controller.dart`)
    — verified via grep that nothing else in the file used any of them.
    Fixed the two stale doc comments that referenced this feature
    (`chef_recipe_parser.dart`'s class doc, `recent_generations_service.dart`'s
    class doc).

    **Explicitly kept, confirmed shared with the surfaces that remain**:
    `_AisleItem`, `_Aisle`, `_mergeAisleItems`, `_aisleItemsFromIngredients`,
    `_inferAisle`, `_upsertShoppingListItemsForMeal`, `_PlannedMeal`, the
    `ingredients` table and its `badge` column, `chef_service.dart`'s
    persona copy ("budget-friendly meals") and allergy-substitution
    guidance ("supermarket tier"), `theme.dart`'s tagline ("Time & Budget
    Kitchen Engine") — all confirmed used elsewhere or app-wide, despite
    surface-level keyword overlap with "deal"/"discount"/"budget".

    **Persisted data — no data migration, by explicit decision.** Old
    `user_meal_plans` rows with `source = 'Supermarket Discount Meal'`
    still render, still open in Cook Mode, still mark as cooked — `source`
    was confirmed (via full-file grep before removal) to be used only as
    display text, never branched on. **Known cosmetic residual, logged and
    accepted, not fixed**: those old slots' caption will keep reading
    "Supermarket Discount Meal" indefinitely, naming a feature that no
    longer exists to generate new ones. Explicitly fine per Harris — those
    rows are his own test data, no real users yet.

    **Closes Roadmap items 18 and 19 completely** — see their headers
    above. `flutter analyze`: **61 issues, down from the 65 baseline** (4
    fewer `unnecessary_type_check` warnings that lived inside the deleted
    JSON-parsing code went with it) — zero new issues introduced.
    `test/services/chef_recipe_parser_test.dart`: never referenced the
    deleted enum value, so no edit was needed there; re-ran anyway,
    11/11 still passing.
26. **Six "Swiss"-worded user-facing strings — NOT a cleanup item, added
    2026-08-15. Correct as they are; do not find-and-replace.** Surfaced
    during a grep for surviving "Swiss" copy after the earlier
    European-framing pass. **These are locale-dependent, not stale**:
    Swiss-first is the actual launch plan, and "Swiss households waste
    600+ CHF a year" is a stronger hook in Switzerland than a generic
    European line would be. They belong in future EN/DE/FR/IT
    localization work as the Swiss-locale variant of that copy, not a
    global rewrite. All six:
    - `lib/screens/onboarding_screen.dart:151` — `"Swiss households waste
      600+ CHF a year… in food that never gets eaten."` (onboarding
      headline)
    - `lib/screens/paywall_screen.dart:238` — `'Swiss households waste
      600+ CHF/year in food that never gets eaten...'` (paywall value
      prop)
    - `lib/screens/paywall_screen.dart:282` — `subtitle: 'Live timers,
      checkboxes, and Swiss substitute guidance.'` (paywall feature list)
    - `lib/screens/fridge_clearer_screen.dart:369` — `title: 'Swiss
      Substitute Map'` (precision-card title)
    - `lib/screens/fridge_clearer_screen.dart:360` — `'...very
      Swiss-kitchen friendly.'` (precision-card explanation text)
    - `lib/screens/fridge_clearer_screen.dart:1149` — `'Heat cues, cut
      specs, timing, and Swiss-kitchen swaps — tailored to your fridge.'`
      (rendered `Text` widget)

    **The three Fridge Clearer ones aren't independent copy choices — they
    trace to a field name in `ai-recipe-precision`'s data model.** That
    edge function's `PrecisionData` interface (`supabase/functions/ai-recipe-precision/index.ts`,
    downloaded and read under Roadmap item 16) has a `substituteSwiss: string`
    field — the Swiss framing is baked into the schema the AI is asked to
    fill, not just wording layered on top in the client. That's *why* the
    earlier European-framing pass missed these three: it was a text pass
    over Dart copy, and this framing lives one layer down, in what the
    model is asked to return. **Do not rename the field** — this is a
    documentation note about why these three exist, not a request to
    touch `ai-recipe-precision` (which is still under a deploy hold per
    Roadmap item 16 regardless). If/when real EN/DE/FR/IT localization
    work starts, this is the pointer to where the Swiss-specific framing
    actually originates for these three, so it isn't mistaken for a
    simple string edit.
27. **Waste Ledger silent data loss — added 2026-08-15. HIGH PRIORITY,
    before any testers.** `_ledgerSessionLogged` is set `true` at
    `one_pan_cooking_roadmap_screen.dart:414`, **before** the `try` block
    that contains the actual write — so it means "we started trying," not
    "the write succeeded." If `LedgerService.logCompletion()`'s
    `waste_ledger_events` insert throws (a network drop being the
    realistic case, though not the only possible one), the rescue is
    never recorded anywhere, the guard prevents any retry, and the
    outer `catch` in `_logCookSessionCompletion()` fails silently — no
    error shown to the user, per its own comment ("do not block their
    cook flow on a ledger error"). This is data loss on the app's core
    premise (rescuing ingredients from waste), not a cosmetic bug. Not
    fixed — report only, this session.

    **Likely fix shape, not designed**: split the single
    `_ledgerSessionLogged` guard into two separate states — one for
    "the ledger write completed," another for "the celebration sequence
    has been shown" — so a failed write can be retried (e.g. next time
    `_logCookSessionCompletion` is invoked, or via an explicit retry
    affordance) while the sheets themselves still only ever run once.
    Not scoped further than that.

    **Open contradiction in the 2026-08-15 report on this — flagged as
    unresolved, not investigated further, per explicit instruction.**
    That report stated two things that can't both be true: (a)
    `_appendWeeklyEvent` runs *before* the Supabase insert, has its own
    self-contained `try`/`catch`, and "can't itself abort the method" —
    implying its local `SharedPreferences` write already happened and
    survives regardless of what the Supabase insert does next; and (b)
    in the same report, "no weekly rollup" was listed among what's lost
    if the insert throws — implying the local write does *not* survive.
    Whether the local weekly-rollup record actually survives a failed
    Supabase insert is unresolved. It matters concretely: if it does
    survive, a retry only needs to re-attempt the Supabase write (cheap,
    the local data is already there); if it doesn't, a retry needs to
    reconstruct the full rescue record from scratch (harder). Needs an
    actual code trace before the fix above is scoped for real — not done
    here.

    **Standing pattern, not just this one bug.** This is the **second**
    confirmed instance of a `catch` block making a real failure look
    like a success from the outside: the first is `askChefHarris`
    swallowing its own network/request errors and returning a friendly
    fallback string, while `UsageCapService.increment(...)` still fires
    unconditionally at all four call sites regardless of whether the
    call actually reached OpenAI (Roadmap item 10, "Also pre-launch,
    added 2026-08-13"). Two different subsystems, same shape of bug:
    tracking/state that's supposed to reflect "did the real thing
    happen" instead just reflects "did we attempt it." Worth a review of
    swallow-and-continue error handling across this project **as a
    class**, not fixed one instance at a time as each is separately
    discovered. Not started.

    **Contradiction above — resolved 2026-08-16.** Traced
    `_appendWeeklyEvent` and the Supabase insert line by line: the local
    `SharedPreferences` weekly record **does** survive a failed Supabase
    insert — `_appendWeeklyEvent` runs first, completes (success or its
    own internally-swallowed failure) fully before the insert is even
    attempted, and nothing about the insert throwing later can undo a
    disk write that already happened. So "This Week" stays correct. What
    actually gets lost is narrower and arguably worse: the
    `waste_ledger_events` row itself, and therefore `user_ledger_totals`'s
    lifetime count (only updated via `trg_increment_ledger_totals`, which
    only fires on that specific insert succeeding) — a permanent,
    silent **local/server split** where "This Week" and "Lifetime" can
    disagree with no reconciliation. The original "no weekly rollup"
    claim in the first report on this item was wrong; corrected here
    rather than left standing.

    **Service/schema layer — IMPLEMENTED 2026-08-16.** Migration
    `supabase/migrations/20260816120000_add_waste_ledger_events_idempotency_key.sql`
    applied to the live project via `supabase db push` (pre-flight
    checked first: `authenticated`'s INSERT grant on `waste_ledger_events`
    is table-level, confirmed via `pg_attribute.attacl` being `null` on
    every column — no column-level ACL override that could have silently
    excluded the new column):
    ```sql
    alter table public.waste_ledger_events
      add column idempotency_key text;

    create unique index waste_ledger_events_idempotency_key_uidx
      on public.waste_ledger_events (idempotency_key)
      where idempotency_key is not null;
    ```
    Undo, if ever needed:
    ```sql
    drop index if exists public.waste_ledger_events_idempotency_key_uidx;
    alter table public.waste_ledger_events drop column if exists idempotency_key;
    ```
    Confirmed live after push: column is `text`, nullable; index is a
    partial unique index (`WHERE idempotency_key IS NOT NULL`) — existing
    rows keep `NULL`, only new inserts are constrained.

    Also implemented, same session: `PendingLedgerWriteService`
    (`lib/services/pending_ledger_write_service.dart`, SharedPreferences-
    backed, key `pending_ledger_writes_v1`); `LedgerService` restructured
    with a sealed `LedgerCompletionSuccess`/`LedgerCompletionWriteFailed`
    result and a three-way `try` boundary (insert, with `23505` treated
    as success; totals read-back, which cannot flip the result to
    failure); a `retryPendingWrite` method that checks the stored
    `user_id` against the current session before attempting anything
    (handles a stale uid from a post-reinstall anonymous re-auth) and is
    **not called from anywhere yet** — dead code until the next phase, no
    automatic trigger, no UI. `one_pan_cooking_roadmap_screen.dart`
    touched only at the `logCompletion()` call site to consume the new
    return type, behavior otherwise unchanged. See `test/services/`
    for the new unit tests. **Still not wired to anything user-facing**:
    no persistent affordance UI, no retry trigger, no automatic
    scheduling — those remain a distinct next phase, not started.

28. **Waste Ledger source accuracy, re-cook exclusion, and Finish & Plate
    skip-ahead — BUILT 2026-08-16.** Two connected changes, implemented
    together per Harris's explicit decisions (not re-opened/re-proposed
    here — this is a record of what was built).

    **Decision 1 — only fridge-originated cooks count as a rescue.**
    Followed up directly from the 2026-08-16 read-only investigation (see
    "Finding 1" earlier that session, not separately recorded in this doc
    until now): `_logCookSessionCompletion()`'s single `logCompletion()`
    call site had hardcoded `source: 'cook_mode'` regardless of entry
    path, and Recently Cooked re-entry carried zero marker distinguishing
    a re-cook from a fresh cook — both logged identically to a first cook.
    Fixed:
    - **`CookModeSurface` enum** (`one_pan_cooking_roadmap_screen.dart`,
      alongside `CookModeRecipePayload`) — `fridgeClearer`,
      `fridgeCountdown`, `customAiRecipeCreator`, `weeklyPlanner`, with
      `isRescueEligible` (true only for the first two — both generate a
      recipe directly from what's actually in the fridge; Custom AI
      Recipe Creator and Weekly Planner don't) and `ledgerSourceValue`
      (the real `waste_ledger_events.source` string for eligible
      surfaces, null otherwise — `logCompletion` is never called for
      non-eligible surfaces, so no value is ever needed).
    - **`CookModeLaunchRequest`** — new envelope type (recipe + surface +
      `isReCook`) replacing a bare `CookModeRecipePayload` as go_router's
      `extra` for every fresh (non-resume) Cook Mode launch. `surface` is
      nullable — null for Recently Cooked re-entry, where original
      provenance isn't tracked and doesn't matter, since `isReCook` alone
      already excludes it from logging.
    - **`ActiveCookSession`** (`cook_session_storage_service.dart`) gained
      `surface`/`isReCook` fields, threaded through
      `saveActiveSession`/`loadActiveSession`, so a session backgrounded
      mid-cook and resumed still logs (or doesn't) exactly as it would
      have without the interruption. Sessions saved before this item
      (no `surface` key in the persisted JSON) default to `surface: null`
      — never rescue-eligible, rather than guessing an origin that was
      never recorded.
    - **All 5 real entry paths updated**: `fridge_clearer_screen.dart`
      (`fridgeClearer`), `weekly_planner_screen.dart`'s single "open
      planned meal" push (`weeklyPlanner` — applies regardless of how the
      meal was originally added to the plan, matching Decision 1's "Weekly
      Planner... do not log" full stop), `generated_recipe_actions_sheet.dart`
      (shared by Fridge Countdown "Use Tonight" and Custom AI Recipe
      Creator — gained a new required `surface` constructor param, passed
      by its two callers as `CookModeSurface.fridgeCountdown` and
      `CookModeSurface.customAiRecipeCreator` respectively), and Home's
      `_openCookMode` (Recently Cooked tap → `isReCook: true, surface:
      null`; Resume Cooking banner → passes the `ActiveCookSession`
      through unchanged, carrying its own captured surface/re-cook state).
    - **Gating**: `_logCookSessionCompletion()` now computes `shouldLog =
      surface != null && surface.isRescueEligible && !isReCook` before
      ever calling `logCompletion()`.
    - **Migration**: `supabase/migrations/20260816130000_add_fridge_countdown_to_waste_ledger_source_check.sql`,
      applied via `supabase db push`, confirmed live via
      `pg_get_constraintdef`:
      ```sql
      alter table public.waste_ledger_events
        drop constraint waste_ledger_events_source_check;

      alter table public.waste_ledger_events
        add constraint waste_ledger_events_source_check
        check (source = any (array['fridge_clearer', 'cook_mode', 'custom_ai_recipe', 'fridge_countdown']));
      ```
      Undo, if ever needed:
      ```sql
      alter table public.waste_ledger_events
        drop constraint waste_ledger_events_source_check;

      alter table public.waste_ledger_events
        add constraint waste_ledger_events_source_check
        check (source = any (array['fridge_clearer', 'cook_mode', 'custom_ai_recipe']));
      ```
      `cook_mode` deliberately left in the constraint (not removed) —
      historical rows already use it; removing it wasn't part of this fix.

    **Decision 2 — Finish & Plate becomes a real skip-ahead control.**
    Follows directly from the 2026-08-16 investigation's "Finding 3":
    the button's render condition (`_recipeFinished`) and the last-step
    auto-fire were the same event, so there was no real window to press
    it. Fixed:
    - **Render condition changed**: Finish & Plate now also appears on
      `_CookPlayerBar` (the in-progress bar, alongside Pause/Next
      Step/Ask Chef) — reachable from any step during an active cook, not
      only once every step is ticked. Deliberately smaller/quieter
      (`TextButton`, muted color) than the routine-action buttons next to
      it, matching its rarer, more consequential nature. The original
      `_CookModeBottomBar` appearance (at `_recipeFinished`) is unchanged
      and still there too — combined, the control is now reachable
      throughout the entire `_cookStarted` lifetime. The existing
      last-step auto-fire itself is untouched.
    - **Confirmation added**: `_FinishAndPlateConfirmSheet` (new, modeled
      on `ConfidenceTierUpSheet`'s accept/decline pattern) — shown via a
      new shared `_confirmAndFinish()` method before the sequence ever
      fires. Wired to both the new mid-cook button and the existing
      `_CookModeBottomBar` button's not-yet-started branch (the
      already-started branch is pure recovery navigation per the existing
      Roadmap item 21 comment — nothing new fires there, so no
      confirmation needed). Its old ad-hoc "Nice work — plate up and
      enjoy" snackbar was removed as part of this — redundant now that a
      real confirmation gate sits in front of the same action.
    - On confirm: cancels the active timer, nulls `_activeStepIndex`
      (matching what the last-step auto-fire branch already does), then
      calls the same `_logCookSessionCompletion()` the last-step tick
      calls — genuinely the same completion sequence, not a parallel one.

    **How the sequence was decoupled from the ledger result (required
    check before this was allowed to proceed — see below).**
    `_logCookSessionCompletion()` restructured so `ledgerSuccess` (now a
    nullable local, `LedgerCompletionSuccess?`) only gates the Waste
    Ledger celebration sheet itself. Everything after it — What You
    Learned, the Confidence Climb evaluation + tier-up offer, the share
    card, the upgrade nudge, and navigation home — moved outside that
    condition and now runs unconditionally, whether the cook was
    non-eligible, a re-cook, or the write simply failed (a failed write
    now falls through instead of aborting the whole method — a small
    included fix beyond the letter of the ask, since "the sequence must
    not depend on a ledger result existing" applies equally to a failed
    attempt as to a skipped one, and the old abort-on-failure behavior
    meant a transient network error could already rob a legitimate Fridge
    Clearer cook of What You Learned and Home navigation). The share
    card's `ingredientsRescued` now reads `LedgerService.freshProduceOnly(_ingredients)`
    directly instead of `ledgerSuccess.ingredientsRescuedList`, so it
    renders identically regardless of whether a ledger write happened —
    same filtering logic `logCompletion` applies internally, just called
    directly rather than round-tripped through a ledger result.
    `_ledgerSessionLogged` (the guard/back-button/Weekly-Planner-completion
    signal) was renamed to `_cookSequenceStarted` throughout, since it now
    means "the post-cook sequence began," deliberately independent of
    whether the ledger portion of it succeeded.

    **Pre-check required before the restructure, done and reported before
    any code changed**: whether Confidence Climb's rep counting or What
    You Learned assume every step was completed (skipping steps could
    otherwise produce a wrong claim). Traced both directly —
    `ConfidenceClimbService.evaluate` operates purely on cook-history
    entries (`CookSessionStorageService.loadCookHistory()`) and each
    entry's `recipe.curriculumLessonIds`, a whole-recipe field set once
    at generation time; `WhatYouLearnedSheet`'s `ids` is
    `payload?.curriculumLessonIds` directly. Neither reads
    `_completedSteps`/`_activeStepIndex` at all. Cook-history population
    itself already happens in `initState` on Cook Mode **open** (via
    `_recordRecentlyCooked`/`_appendToHistory`), not on completion — so
    both were already fully decoupled from step completion before this
    item, and skipping steps via Finish & Plate introduces no new
    inaccuracy. Confirmed safe to proceed without design changes to
    either.

    **`flutter analyze`: 61 issues, unchanged from baseline** — no new
    issues introduced.

## Retention Features Backlog history — full original text (pre-2026-08-17)

Items 1, 2, and 4 (built) are fully closed. Items 3 and 5 (Sunday Reset, Ask Chef Harris Mid-Cook — on hold, decision deferred) were also extracted into `docs/DECISIONS.md` as binding "not yet" decisions. Everything below is the unedited original.

**Status as of 2026-08-11: items 1, 2, and 4 are built.** Harris explicitly
chose to build these ahead of the old "slot in after payment integration"
plan this session, while keeping all paywall/RevenueCat work (roadmap item
6) deliberately paused and untouched — don't read the code changes below as
implying that pause lifted. Items 3 and 5 remain explicitly on hold (see
below) — not just "not started yet," but a decision Harris hasn't made.

1. **Fridge Countdown — BUILT 2026-08-11.** New `fridge_items` table
   (`supabase/migrations/20260811130000_create_fridge_items.sql` — id,
   user_id, ingredient_name, added_date, estimated_shelf_life_days; RLS
   owner-only **plus explicit GRANTs**, applying the lesson from the
   `api_usage_daily` grants bug earlier this session so it wasn't repeated
   here — confirmed via `information_schema.role_table_grants` after push).
   `FridgeCountdownService` (`lib/services/fridge_countdown_service.dart`):
   CRUD against the table, plus a local keyword-based shelf-life estimator
   (same style as `LedgerService._pantryStapleKeywords`) that pre-fills the
   add-item form. `FridgeItem.isExpiringSoon` = 2 days or fewer remaining
   (including overdue). `FridgeCountdownSheet`
   (`lib/widgets/fridge_countdown_sheet.dart`): item list with a
   color-coded freshness bar per item (red/amber/green — deliberately
   separate semantic colors from the app's brand accent), an add-item
   mini-sheet, delete, and a "Use Tonight" button per item. "Use Tonight"
   builds an urgency-framed prompt (star ingredient, explicit "use it
   tonight/today" framing) and calls `ChefService.askChefHarris` directly
   (not the full `FridgeClearerScreen` UI — reused the same
   parse/curriculum-tag/`GeneratedRecipeActionsSheet` pattern already
   established by `CustomAiRecipeCreatorSheet`), gated under the **same**
   `UsageFeature.fridgeClearerGeneration` weekly cap as Fridge Clearer
   itself (deliberate — same marginal AI cost, avoids a cap-bypass
   loophole). Home dashboard: a terracotta "N items expiring soon" chip
   (`_FridgeCountdownChip`, `home_dashboard_screen.dart`) shown only when
   count > 0, placed right after the 6-action grid. **Compiles clean
   (`flutter analyze`: 0 errors), confirmed booting without runtime errors
   against the live Supabase project this session — not yet clicked
   through by Harris.**

   **Priority raised 2026-08-15**: completing live testing of this feature
   is now higher priority — do it sooner rather than whenever there's a
   lull. Also raised: "Use Tonight"'s recipe-variety gap (flagged, not
   fixed, in Roadmap item 13 — it shares Fridge Clearer's weekly cap and
   generates via `askChefHarris` directly but was never wired into the
   `RecentGenerationsService`/`recentDishTitles` variety fix built that
   session). Fix that alongside the live-testing pass, not as a separate
   later task.

   **Cold-start dead end — found 2026-08-15 during live device testing, not
   a hypothesis.** Grepped every call site of `FridgeCountdownService.addItem`
   and every `.insert()` into `fridge_items`: there is exactly **one**,
   inside `_AddFridgeItemSheetState._save()` — and that form is itself only
   reachable from inside `FridgeCountdownSheet`, which (confirmed the same
   day — only one entry point exists, the Home chip) only opens when
   `_expiringSoonCount > 0`. **A user with zero fridge items, or only fresh
   ones, can never open the sheet, and therefore can never reach the only
   form that creates a fridge item at all — a genuine chicken-and-egg dead
   end, not an edge case.** This is exactly why live-testing this feature
   couldn't be done this session — Harris hit it directly trying to seed a
   first item. Real fix shape, not yet designed: the Home entry point (or
   some entry point) needs to be reachable regardless of whether any item
   is currently expiring — e.g. a persistent (if lower-key) "Fridge" entry
   on Home rather than one gated entirely behind the urgency chip. Not
   fixed — flagging so it's understood as a structural gap, not just
   "not yet clicked through."

   **Product question, not a bug — do not resolve unilaterally, added
   2026-08-15.** Once inside the sheet, "Use Tonight" is enabled on every
   item regardless of freshness (confirmed by reading `_FridgeItemRow`:
   the button is only disabled while that item's own generation is
   in-flight, never gated on `isExpiringSoon`). The feature's entire
   framing is urgency ("use it tonight before it spoils") — an ungated
   action lets it be used on an item with three weeks of shelf life left,
   which undercuts that framing. Whether that's actually wrong (vs. just a
   convenience — urgency-framed language on a fresh item isn't harmful,
   just odd) is Harris's call, not a judgment to make here. Logged for a
   future decision, not queued as work.

2. **Confidence Climb — BUILT 2026-08-11.** Confirmed first that the
   kitchen-confidence prompt fix (difficulty rules reaching the AI) is
   still solid — verified directly in `chef_service.dart` while adding the
   prompt-size debugPrint earlier this session; unchanged. Turned out
   `curriculumLessonIds` (the technique-tagging this item asked for) was
   **already** flowing onto every `CookModeRecipePayload` at generation
   time, via `ChefService.matchedCurriculumDrawerKeys` — confirmed at all
   three generation call sites (Fridge Clearer, Custom AI Recipe Creator,
   Weekly Planner) and confirmed it round-trips through
   `CookSessionStorageService`'s cook history JSON (de)serialization. So
   **no new tagging logic was needed at all** — `ConfidenceClimbService`
   (`lib/services/confidence_climb_service.dart`) is pure aggregation over
   `CookSessionStorageService.loadCookHistory()` (the 20-entry rolling
   history, not just the 3-item Recently Cooked UI list). Two thresholds
   (both my call, both easy to retune — plain constants in the service):
   celebration line at **3+ reps of the same technique within the current
   calendar month** (e.g. "3rd time this month using Braising — you're
   building real knife + heat control."), tier-up offer at **5+ reps of
   ANY tagged technique** (broad kitchen mileage, not mastery of one move).
   Tier-up is gated one-time **per tier transition** (SharedPreferences
   flag keyed by the *current* tier name, so declining doesn't block a
   later, real offer for the *next* tier). Celebration line renders inside
   the existing `WhatYouLearnedSheet` (new optional `confidenceLine` param
   — the natural fit, since that sheet is already about techniques
   practiced) rather than a new sheet. Tier-up is its own step
   (`ConfidenceTierUpSheet`, `lib/widgets/confidence_tier_up_sheet.dart`,
   modeled directly on `UpgradePromptSheet`'s accept/decline pattern),
   shown after `WhatYouLearnedSheet` closes, updating
   `UserProfile.kitchenConfidence` via `UserProfileController.updateProfile`
   on accept. **Compiles clean, confirmed booting without runtime errors —
   not yet clicked through by Harris** (would need 3+ real cook-history
   entries with matched techniques in the current month to see the
   celebration line, or 5+ to see the tier-up offer).

   **Priority raised 2026-08-15**: completing live testing of this feature
   is now higher priority — do it sooner rather than whenever there's a
   lull, same reasoning as Fridge Countdown above.

3. **Sunday Reset — still on hold, decision explicitly deferred by Harris
   2026-08-11.** Originally gated on "recipe generation speed confirmed
   fixed." That investigation concluded this session (see Roadmap item 5):
   the honest floor is **~7-10s per generation**, `max_tokens` capping and
   the `gpt-4o-mini` trial didn't move it further, and the only real lever
   left (streaming) is a genuine future project, not a quick fix.
   Perceived-speed work shipped (rotating status card), but actual
   generation time is not going lower without that larger project. Harris
   has NOT yet decided whether ~7-10s × 5 batched calls (a real 35-50s
   wait) is acceptable for Sunday Reset — **do not start this until he
   explicitly says so**, even though the original blocking condition
   ("speed confirmed fixed") is technically now answered (just not
   answered *favorably*).

4. **Rescue Streaks / "Your Month" card — BUILT 2026-08-11** (Harris's
   session instructions renumbered this ahead of Sunday Reset/Mid-Cook;
   kept as backlog item 4 here since that's still its place in the
   original priority list). Deliberately NOT a visible streak counter and
   deliberately no framing around missed days/gaps — a positive recap, not
   a guilt mechanic, per Harris's explicit instruction. Pure aggregation,
   no new capture logic: `LedgerService` gained one new **read** method,
   `getMonthlyIngredientsRescuedCount()` — same local weekly-events store
   `getWeeklySummary()` already uses (90-day retention comfortably covers a
   month), just filtered by calendar month instead of week-start.
   "New techniques this month" and "most-cooked technique" are both
   computed by `YourMonthCard` (`lib/widgets/your_month_card.dart`)
   directly from `CookSessionStorageService.loadCookHistory()`'s
   already-tagged `curriculumLessonIds` (same data Confidence Climb uses —
   "new" = technique ids seen this month but not in any earlier history
   entry within the 20-entry cap; "most-cooked" = the technique with the
   most reps this month, title resolved via the existing
   `resolveDrawerEntry` helper). Note: the original backlog example said
   "most-cooked **category**," but there's no cuisine/category field
   anywhere in the actual data model — used "most-cooked **technique**"
   instead, the closest thing that's genuinely computable from existing
   data, rather than inventing new categorization logic. Dismissible via a
   SharedPreferences flag keyed by year-month (`your_month_dismissed_v1_
   YYYY-MM`), so it reappears fresh next month even if dismissed this one.
   Hides itself entirely (renders nothing) if there's nothing positive to
   report yet. Placed on Home right after the Fridge Countdown chip, before
   Technique of the Week. **Compiles clean, confirmed booting without
   runtime errors — not yet clicked through by Harris.**

5. **Ask Chef Harris Mid-Cook — still on hold, decision explicitly deferred
   by Harris 2026-08-11.** Same reasoning as Sunday Reset above: originally
   gated on confirmed-fast, ideally-streaming generation. The ~7-10s floor
   is now the confirmed, understood reality (not an open question anymore),
   but Harris hasn't decided whether that's acceptable for a feature that
   "needs to feel instant since it's used mid-task." **Do not start until
   he explicitly says so.**

## Design Polish Backlog history — full original text (pre-2026-08-17)

Items 1, 2, and 5 were already closed. Item 6 (the 18-site backgroundColor batch) is verified closed as of 2026-08-17 (see above). Item 4 (_sageBackground) is genuinely still open and lives in `CLAUDE.md`'s roadmap now. Item 3 (6-card grid rework) is still open and also lives in `CLAUDE.md`'s roadmap. Everything below is the unedited original.

Harris asked for a design/polish pass on 2026-08-11; findings were captured
but the actual visual changes were deliberately NOT made that session — a
clean punch list, not half-finished work. Re-verified against current
source on 2026-08-13 (not assumed from the 2026-08-11 write-up) as part of
a design-polish session — **items 1 and 2 turned out to already be fixed**,
and **item 4's root cause turned out to be the reverse of what was
originally written down**. Per this project's own working convention
("verify current state, don't assume regression, don't assume the
documented fix is stale") — check before concluding either way, which is
exactly what caught both of these. No `claude-in-chrome` available on
2026-08-13 either — nothing here has a before/after screenshot yet.

1. ~~**Technique of the Week card shows raw drawer text, not a teaser.**~~
   **CLOSED 2026-08-13 — already fixed, verified against current source.**
   `_TechniqueOfTheWeekCard` (`home_dashboard_screen.dart`) shows only
   `entry.title` (e.g. "Simmering") — not raw drawer text. Tapping it opens
   `_TechniqueOfTheWeekSheet`, which renders `DrawerCard(entry: entry,
   initiallyOpen: true)` from `lib/widgets/curriculum_drawer_content.dart` —
   exactly the teaser + tap-to-expand `FormattedDrawerBody` pattern this
   item asked for, reusing `_parseDrawer`/`DrawerCard` exactly as
   instructed. Nothing to do here. (Exact timing of the fix isn't
   determinable — this repo has a single squashed initial commit, no finer
   git history to check — but the code is unambiguously correct now.)
2. ~~**Technique of the Week card has no green accent.**~~ **CLOSED
   2026-08-13 — already fixed, verified alongside item 1.** Both
   `_TechniqueOfTheWeekCard` and `_TechniqueOfTheWeekSheet` already use
   `AppDesignTokens.deepForest` (via `HomeDashboardScreen._deepForest`) for
   the icon background, icon color, and card border. Nothing to do here.
3. **Home dashboard 6-card grid feels flat/corporate — still open, needs a
   proposal before implementing (real visual direction, not mechanical).**
   Small icon-in-a-box on uniform cream, one generic description line each
   ("Plan Mon–Sun & export shopping lists"). Two independent angles Harris
   flagged, either or both worth trying: (a) larger/bolder icons, and/or a
   subtle colored background wash on 1-2 of the most-used cards (Fridge
   Clearer, Weekly Plan & Shop) instead of uniform cream, for visual
   hierarchy; (b) rewrite the generic description copy into shorter lines
   with more of Chef Harris's established personality, without making the
   functional copy confusing (people still need to know what tapping the
   card does).
4. **Home's background — not onboarding's — is the actual mismatch. Root
   cause reversed from the original 2026-08-11 write-up; still open,
   mechanical, pre-approved to fix next session.** Original framing:
   "onboarding doesn't match Home, point onboarding at `backgroundSage`."
   **That was backwards.** Verified 2026-08-13: `onboarding_screen.dart`'s
   `Scaffold` already correctly uses `AppDesignTokens.backgroundSage`
   (`#E8EFEA`) — confirmed via `nav.dart` that `OnboardingScreen` is the
   single real routed onboarding screen, no duplicate. The actual outlier is
   `home_dashboard_screen.dart:237`: `Scaffold(backgroundColor:
   HomeDashboardScreen._sageBackground, ...)`, where `_sageBackground` is a
   **separate, private, hardcoded** `Color(0xFFC5D3C1)` (line 39) — visibly
   darker/more saturated than the real `backgroundSage` token, not a
   near-identical rounding difference. `_sageBackground` is used exactly
   once in the file (only that Scaffold), so there's no other intentional
   use of the darker shade to preserve. Fix: delete the private
   `_sageBackground` constant and reference `AppDesignTokens.backgroundSage`
   directly at line 237, matching onboarding (and everywhere else). Net
   effect: Home's background gets *lighter* to match the shared token —
   the opposite direction from what the original item description implied.
5. **Post-cook share card (`PostCookShareCardSheet`) color sourcing —
   CHECKED 2026-08-13, confirmed correct, no fix needed.** Its root
   `build()` returns `Material(color: AppDesignTokens.surfaceCream, ...)` —
   real token, not hardcoded. The bold dark-green gradient itself (a nested
   preview card inside that cream sheet, not the sheet's own background) is
   `colors: [AppDesignTokens.deepForest, Color(0xFF14261B)]` — the first
   stop is the real token as suspected; the second stop is a deliberately
   darker, hand-picked shade to give the gradient somewhere to go, which is
   normal for a two-stop gradient and doesn't need to itself be a design
   token. **Don't change anything here** — this is exactly the "don't
   change the visual approach" case, and the token-sourcing question this
   item asked comes back clean.
6. **Bottom-sheet background falls back to an unstyled default — scope was
   wrong in the original write-up. It's not 2 sheets, it's 18 call sites
   across 8 files. Mechanical, pre-approved, ready to run next session —
   see the full list below.** Root cause (confirmed 2026-08-11, still
   accurate): `AppBottomSheet.show(...)` defaults its `backgroundColor` to
   `theme.colorScheme.surface` (plain white/grey) when the caller doesn't
   pass one — and even when the sheet's own inner widget correctly wraps
   itself in `Material(color: AppDesignTokens.surfaceCream, ...)`, that
   only covers the inner content; the outer modal chrome (rounded corners,
   edges, drag-handle area) still shows the unstyled default around/behind
   it. The original write-up flagged only `UpgradePromptSheet` and
   `_ChefSuggestionSheet` and left "grep the rest" as a suggestion for next
   time. **That grep is now done** (2026-08-13, read-only — no edits made,
   per the "no code changes tonight" instruction this was captured under).
   Full result: **18 of the app's ~20 `AppBottomSheet.show` call sites omit
   `backgroundColor` entirely.** All 18 are missing it for the same reason
   (never set, not a deliberate choice) and all 18 want the same fix:
   `backgroundColor: AppDesignTokens.surfaceCream`. Verified each target
   sheet's own root widget individually first, specifically to rule out any
   sheet that might deliberately want a *different* color (like a dark
   sheet) — none do; every one of the 18 either has no color wrapper at all
   (bare `Padding`/`SafeArea`/`AnimatedPadding` — cream would be the
   *effective* background either way) or already wraps in
   `Material(color: AppDesignTokens.surfaceCream, ...)` itself (cream is
   just missing from the outer chrome). By file:
   - `lib/widgets/upgrade_prompt_sheet.dart:22` — `UpgradePromptSheet`
     (original item, has its own cream `Material`)
   - `lib/screens/home_dashboard_screen.dart:63` — `_ChefSuggestionSheet`
     (original item, no color wrapper at all)
   - `lib/screens/home_dashboard_screen.dart:72` — `_TechniqueOfTheWeekSheet`
     (has its own cream `Material` — newly found; postdates the original
     2-item write-up)
   - `lib/screens/home_dashboard_screen.dart:145` — `FridgeCountdownSheet`
     (no color wrapper)
   - `lib/screens/home_dashboard_screen.dart:210` — `_RecentlyCookedSheet`
     (no color wrapper)
   - `lib/screens/fridge_clearer_screen.dart:369` — `WeekdayPickerSheet`
     (no color wrapper)
   - `lib/widgets/fridge_countdown_sheet.dart:61` — `_AddFridgeItemSheet`
     (no color wrapper)
   - `lib/widgets/fridge_countdown_sheet.dart:287` — `GeneratedRecipeActionsSheet`
     (reused here; has its own cream `Material`, see next entry)
   - `lib/widgets/generated_recipe_actions_sheet.dart:111` —
     `WeekdayPickerSheet` (nested "Plan for which day?" picker; no color
     wrapper)
   - `lib/screens/one_pan_cooking_roadmap_screen.dart:421` —
     `WasteLedgerCelebrationSheet` (has its own cream `Material`)
   - `lib/screens/one_pan_cooking_roadmap_screen.dart:445` —
     `WhatYouLearnedSheet` (has its own cream `Material`)
   - `lib/screens/one_pan_cooking_roadmap_screen.dart:475` —
     `PostCookShareCardSheet` (has its own cream `Material` — see item 5;
     do NOT touch its nested dark gradient preview card, only the outer
     `AppBottomSheet.show` chrome)
   - `lib/screens/one_pan_cooking_roadmap_screen.dart:677` — `_ChefSosSheet`
     (no color wrapper)
   - `lib/screens/profile_screen.dart:357` — `_SecureAccountSheet` (no
     color wrapper)
   - `lib/screens/weekly_planner_screen.dart:106` — `_AddMealOptionsSheet`
     (no color wrapper)
   - `lib/screens/weekly_planner_screen.dart:276` —
     `CustomAiRecipeCreatorSheet` (no color wrapper)
   - `lib/screens/weekly_planner_screen.dart:832` —
     `_DealMealSuggestionSheet` (no color wrapper)
   - `lib/widgets/confidence_tier_up_sheet.dart:25` —
     `ConfidenceTierUpSheet` (has its own cream `Material`)

   **Deliberately excluded from this batch fix — do NOT add
   `backgroundColor: surfaceCream` to these**, confirmed intentional:
   - `home_dashboard_screen.dart:88`, `:101-107`, `:191-197` — three
     `GeneratedRecipeActionsSheet`/related call sites that already pass
     `backgroundColor: isDark ? theme.colorScheme.surface :
     LightModeColors.lightWarmCreamSurface` — correctly dark-mode-aware,
     just via a different token name than the rest of the app. Leave as is.
   - `weekly_planner_screen.dart:878` — passes `backgroundColor:
     Colors.transparent` on purpose, per its own comment ("Keep the modal
     container consistent with the app's primary card surfaces" — its
     content draws its own full background). Leave as is.

   Fix shape for all 18: add `backgroundColor: AppDesignTokens.surfaceCream`
   to each `AppBottomSheet.show(...)` call. Purely additive — one named
   parameter on an already-working call, can't change behavior, only the
   chrome color — genuinely mechanical, no visual-direction judgment
   needed. Check `AppDesignTokens` is imported before editing (as of
   2026-08-13, NOT yet imported in: `fridge_countdown_sheet.dart`,
   `one_pan_cooking_roadmap_screen.dart`, `generated_recipe_actions_sheet.dart`
   — add the import alongside the fix in those three).

### Next session starts here

**Priority lowered 2026-08-15**: this batch is mechanical, pre-approved,
and still worth doing, but it's no longer next up — the safety validator
(Roadmap item 15) and finishing live-testing on Fridge Countdown/Confidence
Climb (Retention Features Backlog items 1-2) take priority now. Revisit
once those land.

- **The 18-site `backgroundColor` batch fix above is pre-approved and ready
  to run** — purely mechanical, no proposal needed, just do it (verify with
  `flutter analyze` after, same as any other session).
- **Item 4** (Home's `_sageBackground` → `AppDesignTokens.backgroundSage`)
  is also pre-approved and mechanical — bundle it with the batch fix above.
- **Item 3** (home dashboard grid feels flat/corporate) is real visual
  direction — write up a proposal and show Harris where you're taking it
  *before* touching any code, per his explicit instruction from the
  2026-08-13 session.
- Items 1, 2, and 5 are closed/confirmed — no action needed.

## Pluralization Audit — full original text (pre-2026-08-17, verified closed 2026-08-17, see above)

Triggered by Harris spotting "1 ingredients rescued so far" on Home.
Audited every count-driven interpolated string in `lib/` (not just that one
instance) via a full-codebase grep for `$variable` immediately followed by
a plural noun, cross-checked against every spot that already handles this
correctly (the `${count == 1 ? '' : 's'}` pattern, used consistently in
`fridge_countdown_sheet.dart`, `post_cook_share_card.dart`,
`your_month_card.dart`, and one line of `home_dashboard_screen.dart` itself
— so the correct pattern already exists in this codebase, it's just not
applied everywhere). Read-only audit — no fixes applied yet tonight.

**3 genuine bugs** (wrong today, will show incorrect grammar for real users
at count=1 — not hypothetical):
1. `lib/screens/home_dashboard_screen.dart:320` —
   `'$_weeklyIngredientsRescued ingredients rescued so far.'` — the exact
   string Harris spotted.
2. `lib/screens/home_dashboard_screen.dart:458` — `'Lifetime: $lifetimeCount
   ingredients rescued'`.
3. `lib/widgets/waste_ledger_celebration_sheet.dart:78` — `'Lifetime:
   $lifetimeIngredientsRescued ingredients rescued'` — highest-visibility of
   the three: every new user's very first-ever rescue will show "Lifetime: 1
   ingredients rescued" the first time they ever see this sheet.

**1 stylistic inconsistency** (not grammatically broken, but inconsistent
with the correct pattern used elsewhere in the very same file):
- `lib/screens/home_dashboard_screen.dart:420` — `'$weeklyCount
  ingredient(s) rescued so far this week.'` — the "(s)" placeholder style
  instead of true singular/plural. Reads oddly ("1 ingredient(s)") rather
  than being outright wrong. Worth conforming to the real pattern while in
  this area.

**4 latent risks** (correct today only because their constants currently
happen to be ≥2 — would silently break if ever tuned to 1, e.g. during
pricing/limit A/B testing):
- `lib/screens/fridge_clearer_screen.dart:527` — "...$kFridgeClearerFreeWeeklyLimit
  Fridge Clearer generations a week..." (`kFridgeClearerFreeWeeklyLimit = 3`)
- `lib/widgets/fridge_countdown_sheet.dart:239` — same constant, "...fridge-rescue
  generations a week..."
- `lib/screens/home_dashboard_screen.dart:1263` — "...$kChefHarrisChatFreeDailyLimit
  Chef Harris suggestions a day..." (`kChefHarrisChatFreeDailyLimit = 5`)
- `lib/widgets/custom_ai_recipe_creator_sheet.dart:239` — "...$kCustomAiRecipeCreatorFreeLifetimeUses
  free tastes..." (`kCustomAiRecipeCreatorFreeLifetimeUses = 2`)

**Confirmed a false positive while auditing**: `fridge_countdown_sheet.dart:432`
(`'$d days left'`) looked suspicious in isolation but is actually guarded
correctly — `d == 1` is handled by an explicit branch (`'1 day left'`)
immediately above it, so the plural branch only ever executes for d != 1.
No fix needed there; flagging so it isn't "rediscovered" as a bug next time
someone greps this file.

**Also found, out of UI scope**: `lib/services/ai_recipe_service.dart:167`
and the near-identical `'$portions people'` lines in
`fridge_clearer_screen.dart:226`, `custom_ai_recipe_creator_sheet.dart:217`,
`fridge_countdown_sheet.dart:222` all hardcode "people" regardless of count
— but these are AI *system-prompt* text (recipe-generation instructions
sent to OpenAI), never rendered in the UI. Not a user-visible bug; not
worth fixing.

Fix for all 8 real items (3 bugs + 1 inconsistency + 4 latent risks): same
one-line ternary pattern already used correctly elsewhere in this codebase
— `'${count} noun${count == 1 ? '' : 's'}'`. Purely mechanical, pre-approved,
not yet applied.

**Priority lowered 2026-08-15**: still mechanical and pre-approved, but no
longer next up — see the same note under Design Polish Backlog's "Next
session starts here" above (superseded by the safety validator and
Fridge Countdown/Confidence Climb live-testing).

## Supabase RLS status — full original text incl. audit trail (pre-2026-08-17)

A condensed, current per-table summary now lives in `CLAUDE.md`. The full audit narrative below (including the VERIFIED/WRONG/UNVERIFIED trail) is preserved here unedited.

**POLICY definitions below were freshly re-queried 2026-08-15 via
`pg_policies` and are accurate as of that date.** Two things changed from
the previous version of this section: `ai_precision_cache`'s "zero
client-facing policies" claim was corrected earlier the same day (see
Roadmap item 16), and this pass additionally found **table-level GRANTS
that don't match policy intent on 3 more tables** (`ingredients`,
`user_ledger_totals`, `recipes`) — see the audit note below the list. Policy
definitions and grants are two independent things to check, not one — this
project has now found mismatches between them four separate times
(`api_usage_daily` 2026-08-11, `api_call_cost_log` 2026-08-13,
`ai_precision_cache` 2026-08-15, and this same-day pass). Treat "RLS
enabled" or "has a policy" as necessary, never sufficient — always check
`information_schema.role_table_grants` too.

- `user_profiles` — owner-only via `id = auth.uid()`. Policy confirmed
  correct. **Grants broader than the policy needs**: `anon` has full
  SELECT/INSERT/UPDATE/DELETE, not just `authenticated`. Not currently
  exploitable for cross-user access — the policy's `auth.uid() = id` check
  still requires a real match, and `auth.uid()` is `NULL` for a caller with
  no session, which never equals a real `id` — but it's a least-privilege
  violation worth tightening (`anon` shouldn't need write access here at
  all; this app's anonymous users are still `authenticated`-role sessions,
  not bare `anon`).
- `user_meal_plans` — owner-only via `user_id = auth.uid()`. Policy and
  grants both confirmed correctly aligned — `anon` has no write grant here,
  `authenticated` has exactly what its policies need. No issue.
- `shopping_list_items` — owner-only via `user_id = auth.uid()`. Policy and
  grants both confirmed correctly aligned, same as above. No issue.
- `waste_ledger_events` — owner-only via `user_id = auth.uid()`
  (pre-existing). Policy confirmed correct. Same grants-too-broad pattern
  as `user_profiles`: `anon` has full CRUD grants it doesn't need. Same
  "not currently exploitable, still worth tightening" caveat.
- `user_ledger_totals` — policy confirmed **SELECT-only**, owner-scoped
  (`user_id = auth.uid()`) — the "read-only" framing is correct for what
  the policy allows. **Fixed 2026-08-15.** Had the same structural gap as
  `ai_precision_cache`: `anon`/`authenticated` held table-level INSERT/
  UPDATE/DELETE grants with zero policy covering those commands — inert,
  but one accidentally-added permissive policy away from becoming live
  writes. **Before revoking, checked what actually writes this table**:
  `user_ledger_totals` is written exclusively by `increment_ledger_totals()`,
  a trigger (`trg_increment_ledger_totals`, `AFTER INSERT` on
  `waste_ledger_events`) — confirmed via `pg_get_functiondef` that it's
  `SECURITY DEFINER`, owned by `postgres`, so it runs with elevated
  privileges regardless of the invoking role and needs no direct grant
  from `authenticated` at all. Real users only ever need (and keep) their
  own owner-scoped access to `waste_ledger_events` — confirming this
  before revoking mattered, since guessing wrong here would have silently
  broken Waste Ledger writes for real users, the same class of mistake
  this whole audit was started to catch. Ran, with explicit approval:
  `revoke insert, update, delete on public.user_ledger_totals from anon, authenticated;`
  — confirmed after: `anon`/`authenticated` now hold only REFERENCES/
  SELECT/TRIGGER/TRUNCATE, `service_role` unaffected. Undo, if ever
  needed: `grant insert, update, delete on public.user_ledger_totals to anon, authenticated;`
- `recipes` — policies confirmed exactly as documented: owner-only
  (`auth.uid() = user_id`) for SELECT/INSERT/UPDATE/DELETE, plus public
  SELECT where `user_id IS NULL`. **But `authenticated` only holds a
  SELECT grant on this table — no INSERT/UPDATE/DELETE grant at all.**
  This means the owner-write policies are currently **unreachable** via the
  Data API — a signed-in user cannot actually insert/update/delete their
  own recipe row today, regardless of what the policy allows, because the
  grant layer blocks it first. Confirmed via `grep` that no Dart code
  anywhere references `.from('recipes')` — so nothing has ever hit this
  wall and surfaced it as a bug; it's likely why the table has stayed
  empty (see "Current architecture facts" above) rather than evidence the
  feature was tried and worked. This table appears to be entirely
  dead/unused client-side right now, not actively broken. **Not fixed —
  left alone deliberately** (revoking further would be pointless when the
  real gap is a missing grant, not an excess one) — see the new "Save if
  you liked it" Roadmap item for the warning this blocks.
- `ingredients` — SELECT-only policies confirmed (3 redundant ones, see
  below), matching the "public read-only catalog" framing **for what RLS
  actually allows**. **Fixed 2026-08-15**: `anon`/`authenticated` held full
  INSERT/UPDATE/DELETE grants with zero policy permitting those commands —
  the "no client writes" claim was only true by accident of the policy
  layer. Confirmed via `grep` that nothing client-side writes to this
  table (every reference is `.select()`) before revoking. Ran:
  `revoke insert, update, delete on public.ingredients from anon, authenticated;`
  (SELECT retained — the client reads this table constantly). Confirmed
  after: `anon`/`authenticated` now hold only REFERENCES/SELECT/TRIGGER/
  TRUNCATE. Undo, if ever needed:
  `grant insert, update, delete on public.ingredients to anon, authenticated;`
- `ai_precision_cache` — **fixed 2026-08-15.** Had RLS enabled with 0
  policies (correctly deny-all) but `anon`/`authenticated` incorrectly held
  full CRUD grants (see Roadmap item 16 for the full audit trail — the
  earlier "zero client-facing policies at all... server-only" framing in
  this doc was wrong, corrected there). Ran, with explicit approval:
  `revoke select, insert, update, delete on public.ai_precision_cache from anon, authenticated;`
  — re-queried `information_schema.role_table_grants` immediately after:
  `anon`/`authenticated` now hold only REFERENCES/TRIGGER/TRUNCATE,
  `service_role` retains full CRUD. Now matches `api_call_cost_log`'s
  clean pattern exactly. Undo, if ever needed:
  `grant select, insert, update, delete on public.ai_precision_cache to anon, authenticated;`
- `api_call_cost_log` (added 2026-08-13) — re-confirmed clean 2026-08-15,
  used as the control table while investigating the above: RLS enabled,
  zero `authenticated`/`anon` policies, and — checked directly this
  session — `anon`/`authenticated` correctly hold **no** SELECT/INSERT/
  UPDATE/DELETE grants either (only harmless REFERENCES/TRIGGER/TRUNCATE).
  Only `service_role` has real INSERT/SELECT, exactly as the 2026-08-13 fix
  intended. **This is the one table where policies and grants are both
  provably correct together** — useful as a reference for what "done
  right" looks like when fixing the others. **Important nuance confirmed
  live 2026-08-13**: `service_role`'s `bypassrls` attribute only skips RLS
  *policies* — it does NOT grant table-level SQL privileges on its own.
  The initial migration correctly locked out `authenticated`/`anon` but
  forgot to explicitly grant `service_role` INSERT/SELECT, so the
  `ask-chef-harris` edge function's writes silently failed for one round of
  live testing (5 real generations, 0 rows landed) before a follow-up
  migration (`20260813130000_fix_api_call_cost_log_service_role_grants.sql`)
  fixed it.

Note: there are duplicate/redundant policies on a few tables (both an old
broad "ALL" policy and newer granular per-command policies covering the same
thing) left over from iterative fixes — **confirmed real 2026-08-15** via
direct `pg_policies` query: `user_profiles` (3 duplicate pairs), `ingredients`
(3 redundant SELECT policies), `shopping_list_items` and `user_meal_plans`
(each has both a broad `ALL` policy and separate per-command policies
covering the same ground). Harmless — permissive policies OR together — but
worth cleaning up for hygiene when there's a lull.

There is no `deals` table in the actual database — code has a speculative,
gracefully-failing lookup for one (`paywall_screen.dart`-era code, see actual
class names once verified in this repo) that falls back to inferring deals
from `ingredients.badge`. Not a bug, just worth knowing so it isn't
"discovered" again as a missing table.

### Full RLS/grants verification audit — 2026-08-15

Triggered by finding two wrong claims in this doc the same day (Weekly
Planner's `RecentGenerationsService` coverage, and `ai_precision_cache`'s
grants) — both had been written from assumption and never actually checked
against the live project. Went through every claim in this doc about RLS,
grants, policies, Data API exposure, auth, edge function config, and usage
caps, and checked each one directly (`pg_policies`,
`information_schema.role_table_grants`/`role_routine_grants`, actual edge
function source, actual SDK source in the local pub cache) rather than
trusting the existing text. Full row-count table + methodology lives in
session notes; net result folded into the corrected sections above and into
Roadmap item 16. Nothing was fixed as part of this audit — verification
only, no `REVOKE`/`GRANT` run, no code changed.

**VERIFIED (checked directly this session or a prior one with real, still
re-confirmed evidence):**
- `ask-chef-harris` has `verify_jwt = true` in `supabase/config.toml`,
  matching the live deployed function config (`supabase functions list`).
- `ai-recipe-precision` has `verify_jwt: false` (same source).
- `ask-chef-harris`'s actual source (read directly, not assumed): no
  client-facing API key, generic proxy forwarding `systemPrompt`/
  `userMessage` unmodified, model whitelist enforced
  (`['gpt-4o','gpt-4o-mini']`), `max_tokens: 1200`, decodes `user_id` from
  the JWT `sub` claim trusting `verify_jwt`'s prior validation (documented
  in the function's own code comment), writes `api_call_cost_log` via
  `SUPABASE_SERVICE_ROLE_KEY`.
- `api_usage_daily`: `authenticated` has SELECT/INSERT/UPDATE +
  `EXECUTE` on `increment_api_usage`; `anon` has none of those — matches
  the documented 2026-08-11 fix, re-confirmed live today.
- `fridge_items`: policies and grants both confirmed correctly aligned,
  `anon` correctly excluded.
- `user_meal_plans`, `shopping_list_items`: policies and grants both
  confirmed correctly aligned.
- `recipes` table confirmed still empty (0 rows).
- `EntitlementService.isPro()`: `if (kDebugMode) return true;` confirmed
  at the top of the method, before any RevenueCat/mock check — matches the
  documented debug-bypass design.
- `UsageCapService.getUsageCount(...)`: confirmed `catch (e) { ...; return
  0; }` — matches the documented fail-open design.
- Duplicate/redundant policies claim — confirmed real (see above).
- The general claim "RLS policies and table-level grants are two separate
  Postgres mechanisms" (Roadmap item 11 follow-up) — confirmed true, and
  this entire audit is built on that mechanic holding.

**WRONG (found and corrected this session):**
- `ai_precision_cache` — "zero client-facing policies at all... server-only"
  undersold it: `anon`/`authenticated` hold full CRUD grants, currently
  inert only because RLS has zero policies. Corrected in Roadmap item 16.
- `ingredients` — "no client writes" was only true by accident of the
  policy layer; the grants say otherwise. Corrected above.
- `user_ledger_totals` — "owner read-only" undersold it the same way as
  `ai_precision_cache`: correct for what the policy allows, silent about
  inert-but-present write grants. Corrected above.
- `recipes` — the policy description was accurate, but missing entirely:
  that the write policies are unreachable today because `authenticated`
  lacks the INSERT/UPDATE/DELETE grants the policies assume exist.
  Corrected above.
- Weekly Planner Deal Meal `RecentGenerationsService` coverage (found and
  corrected same day, see Roadmap item 19's correction note) — not a
  permissions claim, but flagged here too since it's the other wrong claim
  that triggered this whole audit.

**UNVERIFIED (still written as fact elsewhere in this doc, not re-checked
this session — flagging rather than assuming either way):**
- The original (2026-08-06 and earlier) claims that Storage bucket
  policies, rate limiting on Edge Functions, and dev/prod project
  separation are outstanding pre-launch items (Roadmap item 10) — not
  re-checked, no reason to doubt them, just not independently confirmed
  this session.
- `ai-recipe-precision`'s own internal logic beyond what was read directly
  in Roadmap item 16 (e.g. whether `OPENAI_API_KEY`/`SUPABASE_SERVICE_ROLE_KEY`
  secrets are actually set correctly in that function's environment, vs.
  just referenced in code) — code reads the env vars and throws if missing,
  but whether they're actually configured wasn't independently checked.
- Whether any Storage buckets exist yet with their own RLS-equivalent
  policies — out of scope for this pass (no Storage usage found in the
  code, consistent with "once profile photos/recipe images are added"
  framing in Roadmap item 10, but not actively re-verified).

## Curriculum content strategy (decided 2026-08-10) — video/photo portions SUPERSEDED 2026-08-17

Reviewed 2026-08-17 for anything in this section that wasn't specifically
about video or photography. **Two decisions survive and are not
superseded** — moved to `docs/DECISIONS.md` under "Techniques & Media hub —
content strategy": (1) primary teaching emphasis stays on text + timing
inside Cook Mode, the browsable hub is supplementary; (2) no
vector/animated diagrams for now (distinct from the new decision to build
*static* SVG diagrams — that doesn't reopen this one). Everything else
below — real still photos, the `externalVideoUrl` field, and the
photo/video presence-handling requirement on `TechniqueLesson`/
`TechniquesMediaScreen` — was specifically about video/photography and
**is** superseded by the "Visual assets — drawn diagrams, not
photographs" decision in `docs/DECISIONS.md` (per
`docs/decisions_2026-08-17.md` item 4): no photos, no video, deterministic
SVG diagrams instead. Full original text preserved below unedited, for the
record of what was decided 2026-08-10 and why.


`CurriculumLibrary` (the browsable Techniques & Media hub content — see
"Current architecture facts" above for how this is a completely separate
system from the `chefTechniqueDrawers`/`chefReferenceDrawers` AI-facing
curriculum) was originally shaped as video-first: every `TechniqueLesson`
had a `videoUrl` + `thumbnailUrl`. **Nothing real has ever shipped there —
all 8 entries still used placeholder `example.com` URLs** — so this is a
clean redirect, not walking back a real feature. Decided with Harris
2026-08-10:

- **Primary emphasis stays on text + timing inside Cook Mode itself.**
  That's the actual differentiator — "we tell you why, in the moment, with
  a timer" — not a video library. The Techniques & Media hub is a
  supplementary browsing surface, not where the app's teaching value lives.
- **Where a technique genuinely benefits from a visual, support a short
  sequence of real still photos (3-5 per technique)** instead of video.
  `TechniqueLesson.photoUrls` (`List<String>`) is now the first-class visual
  field — not a video-only shape with photos bolted on.
- **Leave room for an optional external link field** (`externalVideoUrl` on
  `TechniqueLesson`) to curate a real creator's video later, but don't build
  any content for it now — that's a future manual-curation task for Harris,
  not something to scaffold placeholder content for.
- **No vector/animated diagrams for now.** That needs a freelance motion
  designer — out of scope for this phase, revisit only if/when that's
  commissioned.
- `TechniqueLesson` and `TechniquesMediaScreen` must handle a lesson having
  photos, a link, both, or neither — falling back to text-only (title +
  description + breakdown steps) rather than assuming video/photos are
  always present. All 8 current `CurriculumLibrary` entries currently have
  neither (no real photos shot yet, no creator video curated yet) and
  should render correctly in that all-text state.

## Original "What this is" + "Current architecture facts" — full original text (pre-2026-08-17)

A condensed, current version of both sections now lives in `CLAUDE.md`. The full original text, including historical narrative that was trimmed out of the condensed version (CLI discovery/confirmation history, specific bug-fix dates), is preserved here unedited.

# OptiMeal — Project Context for Claude Code

## What this is

OptiMeal is a zero-waste, technique-first cooking app with an AI persona called
"Chef Harris." Swiss-first launch, European/global ambitions later. Built with
Flutter/Dart, Supabase (Postgres + Auth + Edge Functions), GoRouter, Provider.
Has a live paywall. Approaching real-tester stage.

This project was previously built and iterated on entirely inside **Dreamflow**
(an AI app-builder chat interface) and has just been exported into this repo so
work can continue with Claude Code directly. That means:

- File names in this repo *should* now match their actual class names, since
  they came from a real export rather than Dreamflow's chat-upload flow. The
  previous working environment had a known, confirmed, permanent quirk where
  uploaded filenames were shuffled and did not match file content (e.g. a file
  named `profile_screen.dart` might actually contain `CulinaryMasterclassScreen`).
  **Verify this is no longer the case** by spot-checking a few files early on —
  if filenames still don't match content, treat that the same way: always
  locate code by class name / content, never trust the filename alone.
- There is no established "single Dreamflow prompt" formatting constraint here.
  Claude Code can just read files, edit them directly, and run `flutter analyze`
  / tests. Work normally — no need to produce paste-able prose blocks.
- **Correction (2026-08-10): the Supabase CLI on this dev machine is already
  authenticated to the live project** (`supabase projects list` returns it;
  ref `xwugnhzlnfgmczkbbcbh`) — it was just never linked to this repo before.
  `supabase link --project-ref xwugnhzlnfgmczkbbcbh` then `supabase db push`
  **was confirmed working this session**: applied both pending migrations
  (`20260728120000_create_user_profiles.sql`,
  `20260810120000_create_api_usage_daily.sql`) directly to the live database,
  verified after via `supabase migration list` showing matching local/remote
  timestamps. So Postgres migrations no longer need manual Dashboard SQL
  Editor paste-and-run — link once, then `supabase db push` going forward.
  (A third migration, `20260811120000_fix_api_usage_daily_grants.sql`, was
  pushed the same way 2026-08-11 — see "Follow-up bug found and fixed
  2026-08-11" in the monetization section below for what it fixed.)
  Always check `supabase migration list` before pushing (idempotent
  `IF NOT EXISTS`/`DROP ... IF EXISTS` guards make re-applying safe, but
  still confirm what's actually pending first) — and per the general
  "hard to reverse / affects shared systems" rule, confirm with Harris
  before pushing schema changes to production, same as any other prod DB
  write. **Confirmed working (2026-08-11)**: `supabase functions deploy
  <name> --project-ref xwugnhzlnfgmczkbbcbh --use-api` deploys Edge
  Functions directly, no Dashboard paste-and-run needed. The `--use-api`
  flag is required on this machine — plain `supabase functions deploy`
  fails because it defaults to a Docker-based bundler and this machine has
  no Docker/Podman installed; `--use-api` bundles server-side instead.
  Verified via `supabase functions list --project-ref xwugnhzlnfgmczkbbcbh`
  showing `version` incremented and `updated_at` matching the deploy time.
  **Path note**: the CLI hardcodes `supabase/functions/<name>/index.ts`
  relative to the project root — there's no flag to point it elsewhere.
  `ask-chef-harris`'s source used to live at
  `lib/supabase/functions/ask-chef-harris/index.ts` — a whole duplicate
  Dreamflow-era Supabase CLI scaffold nested under `lib/` (its own
  `config.toml`, `.temp/cli-latest`, `deno.json`, `.npmrc`), because
  Dreamflow could only write function code locally and had no deploy path
  of its own. **Deleted entirely 2026-08-11** — confirmed via grep that no
  Dart code referenced that path (Flutter never compiles/bundles `.ts`
  files; `ChefService` calls the function by name over HTTP via
  `functions.invoke('ask-chef-harris', ...)`, not by file path) and its
  `config.toml` (`verify_jwt = true`) already matched the live deployed
  state exactly, so nothing was lost. `supabase/functions/ask-chef-harris/index.ts`
  is now the **single real source** — no more sync-by-hand risk. Added a
  minimal `supabase/config.toml` (`verify_jwt = true`) alongside it so
  that setting is explicit for future deploys rather than implicit/
  dashboard-inherited. Any other edge function brought into CLI-managed
  deploys later (e.g. `ai-recipe-precision`, whose source isn't in this
  repo at all yet — see Roadmap item 5) should go straight into
  `supabase/functions/<name>/` — there's no reason to add a second copy
  anywhere else.

## Current architecture facts (confirmed from real source, not assumed)

- **Auth**: Anonymous-by-default (`signInAnonymously()` on startup, in `main()`,
  wrapped in try/catch so it never blocks app startup on failure). Users can
  now optionally link an email + password to their anonymous session via a
  "Secure My Account" flow in the Profile/settings screen, using
  `Supabase.instance.client.auth.updateUser(UserAttributes(email: ..., password: ...))`.
  This preserves `auth.uid()`, so all owned data survives linking. **Confirmed
  working** — tested end to end, email shows attached in Supabase Dashboard →
  Authentication → Users. Apple/Google OAuth linking is NOT built yet (needs
  native iOS/Android capability config, out of scope for a Dreamflow-only fix).
  Known follow-up: the email confirmation link currently redirects to
  `localhost:3000` unless Site URL / Redirect URLs are updated in Supabase
  Dashboard → Authentication → URL Configuration. Longer-term this should be a
  real deep link (`optimeal://` or universal link) so confirmation returns to
  the app itself rather than a browser tab.
- **AI calls**: `ChefService.askChefHarris()` is the single centralized AI
  call for recipe generation and chat. It calls the `ask-chef-harris` Supabase
  Edge Function via `Supabase.instance.client.functions.invoke(...)` — **no
  client-side API key**, confirmed secure (this was previously a live
  vulnerability — a direct `http.post` with an embedded
  `OPENAI_PROXY_API_KEY` via `String.fromEnvironment` — now fixed). The edge
  function itself is a generic OpenAI proxy: it does NOT hardcode any system
  prompt, it just forwards whatever `systemPrompt`/`userMessage` the client
  sends. This means prompt/schema changes for recipe generation are pure
  Dart-side changes, not edge function changes.
- There are TWO other, separate AI-adjacent services, easy to confuse with
  `ChefService`:
  - `AiRecipeService` — calls `ai-recipe-precision` (precision metadata: heat
    spec, salt timing, knife cut spec, Swiss substitutes, base ratios). The
    dead `ai-recipe-voice` call (`getChefHarrisVoice()`) was removed this
    session (2026-08-06) — it was never called from any screen.
  - Do not assume a debug log mentioning `AiRecipeService` means
    `ChefService.askChefHarris` didn't run — they're independent calls that
    typically both fire during recipe generation. In Fridge Clearer
    specifically, they now run **concurrently** (fixed 2026-08-06 — see
    session summary below) rather than sequentially, so one being slow no
    longer means the other is blocked on it.
- **Ingredient data is now consistently structured where it matters.** Every
  recipe-generation flow that can produce structured `{name, amount, unit}`
  ingredients (Fridge Clearer, Custom AI Recipe Creator, Weekly Planner's
  Deal Meal path) does so, and `structuredIngredients`/`basePortions` now
  round-trip correctly through Weekly Planner's Supabase persistence (fixed
  2026-08-06 — previously any planned meal became permanently unscalable the
  moment it was saved and reloaded, silently). The Weekly Planner shopping
  list also now merges/sums same-named ingredients across meals instead of
  listing each meal's items as separate duplicate rows. See session summary
  below for full detail — this was a multi-file fix, not a one-liner.
- **Curriculum content — there are TWO separate, unrelated systems.** Do not
  conflate them:
  1. `chefTechniqueDrawers` / `chefReferenceDrawers` (large `Map<String, String>`
     dictionaries of detailed instructional text, keyed by technique name like
     `stir_frying`, `sauteing`, `food_storage`, `knife_grip_mechanics`, etc.)
     inside `ChefService`. These get keyword-matched against the user's
     request and injected into the AI's system prompt on every
     `askChefHarris` call via `_buildCurriculumAddendum()` — this is the real
     "curriculum drawers" system that actually informs what the AI generates.
  2. `CurriculumLibrary` — a small, separate, hand-curated list of ~8
     `TechniqueLesson` entries (with video/thumbnail URLs, currently
     placeholder `example.com` links) used only by the browsable Techniques &
     Media hub screen. This is NOT used for anything AI-related and should
     stay that way — it's legitimate, separate content for browsing, not for
     the post-cook "What You Learned" recap feature (see session summary
     below) or the "Technique of the Week" home card, both of which use
     system 1 above.
- **Recipes table is currently empty** (confirmed via direct query) — no
  actual leakage occurred despite RLS having been briefly open on it; still
  correctly locked down now regardless (see RLS section below).
- **Paywall is not connected to a real purchase provider.** `isSubscribed` is
  a local `SharedPreferences` boolean with a `// TODO: wire to
  RevenueCat/Stripe in Step 5` still in the code. Not tied to `auth.uid()` or
  any real payment validation. This is a real, currently-unaddressed gap —
  bigger than it looks given the paywall is live. Treat as high priority
  whenever it comes up, separate from the auth-linking work above (linking
  identity does NOT fix this). **This needs a provider decision from Harris
  first** (RevenueCat vs. Stripe, account + product setup in App Store
  Connect/Play Console) — it's blocked on external account setup, not
  something Claude Code can meaningfully implement solo. Don't start this
  without checking in first.
- **The paywall was completely unreachable through normal navigation until
  this session (fixed 2026-08-06, NOT yet live-tested).** `onboarding_screen.dart`'s
  "Skip" button (a primary, always-visible button on onboarding slides 1-3)
  calls `context.go('/paywall')`, but `/paywall` was never registered as a
  route in `nav.dart` and `PaywallScreen` was never imported there — tapping
  Skip hit GoRouter's default "page not found" error screen, a dead end.
  `PaywallScreen` itself was already fully built and correctly self-contained
  (its own close/purchase handlers already navigated home correctly) — only
  the route registration was missing. Fixed by adding
  `AppRoutes.paywall = '/paywall'` and its `GoRoute`. **Verify next session**:
  tap Skip during onboarding and confirm it actually reaches the paywall
  screen now. Also worth asking Harris whether Skip-to-paywall should be the
  *only* entry point, or whether there should be others (e.g. an "Upgrade"
  button in Profile) — that's a product question, not something to decide
  unilaterally.
- **`user_profiles.user_id does not exist` (`42703`)** — a known, non-blocking
  error. `user_profiles`'s real primary key column is `id` (= `auth.uid()`),
  never `user_id`. Some code has a dead fallback path that queries a
  `user_id` column that has never existed on that table. App degrades
  gracefully; worth deleting the dead fallback code eventually, not urgent.


---

## Original "Working conventions" — full original text (pre-2026-08-17)

A condensed, reorganized version of this section now lives in `CLAUDE.md` (conventions are meant to be operative/current, so they stayed there rather than being archived — but the original wording is preserved below since some phrasing/detail was tightened during the rewrite).

## Working conventions

- **CLAUDE.md is authoritative for Roadmap item numbering — added
  2026-08-15.** If Harris refers to a Roadmap (or Retention Features
  Backlog, or Design Polish Backlog) item by number and it doesn't match
  what's actually at that number in this doc, **stop and ask** — don't
  guess which item was meant, and don't silently attach findings to the
  nearest-sounding item. Harris's own working list can drift from this
  doc; this doc is the one that's checked against the live project.
- **Locate code by content/class name, not filename**, until you've confirmed
  the export gave files their correct real names (see top of this doc).
- When a fix touches a Supabase Edge Function, give exact code plus explicit
  manual deployment steps (Dashboard → Edge Functions → Deploy → Via Editor).
  Never assume it's live until Harris confirms manual deployment happened.
- When something seems like it "should already be fixed" per this document
  but the live behavior contradicts it, verify the actual current source
  first — don't assume regression, and don't assume the documented fix is
  stale either. Check before concluding either way.
- Prefer running `flutter analyze` and any available tests after changes,
  something that wasn't possible at all in the previous Dreamflow-chat
  workflow — use this now that it's available.
- **Live-testing convention**: run a single `flutter run -d chrome
  --web-port=8765` in the background, and have Harris test in that one
  Chrome tab. After code changes, kill that process (`netstat -ano | findstr
  ":8765"` → `taskkill //PID <pid> //F`) and relaunch fresh on the same port
  rather than hot-reloading — there's no scriptable way to send a hot-restart
  keystroke to a backgrounded process here, and running a second instance on
  a different port caused real confusion earlier this session (Harris tested
  the stale tab and reasonably assumed a fix hadn't landed). Keep it to one
  running instance, same port, always.
- No browser automation (`claude-in-chrome`) was available this session —
  Harris declined the extension. Visual/layout claims this session (e.g. the
  Home dashboard scroll-fit numbers) were worked out from exact layout code
  values against known device viewport sizes, not visually confirmed. If
  `claude-in-chrome` becomes available in a future session, that's strictly
  better for anything visual — but don't assume it's off-limits again by
  default; check.
