# Session — Design QA polish round (2026-08-23)

Share card, upgrade-sheet timing, shared illustration, stage-1 freshness,
safety matcher tightening, H12 ruling, name-list ratification.

---

## The prompt, verbatim

```
PROMPT — Design QA polish round (illustration, share card, upgrade-sheet timing,
stage-1 freshness) + safety matcher tightening + H12 ruling to repo

AUTONOMY: full, hands-free. Stop conditions: any prod Supabase contact (prod is
link-pinned; never relink). No dev DB work is in scope for this prompt — if you
think a migration is needed, stop and report instead. Genuine spec ambiguity:
note it, pick the conservative reading, continue.

Read first: CLAUDE.md, docs/sessions/2026-08-23_safety-validator.md, the most
recent docs/sessions/ entry (dev entitlement fix, if present). CLAUDE.md drifts;
verify every claim against live code. GREP BY CLASS NAME across all .dart files
before touching any file — filenames and class names are mismatched in this
codebase.

This is a FIX round: no new features, no redesign, no new surfaces. Every item
below corrects an already-built surface against its signed spec. Keep diffs
narrow.

==================================================================
PART 1 — Shared spoon-bowl illustration (loading card + onboarding slide 1)
==================================================================

DEVICE FINDING (design chat, 22 Aug, from Pixel screenshots):
- Onboarding slide 1 illustration renders as a detached terracotta dome + a
  floating spoon (reads as a hat and a lollipop).
- Loading card: spoon paddle crosses/exits the bowl rim mid-stir, and the bowl
  outline shows a notch at its base.

SIGNED SPEC (loading card card, §2, verbatim):
"Illustration: wooden spoon stirring a terracotta bowl. Diagram-style rules
apply: black perimeter outlines on every shape, terracotta bowl (#C05C35) with
champagne batter surface (#F7DBCB), sage elliptical base shadow (#DDE6C6). Spoon
in wood tan (#D9A066, shading #C68B4E) — deliberately OUTSIDE semantic tokens
(illustration color, cannot be read as gold/earned)"
"Animation: spoon orbits/oscillates in the bowl, dipping behind the far rim;
3 small batter pearls (terracotta family + one gold) orbit with it; 3 pulsing
dots below the text. Calm speed — charming, not busy"
"Spoon dips behind bowl rim via paint order."

SIGNED SPEC (onboarding card, slide 1, verbatim):
"Chef Harris intro — spoon-and-bowl illustration (diagram-style: black outlines,
terracotta bowl, wood-tan spoon — matches loading card)."

DO:
1a. Extract ONE shared painter/widget — SpoonBowlIllustration — used by both the
    loading card (animated) and onboarding slide 1 (static, animation phase
    fixed at a mid-stir pose). One source of truth; delete the slide-1 drawing
    code that drifted.
1b. Geometry fix: clamp the stir orbit so the spoon paddle stays inside the inner
    rim ellipse at EVERY animation phase. Paint order = far rim → batter surface
    → spoon → near rim (spoon dips behind the near rim). Close the bowl path so
    no notch appears at the base.
1c. Gold pearl stays (signed by design chat by name; illustration tokens are
    quarantined non-semantic — already in DECISIONS.md).
1d. Test: a golden/paint-order test is not required, but add a unit test that
    samples the spoon-paddle position across the full animation cycle and
    asserts it never leaves the inner rim ellipse. Widget test that onboarding
    slide 1 and the loading card both instantiate SpoonBowlIllustration.

==================================================================
PART 2 — Share card: two rule violations + template bug (PRIORITY)
==================================================================

DEVICE FINDING: the share card renders an "OPTIMEAL" wordmark + logo; renders
dark forest green with orange/gold branding; headline composes "learned to
sautéing".

SIGNED SPEC (post-cook + share card, §5, verbatim):
"Opens as a standard sheet (kit chrome) from the verdict's 'share it'. Contents:
- Dish name (large)
- Story line: 'Cooked from what was already in my fridge.' — brags
  resourcefulness, not app usage
- Gold-accented rescue chip ('N ingredients rescued', #FBEED8/#C77E1F) + neutral
  technique chip ('stir-fry, learned properly')
- Card background = canvas sage with thin gold border (earned framing); renders
  as an image for sharing
- GATE — branding line: app name + link slot exists in the layout but ships
  EMPTY until CH+EU trademark clearance. No public branding on any name before
  clearance (standing rule). Card is shippable as dish-and-story only.
- Deferred — photo: no camera step in v1 (permissions/storage/layout scope).
  Layout reserves a photo slot above the title so it can be added on tester
  signal without redesign.
- Didn't-count cooks can still share (dish + technique chip, no rescue chip)"

DO:
2a. REMOVE the wordmark, logo, and any app-name string from the rendered share
    image and the sheet. Keep the branding slot in the layout, EMPTY. Grep the
    whole lib/ tree for "OptiMeal"/"OPTIMEAL"/"Empyria"/"InstinKt" in any
    user-visible string on a shareable or exportable surface and report every
    hit (fix only the share card here; list the rest).
2b. Restyle to spec: canvas sage background (AppDesignTokens canvas token =
    #B3C29A), thin gold border, ivory chips, gold rescue chip
    (#FBEED8 fill / #C77E1F text). Use palette tokens, never literal hexes in
    the widget (palette guard must stay green).
2c. Headline template: fix verb-form composition so it never produces
    "learned to sautéing". Do not author new copy — the headline is persona
    batch // PLACEHOLDER; make the template grammatically safe with the
    technique NAME (noun form: "sautéing, learned properly" pattern), not a
    conjugated verb.
2d. Add a guard test in house style: the share-card render tree contains no
    string matching /optimeal|empyria|instinkt/i. This test is permanent until
    the trademark gate opens.

==================================================================
PART 3 — Upgrade sheet ("Nice cooking!") — TIMING defect only
==================================================================

DEVICE FINDING: a celebration-styled sales interstitial (star + "Nice cooking!"
+ terracotta Upgrade CTA) appears OVER the pre-cook surface mid-flow.

RULING (design chat, ratified by strategy chat): a sales sheet must never
interrupt an active cook path (pre-cook through post-cook verdict). Upgrade
star/CTA stays terracotta — gold never on sales (existing DECISIONS.md entry).

DO:
3a. Move the trigger: the upgrade sheet may only fire from Home, or after the
    post-cook verdict is DISMISSED (i.e. after the exit-to-Home CTA lands on
    Home). Never between pre-cook and verdict. Grep by class for every call
    site that can present this sheet; list them in the report.
3b. Restyle to a plain kit sheet: ivory surface, standard sheet chrome, drop
    the star glyph and the "Nice cooking!" headline, straightforward
    // PLACEHOLDER sales copy, terracotta CTA.
    [HARRIS ALTERNATIVE if he chose warmth: champagne icon chip, no star glyph,
    no "Nice cooking!" headline — otherwise identical.]
3c. Dev builds: confirm this sheet respects the dev-entitled state from the
    entitlement fix (if that build has landed) — an entitled user never sees
    it. Guard test: sheet cannot be presented while a cook session is active.

==================================================================
PART 4 — Fridge Clearer stage-1 freshness (VERIFY, do not change UI)
==================================================================

SIGNED: no regenerate button on the three-ideas screen (FC spec §5 + strategy
ruling). Escape path = back → "Let's Cook" re-runs stage 1 fresh.

DO:
4a. Verify by reading the code AND by one real dev run: back → Let's Cook with
    identical chips produces a FRESH stage-1 call and a new ideas set, not a
    cached or memoized identical three. If any memoization/equality short-circuit
    exists on the stage-1 path, remove it and add a test. Report the two
    ideas-sets side by side from the real run. No UI change.

==================================================================
PART 5 — Safety matcher tightening (from ad5e860 review)
==================================================================

5a. _hasAny in safety_validator.dart matches on word PREFIX. "rarely" trips H2's
    "rare"; "pinkish" trips "pink". Convert every pattern match in the safety
    validator to whole-word (optional trailing s/es where the name list already
    does that). Add tests: "rarely", "pinkish", "Mince the garlic" (regression)
    must NOT fire; "cook until no longer pink", "serve rare", "500 g mince" MUST.
5b. Name-list compound exclusions (DRAFT for Harris's signature, same status as
    the rest of the list): an animal name immediately followed by stock · broth
    · bouillon · gravy · fat · sauce (fish sauce, oyster sauce excluded — S1
    scan must still pass: use "sauce" only as a suffix exclusion, never add a
    shellfish term) · flavoured · flavored · seasoning · powder does NOT count as
    that animal for H1. Test: a risotto using "chicken stock" with no chicken
    ingredient gets no H1 injection; "chicken thighs" + "chicken stock" still
    gets exactly one injection on the last chicken cooking step.
5c. Dedupe "sausage" (listed twice in the comminuted group).
5d. The bread carve-out is NO LONGER unsigned — see Part 6. Update the comment.

==================================================================
PART 6 — H12 ruling into the repo (doc gap)
==================================================================

The H12 ruling cited in the safety-validator brief was never committed. Add to
docs/DECISIONS.md, dated 2026-08-21, source strategy chat, signed by Harris:

"H12 Fermentation. Recipe generation: substitute where a sensible non-fermented
version genuinely exists (Chef Harris's judgment, NOT a hardcoded substitution
table; vegetable ferments qualify: quick kimchi, quick sauerkraut, quick
pickle). Name the result 'Quick X' (e.g. 'Quick kimchi'), not 'kimchi-style
quick pickle'. Substitute without a lecture but carry one short note (note
wording is signed content — Harris authors). Where no honest substitute exists
(miso, tempeh, kombucha): decline with explanation, never invent a fake
equivalent. Chef SOS chat: fermentation answered as knowledge, not instruction —
informational yes, actionable no. Carve-out: sourdough and bread baking are OUT
of scope entirely; grain leavening is not a fermentation hazard. EXEMPT by
name: sourdough, starter, levain, poolish, biga, focaccia, pizza dough. IN
SCOPE: vegetable, dairy, soy, and beverage ferments. Enforcement: this rule
lands on the persona/prompt side; the deterministic layer is LOG-ONLY
verification that the prompt behaved. The 'Quick X' note and the fermentation
explanation are in the Chef Harris authoring batch."

Do NOT add the prompt line itself — that is persona-batch content. Log-only
stays log-only.

==================================================================
VERIFICATION + DOC STEP (mandatory)
==================================================================
- flutter test: all passing, report count vs 489 baseline (or the post-
  entitlement-fix baseline if higher). flutter analyze: report vs 44.
  Palette guard green.
- Real dev runs: one Fridge Clearer stage-1 pair (Part 4), one share-card
  render exported to an image file and attached/described (Part 2).
- CLAUDE.md: add the build/install rule discovered 23 Aug — `flutter install`
  alone pushes a stale APK; correct pair is `flutter build apk --release` then
  install. Also update the share-card and upgrade-sheet descriptions.
- docs/CHANGELOG.md entry. docs/sessions/2026-08-23_design-qa-polish.md with
  this prompt verbatim and your report verbatim. Commit, push.
- Report format as usual: what changed, every call site touched (by class),
  grep hit lists from 2a, ambiguities, anything you chose NOT to do and why.
  Flag scope creep in either direction.
```

