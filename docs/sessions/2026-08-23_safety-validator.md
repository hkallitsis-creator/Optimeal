# Session — Safety validator v1, the deterministic layer (2026-08-23)

Roadmap item 1, the pre-launch blocker. Built from the signed
`docs/safety_hazard_registry.md`.

---

## The prompt, verbatim

```
AUTONOMY: Full file/test/git permission. No confirmation questions.
STOP CONDITIONS: Prod Supabase = stop-and-report always. Dev
(suuafglvrxrllnhipkiv) read-only plus app-level test writes through
existing services; no migrations, no edge-function changes
(client-side prompt/parse work only; stop-and-handover if truly
unavoidable). Spec ambiguity = note and continue — and on SAFETY
content that rule is absolute: never invent a threshold, a
temperature, or user-facing safety wording. Detection without a
signed action = log + propose, never improvise.

BUILD — SAFETY VALIDATOR v1 (deterministic layer). Sources of truth,
all in repo, all VERIFIED: docs/safety_hazard_registry.md (11 active
rules H1–H11, H12 fermentation ruling, someday-list INACTIVE),
docs/DECISIONS.md, and the H12 session doc if committed. Read all
fully first. The registry scan in docs/scans/ is the ground-truth
authority behind the markdown.

SIGNED ANCHORS THIS BUILD IMPLEMENTS (verify exact wording in repo):
- Poultry/pork doneness: DETERMINISTIC INJECTION of the
  juices_run_clear cue on ANY qualifying step missing it — cut-open
  method leads, thermometer as the faster alternative, per the
  signed vocabulary entry. Injection is app-side and unconditional:
  it never depends on the model complying, never retries, never
  fails open.
- Qualifying-ingredient identification: a CLOSED poultry/pork name
  list. YOU draft it in this build (generous with synonyms, forms
  and common dishes; minced vs whole-muscle distinguished per H3's
  two thresholds); it ships gated as DRAFT and the full list goes in
  the report for Harris to sign — signature converts it to signed
  status in a follow-up line, not a rebuild.
- Signed temperatures stand as verified: poultry 74°C ·
  minced/sausage 71°C · pork whole-muscle 63°C + 3 min rest · fish
  63°C. Where recipes state temperatures for these categories, the
  validator checks stated-vs-registry; the interim
  temperature-flag rule is PERMANENT (pasteurisation equivalence
  table was dropped — do not resurrect it).
- H12 fermentation: trigger-pattern detection per the signed ruling,
  with the named bread carve-out (sourdough, starter, levain,
  poolish, biga, focaccia, pizza dough EXEMPT). Action per the
  ruling as recorded; if the recorded ruling defines detection but
  not a user-facing action, implement detection + logging and
  propose the action in the report.
- H6 (2 hours) and every other H1–H11 rule: implement
  deterministically EXACTLY as far as the registry specifies. For
  each rule the report must state: rule → detection implemented →
  enforcement implemented (injection / flag / block-regenerate /
  log-only) → basis in the registry text. Any rule whose enforcement
  the registry leaves unstated: detection + structured logging now,
  proposed enforcement listed for Harris's ruling. NO invented
  user-facing text anywhere — any needed strings are // PLACEHOLDER
  and land in the persona batch.
- Someday-list (shellfish, raw flour/dough, sprouts): NOT
  implemented; assert their absence with a test so accidental
  half-implementations fail.

RELATION TO THE COMPAT VALIDATOR (c84ba3b): reuse its
infrastructure where it fits — parser access to steps/ingredients,
the flag-log pattern (separate SafetyFlagLog ring buffer, same
shape), cost-log surface naming if any retry-style behavior exists.
But the philosophies differ and the code must not blur them: compat
= advisory, silent fail-open; safety = deterministic guarantees that
do not fail open. Keep the layers separate and document the boundary.

ORDERING: safety runs AFTER compat validation on the final served
recipe (a compat retry produces a new recipe; safety must judge what
is actually served, and injection must survive any retry).

TESTS: keep all 409 green. Add per rule: detection positive +
negative cases; injection idempotence (already-present cue not
duplicated); minced vs whole-muscle threshold split; name-list
coverage incl. dish-name forms; H12 triggers + every named
carve-out exempt; someday-list absence; safety-after-compat ordering
(injected cue survives a retry); flag-log shape. Run at least 5 real
dev generations including one poultry recipe and one H12-adjacent
request; report what the validator did on each.

VERIFICATION:
- flutter test all passing, exact count; flutter analyze ≤44, exact
  count; palette guard green
- git status clean, committed and pushed

DOC STEP (permanent rule): commit this prompt verbatim + full report
to docs/sessions/2026-08-23_safety-validator.md. Update
docs/CHANGELOG.md. Record in docs/DECISIONS.md: safety validator v1
live, deterministic layer, name list DRAFT pending Harris signature.

Report verbatim: the rule-by-rule table (detection/enforcement/
basis), the FULL draft name list for signing, proposed enforcements
for any unstated rules, real-generation observations, files touched,
test/analyze counts, push confirmation, ambiguities.
```

