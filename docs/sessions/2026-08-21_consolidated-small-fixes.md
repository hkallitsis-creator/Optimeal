# Session — Consolidated small-fixes build (2026-08-21)

Third session of 2026-08-21, after `2026-08-21_prompt-caching-numbers.md`
(read-only) and `2026-08-21_ground-truth-resync.md` (read-only + doc commits).
Dev Supabase in scope for exactly one migration and one function redeploy.
Prod never contacted. Repo HEAD at session start: `08a8435`.

---

## Prompt (verbatim)

```
AUTONOMY: Full file/test/git permission. No confirmation questions.
STOP CONDITIONS: Prod Supabase = stop-and-report always. Dev Supabase
(suuafglvrxrllnhipkiv, --linked) IS in scope this session for exactly:
one migration on api_call_cost_log + redeploy of ask-chef-harris. Any
other dev DB write = stop and report. Spec ambiguity = note and
continue, never guess.

CONSOLIDATED SMALL-FIXES BUILD — 6 items + docs

1. BOOKMARK ON GENERATION SURFACES
Mount the existing SaveRecipeBookmarkButton on both generation-result
surfaces, same behavior/semantics as its five current mounts:
- _GeneratedRecipeCard (fridge_clearer_screen.dart:1125-1141) — add
  alongside the existing actions; do not displace Cook Now as primary
- GeneratedRecipeActionsSheet (generated_recipe_actions_sheet.dart)
Wire whatever recipe object each surface holds into the button's
expected input; if the freshly generated recipe lacks a field the
service requires (e.g. no persisted id yet), follow the pattern the
post-cook verdict/celebration sheets use for not-yet-saved recipes.
If no such pattern exists and a design gap emerges, note and continue
with the closest safe behavior — do not invent new persistence flows.
Widget tests: bookmark present and functional on both surfaces.

2. PROMPT-ASSEMBLY ORDERING FIX (edge function ask-chef-harris)
Current assembly (index.ts) emits: static header → user profile →
"Recipe context: $recipeTitle" (VARIABLE) → recipeContext → history →
user query (which carries the static schema/vocab block from the
client). This puts ~1,200 static tokens behind a per-call-variable
line, defeating the cedf753 restructure.
Fix: reorder so ALL static content precedes ALL variable content:
static header + any static schema/vocabulary first, then profile,
then recipe context, then history, then the variable user query last.
If the static block currently travels inside the client's userQuery
string (fridge_clearer_screen.dart:225-257 _buildPrompt,
custom_ai_recipe_creator_sheet.dart:81-110), split it: move the static
portion into the edge function's static prefix (or a separate leading
message segment) so the client sends only variable content. Keep the
final assembled semantic content equivalent — same instructions reach
the model, only ordering/transport changes. Do not change model,
temperature, or response schema.

3. COST LOGGING FIXES (dev — explicitly authorized)
a. cost_usd: bill cached_tokens at the cached input rate ($1.25/1M
   gpt-4o) and only uncached prompt tokens at full rate ($2.50/1M).
   Currently overstates ~14%.
b. Migration on dev api_call_cost_log: add a nullable text column
   `surface`. Client passes a surface identifier per call site
   (fridge_clearer / custom_creator / chef_sos — derive from actual
   call sites, don't hardcode my list if it's wrong); edge function
   logs it. Migration file committed to repo per normal flow.
c. Redeploy ask-chef-harris to DEV ONLY (v5). Confirm deploy target
   is suuafglvrxrllnhipkiv before deploying. Do not touch prod
   functions.

4. LEDGER EXPLAINER + VERDICT COPY (approved wording, verbatim)
Ledger screen permanent explainer gains/replaces the provenance
explanation with exactly:
"A recipe created in the Fridge Clearer counts as a rescue wherever
you cook it — right away, or later from your Weekly Planner. What
matters is where the recipe came from, not where you pressed Cook."
Verdict sheet: where the verdict explains why a cook did/didn't count
as a rescue, align the wording to the same ruling — one-line
compression, e.g. "Made in the Fridge Clearer — counts as a rescue
wherever you cooked it." Keep the verdict's existing structure;
only correct wording that implies launch-surface gating.

5. CLAUDE.md STALENESS CORRECTIONS (per resync evidence, minimal edits)
- Item 6: mark the signed confidence wording as implemented
  (what_you_learned_sheet.dart:218/:232/:244,
  confidence_climb_service.dart:30, with regression tests); keep the
  two remaining halves (live-testing at 3+/5+ reps, unfiltered
  cook_session_history_v1 aggregation) as open.
- Item 3: correct "Not started" — diagram_keys.dart holds the closed
  lists, technique_diagram_id declared in both recipe prompts,
  in-context Cook Mode placement live, 3 of 21 diagrams built as
  CustomPainters. Remaining: 18 diagrams + browse library.
- Item 15: note the ~3,400-char vocabulary figure was an estimate of
  a not-yet-authored table, and that the declared cooking_times_key
  decision (option C) supersedes it: prompt will carry only a ~500-char
  closed key list; minutes resolved locally from a signed table
  (to be authored). Record decision C in docs/DECISIONS.md.

6. PUSH STRANDED DOC COMMITS
69cbad8 and 08a8435 are unpushed. Push them with this build's commits.

VERIFICATION
- flutter test: expect 177 + new tests, all passing
- flutter analyze: expect ≤54; report the exact count
- For item 2: after redeploy, run 3 consecutive dev calls through one
  recipe surface with DIFFERENT ingredients/craving each time and
  report prompt_tokens/cached_tokens/surface for each row — the point
  is whether the static prefix now survives variable input (call 2+
  should show cached_tokens ≥ the static-prefix size, unlike before).
  These are legitimate dev writes to api_call_cost_log, in scope.
- git status clean, everything committed and pushed

DOC STEP (permanent rule): commit this prompt verbatim + your full
report to docs/sessions/2026-08-21_consolidated-small-fixes.md in the
same session. Update docs/CHANGELOG.md.

Report verbatim: per-item outcomes, the 3-call cache verification rows,
test/analyze counts, migration + deploy confirmation (dev ref echoed),
push confirmation, any noted ambiguities.
```

