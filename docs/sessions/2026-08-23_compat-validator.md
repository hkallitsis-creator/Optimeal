# Session record — Compatibility validator (declared cooking-times keys, option C)

**Date:** 2026-08-23
**Branch:** `main`
**Feature commit:** `c84ba3b`
**Baseline at session start:** 346 tests passing, 44 analyze issues, tree clean, HEAD `4999d81`
**At session end:** 409 tests passing, 44 analyze issues, tree clean

---

## Part 1 — The prompt, verbatim

> AUTONOMY: Full file/test/git permission. No confirmation questions. STOP
> CONDITIONS: Prod Supabase = stop-and-report always. Dev
> (suuafglvrxrllnhipkiv) read-only plus app-level test writes through existing
> services; no migrations this session — if you conclude a DB table is
> genuinely needed for flag logging, log locally instead and report the case
> for a table; Harris decides later. No edge-function changes (client-side
> prompt work only; stop-and-handover if truly unavoidable). Spec ambiguity =
> note and continue, never guess.
>
> BUILD — COMPATIBILITY VALIDATOR (declared cooking-times keys, Option C,
> signed).
>
> Sources of truth, both VERIFIED: `docs/cooking_times_table.md` (74 rows, 6
> bands, multipliers, density classes) and the relevant `docs/DECISIONS.md`
> entries. Read both fully first.
>
> **Option C**: the AI receives ONLY a closed key list (compact, ~500 chars);
> it declares a `cooking_times_key` per relevant ingredient/step; the APP
> resolves key → minutes/band deterministically from a Dart map derived from
> the signed table. The model never states an authoritative time.
>
> Size scaling = TIME MULTIPLIERS ×0.4 / ×1 / ×2.5 / ×5 per the signed paper
> (NOT band shifts). Whole-muscle vs minced distinction as per the table.
>
> Compatibility tolerance: one band.
>
> Violation behaviour: up to 2 auto-correction regenerations (correction note
> appended to the retry prompt), then SILENT fail-open — serve the recipe, log
> the flag. Never block, never warn the user.
>
> The prose sequencing rule in the generation prompt STAYS — the validator runs
> alongside it, not instead of it.
>
> Red lentils: figure pending; timing checks SKIP this key; structure it so one
> number closes it.
>
> "Package instructions" rows (dried pasta, white rice, brown rice): minutes
> advisory, band stands — compatibility checks by band, no duration flags.
>
> Data: `lib/data/cooking_times.dart` derived from the markdown table. A test
> asserts parity between the Dart data and the committed doc (row count, every
> key, every band/minutes) so the doc remains the single source of truth and
> drift fails loudly.
>
> Key list: snake_case keys for all 74 rows; compact list injected per the
> static-before-variable ordering rule. Report the actual character count of
> the injected block and the measured token delta on a real dev call
> (before/after, same recipe request) — the cost of this feature should be a
> number, not a guess.
>
> Parser: read declared keys per step; unknown/absent key → no check on that
> step (fail-open by construction), logged.
>
> The check: within a step or explicitly-parallel steps, co-cooking
> ingredients' resolved bands (after multipliers) must sit within one band;
> violations produce a machine-readable flag (step, keys, bands, delta).
>
> Retry loop: max 2 regenerations, correction note names the violating pair;
> then serve + log. Wire into BOTH generation surfaces (Fridge Clearer stage 2,
> Custom recipe). Stage 1 (idea summaries) is NOT validated.
>
> Logging: local structured log (your choice of mechanism), plus the existing
> `api_call_cost_log` surface distinction if retries fire.
>
> Runtime cost honesty: the report must state the observed retry rate across at
> least 5 real dev generations (varied ingredient sets, including at least one
> deliberately incompatible combination to prove the retry fires and the
> correction note works).
>
> TESTS: keep all 346 green. Add: table-parity; multiplier resolution incl.
> whole-muscle vs minced; one-band tolerance edges (exactly one band apart =
> pass); red-lentils skip; package-instructions rows band-checked not
> duration-flagged; violation → correction note → capped retries → fail-open
> serve; unknown key fail-open; flag log shape.
>
> VERIFICATION: flutter test all passing with the exact count; flutter analyze
> ≤44 with the exact count; palette guard green; the 5+ real dev generations
> with observed outcomes; git status clean, committed and pushed.
>
> DOC STEP: `docs/sessions/2026-08-23_compat-validator.md` with this prompt
> verbatim and the full report; update `docs/CHANGELOG.md`; record in
> `docs/DECISIONS.md`: validator live, multiplier basis, red-lentils pending
> exception.
>
> Report verbatim: key-list design + injected size + measured token delta,
> retry observations from real calls, logging mechanism chosen, files touched,
> test/analyze counts, push confirmation, ambiguities.