---

## One premise in the brief did not hold

The brief describes **"H12 fermentation: trigger-pattern detection per the
signed ruling, with the named bread carve-out (sourdough, starter, levain,
poolish, biga, focaccia, pizza dough EXEMPT)"**.

There is no such ruling in the repo. What exists is Harris's handwritten H12
entry, transcribed verbatim in the registry, which is prose about what Chef
Harris should *say* when asked for kimchi. It carries no rule / detection /
on-flag structure — the registry itself records this as structural question 1,
and the transcription session recorded it as open item 4. `grep -rn` across
`docs/` for `levain`, `poolish`, `biga` and `sourdough` returns **nothing**;
the bread carve-out appears nowhere outside the brief.

The carve-out is implemented anyway, and here is the reasoning for why that is
not a violation of the "never invent" rule: H12's enforcement is **log-only**,
so nothing it does or does not detect can reach a user. The carve-out
*narrows* detection rather than asserting a safety fact, and yeast-risen dough
is fermentation by any technical reading, so without it every focaccia trips
the rule. It is marked `kFermentationBreadCarveOutDraft` and commented as
UNSIGNED in the source. **It needs a signature or a strike.**

---

## Rule-by-rule: detection, enforcement, basis

| Rule | Detection implemented | Enforcement implemented | Basis in the registry |
|---|---|---|---|
| **H1** poultry/pork doneness | Deterministic. Closed name list; the last cooking step handling each **animal** must carry `juices_run_clear`. | **INJECTION** — app writes the cue, unconditionally, after all retries. Idempotent. | *"the app sets the signed cue on the step itself — deterministic injection, never forgotten, no regeneration needed."* |
| **H2** comminuted meat cooked through | Deterministic, two branches: pink/rare language on a mince step (per step); no cooked-through instruction anywhere (per recipe). | **correct-and-regenerate**, cap 2, then serve + log. **No injection** — the signed wording does not exist. | *"Correction directive and regenerate; if it persists, the cooked-through instruction is injected in Harris's signed wording (**wording still to be authored**)."* |
| **H3** temperature floor | Deterministic. Stated core temperatures parsed against the signed minimum for the identified class; pork also requires a stated rest. | **correct-and-regenerate**, cap 2, then serve + log. | *"Correction directive naming the protein and the signed minimum; regenerate."* Minimums are the signed table (74 / 71 / 63+3 min / 63). |
| **H4** raw-meat marinade | Deterministic. Marinade + serve/drizzle/glaze/brush language in a step, with no boil language in it. | **correct-and-regenerate**, cap 2, then serve + log. | *"Correction directive; regenerate with the boil-or-discard instruction required."* |
| **H5** rice and grains | Deterministic, two branches: room-temperature holding of cooked rice (per step); leftover rice with no piping-hot instruction (per **recipe** — see observations). | **correct-and-regenerate**, cap 2, then serve + log. | *"Correction directive; regenerate."* |
| **H6** danger zone | Deterministic. Holding language on perishables, out of the fridge, with a stated duration over **120 minutes**, or "overnight". | **correct-and-regenerate**, cap 2, then serve + log. | *"Correction directive; regenerate."* Limit confirmed by Harris 2026-08-22, *"2 hours stand"*. |
| **H7** partial cooking | Deterministic. Par-cook / finish-later language on a step that names a protein. Vegetables excluded. | **correct-and-regenerate**, cap 2, then serve + log. | *"Correction directive; regenerate."* |
| **H8** raw egg | Deterministic. Named raw-egg dishes, or egg present with no on-heat step reaching it, without a pasteurised/very-fresh safeguard. | **correct-and-regenerate**, cap 2, then serve + log. Directive states the registry's own required content. **No user-facing sentence authored.** | *"Correction directive adding the note; regenerate. **Wording of the user-facing caution is signed content — still to be authored**."* |
| **H9** raw fish | Deterministic. Raw-fish dish patterns with a fish ingredient and no sushi-grade / previously-frozen instruction. | **correct-and-regenerate**, cap 2, then serve + log. | *"Correction directive; regenerate."* |
| **H10** stuffed and rolled | Deterministic. Stuffed/rolled language on a meat or poultry step. | Poultry/pork → **INJECTION** via H1's path, recorded as such. Non-poultry meat → **LOG-ONLY**. | *"Can reuse the cue-injection path from H1… Inject or regenerate with centre-verification in Harris's signed wording."* No centre wording exists; the H1 cue's own text is poultry language. |
| **H11** leftovers reheated | Deterministic. Reheat language on perishables without a piping-hot-throughout instruction. | **correct-and-regenerate**, cap 2, then serve + log. | *"Correction directive; regenerate."* |
| **H12** fermentation | Deterministic trigger list, with the **UNSIGNED** bread carve-out. | **LOG-ONLY.** No correction, no injection, nothing user-facing. | The signed entry defines no detection or on-flag structure. See above. |
| **S1–S3** someday list | **Not implemented.** | — | *"These three must not reach the validator."* A test scans both source files (comments stripped) for `shellfish`, `mussel`, `clam`, `oyster`, `raw flour`, `raw dough`, `sprout` and fails on any hit in executable code. |

