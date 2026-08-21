# Session — Fridge Clearer redesign: input + ideas (2026-08-22)

## Prompt (verbatim)

```
AUTONOMY: Full file/test/git permission. No confirmation questions.
STOP CONDITIONS: Prod Supabase = stop-and-report always. Dev
(suuafglvrxrllnhipkiv) read-only plus app-level test writes through
existing services; no migrations, no schema changes. EDGE FUNCTIONS:
never assume auto-deploy — if this build requires ANY change to the
ask-chef-harris edge function, STOP on that part, produce the exact
code to paste plus Supabase Dashboard steps for Harris, and ship
everything client-side achievable. Spec ambiguity = note and
continue, never guess.

BUILD — FRIDGE CLEARER REDESIGN (INPUT + IDEAS), two parts, one
session. Signed spec embedded verbatim below — WHAT and WHERE; you
own HOW. Sequencing gate from spec §8 is CLOSED: caching session
done, ordering fix shipped (1c76d03), cost ruled a non-factor;
stage-1 call shape is yours to design within the constraints below.

━━━ SPEC (verbatim, design_spec_fridge_clearer_2026-08-21.md) ━━━
[Sections 1–7 of the card, word for word as I have them:]

Scope: Fridge Clearer input screen redesign (one screen, no scroll)
+ the post-"Let's Cook" ideas moment (two-stage generation UX).
Replaces today's four-card scrolling interview. Likely files (grep,
not filenames): FridgeClearerScreen / AiFridgeScrapGeneratorScreen
classes; ideas stage touches chef_service.dart generation flow +
generated_recipe_actions_sheet.dart (Cook/Save/Plan trio reuse).

Input screen — signed structure (top → bottom, fits one screen):
1. Header: back (+ home glyph if depth ≥2 per hub rule) · "Fridge
   Clearer"
2. Ingredients hero card (the work): short title + ONE quiet line
   replacing today's paragraph: pantry staples assumed (oil, spices,
   pasta). Text chips, NO per-chip icons. Suggestion chips + typed
   ingredients become removable ✕-chips in the same wrap. Selected =
   champagne fill (#F7DBCB / #A44E2B text, weight 500); unselected =
   quiet row surface with hairline border. Type field + champagne
   add button.
3. Settings card (ONE card, three rows — the big cut): Row Time —
   3-segment (15 / 30 / 45+), single-select. Row Gear — small text
   chips, multi-select, wraps to 2 lines max. Row For — segments
   (1/2/4/6), single-select, silently defaults from profile. NO
   headlines, NO explainer paragraphs per row. Icon + one-word label
   only.
4. Pinned bottom: one terracotta CTA ("Let's cook — clear that
   fridge" = placeholder)

Cuts from today: separate Time/Cookware/People cards with headline +
explainer paragraph each (≈2 screens of scroll); all explainer copy;
per-chip icons on ingredients and cookware; horizontal pill overflow.

NEW KIT RULES (apply app-wide, add to kit addendum): Controls wrap,
never clip — no horizontal-scrolling or edge-clipped selectors
anywhere (fixes today's "45+ M…" / "4 …" truncation). Selection
state = champagne fill — selected chips/segments across the app use
the champagne/terracotta-text pair; unselected use quiet surface +
hairline. No selection by border-only or icon-only.

Ideas moment — two-stage generation (SIGNED UX):
After Let's Cook: Stage 1 — menu, not meals: ONE small generation
call returns THREE idea summaries: title · total time ·
ingredient-clearance line. No full recipes generated. Ideas screen:
3 cream cards. The clearance line is the hero of each card: "Clears
4 of your 4 ingredients" / "Clears 3 of your 4 — potatoes stay."
Leaf glyph, sage-dark text. Time top-right, quiet. Tap a card →
actions sheet (kit chrome): Cook it now (terracotta) · Save
(bookmark) · Plan (weekday picker) — same trio as planner spec,
reused not rebuilt. Stage 2 — full recipe generated ONLY for the
chosen idea, on Cook/Save/Plan. Perceived speed improves: fast menu
first, long generation after commitment. Regenerate/reload button
REMOVED from this flow — choosing among three replaces retrying one
(if all three disappoint, back re-runs stage 1). Planner "Clear
Fridge Leftovers" source path lands on this same ideas screen with
"save one into this day" behavior.

Signed-content placeholders (Harris authors — mark // PLACEHOLDER):
ideas screen header (must reference the actual ingredients, not
"Three ways to clear it"), clearance line phrasing, CTA label,
ingredients-card title + staples line, settings row labels.
━━━ END SPEC ━━━

IMPLEMENTATION CONSTRAINTS:
- Stage 1 goes through the EXISTING ask-chef-harris edge function
  unchanged if at all possible — prompt assembly is client-side in
  chef_service.dart, so a summaries-mode prompt should need no
  function change. Static-before-variable prompt ordering rule
  applies to the new stage-1 prompt (enforced since 1c76d03).
  Structured JSON out: three summaries, each {title, total_time,
  ingredients_cleared: [...], ingredients_left: [...]}. Clearance
  lines computed from the user's ENTERED list vs the summary's
  cleared list — never trust the model to do the arithmetic in prose.
- Stage 2 reuses the existing full-recipe generation path with the
  chosen idea's title + entered ingredients as anchors. RecipeOrigin
  stamping unchanged: rescue provenance + originEnteredIngredients
  exactly as today — the two-stage split must not break the ledger.
  Test proving a stage-2 recipe carries correct provenance.
- Cook/Save/Plan trio: reuse generated_recipe_actions_sheet.dart and
  the existing weekday picker. Save before generation? No — all
  three actions trigger stage 2 first, then act on the result
  (a saved recipe must be a real recipe, not a summary).
- Cost logging: stage-1 and stage-2 calls both land in
  api_call_cost_log with distinct surface values.
- The old regenerate affordance in this flow: removed per spec.
- Kit rules are app-wide: apply wrap-never-clip and
  champagne-selection to any OTHER selector you find clipped or
  border-only-selected while in these files; list each site touched.

TESTS: keep all 285 green. Add: input screen renders one-screen
structure; chip select/deselect/typed-add/remove; gear wraps at 2
lines; profile default on For; stage-1 parse (incl. malformed JSON
fallback → note the fallback you choose); clearance-line arithmetic
from entered vs cleared lists incl. the "X stays" case; tap →
actions sheet → stage-2 triggered only after choice; provenance on
stage-2 recipe; planner leftovers path lands on ideas screen.

VERIFICATION:
- flutter test all passing, exact count; flutter analyze ≤45, exact
  count; palette guard green
- git status clean, committed and pushed

DOC STEP (permanent rule): commit this prompt verbatim + full report
to docs/sessions/2026-08-22_fridge-clearer-redesign.md. Update
docs/CHANGELOG.md. Record in docs/DECISIONS.md: two-stage generation
signed; regenerate removed from this flow; kit rules (wrap-never-
clip, champagne-selection) adopted app-wide.

Report verbatim: stage-1 call design (prompt shape, token estimate
from a real dev call if feasible), edge-function verdict (unchanged
or stop-and-handover), kit-rule sites touched beyond this screen,
files touched, test/analyze counts, push confirmation, ambiguities.
```

