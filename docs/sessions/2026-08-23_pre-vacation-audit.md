# Session — Pre-vacation audit + system freeze (2026-08-23)

Read-only on app code. Docs-only edits, one audit file, one kickoff file,
one tag. No dev DB writes, no prod contact.

---

## The prompt, verbatim

```
PROMPT — Pre-vacation audit + system freeze (READ-ONLY on app code)

You are a verification session with no memory of how this code was written.
HARD RULE: you may NOT modify any file under lib/, test/, android/, ios/,
supabase/. You may only edit CLAUDE.md, docs/CHANGELOG.md, docs/DECISIONS.md,
docs/sessions/, and create docs/audit_2026-08-23.md and the device-check
kickoff doc. No dev DB writes. No prod contact (link-pinned). You may RUN
tests, analyze, and read-only dev SELECTs.

Read first, fully: CLAUDE.md, docs/DECISIONS.md, docs/CHANGELOG.md, every
file in docs/sessions/ from 2026-08-22 onward, docs/safety_hazard_registry.md,
docs/cooking_times_table.md. Then read the code. Grep by class; filenames are
unreliable and CLAUDE.md drifts — treat the code as truth and the docs as
claims to verify.

PART A — Audit (output: docs/audit_2026-08-23.md)
Findings ranked CRITICAL / HIGH / MEDIUM / LOW, each with class + file,
one-line reproduction or reasoning, and a one-line proposed fix. No fixes
applied. Target the compound paths, not the screens:
A1. Cook session lifecycle: Start cooking → steps → back arrow / system
    back → overview → Start cooking (resume) → Home glyph → Resume banner →
    Finish & Plate → verdict → share → Home. Look for: duplicate sessions,
    duplicate cook-log rows, lost PlannerSlotRef, lost provenance, stale
    scale, setState after dispose, unawaited futures.
A2. Step-list integrity after mise dedup: every consumer of the displayed
    step list (progress bar, whisper, overview sheet panes, jump, cooked-set
    rewrite, SOS context, timer) — any that index the raw generated list.
A3. Generation pipeline ordering: prompt assembly (static-before-variable,
    block indices), parser, compat validator, safety validator, allergen
    guard, retry budgets (state the true worst-case number of model calls
    per recipe and per ideas request), fail-open logging, cost logging
    surfaces. Any path where a retry can skip a validator.
A4. Stage-1 / stage-2 Fridge Clearer: recentDishTitles, allergen drop +
    regenerate, exclusion lists, cache ordering on both.
A5. DataChangeSignal coverage: list every Supabase write in lib/ and whether
    a signal fires; any read that can go stale.
A6. Entitlement: every cap/gate; dev env entitled; release unchanged;
    UpgradeNudgeGate dedupe; paywall unreachable in dev.
A7. Timer state machine (45870e8): any path that starts a timer without a
    tap, advances a step from a timer, or leaks a ticker across steps /
    dispose.
A8. Servings: scale holder, lock on Start cooking, null-servings fallbacks
    on every Cook Mode entry (generation Cook Now, planner Cook, resume),
    whole-piece rounding, ≥100 nearest-5.
A9. Known crash classes: GoRouterState.of in initState; context use after
    await; late fields read before set; non-null assertions on JSON fields
    the model can omit.
A10. Stale-promise strings: grep user-visible strings for checklist, check
    off, shopping list, statistic, saved favorites, language, regenerate,
    science note, dreamflow, OptiMeal/Empyria/InstinKt on any shareable
    surface.
A11. Guard-test inventory: list every exhaustive-list guard test and
    whether its list matches the current code (a guard that is green because
    its list was widened is a finding).
A12. Edge function: ask-chef-harris source in repo vs what the client
    sends; any payload field the function ignores or any response field the
    client assumes.
Also report: flutter test count and any skipped tests with reasons;
flutter analyze breakdown by rule; TODO/FIXME/PLACEHOLDER counts by file.

PART B — Freeze
B1. Rewrite CLAUDE.md from the code as found: surfaces, routes, services,
    data contracts, guard tests, rules (build/install pair, grep by class,
    prod stop-and-report, dev migrations, edge-function manual deploy,
    never flutter install alone, no emoji in CTAs, gold only earned). Keep
    every standing rule; correct every drifted claim; mark unverifiable
    claims as such rather than deleting them.
B2. Reconcile DECISIONS.md and CHANGELOG.md against docs/sessions/ 22–23 Aug:
    every ruling in a session report must have a DECISIONS entry; list any
    missing and add them with the session as source. Contradictions
    resolved by recency and noted.
B3. Regenerate docs/device_check_kickoff_2026-08.md from the existing
    project kickoff structure: every device acceptance item from the specs
    built 22–23 Aug (home cluster, planner, cook mode, fridge clearer,
    waiting card, onboarding, post-cook/share, recipe overview, pre-cook
    mise, profile, custom creator, timer, back-to-overview, type scale),
    plus a KNOWN-UNBUILT list (SOS redesign, diagram batch — pills render
    only for built diagrams, persona placeholders everywhere, pre-cook shell
    around the mise card, custom-creator-to-overview routing mismatch) and
    a KNOWN-OPEN list from DECISIONS. Items Harris has already ruled on are
    excluded.
B4. Run the full suite and analyze once more; then commit everything with
    message "freeze: pre-vacation audit + docs reconcile" and tag
    vacation-2026-08. Push with tags.

REPORT: the audit's CRITICAL and HIGH findings inline in your reply (the
rest in the file), B2's missing-decisions list, CLAUDE.md claims corrected
(count + the five most significant), confirmation of the tag.
```

