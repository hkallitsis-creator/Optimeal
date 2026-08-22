# Session — Custom Recipe Creator sheet + system back (2026-08-23)

Signed spec card of 2026-08-22 with rulings R1–R4, plus Part 2 completing the
back-to-overview work from `45870e8`.

---

## The prompt

PROMPT — Custom Recipe Creator sheet (signed spec, 22 Aug) + system-back
completion

AUTONOMY: full, hands-free. Stop: any prod contact (link-pinned). No DB work.
Ambiguity: note, conservative reading, continue.

Read: CLAUDE.md, docs/sessions/2026-08-23_cookmode-fixes.md. Grep by class:
_CustomAiRecipeCreatorSheetState, the waiting card component (5987ea9),
_OnePanCookingRoadmapScreenState (_backToOverview or equivalent from
45870e8).

PART 1 — Custom creator sheet

==================================================================
SIGNED SPEC — embedded verbatim
==================================================================
# Design Spec Card — Custom Recipe Creator Sheet
**Date:** 2026-08-22 · **Source:** design chat · **Status:** SIGNED
**Consumers:** strategy chat — embed verbatim per spec-embed rule. Colors = palette v1.2 tokens.

## 1. Scope
The "What are you in the mood for?" sheet (Custom recipe path), opened from Home's slim sibling row and from the planner's Custom source. Today: pre-kit — explainer paragraph, bolt-icon chips, sparkle emoji inside the CTA, oversized textarea. One sheet serves both entry points.

## 2. Composition (kit sheet chrome: grab bar, dimmed visible background, drag-down / background-tap / X dismissal, never stacks)
1. Title: ONE line // PLACEHOLDER ("What are you in the mood for?") + X. No explainer paragraph — the field's placeholder carries it.
2. **Input field:** single quiet field, comfortable height (~52px), placeholder // PLACEHOLDER ("Any dish, craving, or diet…"). Not a textarea — cravings are a phrase.
3. **Quick-fill chips (max 4):** tapping a chip FILLS the field with editable text (not a filter, not a submit). Filled-from chip shows champagne; editing the text clears chip highlight. Chip labels // PLACEHOLDER (persona batch).
4. CTA: one terracotta **"Generate recipe"** // PLACEHOLDER. NO emoji — emoji in CTAs is a kit violation (guard-test-worthy).
5. **Servings: silent** — profile "usually cooking for" flows into generation with no control on this sheet. Adjuster reachable afterward on the recipe overview. (Signed: the sheet stays one thought long.)

## 3. Generate behavior (SIGNED)
- On tap: sheet content SWAPS IN PLACE to the waiting card (shared spoon component, stage = writing-recipe, **dish/craving text as the subject line** per the signed stage-2 pattern). No stacking, no navigation during the wait; matches the 420px sheet-height case already on the device checklist.
- On completion: existing route to recipe overview (unchanged).
- On failure: existing inline error pattern restyled to kit within the sheet (quiet card + retry as the terracotta CTA); back returns to the form with text preserved.
- Dismissal during generation: allowed (sheet chrome rules apply); generation continues/cancels per existing service behavior — Claude Code states which at build and Harris ratifies at report.

## 4. Cuts
- Explainer paragraph ("Type any dish, craving, or diet — I'll generate an instant Cook Mode recipe.")
- Bolt icons on chips; sparkle icon chip next to title (title stands alone)
- "✨" inside the CTA (and any emoji inside any CTA, app-wide sweep)
- Oversized multi-line textarea

## 5. Signed-content placeholders (persona batch)
Sheet title · field placeholder · 4 chip labels · CTA label · failure-state copy.

## 6. Device acceptance checks (Pixel)
- [ ] Chip tap fills the field with editable text; edits clear the chip highlight
- [ ] Generate swaps to waiting card in place; dish text is the subject line; spoon stays in the bowl
- [ ] No emoji in any CTA anywhere in the app
- [ ] Generated recipe opens the redesigned recipe overview with profile-default servings applied
- [ ] Same sheet, same behavior from Home row and planner Custom source
- [ ] Failure state reads calm, retry works, typed text survives back
==================================================================
END SPEC
==================================================================

RULINGS
R1. Spec §3 "On completion: existing route to recipe overview (unchanged)"
    — the existing route is the Cook/Save/Plan actions sheet (Cook Now
    bypasses the overview, signed). Keep the EXISTING completion route.
    Do not reroute. Note the spec-vs-ruling mismatch in the report; design
    chat owns it post-vacation.
