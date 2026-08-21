# Session — stale-read-after-write fix (2026-08-22)

## Prompt (verbatim)

```
AUTONOMY: Full file/test/git permission. No confirmation questions.
STOP CONDITIONS: Prod Supabase = stop-and-report always. Dev Supabase
(suuafglvrxrllnhipkiv, --linked) is in scope READ-ONLY plus normal
app-level test writes through existing services — no migrations, no
schema changes, no function deploys this session. Spec ambiguity =
note and continue, never guess.

STALE-READ-AFTER-WRITE FIX — investigation first, then fix

SYMPTOMS (both observed on device, fresh 1c76d03 build, dev DB,
writes confirmed landing):
A. Home rescue strip shows the old rescue count after a completed
   counted cook; correct only after restart.
B. Weekly Planner does not show a newly placed recipe until restart.

Writes succeed; reads are not invalidated. Same defect family.
NOTE: symptom A closely resembles the F1 fix from 69f7e9c (Home This
Week card refresh after cook / on return to Home). Part of this
investigation is whether F1's mechanism regressed during the Home hub
rebuild (0e695c7 deleted MainLayout and rebuilt Home) or whether the
rescue strip is a different widget reading a different source that F1
never covered.

PART 1 — INVESTIGATION (report findings before fixing)
I1: For the Home rescue strip: exactly which widget renders it, what
source it reads (service/stream/future/local cache), and every
trigger that refreshes it. State plainly why a completed cook doesn't
reach it. Compare against the F1 mechanism and say whether F1's
refresh path still exists post-hub-rebuild and whether the strip is
on it.
I2: For Weekly Planner: how placed meals are read (one-shot future vs
stream), and why a placement made in-session isn't visible on return
to the planner screen.
I3: Sweep for the rest of the defect family: any surface that reads
ledger totals, saved recipes, planner contents, or cook history via
a one-shot read with no invalidation on write. List them all — My
recipes, verdict sheets, week states — whether or not symptomatic yet.

PART 2 — FIX
Fix A, B, and any family members found in I3 with ONE consistent
invalidation mechanism, not per-screen patches. Prefer extending
what already exists (watchSavedRecipes streams, F1's refresh path)
over introducing new state-management machinery. If the clean fix
is streams where futures are used today, do that. Do not add new
packages without noting why. Tests: regression test per symptom
(cook completes → Home strip updates without remount; placement →
planner shows it without restart) plus tests for I3 members fixed.

VERIFICATION
- flutter test: 190 baseline + new, all passing; flutter analyze ≤54,
  report exact count
- End-to-end on dev through real services where feasible without a
  device: write then read-back through the fixed paths
- git status clean, committed and pushed

DOC STEP (permanent rule): commit this prompt verbatim + your full
report to docs/sessions/2026-08-22_stale-read-fix.md. Update
docs/CHANGELOG.md.

Report verbatim: I1/I2/I3 findings, chosen mechanism and why,
files touched, test/analyze counts, push confirmation, ambiguities.
```

---

## Part 1 — Investigation

### I1 — the Home rescue strip

**Widget.** `_RescueStrip` (`lib/screens/home_dashboard_screen.dart`), zone 6
of the hub, a private `StatelessWidget` fed one `int count` from
`_HomeDashboardScreenState._weeklyIngredientsRescued`.

**Source.** A one-shot future: `_loadWeeklyLedger()` →
`LedgerService.getWeeklySummary()`, which reads the weekly figure out of
SharedPreferences (`waste_ledger_weekly_events_v1`, written by
`LedgerService._appendWeeklyEvent` during `logCompletion`) and the lifetime
figure out of `user_ledger_totals` in Supabase. The result is copied into
`State` fields by `setState`. No stream, no listener, no cache invalidation.

**Every trigger that refreshed it, before this session.** Exactly four:
`initState`; `didChangeAppLifecycleState(resumed)`; `didPopNext()` (via the
app-wide `routeObserver`); and the explicit re-read after `_resumeCookMode`'s
`await context.push(...)` returns.