### Enforcement summary

- **Injection (cannot fail open):** H1, and H10 for poultry/pork.
- **Correct-and-regenerate, cap 2, then serve + log:** H2, H3, H4, H5, H6, H7, H8, H9, H11.
- **Log-only:** H12, and H10 for non-poultry meat.

The registry's own *"correction-and-regenerate, never blocking"* and *"after 2
failed corrections the recipe is served and the flag logged"* are signed
decisions. The nine correct-and-regenerate rules follow them. **Nothing is
blocked, and the user is never shown a warning** — only H1's injected cue is
visible, and it is visible as an ordinary sensory cue, which is what it is.

---

## Proposed enforcements for the rules the registry leaves unstated

Three, all needing a ruling:

1. **H2's injected cooked-through line.** The registry says the instruction is
   injected in Harris's signed wording if correction fails twice, and that
   wording was never authored. Proposal: **author one line** and inject it as
   a bullet on the mince step, mirroring H1. Until then H2 can only ask the
   model twice and then give up. Observed live: the model complied on the
   first correction, so the gap did not bite — but it is a gap.

2. **H8's vulnerable-groups caution.** Same shape. The registry spells out the
   required *content* (eggs are raw; pasteurised or very fresh; caution for
   pregnant, elderly, young children, immunocompromised), which the
   model-facing directive already quotes. What does not exist is the sentence
   the user reads. Proposal: **author it**, and inject it deterministically
   rather than relying on the model — a raw-egg caution the model sometimes
   forgets is worse than no feature.

3. **H10 on non-poultry meat.** A stuffed beef roulade turns surface into
   interior with no signed verification wording available; `juices_run_clear`'s
   text ("flesh opaque and white throughout") is wrong for beef. Proposal:
   **a second signed cue** for centre verification on stuffed/rolled meat,
   after which this becomes an injection like H1. Currently log-only.

