# Session — Cook Mode layout finalization, Unit B (2026-08-22)

## Prompt (verbatim)

```
AUTONOMY: Full file/test/git permission. No confirmation questions.
STOP CONDITIONS: Prod Supabase = stop-and-report always. Dev
(suuafglvrxrllnhipkiv) read-only plus app-level test writes through
existing services; no migrations, no deploys. Spec ambiguity = note
and continue, never guess.

BUILD — COOK MODE LAYOUT FINALIZATION (Unit B of the signed Cook
Mode/Palette card, 2026-08-21). Spec embedded verbatim below — WHAT
and WHERE; you own HOW. Read docs/sessions/2026-08-22_palette-v12-
swap.md first: this build sits on the consolidated tokens.

SCOPE FENCES, read before the spec:
- Pre-cook moment merge and the SOS sheet REDESIGN are separate
  queued builds — NOT this one. The SOS square placement below is in
  scope; it opens whatever SOS surface exists today.
- Grep by class name first; the spec warns ChecklistScreen lives in
  one_pan_cooking_roadmap_screen.dart — filenames are not ground
  truth.

━━━ SPEC (verbatim, design_spec_cookmode_palette_2026-08-21.md §3–5) ━━━
Single focused layout, one step dominant. Composition top→bottom:
1. Header: back arrow (+ home glyph per hub depth rule) · "Cook
   mode" · SOS square top-right (persistent, findable in panic)
2. Progress bar, tappable → overview sheet. Label "Step N of M ·
   step title"
3. Step card (ivory):
   - Dominant action line = the instruction itself, imperative, ≤12
     words target (generation-prompt implications are strategy-chat
     territory — do NOT touch generation prompts this build)
   - Meta pill row: heat (champagne tint, only warm pill) · ~time
     (neutral) · timer state as quiet text in the same row
   - Cue panel (sage tint): promoted ABOVE detail. Label "HOW YOU
     KNOW IT'S RIGHT" (readiness) / "...IT'S DONE" (doneness) per
     signed phase field · one sensory sentence (signed vocabulary) ·
     "Not there yet, or gone too far?" inline expander with signed
     remedy phrases
   - Demoted DETAIL block: original bullets as small muted prose +
     cut pill(s) → diagram sheet
   - NEXT-STEP WHISPER: strip fused to card's bottom edge, neutral
     pill tone, small caps "NEXT" + one short line of the next step.
     No icon competition, visibly quieter than everything above.
     Tap → opens overview sheet. No previous-step whisper
     (deliberate asymmetry).
4. Bottom: pause as outlined icon square · one terracotta CTA "Next
   step" · Ask-Chef-Harris demoted to hint text / SOS. Finish &
   Plate ONLY at end of overview sheet list, never per-step.

Overview sheet (tap progress bar or whisper) — TWO PANES. Standard
sheet chrome (grab bar, dimmed background visible, drag-down /
background-tap / X dismissal, never stacks — pane swap only):
- All steps pane: done steps faded with check · current highlighted
  (champagne) · upcoming tappable to jump · Finish & Plate at list
  end
- Ingredients pane: full ingredient list with quantities — answers
  mid-cook "how much X?" in one tap. Servings scaling read-only here
  (adjuster lives on recipe overview per pre-cook merge decision).

Tiered mid-step access: Tier 1 on-screen = whisper. Tier 2 one tap =
steps pane, ingredients pane, diagram pill. Tier 3 evidence-gated:
timer promotion to a chip ONLY on device evidence — do NOT pre-build.
━━━ END SPEC ━━━

CUE PANEL DATA CONTRACT (known gap, handle don't guess): generated
steps may not yet carry structured cue fields. Build the panel
against an optional cue structure (cue_key, phase, sentence, remedy
phrases) per the signed schema (phase: readiness|doneness; no_cue
escape). When a step has no cue / no_cue: hide the panel entirely —
never invent a cue, never show an empty frame. Wiring generation to
emit cues is a separate build; if today's payload has zero cue
support, ship the panel dormant-but-tested and say so plainly.

All strings are placeholders — mark each // PLACEHOLDER (whisper
"NEXT" label + phrasing, cue panel labels, CTA labels).

SIDE PART 1 — champagne conversion: the 13 terracotta-alpha-wash
sites deferred from 15325f5 convert to champagneTint per the spec's
champagne semantic (heat pills, step-number chips, SOS chips). In
scope now precisely because this build owns those elements.

SIDE PART 2 — gold earned-moments: IF 15325f5 did not already move
the four named gold moments (counted-verdict badge, rescue
milestone, tier-up star, share accent) onto the gold tokens, do that
token swap now — color only, no layout. If already done, one line
confirming it.

SIDE PART 3 — dev paywall skip: in dev-flavored builds (however the
DEV badge is currently gated), never show PaywallScreen — route
straight through. Release behavior unchanged. One test.

SIDE PART 4 — housekeeping: fix the phantom "CLAUDE.md Roadmap item
28" comments in one_pan_cooking_roadmap_screen.dart and
cook_session_storage_service.dart (item 28 never existed; week
anchoring was folded into 27).

TESTS: keep all 266 green. Add: composition renders (header/
progress/card/whisper/bottom bar); whisper shows next step and taps
open the sheet; last step shows no whisper; cue panel readiness vs
doneness labels, expander, and hidden-when-absent; overview panes
swap without stacking; jump-to-step works; Finish & Plate only at
list end; one-terracotta-CTA assertion; paywall skip on dev.

VERIFICATION:
- flutter test all passing, exact count; flutter analyze ≤46, exact
  count; palette guard test still passing
- git status clean, committed and pushed

DOC STEP (permanent rule): commit this prompt verbatim + full report
to docs/sessions/2026-08-22_cookmode-unit-b.md. Update
docs/CHANGELOG.md.

Report verbatim: layout implementation notes, cue-data-contract
status (live or dormant), the four side parts, files touched,
test/analyze counts, push confirmation, ambiguities.
```

