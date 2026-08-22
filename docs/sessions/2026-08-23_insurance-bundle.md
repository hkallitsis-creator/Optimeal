# Session — Pre-vacation insurance bundle (2026-08-23)

Token headroom (M-6, client half), gateway retry (M-3), full validator chain
on every regenerate (M-4). The last code change before the moved
`vacation-2026-08` tag.

---

## The prompt, verbatim

```
PROMPT — Pre-vacation insurance bundle: token headroom, 502 retry, full
validator chain on every regenerate (audit MEDIUMs)

AUTONOMY: full, hands-free. Stop: any prod contact. No DB work. Minimal
diff — last code change before the release build. Nothing else from the
audit.

Read: docs/audit_2026-08-23.md (the max_tokens, 502-burst, and
allergen-retry-skips-safety findings), docs/sessions/2026-08-23_post-audit-
fix.md. Grep by class: the ask-chef-harris client (chef_service), the
validated generation orchestrator (validated_recipe_generation), the
allergen guard retry path from d933fbb.

PART 1 — Token headroom
Raise max_tokens on recipe generation from 1200 to 2000 (ideas stage
unchanged unless it is also tight — report its value). Read finish_reason
from the response; if "length", log it to the flag log with the surface and
treat the result as a parse failure (it will be) so the existing retry
fires rather than a garbled recipe reaching the parser. Test: a stubbed
"length" response → logged + retried; a normal response → no change in
behaviour. Confirm the edge function passes max_tokens through rather than
clamping it (read lib/supabase/functions/ask-chef-harris/index.ts; if it
clamps, report the clamp and STOP on that part — no edge deploys in this
session).

PART 2 — 502/503 retry
In the ask-chef-harris client: on HTTP 502, 503, or 504, ONE retry after
1500 ms, same payload, then surface the existing error. Never retry 4xx.
Retries are idempotent here (no write happens before the model call
returns — verify, and if UsageCapService.increment or the cost log fires
before the call, ensure the retry does not double-count). Test: 502 then
200 → success, one increment; 502 then 502 → error, one increment; 400 →
no retry.

PART 3 — Full validator chain on every regenerate
Rule: any regeneration — compat correction, safety correction, allergen
drop — produces output that re-enters the chain from the top (compat →
safety → allergen → deterministic H1 injection last). Retry budgets stay
per-validator (2 each); a regenerate triggered by one validator does not
refund the others. State the new true worst-case call count per recipe
and per Fridge Clearer intent in the report and in CLAUDE.md. Test: an
allergen-triggered regenerate whose new output carries an H2 violation gets
the H2 correction round, not just a log line; H1 injection present on the
final served output in every branch.

Do NOT touch: timer, routing, servings, profile, paywall strings,
max_tokens (all logged for post-vacation).

VERIFICATION: flutter test vs the post-audit-fix count; analyze vs 40;
palette guard green. One real dev generation of a deliberately long request
("8-step one-pan chicken and vegetable traybake with a pan sauce") —
report finish_reason and token usage.

DOC STEP: CLAUDE.md (max_tokens, retry policy, chain re-entry rule, worst-
case counts). CHANGELOG. DECISIONS.md: "every regenerate re-enters the full
chain". Mark the three audit findings FIXED with commit hash.
docs/sessions/2026-08-23_insurance-bundle.md with prompt + report verbatim.
Commit, push, move the tag: git tag -f vacation-2026-08 && git push --force
origin vacation-2026-08. Confirm.

REPORT: changes by class, whether the edge function clamps max_tokens,
worst-case counts, real-run finish_reason, test count, tag confirmation.
```

---

## Report

### The edge function CLAMPS — Part 1's server half is STOPPED

