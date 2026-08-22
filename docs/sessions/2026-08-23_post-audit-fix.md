# Session — Post-audit fix: back round trip + servings fallbacks (2026-08-23)

Closes audit findings H-1, H-2, M-1, M-2 (`docs/audit_2026-08-23.md`). The
last code change before the moved `vacation-2026-08` tag.

---

## The prompt, verbatim

```
PROMPT — Post-audit fix: back-from-Cook-Mode round trip (H-1, H-2) +
servings fallbacks (M-1, M-2)

AUTONOMY: full, hands-free. Stop: any prod contact. No DB work. Keep the
diff minimal — this is the last code change before a tagged release build.

Read: docs/audit_2026-08-23.md (findings H-1, H-2, and the two servings
MEDIUMs), docs/sessions/2026-08-23_cookmode-fixes.md and
_custom-creator.md. Grep by class: RecipeDetailsScreen state,
_OnePanCookingRoadmapScreenState._backToOverview, ActiveCookSession,
AppDataChanges.

H-2 FIRST (it arms H-1): back from Cook Mode must not stack a second
overview of the same recipe on top of the one that launched the cook. Rule:
if the route below Cook Mode is already RecipeDetailsScreen for the same
recipe (match on the session's recipe id / payload identity — report which
key), POP back to it; otherwise (Cook Now from a generation surface,
planner Cook button, resume banner) REPLACE Cook Mode with a fresh
overview as 45870e8 does. Never two overviews of one recipe on the stack.

H-1: RecipeDetailsScreen subscribes to AppDataChanges.cookLog (and any
session-write signal, if distinct) and re-reads the resumable session on
every signal, not only in initState — same pattern as Home's
_ResumeSessionBanner. Effect: an overview that is returned to always knows
an in-progress session exists, so "Start cooking" RESUMES at the stored
step and never calls saveActiveSession over a live session. Test the exact
repro: overview → Start cooking → advance two steps → back → back →
Start cooking → lands on step 3 with the same session id and the
PlannerSlotRef intact when launched from the planner.

M-1: on the resume path the servings stepper is live but ignored. Rule:
when a session is in progress, the stepper renders DISABLED showing the
locked N (quantities are locked from Start cooking per the signed spec);
it re-enables only when no session is active for this recipe. Test.

M-2: Cook Mode has two disagreeing null-servings fallbacks. Collapse to ONE
function (in recipe_scale.dart or beside the scale holder — report which)
implementing the signed precedence: launch servings → profile household if
onboarded → recipe basePortions → 1. Every Cook Mode entry calls it. Test
the three fallback cases.

Do NOT touch: validators, allergen guard, prompts, timer, paywall strings,
max_tokens (all logged for post-vacation).

VERIFICATION: flutter test vs 703; analyze vs 40; palette guard green; one
real dev generation through the H-1 repro sequence — paste the rendered
step index and session id before and after.

DOC STEP: CLAUDE.md (overview session subscription; back-routing rule
pop-vs-replace). CHANGELOG. DECISIONS.md: "never two overviews of one
recipe on the stack; overview re-reads session on signal". Update
docs/audit_2026-08-23.md: mark H-1, H-2, M-1, M-2 FIXED with commit hash.
docs/sessions/2026-08-23_post-audit-fix.md with prompt + report verbatim.
Commit, push, then MOVE the tag: git tag -f vacation-2026-08 && git push
--force origin vacation-2026-08. Confirm the tag points at the new commit.

REPORT: changes by class, the identity key used for H-2, the repro
evidence, test count, tag confirmation.
```

---

## Report

### Changes by class

