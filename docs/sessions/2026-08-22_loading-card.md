# Session — Generation loading card (2026-08-22)

## Prompt (verbatim)

```
AUTONOMY: Full file/test/git permission. No confirmation questions.
STOP CONDITIONS: Prod Supabase = stop-and-report always. Dev
(suuafglvrxrllnhipkiv) read-only plus app-level test writes through
existing services; no migrations, no deploys. Spec ambiguity = note
and continue, never guess.

BUILD — GENERATION LOADING COMPONENT ("waiting card"). Signed spec
embedded verbatim below — WHAT and WHERE; you own HOW.

━━━ SPEC (verbatim, design_spec_loading_card_2026-08-21.md) ━━━
Scope: One reusable loading component shown during AI generation.
Appears at ALL FOUR generation points: Fridge Clearer stage 1 (ideas
menu) · Fridge Clearer stage 2 (full recipe) · Custom recipe
generation · planner-initiated generation paths. One component,
parameterized by stage.

Visual (SIGNED — spoon version): Ivory card centered on canvas,
generous padding. Illustration: wooden spoon stirring a terracotta
bowl. Diagram-style rules apply: black perimeter outlines on every
shape, terracotta bowl (#C05C35) with champagne batter surface
(#F7DBCB), sage elliptical base shadow (#DDE6C6). Spoon in wood tan
(#D9A066, shading #C68B4E) — deliberately OUTSIDE semantic tokens
(illustration color, cannot be read as gold/earned). Animation:
spoon orbits/oscillates in the bowl, dipping behind the far rim; 3
small batter pearls (terracotta family + one gold) orbit with it; 3
pulsing dots below the text. Calm speed — charming, not busy. NO
progress bar (signed): generation time is unpredictable; a stalling
bar is worse than none. Pulsing dots = "alive", promising nothing.

Two stages, two behaviors (SIGNED): Stage "finding ideas" (short
wait, seconds): ONE static line + one sub-line. No cycling — would
flicker. Stage "writing recipe" (long wait): lines CYCLE ~2.5s.
Lines narrate REAL generation work (using the person's actual
ingredients, pan ordering, adding sensory cues) — teaches what Chef
Harris does, builds trust. Because they are claims about real
behavior, they must stay truthful to the pipeline.

Placeholders (Harris authors — persona batch; mark // PLACEHOLDER):
ALL lines and sub-lines, both stages. Prototype lines ("Looking at
what you've got…", "Setting the pan order — onions before zucchini,
always") are placeholders illustrating narrate-real-work.
Ingredient-aware lines (inserting the user's actual ingredients) are
nice-to-have — static lines are the v1 floor; if ingredient-aware is
cheap, do it, else flag.

Implementation note (sizing, not prescriptive): CustomPainter or
simple widget tree + AnimationController tweens; no Lottie/rive.
Spoon dips behind bowl rim via paint order.
━━━ END SPEC ━━━

IMPLEMENTATION NOTES:
- TOKEN/GUARD RECONCILIATION: declare wood tan + shading in
  app_design_tokens.dart under a clearly-marked ILLUSTRATION section
  (doc comment: illustration-only, not semantic, never for UI
  chrome) so the palette guard stays intact and pins them. Do not
  weaken the guard.
- FOUR-POINT WIRING against current code (post-650f52b): stage-1
  wait after "Let's cook" → component in "finding ideas" mode. The
  stage-2 inline "Writing the recipe…" text state on the tapped idea
  card from 650f52b is SUPERSEDED by this component in "writing
  recipe" mode — reconcile the interaction (component may present
  over/instead of the card area; keep the tapped card's identity
  visible if cheap, note what you chose). Custom recipe generation
  and planner-initiated generation paths → same component, correct
  mode. Grep for any remaining ad-hoc spinners/progress indicators
  on generation waits and replace; list each site.
- TRUTHFULNESS RULE for cycling lines: only claim work the pipeline
  actually does (ingredient use, sequencing rules, sensory-cue
  attachment are real; do not claim e.g. nutrition analysis). Keep
  placeholder lines within this rule.
- ONBOARDING KINSHIP TOUCH-UP (one small item): slide-1 spoon
  illustration from bca2bd5 used champagne for the spoon because
  wood tan had no token; now it does — switch the onboarding spoon
  to the wood-tan tokens so the two illustrations are kin, per that
  spec's "matches loading card" line. Nothing else on onboarding.
- Animation: respect reduced-motion accessibility setting (static
  illustration + dots only) — cheap to honor, note it.

TESTS: keep all 334 green. Add: component renders both modes;
stage-1 shows static line (no cycling); stage-2 cycles; component
present at all four generation points (widget-level where services
allow, structural assertion otherwise — say which); no progress bar
widget in the component; guard still green with the new illustration
tokens pinned.

VERIFICATION:
- flutter test all passing, exact count; flutter analyze ≤44, exact
  count
- git status clean, committed and pushed

DOC STEP (permanent rule): commit this prompt verbatim + full report
to docs/sessions/2026-08-22_loading-card.md. Update
docs/CHANGELOG.md.

Report verbatim: wiring decisions at the four points (esp. the
stage-2 supersession), ad-hoc indicator sites replaced, ingredient-
aware feasibility verdict, files touched, test/analyze counts, push
confirmation, ambiguities.
```

