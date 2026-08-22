# Session — Pre-cook merge: Step 1 = mise en place (2026-08-23)

Signed spec card of 2026-08-22, plus strategy rulings R1–R8. Companion to the
recipe-overview build (`edfeb50`).

---

## The prompt

The full prompt — including the verbatim signed spec card "Design Spec Card —
Pre-Cook Merge (Step 1 = Mise en Place)" and rulings R1–R8 — is reproduced in
this session's chat transcript. Every ruling is addressed by number below, and
every spec line not satisfied is listed explicitly.

---

## Report

### Two premise corrections, found by grepping before touching anything

1. **There is no `ChecklistScreen` route, and there never was.** Spec §6 and R4
   both call for deleting it. The checklist was a **card**
   (`_IngredientsChecklistCard`) inside Cook Mode's pre-cook body, reached by
   opening Cook Mode — no route, no navigation call sites to redirect. Nothing
   to delete at the route layer; a guard test now forbids one appearing.
2. **The synthesized prep step already existed.** `_buildPrepStep()` has been
   prepended to every session for a while. So the "insert" branch of R1 was
   already the shipped behaviour, and the actual defect was the **absence of
   dedup**: when the model also emitted its own prep step, the user saw both.
   That is exactly what Harris's 22 Aug screenshots show.

### Deletions confirmed, by class

| Deleted | Where |
|---|---|
| `_IngredientsChecklistCard` | `one_pan_cooking_roadmap_screen.dart` (167 lines) |
| `_IngredientChecklistRow` | same (139 lines) |
| `_checkedIngredientIndices` | the tick-state bridge to `IngredientPrepController` |
| `_ingredientKeys` | existed only to key that tick state |
| `_changePortions` | the inline pre-cook servings stepper |
| `IngredientPrepController` import | no longer used by Cook Mode |
| The `_buildPreCookBody` checklist block | the card and its stepper wiring |

A test asserts all of these are absent from the source with comments stripped,
so a doc reference explaining the removal does not count as a survival.

### R1 — the dedup heuristic, and the real-run table

`lib/services/prep_step_detector.dart`. Deliberately asymmetric, because **a
false positive deletes a real cooking step** and that is much worse than a
duplicate prep step:

- **Only the first step is ever a candidate.** Step 2+ is never deduped.
- **A cooking verb anywhere disqualifies it, even under a prep-ish title** —
  "Prep and sear the chicken" is a cooking step with a misleading name, and
  deleting it would delete the sear.
- Absent a prep title, the fallback is much stricter: no cooking verb **and**
  every bullet names a real ingredient of this recipe.

**Real dev runs, both branches:**

| | Fridge Clearer | Custom creator |
|---|---|---|
| generated step count | 5 | 6 |
| first step title | `Preheat Oven` | `Prepare Ingredients` |
| detected as prep | **false** | **true** |
| final displayed count | **6** (1 + 5, inserted) | **6** (1 + 5, replaced) |

"Preheat Oven" being *kept* is the heuristic working: it is a real cooking
action despite arriving first, and the conservative rule protects it.

**Proposed refinement, not implemented:** the detector could also treat a first
step with `heat: off_heat` **and** `durationMinutes: 0` as corroborating
evidence. I left it out because the model does not set those reliably, and the
title branch already caught the real case.

### R2 — step-index integrity: every consumer, by class

`_steps` was already the single source of truth; dedup changes its contents and
every consumer follows. Enumerated:

| Consumer | How it indexes |
|---|---|
| `_OnePanCookingRoadmapScreenState` | owns `_steps`; `_activeStepIndex`, `_completedSteps`, `_stepKeys` all index it |
| `_CookModeProgressBar` | `totalSteps: _steps.length`, `progress` from `_completedSteps` |
| `_FocusedStepCard` | `step` + `nextStep` by index |
| `_CookStepCard` | pre-cook list, index `i` |
| `_CookOverviewSheet` | `steps: _steps` — All Steps and Ingredients panes |
| `_NextStepWhisper` / `MiseEnPlaceCard` whisper | `_steps[index + 1]` |
| jump-to-step (`_jumpToStep`) | bounds-checked against `_steps.length` |
| cooked-set rewrite (`_toggleStepComplete`) | same indices |
| `_ChefSosSheet` recipe context | iterates `_steps`, **skipping the mise step** |
| `PlannerCookAttributionService` | does not index steps at all |
| cook log / `ActiveCookSession` | stores `activeStepIndex` + `completedSteps` against the same list |

Tested: a 4-step generation with a prep step displays 4; a 3-step generation
without one displays 4.

### R3 — Step 1's exemptions

No timer, no heat pill, no sensory cue, no cue-panel machinery. It is not seen
by the compatibility or safety validators (both run at generation time on the
model's own steps; the mise step is synthesized afterwards and is never in that
list). **It is excluded from the SOS prompt payload**, and numbering there
restarts from the first real cooking step — describing "1. Set up your board —
off heat, ~0 min" to the model would present a client-side UI affordance as
part of the recipe.

**No cook-log step count exists to exclude it from.** The cook log stores the
recipe payload plus `activeStepIndex`/`completedSteps`; there is no step-count
field. Reported rather than invented.