**Why a completed cook did not reach it.** The write is fine and the read is
fine — the *trigger* never fires. The post-cook sequence ends in a verdict
sheet (`WasteLedgerCelebrationSheet` or `LedgerVerdictSheet`) whose single CTA
runs `context.pop()` immediately followed by `context.go(AppRoutes.home)`.
That is a page-based Navigator update, not a pop of the Cook Mode page, and
the Cook Mode page still owns a *pageless* route at that moment — the sheet,
which is still animating out. In `Navigator._updatePages` →
`DefaultTransitionDelegate.resolve`, an exiting page route that has pageless
routes attached is given `markForComplete`, **not** `markForPop`
(`packages/flutter/lib/src/widgets/navigator.dart:1201-1209`), and Flutter's
`RouteObserver` overrides only `didPush` and `didPop` — never `didRemove` or
`didComplete` (`routes.dart:2478/2499`). So no `RouteAware` callback of any
kind reaches Home, and `_loadWeeklyLedger()` never re-runs. Home keeps the
count it read when it was last entered; a restart re-runs `initState` and the
correct number appears.

Measured, not reasoned — a throwaway probe on the real `routeObserver` before
any fix was written:

| exit shape from a 2-deep stack | Home `didPopNext` calls |
|---|---|
| `context.go('/')` with a modal sheet just popped | **0** |
| `context.go('/')` with no sheet involved | 1 |
| `context.go('/')` from 1 deep, no sheet | 1 |

That probe is now a permanent test (`test/screens/home_rescue_strip_refresh_test.dart`,
group "why didPopNext alone could never have carried this").

**Against F1 (69f7e9c).** F1's mechanism — the app-wide
`RouteObserver<PageRoute>` in `lib/nav.dart` plus `RouteAware.didPopNext` on
the Home state — **still exists and still works**; it did not regress in the
hub rebuild, and the rescue strip *is* wired to it (`didPopNext` calls
`_loadWeeklyLedger`). Both halves of the prompt's either/or are therefore
"no". What actually changed is the exit path, not the refresh path: F1 was
built when leaving a cook meant popping back, and the post-cook sequence now
ends by replacing the stack from inside a sheet. `didPopNext` is simply blind
to that shape. CLAUDE.md's line "verified 2026-08-20 that `context.go('/')`
from two-deep does fire it" is true as written and was presumably verified
without a sheet on top — it is the sheet, not the depth, that decides.

### I2 — the Weekly Planner

**How placed meals are read.** One-shot future, `_loadPlanFromSupabase()`,
started from `initState` and never repeated except by the manual Retry button.
Placement itself is optimistic and purely local: `_optimisticallyAddMeal`
mutates the in-memory `_planned` map inside `setState` and fires the
`user_meal_plans` upsert in the background.

**Why an in-session placement wasn't visible.** A read/write ordering loss,
not a missing refresh. A placement made from *another* screen — Fridge
Clearer, My recipes' "Plan for which day?", or `GeneratedRecipeActionsSheet` —
does not go into the planner directly; it queues a
`WeeklyPlannerAddMealIntent` on a process-global `ValueNotifier` and then
navigates. The planner is constructed fresh, and in its `initState` two things
start in this order:

1. `unawaited(_loadPlanFromSupabase())` — the `SELECT` leaves immediately,
   before any frame;
2. a post-frame callback that consumes the pending intent, places the meal,
   and starts its upsert one frame later (~16 ms).

The `SELECT` was issued before the upsert, so it can never contain the new
row, and when it returned (~100-500 ms) it ran
`_planned..clear()..addAll(next)` unconditionally — wiping the meal that had
just been placed and persisted. The row was in `user_meal_plans` the whole
time, which is exactly why it reappeared after a restart. Deterministic in
practice, and reproduced as a failing test before the fix (the assertion read
`Found 0 widgets with text "Rescue Dish"`).

The in-planner sources (the add sheet's saved pane, and the Fridge Clearer
*picker* pushed from the planner, which fires its intent while the planner is
alive underneath) never hit this: their placement happens after the initial
load has already settled.

### I3 — the rest of the family

Every surface that reads ledger totals, saved recipes, planner contents, or
cook history:

