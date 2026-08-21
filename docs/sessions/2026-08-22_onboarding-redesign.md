# Session — Onboarding redesign (2026-08-22)

## Prompt (verbatim)

```
AUTONOMY: Full file/test/git permission. No confirmation questions.
STOP CONDITIONS: Prod Supabase = stop-and-report always. Dev
(suuafglvrxrllnhipkiv) read-only plus app-level test writes through
existing services; no migrations, no deploys. Spec ambiguity = note
and continue, never guess.

BUILD — ONBOARDING REDESIGN. Signed spec embedded verbatim below —
WHAT and WHERE; you own HOW. Treat §1 as correctness fixes, not
restyle: every new user currently sees stale promises.

━━━ SPEC (verbatim, design_spec_onboarding_2026-08-21.md) ━━━
Scope + correctness findings: Onboarding PageView redesign. Current
build contains STALE PROMISES shown to every new user: Slide 3
advertises "steps, checkboxes, and timing" — checkboxes are dead
(pre-cook merge, ticks killed). Slide 4 advertises "Weekly Planner +
Shopping List stay in sync. Two-way." — shopping list was cut
entirely. Skip routes to the paywall (_skipToPaywall) while pricing
is deliberately open (15 CHF is placeholder). Slide 1 is
invented-persona-era text ("not a chatbot pretending to know knife
skills").
Location: OnboardingScreen class (currently in the file named
fridge_clearer_screen.dart — grep by class, filenames unreliable).
Completion = SharedPreferences hasSeenOnboarding + profile onboarded
+ Supabase upsert (mechanics unchanged).

Structure (KEPT — it's sound): PageView of 4 slides · one ivory card
per slide · dots indicator · one terracotta CTA (Next → "Let's cook"
on slide 4) · Skip top-right (hidden on slide 4). Palette v1.2
tokens throughout.

Routing (SIGNED): Skip → Home. Finish → Home. The paywall exits the
onboarding path entirely until pricing is real. (Paywall screen
itself untouched — only this routing.) Completion flag mechanics
unchanged.

Slide content (SIGNED direction; final microcopy = persona batch):
1. Chef Harris intro — spoon-and-bowl illustration (diagram-style:
   black outlines, terracotta bowl, wood-tan spoon — matches loading
   card). Harris-edited draft stands as current direction: "Hi, I'm
   Chef Harris. A real cooking teacher — years of real students,
   real pans, real mistakes fixed. I'll teach you the way I teach in
   person." (No hardcoded year-count.) Lead with what he IS, no
   defensive "not a chatbot" framing.
2. Fridge Clearer promise — fridge glyph. "The best dinner is
   already in your fridge." + rescue counting. CHF waste statistic
   OUT unless verified and signed.
3. Cook Mode truth — mini sage cue-panel as the visual (pre-teaches
   green = teaching). One step at a time + sensory cues; "cook by
   your senses, not the clock."
4. Planner + My recipes — mini week-strip visual previewing real day
   states (✓ / today·Cook / dashed +). "Plan your week. Keep your
   winners." Bookmark-everywhere mention.

Dev affordance: add a dev-only "Replay onboarding" row to the
profile screen (resets local flag; dev builds only).

Placeholders (mark // PLACEHOLDER): slide 1 final verbatim rides
with the persona batch; slides 2–4 headlines + subtexts (draft
illustrating direction); CTA labels.
━━━ END SPEC ━━━

IMPLEMENTATION NOTES:
- Slide 1 illustration and slide 3 mini cue-panel and slide 4 mini
  week-strip are small in-slide visuals. Build them as compact
  widgets reusing real components/tokens where cheap (_CuePanel
  styling, planner day-state looks), simplified static previews
  where reuse is heavy — they must read as previews, not live UI.
  Diagram-style illustration follows the signed diagram family
  (black outlines, terracotta fills, tokens).
- Routing: verify no OTHER path routes into /paywall from the
  onboarding flow after the change; grep and report every remaining
  route to PaywallScreen app-wide (dev builds already skip it via
  the 30243cf redirect — confirm the two mechanisms compose).
- Completion mechanics untouched, but add a test pinning them
  (hasSeenOnboarding + profile upsert still fire on both Skip and
  Finish — Skip must ALSO complete, or users see onboarding twice).

TESTS: keep all 319 green. Add: four slides render with dots + CTA
progression + Skip hidden on slide 4; Skip → Home; Finish → Home;
completion fires on both; no route to paywall from onboarding;
replay row resets flag, dev-only; no "checkbox"/"shopping list"
strings anywhere in onboarding content.

VERIFICATION:
- flutter test all passing, exact count; flutter analyze ≤45, exact
  count; palette guard green
- git status clean, committed and pushed

DOC STEP (permanent rule): commit this prompt verbatim + full report
to docs/sessions/2026-08-22_onboarding-redesign.md. Update
docs/CHANGELOG.md.

Report verbatim: slide implementation notes, the app-wide paywall
route census, files touched, test/analyze counts, push confirmation,
ambiguities.
```