---

## Edge-function verdict: **UNCHANGED**. No handover needed.

`ask-chef-harris` is a generic proxy — it forwards whatever
`systemPrompt`/`userMessage` arrives and stores whatever `surface` string
arrives, validating neither against any list. Stage 1 is therefore a new
*prompt*, not a new *endpoint*.

Confirmed empirically rather than by reading the source: one real stage-1 call
against live dev (authenticated anonymous session) returned `200` with usage
data and three well-formed ideas, sending `surface: "fridge_ideas"` — a value
the deployed function has never seen. Nothing was deployed, nothing was
changed, and no Dashboard step is owed.

## Stage-1 call design

**Shape.** One `askChefHarris` call, `forceJsonObject: true`, split the way the
1c76d03 ordering rule requires:

- `staticPromptBlock:` `buildFridgeIdeasStaticPrompt()` — schema + guidelines,
  byte-identical on every call, added to `lib/prompts/recipe_static_prompts.dart`
  beside the two existing static blocks so a test can reach it and prove
  nothing per-call has crept in. **1,289 chars** — deliberately tiny next to
  the recipe block's 6,968, because the whole economic case for splitting the
  flow is that this call is cheap.
- `userQuery:` ingredients, time box, gear, portions. Everything variable,
  landing after the static prefix.