---

## Report

### Item 1 — Bookmark on generation surfaces — DONE

Both surfaces mount the existing `SaveRecipeBookmarkButton`, unchanged
semantics:

| surface | placement |
|---|---|
| `GeneratedRecipeCard` (`fridge_clearer_screen.dart`) | beside the recipe title, in a new `Row` |
| `GeneratedRecipeActionsSheet` | header row, between the title and the close button |

**No design gap emerged, and no new persistence flow was invented.** The
concern in the prompt — "if the freshly generated recipe lacks a field the
service requires (e.g. no persisted id yet)" — does not apply: the bookmark's
identity is the recipe *title* via `SavedRecipesService.recipeKeyFor`, and
`save()` writes the whole `CookModeRecipePayload` inline. A freshly generated
recipe is already exactly the shape the post-cook verdict and celebration
sheets pass. Nothing needed to exist first.

`_GeneratedRecipeCard` → `GeneratedRecipeCard` (public) for one reason: it is
constructed only by its screen's State, so a widget test could not reach it
without pumping the whole screen and its Supabase/provider stack. Both
surfaces gained an injectable `service` param, matching the five existing
mounts.

Cook Now was not displaced — a test asserts the card still has exactly one
`FilledButton`, so the bookmark cannot quietly become a third action.

6 new tests in `test/widgets/generation_surface_bookmark_test.dart`.

### Item 2 — Prompt-assembly ordering — DONE, with one spec correction

**Noted ambiguity (correction, not a guess).** The prompt located the assembly
in `index.ts`. It isn't there. The edge function is a thin proxy: it takes
`systemPrompt` and `userMessage` and forwards them. The
header → profile → `Recipe context:` → recipeContext → history → query
sequence is in **`lib/services/chef_service.dart`** (Dart client). The intent
was unambiguous, so the fix went where the code actually is; nothing in the
edge function's message construction changed.

The fix, following the prompt's own preferred shape ("split it … so the client
sends only variable content"):

- `askChefHarris` gained `staticPromptBlock`, written immediately after the
  static header — ahead of the profile block and everything per-call.
- Both callers' static halves moved to a new
  `lib/prompts/recipe_static_prompts.dart`
  (`buildFridgeClearerStaticPrompt`, `buildCustomCreatorStaticPrompt`). They
  live outside the widgets because the cacheable prefix has to be assertable
  on its own.
- Each caller now builds only its variable half for `userQuery`.
- Assembly extracted into `ChefService.buildUserMessage`, with the ordering
  contract written into its doc comment and locked by
  `test/services/chef_prompt_ordering_test.dart` (7 tests).

Model, temperature, and response schema untouched.

**Semantic equivalence was preserved deliberately, including a bug.**
`_buildCurriculumAddendum` keyword-matches the assembled request to pick
Bucket B drawers. Before the split, the callers' static text was part of
`userQuery` and so was matched against. Passing it separately would have
silently changed which drawers get injected — a behavioural change, not an
ordering one — so the static block is explicitly folded back into the match
text. See "Found, not fixed" below for what that behaviour actually is.

### Item 3 — Cost logging — DONE (dev)