---

## The correctness finding the spec did not have: Skip never worked

The spec lists Skip's *destination* as wrong. Reading the routing showed
something worse: **Skip did not skip.**

`_skipToPaywall` set `hasSeenOnboarding` and called `context.go('/paywall')`.
It never set `profile.onboarded`. The router's redirect is:

```dart
if (!profile.isOnboarded && !isOnboarding) return AppRoutes.onboarding;
```

So the navigation to `/paywall` was immediately bounced back to `/onboarding`.
A user who pressed Skip stayed exactly where they were, with no explanation.
The two flags look interchangeable and are not: `hasSeenOnboarding` is a local
convenience the router never reads, and `profile.onboarded` is the one that
actually gates.

Skip and Finish now share **one** `_completeOnboarding()` performing all three
writes in a fixed order — local flag, profile flag, `user_profiles` upsert. The
order is load-bearing twice over: the profile flag must be set or the redirect
traps the user, and it must be set *before* the Supabase write because the
controller's `notifyListeners()` is the router's `refreshListenable`, so
flipping it first means navigation never waits on the network. The upsert stays
best-effort and never blocks completion, exactly as before.

`OnboardingScreen.resetForReplay` is the deliberate inverse — it clears both
flags, for the same reason.

## Slide implementation notes

`lib/widgets/onboarding_visuals.dart` holds all four visuals, out of the screen
file, because two of them are previews of real UI and deserve to be findable
when that UI changes.

**Slides 1–2 are line illustrations** in the signed diagram family, following
`technique_diagrams.dart`'s conventions exactly: `CustomPainter`, flat, black
outlines (`textCharcoal`), terracotta fills, no gradients, no assets. The
spoon-and-bowl has a rounded half-ellipse bowl in `ctaTerracotta`, three steam
strokes, and an angled spoon; the fridge has a split body, two handles, and one
piece of produce showing through the lower door — the thing worth rescuing.

**Slides 3–4 are previews of real UI, and are static on purpose.** The live
`_CuePanel` and the planner's day rows carry state, gestures and service
dependencies a slide has no business owning, and a preview that responded to
taps would promise an interaction the slide cannot deliver. They reuse the real
**tokens**, which is the part that matters: the sage a user learns on slide 3
is `sageTeachingPanel`, the exact fill they will meet mid-cook, and the mini
week strip uses `goldEarnedOnLight` for the counted ✓, `champagneTint` for
today, and the planner's own dashed outline for an empty day. The point is
pre-teaching the colour vocabulary, so green already reads as "Chef Harris is
teaching me" the first time it appears over a pan.

**Slide content.** All headlines and subtexts carry `// PLACEHOLDER`, per the
spec — slide 1's verbatim rides with the persona batch and 2–4 are drafts
illustrating direction. The CHF statistic is out, the year count is out, and
slide 1 leads with what Chef Harris is. The dot count and last-slide checks all
read `OnboardingScreen.slideCount`, so adding a fifth slide cannot leave one of
them behind.

The slide card gained a `SingleChildScrollView`: the visuals are taller than
the icon tiles they replaced, and at large text scales slide 1 would otherwise
overflow.

## App-wide paywall route census

`grep -rn "PaywallScreen\|AppRoutes.paywall\|'/paywall'" lib/` — every hit,
classified:

| site | what it is | verdict |
|---|---|---|
| `lib/nav.dart:150,163,200` | the route definition, its builder, and the path constant | the route itself |
| `lib/screens/paywall_screen.dart` | the screen | untouched, per spec |
| `lib/widgets/upgrade_prompt_sheet.dart:75` | `context.push(AppRoutes.paywall)` | **the only remaining entry point** — a mid-app upsell, not onboarding |
| `lib/services/entitlement_service.dart:18,77` | doc comments naming the screen | not routes |
| ~~`lib/screens/onboarding_screen.dart:82`~~ | `context.go('/paywall')` | **removed this session** |

So: **exactly one route into the paywall remains app-wide**, and it is not in
the onboarding path. A test asserts that list *exactly* (not "does not
contain") so a new entry point added later fails rather than passing silently.

**The two mechanisms compose.** Onboarding no longer asks for the paywall at
all; independently, the 30243cf route-level redirect means that in a dev build
`/paywall` resolves to Home even if something did ask. They are belt and
braces, not duplicates: one removes an intent, the other removes a
destination — and the redirect still covers `UpgradePromptSheet`, which is
staying.

## Files touched

**New**
- `lib/widgets/onboarding_visuals.dart` — the four slide visuals
- `test/screens/onboarding_redesign_test.dart` (15 tests)
- `docs/sessions/2026-08-22_onboarding-redesign.md` (this file)

**Rewritten**
- `lib/screens/onboarding_screen.dart` — content, visuals, unified completion,
  `slideCount`, `resetForReplay`. `_skipToPaywall` deleted.

**Changed**
- `lib/screens/profile_screen.dart` — dev-gated Developer section with the
  `_ReplayOnboardingRow`
- `CLAUDE.md`, `docs/CHANGELOG.md`

## Tests and analyze

`flutter test`: **334 passing** (319 baseline + 15 new), 0 failing.
`flutter analyze`: **44 issues**, 0 errors, 0 warnings — below the ≤45 ceiling
and unchanged from where this session started. Palette guard green.

New coverage: four slides in order with the right visual on each, Skip present
on 1–3 and absent on 4, CTA switching to the finish label; the dots tracking
the page with exactly `slideCount` of them; one `FilledButton` on screen at a
time; **a walk of all four slides harvesting every `Text` and asserting the
absence of "checkbox", "tick", "shopping list", "chf", "600", "not a chatbot"
and "pretending"** — a content test that walks the pages rather than reading
the source, so a string that only appears after a page change still counts;
slide 1 leading with what Harris is and carrying no year count; slide 3 naming
senses and showing the cue panel; slide 4 showing all three real day states and
the bookmark mention; **Finish completing and landing on Home**; **Skip
completing and landing on Home**, from slide 1 and from a middle slide;
a completed user being redirected away from onboarding when they ask for it
again; the onboarding source containing no paywall reference (comments
stripped, so the doc comment recording the removal does not trip it); the
exact app-wide paywall census; `resetForReplay` clearing both flags and the
router putting the user back at slide 1; and the Profile row sitting inside the
`kIsDevEnvironment` guard.

## Ambiguities

1. **"Wood-tan spoon" has no signed token.** The palette has no tan.
   `champagneTint` is the nearest warm neutral and is already the terracotta
   family's background wash, so it reads as wood beside a terracotta bowl
   without spending another semantic. Adding an unsigned token would have been
   guessing, and a literal would fail the palette guard.
2. **"Matches loading card"** — the Fridge Clearer's `_InlineGeneratingCard`
   was deleted with the single-stage flow in the previous build, so there is no
   loading card left to match. The illustration follows the diagram family's
   documented conventions instead.
3. **The dev replay reset lives on `OnboardingScreen`, not the Profile
   screen.** It knows about onboarding's own completion flags, and putting it
   there is what makes it testable — `ProfileScreen` cannot be pumped without a
   live Supabase instance, so a widget test of the row itself is not possible
   today. The row's dev-gating is asserted by a source check instead.
4. **The spec says the replay row "resets local flag"; it resets both.**
   Clearing only `hasSeenOnboarding` leaves `profile.onboarded` true and the
   router keeps the user on Home — the affordance would do nothing. This is the
   same trap Skip fell into.
5. **Slide 4's "My recipes" is covered by the bookmark line**, not by a second
   visual. The week strip is the signed visual and adding a second would fight
   it for the slide.
6. **Slide 3's cue-panel preview shows a readiness cue** (`oil_shimmers`
   wording). The doneness label exists too; showing one keeps the preview to
   two lines, and readiness is what a beginner meets first.