---

## Layout implementation notes

### The structural decision: two bodies, one screen

`build` now branches on a single getter:

```dart
bool get _isFocusedCook => _cookStarted && _activeStepIndex != null;
```

True → `_buildFocusedBody()`, the new composition. False → `_buildPreCookBody()`,
which is the previous screen **moved verbatim**, not rewritten. That split is
what keeps the scope fence honest: before Start the screen is still the
pre-cook body (the subject of the separate merge build), and after the last
step `_activeStepIndex` is null and the finished state keeps its existing
bottom bar. The focused layout has nothing to focus on in either case.

The header is shared by both, because the SOS square has to be **persistent** —
findable in a panic means it does not appear only once you have pressed Start.

### The card

`_FocusedStepCard` is a single ivory `Container`, `clipBehavior: antiAlias`, so
the whisper can be fused flush to its bottom edge with no gap and no second
card. Reading order top to bottom: action line (`headlineSmall`, w900) → meta
row → cue panel → detail → whisper.

The meta row is a `Row`, not a `Wrap`, so the three elements cannot reflow into
a stack of pills and break the "one warm pill" read. Heat is `_MetaPill(warm:
true)` (champagne), time is `_MetaPill(warm: false)` (neutral pill tint), and
the timer is a `Flexible` `Text` in the same row — not a third pill. `warm` is
deliberately a bool budget rather than a colour parameter, so nothing can quietly
add a second warm pill.

The detail block keeps the bullets but at `bodySmall`, 68% charcoal, under a
quiet `DETAIL` label. That inversion is the point of the whole card: the bullets
used to be the loudest thing on it, which put procedure above judgement.

### The whisper

`_NextStepWhisper` is neutral pill tint, small-caps `NEXT` + one ellipsised
line, no icon. It is only built when `nextStep != null`, so the last step has
none — and there is no previous-step whisper anywhere, which is the asymmetry
the spec asks for. Tapping it opens the same overview sheet the progress bar
opens: "where am I" and "what's coming" have one answer.

### The overview sheet

`_CookOverviewSheet` is a `StatefulWidget` holding one bool, exactly like the
Weekly Planner's add sheet — pane swap inside one sheet, never a second sheet.
Both panes carry the full chrome (grab bar from `AppBottomSheet`, explicit X),
and the ingredients pane has a back arrow to pane 1 rather than closing.

Jump-to-step is `_jumpToStep`, and it makes a judgement the spec did not
specify: **everything before the target is marked done and everything after is
cleared.** Jumping forward is the user saying they have done those steps;
jumping back is them saying they have not. The alternative — leaving the
completed set untouched — produces a progress bar that disagrees with the step
you are on, and a set with holes in it that nothing else in the screen knows how
to render. Flagged under ambiguities.

Progress is `completedSteps.length / steps.length`, not `activeIndex / length`,
precisely so a backward jump moves the bar back.

### Bottom bar

`_FocusedCookBottomBar`: an outlined 52×52 pause square, one terracotta
`FilledButton`, and Ask-Chef as a `TextButton` hint. There is a test asserting
exactly one `FilledButton` on screen. **Finish & Plate is absent** — it now
exists only at the end of the overview sheet's step list, because it skips every
remaining step and fires a permanent ledger write, which should not sit under
the user's thumb for the whole cook.

`_CookPlayerBar` (the old two-row player with its own Finish & Plate, Ask-Chef
button and pause) was deleted, 5,620 characters.

---

## Cue data contract: **LIVE**, not dormant

The prompt anticipated that generated steps might not carry cue fields yet.
They do — the contract is wired end to end, and I verified each hop rather than
assuming:

- **Prompt**: both recipe surfaces' static blocks declare
  `"sensory_cue": "..."` as a required field with the closed key list and a
  selection rule (`lib/prompts/recipe_static_prompts.dart:40, 55, 81, 94`).
- **Parse**: `_readDeclaredSensoryCueForStep` in `chef_recipe_parser.dart`
  validates the declared value against `SensoryCueVocabulary.allKeys` and falls
  back to `no_cue` on absent / wrong-type / unknown.
- **Payload**: `CookModeStepPayload.sensoryCue` is non-null, defaulting to
  `noCueKey`, and round-trips through both codecs.
- **Render**: `SensoryCueVocabulary` supplies `phase`, `harrisSays`,
  `ifNotReady`, `ifOvershot`, `action` and `safetyNote` — all signed, all
  app-side, never sent in a prompt.

So the panel ships live. Its tests assert against the real vocabulary entries
(`oil_shimmers` for readiness, `fork_slides_easily` for doneness), not stubs —
the readiness test asserts the exact `harrisSays` string the vocabulary holds,
so a change to signed voice text fails the test rather than silently shipping.

`no_cue` is handled by the **card**, not the panel: `_FocusedStepCard` omits
the widget entirely. The panel additionally returns `SizedBox.shrink()` for an
unrecognised key — two independent guards, because an empty sage frame teaches
the user to stop looking at the one panel that matters.

**One cue presentation, not two.** `_SensoryCueCard` (deep-forest tint, remedy
in a modal sheet) and `_SensoryCueDetailSheet` were deleted, and the pre-cook
step list now renders the same `_CuePanel`. Keeping the old widget for the
pre-cook body would have re-created exactly the two-implementations drift the
palette sweep just finished removing. The pre-cook body's *layout* is still
untouched; only the cue widget inside it became the signed one.

---

## The four side parts

**1 — Champagne conversion.** Eight of the thirteen deferred sites converted to
`champagneTint` (fills only; borders and glyphs stay terracotta, which is what
gives these pills their edge): the Fridge Clearer info pill, Home's resume-cook
panel and its inner icon square, onboarding and paywall feature circles, the
profile diet chip's selected fill, the culinary matrix card panel, and the
upgrade sheet badge. **Three of the thirteen became gold instead** (share card
×2, celebration sheet — see part 2). The remaining two were never fills: a
`focusedBorder` in Fridge Clearer and a bullet dot in recipe details. Cook
Mode's own heat pill and the step-number chip in the overview sheet are
champagne by construction in the new widgets.

**2 — Gold earned moments. `15325f5` had NOT done this; done now.** Colour
only, no layout:

- `WasteLedgerCelebrationSheet` — this is both the counted-verdict badge *and*
  the rescue milestone (`LedgerVerdictSheet` has no counted variant, by design).
- `ConfidenceTierUpSheet` — **correcting my own report from `15325f5`**, which
  named `UpgradePromptSheet`'s star as the tier-up. It is not: that is the
  subscription upsell. The tier-up is the Confidence Climb sheet, and it was
  deep forest.
- `PostCookShareCard` — both accents.

Treatment is `goldEarnedBadgeTint` fill + a thin `goldEarnedFill` border +
`goldEarnedOnLight` glyph. The one exception is the share card's eco glyph,
which sits on the deep-forest gradient and uses `goldEarnedFill` — the on-light
value exists to survive ivory, not darkness.

**`UpgradePromptSheet`'s star deliberately stays terracotta.** It is a sales
CTA, and the rule is that gold never goes on a CTA.

**3 — Dev paywall skip.** A route-level `redirect` on `AppRoutes.paywall` in
`lib/nav.dart`, not a guard at the two call sites. Both entry points
(onboarding's skip, `UpgradePromptSheet`'s CTA) are covered at once, and a
third added later cannot forget. `kIsDevEnvironment` is a compile-time
constant, so the branch folds away in a prod build exactly like the DEV badge.
Two tests: the widget test asserts the dev arm *and* the prod arm's contract
(rather than skipping when run with `--dart-define=OPTIMEAL_ENV=prod`), and a
structural test asserts the route carries a redirect at all — otherwise
deleting it would pass unnoticed in a prod-flavoured run.

**4 — Phantom item 28.** Eleven references across five files (the prompt named
two; `ledger_service.dart`, `ledger_verdict.dart` and
`generated_recipe_actions_sheet.dart` had them too). All now point at the
rescue-provenance rule / `RecipeOrigin`, which is what they always meant.
`grep -rn "item 28" lib/` returns nothing.

---

## Files touched

**New**
- `test/screens/cook_mode_focused_layout_test.dart` (17 tests)
- `test/screens/dev_paywall_skip_test.dart` (2 tests)
- `docs/sessions/2026-08-22_cookmode-unit-b.md` (this file)

