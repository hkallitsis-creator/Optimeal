# Session — Recipe overview / details redesign (2026-08-23)

Signed spec card of 2026-08-22, plus strategy rulings R1–R9.

---

## The prompt, verbatim

```
PROMPT — Recipe Overview / Details redesign (signed spec, 22 Aug)

AUTONOMY: full, hands-free. Stop conditions: any prod Supabase contact (prod is
link-pinned; never relink). Dev DB: no migration expected — if you conclude one
is needed, stop and report. Genuine spec ambiguity: note it, take the
conservative reading, continue.

Read first: CLAUDE.md, docs/sessions/ latest three entries (dev-entitlement,
design-qa-polish, safety-validator), docs/DECISIONS.md. CLAUDE.md drifts —
verify against live code. GREP BY CLASS across all .dart files before touching
anything; filenames and class names are mismatched (e.g. CurriculumLibrary
lives in recipe_details_screen.dart).

SEQUENCING CONTEXT (do not act on, but know): the companion pre-cook merge
build runs NEXT and will DELETE the old Ingredients Checklist card and its
inline servings stepper. This build must therefore (a) give the servings
adjuster its new home on the overview and (b) build the shared ingredient row
component the pre-cook Step 1 will reuse. Do NOT delete the checklist surface
in this build — leave the old stepper in place even though it is now
redundant; removing it is the next prompt's job. Build once, render twice.

==================================================================
SIGNED SPEC — embedded verbatim
==================================================================
# Design Spec Card — Recipe Overview / Details Redesign
**Date:** 2026-08-22 · **Source:** design chat · **Status:** SIGNED
**Companion:** design_spec_precook_merge_2026-08-22.md (this surface receives the servings adjuster; build the pair in either order but ship both before testers — the pre-cook card's read-only pill points here)
**Consumers:** strategy chat — embed verbatim per spec-embed rule. Colors = palette v1.2 tokens.

## 1. Scope
The recipe overview screen (between choosing a recipe — ideas tap, Saved, planner — and Cook Mode). Currently: title · "Est. time" pill · "Mode: Cook Mode" pill · "Kitchen Gear Needed" headline + chips · the old Ingredients Checklist card (deleted by the pre-cook merge) · science-notes disclosure (already deleted). Grep by class — recipe details/generated-recipe-card widgets are scattered across misnamed files.

## 2. Composition (top → bottom)
1. Header: back + home glyph (depth ≥2 rule) · **bookmark top-right** (universal save; pre-cook saving's home; filled/outline states)
2. **Title** (large) · **description = ONE quiet sentence** under it (the generated dish description; single line, ellipsized — never a paragraph)
3. **Provenance line** when Fridge Clearer origin: leaf + clearance story ("fridge rescue · clears 4 of your 5") // PLACEHOLDER phrasing, consistent with ideas-screen line
4. **Meta card:** left = quiet line "~32 min · 7 steps"; right = **SERVINGS STEPPER** (terracotta − / + glyphs, "Serves N"). This is the adjuster's new and only home.
5. **Gear card:** glyph + **champagne chips** (signed: requirements wear champagne even though not tappable), wrap never clip
6. **Ingredients card:** section label // PLACEHOLDER · quiet rows `quantity + name` + cut pill → diagram sheet. SAME row component as pre-cook Step 1 — build once, render twice. Have-out items may join into one compact row. Read-only, nothing tickable.
7. Pinned bottom: **Plan** (outlined calendar-plus icon square → existing weekday picker) · one terracotta CTA **"Start cooking"** // PLACEHOLDER

## 3. Servings mechanics (SIGNED)
- Stepper rescales ingredient quantities LIVE from structured data (base amounts × N/basePortions).
- **Whole-piece rule (signed):** countable/piece-unit ingredients ROUND UP to the next whole; row gains a quiet hint suffix ("· rounded up") // PLACEHOLDER. Non-count units display exact (sensible precision: trailing .0 dropped, one decimal max).
- Range 1–6 (matches Fridge Clearer "For" segments; extend only if profile household exceeds).
- Quantities LOCK when Cook Mode opens (Start cooking) — Step 1's read-only pill and the whisper/steps all render from the locked scale. Returning here after backing out of Cook Mode unlocks again.
- Default N: recipe's generated basePortions, overridden by planner/profile context where already wired.

## 4. Cuts
- "Mode: Cook Mode" pill (tautology)
- "Est. time" pill-card styling (demoted to quiet meta line with step count)
- "Kitchen Gear Needed" headline (glyph + chips carry it)
- Ingredients Checklist card (per pre-cook merge card — listed for sweep completeness)

## 5. Signed-content placeholders (persona batch)
Ingredients section label · provenance/clearance phrasing · rounded-up hint wording · CTA label · Plan tooltip if any.

## 6. Device acceptance checks (Pixel)
- [ ] Stepper rescales all quantities instantly; eggs at Serves 3 show "2 eggs · rounded up", never "1.5 eggs"
- [ ] Quantities locked inside Cook Mode; Step 1 pill matches chosen N
- [ ] Description never wraps past one line; long titles wrap, description ellipsizes
- [ ] Bookmark toggles + persists; recipe appears in My recipes as "not cooked yet" when saved pre-cook
- [ ] Plan opens weekday picker; planned recipe carries provenance leaf
- [ ] Cut pills open correct diagrams; no pill on unrecognized cuts
- [ ] One terracotta CTA on screen; gear chips wrap at 360 logical px
==================================================================
END SPEC
==================================================================

DEVICE EVIDENCE (Harris, 22 Aug screenshots of the current screen): half-
screen empty terracotta hero block above the title; three-line description;
bulleted ingredient list with "4 piece Eggs" / "0.3 tsp Black Pepper"
formatting; "Kitchen gear" chips; inline "Steps" list below; NO cook
affordance when opened from My Recipes. All addressed by the spec + rulings.

STRATEGY-CHAT RULINGS FOR THIS BUILD

R1. Spec §4 "Ingredients Checklist card" cut: DEFERRED to the next build.
    Leave it and its stepper untouched. Record in the session doc that the
    overview now carries a second, authoritative stepper until the pre-cook
    merge lands.

R2. Cut-pill resolution: RecipeIngredient is name/amount/unit only; there is
    no per-ingredient cut key and generation prompts are NOT to be changed
    (zero token cost — pre-cook card §3). Implement a client-side resolver,
    lib/services/cut_key_resolver.dart, matching the closed cut vocabulary in
    the repo (grep for the cut vocabulary data file; exact names, never
    invented) against (a) the ingredient name/note and (b) the recipe's step
    text where the ingredient is mentioned. Whole-word matching. Pill renders
    ONLY when a diagram exists for that key (currently the pilots — verify by
    grepping the CustomPainter registry). Technique diagrams (pan_crowding,
    cold_vs_hot_pan) NEVER attach to ingredient rows — only CUT keys do.
    Report the resolver's match rate across the real runs (ingredients seen /
    ingredients with any cut detected / pills rendered).

R3. Servings scale model: ONE scale holder (RecipeScaleState or a field on
    the cook-session payload — your call, report it) that Cook Mode reads at
    open and freezes. "Lock" = Cook Mode snapshots N at Start cooking; the
    overview's stepper re-enables when the route pops back. No persisted
    schema change: scale is launch context, same pattern as PlannerSlotRef
    (DECISIONS.md) — deliberately NOT written onto the saved recipe payload.
    Saved/bookmarked recipes keep basePortions.

R4. Whole-piece rule applies to units: piece, clove, slice, and any unit-less
    countable. Rounding is ceil on the scaled amount; hint suffix only when
    rounding actually changed the value. Non-count units: one decimal max,
    trailing .0 dropped, and values ≥ 100 (g/ml) round to the nearest 5 (my
    addition for legibility — flag if it conflicts with anything signed).
    Row text format: "4 eggs", "200 g potatoes", "½ tsp salt" style — the
    unit word "piece" never renders; fractions ½/¼/¾ for 0.5/0.25/0.75 on
    tsp/tbsp, decimals otherwise.

R5. Default N precedence: planner slot context (if launched from planner) >
    profile "usually cooking for" (if set) > recipe basePortions. Range 1–6;
    ceiling extends to the profile household value if it exceeds 6.

R6. Bookmark: reuse the universal bookmark mechanism from the My Recipes
    build; saving pre-cook must produce a My Recipes "Saved" entry with no
    cooked state. Provenance (Fridge Clearer origin) must survive save and
    Plan — do not strip it.

R7. Kit rules: one terracotta CTA; gear chips champagne, wrap never clip;
    home glyph present (depth ≥2); no literal hexes (palette guard). The
    terracotta hero block is gone — the reserved photo slot is a modest
    fixed-height placeholder area (ivory, empty, no text), not a half-screen
    block. The inline "Steps" list is REMOVED from the overview (steps live
    in Cook Mode and its overview sheet); meta line carries the step count.
    Extend existing exhaustive guard tests where a new entry point or chip
    class is introduced.

R8. All new user-visible strings marked // PLACEHOLDER (persona batch).

R9. DEVICE BUG (Harris, 22 Aug): recipes opened from My Recipes (Saved and
    Recently Cooked) land on this screen with NO cook affordance — they can't
    be cooked again. The pinned "Start cooking" CTA fixes this by design, but
    VERIFY all entry points reach the SAME overview widget and that Start
    cooking launches Cook Mode correctly from each: Fridge Clearer ideas tap
    · Custom generation · Saved · Recently Cooked · planner slot (has its own
    Cook button — confirm it routes through this overview or deliberately
    bypasses it; report which). Re-cooking a saved recipe must preserve
    provenance (a saved Fridge Clearer recipe cooked again counts as a rescue
    per DECISIONS.md) and must create a NEW cook-log row, never mutate the
    old one. Widget test per entry point.

TESTS (minimum)
- Scaling math: eggs 1.5 → "2 eggs · rounded up"; 250 g at 3/4 → "190 g";
  0.5 tbsp → "½ tbsp"; basePortions null → stepper disabled at default N, no
  crash.
- Lock/unlock: Start cooking freezes N; stepper change after pop is honored;
  Cook Mode reads the frozen value, not the live one.
- Default precedence R5 (three cases).
- Resolver: whole-word; technique keys never attach to rows.
- Widget: one terracotta CTA; description maxLines 1 ellipsis; bookmark
  toggles and calls the save service once; no "Steps" section rendered.
- R9: Start cooking reachable and functional from all five entry points.

VERIFICATION
- flutter test green vs 543; analyze vs 44; palette guard green.
- Real dev runs: two generations (one Fridge Clearer, one Custom); exact
  rendered text of the meta line and scaled ingredient rows at N=1, N=3,
  N=6; the resolver match-rate table.

DOC STEP (mandatory)
- CLAUDE.md: overview surface, scale-holder location, resolver, entry-point
  routing table from R9.
- docs/CHANGELOG.md; docs/DECISIONS.md entries for R2 (client-side resolver,
  no schema change), R3 (scale = launch context), R9 (re-cook = new row,
  provenance preserved).
- docs/sessions/2026-08-23_recipe-overview.md with this prompt and your
  report verbatim. Commit, push.

REPORT: what changed by class, scale-holder decision, resolver match rate,
the R9 routing table, every spec line not satisfied and why, ambiguities,
scope flags both ways. Nothing from the pre-cook merge card may be started.
```