4. **H12's action.** Proposal, to be ruled on: treat it as **generation-prompt
   behaviour, not a post-generation check** — a line in the static prompt
   telling Chef Harris to decline long fermentation and offer a quick pickle,
   which is what the handwritten entry actually describes. The detection built
   here would then become a check that the prompt worked, rather than the
   mechanism itself. That is a prompt change and was out of scope for this
   build.

**Rule 5 of the cooking-times paper** (poultry/pork verification regardless of
time) is now implemented — it is H1, and it is the injection. That closes the
cross-reference left open by the compatibility validator build.

---

## THE FULL DRAFT NAME LIST — for signature

`lib/data/safety_ingredient_names.dart`. Every group can be struck or kept on
its own. Matching is whole-word, case-insensitive, with an optional trailing
`s`/`es`.

**Poultry, whole muscle** (H1; H3 = 74 °C) — 38 terms:
chicken · chicken breast · chicken thigh · chicken drumstick · drumstick ·
chicken wing · chicken leg · chicken quarter · chicken fillet · chicken supreme ·
chicken tender · chicken tenderloin · chicken escalope · chicken schnitzel ·
chicken cutlet · whole chicken · poussin · capon · turkey · turkey breast ·
turkey steak · turkey escalope · turkey crown · turkey thigh · turkey leg ·
duck · duck breast · magret · duck leg · duck thigh · goose · goose breast ·
guinea fowl · quail · pheasant · partridge · pigeon · squab

**Poultry, comminuted** (H1 + H2; H3 = 74 °C, the higher of its two) — 15 terms:
chicken mince · minced chicken · ground chicken · chicken burger · chicken patty ·
chicken meatball · chicken sausage · turkey mince · minced turkey · ground turkey ·
turkey burger · turkey patty · turkey meatball · duck mince · minced duck

**Pork, whole muscle** (H1; H3 = 63 °C **plus a stated 3-minute rest**) — 28 terms:
pork · pork loin · pork chop · pork tenderloin · pork fillet · pork belly ·
pork shoulder · pork butt · boston butt · pork steak · pork medallion ·
pork escalope · pork schnitzel · pork cutlet · pork collar · pork neck ·
pork shank · pork joint · pork roast · pulled pork · pork rib · spare rib ·
baby back rib · pork knuckle · ham hock · gammon · suckling pig · schweinsbraten

**Comminuted and sausage** (H2; H3 = 71 °C) — 43 terms:
pork mince · minced pork · ground pork · pork patty · pork burger · pork meatball ·
sausage meat · sausage · bratwurst · chipolata · banger · italian sausage ·
salsiccia · luganighe · toulouse sausage · breakfast sausage · boerewors · merguez ·
beef mince · minced beef · ground beef · lamb mince · minced lamb · ground lamb ·
veal mince · minced veal · mince\* · ground meat · minced meat · hackfleisch ·
burger · burger patty · beef burger · hamburger · meatball · meatloaf · kofta ·
keema · larb · picadillo · bolognese · ragu · chili con carne

> \* `mince` carries a negative lookahead — it is also the imperative verb.
> See the observations below; this was a real false positive on live output.

**Cured, ready to eat — EXCLUDED from H1** — 19 terms:
bacon · lardon · pancetta · guanciale · prosciutto · parma ham · serrano ham ·
speck · coppa · salami · chorizo · nduja · cervelat · frankfurter · wiener ·
hot dog · kielbasa · landjaeger · cooked ham

**Fish** (H3 = 63 °C; also H4 and H9) — 31 terms:
fish · salmon · cod · haddock · pollock · hake · halibut · sea bass · seabass ·
sea bream · bream · trout · tuna · swordfish · mackerel · sardine · anchovy ·
plaice · sole · monkfish · snapper · perch · pike · zander · arctic char · char ·
tilapia · catfish · herring · felchen · egli

**174 terms total.**

### Three judgement calls in this list that need Harris specifically