### Mid-turn addendum, verbatim

```
ADDENDUM to Part 7 (apply after Part 1 finishes, before Parts 2–4 — do not
interrupt the current file). Harris has signed the two PENDING items:

- Duck whole-muscle (breast, magret, leg, thigh, whole duck, confit): EXEMPT
  from H1 injection and H2 pink-language checks. SIGNED 23 Aug: served pink is
  safe; doneness on duck is technique, not hazard. Duck mince remains in the
  comminuted group (H2). Tests: "duck breast, serve pink" → no H1, no H2;
  "duck mince" → H2 as before; "duck leg" → no injection.
  Do NOT add any duck-leg texture cue — that is sensory-vocabulary / persona
  content, logged elsewhere.
- Shrimp group → fish 63°C floor, whole or minced: shrimp, prawn, king prawn,
  tiger prawn, crevette, scampi, langoustine. SIGNED 23 Aug. Bivalves stay
  inactive; the S1 source-scan test must still pass (none of these terms are
  on it — verify, don't edit the scan list).

Part 7 is now fully signed: file header DRAFT → SIGNED, no PENDING remains in
lib/data/safety_ingredient_names.dart or docs/DECISIONS.md. Include the two
rulings in the same DECISIONS.md entry dated 2026-08-23. Continue with
Parts 2–4 as ordered.
```