`supabase/functions/ask-chef-harris/index.ts` (the checked-in source of the
deployed function; the prompt's `lib/supabase/...` path does not exist)
**hardcodes `max_tokens: 1200`** in the OpenAI payload, does not destructure
any client-sent value from the request body, and its response
(`{content, usage, model}`) **does not include `finish_reason`**. That is an
effective clamp — worse, a hardcode — so per the brief the raise is reported
and stopped on; **no edge deploy was made**.

What shipped instead is the client half, dormant-but-ready:

- Recipe surfaces send `maxTokens: kRecipeGenerationMaxTokens` (2000). The
  function ignores unknown body fields, so this is inert and harmless today
  and takes effect the moment the function is redeployed.
- `askChefHarris` reads `finish_reason` when the response carries one; on
  `"length"` it records surface + sizes to the new `GenerationTruncationLog`
  (own 50-entry ring buffer, same pattern as the other three logs) and lets
  the content fall through — truncated JSON fails the parser, which is
  exactly the parse-failure path the orchestrator already handles, so
  nothing garbled reaches Cook Mode. A normal response is byte-for-byte
  unchanged behaviour.
- **The ideas stage stays at the deployed default deliberately**: its
  completions measure ~155 tokens (2026-08-22 measurement) against the
  1,200 cap — not tight.

**The handed-over diff** (deploy post-vacation with
`supabase functions deploy ask-chef-harris --project-ref suuafglvrxrllnhipkiv --use-api`,
then verify via `supabase functions list`):

```ts
// 1. destructure the client's value:
const { systemPrompt, userMessage, temperature, forceJsonObject, model,
        surface, maxTokens } = await req.json();

// 2. replace `max_tokens: 1200` with a bounded pass-through:
max_tokens: typeof maxTokens === 'number' && maxTokens >= 256 && maxTokens <= 4000
    ? Math.floor(maxTokens)
    : 1200,

// 3. surface finish_reason to the client:
const finishReason = data?.choices?.[0]?.finish_reason ?? null;
// ...and add it to the success response:
return new Response(JSON.stringify({ content, usage, model: resolvedModel,
                                     finish_reason: finishReason }), ...
```

### Changes by class

| Change | Class / file |
|---|---|
| Gateway retry helper (one retry, 1500 ms, 502/503/504 only) | `ChefService.invokeWithGatewayRetry` + `kGatewayRetryDelay` |
| Injectable transport seam (tests) | `ChefTransport` typedef; `ChefService({transport})` |
| `maxTokens` param + payload field; `finish_reason` handling | `ChefService.askChefHarris` |
| Truncation ring buffer | **new** `GenerationTruncationLog` (`lib/services/generation_truncation_log.dart`) |
| The 2000 constant + wiring | `kRecipeGenerationMaxTokens` (`chef_service.dart`); `_commitToIdea` (Fridge stage 2) and `_CustomAiRecipeCreatorSheetState._generate` pass it |
| Chain re-entry (M-4) | `generateValidatedRecipe` rewritten: one loop, accepted regenerates re-enter from the top; per-layer `closed` flags preserve the old "a failed retry ends that layer" semantics |
| Fake override signature | `_FakeChefService` in `test/screens/fridge_clearer_redesign_test.dart` gained `maxTokens` |

### Idempotency of the retry — verified

Nothing is written before the model call returns. `UsageCapService.increment`
fires **once per user intent in the screens**, before the whole generation
(not per call), and `api_call_cost_log` is written **server-side only after a
successful OpenAI response** — a 502 by definition did not have one. A source
pin in the new test file asserts `chef_service.dart` contains no executable
reference to either, so the "one increment" property cannot silently move
into the retried path later.

### Worst-case counts (stated here and in CLAUDE.md)

- **Billed model calls: unchanged — 7 per recipe** (1 first + 2 compat + 2
  safety + 2 allergen), **9 per Fridge Clearer intent** (+ stage 1 and its
  one silent allergen regenerate). Chain re-entry reorders who judges what;
  it adds no budget.
- **HTTP requests: up to double those** (14 / 18) — each call may take one
  gateway retry. A 502'd attempt was not billed.
- One deliberate semantic kept from the old loops: a correction round that
  fails outright (no reply / unparseable) **closes that layer** for the
  generation rather than re-firing its remaining budget at a model that just
  hard-failed; a parsed-but-worse round only spends the point.

### The real dev run — the long request

`test/manual/long_recipe_probe.dart`, live against dev:

```
PROBE long request: "8-step one-pan chicken and vegetable traybake with a pan sauce"
PROBE usage: prompt=7700 cached=3968 completion=1200
PROBE finish_reason in response: ABSENT (deployed function does not return it yet)
PROBE completion vs deployed cap: 1200 / 1200  ← AT THE CAP: truncated
PROBE content chars: 3884 · JSON closes cleanly: false
```

This is audit M-6 caught in the act: the deployed cap truncated a real
recipe mid-JSON, and the deployed response carries no `finish_reason` to say
so. (In the shipping app this lands as the existing quiet "try again" — the
parse-failure path; the probe result is also why the raise genuinely needs
the redeploy.) The probe sends `maxTokens` too, so re-running it after the
redeploy verifies the fix with no edits.

### Tests

**724 passing** (711 baseline + 13 new in
`test/services/insurance_bundle_test.dart`): the maxTokens wiring pins (2000
on both recipe surfaces, absent from stage 1); "length" → logged with
surface + content falls through to the parser's failure path; normal
response unchanged; 502→200 (two calls, one 1500 ms wait), 502→502 (error,
two calls), 503/504 retried, 400 never retried, retry through the full
`askChefHarris` path; the no-caps-in-transport source pin; the M-4 chain
test (`[first, allergen, safety]` — a fresh H2 on allergen-corrected output
gets its correction round); H1 injection on allergen-branch output; and
budgets-never-refunded. `flutter analyze`: **40**, unchanged; palette guard
green. Three pre-existing orchestrator tests initially failed against the
naive re-entry loop and drove the `closed`-flag semantics above — they now
pass unmodified.

### Constraint compliance

No prod contact, no DB work, no edge deploy. Timer, routing, servings,
profile, paywall strings and prompt wording untouched. Audit M-3 and M-4
marked FIXED with the fix commit's hash; M-6 marked client-half-fixed with
the edge redeploy explicitly owed (the honest reading — the brief's own STOP
clause fired).
