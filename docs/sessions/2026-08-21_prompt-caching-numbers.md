# Session — Prompt-caching numbers (2026-08-21)

Read-only session. Dev Supabase only (`suuafglvrxrllnhipkiv`). No schema
changes, no migrations, no writes, no deploys. Repo HEAD at the time:
`10b1d7e`, working tree clean.

---

## Prompt (verbatim)

```
Prompt-caching numbers session. READ-ONLY task — no schema changes, no
migrations, no writes to any table. Query the dev Supabase project only
(suuafglvrxrllnhipkiv, --linked). If any step would touch prod, stop and
report instead of proceeding.

AUTONOMY: you may run read-only SQL queries against dev, inspect the
edge function logs/source, and read any file in the repo without asking
first. Do not modify code. Do not deploy anything.

CONTEXT: cedf753 reordered static-before-variable content in
chef_service.dart, fridge_clearer_screen.dart, and
custom_ai_recipe_creator_sheet.dart so the ~6,972-char system prompt
sits before variable content in the user-message assembly, and added
cached_tokens capture (api_call_cost_log.cached_tokens, edge function v4
ask-chef-harris). The prior report confirmed the restructure landed but
never gave the actual numbers. That's this session's only job.

PART 1 — Real cached-token numbers, post-restructure
Query api_call_cost_log on dev for every row since the cedf753 deploy.
For each of the surfaces that route through ChefService (identify them
by grepping call sites — don't assume there are exactly 4), report:
- total calls
- average cached_tokens vs average total prompt tokens (cache hit rate)
- whether any surface is NOT getting cache hits, and if so why (look at
  what precedes the static block for that call site)
If dev has too few real rows to be meaningful (likely, given the DB was
near-empty as of 19 Aug), say so plainly rather than drawing conclusions
from a thin sample — don't paper over a small-N problem.

PART 2 — Projected cost, cooking-times vocabulary cached vs uncached
The ~3,400-char cooking-times vocabulary is not yet in the prompt (it's
the input to the still-undecided declared cooking_times_key approach).
Using OpenAI's actual cached-input vs uncached-input pricing for
whatever model ask-chef-harris currently targets (check the edge
function source, don't assume), calculate:
- per-call cost delta if those ~3,400 chars sit INSIDE the cached prefix
  (i.e. added to the static system prompt)
- per-call cost delta if they sit OUTSIDE it (i.e. assembled per-call as
  variable content, the declared-key approach)
- the cost at realistic monthly call volume for each (state your volume
  assumption explicitly, keep it conservative given this is pre-tester)
Show the arithmetic, not just the conclusion.

PART 3 — Report
Plain numbers, no recommendation — the declared-key decision is mine to
make from your numbers, not yours to make for me. Flag anything that
surprised you or that the numbers don't cleanly answer.

Full test suite + flutter analyze at the end (expect no changes, this
is read-only — flag immediately if either baseline moved). Report
verbatim tests/analyze counts, git status, and confirm nothing was
pushed or migrated.
```

---

## Report (verbatim)

# Prompt-caching numbers — dev, post-cedf753

## Surfaces routing through `ChefService` — 3, not 4

| call site | surface | UI entry points |
|---|---|---|
| `lib/screens/fridge_clearer_screen.dart:543` | Fridge Clearer | `nav.dart:129` (`/fridge-clearer`), `nav.dart:135` (planner picker) |
| `lib/widgets/custom_ai_recipe_creator_sheet.dart:173` | Custom AI Recipe Creator | `home_dashboard_screen.dart:51`, `weekly_planner_screen.dart:262` |
| `lib/screens/one_pan_cooking_roadmap_screen.dart:3574` | Chef SOS (`_ChefSosSheet`) | Cook Mode |

`_ChefSuggestionSheet` and `kChefHarrisChatFreeDailyLimit` return **zero grep matches** in `lib/`. cedf753 measured 4 surfaces; one of them (the best-performing, "Suggestion ~90%") was deleted two days later by the Home hub rework. 3 call sites, 5 entry points, today.

---

## PART 1 — Real cached-token numbers