---

## The component

`GenerationLoadingCard(stage:, subject:, ingredients:)` —
`lib/widgets/generation_loading_card.dart`.

**The illustration** is one `CustomPainter` on a single `AnimationController`
(2.6s, repeating). The spoon swings on `sin(t·2π)·2.4` rather than orbiting a
full circle — a person stirring while they think, not a spinner wearing a spoon
costume. The **dip behind the far rim is pure paint order**: `isBehind =
sin(angle) < 0`, and the spoon is drawn before the champagne batter ellipse on
the far half of the swing and after it on the near half. Perimeter outlines are
drawn last so nothing paints over them, which is the diagram family's rule.

Three pearls ride the batter surface at fixed angular offsets from the spoon,
so they read as being pushed by it rather than orbiting independently.

**The dots** share the same controller with a per-dot phase offset, so they read
as a wave rather than a blink. They are the whole "no progress bar" argument in
one widget: alive, promising nothing.

**Copy advances off the animation clock**, not a second `Timer`. A `Timer` would
keep cycling behind a frozen illustration under reduced motion; driving both
from one controller means stopping the controller stops everything.

**Reduced motion** (`MediaQuery.disableAnimationsOf`) stops the controller and
paints the illustration at a fixed phase of `0.12` — composed, rather than
frozen wherever it happened to be. The dots hold at a mid swell. The card still
says "something is happening" through its copy. The test asserts this by
`pumpAndSettle()` returning at all, which it cannot do if the controller is
still running.

## Wiring decisions at the four points

**1 — Fridge Clearer stage 1.** The card replaces the *input body* while the
menu call is in flight, and the CTA bar is **removed from the tree** rather than
disabled. A disabled button sitting under a full-canvas card is just something
else to look at. `_GenerateCtaBar` lost its `isLoading` parameter entirely —
it no longer has a loading state to render.

**2 — Fridge Clearer stage 2: the supersession.** 650f52b put a small spinner
and "Writing the recipe…" inline on the tapped idea card. That is gone;
`_IdeaCard` lost its `isCommitting` parameter and the whole branch. The card now
**replaces the ideas list**, and carries the chosen dish's title as its
`subject` line — which is how the tapped card's identity stays visible, and it
was cheap (one existing string, one optional parameter). What the user sees is
their choice, named, with the spoon working under it.

Both stages route through one `_buildBody(...)`, which puts the wait ahead of
both the input and the menu. The mode is derived from `_committingIdeaIndex`
being set, which is already the screen's "stage 2 is in flight" state — no new
flag.

**3 — Custom recipe creation.** The sheet body is replaced wholesale by the card
in `writingRecipe` mode, inside a fixed 420px height so the sheet does not
resize under the user mid-generation. The in-button spinner and its
"Generating…" label are gone; the CTA is a plain label again.

**4 — Planner-initiated paths.** These are **not a fourth implementation**. The
Weekly Planner's two generation entry points push the Fridge Clearer as a picker
(`AppRoutes.fridgeClearerPicker`) and open `CustomAiRecipeCreatorSheet` — both
already covered by 1–3, and both get the card automatically. A test asserts the
planner contains those two entry points and **contains no `askChefHarris` call
of its own**, so if it ever grows a third generation path this fails rather than
silently going uncovered.

## Ad-hoc indicator sites replaced

| site | was | now |
|---|---|---|
| `fridge_clearer_screen.dart` `_GenerateCtaBar` | spinner + "Chef Harris is thinking…" in the CTA | card, stage 1 |
| `fridge_clearer_screen.dart` `_IdeaCard` | spinner + "Writing the recipe…" inline on the card | card, stage 2, with the dish named |
| `custom_ai_recipe_creator_sheet.dart` | spinner + "Generating…" inside the CTA | card, stage 2 |

**Deliberately left alone**, and pinned by an allow-list in the test so a new
one has to be justified there:

- `weekly_planner_screen.dart` ×2 — a slot **write** in flight and the day-card
  "Saving…" row. Not generation.
- `paywall_screen.dart` — purchase in flight.
- `profile_screen.dart` — account linking in flight.
- `post_cook_share_card.dart` — image render in flight.
- `one_pan_cooking_roadmap_screen.dart` ×2 — the Cook Mode step progress bar
  (a real, knowable progress, unlike a generation), and the **Chef SOS typing
  bubble**. SOS is a conversation with its own chat affordance, and it is not
  one of the four generation points; swapping a chat's typing indicator for a
  full-canvas card would be wrong.

The test walks `lib/` and fails on any `CircularProgressIndicator` or
`LinearProgressIndicator` outside that list.

## Ingredient-aware feasibility: **shipped, where a list exists**

Verdict per surface:

- **Fridge Clearer stage 2 — done.** The screen already holds
  `_sortedIngredients`, so the first cycling line becomes "Reading your zucchini
  and eggs…". It is truthful: those exact strings are in the prompt for that
  call.
- **Fridge Clearer stage 1 — not applicable.** That stage does not cycle at
  all, so there is no line to personalise.
- **Custom recipe creator — not possible today.** It takes free text ("keto
  rösti bowl") and has no structured ingredient list before generation. It uses
  the generic line, which is the specced v1 floor.

The substitution needs ≥2 ingredients; below that it falls back to the generic
line rather than producing "Reading your zucchini and…". Both cases are tested.

## Tokens and the guard

`illustrationWoodTan` `#D9A066` and `illustrationWoodTanShade` `#C68B4E` live in
a new **ILLUSTRATION ONLY** section of `AppDesignTokens`, with a doc comment
stating they are not semantic and must never be used for UI chrome. The reason
is in the comment: a wooden spoon has to look like wood, and the nearest
semantic — gold — means "earned", which a stirring spoon must never claim.

**The guard was not weakened.** Both values are added to its pinned map
alongside the twelve v1.2 hexes, so they cannot drift either, and the
literal-sweep is untouched — the tokens file is still the only place in `lib/`
allowed to declare a colour.

## Onboarding kinship

Slide 1's spoon switched from `champagneTint` (the stand-in from bca2bd5, when
no wood token existed) to `illustrationWoodTan`, and gained the same single
shading crescent on the head. The two illustrations now share a palette and a
modelling convention. Nothing else on onboarding was touched.

## Files touched

**New**
- `lib/widgets/generation_loading_card.dart`
- `test/widgets/generation_loading_card_test.dart` (12 tests)
- `docs/sessions/2026-08-22_loading-card.md` (this file)

**Changed**
- `lib/theme/app_design_tokens.dart` — ILLUSTRATION ONLY section
- `test/theme/palette_token_guard_test.dart` — the two new values pinned
- `lib/screens/fridge_clearer_screen.dart` — `_buildBody`, both stages wired,
  `_IdeaCard.isCommitting` and `_GenerateCtaBar.isLoading` removed
- `lib/widgets/custom_ai_recipe_creator_sheet.dart` — sheet body swap, CTA
  spinner removed
- `lib/widgets/onboarding_visuals.dart` — wood-tan spoon + shading
- `CLAUDE.md`, `docs/CHANGELOG.md`

## Tests and analyze

`flutter test`: **346 passing** (334 baseline + 12 new), 0 failing.
`flutter analyze`: **44 issues**, 0 errors, 0 warnings — at the ≤44 ceiling and
unchanged from where this session started. Palette guard green, including the
two new pinned illustration values.

Coverage, and which kind each is:

- **Widget-level**: stage 1 showing one static line and still showing the same
  line nine seconds later, with none of the long-wait lines ever appearing;
  stage 2 moving to the second line after one interval; the `subject` line
  naming the dish; the ingredient-aware line naming the user's own
  ingredients; the fallback with too few ingredients; no progress indicator of
  either kind in either mode; reduced motion settling.
- **Pure**: the truthfulness rule, asserted from the other side — every line
  and sub-line is checked against a forbidden-word list ("nutrition",
  "calorie", "macro", "allerg", "safe", "cost", "budget", "price").
- **Structural** (source assertions, stated as such in the file): the four
  wiring points, and the no-ad-hoc-spinner sweep. Three of the four surfaces
  reach for Supabase / entitlement / usage services on the way into a
  generation, so pumping them to observe a transient loading frame would test
  the mocks rather than the wiring; the fourth is not a screen at all.

## Ambiguities

1. **The gold pearl breaks the standing "gold = earned only" rule.** The spec
   asks for "3 small batter pearls (terracotta family + one gold)" explicitly,
   so it is implemented — but this is the one place gold appears outside an
   earned moment, and it is flagged in a code comment as well as here. At ~2px
   it reads as a highlight rather than a badge. Easy to make it a third
   terracotta if the rule should hold absolutely.
2. **The Chef SOS typing indicator was left alone.** SOS is an AI call, so it
   arguably qualifies — but it is not one of the four named generation points,
   it is a conversation rather than a recipe generation, and it already has a
   chat-appropriate affordance. Replacing it would mean a full-canvas card
   inside a chat thread.
3. **Custom creator's fixed 420px height** while generating is a chosen number,
   not a specced one — it stops the bottom sheet resizing under the user
   mid-generation. Worth a device look.
4. **Reduced motion holds the illustration at phase 0.12**, an arbitrary but
   deliberate choice: it puts the spoon slightly off-centre and in front of the
   rim, so the still frame is composed rather than looking stuck mid-swing.
5. **The line-cycling clock is the animation controller.** Under reduced motion
   the copy therefore stops cycling too. That is a defensible reading of
   "static illustration + dots only", but if Harris wants the copy to keep
   narrating while nothing moves, it is a small change.
6. **`_GenerateCtaBar` lost its loading state entirely** rather than keeping a
   disabled variant. The bar is removed from the tree during generation, so
   there is nothing for a loading style to describe.