| surface | reads | state before | verdict |
|---|---|---|---|
| Home — rescue strip + ledger explainer sheet | `LedgerService.getWeeklySummary()` | one-shot future, navigation-triggered | **symptom A — fixed** |
| Home — resume banner | `CookSessionStorageService.loadActiveSession()` | same triggers, same blind spot | **latent, same root cause — fixed** |
| Weekly Planner — planned meals | `user_meal_plans` select | one-shot, clobbers newer local state | **symptom B — fixed** |
| My recipes — saved shelf | `watchSavedRecipes()` | already write-driven | already correct, untouched |
| My recipes — recently cooked + derived "times cooked" | `recentlyCooked()` / `timesCooked()` over the local cook history | one-shot in `initState`, nothing invalidates it | **real family member — fixed.** Symptomatic when a cook is launched from one of its own rows and exited by back-pop rather than go-home, leaving this screen mounted with a stale log |
| Bookmark button (every surface) | `watchSavedRecipes()` | already write-driven | already correct, untouched |
| Weekly Planner add sheet — saved pane | `watchSavedRecipes()` | already write-driven | already correct, untouched |
| Verdict / celebration sheets | values passed in from the completion that just ran | not a read at all | not in the family |
| Profile — "comfortable techniques" | `ConfidenceClimbService.loadComfortableTechniqueIds()` | one-shot in `initState` | **not fixed, deliberately**: Profile is the only writer while it is open, and no path reaches Cook Mode from it, so it cannot go stale under its own feet. Listed for completeness |
| `YourMonthCard` | ledger month count + cook history | one-shot | **not fixed**: retained but mounted nowhere (CLAUDE.md architecture facts). Would need the same subscription if it is ever remounted |
| Fridge Clearer / Custom AI sheet reading cook history at generation time | `loadCookHistory()` | one-shot per generation | not in the family — a fresh read each time it is used, nothing cached on screen |

One adjacent finding, **reported not fixed** (it is a different defect, and
the fix is a product decision): `_openPlannedMeal` awaits
`context.push<bool>(...)` to learn whether the cook finished, so it can mark
the planner row "Cooked". The post-cook sequence leaves via
`context.go('/')`, which removes the planner page and completes that future
with `null` — so a planner-launched cook that finishes normally never marks
its slot. Only backing out through Cook Mode's app-bar button (which pops
`_cookSequenceStarted`) ever sets it. Deciding where that flag should come
from instead is Harris's call.

---

## Part 2 — the fix

### Mechanism, and why this one

**The trigger is the write, not the navigation.** A new
`DataChangeSignal` (`lib/services/data_change_signal.dart`) — a broadcast
`Stream<void>` with `notify()` / `listen()` — is announced by the service that
performed the write, and every mounted reader re-reads. Screens that are not
mounted need no telling; they read in their own `initState`.

This is not new machinery: it is exactly the pattern
`SavedRecipesService` has used since the saved-recipes build (a private
`StreamController<void>` re-emitting `watchSavedRecipes`), generalised into
one class and reused. `SavedRecipesService` now holds a `DataChangeSignal`
instead of its own controller, per-instance so an injected test service cannot
cross-talk with the singleton; the two stores whose writers are constructed ad
hoc all over the app get process-global signals in `AppDataChanges`:

- `AppDataChanges.ledger` — notified by `LedgerService.logCompletion` (on both
  outcomes: the local weekly store has already changed even when the remote
  insert failed) and by a successful `retryPendingWrite`.
- `AppDataChanges.cookLog` — notified by `CookSessionStorageService`'s
  `saveActiveSession`, `clearActiveSession`, and `addRecentlyCooked` (which
  also writes the history store).

Readers: Home subscribes to both (`ledger` → `_loadWeeklyLedger`, `cookLog` →
`_loadActiveSession`); My recipes subscribes to `cookLog` → `_loadDerived`.
Subscriptions are held in `State` and cancelled in `dispose`.

`didPopNext` **stays** on Home as a secondary trigger, with a comment saying
plainly that it is secondary and why. It costs nothing, it still covers
ordinary back-pops, and removing it would be a second behaviour change riding
along with this one.

No new packages. No state-management library. Nothing was converted to a
stream where a future was doing its job — only the *invalidation* changed.

**Why not "just await the sheet before navigating".** That would fix one call
site by ordering luck and leave the next sheet-plus-`go` combination to
rediscover the same bug. It also cannot help the planner at all.

**The planner needed a second thing**, because its defect is ordering, not
notification — the reader and the writer are the same `State` object, so
there is nobody to notify. It got the standard answer to a lost read/write
race, a generation guard: `_writeEpoch` is bumped by every local mutation,
`_loadPlanFromSupabase` captures it before the read, and if it moved while the
read was in flight the snapshot is **discarded rather than applied**, with a
re-read scheduled for the moment no slot write is in flight
(`_reloadIfWritesSettled`, called from the `finally` of both write paths).
Discard-and-re-read rather than skip-and-forget: skipping alone would have
kept the new meal but dropped every other day's meals from that load.

To make any of that testable, `user_meal_plans` access moved behind
`WeeklyPlanBackend` / `SupabaseWeeklyPlanBackend`
(`lib/services/weekly_plan_service.dart`), injected into the screen exactly
like `SavedRecipesBackend` already is. The JWT-clock-skew retry moved with it
(it is a transport concern) and now also covers the SELECT, which it did not
before.