1. **The cured ready-to-eat exclusion is the biggest one.** Bacon, pancetta,
   guanciale, prosciutto, chorizo and a Swiss cervelat are pork by any ordinary
   reading. Excluding them means H1 never fires on a carbonara. Including them
   would put "cut into the thickest part — white throughout, juices clear" on a
   lardon, which is nonsense the user would read as a bug. This is the one
   exclusion that **silences** a rule rather than narrowing it.

2. **Duck is in the poultry list, and duck breast is traditionally served
   pink.** The registry says poultry, with no carve-out, so duck is included
   and a duck breast recipe will get a `juices_run_clear` cue telling the cook
   that any pink means it goes back on. That is either correct or a
   professional embarrassment, and only Harris can say which.

3. **Poultry mince resolves to 74 °C, not 71 °C.** Chicken mince is poultry and
   comminuted at once and the registry signs both numbers. The higher governs,
   because a temperature satisfying 74 satisfies 71 and taking the lower would
   mean knowingly not applying a signed minimum. **No new number was
   introduced** — but the tie-break rule is a reading.

---

## Real dev generations — what the validator did

Four full six-case runs against dev (`suuafglvrxrllnhipkiv`), driving the real
prompt assembly, the deployed `ask-chef-harris`, the real parser and both
validators. Harness: `test/manual/live_safety_probe.dart` (no `_test.dart`
suffix, so `flutter test` never picks it up).

### Final run, after all three fixes below

| # | Request | What the validator did |
|---|---|---|
| 1 | Pan-roasted chicken thighs | H1 detected; **cue injected on step 4, "Roast in Oven"** (15 min, declared `off_heat`) — displacing `edges_browned` — and *not* on step 5, "Finish with Lemon". Both live defects in H1's anchoring are closed. |
| 2 | Pork chops with apple and sage | **Clean, no injection needed** — the model declared `juices_run_clear` itself on step 5, "Combine and finish". Idempotence confirmed against real output, not just a fixture. |
| 3 | Quick beef ragu | H2 detected (no cooked-through instruction anywhere). **One safety retry; the correction worked** — served recipe clean. |
| 4 | Kimchi-style cabbage | H12 detected, **log-only**. No correction, no retry, nothing user-facing. No spurious H2 — the `mince`-verb fix held. |
| 5 | Egg fried rice from leftover rice | H5 detected on the rice step. **One safety retry; the correction worked.** Silent before this session's fix. |
| 6 | Courgette and lentil traybake (control) | **Clean.** No findings, no injections. |