**Schema** (as specced):

```json
{"ideas":[{"title":"...","total_time_minutes":0,
           "ingredients_cleared":["..."],"ingredients_left":["..."]}]}
```

**`ingredients_left` is requested and never read.** The app computes the
partition itself. Asking for it anyway is deliberate: it forces the model to
account for the user's whole list rather than casually over-claiming in
`ingredients_cleared`, and it costs a handful of output tokens.

**Token measurement — a real call, live dev, 2026-08-22:**

```
usage: {"prompt_tokens": 2857, "completion_tokens": 155, "total_tokens": 3012,
        "prompt_tokens_details": {"cached_tokens": 0, ...}}
```

Char counts behind it (dumped from the real assembly path, not estimated):
system prompt 7,044 · stage-1 user message 4,866 = **11,910 chars → 2,857
tokens**. The stage-2 equivalent is 7,044 + 20,636 = 27,680 chars, which the
2026-08-21 session measured at ~6,950 prompt tokens — so the char→token ratio
here is calibrated against a prior real measurement of the same prompt family.

| | prompt | completion | ≈ cost (gpt-4o) |
|---|---|---|---|
| stage 1 | **2,857** | **155** | ~$0.0087 |
| stage 2 | ~6,950 | ~900 | ~$0.026 |

Browse-and-back-out costs **~65% less** than the old single-stage flow.
Browse-and-commit costs **~30% more**. The comparison that matters is against
what it replaces: "Try Another" cost a full recipe generation each press, so
seeing three dishes the old way ran ~$0.079 against ~$0.035 now — and the user
now waits 7–10s *after* committing rather than before.

`cached_tokens: 0` on a first-ever call is expected; the static prefix is
byte-identical across stage-1 calls, so it should cache from the second call
onward exactly as the recipe prefix does.

**The reply it produced**, unedited, on ingredients {Eggs, Potatoes, Zucchini}:

| title | time | cleared | left |
|---|---|---|---|
| Spanish Tortilla | 25 min | Eggs, Potatoes | Zucchini |
| Zucchini Potato Hash | 20 min | Potatoes, Zucchini | Eggs |
| Vegetable Frittata | 30 min | Eggs, Potatoes, Zucchini | — |

Three genuinely different dishes, one clearing everything, partitions summing
correctly. That is the behaviour the guidelines ask for, on the first attempt.

**Malformed-reply fallback: null → error card. Nothing is fabricated.**
`parseFridgeIdeasJson` is tolerant about *shape* (accepts a bare array, accepts
1–3 ideas rather than demanding exactly 3, skips title-less entries, caps at 3)
and strict about *substance* (no usable idea → null). This is the opposite of
what this screen did when full-recipe parsing failed — CLAUDE.md roadmap item
20 flags a hardcoded fallback recipe there — and deliberately so: a fabricated
menu is worse than a visible failure, because a made-up idea then anchors a
real, paid stage-2 generation.

## Clearance arithmetic