**One extra fix in the same family**, found while making symptom A testable:
`LedgerService.getWeeklySummary` computed the weekly figure from local storage
and the lifetime figure from Supabase inside a *single* try/catch, so any
network failure returned `weeklyIngredientsRescued: 0` — an offline user was
shown "0 ingredients rescued this week" for rescues sitting in local storage.
The lifetime read now has its own catch and weekly degrades independently.

### Files touched

New:
- `lib/services/data_change_signal.dart`
- `lib/services/weekly_plan_service.dart`
- `test/support/fake_weekly_plan_backend.dart`
- `test/screens/home_rescue_strip_refresh_test.dart`
- `test/screens/weekly_planner_stale_load_test.dart`

Changed:
- `lib/services/ledger_service.dart` — notify on completion/retry; split the
  lifetime read's error handling out of the weekly path
- `lib/services/cook_session_storage_service.dart` — notify on the three write
  paths
- `lib/services/saved_recipes_service.dart` — private controller → shared
  `DataChangeSignal` (API unchanged)
- `lib/screens/home_dashboard_screen.dart` — subscribe to both signals;
  `didPopNext` documented as secondary
- `lib/screens/my_recipes_screen.dart` — subscribe to `cookLog`, add `dispose`
- `lib/screens/weekly_planner_screen.dart` — backend seam, epoch guard,
  reload-on-settle
- `test/screens/my_recipes_screen_test.dart` — one added group

### Tests and analyze

`flutter test`: **198 passing** (190 baseline + 8 new), 0 failing.
`flutter analyze`: **50 issues** (baseline 54; all 50 are `info`-level, no
errors or warnings — the four that went away were dead type-checks and
`return`-in-`finally` in the planner code this session replaced).

Both symptom tests were verified to **fail without the fix**, not merely to
pass with it:

- planner, guard disabled → `Found 0 widgets with text "Rescue Dish"`;
- Home, ledger subscription removed → `Found 0 widgets with text
  "3 ingredients rescued this week"` on both Home tests.

New tests: Home refreshes in place on a ledger change (same `State` instance
asserted, so it is a refresh, not a remount); Home shows the correct count
after a cook exited through a sheet CTA; the resume banner rides the same
signal; the framework-behaviour probe documenting why `didPopNext` cannot
carry it; planner survives a stale load and re-reads afterwards; a clean load
still replaces local state; a placement after the load is persisted and stays;
My recipes picks up a cook recorded while it is mounted (through the real
`CookSessionStorageService.addRecentlyCooked` writer, no fake).

### Dev verification (read-only)

Against dev (`suuafglvrxrllnhipkiv`) over PostgREST with the committed
publishable key:

- every column the refactored planner backend reads and writes exists —
  `user_id, day_index, slot_index, title, source, aisle_items, recipe_payload,
  is_cooked, updated_at` returned **200** on `?select=…&limit=0` (a wrong
  column returns 400);
- `user_meal_plans`, `waste_ledger_events`, `user_ledger_totals`,
  `saved_recipes` all present, anon `SELECT` returns `[]` — RLS holding;
- **no schema change was made or needed** this session; no migrations, no
  function deploys.

A genuine end-to-end write-then-read-back on dev is **not possible from this
machine**: dev has anonymous sign-in disabled and sends the
`sb_publishable_…` key as the bearer, so `auth.uid()` is null and the
owner-only policy rejects the insert — confirmed, deliberately, with a probe
row that was refused `401 / 42501` and left nothing behind (`SELECT` after it
returns `[]`). Reported rather than worked around; it needs a device or an
authenticated session. The ledger and cook-log halves of the fix *are*
exercised end to end in-process against their real stores (SharedPreferences),
with no fakes at all — only the planner's transport is faked, and only so its
timing can be controlled.

### Ambiguities / notes

1. **The planner's "Cooked" flag** never gets set on a normal post-cook exit
   (see I3). Reported, not fixed — where that signal should come from is a
   product decision.
2. **`YourMonthCard`** was left alone: it is mounted nowhere. If it returns it
   needs the `ledger` + `cookLog` subscriptions.
3. **Profile's comfortable-techniques read** was left one-shot for the reason
   given in I3, not by oversight.
4. `AppDataChanges`' two signals are process-lifetime and never disposed —
   deliberate; a broadcast controller with no listeners drops events.
5. CLAUDE.md's 2026-08-20 note that `context.go('/')` "does fire"
   `didPopNext` is not wrong, but it is only true without a sheet attached.
   The architecture facts have been updated to say so rather than leaving a
   line that reads as a general guarantee.