---

## Report

### Part A — the audit

Full findings: `docs/audit_2026-08-23.md`. Summary:

- **CRITICAL: none.** No unconditional crash, no data corruption, no safety
  guarantee violated. The compat → safety → allergen → inject-last ordering
  is implemented as signed and no retry path can discard H1's injection.
- **HIGH: 2.**
  - **H-1** — `RecipeDetailsScreen` loads its resumable session once in
    `initState` with no `AppDataChanges.cookLog` subscription. A stale
    overview left underneath the stack (see H-2) offers "Start cooking" as a
    fresh launch and **silently overwrites an in-progress session at
    Step 1**, losing progress and (for planner cooks) the `PlannerSlotRef`.
    This is the one violation found of the project's own write-driven-signal
    rule.
  - **H-2** — Cook Mode's `_backToOverview` uses `pushReplacement`, so when
    the overview launched the cook the round trip leaves **two stacked
    overviews of the same recipe**, the lower one stale (which is what arms
    H-1).
- **MEDIUM: 6** (resume-path stepper live-but-ignored; two divergent
  null-servings fallbacks inside Cook Mode; worst case is 7 model calls per
  recipe / 9 per Fridge Clearer intent, undocumented, with observed 502s on
  bursts; allergen retries skip the safety *correction* round; paywall sells
  checkboxes and live timers that no longer exist; `max_tokens: 1200`
  headroom is thin against 803–1,020-token real completions).
- **LOW: 6** (frozen mise bullets on resume; `CFBundleName` still
  `dreamflow`; nudge presentation timing-dependent; dead back-result
  protocol; client cost estimate ignores the cached rate; known dead code).
- Guard-test inventory: **all 14 exhaustive-list guards match the code they
  pin**; none is green because its list was widened illegitimately.
- Numbers: 703 tests passing / 0 failing / 0 skipped (7 live probes excluded
  by design via no `_test.dart` suffix); analyze 40 (0 errors, 7 warnings,
  33 info, breakdown by rule in the audit); TODO/FIXME 2; placeholder lines
  123.

### Part B1 — CLAUDE.md corrections (11)

Approach: targeted correction of every drifted claim in place, keeping every
standing rule, rather than a from-scratch regeneration — the file was
structurally sound and a rewrite would have risked losing nuance the sessions
encode. The five most significant corrections:

1. `kChefCallSurfaces` holds **10** values, not 8 — the `_allergen_retry`
   twins (profile build) were never recorded; the true worst-case call count
   (7 per recipe) is now stated.
2. The 174-term safety name list is **RATIFIED/SIGNED**, not "DRAFT, NOT
   SIGNED" — including duck's H1/H2/H3 whole-muscle exemption.
3. The allergen guard's fail-open question is **RULED** (interim fail-open
   with a loud log), the synonym list is **SIGNED**, and the stage-1 leak
   note is replaced by a pointer to the same-day fix.
4. Roadmap **item 20 is closed in code** — the two-stage redesign removed
   the fabricated fallback (`useGenericFallbacks: false` → error card).
5. The Environment section's "entitlement stays debug-based" paragraph is
   marked **SUPERSEDED** by the 2026-08-23 environment-based fix.

Plus: roadmap item 1's (c)/(d) marked closed; Unit B's "timer is quiet text"
and "pre-cook merge is queued" lines marked superseded; the re-cook ruling
added to the overview entry; the `CFBundleName` gap noted on the launcher
entry; an audit pointer added to Working conventions.

### Part B2 — missing-decisions list (all added to DECISIONS.md)

Seven rulings existed only in session docs / CLAUDE.md:

1. A sales sheet never interrupts an active cook path (23 Aug).
2. No public branding before CH+EU trademark clearance — share card slot
   ships empty, launcher label gated (standing rule, recorded as a decision).
3. Onboarding: both exits complete and land on Home; paywall out of the
   onboarding path; dev builds never show the paywall (22 Aug).
4. The waiting card: no progress bar, truthful cycling lines, gold pearl as
   a signed exception (22 Aug).
5. Cook Mode is one focused step; Finish & Plate only at the end of the
   overview sheet's list (22 Aug).
6. Planner slot attribution, option A — launch-context stamp, targeted
   UPDATE, nothing inferred (22 Aug).
7. Write-driven signals, never navigation callbacks, for cross-screen reads
   (22 Aug).

Contradictions resolved by recency and noted in place: the safety-validator
entry's "name list is DRAFT" and "bread carve-out is UNSIGNED" paragraphs are
marked superseded by the same-day ratification and the recorded H12 ruling.
CHANGELOG needed no reconciliation — every 22–23 Aug session already has an
entry — beyond this session's own entry.

### Part B3

`docs/device_check_kickoff_2026-08.md` created (no prior kickoff doc existed
anywhere in the repo or its history — it was built fresh from the session
docs' signed spec cards and their §6 device checks): fourteen per-surface
checklists, a KNOWN-UNBUILT list (SOS redesign; 3-of-21 diagrams; 123
persona placeholders; the pre-cook shell; the custom-creator routing
mismatch; the planner headcount tier; °F non-conversion) and a KNOWN-OPEN
list drawn from DECISIONS with already-ruled items excluded.

### Part B4 — verification and freeze

- `flutter test`: **703 passing, 0 failing** (run twice this session —
  before the audit and again before the freeze commit; identical).
- `flutter analyze`: **40 issues, 0 errors** (7 warnings, 33 info) — both
  runs identical.
- `git diff --stat` at commit time touches only `CLAUDE.md`,
  `docs/CHANGELOG.md`, `docs/DECISIONS.md`, `docs/audit_2026-08-23.md`,
  `docs/device_check_kickoff_2026-08.md`, and this file — the read-only
  fence held.
- Committed as `freeze: pre-vacation audit + docs reconcile`, tagged
  **`vacation-2026-08`**, pushed with tags.

### Constraint compliance

No file under `lib/`, `test/`, `android/`, `ios/`, `supabase/` modified. No
dev DB write (this session did not even need the read-only SELECTs it was
allowed — every claim was verifiable from code, tests and prior session
records). No prod contact.