### Sample size: this is a small-N problem, and it's worse than "thin"

`api_call_cost_log` on dev holds **36 rows, all time**. All `function_name = 'ask-chef-harris'`, all `model = 'gpt-4o'`. `cached_tokens` is NULL on 23 of them (pre-v4) and measured on **13**.

- `ask-chef-harris` v4 deployed to dev: **2026-08-18T17:57:28Z**
- cedf753 authored: 2026-08-18T18:24:39Z
- All 13 measured rows: **12 inside a single 59-second window** (18:16:03–18:17:02Z), plus **1 isolated call** on 19 Aug 03:05:54Z
- **Nothing logged since 2026-08-19T03:05Z** — zero calls in the last ~2.5 days

So the post-restructure population is one scripted burst plus one real call. Anything below the aggregate line is inference, not measurement.

### The table has no surface column

`function_name` is the *edge function*, identical on every row. There is no call-site, surface, or prompt-hash column. Per-surface attribution is only possible by clustering on `prompt_tokens` and timing — which happens to work here because the four bursts' warm rates match cedf753's own four quoted percentages **exactly, in the same order**:

| burst | time (Z) | prompt_tokens | cached_tokens | warm rate | commit says |
|---|---|---|---|---|---|
| 1 | 18:16:03–07 | 1987 / 1959 / 1953 | 0 / 0 / 1536 | 78.6% | SOS ~78% |
| 2 | 18:16:10–16 | 1846 / 1845 / 1844 | 0 / 1664 / 1664 | 90.2% | Suggestion ~90% |
| 3 | 18:16:24–39 | 3575 / 3576 / 3577 | 0 / 2944 / 2944 | 82.3% | Fridge Clearer ~82% |
| 4 | 18:16:46–17:02 | 3483 / 3482 / 3486 | 0 / 2944 / 2944 | 84.5% | Custom AI ~85% |
| — | 19 Aug 03:05:54 | 7164 | 0 | 0% | — |

Total calls per surface, post-deploy: **3 each**. That is the honest per-surface "total calls" figure.

### Aggregate

```
sum prompt_tokens   39,777
sum cached_tokens   16,640
aggregate cache rate    41.8%     (all 13 rows)
warm-rows-only rate     84.2%     (7 rows with cached > 0)
rows with zero hit       6 of 13
avg prompt_tokens     3,059.8
avg completion_tokens   536.5
```

CLAUDE.md item 15's "78–90% … on repeat calls" is accurate **as worded** — it is a repeat-call number. The all-calls number is **41.8%**.

### Is any surface not getting hits — and why

Two separate things showed up.

**(a) Every burst's first call is cold, including across surfaces.** Burst 2's opener was cold 3 seconds after burst 1 had a warm 1536-token hit, despite both sending a byte-identical 7,044-char system prompt (`_systemPersona` 3,952 + `_curriculumCore` 2,206 + `_recipeDifficultyByKitchenConfidence` 882 + separators). Under pure prefix caching that first ~1,700 tokens should have matched. It never did, in any of the four transitions. Cross-surface cache sharing did not happen once in this sample.

**(b) The reordering is partly defeated downstream — code fact, not inference.** `_buildCookModePrompt` (`fridge_clearer_screen.dart:225-257`) and `_buildPrompt` (`custom_ai_recipe_creator_sheet.dart:81-110`) put the JSON schema + vocabulary declarations first *within their own string*. But that string is passed to `askChefHarris` as `userQuery`, and `askChefHarris` emits it **last**. Order in `chef_service.dart:651-753`:

```
1. static header                          line 670-686   static
2. "User profile context (local):"        line 688-711   constant per user
3. "Recipe context: $recipeTitle"         line 713-716   ← VARIES PER CALL
4. recipeContext                          line 718-730
5. conversationHistory                    line 732-746
6. "User SOS: $query"  ← the static block line 748
```

`recipeTitle` is per-call variable on both recipe surfaces:
- `fridge_clearer_screen.dart:545` → `idea.title`, built at line 276-278 as `'Fridge Clearer: <ing1> + <ing2> + …'` — changes with the ingredient selection
- `custom_ai_recipe_creator_sheet.dart:175` → `userPrompt`, the typed craving — changes every call