`FridgeClearance.forIdea` iterates the **entered** list and asks, per item,
whether the idea claims it. That direction is the whole safeguard: an
ingredient the model invented is never iterated, so it cannot inflate the
count. Matching is case/whitespace-insensitive with containment both ways, so
"potato" matches "Potatoes" and "bread" matches "Stale Bread"; anything
cleverer would be a guess about food language that could silently over-count
the one number this screen must not inflate.

**One real bug the tests caught**: my first version wrote
`left.length == 1 ? 'stays' : 'stay'`, which renders "— potatoes stays." Verb
agreement follows the noun's number, not the count of leftovers, and the app
cannot know whether a single leftover is "potatoes" or "cheese". It is now
always "stay", matching the spec's own example; "cheese stay" is mildly odd
where "potatoes stays" is simply wrong.

## Kit-rule sites touched beyond this screen

**Wrap, never clip** — `grep -rn "scrollDirection: Axis.horizontal" lib/` now
returns **nothing**. Four sites:

1. `fridge_clearer_screen.dart` — the Time selector (the one that rendered
   "45+ M…").
2. `fridge_clearer_screen.dart` — the portions selector ("4 …").
3. `techniques_media_screen.dart` — the category bar. Was a horizontal
   `ListView`, so categories past the fold were invisible with no cue they
   existed, and the last visible one was sliced by the screen edge.
4. `one_pan_cooking_roadmap_screen.dart` — Cook Mode's kitchen-gear row. Not a
   selector, so strictly outside the rule's wording; a clipped gear chip is no
   more readable for being unselectable.

**Champagne selection** — three sites:

1. `fridge_clearer_screen.dart` — the new `_SelectChip` (ingredients, time,
   gear, portions), champagne fill + `terracottaOnLight` text at weight 500,
   quiet row surface + hairline when unselected.
2. `techniques_media_screen.dart` — categories, previously a terracotta fill.
3. `profile_screen.dart` — allergy chips, the **last** terracotta-fill
   selection left in the app (the diet chips moved during the palette sweep).

## Files touched

**New**
- `lib/models/fridge_idea.dart` — `FridgeIdea`, `FridgeClearance`,
  `parseFridgeIdeasJson`
- `test/models/fridge_idea_test.dart` (18 tests)
- `test/screens/fridge_clearer_redesign_test.dart` (19 tests)
- `docs/sessions/2026-08-22_fridge-clearer-redesign.md` (this file)

**Rewritten**
- `lib/screens/fridge_clearer_screen.dart` — input body, ideas body, both
  generation stages, and the new `_FridgeCard` / `_SettingsRow` /
  `_SegmentedRow` / `_SelectChip` / `_IdeaCard`. Deleted with the old flow:
  `GeneratedRecipeCard`, `_ScienceNotesDisclosure`, `_SectionCard`,
  `_TapChip`, `_PillOption`, `_RecipeIdea`, the per-chip icon maps, and the
  `_fetchPrecisionCards` / `ai-recipe-precision` call plus its three
  formatters.

**Changed**
- `lib/prompts/recipe_static_prompts.dart` — `buildFridgeIdeasStaticPrompt()`
- `lib/services/chef_service.dart` — `kChefCallSurfaceFridgeIdeas`
- `lib/screens/techniques_media_screen.dart`, `lib/screens/profile_screen.dart`,
  `lib/screens/one_pan_cooking_roadmap_screen.dart` — kit rules
- `test/services/chef_prompt_ordering_test.dart` — four surfaces, not three
- `test/widgets/generation_surface_bookmark_test.dart` — the
  `GeneratedRecipeCard` group removed with the widget
- `CLAUDE.md`, `docs/CHANGELOG.md`, `docs/DECISIONS.md`

## Tests and analyze

`flutter test`: **319 passing** (285 baseline − 3 deleted + 37 new), 0 failing.
`flutter analyze`: **44 issues**, 0 errors, 0 warnings — one below the ≤45
ceiling, and below the 45 this session started from. Palette guard green;
zero stray colour literals.