### R4 — routes and resume

No checklist route exists (see premise correction 1). A test asserts
`lib/nav.dart` contains no `checklist` match at all. `_ResumeSessionBanner` →
`_resumeCookMode` → `AppRoutes.onePanCookingRoadmap` with the stored
`ActiveCookSession`; a test resumes at index 2 of a 3-step list and lands on
"Boil the pasta" at "Step 3 of 3", never on the mise read.

### R5 / R6 — reuse confirmed, no duplicates

`IngredientRow` is imported from `lib/widgets/ingredient_row.dart` — **no
second row widget was created**. Scaling goes through
`lib/models/recipe_scale.dart` — **no second scale holder**. The have-out group
is one compact `·`-joined row that wraps.

The serves pill reads `CookModeLaunchRequest.servings` when non-null; when null
(generation surfaces and the planner Cook button bypass the overview) it falls
back to the same precedence the overview uses — profile household **if
onboarded**, else recipe `basePortions`. Both branches tested: `servings: 5`
renders "Serves 5" and scales 200 g → 500 g; null renders "Serves 2" at 200 g.

### R7 — overflow

`grep -rn "scrollDirection: Axis.horizontal" lib/` returns **nothing**, and a
test now walks all of `lib/` asserting that. One real overflow was found and
fixed while testing at 360 px: the serves pill's label is long enough with its
placeholder suffix that it overflowed its own `Row` — the label is now
`Flexible`.

### Step 1 as rendered, from the real runs

```
1. FRIDGE CLEARER
    [1] Set up your board
    ( No heat yet ) ( Serves 2 · set on recipe page )
    sage: Everything cut and within reach before the pan gets hot.

    NEEDS THE KNIFE
      200 g courgette
      300 g potatoes
      1 lemon

    JUST HAVE IT OUT
      400 g chicken thighs · 100 g feta

    Next · Preheat Oven
    CTA: Board's clear — heat goes on

2. CUSTOM CREATOR
    [1] Set up your board
    ( No heat yet ) ( Serves 2 · set on recipe page )
    sage: Everything cut and within reach before the pan gets hot.

    NEEDS THE KNIFE
      300 g potato
      100 g onion

    JUST HAVE IT OUT
      4 eggs · 3 tbsp olive oil · ½ tsp salt · ¼ tsp black pepper

    Next · Cook Potatoes
    CTA: Board's clear — heat goes on
```

No cut pills rendered on either: the resolved cuts were `thin_slice`,
`large_dice` and `wedges`, none of which has a built diagram. `julienne` is
still the only drawn cut.

### Spec lines not satisfied

1. **§2.7 "CTA = the step's Next"** — implemented as the **bottom bar's** Next
   button, relabelled on Step 1, rather than a button inside the card. A filled
   button in the card would have been a *second* terracotta CTA on screen,
   breaking the kit rule the same spec cites in R7. Flagged as a reading.
2. **§1 "Cook Mode opens on Step 1"** — taken narrowly. The checklist card is
   deleted, so Step 1 is the first thing below the header, but the pre-cook
   body and its "Start Cooking" card still exist. §6's deletion checklist names
   the checklist card, its strings, its stepper, the (non-existent) route and
   the generated prep step — **not** the pre-cook body or the Start Cooking
   card. Auto-starting the cook would have deleted a surface the spec did not
   list. Conservative reading; easy to change if the wider one was meant.
3. **§3 "existing note-splitting … rendered pill-less in the knife group if a
   cut-like note exists"** — an unstructured recipe currently renders its plain
   strings in the have-out group only. Splitting free-text ingredient notes into
   knife/have-out would need a second inference layer over strings that have no
   structure by definition, and every generated recipe has structured data. The
   fallback exists so nothing renders empty.

### Ambiguities

- **R3 "cook-log step counts exclude it if they exist"** — none exist.
- **R2's "SOS current step context"** vs **R3's "must not appear in any prompt
  payload"** pull against each other when the user is *on* Step 1. Resolved
  conservatively: the mise step is omitted from the payload entirely, so on
  Step 1 the model sees the recipe with no "user is here" marker rather than
  seeing a step that is not a step.
- **Step 1's title** is now "Set up your board" (the spec's placeholder),
  replacing "Prepare Your Ingredients". Two existing Unit B tests asserted the
  old string and were updated.

### Scope flags

**Grew:** `_FocusedCookBottomBar` gained a `nextLabel` (needed for the Step 1
CTA without adding a second one); `_CookStep` gained `isMiseEnPlace`; the SOS
payload builder changed. The `_MetaPill` label became `Flexible` after a real
360 px overflow.

**Held:** `IngredientRow` and `recipe_scale.dart` were **consumed, not
rebuilt**. Nothing from the profile or custom-creator cards was started. The
generation prompts, the cue contract and both validators are untouched — Step 1
costs zero tokens.

### Verification

- `flutter test`: **623 passing** (593 baseline + 30 new), zero failures.
- `flutter analyze`: **44** — unchanged. Palette guard green.
- Two real dev generations, both R1 branches exercised.
- **No migration, no dev DB write, no prod contact.**
