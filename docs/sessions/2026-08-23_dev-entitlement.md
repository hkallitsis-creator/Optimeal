# Session — Dev entitlement fix + four follow-ups (2026-08-23)

Unblocks two weeks of device-only testing on a release-mode APK pointed at dev.

---

## The prompt, verbatim

```
PROMPT — Dev entitlement fix + four small follow-ups from the polish round

AUTONOMY: full, hands-free. Stop: any prod contact (link-pinned). No dev DB
work expected; if a migration seems needed, stop and report. Ambiguity: note,
conservative reading, continue.

Read: CLAUDE.md, docs/sessions/2026-08-23_design-qa-polish.md. Grep by class.

CONTEXT: Harris's Pixel runs a RELEASE-mode APK pointed at dev (the
build/install pair in CLAUDE.md). EntitlementService.isPro() bypasses only
under kDebugMode, so release-dev builds hit usage caps with no unlock path
(the dev paywall route redirect removed the mock-purchase path). Harris is
about to start two weeks of device-only testing; this must be airtight.

PART 1 — Dev entitlement
1a. Entitlement is a property of the ENVIRONMENT, not the build mode:
    isPro() (and any sibling gate — usage caps, daily/lifetime generation
    counts, upgrade-nudge eligibility) returns entitled whenever the app's
    environment is dev (the OPTIMEAL_ENV define / AppEnvironment, whatever
    the live name is — grep, don't trust CLAUDE.md). kDebugMode bypass may
    stay as an additional OR, never as the only path. Release env: UNCHANGED.
1b. Tester bypass is NOT in scope (deferred to the RevenueCat build per
    DECISIONS.md). Do not add an account-level flag.
1c. Every cap/gate site by class in the report. Guard test in house style:
    an exhaustive list of entitlement-gated call sites; a new gate not on the
    list fails the test. Test matrix: dev+release mode → entitled; dev+debug
    → entitled; release env+release mode → NOT entitled (caps live).
1d. UpgradeNudgeGate (Home, from polish round): confirm it presents at most
    ONCE per triggering cook, not once per Home build/rebuild; if it doesn't
    already dedupe, add a trigger token (e.g. the cook-log row id) and a test.
    Entitled users must never see it (ties to 1a).

PART 2 — Launcher label (AndroidManifest.xml:8 currently "dreamflow")
    Make android:label flavour/env-resolved. Dev env → "OptiMeal dev".
    Release → keep a string resource marked // GATED: trademark clearance;
    set it to "OptiMeal dev" as well for now so no build can ever read
    "dreamflow". iOS: CFBundleDisplayName same treatment if trivially
    reachable; otherwise report and leave. Harris is rebuilding after this
    prompt; the label must change on his phone.

PART 3 — Fridge Clearer stage 1 freshness (defect from polish Part 4)
    Stage 1 omits recentDishTitles while stage 2 passes it (fridge_clearer
    path, ~:385 — grep). Pass the same recent-titles list to stage 1 so
    back → Let's Cook produces three genuinely new ideas. Keep it static-
    before-variable in prompt assembly (cache ordering rule). One real dev
    pair run: report the two sets; acceptance = 0 repeats across the pair.
    Test: stage-1 payload contains the recent-titles block when titles exist.

PART 4 — Duck H3 extension (ruling, Harris 23 Aug, extends the polish
    addendum)
    Duck whole-muscle (breast, magret, leg, thigh, whole duck, confit) is
    exempt from H3's temperature floor as well as H1/H2: doneness on duck is
    technique, not hazard. Duck mince unchanged. Test: "duck breast, core
    57°C" → no H3 flag; "chicken breast, core 57°C" → H3 flag unchanged.
    DECISIONS.md: amend the 23 Aug duck entry to read H1/H2/H3.

VERIFICATION
- flutter test green vs 528; analyze vs 44; palette guard green.
- Real dev run for Part 3.
- State in the report, explicitly: "A release-mode APK built from this commit
  against dev will be entitled, show no caps, and present no upgrade sheet."
  If you cannot state that, say why.

DOC STEP
- CLAUDE.md: entitlement rule (env-based), launcher label rule, the
  build/install pair restated. CHANGELOG. DECISIONS.md: entitlement = env
  property; duck H3. docs/sessions/2026-08-23_dev-entitlement.md with prompt
  + report verbatim. Commit, push.

REPORT: gate sites by class, the 1c test matrix results, Part 3 pair, any
spec line not satisfied, scope flags both ways.
```

---

## Report

### The required statement

> **A release-mode APK built from this commit against dev will be entitled,
> show no caps, and present no upgrade sheet.**

I can state that. The reasoning, so it is checkable rather than trusted:

- `isPro()` now short-circuits on `kIsDevEnvironment || kDebugMode`.
  `kIsDevEnvironment` is a genuine compile-time constant derived from
  `String.fromEnvironment('OPTIMEAL_ENV', defaultValue: 'dev')`, so a build
  with **no** `--dart-define` — which is what `flutter build apk --release`
  produces — resolves to dev and the branch is `true`.