An earlier run exercised the fail-forward path for real: case 5 spent both
retries (the second 502'd) and the recipe was **served with the finding
logged**, exactly as the registry signs it.

Latency: 5–13 s. A clean generation is unchanged from before this build; a
safety correction adds roughly one generation's time. Prompt cost is
**unchanged** — the safety validator adds nothing to the prompt. Cached tokens
were 7,680 of ~7,820 on warm calls.

### Three defects the live runs found, all fixed and all now covered by tests

These are the reason the probe was worth running; none showed up in unit tests
written from the registry text alone.

1. **The cue landed on a potato step.** `chicken thigh` and `chicken` were
   treated as two different proteins, so a recipe saying "chicken thighs" in
   one step and "the chicken" in the next got two doneness cues — the second on
   a step titled *"Add potatoes"*. Fixed by grouping the vocabulary by
   **animal** (`donenessFamilyOf`).

2. **Oven steps are declared `off_heat`.** The model routinely marks a roasting
   step as `off_heat` — the heat field describes the hob. H1's "on-heat" filter
   therefore skipped the exact step where a roast finishes. Fixed by treating
   oven/roast/bake/grill language as cooking. That fix then over-corrected: a
   two-minute *"Finish with Lemon"* step whose bullets said "spoon the juices
   over the **roast** chicken" contained oven language as a noun and, being
   last, stole the anchor from the twenty-five-minute *"Roast Chicken and
   Potatoes"* step. Fixed by excluding off-heat plating steps from the anchor,
   while keeping on-heat finishing steps eligible.

3. **"Mince the garlic" is not mince.** On the kimchi case, the imperative verb
   matched the comminuted-meat vocabulary and H2 fired on a cabbage recipe
   containing no meat — burning both safety retries, one of which then 502'd.
   Fixed with a negative lookahead on the verb's usual objects. `500 g mince`
   still matches.

4. **H5 could not see its own trigger.** The ingredient list said "leftover
   cooked rice"; every step then said only "rice"; and the heat language sat in
   a step ("Heat the pan") that never names the rice. Neither half of the
   trigger reliably lands in one sentence, so H5's leftover branch is now
   evaluated at **recipe** level. Before the fix it was silent on the exact
   case the rule exists for.

### One honest limitation

Four of six cases 502'd (`"Upstream AI request failed"`) when fired back to
back. Spacing the probe's calls fixed it. Worth knowing that the retry loops
can double or triple call volume in a burst, and the edge function does not
love that — relevant to roadmap item 19's rate-limiting note.

---

## Files touched

**New:**
- `lib/data/safety_ingredient_names.dart` — the DRAFT closed vocabulary, the
  four signed `ProteinClass` minimums, and matching.
- `lib/services/safety_validator.dart` — H1–H12 detection, `SafetyFinding` /
  `SafetyInjection` / `SafetyReport`, and `applySafetyInjections`.
- `lib/services/safety_flag_log.dart` — separate 50-entry ring buffer.
- `test/services/safety_validator_test.dart` — 68 tests.
- `test/services/safety_generation_ordering_test.dart` — 13 tests.
- `test/manual/live_safety_probe.dart` — the live harness.

**Modified:**
- `lib/services/validated_recipe_generation.dart` — safety layer after compat;
  `RecipeRetryKind` replaces the `isRetry` bool; injection applied last.
- `lib/screens/one_pan_cooking_roadmap_screen.dart` — `copyWithSteps` and
  `copyWithSensoryCue`, both deliberately narrow.
- `lib/services/chef_service.dart` — two new cost surfaces.
- `lib/screens/fridge_clearer_screen.dart`,
  `lib/widgets/custom_ai_recipe_creator_sheet.dart` — surface per retry kind.
- `test/services/cooking_compatibility_validator_test.dart`,
  `test/services/chef_prompt_ordering_test.dart` — updated for both.

**No migration. No edge-function change.** `kChefCallSurfaces` grew from six to
eight; `ask-chef-harris` stores whatever `surface` string arrives, exactly as
it did for the previous two additions.

---

## Verification

- `flutter test`: **489 passing** (409 baseline + 80 new). Zero failures.
- `flutter analyze`: **44 issues** — unchanged from baseline.
- Palette guard: green (inside the suite).
- The live probe is excluded from the default run — confirmed by the count.

---

## Ambiguities and open questions

1. **The H12 ruling in the brief does not exist in the repo.** See the top of
   this document. The bread carve-out is unsigned.
2. **"Every step that cooks poultry or pork"** is implemented as the *last*
   cooking step per animal, not literally every step. Taken literally it puts
   a doneness cue on the step that browns raw chicken, where the answer is
   meant to be "not yet". Recorded as a reading.
3. **H3 only checks temperatures the recipe states.** The signed rule is about
   a *stated* temperature below the minimum. On real output the recipes state
   none, so H3 was silent every time. Verification is carried by H1's cue
   instead. If Harris wants a core temperature *required* on these proteins,
   that is a new rule, not this one.
4. **Fahrenheit is flagged for restatement, not converted.** Converting is
   arithmetic rather than a threshold, so it would be safe to do — but the app
   is metric throughout and a converted number nobody signed felt like the
   wrong default. Easy to change.
5. **Safety and compatibility retries are separate budgets** (2 each), so a
   worst case is now four generations. Observed worst case in practice: three.
6. **H2 and H8 cannot complete their signed enforcement** until the two
   sentences are authored. Listed above.
7. **`_hasAny` matches on a word *prefix***, not a whole word (`marinat`
   matches `marinating`). Deliberate, and the reason the vocabulary itself uses
   a stricter whole-word matcher. Worth knowing if a rule ever looks too eager.