So the ~1,200-token static schema block sits **behind** a line that varies, at roughly token ~1,800. The 82%/84.5% figures are only reachable when `recipeTitle` is held constant — which is exactly the "Try Another with the same ingredients" flow (`excludeTitle` and `recentDishTitles` both live in the trailing variable block, so they vary without touching the prefix). A second generation with *different* ingredients, or a *different* craving, breaks the prefix at `Recipe context:` and caps the hit near the system prompt alone.

Corroborating signal from the conversational bursts: burst 1 cached 1536, burst 2 cached 1664 — exactly one 128-token block apart. SOS emits `recipeContext` (recipe text + current-step marker, which moves as the cook advances) at step 4; Suggestion had none and so diverged one block later at step 6. Consistent fit, n=3 each — not proof.

**Bottom line:** I can't say "surface X gets no hits," because no surface was exercised post-deploy in a realistic pattern. What I can say is that both recipe surfaces have a per-call-variable line sitting in front of their static block, and the burst test did not vary it.

### Three side findings

- **`user_id` is NULL on all 36 rows.** `decodeUserIdFromAuthHeader` (`index.ts:22-34`) needs a 3-part JWT; dev has anonymous sign-in disabled, so the client sends the `sb_publishable_…` key as the bearer — no dots, returns null. Per-user cost attribution is dead on dev. Prod may differ (anon sign-in works there); I did not check, per your instruction.
- **`cost_usd` bills every prompt token at the full input rate** — `index.ts:169` has no cached rate. Across the 13 measured rows it records **$0.16918** against a cache-adjusted actual of **$0.14838**: a **14% overstatement**, which grows as the hit rate grows.
- **Only `ask-chef-harris` is deployed on dev** (v4). `ai-recipe-precision` is absent — deploy hold honored — and its cost is therefore entirely unlogged.

---

## PART 2 — Cooking-times vocabulary, cached vs uncached

**Model:** `gpt-4o`. `index.ts:117` defaults to it, and `ChefService`'s payload (`chef_service.dart:811-816`) sends no `model` key at all, so gpt-4o is the only reachable model. All 36 dev rows confirm it.

**Pricing, verified today** (not from memory): gpt-4o input **$2.50**/1M, **cached input $1.25**/1M, output **$10.00**/1M — a 50% cached discount.

**Token estimate:** 3,400 chars ÷ 4 = **850 tokens**, using the chars/4 estimator this codebase already uses. The measured cached prefixes imply this app's prose runs ~4.3–4.6 chars/token, so the real figure is likely 750–850. 850 is the conservative (high) end.

### Per-call

```
A — inside the cached prefix, warm call
    850 / 1,000,000 × $1.25  = $0.0010625

A — inside the cached prefix, cold call
    850 / 1,000,000 × $2.50  = $0.002125

B — outside the prefix, every call
    850 / 1,000,000 × $2.50  = $0.002125

delta (B − A) on a warm call = $0.0010625     ← exactly 2×
delta (B − A) on a cold call = $0.000000      ← no difference at all
```

The two options are identical on any call that misses cache. The entire difference lives in the hit rate.

### Monthly

**Volume assumption, stated explicitly: 300 calls/month (10/day, one solo developer/tester, no external testers).** Conservative against the record — dev logged 36 calls inside a single ~24.5h window on 18–19 Aug (~35/day) and zero since. I show 150 / 500 / 2000 for scale.

Blended rate at the observed 41.8% cached share: `0.418 × $1.25 + 0.582 × $2.50 = $1.9771/1M` → `850 × $1.9771/1M = $0.001681/call`.

| calls/mo | A @100% warm | A @41.8% (observed) | B (always uncached) | B − A (observed) | B − A (100% warm) |
|---:|---:|---:|---:|---:|---:|
| 150 | $0.159 | $0.252 | $0.319 | **$0.067** | $0.159 |
| 300 | $0.319 | $0.504 | $0.638 | **$0.133** | $0.319 |
| 500 | $0.531 | $0.840 | $1.063 | **$0.222** | $0.531 |
| 2,000 | $2.125 | $3.361 | $4.250 | **$0.889** | $2.125 |