---

## Report

### What changed, by class

**New:**

| Class / file | Role |
|---|---|
| `RecipeOverviewBody`, `RecipeOverviewBottomBar` (`lib/widgets/recipe_overview_body.dart`) | The redesigned surface and its pinned bar. Private `_MetaCard`, `_StepperGlyph`, `_GearCard`, `_IngredientsCard`, `_OverviewCard`. |
| `IngredientRow` (`lib/widgets/ingredient_row.dart`) | **Built once, rendered twice** — the pre-cook merge's Step 1 reuses it. |
| `ScaledIngredient` + `scaleIngredients` / `defaultServingsFor` / `servingsCeilingFor` / `estimatedMinutes` (`lib/models/recipe_scale.dart`) | All servings arithmetic and formatting, pure. |
| `resolveCutKey` / `resolveCutDiagramKey` (`lib/services/cut_key_resolver.dart`) | Client-side cut resolution. |

**Rewritten:** `RecipeDetailsScreen` — `StatelessWidget` → `StatefulWidget`
(it now owns servings). `_RecipeBody` and `_DetailsSection` deleted;
`_MissingRecipeBody` replaces the old inline demo body.

**Modified:** `CookModeLaunchRequest` and `OnePanCookingRoadmapScreen` gained
`servings`; `lib/nav.dart` forwards it.

