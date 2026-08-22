# Session — Cook Mode fix round (2026-08-23)

Timer semantics, back-to-overview, type scale, stage-1 allergen leak.
All four are Harris's device rulings or fallout from the profile verification.

---

## The prompt

The full prompt — Parts 1–4 with their rulings and test lists — is reproduced
in this session's chat transcript. Every part is addressed below, and every
spec line not satisfied is listed explicitly.

---

## Report

### Part 1 — timer semantics

**What was there:** the timer started by itself on step entry (`_resumeTimer`
was called from `_startCooking`, `_advanceToNextStep` **and** `_jumpToStep`),
and at zero `_onActiveTimerDone` marked the step complete, showed a
"Step N complete. Moving on…" snackbar, and called `_advanceToNextStep`.

**What it is now:** `StepTimerState { idle, running, paused, done }`, rendered
by `StepTimerPill` (`lib/widgets/step_timer_pill.dart`).

| Class | Change |
|---|---|
| `StepTimerPill`, `StepTimerState` | **new** — the pill and its states |
| `_OnePanCookingRoadmapScreenState` | `_timerState` field; `_enterStep`, `_onTimerPillTapped`, `_adjustTimer`, `_startTicking` **new**; `_resumeTimer` **deleted** |
| `_onActiveTimerDone` | no longer completes, snackbars or advances — beeps twice, buzzes once, sets `done` |
| `_advanceToNextStep`, `_jumpToStep`, `_startCooking` | all route through `_enterStep`, so idle-on-entry is structural |
| `_FocusedStepCard` | takes `timerState` + two callbacks instead of `isPaused`; the `~N min` pill and the separate countdown text **collapsed into the one pill** |
| `_togglePause` | the bottom-bar square now maps onto the same state machine |

**Every step entry goes through `_enterStep`.** That is what makes "no
auto-start, ever" a property of the code rather than a promise — the jump path
was the obvious back door and it is closed by construction.

**Sound:** `SystemSound.play(SystemSoundType.alert)` twice with a 260 ms gap,
plus one `HapticFeedback.mediumImpact()`. No new audio asset. There is no
reliable cross-platform API to query the mute switch, so this relies on the OS
silencing `SystemSound` itself rather than pretending to check — muted
therefore gives haptic + pulse, which is the ruling.

12 tests, including the source-scan guard asserting `_resumeTimer` never
returns and that `_onActiveTimerDone` contains neither `_advanceToNextStep` nor
`_completedSteps`.

### Part 2 — back to the overview

**Which object carries the payload: `ActiveCookSession`.** It holds the full
`CookModeRecipePayload`, `activeStepIndex`, `completedSteps`, `currentPortions`,
`surface`, `isReCook` **and `plannerSlot`** — so a planner-launched cook that
detours through the overview still attributes its slot on completion.
`CookModeLaunchRequest` also carries a payload but is launch-only and knows
nothing about progress, so it cannot express "resume".

`_backToOverview` does `pushReplacement(AppRoutes.recipe, extra: payload)` —
replacement, so a round trip cannot stack Cook Modes. `RecipeDetailsScreen`
loads the active session, matches it **by recipe key** (the payload arriving as
go_router `extra` is a different object from the one the session persisted), and
Start cooking pushes the session rather than a fresh launch request.