The three deleted tests covered `GeneratedRecipeCard`'s bookmark. They were
removed with the widget, not lost: `GeneratedRecipeActionsSheet` — now the only
surface a generated recipe arrives on — already had equivalent coverage in the
same file, and the file's doc comment records why the pair became a single.

New coverage: the one-screen structure with every cut explainer asserted
absent; no horizontal scroll view anywhere on the screen; chip
select/deselect; typed ingredient joining the same wrap as a removable ✕-chip
and coming back out; the For row defaulting silently from the profile; gear as
text chips with no per-chip icons; stage 1 making exactly one call and **zero**
recipe calls; clearance computed from the entered list including the
model-invented-ingredient case; the "X stays" phrasing; the header naming real
ingredients; no regenerate affordance; back preserving selections; malformed
stage-1 → error card with no recipe call; the static block travelling
separately from the query; choosing an idea firing exactly one recipe call
anchored on its title; the result arriving in the shared actions sheet;
**the stage-2 recipe carrying `RecipeOrigin.fridgeClearer` and the entered
ingredients**; the planner path landing on the same ideas screen; and a
malformed stage-2 keeping the menu.

## Dev verification

One real `ask-chef-harris` call (authenticated anonymous session, dev). No
migrations, no schema changes, no deploys, nothing touched on prod. That call
writes one `api_call_cost_log` row with `surface: 'fridge_ideas'`, which is
the intended behaviour rather than probe data — but it is a real row, and
`api_call_cost_log` is service-role-only so I could not read it back to confirm
the surface landed. Worth a glance in the Dashboard.

## Ambiguities

1. **When stage 2 fires.** The spec reads "tap a card → actions sheet …
   stage 2 … on Cook/Save/Plan"; the constraints read "all three actions
   trigger stage 2 first, then act on the result". Those cannot both be
   literally true — the sheet needs a real `CookModeRecipePayload` to mount its
   bookmark. Resolved as: **tap runs stage 2 (with an inline "Writing the
   recipe…" on that card), then the sheet opens with the real recipe.** The
   choice is the tap; all three actions still act on a real recipe, never a
   summary. One method to move if the other reading was meant.
2. **The `ai-recipe-precision` "Science Notes" call is gone from this flow.**
   Its only display surface was the inline result card the spec replaces, and
   the spec gives it no new home. Deleting the call rather than making one up
   also shrinks roadmap item 2's exposure — but it is an unsigned removal of a
   real feature, and it is the one thing here most worth a ruling.
3. **"Fits one screen, no scroll"** is honoured for the *page*: the body is a
   `Column`, and there is no `ListView`. The chip area inside the ingredients
   card scrolls internally if the user adds enough ingredients, because the
   alternative is chips escaping the card. Asserted as "no `ListView` on the
   input screen" rather than "nothing scrolls".
4. **"Gear wraps to 2 lines max"** is achieved by shortening the labels
   ("Blender/Processor" → "Blender") rather than by constraining the `Wrap`,
   which cannot enforce a line count without clipping — and clipping is the
   thing the other kit rule forbids. At 360dp the six chips take two lines.
5. **The free-tier cap counts stage 1 only.** Not specified. Reasoning in
   `docs/DECISIONS.md`; it means a user can browse three ideas and cook one for
   a single unit of their weekly allowance.
6. **Planner path skips the actions sheet.** With `returnCookModePayload`,
   committing pops the payload straight back to the planner, which is already
   waiting to place it into a chosen day — the spec's "save one into this day"
   behaviour. Showing Cook/Save/Plan there would offer actions the planner
   context has already decided.
7. **Time and gear are still absent from the stage-1 prompt as hard
   constraints** — they are context lines, and a model that ignores a 15-minute
   box will produce a 40-minute idea whose `total_time_minutes` says so. The
   card shows the real number, so the user can see the mismatch; enforcing it
   would need a validator, which is roadmap item 1's territory.
