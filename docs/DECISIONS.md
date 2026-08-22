# OptiMeal — Decisions

Binding product/architecture decisions and their reasoning. These are not
descriptions of current code — see `CLAUDE.md` for that, and
`docs/CHANGELOG.md` for how and when each decision was actually implemented.
Read on request, not auto-loaded.

---

## Cut pills resolve client-side; no schema and no prompt change (23 August 2026)

**Binding rule:** the cut diagram on an ingredient row is resolved in the app,
by `lib/services/cut_key_resolver.dart`. No prompt was changed and no field was
added, so this costs zero tokens.

**A premise correction, recorded because it changes the design.** The build
brief said `RecipeIngredient` is name/amount/unit only and has no per-ingredient
cut key. It is not: `RecipeIngredient.cut` exists, is parsed from the model's
declared `cut`, and is already validated against the closed
`ingredientCutVocabulary` by `chef_recipe_parser.dart`. So the resolver uses the
**declared value first** and falls back to text matching only when the model
declared nothing — strictly better than inferring from prose in every case,
because a declared key is the model's statement about the ingredient while a
text match is an inference from a sentence that may be about something else.

Three hard limits, each with a test: it can only ever return a key from the
signed cut vocabulary; a **technique** diagram (`pan_crowding`,
`cold_vs_hot_pan`) can never attach to an ingredient row, because a fact about a
pan is not a fact about a carrot; and the pill form returns a key only when a
diagram is actually **built**, so the 15 valid-but-undrawn keys render nothing
rather than something broken.

**Prose matching is sentence-scoped, not step-scoped.** Found on real dev
output: a step that said "thinly slice the potatoes" and "season with salt" put
a `thin_slice` pill on the SALT, and one mentioning lemon wedges put `wedges` on
the FETA. Requiring the ingredient and the cut phrase to share a sentence is
what makes the match about that ingredient. Both false positives are pinned.

---

## The servings scale is launch context, never persisted (23 August 2026)

**Binding rule:** the servings count chosen on the recipe overview travels on
`CookModeLaunchRequest.servings` and **must never be written onto
`CookModeRecipePayload`**. Same rule and same reasoning as `PlannerSlotRef`: the
payload is persisted into `saved_recipes.recipe_payload` and
`user_meal_plans.recipe_payload`, so a scale stored there would make a saved
recipe permanently remember one evening's headcount. Saved recipes keep their
`basePortions` and are rescaled fresh every time the overview opens.

The scale holder is the overview screen's own `State` — deliberately not a new
service. That single choice is what makes the signed lock/unlock behaviour fall
out for free: Cook Mode reads `servings` once on mount, and popping back
re-enables the stepper because the overview's `State` was never disposed. No
persisted schema change, no migration.

**Default precedence:** planner slot > profile household **if set** > recipe
`basePortions`. "If set" is load-bearing rather than pedantic —
`UserProfile.empty()` reports a household of 1 on a non-nullable field, so an
un-onboarded profile would silently out-rank every recipe's own base and open
everything at Serves 1. `profile.onboarded` is the honest proxy. **The planner
tier has no data source yet**: `PlannerSlotRef` carries week/day/slot and no
headcount. The parameter exists and is always null.

**Whole-piece rule:** countable units (piece, clove, slice, and a bare unit)
round UP, with a hint only when rounding changed the number. Non-count units get
one decimal, trailing `.0` dropped, `½`/`¼`/`¾` on spoons, and bulk grams and
millilitres at 100+ round to the nearest 5 — a scaled 187.5 g is a precision no
kitchen can weigh.

---

## Re-cooking a saved recipe is a real cook (23 August 2026)

**Binding rule:** launching Cook Mode from the recipe overview passes
`surface: null` and does **not** set `isReCook`.

Rescue eligibility is a property of the RECIPE (`RecipeOrigin`), not of the
screen that launched it, so a saved Fridge Clearer recipe cooked again still
counts as a rescue with no special handling. Leaving `isReCook` false is the
deliberate half: a launch flagged as a re-cook never logs, and this is a real
cook that earns its own **new** cook-log row rather than mutating the old one.

This also closes a device bug that had made the whole Saved feature a read-only
archive — recipes opened from My Recipes had no cook affordance at all.

---

## Entitlement is a property of the environment, not the build mode (23 August 2026)

**Binding rule:** `EntitlementService.isPro()` returns entitled whenever the
app's **environment** is dev — `kIsDevEnvironment`, from the `OPTIMEAL_ENV`
define. `kDebugMode` survives as an additional OR, **never as the only path**.
Release environment behaviour is unchanged.

**Why this was urgent rather than tidy.** Device testing uses a **release-mode**
APK pointed at dev — that is the build/install pair in CLAUDE.md, and it is the
only configuration Harris's phone ever runs. `isPro()` bypassed only under
`kDebugMode`, which is `false` in a release build. So that one configuration hit
the free-tier caps (3 Fridge Clearer generations a week, 2 lifetime custom
recipes) with **no unlock path at all**, because the dev paywall redirect had
already removed the mock-purchase route. Two weeks of device-only testing would
have stopped on day one.

The decision lives in a pure, parameterised
`EntitlementService.entitlementBypassFor(...)` because `kIsDevEnvironment` and
`kDebugMode` are compile-time constants that a test process cannot vary; the
four-cell matrix is asserted directly.

**One chokepoint, and a census that keeps it that way.** All three gates —
`_FridgeClearerScreenState`'s weekly cap, `_CustomAiRecipeCreatorSheetState`'s
lifetime cap, and `_HomeDashboardScreenState`'s post-cook upgrade nudge —
already funnel through `isPro()`. `test/services/entitlement_gate_test.dart`
enumerates them by file and **fails when a new `.isPro()` caller appears**, so a
future gate cannot quietly bypass the environment rule.

**Not in scope, deliberately:** a tester/account-level bypass flag. That is
deferred to the RevenueCat build.

**Usage counters still increment in dev.** The caps do not *gate* anything
there, but `UsageCapService.increment` still writes to `api_usage_daily`. Left
alone: it is harmless, it keeps the dev counter data real, and suppressing it
would mean a second environment branch in a second place.

---

## Duck is exempt from H3 as well as H1 and H2 (23 August 2026)

**Binding rule:** duck **whole muscle** — breast, magret, leg, thigh, whole
duck, confit — carries no H3 temperature floor, extending the same-day ruling
that exempted it from H1's cue injection and H2's pink-language check.
Doneness on duck is **technique, not hazard**.

Implemented by having `SafetyIngredientName.donenessExempt` suppress the
whole-muscle protein class, so an exempt name resolves to no class and H3 has
nothing to compare against. A rule that flags a correctly-cooked duck breast at
57 °C is a rule that teaches the cook to ignore temperature warnings, which
costs more than it saves.

**Duck mince is untouched and is 74 °C.** It is poultry *and* comminuted, so
the signed poultry-mince tie-break applies exactly as it does to chicken mince
— the exemption is for whole muscle, and mincing is precisely the thing that
changes the hazard, since surface becomes interior.