### The cuts, all made

Gone: the 250px terracotta `SliverAppBar` hero, the three-line description
(now `maxLines: 1` + ellipsis), the "Mode: Cook Mode" pill, the "Est. time"
pill-card (now `~50 min · 5 steps`), the "Kitchen gear" headline (glyph +
chips carry it), and the **inline Steps list**. Tests assert each absence.

### Scale-holder decision (R3)

**The overview screen's own `State`, with the value travelling on
`CookModeLaunchRequest.servings`.** Not a new `RecipeScaleState` service and
not a payload field.

The payload is persisted into `saved_recipes.recipe_payload` and
`user_meal_plans.recipe_payload`, so a scale written there would make a saved
recipe permanently remember one evening's headcount — the same trap
`PlannerSlotRef` was kept out of. Keeping it in the route's `State` is also
what makes the signed lock/unlock fall out for free rather than needing
machinery: Cook Mode reads `servings` once on mount (**that is the lock**), and
popping back re-enables the stepper because the `State` was never disposed.
**No persisted schema change, no migration.**

### Resolver match rate (R2), from the real dev runs

| | count |
|---|---|
| ingredients seen | **14** |
| with any cut detected | **5** |
| pills rendered | **0** |

Zero pills is correct, not a failure: `julienne` is the only **built** cut
diagram, and neither generated recipe used it. The five detections were
`thick_slice`, `large_dice`, `wedges`, and `thin_slice` ×2 — all from the
model's **declared** `cut`, none needing the prose fallback.