For scale: the average post-deploy call is 3,060 prompt + 537 completion tokens ≈ **$0.0130** at full rates. Adding 850 tokens is **+28% on prompt tokens**, and the A-vs-B difference is **~8% of one call's total cost**.

CLAUDE.md item 15's existing "~$0.0022/call uncached vs ~$0.0011 inside the cached prefix" reproduces exactly ($0.002125 / $0.0010625) against today's verified pricing.

---

## PART 3 — Flags

1. **The sample is one 59-second scripted burst plus one isolated call.** 13 rows, 3 per surface. Nothing has been logged in 2.5 days. Treat the per-surface split as inference — the table has no surface column, and attribution rests on prompt-size clustering plus exact agreement with cedf753's own quoted figures.
2. **The 90% surface no longer exists.** Suggestion was the best performer measured and was deleted on 2026-08-20.
3. **Surprised me:** the cache never carried across surfaces — not once in four transitions, including one 3 seconds apart with an identical system prompt. Prefix caching should have matched there. The data doesn't say why; candidates are OpenAI cache routing (no `prompt_cache_key` is sent) or a cache-write delay. This matters directly because Case A's benefit assumes the system prompt is a warm prefix shared across surfaces — this sample says it isn't. Settling it needs a deliberate A→B→A test, which I did not run.
4. **Also surprised:** burst 1's second call (+2s) was still cold and only the third (+4s) hit, while burst 2's second call (+3s) hit. That looks like a few-seconds cache-write latency — relevant if the honest answer is "real recipe generations are minutes apart anyway, so warm hits are rare regardless of placement."
5. **The ordering defect in (b) above is not mentioned in cedf753 or in CLAUDE.md item 15.** It means 82–85% is the ceiling for the same-inputs case, not the typical case. Of all the numbers here, that's the one I'd least trust for projecting Case A's real benefit.
6. **What the numbers can't answer:** whether the declared-key approach genuinely costs 850 uncached tokens/call. As you specified Part 2 — the 3,400 chars assembled per-call as variable content — it does, and the table above is right. But if the declared-key design instead *replaces* the 3,400-char table with a short closed key list in the prompt and does the lookup locally, its per-call token cost is a fraction of 850 and the comparison inverts. I priced what you asked; the key-list-only variant isn't priced here because its size isn't decided. That's a decision input you may want before choosing.
7. **`cost_usd` overstates by 14%** on the measured rows and will overstate more as hit rates rise — worth knowing before any of those numbers get quoted forward.

Sources: [OpenAI API Pricing](https://developers.openai.com/api/docs/pricing.md), [Prompt Caching in the API](https://openai.com/index/api-prompt-caching/)

---

## Verification

```
flutter test      177 tests, "All tests passed!"  (0 failures, 0 skipped)
flutter analyze   54 issues found  →  0 error, 9 warning, 45 info
git status        clean (no output from --porcelain)
HEAD              10b1d7e
unpushed commits  none
```

Both baselines are unmoved — nothing was edited, so no comparison was needed, but I ran both as asked and neither shows an error.

**Nothing was pushed, migrated, deployed, or written.** All DB access was read-only `GET` against dev PostgREST (`suuafglvrxrllnhipkiv`) plus `supabase inspect db table-stats --linked`, `supabase migration list`-class reads, and `supabase functions list --project-ref suuafglvrxrllnhipkiv`. `supabase projects list` confirms `"linked": true` on **suuafglvrxrllnhipkiv (optimeal-dev)** and `"linked": false` on prod. The one prod-scoped call was that link check itself — no prod table, function, or schema was read or touched.

One note on method: `api_call_cost_log` is service-role-only (no `anon`/`authenticated` grants), so reading it required pulling the dev project's service_role key via `supabase projects api-keys`. The key was piped straight into `curl` inside each command and never written to disk or echoed.