- All three gates reach that one function *before* they read a counter, and
  each is written `if (!isPro) { ...cap check... }`. Verified by reading each,
  and pinned by a census test that fails if a fourth appears.
- The post-cook nudge checks `isPro()` and returns before presenting.

One honest caveat, which does not change the statement: usage counters still
**increment** in dev (`UsageCapService.increment` on both generation paths).
They gate nothing there, because the gate is skipped entirely. Left deliberately
— see the scope notes.

### 1a — the change

`EntitlementService.isPro()` previously read `if (kDebugMode) return true;`.
`kDebugMode` is `false` in a release build, so the one configuration device
testing actually uses — release mode, dev environment — bypassed nothing, hit
the caps (3 Fridge Clearer generations/week, 2 lifetime custom recipes), and
had no unlock route, because `lib/nav.dart:161` already redirects
`AppRoutes.paywall` → Home under `kIsDevEnvironment`, removing the
mock-purchase path.

The decision is now a pure, parameterised function:

```dart
static bool entitlementBypassFor({
  required bool isDevEnvironment,
  required bool isDebugMode,
}) => isDevEnvironment || isDebugMode;
```

`kDebugMode` survives as an additional OR, never as the only path — a debug
build pointed at prod is still a developer's machine. Release environment +
release mode is unchanged: both constants are false, the branch folds away, and
the RevenueCat/mock lookup below runs exactly as before.

The function is parameterised because both inputs are **compile-time
constants**: a test process cannot vary them, so without this seam the matrix
below could not be asserted at all — only the single cell the test binary
happens to be compiled in.

### 1c — gate sites by class

| Class | File | Gate |
|---|---|---|
| `_FridgeClearerScreenState` | `lib/screens/fridge_clearer_screen.dart:251` | Weekly Fridge Clearer generation cap (`kFridgeClearerFreeWeeklyLimit` = 3) |
| `_CustomAiRecipeCreatorSheetState` | `lib/widgets/custom_ai_recipe_creator_sheet.dart:107` | Lifetime free-uses cap (`kCustomAiRecipeCreatorFreeLifetimeUses`) |
| `_HomeDashboardScreenState` | `lib/screens/home_dashboard_screen.dart:199` | Post-cook upgrade nudge eligibility |

A fourth entitlement-adjacent site exists and is **not** an `isPro()` caller:
the route-level redirect on `AppRoutes.paywall` in `lib/nav.dart:161`, which is
already `kIsDevEnvironment`-gated and therefore already environment-based. It
is noted here rather than changed.

**The census test** (`test/services/entitlement_gate_test.dart`) walks every
`.dart` file under `lib/`, strips comments so a doc reference is not read as a
call, and asserts the set of files containing `.isPro()` equals the list above.
A new gate fails it until someone adds it deliberately. A second test does the
same for `UsageCapService.instance`, asserting Home is *not* among them — Home
reads entitlement but never counts usage.

### 1c — test matrix results

| Environment | Build mode | Expected | Result |
|---|---|---|---|
| dev | release | entitled | **PASS** — the configuration on Harris's phone; this was the broken cell |
| dev | debug | entitled | **PASS** |
| release | release | NOT entitled, caps live | **PASS** |
| release | debug | entitled | **PASS** — developer machine, the surviving OR |

### 1d — the nudge dedupes per cook

It already deduped per *scheduling* (`consumePendingPostCookNudge` was
one-shot), so a Home rebuild storm could not double-present. What it did not
have was a notion of *which cook* owed the nudge: a completion sequence that
ran twice — a resumed session, a retried write — would schedule twice and owe
two sheets.

`schedulePostCookNudge(String token)` now takes a token minted **once per Cook
Mode session** in `initState` and never regenerated. Re-scheduling an
already-handled token is a no-op. Three tests cover it, including a 50-iteration
rebuild storm that yields exactly one presentation.

I used a session-scoped token rather than the suggested cook-log row id: the
cook log row is written asynchronously partway through the same completion
sequence, so its id is not reliably available at the moment the nudge is
scheduled, and a null token would silently disable the dedupe. The session
token is available at `initState` and is exactly as unique per cook.

Entitled users never see it — the `isPro()` check sits in Home's presenter and
returns before `UpgradePromptSheet.show`.

### Part 2 — launcher label

`AndroidManifest.xml:8` read `android:label="dreamflow"` and
`ios/Runner/Info.plist` read `<string>Dreamflow</string>`. Both are Dreamflow
export leftovers, and both are the app's **public name on the launcher**.

Android is now `android:label="${optimealAppLabel}"`, resolved in
`android/app/build.gradle`'s `defaultConfig`:

```gradle
def optimealEnv = project.findProperty('OPTIMEAL_ENV') ?: 'dev'
manifestPlaceholders += [
    optimealAppLabel: optimealEnv == 'prod' ? 'OptiMeal dev' : 'OptiMeal dev'
]
```