**The session is not ended by going back**, and nothing here invents an abandon
path — the existing ones (Finish & Plate, and the Home resume banner's discard)
are untouched.

### Part 3 — type scale

| Where | Change |
|---|---|
| Cook Mode dominant action line | **+3 sp** |
| Cue panel sentence | **+2 sp** |
| Detail prose | **+1 sp** |
| Whisper, meta pills | unchanged, deliberately |
| `AppDesignTokens.body` | **15 → 16**, in the tokens file only |

**No screen needed a local override.** The existing 360 px / wrap-never-clip
guards all still pass at the new size.

**One real overflow, fixed properly rather than by shrinking back:** Cook
Mode's meta row was a `Row`, and once the timer pill gained ± glyphs it
overflowed by **7.6 px** at 360 px × textScale 1.3. It is now a `Wrap` — which
is what the app-wide kit rule said it should have been all along.

### Part 4 — the stage-1 allergen leak

**4a — the block index.** The stage-1 prompt already carried the profile block
and still leaked, so prevention was never the missing half. Measured on the
live run:

```
static block at index :   39
profile block at index: 1330
```

Static-before-variable is intact; the profile block sits after the whole cached
prefix, exactly where stage 2 puts it.

**4b–4d.** `_generateIdeasWithAllergenFilter` runs the existing guard over each
idea's title **and** its ingredient hints, drops anything flagged, and — if
fewer than three survive — runs **exactly one** silent regenerate with the
dropped titles added to the existing exclusion list. Survivors are shown down
to one; zero is the inline error state. Every drop goes to `AllergenFlagLog`,
the same log recipes use.

**Both ideas sets, from the live adversarial run** (profile: vegan, avoid Egg /
Lactose-Dairy / Tree Nuts; chips: eggs, cheese, walnuts, potatoes, spinach):

```
BEFORE the filter — what the model returned
  • Spinach Potato Bake        (potatoes, spinach)
  • Cheesy Spinach Potatoes    (potatoes, cheese, spinach)
  • Potato Walnut Salad        (potatoes, walnuts)

AFTER the filter — what the user is offered
  KEPT
    • Spinach Potato Bake
  DROPPED
    ✕ Cheesy Spinach Potatoes  → {Lactose/Dairy}
    ✕ Potato Walnut Salad      → {Tree Nuts}
```

One survivor, so in the app this trips the <3 branch and buys one silent
regenerate with those two titles excluded.

**A matching gap this exposed, and fixed.** Whole-word matching meant `cheese`
did **not** catch **"Cheesy"** — and a dish title is often the only text an
idea has, so the adjective can be the only signal there is. `cheesy`, `creamy`,
`buttery`, `milky` and `nutty` are now in the synonym list. This is the exact
opposite trade-off from `nutritional yeast`, where whole-word matching is what
*prevents* a false positive; both are in the tests so neither can be undone by
accident.

### The requested live verification

Because `TestWidgetsFlutterBinding` fails every real HTTP request with a 400,
generating and rendering cannot share a process. So one probe generates against
dev and writes the payload out, and a second renders it:

```
RENDER recipe: Vegan Potato and Spinach Bake
RENDER steps:  5 generated
RENDER step 1 timer pills: 0 (expect 0 — mise)
RENDER step 2 timer state: idle (expect idle) · shows 10 min
RENDER after 5s:           idle · still 10 min
```

A real generated recipe, driven into Cook Mode, sitting idle five seconds
later. **Back → overview is covered by tests rather than this probe** — the
route push needs a router, which the probe has no reason to stand up.

---

## Spec lines not satisfied

1. **"Respect the system mute switch"** is delegated to the platform rather
   than checked. There is no reliable cross-platform mute query; `SystemSound`
   is silenced by the OS under the mute switch. Behaviour matches the ruling;
   the mechanism is "rely on", not "detect".
2. **The Part 2 "no duplicate cook-log row" test** is covered structurally —
   `_backToOverview` provably does not call `clearActiveSession` or the
   completion path — rather than by an integration test that completes a cook
   twice. Nothing in the round trip touches the log.
3. **A back-press (system gesture) hook** was not added. Only the back *arrow*
   is rerouted. Adding a `PopScope` would change Cook Mode's system-back
   semantics, which CLAUDE.md records as deliberately untouched, and the spec
   line ("and system back") conflicts with that standing note. Conservative
   reading: arrow only, flagged here.

## Ambiguities

- **What the bottom-bar pause square means** once the timer is idle by default.
  Wired to the same state machine as the pill, so there is one mental model
  rather than two controls that can disagree. Not separately specified.
- **The done pill's label** is a placeholder word rather than a countdown,
  since there is no time left to show.

## Scope flags

**Grew:** `AllergenFlagLog` is new (Part 4d asked for "the same flag log as
recipes", and recipes were only `debugPrint`-ing, so the shared log had to
exist for either to use it). The meta row became a `Wrap`. `_FocusedStepCard`'s
signature changed.

**Held:** no DB work. No new surfaces. Nothing from the custom-creator card.
The home glyph, the abandon paths, and the "Cook Now bypasses the overview"
ruling are all untouched.

## Verification

- `flutter test`: **685 passing** (657 baseline + 28 new), zero failures.
- `flutter analyze`: **40** — unchanged.
- Palette guard green.
- Live: the stage-1 pair above, plus the real-generation Cook Mode render.
- **No DB work, no migration, no prod contact.**