**a. Cached-rate billing.** `cost_usd` now prices cached prompt tokens at
gpt-4o's cached input rate and only the uncached remainder at full rate. A
null `cached_tokens` is treated as zero cached, keeping the old conservative
figure for rows that were never measured rather than inventing a discount.
Rates verified against OpenAI's published pricing today, not from memory:
input \$2.50/1M, **cached input \$1.25/1M**, output \$10.00/1M.

Measured on the two warm verification rows: logged \$0.02065 and \$0.02110
against \$0.02433 and \$0.02478 under the old formula — **\$0.00368 less per
call**, which is exactly 2944 × \$1.25/1M.

**b. `surface` column.** Migration `20260821120000_add_surface_to_api_call_cost_log.sql`,
nullable `text` + a `(surface, created_at)` index mirroring the existing
`(function_name, created_at)` shape. Client side, `kChefCallSurfaces` in
`chef_service.dart`.

**Derived from the actual call sites, and the supplied list was right — but
there are three, not four.** `grep -n 'askChefHarris(' lib/` gives exactly
three: `fridge_clearer_screen.dart` → `fridge_clearer`,
`custom_ai_recipe_creator_sheet.dart` → `custom_creator`,
`one_pan_cooking_roadmap_screen.dart` (`_ChefSosSheet`) → `chef_sos`.

Deliberately **no** CHECK constraint on the column: the client owns the
vocabulary, and a constraint would mean a new surface cannot ship without a
migration, with a silently lost cost row as the failure mode. The set already
changed once, on 2026-08-20.

**c. Deploy.** See the confirmation block below.

### Item 4 — Ledger explainer + verdict copy — DONE, one wording judgement noted

Explainer (`home_dashboard_screen.dart`): the provenance line
`'Fridge Clearer cooks count toward it.'` — which described the
pre-2026-08-20 launch-surface rule — is replaced with the approved paragraph
**verbatim**, with a comment telling future readers not to paraphrase it. The
two surrounding lines were left alone.

Verdict (`ledger_verdict.dart`): `notCountedNotFridgeRecipe` was
`"This wasn't cooked from your fridge — only Fridge Clearer cooks count."` —
the only string in the verdict system implying launch-surface gating. Now
**"Rescues come from Fridge Clearer recipes — this one didn't."**

**Noted ambiguity.** The example given —
*"Made in the Fridge Clearer — counts as a rescue wherever you cooked it."* —
is positive framing for the **counted** case, and `ledgerVerdictCopy` has no
entry for `counted` by design (the celebration sheet serves it, and its signed
one-icon/one-line/one-CTA structure would have to grow a second line to carry
it). Since the instruction was also "keep the verdict's existing structure;
only correct wording that implies launch-surface gating", I corrected the one
line that had that problem and left the celebration sheet untouched rather
than restructuring a signed surface. Say the word if you want that sentence
placed somewhere specific.

Also worth knowing: the first rewrite was 15 words and tripped the existing
`ledger_verdict_test.dart` rule that verdict copy stays under 15 words. The
shipped line is 10.

### Item 5 — Doc corrections — DONE

- **CLAUDE.md item 6** now records the signed confidence wording as shipped,
  with the file/line evidence, and keeps the two open halves.
- **CLAUDE.md item 3** corrected from "Not started", including the naming
  point that the built diagrams are `CustomPainter`s rather than `.svg`
  assets.
- **CLAUDE.md item 15** rewritten around the real failure (the reorder was
  correct inside each caller and defeated downstream), the A/B numbers below,
  and the fact that the ~3,400-char figure estimated a table that has never
  been authored.
- **New items 25** (per-surface attribution done; three dev-only migrations
  still not on prod; `user_id` null on every dev row) **and 26** (the
  curriculum-matching finding).
- Architecture facts updated: the AI-calls entry, the saved-recipes gap
  (closed), the provenance copy-drift note (closed), and the RLS table's
  `api_call_cost_log` row.
- **`docs/DECISIONS.md`**: decision C recorded — cooking times reach the model
  as a declared key, never as a table — with the full costing table and an
  explicit note that cost is *not* the deciding reason.

### Item 6 — Push — DONE

See the push confirmation below.

---

## Cache verification (item 2) — dev, ask-chef-harris v5

Three consecutive calls through the Fridge Clearer surface, different
ingredients each time (`courgette/feta/lemon`, `chicken thigh/fennel/orange`,
`white beans/kale/pancetta`), so `recipeTitle` and the whole variable block
changed on every call — the exact case the old ordering broke.

Payloads were generated from the real code (a throwaway `flutter test`
harness calling `ChefService.buildUserMessage` and
`buildFridgeClearerStaticPrompt`, deleted afterwards), not hand-copied, so
these are the bytes the app now sends. Static prefix: 14,012 chars
(system prompt 7,044 + static block 6,968).