---

## H12 Fermentation — the ruling (21 August 2026)

Source: strategy chat, signed by Harris. **Recorded here on 2026-08-23**; it
was cited in the safety-validator brief before it had ever been committed,
which is why that build shipped its bread carve-out marked "unsigned". The
ruling and the code agree; only the record was missing.

> **H12 Fermentation.** Recipe generation: substitute where a sensible
> non-fermented version genuinely exists (Chef Harris's judgment, NOT a
> hardcoded substitution table; vegetable ferments qualify: quick kimchi,
> quick sauerkraut, quick pickle). Name the result "Quick X" (e.g. "Quick
> kimchi"), not "kimchi-style quick pickle". Substitute without a lecture but
> carry one short note (note wording is signed content — Harris authors).
> Where no honest substitute exists (miso, tempeh, kombucha): decline with
> explanation, never invent a fake equivalent. Chef SOS chat: fermentation
> answered as knowledge, not instruction — informational yes, actionable no.
> Carve-out: sourdough and bread baking are OUT of scope entirely; grain
> leavening is not a fermentation hazard. EXEMPT by name: sourdough, starter,
> levain, poolish, biga, focaccia, pizza dough. IN SCOPE: vegetable, dairy,
> soy, and beverage ferments. Enforcement: this rule lands on the
> persona/prompt side; the deterministic layer is LOG-ONLY verification that
> the prompt behaved. The "Quick X" note and the fermentation explanation are
> in the Chef Harris authoring batch.

**What this means for code, and what it deliberately does not.** The
deterministic layer stays **log-only** — that is the ruling's own words, not a
gap. The substitution behaviour, the "Quick X" naming and the short note are
persona/prompt work in the authoring batch, and **the prompt line was not
added as part of the 2026-08-23 design-QA round**. The bread carve-out in
`kFermentationBreadCarveOutDraft` is now signed and its comment says so.

---

## The poultry/pork/fish name list is ratified (23 August 2026)

**Binding rule:** `lib/data/safety_ingredient_names.dart` is **SIGNED**, not
draft, and **nothing in it is pending**. H1's detection depends on it entirely,
so this closes the largest open item from the safety validator build.

Signed with the list:

- **The cured ready-to-eat exclusion from H1.** Bacon, pancetta, guanciale,
  prosciutto, chorizo, cervelat and the rest are pork, and are excluded from
  the doneness rule anyway. This is the one exclusion that silences a rule
  rather than narrowing it, which is why it was ratified by name.
- **The poultry-mince 74 °C tie-break.** Chicken mince is poultry and
  comminuted at once; the higher signed minimum governs. No new number.
- **The bread carve-out** — see the H12 entry above.
- **The veggie-product exclusion**: `burger`, `patty`, `meatball` or `sausage`
  preceded within two words by veggie / vegetarian / vegan / plant / bean /
  lentil / chickpea / tofu / mushroom / halloumi / falafel is **not**
  comminuted meat. A bean burger has no pink to worry about.
- **The animal-compound exclusion**: an animal name immediately followed by
  stock, broth, bouillon, gravy, fat, sauce, flavoured/flavored, seasoning or
  powder is not that animal. A risotto made with chicken stock contains no
  chicken, and H1 injecting "cut into the thickest part" into it is nonsense.
  `sauce` is a **suffix exclusion only** — it neutralises "fish sauce", which
  is the point. **No shellfish term appears anywhere in the file**, which is
  also what keeps the S1 someday-list guard passing.
- **Swiss and German additions, signed strike-only** (present unless struck,
  rather than awaiting positive confirmation): Poulet, Pouletbrust,
  Pouletschenkel, Güggeli → poultry whole-muscle; Cordon bleu → pork
  whole-muscle, and it trips H10 as well since it is stuffed by definition;
  Geschnetzeltes → whole-muscle H1; Hackbraten and Fleischkäse → comminuted;
  unqualified **Schnitzel** → H1 at the poultry 74 °C floor, the higher of the
  plausible readings, because the word alone does not say which animal it is.

**The last two open lines were signed the same day**, so nothing in this file
is pending:

1. **Duck whole muscle is EXEMPT from H1, from H2's pink-language check, and
   — by the same-day extension recorded above — from H3's temperature floor** —
   breast, magret, leg, thigh, whole duck, confit. Served pink is safe, and
   doneness on duck is technique, not hazard. Implemented as
   `SafetyIngredientName.donenessExempt`, deliberately a separate flag from
   `curedReadyToEat`: one is a product never cooked at all, the other is a cut
   that is cooked and correctly served short of the poultry cue. **Duck mince
   is unaffected and remains H2** — comminuted is comminuted regardless of
   species. No duck-leg texture cue was added; that is sensory-vocabulary and
   persona content, logged elsewhere.
2. **The shrimp group sits at the fish 63 °C floor**, whole or minced: shrimp,
   prawn, king prawn, tiger prawn, crevette, scampi, langoustine. They are
   fish-class, so H1 never touches them. **Bivalves stay INACTIVE** — S1 on
   the someday list. None of the seven terms appears on that list, which the
   source-scan guard verifies rather than assumes; the scan list itself was
   not edited.

**Ambiguity recorded rather than resolved:** *Geschnetzeltes* is veal as often
as pork or chicken, and H1 covers only poultry and pork. It is filed as pork so
the rule fires at all, which also gives it the 63 °C + 3-minute-rest floor. If
the veal reading is wanted it needs its own line.

---

## Safety validator v1 is live — the deterministic layer (23 August 2026)

**Binding rule:** food safety and cooking-time compatibility are **two
validators, not one**, and the difference is not organisational. The
compatibility validator is advisory and fails open silently. The safety
validator does not: H1's enforcement is a **deterministic injection** the app
performs on the recipe itself, which never asks the model, never retries, and
has no failure path. They share the parsed payload and the ring-buffer log
shape and nothing else. Do not merge them behind a common "validator"
abstraction.

**Ordering is fixed and load-bearing.** Compatibility runs first and settles
completely; safety then judges the recipe that is actually going to be served;
the injection is applied **last of all**, after every correction round of both
layers. A compatibility retry produces a whole new recipe, so an injection
applied earlier would be discarded with the draft it was written onto, and
H1's guarantee would quietly become "usually". `test/services/
safety_generation_ordering_test.dart` pins this.

**Enforcement per rule follows the registry, not a house style.** H1 (and H10
where it rides H1's path) injects. H2, H3, H4, H5, H6, H7, H8, H9 and H11
correct-and-regenerate, capped at 2, then the recipe is served and the finding
logged — the registry's own signed *"correction-and-regenerate, never
blocking"* and *"after 2 failed corrections the recipe is served and the flag
logged"*. H12, and H10 on non-poultry meat, are **log-only**. The user is never
blocked and never shown a warning; the only visible output is H1's cue, which
reads as an ordinary sensory cue because that is what it is.

**Two rules cannot complete their signed enforcement**, because the wording
does not exist: H2's cooked-through line and H8's vulnerable-groups caution are
both marked on the registry as Harris's to author. Both are `// PLACEHOLDER` in
source and both degrade to a model-facing correction directive. **No user-facing
safety sentence was invented**, and none may be.

**The closed poultry/pork name list is DRAFT and NOT signed.** H1's detection
depends on it; the registry describes it as "drafted separately for review" and
it had never existed. `lib/data/safety_ingredient_names.dart` is that draft —
174 terms, written by Claude. Three judgement calls in it need Harris
specifically: the **cured ready-to-eat exclusion** (bacon, pancetta, prosciutto,
chorizo, cervelat are excluded from H1, which is the one exclusion that
silences a rule rather than narrowing it), **duck** (included as poultry, so a
duck breast recipe is told any pink means it goes back on), and the tie-break
that **poultry mince resolves to 74 °C rather than 71 °C** (both are signed;
the higher governs, so no new number was introduced). Signature converts the
file's status in a follow-up line — it does not need a rebuild.

**The H12 bread carve-out is UNSIGNED.** The build brief described a signed
H12 ruling with a named bread carve-out; no such ruling is in the repo, and
`sourdough`, `levain`, `poolish` and `biga` appear nowhere in `docs/`. What is
signed is Harris's handwritten prose, which has no detection or on-flag
structure. The carve-out ships because H12 is log-only and therefore cannot
reach a user, and because yeast dough is fermentation by any technical reading.
It needs a signature or a strike.

**The someday list stays out.** S1 shellfish, S2 raw flour and dough, S3
sprouts are INACTIVE. A test scans the two source files with comments stripped
and fails on any executable mention, so a half-implementation breaks the build
rather than shipping quietly.

**Rule 5 of the cooking-times paper is now implemented** — it is H1, and it is
the injection. The cross-reference the compatibility validator left open is
closed.

Full reasoning, the rule-by-rule table, the complete draft name list and the
live-generation observations: `docs/sessions/2026-08-23_safety-validator.md`.

---

## The compatibility validator is live, and what it is allowed to conclude (23 August 2026)

**Binding rule:** the app, not the model, owns cooking times. The model is
given a closed list of **74 keys** and declares a `cooking_times_key` per cooked
ingredient; the app resolves that key to a band from
`lib/data/cooking_times.dart` and does the arithmetic itself. **A time or a band
stated by the model is never authoritative and is never read.** This is option C
as signed on 21 August, with the key-list size question answered: all 74 rows,
not a coarser vocabulary.

`lib/data/cooking_times.dart` is **derived from `docs/cooking_times_table.md`**
and a parity test re-parses the committed doc on every run. The doc is the
source of truth in fact, not by convention: changing a band in Dart alone fails
the build.

**Size scaling is by time multiplier, never by band shift.** ×0.4 / ×1 / ×2.5 /
×5 against the row's reference cut, then the four shape adjustments, then the
band is whatever the scaled time falls into. This was already the paper's word
against the earlier session prompt's; it is now also the code's.

**Tolerance is one band, and a violation never reaches the user as a warning.**
Up to two correction regenerations, then silent fail-open: the recipe is served,
the flag is logged, nothing is shown and nothing is blocked. The correction note
goes on the variable half of the prompt, never the cached prefix.

**Red lentils remains the one pending exception.** The key is declarable so the
model can name the row, but it resolves to no band and every timing check skips
it. The printed 18 min / B5 must not be used. Closing it is a one-number edit to
the doc; the parity test then forces the Dart to match.

**Two readings that go beyond the literal paper, adopted on measured evidence
and open to reversal:**

1. A step at `heat: off_heat` is never checked. Chopping and assembling are not
   co-cooking, and real output lists four ingredients against a prep step
   routinely.
2. Rule 4 compares a band against the **cumulative heated minutes from the step
   that adds the ingredient to the end of the recipe**, not one step's stated
   duration. An ingredient added early keeps cooking; stewing beef browned for
   10 minutes and then simmered for 90 has 100 minutes, not 10.

Together these took the observed flag rate on real dev output from 4-in-7 to
1-in-7, so they carry most of the feature's running cost. Reasoning and the raw
observations: `docs/sessions/2026-08-23_compat-validator.md`.

**Rule 5 of the paper — poultry and pork verification — is deliberately NOT in
this validator.** It is food safety, which is roadmap item 1, with its own
signed registry and its own decisions about blocking versus correcting. Timing
and safety are not merged.

---

## The cooking-times table and the safety hazard registry are VERIFIED (22 August 2026)

**Binding rule:** `docs/cooking_times_table.md` and
`docs/safety_hazard_registry.md` are the transcriptions of record, and the
scans in `docs/scans/` are the authority behind them. Where a transcription and
a scan disagree, the scan wins and the transcription is the bug.

Both were signed on paper by Chef Harris — cooking times **17.08.2026**,
registry **21.08.26** — transcribed on 2026-08-22, and the six transcription
flags were then answered by him against the paper. His answers are recorded
verbatim in `docs/sessions/2026-08-22_transcription.md`.

**Registry: fully verified. This unblocks the safety validator's deterministic
layer.**

The two questions that mattered were the same shape: H3's four temperatures and
H6's 2-hour limit were each printed as drafts *needing* correction, each had a
**ticked** checklist item claiming correction, and each had an **empty**
correction box. Harris's answers — *"all 4 stand"* and *"2 hours stand"* —
settle both, and settle the reading of the whole sheet: a ticked KEEP with an
empty box means "reviewed, correct as drafted", and the checklist tick meant "I
did the checking", not "I rewrote something".

**The signed minimums** (H3): poultry **74 °C**; minced meat and sausage
**71 °C**; pork whole-muscle **63 °C plus a 3-minute rest**; fish **63 °C**.
The pork entry has two parts — 63 °C *without* the rest is not the signed
condition. **The danger-zone limit** (H6): **2 hours**.

Eleven active rules, all KEEP, none struck. The someday list (shellfish, raw
flour and dough, raw sprouts) stays **INACTIVE** and out of validator v1.

**Cooking times: verified with exactly one row still open. This unblocks the
compatibility validator, with a named exception.**

Harris confirmed: "16–20 min." is **Risotto rice**'s own correction, not White
rice's; the stray tick belongs to **Fresh pasta**; the three non-numeric
annotations mean *"package instructions but always try as well"*, so on
`dried_pasta`, `white_rice_absorption` and `brown_rice_absorption` the printed
**minutes are advisory and the printed band still stands** (a B6 brown rice
still needs its own head start — it is the minutes that carry no authority).

**The open row is red lentils.** Harris confirmed the annotation reads "even
faster" but gave no replacement figure, so the printed 18 min / B5 is known to
be wrong and nothing has been substituted for it. **No number was invented.**
The validator must either carry a figure once one exists, or skip the timing
check for that row. This is the only pending value in either document.

**Two things the paper says that the validator design did not expect**, both
resolved in favour of the paper: size scaling is expressed as **time
multipliers** (× 0.4 / × 1 / × 2.5 / × 5) rather than band shifts, and the two
are not equivalent (× 0.4 on a 12 min B4 gives 4.8 min, a two-band drop); and
the sheet carries **74 ingredient rows** where the design anticipated "~26
declared keys", so the closed key list is either 74 long or a coarser
vocabulary these rows resolve into. That choice is still open.

---

## Fridge Clearer generation is two-stage; regenerate is removed (22 August 2026)

**Binding rule:** pressing "Let's cook" makes ONE small call that returns three
**idea summaries** — title, total time, which ingredients each would clear. No
full recipe is generated until the user picks one. Stage 2 generates the full
recipe for that idea alone.

**The regenerate affordance ("Try Another") is removed from this flow.**
Choosing among three replaces retrying one. If all three disappoint, back
returns to the input screen with every selection intact and re-runs stage 1.

**Measured on live dev, 2026-08-22** (one real `ask-chef-harris` call):

| | prompt tokens | completion | ≈ cost (gpt-4o) |
|---|---|---|---|
| stage 1 (menu of three) | **2,857** | **155** | ~$0.0087 |
| stage 2 (full recipe) | ~6,950 | ~900 | ~$0.026 |

So the split costs ~30% more when the user commits, and ~65% **less** when
they browse and back out. The comparison that actually matters is against what
it replaces: the old flow's "Try Another" cost a full recipe generation every
time, so two retries ran ~$0.079 for three dishes seen one at a time, against
~$0.035 for three seen at once and one cooked. The user also waits 7–10s
**after** committing rather than before, which is the perceived-speed argument
independent of cost.

**Clearance arithmetic is computed app-side, never read from model prose.**
The model is asked which of the user's ingredients a dish uses; the app
partitions the user's own entered list against that answer
(`FridgeClearance.forIdea`). The loop iterates the ENTERED list, so an
ingredient the model invented cannot inflate the count. `ingredients_left` is
requested in the schema and deliberately not read — asking for it makes the
model commit to a full partition, which improves how honestly it fills
`ingredients_cleared`; the app's own subtraction is what reaches the screen.
A number a user can check against their own counter is the whole feature.

**A malformed stage-1 reply fabricates nothing.** `parseFridgeIdeasJson`
returns null and the screen shows its error card with a retry. This is the
opposite of what this screen did when full-recipe parsing failed (roadmap item
20: a hardcoded fallback recipe), and deliberately so — a made-up menu is worse
than a visible failure, because a fabricated idea then anchors a real stage-2
generation.

**No edge-function change was required.** Both stages go through
`ask-chef-harris` unchanged: prompt assembly is client-side, and the function
stores whatever `surface` string arrives without validating it against a list.
The two stages log as `fridge_ideas` and `fridge_clearer`, so browsing cost and
committing cost are separable in `api_call_cost_log`.

**The free-tier cap counts stage 1 only.** The cap bounds cost per user
*intent*, and browsing three ideas then cooking one is a single intent.
Charging twice would penalise exactly the behaviour the split encourages.

## Kit rules adopted app-wide (22 August 2026)

Two rules from the Fridge Clearer card, binding on every screen:

**1. Controls wrap, never clip.** No horizontal-scrolling or edge-clipped
selectors anywhere. The failure this exists to prevent is real and shipped:
the Fridge Clearer's time and portion pickers rendered "45+ M…" and "4 …" at
common phone widths, and the Techniques category bar hid whole categories past
the fold with no cue they existed. Anything that does not fit moves to the next
line where it can still be read.

**2. Selection state is a champagne fill.** Selected chips and segments use
champagne (`#F7DBCB`) with terracotta-on-light text (`#A44E2B`, weight 500);
unselected use the quiet row surface with a hairline border. **Never
border-only, never icon-only** — both read as "nothing is selected" at a
glance in a kitchen. This also frees terracotta: a screen's selected chips no
longer compete visually with its one real CTA.

Enforced by convention rather than a test today; `grep -rn "scrollDirection:
Axis.horizontal" lib/` returning nothing is the cheap check for rule 1.

---

## Palette v1.2 (variant D) is the sole token set, enforced by a guard test (22 August 2026)

**Binding rule:** `lib/theme/app_design_tokens.dart` is the **only** file in
`lib/` allowed to define a colour. Every widget references a named semantic
token; `LightModeColors` / `DarkModeColors` in `lib/theme.dart` are Material-3
*role bindings* over those tokens and define nothing of their own.
`test/theme/palette_token_guard_test.dart` walks `lib/`, strips comments, and
fails the build if a `0x…` colour literal appears anywhere else — plus it pins
the twelve signed v1.2 hex values, so the palette cannot be edited back by
accident either.

**Why a test and not a convention.** The codebase reached 2026-08-22 with *two*
disagreeing palettes. `AppDesignTokens` and `LightModeColors` had drifted apart
one hardcoded value at a time — the same semantic held `#D94A1E` in one place
and `#D96B43` in another, deep forest was `#1E3A2B` here and `#284236` there —
and nothing ever failed while it happened. A third mini-set had appeared as
statics on `ProfileScreen`. Colour drift is invisible to the compiler and to
every existing test; a source scan is the only thing that catches it, and a
grep is only as good as the last person who remembered to run it.

**The three semantic families, and what they cost when spent wrongly.**

- **Terracotta = act now.** Split into a fill (`ctaTerracotta`) and a darker
  text/glyph weight (`terracottaOnLight`), because the fill fails small-text
  contrast on ivory.
- **Sage = Chef Harris teaching.** `sageTeachingPanel` on cards, and only on
  panels. Sage on the canvas (`backgroundSage`, `sageStripOnCanvas`) is
  decorative and carries no teaching meaning. The two sage-on-light tokens are
  kept **separate despite sharing a value**, so the open device question — does
  the strip separate from the deepened canvas — can be answered by moving one
  without dragging teaching panels with it.
- **Gold = earned.** Counted-verdict badges, rescue milestones, tier-ups, the
  share accent. Never on CTAs, teaching panels, or large container fills:
  glyphs, badges, thin borders and small text only. Same fill-vs-text split as
  terracotta (`goldEarnedFill` / `goldEarnedOnLight`).

**The Home rescue strip stays sage, deliberately.** It reports a running total,
which is not an earned moment. This is the clearest test of the gold rule: it
is the most obviously "reward-shaped" surface in the app and it still does not
get gold.

**Non-palette colours are quarantined, not renamed.** Material error roles and
the (unreachable) dark scheme live in a marked section of the tokens file so
that file stays the single place a colour is defined, without pretending they
have brand semantics. v1.2 is a light-only palette and says nothing about dark
mode; inventing dark equivalents would have been guessing.

---

## Planner weeks are anchored to a Monday, computed at read time (22 August 2026)

**Binding rule:** every `user_meal_plans` row stores `week_start` — the
**Monday of its week** — and `day_index` is 0–6 within that week. The two
weeks the planner can show are **computed from the clock every time they are
read**: "this week" is the Monday of today, "next week" is that Monday plus
seven. Neither is stored, cached, or advanced.

**Boundary: Monday, device-local time. Deliberately NOT pinned to
Europe/Zurich** (Harris's ruling, 22 August 2026). A travelling user's "this
week" should follow the phone in their pocket; a fixed zone would roll their
planner over at the wrong hour and, worse, would disagree with the date the
phone itself is showing them. Switzerland is the default in practice because
the device is in Switzerland — same answer, no special case. The one place
Zurich *is* named explicitly is migration `20260822120000`'s backfill, which
has no device to ask and had to pick something; picking UTC there would have
rolled a plan forward a week if the migration ran on a Sunday evening.

**Why read-time rather than stored.** The alternative — a stored "current
week" that something advances — needs a thing that does the advancing: a
background job, a launch-time check, or a migration every Monday. All three
can fail to run, and all three have a wrong-answer state (the app open across
midnight on Sunday, a phone that was off all week). Deriving it from the clock
has no such state: at 00:00 on Monday the same code starts returning a
different Monday, last week's rows stop being fetched, and what was "next
week" is now "this week". Rollover is a property of asking, not of stored
data.

**Past weeks are unreachable, not deleted.** There is no way to navigate
backwards — history lives in My recipes and the Waste Ledger, which is where
users actually look for it. But the rows stay: the read is scoped to the two
weeks the screen can show, so a past week is simply never asked for. That
keeps the migration non-destructive and leaves a past-weeks feature possible
later without recovering anything.

**What this supersedes.** The 22 August redesign encoded next week as
`day_index + 7` (0–6 this week, 7–13 next), because the table had no week
column. That was storable — verified against live dev — but nothing anchored
either week to a date, so neither ever rolled over: "next week" stayed next
week forever, and last week's meals sat there labelled as this week's. That
was already true of the single-week model before the toggle existed; the
toggle only made it visible. 0–13 survives **only as a view offset inside
`weekly_planner_screen.dart`** (day cards, inline-error keys, the in-flight
write set) and is no longer a storage encoding.

**Consequence for slot identity.** `(user_id, day_index, slot_index)` stopped
being unique the moment weeks were anchored, so the unique constraint — and
therefore PostgREST's `on_conflict` target — became
`(user_id, week_start, day_index, slot_index)`. Verified against live dev:
the old three-column target now returns `42P10` ("no unique or exclusion
constraint matching the ON CONFLICT specification"), which would have broken
every planner overwrite had the app not been changed in the same step. This is
the second instance of the same lesson recorded on 22 August: having a
constraint is not the same as PostgREST using it.

`PlannerSlotRef` carries the week for the same reason — a cook launched at
23:55 on Sunday and finished at 00:05 on Monday must mark the row it was
planned in, not the same weekday of the week that just began.

---

## Cooking times reach the model as a declared key, not a table — option C (21 August 2026)

**Binding rule:** the cooking-times vocabulary is **never sent to the model as
a table**. The prompt carries only a short closed key list (~500 chars); the
model declares one `cooking_times_key` per recipe or step; the app resolves
the actual minutes locally from the signed table. Fifth instance of the
closed-vocabulary pattern, after cut vocabulary, `curriculum_lesson_id`,
`sensory_cue`, and `technique_diagram_id` — all four of which already work.

**What this supersedes.** CLAUDE.md roadmap item 15 carried a costing for a
"~3,400-char cooking-times block", cached vs uncached. Two problems with
using that number to decide:

1. **The table does not exist.** As of 21 August 2026 there is no
   cooking-times data anywhere in `lib/` or `docs/` — only the *shape*
   decision (`docs/decisions_2026-08-17.md` item 2: size scaling as band
   shifts, one-band compatibility tolerance, whole-muscle vs minced as a
   real split). 3,400 chars was an estimate of unwritten content, and the
   real table could land at any size.
2. **Option C makes its size irrelevant to prompt cost.** Only the key list
   is recurring prompt tokens. The table itself becomes app data, priced
   once at authoring time rather than on every call forever.

**The numbers this was decided from** (21 August 2026 session, verified
against OpenAI's published gpt-4o rates: input \$2.50/1M, cached input
\$1.25/1M, output \$10.00/1M):

| placement | tokens/call | warm | cold |
|---|---|---|---|
| ~3,400-char table inside the cached prefix | ~850 | \$0.00106 | \$0.00213 |
| ~3,400-char table outside it | ~850 | \$0.00213 | \$0.00213 |
| **~500-char key list inside the prefix (option C)** | **~125** | **\$0.00016** | **\$0.00031** |

At a conservative 300 calls/month the full table costs \$0.32–\$0.64/month
depending on placement; the key list costs \$0.05–\$0.09. The absolute
amounts are small either way — **cost is not why this was decided.** The
reasons are that the key list keeps the resolved minutes deterministic and
editable without touching a prompt, keeps the table auditable as signed
content rather than as model input, and stops the table's eventual size from
being a prompt-architecture constraint at all.

**Consequence for the safety validator (roadmap item 1):** the validator
reads the resolved local table, not model-echoed times, which is the stronger
position anyway — a model cannot mis-transcribe a number it never received.

**Still to author:** the table content itself, and the closed key list
derived from it. Both are Harris's, and the key list must be closed and
stable before it enters a prompt, since it becomes part of the cached prefix.

---

## Rescue provenance travels with the recipe (20 August 2026)

**Binding rule:** whether a completed cook counts toward the Waste Ledger is
a property of the **recipe**, not of the screen the cook was launched from.

The rule this replaces keyed eligibility on `CookModeSurface` — which screen
pushed Cook Mode. That made a real behavioural bug inevitable: a Fridge
Clearer recipe scheduled into the Weekly Planner and cooked from there
launched with `CookModeSurface.weeklyPlanner`, which was not rescue-eligible,
so a genuine fridge rescue silently did not count. The food was rescued; the
app was looking at the wrong thing.

Provenance is now `RecipeOrigin`, stamped onto the recipe payload once at
generation time and carried through every hop the recipe takes — the local
active-session and cook-history stores, `user_meal_plans.recipe_payload`
jsonb, and `saved_recipes`. `CookModeSurface` survives as launch context and
decides nothing.

Two consequences worth stating explicitly, because they are easy to get
wrong later:

1. **The entered fridge list has to travel too.** `FridgeClearerEntryService`
   only ever holds the *most recent* generation's entered ingredients and is
   cleared on completion. By the time a planner-scheduled fridge recipe is
   cooked, that store has moved on. Counting the cook as a rescue while
   crediting zero ingredients would be worse than not counting it, so
   `originEnteredIngredients` rides along on the payload.
2. **Unknown provenance is not rescue-eligible.** Recipes persisted before
   this rule existed decode with a null origin. That must degrade to "does
   not count", never be guessed from title, surface, or ingredients.

Re-cooks are unchanged: a re-cook never counts, whatever the origin, because
the rescue was already credited the first time.

---

## saved_recipes follows user_meal_plans, not recipes (20 August 2026)

**Binding rule:** a saved recipe stores the **full recipe payload inline as
jsonb**, not a foreign key into `public.recipes`.

Checked against the live dev schema rather than the docs before deciding:
`public.recipes` really is a content-less placeholder (`id`, `user_id`,
`created_at` — `title`, `ingredients`, `steps`, `description` do not exist),
and nothing in the app has ever written to it on either project.
`user_meal_plans` is the pattern that actually carries recipes today, via a
`recipe_payload` jsonb column.

Generated recipes have no server-side row and no server id at all — they
exist only as a `CookModeRecipePayload`. Saving therefore cannot depend on a
`recipes` row existing, and identity cannot be a uuid. Identity is
`recipe_key`: the title, trimmed, lowercased, whitespace-collapsed — the same
notion of "the same recipe" the local cook-history store has always
deduplicated on. Uniqueness is `(user_id, recipe_key)`; re-saving updates in
place.

Three things are deliberately **not** in that table:

- **No times-cooked column.** How often something was cooked is
  ledger/cook-session data and is derived at read time. A counter here would
  be a second source of truth that silently drifts from the first.
- **No row limit and no pricing/tier columns.** Pricing is a deferred
  decision; encoding tiers into the schema now would prejudge it.
- **No `set_updated_at` trigger.** `last_touched_at` means "when the user
  last did something with this recipe", which only the client knows. A
  trigger would bump it on any write at all — including a future backfill —
  and scramble the recency sort it exists to drive.

`origin` is duplicated as its own column alongside the copy inside
`recipe_payload`, on purpose: the leaf badge and any future "show me my
fridge rescues" filter should be an indexed column read, not a jsonb
traversal. The service writes both from the same payload so they cannot
diverge.

---

## Pricing — NOT DECIDED (17 August 2026)

Source: `docs/decisions_2026-08-17.md`, item 9.

- Harris has **not** committed to CHF 6.99/month, CHF 69.99/year, or any
  other figure.
- Pricing is **deliberately deferred** until the app is functioning and
  proven good.
- The **15 CHF/month currently in the paywall is a placeholder in code, not
  a decision.**

**This directly contradicts the framing of the "Monetization / paywall tier
structure" section below**, which was decided 2026-08-10 and reads as a
settled price. That section has been moved here unedited, at Harris's
explicit instruction, pending his decision on how to reconcile the two — see
the 2026-08-17 restructure report (chat) for the exact lines flagged.

---

## Product cuts (17 August 2026)

Source: `docs/decisions_2026-08-17.md`, item 3. Mechanical removal record
(what was cut from the roadmap, and when) lives in `docs/CHANGELOG.md` under
"Cut — 2026-08-17."

| Item | Decision | Reasoning on record |
|---|---|---|
| Shopping list | Cut. Currently live in Weekly Planner, needs removal from the app. | Not stated in the source decision record beyond "needs removal" — no product reasoning was captured. Flag to Harris if the reasoning matters later. |
| Video / media content | Cut. | Superseded by drawn SVG diagrams — see "Visual assets" below. |
| Fridge tab | Cut. | Replaced by a single local notification — see "Fridge tab replacement" below. |
| Pasteurisation equivalence table | Dropped. | The interim flag-only rule becomes the permanent rule — see "Pasteurisation rule" below. |
| Cut reference photo library | Cut, as a photo shoot specifically. | Superseded by drawn SVG diagrams — see "Visual assets" below. |

---

## Visual assets — drawn diagrams, not photographs (17 August 2026)

Source: `docs/decisions_2026-08-17.md`, item 4.

- Cut reference visuals will be **deterministic SVG diagrams**. Not
  AI-generated images, and not a real photo shoot.
- This removed the photo library from the vacation deliverables list.
- The media section shell (previously the browsable Techniques & Media hub,
  see the superseded 2026-08-10 curriculum content strategy decision in
  `docs/CHANGELOG.md`) is **repurposed as a drawn-diagram learning library**,
  containing:
  - the 16 cut diagrams (one per cut vocabulary value)
  - a closed set of technique diagrams: pan crowding, cold vs hot pan, oil
    depth, tray spacing, staggered adds
- **In-context placement inside recipes is the higher-value surface.** The
  browse library is secondary and gets built second.
- Technique diagrams get a closed `technique_diagram_id` key list that the
  model declares from — same pattern as cut vocabulary and curriculum
  drawer keys. Third and fourth instance of a pattern that has now worked
  repeatedly in this codebase.

Build task tracked as an open roadmap item in `CLAUDE.md`.

---

## Fridge tab replacement (17 August 2026)

Source: `docs/decisions_2026-08-17.md`, item 5.

The tab is gone. In its place:

- A single local scheduled notification, fired 2 days after unused Fridge
  Clearer ingredients.
- One nudge only. Never repeated.
- Two CTAs on the notification: Fridge Clearer and the AI generator.

This dissolves the Fridge Countdown cold-start dead end (documented in
`docs/CHANGELOG.md` under Retention Features Backlog item 1) rather than
solving it by adding a persistent Home entry point, which was the direction
implied — but never committed to — before this decision.

Build task tracked as an open roadmap item in `CLAUDE.md`.

---

## Pasteurisation rule — permanent (17 August 2026)

Source: `docs/decisions_2026-08-17.md`, item 8.

The interim rule becomes the **permanent** rule, replacing the idea of
building a full pasteurisation equivalence table:

> Flag a temperature below the instantaneous minimum with no hold time
> stated.

This removed the pasteurisation table from the vacation deliverables list.
Relevant to the safety validator roadmap item in `CLAUDE.md` — this is one
concrete, already-decided rule for that validator's hazard list.

---

## Waste Ledger legibility — option B (17 August 2026)

Source: `docs/decisions_2026-08-17.md`, item 6.

- Every completed cook gets a verdict explaining why it did or did not
  count.
- Plus a permanent explainer on the Waste Ledger screen itself.

Rationale on record: Harris wrote the spec and still experienced correct
behaviour as inconsistent, because nothing in the UI explained the rules. A
tester never would. Build task tracked as an open roadmap item in
`CLAUDE.md`.

---

## Confidence question wording — FINAL (17 August 2026)

Source: `docs/decisions_2026-08-17.md`, item 7. Not a proposal — this exact
wording is decided.

> **"Are you comfortable with this technique?"**
>
> - Yes, it's automatic now
> - Not yet, still takes concentration

This resolves the open "What You Learned repeats the same technique
forever" problem. Build task tracked as an open roadmap item in
`CLAUDE.md`.

---

## Sunday Reset — on hold, not cancelled

Originally gated on "recipe generation speed confirmed fixed." That
investigation concluded: the honest floor is ~7-10s per generation,
`max_tokens` capping and the `gpt-4o-mini` trial didn't move it further, and
the only real remaining lever (streaming) is a genuine future project, not a
quick fix (see the "Recipe generation streaming" item in `CLAUDE.md`'s open
roadmap). Perceived-speed work shipped (a rotating status card during
generation), but actual generation time is not going lower without the
streaming project. Harris has **not** decided whether ~7-10s × 5 batched
calls (a real 35-50s wait) is acceptable for Sunday Reset — **do not start
this until he explicitly says so**, even though the original blocking
condition ("speed confirmed fixed") is technically now answered, just not
answered favorably.

---

## Ask Chef Harris Mid-Cook — on hold, not cancelled

Same reasoning as Sunday Reset above: originally gated on confirmed-fast,
ideally-streaming generation. The ~7-10s floor is now the confirmed,
understood reality (not an open question anymore), but Harris hasn't
decided whether that's acceptable for a feature that "needs to feel
instant since it's used mid-task." **Do not start until he explicitly says
so.**

---

## Techniques & Media hub — content strategy (decided 2026-08-10, still binding)

Two decisions from the original 2026-08-10 "Curriculum content strategy"
record survive the 2026-08-17 SVG-diagram decision unchanged — neither was
ever about video or photography, so neither is superseded by it. (The rest
of that original decision — real still photos, the `externalVideoUrl`
field, and the requirement that `TechniqueLesson`/`TechniquesMediaScreen`
gracefully handle photos/a video link being present or absent — was
specifically about video/photography and **is** superseded; full original
text is preserved, marked superseded, in `docs/CHANGELOG.md`.)

- **Primary emphasis stays on text + timing inside Cook Mode itself, not
  the browsable hub.** That's the actual differentiator — "we tell you
  why, in the moment, with a timer." The Techniques & Media hub
  (`CurriculumLibrary`/`TechniquesMediaScreen`) is a supplementary browsing
  surface, not where the app's teaching value lives. Consistent with, and
  reinforced by, the 2026-08-17 SVG diagram decision's own ordering
  ("in-context placement inside recipes is the higher-value surface, the
  browse library is secondary and gets built second" — see "Visual assets"
  above).
- **No vector/animated diagrams for now.** That needs a freelance motion
  designer — out of scope for this phase, revisit only if/when that's
  commissioned. Distinct from the 2026-08-17 decision to build **static,
  deterministic** SVG diagrams — that decision does not reopen this one;
  animated/motion-designer-dependent diagrams remain out of scope.

---

## Monetization / paywall tier structure (decided 2026-08-10)

**Moved verbatim from CLAUDE.md below this line, completely unedited, per
explicit instruction pending Harris's review — see the "Pricing — NOT
DECIDED" entry above for the 2026-08-17 update this section has not yet
been reconciled with. Everything from the next heading to the end of this
section is copied character-for-character from the original CLAUDE.md; no
wording, structure, or claim has been changed.**

## Monetization / paywall tier structure (decided 2026-08-10 — built against mock/sandbox state)

This is the source of truth for what's free vs. paid. Decided in conversation
with Harris on 2026-08-10, then built the same session — see "Build status"
at the end of this section for exactly what's done vs. still TODO.

**Deliberately deferred**: real Apple Developer / Play Console / RevenueCat
account setup. Harris hasn't cleared the Empyria-vs-OptiMeal trademark
question yet and isn't distributing to real testers yet, so none of that is
worth doing now. Instead, the whole gating/entitlement stack is built and
fully testable against a **local mock entitlement flag** (see
`entitlement_service.dart`) — real accounts get created, and real RevenueCat
keys handed over, only once Harris is actually approaching real-tester
distribution. Do not create real store/RevenueCat accounts unprompted.

**Provider: RevenueCat (confirmed, not Stripe-direct).** Reasoning: Apple/
Google require native IAP (StoreKit/Play Billing) for digital subscriptions
sold inside a native app — App Store Review Guideline 3.1.1 blocks charging
via Stripe directly for that. RevenueCat wraps both platforms' native IAP
behind one API, handles receipt validation/entitlements, free until $2.5k/mo
tracked revenue then 1% — effectively free at current pre-revenue stage.
Apple/Google's own platform cut (15-30%) applies regardless of RevenueCat.

**Tier structure:**

- **Free forever, never gated**: Waste Ledger (including all stats/streaks),
  Cook Mode, basic recipe browsing. This is the core "don't waste food"
  mission and the word-of-mouth engine — explicitly must never be gated,
  including Waste Ledger stats/streaks (gating proof-of-your-own-usage was
  considered and rejected as contradicting the app's premise).
- **Free but usage-capped**: Chef Harris AI chat (5 messages/day, applies
  ONLY to `_ChefSuggestionSheet` in `home_dashboard_screen.dart` — the Home
  "Chef Harris Suggestion" generator), Fridge Clearer AI generation (3 per
  week). Both built and wired. Protects real marginal cost (OpenAI calls) —
  the only tier boundary justified on cost grounds, not value withholding.
  **Explicitly does NOT apply to `_ChefSosSheet`** (Cook Mode's SOS chat,
  same file) — confirmed by Harris 2026-08-10: SOS stays free-forever as
  part of Cook Mode, since asking for help mid-recipe is exactly the moment
  the app needs to be reliable, not the moment to show a paywall.
- **Pro-only**: `CustomAiRecipeCreatorSheet` (Custom AI Recipe Creator), and
  skill-based Smart Suggestions once [[Confidence Climb]] (Retention
  Features Backlog item 2) exists. Both require cook-history data to feel
  valuable, so gating them doesn't feel arbitrary.
- **One exception to the Pro gate**: Custom AI Recipe Creator is usable free
  for the first 2 generations ever (lifetime, not per-week), then converts
  to Pro-only. Gives a real taste of the highest-value feature without
  touching the core free experience or needing a whole-app trial countdown.

**Upgrade prompts — exactly three moments, no others:**
1. Post-cook, after the existing `WasteLedgerCelebrationSheet` →
   `WhatYouLearnedSheet` sequence closes (`one_pan_cooking_roadmap_screen.dart`)
   — a lightweight card (`UpgradePromptSheet`, built), not inserted into
   either existing sheet (keeps Waste Ledger itself untouched per the
   free-forever rule above). People upgrade when they feel successful, not
   when they feel blocked. **Built, not yet live-tested.**
2. The moment someone hits their weekly Fridge Clearer cap. **Built, not
   yet live-tested.**
3. A locked preview of Smart Suggestions, once Confidence Climb exists.
   **Not buildable yet** — Confidence Climb doesn't exist.

**Enforcement mechanism**: `api_usage_daily` Supabase table — migration
written (`supabase/migrations/20260810120000_create_api_usage_daily.sql`),
schema `user_id, feature, usage_date, count` + an `increment_api_usage(p_feature)`
RPC function for race-free increments. **Applied to the live Supabase
project 2026-08-10** via `supabase link --project-ref xwugnhzlnfgmczkbbcbh`
+ `supabase db push` (see "What this is" section at top of this doc for how
that CLI path was discovered/confirmed working). Read/write via
`lib/services/usage_cap_service.dart` (`UsageCapService`), shared by both
AI-cost rate-limiting and paywall-gating checks — one mechanism, not two
competing systems. Fails open (allows the action, logs a debug line) if a
usage check errors, so a transient DB issue never locks someone out of a
feature they're entitled to.

**Current placeholder pricing** (in `paywall_screen.dart`, explicitly marked
`// NOTE: placeholder variables (intentionally easy to A/B later)`): pricing
is deliberately deferred until the app is functioning and proven good. The
15 CHF/month figure and the ~135 CHF/year annual figure (25% off) currently
in code are placeholders, not decisions — no price has been committed to.

**Bundle ID / package name — deliberately still a placeholder.** Both
`ios/Runner.xcodeproj` and Android `namespace`/`applicationId`
(`android/app/build.gradle`) were changed this session from the Flutter
default `com.mycompany.CounterApp` to `com.optimeal.dev.placeholder` (also
updated `MainActivity.kt`'s package declaration to match). This is
explicitly NOT a final decision — Harris is still deciding between OptiMeal
and Empyria branding (trademark check pending on the latter) — and is safe
to keep changing right up until the first real Play Store publish (Android's
`applicationId` can't change after that point; iOS is more forgiving).
Whoever picks up store account setup later must pick the real final value
first and update both project files before creating App Store Connect /
Play Console app records.

**Build status (this session, 2026-08-10)**: tier structure, provider
choice, and the full gating stack are built end-to-end against **mock/
sandbox entitlement state**, real store accounts intentionally deferred.
Done: bundle ID off the Flutter default (see above); `purchases_flutter`
added; `EntitlementService` (`lib/services/entitlement_service.dart`) — real
RevenueCat calls behind empty placeholder API key constants
(`kRevenueCatIosApiKey`/`kRevenueCatAndroidApiKey`), falls back to a local
mock flag (`SharedPreferences` key `isSubscribed`, same one `PaywallScreen`'s
placeholder purchase button already flips) whenever real keys are empty —
this is intentional, not a bug, until real keys exist; `api_usage_daily`
migration written and applied to the live project (see above); `UsageCapService` built;
Fridge Clearer's weekly cap wired with upgrade prompt
(`fridge_clearer_screen.dart`); Custom AI Recipe Creator's 2-free-lifetime-
then-Pro gate wired (`custom_ai_recipe_creator_sheet.dart`); post-cook
upgrade nudge wired (`one_pan_cooking_roadmap_screen.dart`); Chef Harris
chat cap wired to `_ChefSuggestionSheet` only, per Harris's explicit
decision above (`home_dashboard_screen.dart`). **None of this has been
live-tested in a running app yet** — verify next session, same as any
"implemented but never clicked through" item elsewhere in this doc.

Still needed, in order: (1) live-test all four gates (Fridge Clearer cap,
Custom AI Recipe Creator gate, post-cook nudge, Chef Harris chat cap) in a
running app now that the `api_usage_daily` migration is actually applied
(previously untestable — every check 403'd and fell back to fail-open, so
the gates themselves were never really exercised), (2) once Harris is
actually approaching real testers: final bundle ID/package name decision,
then Harris creates Apple Developer + Play Console + RevenueCat accounts
and hands over the real RevenueCat public SDK API keys (iOS + Android) +
entitlement identifier — see Roadmap item 6.

**Live-tested 2026-08-10 (Chrome DevTools, real cook session):** confirmed
`api_usage_daily?select=count...` and the `increment_api_usage` RPC both
403'd against the live Supabase project at that point in the session —
expected, the migration hadn't been applied yet. Also confirmed the
fail-open design actually works in practice: those two 403s did not block
or slow down recipe generation, Cook Mode, or Finish & Plate — everything
else completed normally. **Migration was applied later the same session**
(see "Enforcement mechanism" above) — the 403s should be gone now, but that
specific fix hasn't been re-confirmed live yet (verify next session: same
DevTools Network-tab check, expect 200s). Same session: a full recipe
generation (`ask-chef-harris` + `ai-recipe-precision`) took ~9.4s / ~4.7s
respectively, running
concurrently as expected (2026-08-06 fix) — wall time is bounded by the
slower call, not their sum. This ~6-9s range is current normal, driven by
real OpenAI completion latency through the edge-function proxy with no
response caching yet (see Roadmap item 5) — not a regression to chase.

**Follow-up bug found and fixed 2026-08-11**: those 403s did NOT actually
clear after the migration applied 2026-08-10, contrary to what this doc
predicted — real root cause was different from "migration not applied
yet." The `20260810120000_create_api_usage_daily.sql` migration created
the table, RLS policies, and the `increment_api_usage` function, but never
ran a `GRANT` giving the `authenticated` role table-level SELECT/INSERT/
UPDATE privileges (or `EXECUTE` on the function). **RLS policies and
table-level grants are two separate Postgres mechanisms** — a table can
have perfect owner-scoped RLS policies and still 42501 "permission denied"
for everyone, because RLS only filters rows *after* a grant already allows
the query to run at all. Confirmed via `information_schema.role_table_grants`
against the live project: `user_profiles`/`user_meal_plans` (created
earlier, likely inheriting schema-level default privileges at the time)
had full CRUD grants for `authenticated`, `api_usage_daily` had only
REFERENCES/TRIGGER/TRUNCATE — SELECT/INSERT/UPDATE were simply missing.
Root cause of *why* default privileges didn't carry over to this table
wasn't pinned down, but the fix doesn't depend on that: wrote and pushed
`supabase/migrations/20260811120000_fix_api_usage_daily_grants.sql` with
explicit `grant select, insert, update on public.api_usage_daily to
authenticated;` and `grant execute on function public.increment_api_usage(text)
to authenticated;`. **Confirmed fixed live** — re-queried
`role_table_grants` post-push and saw SELECT/INSERT/UPDATE now present,
and Harris's own live Chrome DevTools screenshot the same session showed
`increment_api_usage`/`api_usage_daily` calls returning clean `200`s.
**Lesson for future migrations on this project**: don't rely on default
privileges applying automatically — include explicit `GRANT` statements
for `authenticated` (and `anon` if a table is ever meant to allow
anonymous-session access beyond what `auth.uid()`-scoped RLS implies) in
every new table migration from now on, rather than assuming Dashboard-era
behavior carries over to CLI-pushed migrations.

This directly unblocks the "live-test all four gates" item at the top of
Roadmap item 6's still-needed list — that testing was previously
impossible (every usage-cap check 403'd and silently fell back to
fail-open, so the gates themselves were never actually exercised even
after the table existed). Worth re-running that full checklist next
session now that the underlying permission bug is actually fixed, not
just the table's existence.