### R9 — entry-point routing table

| Entry point | Class | Reaches the overview? |
|---|---|---|
| Saved recipe | `_MyRecipesScreenState._openDetails` | **Yes** — `AppRoutes.recipe` |
| Recently Cooked | `_MyRecipesScreenState._openDetails` | **Yes** — same method |
| Planner day-detail *view* tap | `weekly_planner_screen.dart:485` | **Yes** — `AppRoutes.recipe` |
| Fridge Clearer stage 2 | `GeneratedRecipeActionsSheet` | **No — deliberate bypass**, straight to Cook Mode |
| Custom generation | `GeneratedRecipeActionsSheet` | **No — deliberate bypass**, same sheet |
| Planner **Cook** button | `weekly_planner_screen.dart:400` | **No — deliberate bypass** |

The two generation surfaces bypass because **"Cook Now stays the only primary
action on both" is already signed** (CLAUDE.md, 2026-08-21); routing them
through an intermediate screen would contradict it, so I did not. The planner's
Cook button bypasses because it must stamp `PlannerSlotRef`, which the overview
has no way to supply — routing it through would silently break slot
attribution. **All three were left alone and are reported rather than changed.**

The device bug is nonetheless fixed: it was specifically that My Recipes had no
cook affordance, and all three overview-reaching paths now have one. Five entry
*shapes* are covered by widget tests asserting a present, enabled CTA.

Re-cook launches with `surface: null` and **not** `isReCook` — provenance rides
on `RecipeOrigin` so a saved Fridge Clearer recipe still counts as a rescue, and
leaving `isReCook` false means the cook logs a **new** row rather than being
suppressed.

### Real dev runs

Both against `suuafglvrxrllnhipkiv`. Meta lines: `~50 min · 5 steps` (Fridge
Clearer) and `~31 min · 6 steps` (Custom).

**Fridge Clearer — Chicken and Courgette Traybake** (`basePortions: 2`)

| Serves 1 | Serves 3 | Serves 6 |
|---|---|---|
| 200 g chicken thighs | 600 g chicken thighs | 1200 g chicken thighs |
| 100 g courgette | 300 g courgette | 600 g courgette |
| 150 g potatoes | 450 g potatoes | 900 g potatoes |
| 50 g feta | 150 g feta | 300 g feta |
| **1 lemon · rounded up** | **2 lemon · rounded up** | 3 lemon |
| 1 tbsp olive oil | 3 tbsp olive oil | 6 tbsp olive oil |
| ½ tsp salt | 1½ tsp salt | 3 tsp salt |
| ¼ tsp black pepper | ¾ tsp black pepper | 1½ tsp black pepper |