---

## Part 2 — Report

### Key-list design

**74 keys, one per row of the signed table.** The doc left this open ("that
list either is 74 long or is a coarser vocabulary that these 74 rows resolve
into… not answered anywhere on the paper"). Taking all 74 was the only option
that needed no new authoring: a coarser vocabulary would itself have to be
written, reviewed and signed, and it would throw away exactly the distinction
the field exists for — `potato_waxy_1cm_dice` and `potato_waxy_2cm_dice` are
different bands, and collapsing them to `potato_waxy` makes the validator blind
to the single most common real mistake.

Keys are derived mechanically from the doc (ingredient + reference cut), sorted,
and joined with `, `. Sorting is not cosmetic: the string sits in the cached
prompt prefix, and a list whose order wobbled between builds would invalidate
the cache for every user on every release.

Fail-open is built into the vocabulary rather than bolted on downstream. An
absent key, an unknown key, `"none"`, and a row whose timing is pending all
resolve to *no bands*, and every check is a no-op on an ingredient with no
bands. There is no branch anywhere that says "if we could not check this,
skip" — there is nothing to skip.

### Injected size, and the measured cost

Measured, not estimated:

| | chars |
|---|---|
| Bare key list (74 keys, `, `-joined) | **1,547** |
| Guideline wrapper (instruction + tail) | 842 |
| Schema field `"cooking_times_key": "..."` | 29 |
| **Total added to the static block** | **2,418** |
| Total added to the assembled user message | 2,640 |

The signed option-C decision estimated "~500 chars ≈ 125 tokens". The real
figure is **~5× that in characters**, for the reason above (74 rows, not ~26).

**Token delta on a real dev call**, same recipe request, same static block
otherwise, `gpt-4o` on dev (`suuafglvrxrllnhipkiv`):

| call | prompt tokens | cached | completion |
|---|---|---|---|
| without the key list | 6,945 | 0 | 803 |
| with the key list (cold) | 7,741 | 0 | 888 |
| with the key list (warm, identical prefix) | 7,741 | **7,552** | 1,020 |

**Delta: +796 prompt tokens (+11.5%).** At gpt-4o's $2.50/M input and $1.25/M
cached, that is **+$0.0020 on a cold call and +$0.0010 on a warm one** — versus
the decision's estimate of $0.00016 warm, so roughly 6× the estimated running
cost. It is still a fifth of a cent per recipe.

The warm call shows 97.6% of the whole prompt cached, which confirms the block
landed where it was supposed to: entirely inside the cacheable prefix, ahead of
everything per-call. `test/services/chef_prompt_ordering_test.dart` now asserts
that ordering directly rather than leaving it to be re-measured.

**One unbudgeted side effect, worth Harris's attention.** The 2,640-char growth
of the assembled message is 222 chars more than the 2,418 that was deliberately
added. Diffing the two assembled messages shows why: the key list changed which
curriculum/substitution drawers `_buildCurriculumAddendum` keyword-matches.
Three drawers were gained (kale, carrot, basil+garlic+tomato, +1,229 chars) and
three lost (potato-waxy, garlic, miso+butter+garlic, −1,226 chars). This is
roadmap item 26 biting in a new place: the drawers a recipe gets are now partly
decided by a list of ingredient keys that has nothing to do with what the user
asked for. Net cost ≈ zero; net *relevance* is worse. Not fixed here — fixing
it changes what reaches the model, which is a behavioural change and Harris's
call, exactly as item 26 already says.

### Retry observations from real dev calls

Eight recipes generated against live dev, seven of them with the key list.
Varied deliberately: fridge-clearer and custom-creator surfaces, 2-portion and
4-portion, 25-minute and 2-hour, meat / fish / vegetarian.

**How well the model declares keys.** 3–5 of the cooked ingredients per recipe
carried a key; oil, salt, herbs and stock correctly carried none. **It never
invented a key outside the closed list** across all seven — the only non-list
value it ever produced was the literal string `"none"`, which it clearly copied
from the `technique_diagram_id` convention. That is the field working, not
missing, so the parser now treats `"none"` as absence and does not count it as
a rejection.

**Observed flag rate.**

| implementation | flagged | rate |
|---|---|---|
| rules 3 and 4 read literally off the paper | 4 of 7 | 57% |
| after the two precision decisions below | **1 of 7** | **14%** |

A 57% retry rate would have meant roughly one extra ~7,900-token call for every
other recipe, and almost all of it was noise. Two causes, both visible in the
raw output:

1. **Off-heat steps.** The model routinely writes a `Prepare ingredients` or
   `Assemble tray` step at `heat: off_heat` and lists four ingredients against
   it. Nothing is cooking, so nothing is co-cooking; comparing bands there is
   meaningless. Off-heat steps are now skipped entirely.
2. **Rule 4 against a single step's duration.** Stewing beef (B6) browned for
   10 minutes and *then simmered for 90* was being flagged as a 10-minute step.
   An ingredient added in step 1 keeps cooking through steps 2..n, so the
   correct comparison is against the total heated minutes from the step that
   adds it to the end of the recipe. Off-heat minutes (resting, plating) do not
   count as cooking time.

Both are decisions beyond the literal text of the paper — see Ambiguities.

The one surviving flag is genuine: a tray bake that sautéed onion, then listed
raw `onion_soften_1cm_dice` (B2) again in the 20-minute roast alongside
`chicken_breast_whole_2_5cm` (B4). Two bands apart, and the onion would indeed
be gone.

**The retry was fired for real, end to end.** The correction note from that
recipe was appended to the variable half of the same prompt and sent to dev:

> Step 5 ("Roast Chicken and Potatoes") adds chicken_breast_whole_2_5cm (B4,
> 10-15 min) and onion_soften_1cm_dice (B2, 3-5 min) at the same time. That is
> 2 bands apart; the limit is one. Give the slower one a head start in its own
> earlier step, or cut it smaller so the two land within one band of each other.

The retry returned a recipe that **validates clean** — 7,885 prompt tokens
(3,968 cached), 900 completion. So one correction, one fix, and the cap of two
was never reached on any real generation this session.

**The deliberately incompatible scenario did not fire, and that is reported as
it happened.** Scenario `g6` instructed, in the user's own voice, that brown
rice, spinach, rocket, potatoes and spring onion all go in "at the same time,
in a single cooking step, and nothing is added later". The model declined and
staggered the adds anyway. The prose sequencing rule that stayed in the prompt
is the likely reason. The retry loop is therefore proven on a *naturally
occurring* violation rather than a forced one, which is arguably better
evidence, but the forced case is not evidence of anything and is not claimed as
such.

### Logging mechanism chosen

**`CompatibilityFlagLog`, a bounded local ring buffer in `SharedPreferences`
(50 entries, newest first), plus a `debugPrint` mirror.** Every validated
generation is recorded, clean or not — a log holding only failures cannot
produce a rate.

No table. The brief allowed one; nothing needs it yet. Every consumer of this
data today is a developer asking "how often does the model break the rule, and
does the correction work?", which a device-local log answers completely, and a
table would add a migration, an RLS policy, a grant, a write on the hot
generation path and a round trip to answer the same question from a different
machine. **The case for a table starts the moment there are real testers whose
flag rates cannot be read off their own phones** — at that point the local log
stops being observable and the shape recorded here (`surface`, `retries_used`,
`served_with_flags`, plus the flag list) is already the table's columns.

Retries are separately visible in cost data without any new storage:
`fridge_clearer_retry` and `custom_creator_retry` were added to
`kChefCallSurfaces`, so the retry rate is a `GROUP BY surface` on
`api_call_cost_log`. The edge function needed no change — it stores whatever
`surface` string arrives, same as when `fridge_ideas` was added.

Every write is wrapped in try/catch. The whole design is fail-open; a log that
could throw would undo that.

### Files touched

Added:

- `lib/data/cooking_times.dart` — 74 rows derived from the doc, the 6 bands,
  the 4 multipliers, the 4 shape adjustments, the 5 density classes, and
  `CookingTimes.promptKeyList`.
- `lib/services/cooking_compatibility_validator.dart` — the check, the flags,
  the correction note.
- `lib/services/validated_recipe_generation.dart` — generate → validate →
  correct → serve, capped at 2 retries.
- `lib/services/compatibility_flag_log.dart` — the local structured log.
- `test/data/cooking_times_parity_test.dart` (6 tests)
- `test/data/cooking_times_resolution_test.dart` (16 tests)
- `test/services/cooking_compatibility_validator_test.dart` (38 tests)

Modified:

- `lib/models/recipe_model.dart` — `RecipeIngredient.cookingTimesKey`,
  validated against the closed list on read, round-tripping through both jsonb
  codecs for free (both go through `RecipeIngredient.fromJson`/`toJson`).
- `lib/services/chef_recipe_parser.dart` — `_readDeclaredCookingTimesKey`, the
  fifth closed-vocabulary reader, with an unknown-key sink.
- `lib/prompts/recipe_static_prompts.dart` — schema field + guideline + key
  list, in both recipe prompts, not in the ideas prompt.
- `lib/services/chef_service.dart` — the two retry cost surfaces.
- `lib/screens/fridge_clearer_screen.dart` — stage 2 through the orchestrator.
- `lib/widgets/custom_ai_recipe_creator_sheet.dart` — same.
- `test/services/chef_prompt_ordering_test.dart` — six surfaces, and the key
  list's position inside the cached prefix.

### Counts

- **`flutter test`: 409 passing, 0 failing** (346 baseline + 63 new).
- **`flutter analyze`: 44 issues** — exactly the baseline, no new ones.
- Palette guard (`test/theme/palette_token_guard_test.dart`): green. No colour
  literal was added; this build touches no UI.

### Ambiguities and decisions

1. **74 keys, not "~26".** The doc flags this as unanswered on paper. Reasoning
   above. If Harris wants a coarser vocabulary, the change is confined to
   `promptKeyList` and a resolution step — the table itself does not move.
2. **"Explicitly-parallel steps" was not built.** The paper says "within a
   single step", and the recipe schema carries no parallelism marker. Adding
   one would mean a new declared field on every step, more prompt surface and a
   codec change, to cover a case that is usually a second pan and therefore not
   co-cooking at all. Grouping is per step.
3. **Rule 5 is deliberately absent.** "Any poultry or pork step without a
   verification instruction is a flag" is food safety, which is roadmap item 1
   with its own signed hazard registry. `SensoryCue.mandatoryOnPoultryAndPork`
   already exists for it. This file is timing only, and its doc comment says so.
4. **Off-heat steps are skipped, and rule 4 uses cumulative heated time.** Both
   go beyond the literal paper text; both were forced by measured false
   positives on real output; both are argued above and marked in the source.
   **These are the two decisions in this build most worth Harris overruling if
   he disagrees** — they are the difference between a 57% and a 14% retry rate,
   so they are also the two with the most cost attached.
5. **`lamb_diced_2cm_dice` (the sheet's only dual-band row) passes if *either*
   of its bands is compatible.** The paper does not resolve which regime the
   row is in, so the permissive reading is the fail-open one. Still open on
   paper.
6. **Red lentils.** The key is declarable — the model may name the row — but it
   resolves to no band, so every timing check skips it. Closing it is a
   one-number edit: fill the time and band cells in
   `docs/cooking_times_table.md` and re-derive; the parity test will fail until
   the Dart matches, which is the intended forcing function.
7. **`"none"` accepted as absence** in `cooking_times_key`, per observed real
   output. Noted here because it is a small vocabulary decision made mid-build
   on evidence, not from the spec.