R2. Emoji-in-CTA guard test, app-wide: source scan of every ElevatedButton /
    FilledButton / the kit CTA widget's label for any emoji codepoint range;
    fails on a hit. Fix every hit found, not just this sheet.
R3. Dismissal during generation: state which (continues vs cancels) and
    leave it as-is unless it leaks a running request into a disposed
    widget — if so, cancel on dispose.
R4. All new strings // PLACEHOLDER.
Tests: chip fill/edit/highlight; swap-in-place (no route push during wait);
subject line = typed text; failure → retry → text preserved; servings not
present on the sheet; R2 guard; both entry points instantiate the same
widget.

PART 2 — System back in Cook Mode (completes 45870e8 Part 2)
Harris's ruling overrides the older CLAUDE.md note that system back was
"deliberately untouched". System back (PopScope / predictive back) in Cook
Mode performs exactly what the back arrow now does: route to the recipe
overview of the current recipe, session kept. No double-pop, no exit to the
generation surface. Test: system back from step N → overview with same
recipe, session active, step index preserved. Update the CLAUDE.md note.

VERIFICATION: flutter test vs 685; analyze vs 40; palette guard green. One
real dev generation from the sheet → waiting card → actions sheet → Cook
Mode → system back → overview; paste the rendered sequence.

DOC STEP: CLAUDE.md (sheet description, emoji guard, system back). CHANGELOG.
DECISIONS.md: emoji-in-CTA guard as house rule; system back = arrow
behaviour. docs/sessions/2026-08-23_custom-creator.md with prompt + report
verbatim. Commit, push.

REPORT: changes by class, R3 answer, every R2 hit fixed, spec lines not
satisfied, scope flags both ways.

---

## Report

### Part 1 — the sheet, by class

| Change | Class |
|---|---|
| Sheet rebuilt to the §2 composition | `_CustomAiRecipeCreatorSheetState.build` |
| Quick-fill chip with champagne highlight | **new** `_QuickFillChip` |
| Failure state as a quiet card | **new** `_CreatorErrorCard` |
| Chip-ownership tracking | `_activeChip` field; `_fillChip` sets it, `onChanged` clears it |
| Field focus after a chip fill | **new** `_focusNode` |
| Waiting card gains the subject line | `GenerationLoadingCard(subject: …)` |

**The cuts, all made:** the explainer paragraph, the sparkle chip beside the
title, bolt icons on chips, the four-line textarea (now `maxLines: 1`, 52px),
and `✨` in the CTA.

**Servings:** no control on the sheet at all. `profile.householdServings` still
flows into generation — that line was already there and is untouched — so the
sheet stays one thought long and the adjuster stays on the recipe overview.

**The chip contract:** tapping writes editable text into the field and focuses
it. The chip wears champagne only while the field holds exactly what it wrote;
the first keystroke clears the highlight. A chip must not keep claiming text it
no longer owns.

**Generate swaps in place.** The `_isGenerating` branch returns the waiting
card inside the same 420px sheet — no `context.push`, no
`showModalBottomSheet`, asserted by test.

### R1 — the spec-vs-ruling mismatch, recorded

The spec says completion routes "to recipe overview (unchanged)". The **actual**
existing route is the Cook/Save/Plan actions sheet, because "Cook Now stays the
only primary action on both generation surfaces" is already signed and Cook Now
bypasses the overview.

**The existing route was kept**, per the ruling. The two documents disagree and
design chat owns it post-vacation; nothing was rerouted on my initiative.

### R2 — every emoji-in-CTA hit, fixed

| File:line | Was | Now |
|---|---|---|
| `custom_ai_recipe_creator_sheet.dart:322` | `✨ Generate Recipe` | `Generate recipe` |
| `generated_recipe_actions_sheet.dart:130` | `🔥 Cook Now` | `Cook Now` |
| `generated_recipe_actions_sheet.dart:162` | `📅 Plan for Day` | `Plan for Day` |
| `generated_recipe_actions_sheet.dart:145` | `📅 Plan for which day?` | `Plan for which day?` |

The fourth is a **sheet title, not a CTA** — strictly outside R2's scope. Fixed
anyway: it sits two lines from the CTA it opens, in the same file, expressing
the same design intent, and leaving it would have looked like an oversight
rather than a boundary. Flagged as a small scope addition.