Rows as stored in `api_call_cost_log`:

```
created_at (UTC)   surface             prompt cached  comp   cost_usd
03:11:22           fridge_clearer        6924      0    800   0.02531
03:11:28           fridge_clearer        7012   2944    725   0.02110
03:11:33           fridge_clearer        6953   2944    695   0.02065
03:13:01           control_old_order     6924      0    690   0.02421
03:13:08           control_old_order     7012      0    829   0.02582
03:13:12           control_old_order     6953      0    676   0.02414
```

The `control_old_order` rows are three **additional** calls I ran with the
same three ingredient sets assembled in the **pre-fix** order (static block
inside `userQuery`, behind `Recipe context:`). Without them the result would
only have been a comparison against a differently-configured measurement from
three days ago. With them it is a direct A/B:

- **pre-fix: 0 / 0 / 0 cached** — the static prefix never survived varying input
- **post-fix: 0 / 2944 / 2944** — 42.3% of a ~6,950-token prompt, on every
  repeat call

`prompt_tokens` are **identical between the two arms** for each ingredient set
(6924, 7012, 6953), which is the useful proof that this was an ordering change
and not a content change.

**One number came in under the prediction, and I can't fully close it.** The
static prefix is 14,012 chars; at the ~4.0 chars/token the full payload
implies, that is ~3,480 tokens, so the first cache hit "should" have been
~3,456 (27 × 128) rather than 2,944 (23 × 128) — about 500 tokens short. The
cached figure is floored to 128-token blocks and I have no local tokenizer to
measure the block exactly, so I can't say whether the prefix is genuinely
being truncated a little early or whether this dense, punctuation-heavy text
simply tokenizes at ~4.76 chars/token. It does not change the finding — 2,944
vs 0 is the result — but "cached_tokens ≥ the static-prefix size" is not
literally met on my char-based estimate of that size, and I'd rather flag that
than round it away.

Note also that call 1 is cold in both arms. That matches the 2026-08-18
pattern: the first call of a burst never hits, and cross-surface sharing was
never observed.

---

## Found, not fixed

**Curriculum drawers are selected by the prompt's own boilerplate.**
`_buildCurriculumAddendum` keyword-matches the whole assembled request, and
the recipe surfaces' static block embeds the literal `curriculumDrawerKeys`
list and `ingredientCutVocabulary`. So `sauteing`, `braising`, `julienne`,
`dice`, `food_storage` and `leftovers` all appear on **every** recipe-surface
call regardless of what the user actually asked for, and both surfaces
therefore always pull the same handful of drawers from keyword noise rather
than relevance. This predates today and is not caused by the split — but the
split is what surfaced it, and I deliberately preserved it (by folding the
static block into the match text) so that an ordering fix stayed an ordering
fix. Fixing it changes what reaches the model and is yours to call. Filed as
roadmap item 26; related to item 9.

---

## Verification

```
flutter test      190 tests, "All tests passed!"   (was 177; +13 new)
flutter analyze   54 issues found                   (0 error, 9 warning, 45 info)
```

Analyze is unchanged at 54 — the new files and the refactor introduced no new
lints, and none of the 54 are errors.

**Migration**, dev ref echoed:

```
$ supabase projects list
  xwugnhzlnfgmczkbbcbh  hkallitsis@hotmail.com's Project  not-linked
  suuafglvrxrllnhipkiv  optimeal-dev                      LINKED

$ supabase db push --linked
  Applying migration 20260821120000_add_surface_to_api_call_cost_log.sql...
  {"upToDate":false,"migrations":["20260821120000_add_surface_to_api_call_cost_log.sql"],
   "message":"Finished supabase db push."}

column probe: GET .../api_call_cost_log?select=surface&limit=0 -> HTTP 200
```

**Deploy**, dev ref echoed explicitly on the command line:

```
$ supabase functions deploy ask-chef-harris --project-ref suuafglvrxrllnhipkiv --use-api
  {"project_ref":"suuafglvrxrllnhipkiv","functions":["ask-chef-harris"],
   "message":"Deployed Functions."}

$ supabase functions list --project-ref suuafglvrxrllnhipkiv
  "slug":"ask-chef-harris"  "version":5  "verify_jwt":true
```

**Prod was never contacted.** The only prod-scoped call all session was the
`projects list` link check above, which is what confirmed prod is not linked.
No prod migration, no prod deploy, no prod read. The only dev DB writes were
the authorized migration plus the six `api_call_cost_log` rows the
verification calls produced — which the prompt explicitly placed in scope.