| Change | Class / file |
|---|---|
| Pop-vs-replace back routing (H-2) | `_OnePanCookingRoadmapScreenState._backToOverview` |
| Mounted-overview registry | **new** `OverviewRouteRegistry` (`lib/services/overview_route_registry.dart`) |
| Register/unregister the recipe key | `_RecipeDetailsScreenState.initState` / `dispose` |
| cookLog subscription, re-read on signal (H-1) | `_RecipeDetailsScreenState._cookLogSub` |
| Locked stepper while a session exists (M-1) | `_RecipeDetailsScreenState.build` + `RecipeOverviewBody.enabled` (new param, default true) → `_MetaCard` |
| The one fallback (M-2) | **new** `resolveCookModeServings` in `lib/models/recipe_scale.dart` |
| Resolve once at mount; delete the second chain | `_OnePanCookingRoadmapScreenState.initState` (payload branch), `_buildMiseCard` (its profile-consulting `defaultServingsFor` chain removed) |
| Pre-M-2 resume can't null the resolved value | resume block: `resume.currentPortions ?? _currentPortions` |

**Why a registry rather than router introspection (H-2):** go_router's
imperative match list does not expose a lower route's `extra` in a
version-stable way, and pages below the top of the stack stay mounted — so
"is an overview for this recipe mounted right now" is exactly the question,
answerable by construction from `initState`/`dispose` bookkeeping. Verified
that `GoRouterDelegate.pop` calls `NavigatorState.pop` directly (not
`maybePop`), so the pop branch cannot be intercepted by Cook Mode's own
`PopScope` and loop.

**M-2's function lives in `recipe_scale.dart`**, beside `defaultServingsFor`
(the overview's own default chain, which stays — the overview additionally
clamps to the stepper range). Cook Mode's demo body (no payload, nothing
scalable) is deliberately outside it: `_currentPortions` stays null there and
both consumers read `_basePortions`, which for the demo is the only truth.

### The identity key used for H-2

**`SavedRecipesService.recipeKeyFor(title)`** — the normalized title
(trimmed, lowercased, whitespace-collapsed). There is no server id for
generated recipes and **no session id field on `ActiveCookSession`**; this
key is the same identity the resume matching (`_loadResumableSession`) and
the saved-recipes table already use, so back routing, resume, and saving all
agree on what "the same recipe" means.

### The repro evidence — one real dev generation

`test/manual/custom_creator_probe.dart` (one real billed `ask-chef-harris`
call against dev) → `test/manual/h1_backtrip_probe.dart` (drives the repro on
the real payload; two processes because the test binding fails real HTTP):

```
PROBE recipe: Spicy Veggie Noodles (5 generated steps)
BEFORE back:
  rendered: Step 3 of 6 · Sauté the vegetables
  session identity (recipe key): spicy veggie noodles
  session activeStepIndex: 2 · completed: {0, 1}
AFTER back: overview instances in tree: 1 (H-2: must be 1) · Cook Modes: 0
AFTER resume:
  rendered: Step 3 of 6 · Sauté the vegetables
  session identity (recipe key): spicy veggie noodles (same as before: true)
  session activeStepIndex: 2 · completed: {0, 1}
```

The audit repro's second back-press is now unreachable by construction —
there is no second overview to fall through to. The planner variant
(direct launch with a `PlannerSlotRef`, back → fresh overview via the
replace branch, resume) is covered by widget test:
`session.plannerSlot` survives with `weekStart 2026-08-17 / day 2 / slot 0`.

### One reading taken, flagged

The prompt's repro line says "back → back → Start cooking". After the fix
the first back pops straight to the launcher, so there is no second back to
press — the widget test asserts the stronger property (exactly one overview
in the whole tree, on- or offstage) instead of pressing a button that no
longer has a target.

### Verification

- `flutter test`: **711 passing** (703 baseline + 8 new in
  `test/screens/post_audit_backtrip_test.dart`), zero failures. Every
  pre-existing back/overview/mise test passes unmodified.
- `flutter analyze`: **40** — unchanged. Palette guard green.
- Live dev: the probe pair above (one billed generation).
- **No DB work, no prod contact.** Validators, allergen guard, prompts,
  timer, paywall strings and `max_tokens` untouched, per the brief.
- Audit doc updated: H-1, H-2, M-1, M-2 marked FIXED with the fix commit's
  hash (recorded there in the follow-up docs commit, since a commit cannot
  contain its own hash).
- Tag `vacation-2026-08` moved to the new HEAD and force-pushed; confirmed
  against `origin` in the session's final report.