Both branches read **"OptiMeal dev"** on purpose — GATED on trademark
clearance, marked as such in the source. Harris's `flutter build apk --release`
passes no Gradle property, defaults to dev, and gets "OptiMeal dev". **The
label will change on his phone.**

**A seam worth knowing, and the one place I could not fully satisfy the spec:**
a `--dart-define` reaches the Dart compiler and **never reaches Gradle**, so
the app's own `OPTIMEAL_ENV` cannot drive the manifest. A prod build that wants
a prod label must pass `-POPTIMEAL_ENV=prod` *as well as* the dart-define. That
is a real duplication. It is currently unobservable because both strings are
identical, and it should be revisited when the trademark gate opens — at which
point the two values diverge and the duplication starts to matter.

iOS is a plain string with a GATED comment, **not** env-resolved: that needs an
xcconfig or scheme split, which the spec said to skip if not trivially
reachable. Reported and left.

### Part 3 — stage-1 freshness

`recentDishTitles` now flows to stage 1, assembled the same way stage 2 does
it (`RecentGenerationsService` + persisted cook history). The screen also
**records the three ideas it just showed**, so pressing back and asking again
sees them — without that, the in-session case the escape path exists for would
still have had nothing to exclude.

Ordering is unaffected: `ChefService` writes recent titles into the **variable**
half, after the entire static prefix, so the cached prefix is untouched. A test
asserts the recent-titles block appears *after* the static block.

**Real dev pair, after the fix** — identical chips
(`courgette, chicken thighs, spring onion, feta`, 2 portions, 30 min):

| RUN 1 | RUN 2 (back → Let's Cook) |
|---|---|
| Chicken and Feta Stuffed Courgettes | Grilled Chicken with Feta Salad |
| Spring Onion and Feta Chicken Skillet | Courgette and Feta Frittata |
| Mediterranean Chicken and Veggie Bake | Chicken and Courgette Stir-Fry |

**Overlap 0 of 3.** Acceptance met.

The number that shows this is wiring rather than luck: RUN 1's prompt is
**2,800** tokens, RUN 2's is **2,920** — the +120 is the exclusion block
landing. The formats also separate cleanly (stuffed / skillet / bake →
salad / frittata / stir-fry), which is the format-level exclusion working, not
just title matching.

**A measurement caveat I should flag.** Before the fix, one pair returned 1 of 3
repeats and a second pair returned 0 of 3 — the pre-fix baseline is noisy, so a
single post-fix pair at 0 of 3 is consistent with the fix working but is not on
its own proof. The token delta is the stronger evidence, and the unit test
pins the mechanism deterministically.

### Part 4 — duck H3

`donenessExempt` now also suppresses the whole-muscle protein class, so an
exempt name resolves to no class at all and H3 has nothing to compare a stated
temperature against.

- `duck breast` + "internal temperature reaches 57°C" → **no H3 flag**
- `chicken breast` + the same sentence → **H3 flag, naming 74** (unchanged)
- `proteinClassesIn('duck breast')` → empty; `'chicken breast'` → poultry

**Duck mince is 74 °C, not 71** — and that is correct rather than an oversight.
It is poultry *and* comminuted, so the already-signed poultry-mince tie-break
governs, exactly as it does for chicken mince. The exemption is for whole
muscle; mincing is precisely the thing that changes the hazard. My first test
asserted 71 and was wrong; the code was right.

`docs/DECISIONS.md`'s 23 Aug duck entry now reads H1/H2/H3, with the extension
recorded as its own dated decision above it.

---

## Verification

- `flutter test`: **543 passing** (528 baseline + 15 new). Zero failures.
- `flutter analyze`: **44** — unchanged from baseline.
- Palette guard: green (inside the suite).
- Real dev run: the stage-1 pair above, against `suuafglvrxrllnhipkiv`.
- **No dev DB work, no migration, no edge-function change, no prod contact.**

One test from the polish round needed updating for the new
`schedulePostCookNudge(token)` signature — mechanical, still green.

---

## Scope flags

**Grew:**
- `android/app/build.gradle` gained a `manifestPlaceholders` line and
  `ios/Runner/Info.plist` changed — the first native-config edits in a while,
  unavoidable for Part 2.
- The Fridge Clearer now records its own ideas into `RecentGenerationsService`.
  Strictly beyond "pass the same list", but without it the in-session
  back-and-retry case — the exact case Part 3 exists for — has nothing to
  exclude, so the fix would have been inert where it matters most.

**Shrank / not done:**
- **No tester or account-level bypass flag** (1b said not to).
- **Usage counters still increment in dev.** The caps gate nothing, so this is
  invisible to Harris; suppressing it would put a second environment branch in
  a second place for no behavioural gain, and it keeps dev counter data real.
  Flagged rather than silently changed.
- **iOS label is not env-resolved** — reported per the spec's own escape clause.
- **The Gradle-property duplication** described in Part 2 is a real wart. It
  cannot be removed without either a Flutter-level flavour setup or reading the
  dart-define from Gradle, neither of which is a small change, and both of
  which are better done when the trademark gate makes the two labels differ.