**Changed**
- `lib/screens/one_pan_cooking_roadmap_screen.dart` — the layout: split body,
  `_openOverview` / `_jumpToStep`, and the new `_SosSquare`,
  `_CookProgressBar`, `_FocusedStepCard`, `_MetaPill`, `_CuePanel`,
  `_RemedyLine`, `_NextStepWhisper`, `_FocusedCookBottomBar`,
  `_CookOverviewSheet` + its two panes and two rows. Deleted `_CookPlayerBar`,
  `_SensoryCueCard`, `_SensoryCueDetailSheet`.
- `lib/nav.dart` — paywall redirect
- `lib/widgets/waste_ledger_celebration_sheet.dart`,
  `lib/widgets/confidence_tier_up_sheet.dart`,
  `lib/widgets/post_cook_share_card.dart` — gold
- `lib/screens/fridge_clearer_screen.dart`,
  `lib/screens/home_dashboard_screen.dart`,
  `lib/screens/onboarding_screen.dart`, `lib/screens/paywall_screen.dart`,
  `lib/screens/profile_screen.dart`, `lib/widgets/culinary_matrix_card.dart`,
  `lib/widgets/upgrade_prompt_sheet.dart` — champagne
- `lib/services/cook_session_storage_service.dart`,
  `lib/services/ledger_service.dart`, `lib/services/ledger_verdict.dart`,
  `lib/widgets/generated_recipe_actions_sheet.dart` — phantom item 28
- `CLAUDE.md`, `docs/CHANGELOG.md`

---

## Tests and analyze

`flutter test`: **285 passing** (266 baseline + 19 new), 0 failing.
`flutter analyze`: **45 issues**, 0 errors, 0 warnings — one *below* the 46
baseline, because deleting `_CookPlayerBar` and the two cue widgets removed a
`prefer_const` info. Palette guard green; a comment-stripping scan of `lib/`
still reports **0 stray colour literals**.

New coverage: the whole composition renders (header, SOS, progress label,
progress bar, exactly one step card, whisper, bottom bar); exactly one
`FilledButton` and one `OutlinedButton`; Finish & Plate absent from the step
screen on two different steps; exactly one champagne container on the card;
the whisper names the genuinely-next step and disappears on the last one;
tapping it opens the sheet; readiness vs doneness labels with the signed
sentence asserted verbatim; the remedy expander opening **inline** with no
`BottomSheet` and the step still visible; a `no_cue` step showing neither panel
nor expander; the sheet listing every step; panes swapping with exactly one
`BottomSheet` throughout and back returning to pane 1; the ingredients pane
answering "how much X" with quantities; jump-to-step landing on the right step
with the right cue; Finish & Plate present once and positioned below the last
step row; SOS present before Start and during the cook; and the paywall
redirect both ways.

---

## Ambiguities

1. **Jump-to-step rewrites the completed set** (everything before the target
   done, everything after cleared). The spec says "upcoming tappable to jump"
   and nothing about what happens to the steps in between. My reasoning is in
   the notes above; the alternative leaves a progress bar that disagrees with
   the step you are on. One method to change if Harris wants the other reading.
2. **`CuePhase.during` has no signed label.** The spec gives two labels for the
   two signed phases; `during` is a schema addition already flagged to Harris
   (2026-08-17). It keeps its existing "WHILE IT COOKS" rather than being
   forced into one of the two signed phrasings.
3. **"≤12 words" on the action line is not enforced.** The line renders
   `step.actionTitle` as generated, and the prompt explicitly forbids touching
   generation prompts this build. Long titles wrap rather than truncate — a
   truncated instruction is worse than a two-line one.
4. **The finished state still uses the old body and `_CookModeBottomBar`.** The
   spec covers the cooking layout; once `_activeStepIndex` is null there is no
   dominant step. It looks unlike the focused layout, which may or may not be
   wanted.
5. **The pre-cook body overflows horizontally below ~600 logical px** in the
   test viewport (`_MiniPill` / `_InfoPill` rows in the old step cards). It is
   pre-existing, in code this build does not own, and my tests widen the
   viewport rather than mask it — but it is real and the pre-cook merge build
   should know.
6. **`UpgradePromptSheet` star left terracotta** — reasoned above, but it is a
   judgement about which "tier-up" the spec meant, and it corrects what I
   reported last session.
7. **The SOS square opens today's `_ChefSosSheet` unchanged**, per the fence.
   Its own redesign is queued.
8. **Cut pills**: the spec says "cut pill(s) → diagram sheet". The card renders
   the technique and cut `DiagramPill`s that already existed; there is no
   separate per-ingredient cut pill row in the step card (that lives in the
   pre-cook checklist). Read as the same thing; flagging in case it is not.