*(Part 7's original text arrived with the checkpoint acknowledgement and is
reproduced in `docs/DECISIONS.md` rather than duplicated here.)*

---

## Report

### Part 2 — share card (PRIORITY)

Located by class: `PostCookShareCardSheet` → `lib/widgets/post_cook_share_card.dart`.

**Four branding violations, not two.** The device finding named the wordmark
and the logo. Reading the file turned up two more on the same surface:

| Location | What it was | Why it counts |
|---|---|---|
| `_RecapCard`, the rendered image | `'OPTIMEAL'` wordmark + `Icons.eco_rounded` leaf | On the exported PNG |
| `_share()` | `text: '$_headline 🍳 #OptiMeal'` | Travels with the image into every share target |
| `_share()` | `optimeal_recap_*.png` filename | Many share targets show the filename to the recipient |
| `_RecapCard` footer | "Zero-waste cooking, one recipe at a time." | Not a name, but app-voice tagline on a public surface — removed with the restyle |

All removed. The branding slot stays in the layout as an explicit, commented,
empty `SizedBox`.

**Restyled to spec**, tokens only, no literal hexes (palette guard green):
canvas sage `backgroundSage` (#B3C29A) with a 1.5px `goldEarnedFill` border;
reserved-but-empty photo slot above the title; dish name at 24pt; the signed
story line; gold rescue chip (`goldEarnedBadgeTint` / `goldEarnedOnLight`,
which are exactly the spec's #FBEED8 / #C77E1F) and a neutral ivory technique
chip.

**The dish name was not available to this widget** — `PostCookShareCardSheet`
only received `ingredientsRescued` and `techniqueTitles`. The spec's first
line is "Dish name (large)", so a `dishName` parameter was added and wired from
`_OnePanCookingRoadmapScreenState`'s existing `_recipeTitle`. Narrow, but it is
a signature change and is flagged as the one place this part grew.

**The "learned to sautéing" bug.** The old template was
`'…and learned to ${techniques.first.toLowerCase()}.'`, which conjugates a
noun. Technique titles are nouns ("Sautéing", "Braising"), so this could never
have read correctly. Replaced with the spec's own signed pattern,
`techniqueChipLabel()` → `"sautéing, learned properly"`. No new copy was
authored: the story line and both chip patterns are quoted from the spec, and
the share text is now assembled only from those signed fragments.

A didn't-count cook still shares — dish plus technique chip, no rescue chip,
and no story line (the fridge story would be untrue there).

**Guard test:** `test/widgets/share_card_branding_guard_test.dart`, permanent,
5 tests. Walks the render tree for `/optimeal|empyria|instinkt/i` in both the
counted and not-counted states.

#### 2a grep hit list — every branding string in `lib/`

Searched `optimeal|empyria|instinkt`, case-insensitive, excluding
`package:optimeal/` imports. **No `Empyria` or `InstinKt` hit anywhere.**

**Fixed this round (shareable/exportable surface):**
- `lib/widgets/post_cook_share_card.dart:221` — `'OPTIMEAL'` wordmark
- `lib/widgets/post_cook_share_card.dart:77` — `'#OptiMeal'` in share text
- `lib/widgets/post_cook_share_card.dart:74` — `optimeal_recap_*.png` filename

**User-visible, NOT shareable — reported, not touched:**
- `lib/screens/paywall_screen.dart:238` — "OptiMeal pays for itself in the first month…"
- `lib/screens/paywall_screen.dart:265` — "Included with OptiMeal+"
- `lib/theme.dart:8` — `AppBrand.appName = 'OptiMeal'`, used only at
  `lib/main.dart:163` as `MaterialApp.title` (the OS task-switcher label)

**Not user-visible (build config, comments, console):**
- `lib/config/app_environment.dart` — the `OPTIMEAL_ENV` dart-define name,
  its doc comments, and the startup banner (console only)
- `lib/main.dart:27`, `:170` — comments
- `lib/widgets/dev_environment_badge.dart:9` — comment
- `lib/theme.dart:149` — comment

**Separate finding, outside this round's scope:**
`android/app/src/main/AndroidManifest.xml:8` has `android:label="dreamflow"` —
the installed app is literally named "dreamflow" on the device, a leftover from
the Dreamflow export. Not a trademark violation, but it is the app's public
name on the launcher and it is wrong. Not touched: it is neither the share card
nor in `lib/`.

### Part 3 — upgrade sheet timing

**Every call site, by class:**

| Class | File:line | Verdict |
|---|---|---|
| `_OnePanCookingRoadmapScreenState` | `one_pan_cooking_roadmap_screen.dart:1014` | **VIOLATION — moved.** Fired between the share card and the verdict sheet |
| `_FridgeClearerScreenState` | `fridge_clearer_screen.dart:258` | **Left alone.** Weekly-cap gate, fires before generation, not on a cook path |
| `_CustomAiRecipeCreatorSheetState` | `custom_ai_recipe_creator_sheet.dart:113` | **Left alone.** Lifetime-cap gate, same reasoning |

The device finding said the sheet appeared "over the pre-cook surface". What
the code actually does is fire it **after the share card and before the verdict
sheet** — still squarely inside the forbidden window, and still an
interstitial over an unfinished cook, so the ruling applies unchanged.

**New `UpgradeNudgeGate`** (`lib/services/upgrade_nudge_gate.dart`) holds two
process-global facts. Cook Mode opens the gate in `initState` and closes it in
`dispose` — dispose specifically, so an abandoned cook cannot leave it shut for
the session. The post-cook sequence now only calls `schedulePostCookNudge()`.

**Home presents it, from `build`.** That looks wrong and is deliberate: this
screen already documents that the post-cook exit (`context.pop()` +
`context.go('/')` with a modal attached) produces no `didPop` and so never
reaches `didPopNext` — the same mechanism that made the rescue strip stale in
August. A write-driven signal is no good either, because `AppDataChanges.cookLog`
fires at the *top* of the post-cook sequence, which is exactly when the sheet
must not appear. So Home checks cheaply every frame and acts only once the gate
has closed; `consumePendingPostCookNudge()` is one-shot, and an unconsumed
nudge is deferred rather than swallowed.

`UpgradePromptSheet.show` also refuses outright while a cook is active. That
guard lives in the shared entry point rather than in each caller, because a
guard the caller has to remember is one the fourth caller forgets.

**3b restyle:** star glyph and its champagne chip removed, "Nice cooking!"
replaced with `// SIGNED-CONTENT PLACEHOLDER` sales copy, ivory surface and
standard chrome kept, CTA still terracotta. **The Harris warmth alternative was
not taken** — there is no evidence in the repo that he chose it, and 3b as
written is the conservative reading. It is a two-line change if he did.

**3c — could not be confirmed as specified.** The prompt says "if that build
has landed"; **it has not**. `docs/sessions/` ends at the safety-validator
entry and there is no dev-entitlement fix. Per the follow-up instruction, no
entitlement logic was touched. The nudge calls the existing
`EntitlementService.instance.isPro()`, which still returns `true`
unconditionally under `kDebugMode` — so in a debug build an "entitled" user
never sees the sheet, which happens to be the desired behaviour, by the old
mechanism rather than a new one.

**Guard test:** `test/widgets/upgrade_sheet_timing_test.dart`, 6 tests.

### Parts 5 + 7 — safety matcher and name list

**5a — the prefix bug.** `_hasAny` built `RegExp('\\b$needle')` with no closing
boundary. Converted to whole-word with regular inflection and trailing-`e`
elision (`bake`→`baking`, `leave`→`leaving`).

That elision is not cosmetic. Several needles sit in **exclusion** lists —
`chill` in `_fridgeLanguage` is the clearest — and a naive whole-word
conversion would have stopped `chill` matching "chilled"/"chilling", which
would have turned H5 and H6 from quiet rules into false-positive machines. One
list entry was a bare stem (`'refrigerat'`) that only ever worked because of
the bug; it is now `refrigerate` / `refrigerator` / `refrigeration`.

All six required cases are tested and pass.

**5b — compound exclusions.** Applied automatically to every poultry, pork and
fish entry rather than written onto 170-odd entries. `sauce` is a suffix
exclusion only, so "fish sauce" stops reading as fish. Hyphenation is handled
(`chicken-flavoured` excludes the same as `chicken flavoured`) — found by the
test, not by inspection.

**5c — there was no duplicate.** `'sausage'` appears twice in the file, but the
second occurrence is in `_donenessFamilyRoots`, a different structure added for
H1's animal grouping. `'sausage'` and `'sausage meat'` are distinct terms and
both belong. Rather than "fix" a non-defect I added a permanent test asserting
no term appears twice anywhere in the vocabulary; it passes.

**5d** — carve-out comment updated to SIGNED.

**Part 7 — ratified.** Header DRAFT → SIGNED. Veggie-product exclusion
implemented as `notPrecededBy` with a three-word lookbehind. Swiss/German
additions added strike-only.

**Addendum, both formerly-pending items now signed and implemented:**
- **Duck whole muscle is exempt from H1 and H2's pink language** — new
  `donenessExempt` flag, deliberately separate from `curedReadyToEat` (one is a
  product never cooked, the other a cut cooked and correctly served pink).
  Covers breast, magret, leg, thigh, whole duck, confit, confit de canard.
  **Duck mince is untouched and still H2.** No duck-leg texture cue was added.
- **Shrimp group at the fish 63 °C floor** — shrimp, prawn, king prawn, tiger
  prawn, crevette, scampi, langoustine. Fish-class, so H1 never touches them.
  **Verified rather than edited:** none of the seven appears on the S1
  someday-list scan (`shellfish`, `mussel`, `clam`, `oyster`, `raw flour`,
  `raw dough`, `sprout`); the scan list was not modified, and a test asserts
  mussel/clam/oyster/scallop still match nothing.

Nothing marked PENDING remains in either the file or `docs/DECISIONS.md`.

### Part 6 — H12 ruling

Committed to `docs/DECISIONS.md` verbatim, dated 2026-08-21, with a note on why
it is being recorded on 2026-08-23. The prompt line was **not** added — that is
persona-batch content and the ruling itself says the deterministic layer stays
log-only.

### Part 1 — shared illustration

`SpoonBowlIllustration` + `SpoonBowlGeometry` + `SpoonBowlPainter` in
`lib/widgets/spoon_bowl_illustration.dart`. `_SpoonAndBowlPainter` (85 lines,
onboarding) and `_StirringSpoonPainter` (136 lines, loading card) both deleted.

**Both device findings traced to specific arithmetic:**

1. **The notch.** The bowl was two quadratics meeting at `(cx, rimY+bowlDepth)`
   with control points *below* the join, so the incoming tangent pointed up and
   the outgoing tangent pointed down — a **cusp**. Replaced with a single cubic:
   no join, nothing to go wrong.
2. **The paddle crossing the rim.** `rimRy` was `0.09h` while the paddle was
   `0.13h` tall — the paddle could not fit inside the rim at *any* phase, let
   alone orbit within it. Rim deepened, paddle slightly reduced.

**The clamp needed a closed form, and the obvious one is wrong.** Insetting
each axis by the paddle radius independently — which is what I wrote first —
leaves the paddle outside the ellipse on the diagonals even though it fits on
both axes; the test caught it at four sizes. Writing the condition out gives
`(k + hypot(u, v))² ≤ 1`, so `k ≤ 1 - hypot(u, v)`. The orbit is now the rim
scaled by that, and containment holds by construction at every phase and size.

Paint order per 1b: bowl → batter → **far rim arc** → pearls → spoon → **near
rim arc** → perimeter. Gold pearl kept.

**Tests:** 11, sampling 721 phases at four canvas sizes, plus widget tests that
both surfaces instantiate the shared widget and that onboarding uses the frozen
phase.

### Part 4 — stage-1 freshness

**No memoization exists.** `_generateIdeas` calls `askChefHarris` unconditionally
every time; back (`fridge_clearer_screen.dart:467-468`) resets
`_stage = input` and `_ideas = null`. There was no short-circuit to remove, so
per the brief no test was added for one.

**Two real dev runs, identical chips** (`courgette, chicken thighs, spring
onion, feta`, 2 portions, 30 min, one pan/oven/saucepan), 2,800 prompt tokens
each:

| RUN 1 | RUN 2 (back → Let's Cook) |
|---|---|
| Chicken and Courgette Stir-Fry | Chicken and Courgette Stir-Fry |
| Baked Feta Chicken | Baked Feta Chicken Thighs |
| Mediterranean Chicken Sheet Pan | Courgette and Feta Frittata |

Exact-title overlap 1 of 3; identical-set false. **The escape path works.**

**But it is weaker than the table makes it look**: rows 1 and 2 are the same
two dishes, so only 1 of 3 is genuinely new. The cause is visible in the code —
**stage 1 passes no `recentDishTitles`**, while stage 2 does
(`fridge_clearer_screen.dart:385`). With temperature 0.25 and an identical
prompt, there is no variety pressure at all on the one call whose whole job is
to offer a choice.

**Not fixed, deliberately.** The brief scoped Part 4 to verification and said
"no UI change"; passing `recentDishTitles` is a behaviour change on a
generation path. Recommended as the next small fix — it is the same one-line
mechanism already used one stage later.

---

## Verification

- `flutter test`: **528 passing** (489 baseline + 39 new). Zero failures.
- `flutter analyze`: **44 issues** — unchanged from baseline.
- Palette guard: green (inside the suite). No literal hex entered a widget.
- Real dev runs: the stage-1 pair above, against `suuafglvrxrllnhipkiv`.
- **No dev DB work, no migration, no edge-function change, no prod contact.**

### One verification item not delivered

**The share-card PNG export did not complete.** A harness that pumped the card
and called `RenderRepaintBoundary.toImage()` hung and hit the 10-minute test
timeout, twice — `toImage()` deadlocks under headless `flutter test` on this
setup. I removed the harness rather than leave a file in the repo that hangs
the suite for ten minutes if anyone runs it.

What stands in its place: the branding guard test walks the actual render tree
and asserts the absence directly, which is the substantive claim; and the
styling is token-by-token checkable in the diff. The visual check itself is
better done on device with the `flutter build apk --release` + `flutter install`
pair now documented in CLAUDE.md. Flagged rather than quietly dropped.

---

## Ambiguities and scope notes

1. **Part 3's device finding said "over the pre-cook surface"; the code fires
   it after the share card, before the verdict.** Both are inside the forbidden
   window so the fix is the same, but the reported symptom and the actual call
   site do not match — worth knowing if there is a second path I did not find.
2. **The Harris warmth alternative for 3b was not taken** — no evidence in the
   repo that he chose it. Two lines if he did.
3. **5c's premise was wrong**: no duplicate `sausage` entry exists. Added a
   permanent duplicate guard instead of making a change.
4. **Geschnetzeltes** is filed as pork so H1 fires at all — the dish is veal as
   often as pork or chicken, and H1 covers only poultry and pork. Recorded in
   DECISIONS.md rather than resolved.
5. **Duck's H3 floor was left in place.** The ruling exempts duck from H1 and
   H2; it does not mention H3, so a duck recipe *stating* a core temperature
   below 74 °C would still flag. Conservative reading — flagging rather than
   silently widening an exemption across a rule that was not named.
6. **Scope creep, declared:** `PostCookShareCardSheet` gained a `dishName`
   parameter (the spec's first content line was unreachable without it), and
   `RecipeRetryKind`-style plumbing was *not* needed anywhere. `UpgradeNudgeGate`
   is a new file — unavoidable, since "show it on Home instead" requires
   something to carry the fact across a navigation boundary.
7. **Scope creep in the other direction:** stage 1's missing `recentDishTitles`
   is a real defect I found and did not fix, because Part 4 said verify only.