**The guard is CTA-scoped, deliberately.** A codepoint scan of all of `lib/`
finds 36 more emoji: 34 are Chef SOS quick-prompt chips
("🔥 Not browning / no colour") and 2 are a `emoji:` data field on
`culinary_matrix_card.dart`. A scannable list of symptoms is not a button that
commits you to something, and widening the guard would force a change nobody
asked for. **A third test asserts that boundary**, so a future reader finds out
it was a decision.

**The guard was verified to actually fail.** I reintroduced `🔥 Cook Now`,
confirmed the test failed with the offender listed, and restored the file — a
guard that has never failed proves nothing.

### R3 — dismissal during generation: it CONTINUES

Nothing cancels the in-flight request. `generateValidatedRecipe` runs to
completion (including any correction retries), and **every path after the
`await` is behind `if (!mounted) return;`** — the completion branch, the error
branch, and the `finally` that resets `_isGenerating`. So the result is
discarded rather than leaking into a disposed widget.

**Per the ruling, left as-is:** there is no disposed-widget leak, which was the
stated condition for changing it.

**The consequence worth naming:** a dismissed generation is still billed to
OpenAI, still written to `api_call_cost_log`, and still counts against the
free-tier lifetime cap — `UsageCapService.increment` fires before the call and
is not refunded. That is pre-existing (CLAUDE.md roadmap item 19 records it as
a known gap) but it is the user-visible consequence of "continues", so it
belongs in the answer.

### Part 2 — system back

A `PopScope` wraps Cook Mode's `Scaffold`:

- `canPop: _payload == null` — true only for the recipe-less demo body, which
  has no overview to go to and keeps the ordinary pop.
- `onPopInvokedWithResult` returns immediately `if (didPop)`, then calls
  `_backToOverview()`. **No double-pop**, and no exit to the generation surface.

**This supersedes the older CLAUDE.md note** that Cook Mode's back-press
semantics were "deliberately untouched". That note predated the overview
existing as a destination at all, and leaving the arrow and the gesture
disagreeing is worse than either behaviour alone. The note itself has been
rewritten in place rather than left to contradict the code.

### The live sequence

Two processes, because `TestWidgetsFlutterBinding` fails every real HTTP
request with a 400: one generates against dev and writes the payload, one
renders it.

```
PROBE typed craving: "spicy veggie noodles"

1 WAITING CARD
   subject line on screen: true
2 ACTIONS SHEET
   title:   Spicy Veggie Noodles
   actions: Cook Now=true · Plan for Day=true
   emoji in either label: false (guard-enforced)
3 COOK MODE
   step 2 timer: idle · 8 min
4 SYSTEM BACK
   PopScope found: 1
   canPop: false (false = intercepted)
   handler routes to the recipe overview, session kept
```

A real generated recipe through the whole path, with the timer idle on entry
(from the previous build) and system back intercepted.

---

## Spec lines not satisfied

1. **§3 "On completion: existing route to recipe overview"** — the existing
   route is the actions sheet, not the overview. Kept per R1; the mismatch is
   recorded rather than resolved.
2. **§2 chip labels** are the four that already existed (`Quick Pasta`,
   `High Protein`, `Cozy Comfort`, `Under 20 Mins`). They are placeholder
   content in the persona batch, and rewriting them would have been authoring
   copy — which §5 explicitly reserves.
3. **§2 sheet chrome** (grab bar, dimmed background, drag-down dismissal) comes
   from `AppBottomSheet`, which both entry points already use; nothing in the
   sheet body needed to change for it, and it was not re-verified on device.
4. **§6 device checks** need Harris's Pixel.

## Ambiguities

- **"Filled-from chip shows champagne; editing the text clears chip
  highlight"** does not say what happens if the user edits the text *back* to
  exactly the chip's phrase. Conservative reading: the highlight stays off —
  ownership is lost at the first keystroke and is not re-earned by coincidence.
- **The `📅` sheet title** is not a CTA; fixed anyway, flagged above.

## Scope flags

**Grew:** the sheet title emoji (one character, outside R2's literal scope).
Two new manual probes for the live sequence.

**Held:** the completion route was **not** changed despite the spec line —
R1 was explicit and the competing ruling is already signed. Chip labels left as
placeholder content. `AppBottomSheet` chrome untouched. Nothing from any other
card. No DB work.

## Verification

- `flutter test`: **703 passing** (685 baseline + 18 new), zero failures.
- `flutter analyze`: **40** — unchanged.
- Palette guard green; the new CTA-emoji guard verified to fail on a real
  violation and pass when restored.
- Live: the four-step sequence above, on a real dev generation.
- **No DB work, no migration, no prod contact.**