**Custom — Classic Spanish Omelette** (`basePortions: 2`)

| Serves 1 | Serves 3 | Serves 6 |
|---|---|---|
| 150 g potatoes | 450 g potatoes | 900 g potatoes |
| 50 g onion | 150 g onion | 300 g onion |
| **2 eggs** | 6 eggs | 12 eggs |
| 1½ tbsp olive oil | 4½ tbsp olive oil | 9 tbsp olive oil |
| ½ tsp salt | 1½ tsp salt | 3 tsp salt |
| ¼ tsp black pepper | ¾ tsp black pepper | 1½ tsp black pepper |

The device evidence's two complaints are gone: no "4 piece Eggs" (the unit word
never renders) and no "0.3 tsp Black Pepper" on these outputs — though a genuine
0.3 would still print as `0.3 tsp`, which is honest rather than rounded away.

### A defect the real runs found, and fixed

Step-scoped prose matching put a **`thin_slice` pill on the SALT** ("Thinly
slice the potatoes. Season with salt." in one step) and **`wedges` on the FETA**
(lemon wedges mentioned nearby). Matching is now **sentence-scoped**. A second
bug surfaced fixing it: naive plural stripping turned `potatoes` into
`potatoe`, which matched nothing. Both are pinned by tests.

### Spec lines not satisfied

1. **§3 "Step 1's read-only pill … render from the locked scale."** Step 1's
   pill is the **pre-cook merge's** surface and is explicitly out of scope. The
   locked value is plumbed and read; nothing renders it there yet.
2. **§2.3 clearance story** ("clears 4 of your 5"). The overview renders the
   leaf + `fridge rescue` placeholder only. The clearance count comes from
   `FridgeClearance.forIdea`, computed from the user's *entered* list, which is
   not on the payload at this point in the flow. Rendering a fabricated count
   would be exactly the failure mode the Fridge Clearer build was careful to
   avoid, so I rendered none.
3. **§2.6 "Have-out items may join into one compact row."** Not implemented —
   `IngredientRow` has a `dense` flag ready, but nothing in the data marks an
   ingredient as have-out, and inventing a classifier would be a new rule. The
   spec says "may".
4. **R5's planner tier** has no data source: `PlannerSlotRef` carries
   week/day/slot and no headcount. The parameter exists and is always null.
5. **§6 device checks** are Pixel checks and need Harris.

### Ambiguities

- **R2's premise is wrong.** `RecipeIngredient.cut` exists and is
  parser-validated. Declared wins; prose is the fallback. Recorded in
  `DECISIONS.md`.
- **R5 "profile if set"** — `UserProfile.empty()` returns a non-nullable
  household of `1`, so an un-onboarded profile would out-rank every recipe's
  own base and open everything at Serves 1. I gated on `profile.onboarded`.
- **R4's ≥100 nearest-5 rule** conflicts with nothing signed. Adopted.
- **Ingredient name casing** left verbatim ("2 eggs" but "300 g Feta" if the
  model capitalises) — re-casing generated content would mangle "Parmesan".

### Scope flags

**Grew:** `CookModeLaunchRequest` / `OnePanCookingRoadmapScreen` / `nav.dart`
gained `servings` (unavoidable — the lock has to reach Cook Mode);
`RecipeDetailsScreen` became stateful; the old `_MissingRecipeBody` replaced a
large inline demo body rather than being preserved verbatim.

**Held:** **R1 respected — the Cook Mode ingredients checklist and its inline
stepper are untouched.** The app now carries **two servings steppers**, and the
overview's is the authoritative one (its value is what reaches Cook Mode). The
old one is the pre-cook merge's to delete. **Nothing from the pre-cook merge
card was started.** The three bypassing entry points were reported, not
rerouted.

### Verification

- `flutter test`: **593 passing** (543 baseline + 50 new), zero failures.
- `flutter analyze`: **44** — unchanged. Palette guard green; no literal hexes.
- **No migration, no dev DB write, no prod contact.**
