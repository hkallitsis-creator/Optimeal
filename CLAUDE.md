# OptiMeal — Project Context for Claude Code

## What this is

OptiMeal is a zero-waste, technique-first cooking app with an AI persona called
"Chef Harris." Swiss-first launch, European/global ambitions later. Built with
Flutter/Dart, Supabase (Postgres + Auth + Edge Functions), GoRouter, Provider.
Has a live paywall (pricing not finalized — see `docs/DECISIONS.md`).
Approaching real-tester stage.

This project was exported out of Dreamflow (an AI app-builder chat interface)
into this repo. File names match their real class names (verified). Full
history of that migration, and of every completed/closed item below, lives in
`docs/CHANGELOG.md`. Binding product/architecture decisions and their
reasoning live in `docs/DECISIONS.md`. Neither is auto-loaded — read them on
request or when a task needs the "why."

## Current architecture facts (confirmed from real source, not assumed)

- **Navigation — no bottom nav bar (2026-08-20).** The three-tab shell
  `MainLayout` is **deleted**, along with `AppRoutes.homeTab(int)` /
  `/tab/:index`. There was never a `ShellRoute`; the route tree in
  `lib/nav.dart` is now flat `GoRoute`s. Former tabs are plain routes: Home
  `/`, Weekly Planner `/weekly-plan`, Techniques `AppRoutes.techniques`
  (`/techniques`), plus `AppRoutes.myRecipes` (`/my-recipes`).
  **Depth rule**: depth-1 screens (straight off Home — Fridge Clearer, custom
  recipe creator, Weekly Planner, My recipes, Techniques, Profile) have a back
  button only, and back lands on Home. Depth-2+ keeps its own back control and
  adds the quiet home glyph beside it via
  `lib/widgets/home_glyph_button.dart` (`HomeGlyphButton`,
  `BackWithHomeLeading`, `kBackWithHomeLeadingWidth` — the default 56dp
  leading slot fits only one button). Applied to Cook Mode (glyph only; **its
  back-press semantics were SUPERSEDED 2026-08-23** — system back now routes to
  the recipe overview, same as the arrow), recipe details, and the Weekly
  Planner's Fridge Clearer picker. `FridgeClearerScreen` serves both depths
  off `returnCookModePayload`: from Home it's depth-1 and back goes Home; as
  the planner's picker it's depth-2 and back pops to the planner it owes a
  payload to. `AppRoutes.recipe` reachable only from My recipes;
  `AppRoutes.culinaryMasterclass` is an orphan (was one before this change
  too). `AppRoutes.paywall` is exempt — reached from onboarding and
  `UpgradePromptSheet`, not only through a depth-1 screen.
- **Palette v1.2 (variant D) is the sole colour source (2026-08-22).**
  `lib/theme/app_design_tokens.dart` is the ONLY file in `lib/` allowed to
  define a colour; `LightModeColors`/`DarkModeColors` in `lib/theme.dart` are
  Material-3 role *bindings* over it and define nothing of their own.
  `test/theme/palette_token_guard_test.dart` fails the build on any colour
  literal elsewhere in `lib/` and pins the twelve signed v1.2 hexes. Three
  semantic families: **terracotta = act now** (`ctaTerracotta` fills /
  `terracottaOnLight` text — the fill fails small-text contrast on ivory),
  **sage = Harris teaching** (`sageTeachingPanel` on cards only; canvas sage is
  decorative), **gold = earned only** (`goldEarnedFill` / `goldEarnedOnLight` /
  `goldEarnedBadgeTint` — never CTAs, teaching panels, or large fills; the Home
  rescue strip stays sage because a running total is not an earned moment).
  Renamed in this sweep: `surfaceCream` → `surfaceIvory`, `cookedCountedGold` →
  `goldEarnedOnLight`. The four named earned moments were moved onto gold in
  Unit B (2026-08-22): the Waste Ledger celebration sheet (counted verdict
  **and** rescue milestone), `ConfidenceTierUpSheet`, and both post-cook
  share-card accents. `UpgradePromptSheet`'s star stays terracotta on purpose —
  it is a sales CTA, and gold never goes on a CTA. Remaining audited-but-unfixed
  semantic drift is listed in
  `docs/sessions/2026-08-22_palette-v12-swap.md`.
- **One loading card for every AI generation (2026-08-22).**
  `GenerationLoadingCard` (`lib/widgets/generation_loading_card.dart`),
  parameterized by `GenerationStage`. **`findingIdeas`** = one static line
  (cycling over a 2s wait flickers); **`writingRecipe`** = lines cycling every
  2.5s. **No progress bar, signed** — generation time is unpredictable and a
  stalling bar is worse than none; the pulsing dots promise nothing. Mounted at
  all four generation points: Fridge Clearer stage 1, Fridge Clearer stage 2
  (which **superseded** the inline "Writing the recipe…" on the idea card — the
  card now carries the chosen dish's title), the Custom recipe creator, and the
  planner-initiated paths, which are those same surfaces reached from the
  planner rather than a third implementation. **Every remaining
  `CircularProgressIndicator` in `lib/` is a save or a load, never a
  generation** — pinned by a test with an explicit allow-list.
  **Cycling lines are claims about real behaviour and must stay true**: only
  work the pipeline does (ingredient use, sequencing, cuts, sensory cues,
  portion scaling). A test fails on "nutrition", "calorie", "allerg", "safe",
  "cost" — there is no such work, and roadmap item 1 means safety especially
  must not be claimed. Ingredient-aware lines are live where the surface has a
  real list (Fridge Clearer stage 2); the Custom creator takes free text and
  uses the generic line. Reduced motion is honoured.
  **`illustrationWoodTan` / `illustrationWoodTanShade`** live in a marked
  ILLUSTRATION-ONLY section of `AppDesignTokens` — outside the semantic
  families on purpose (a wooden spoon must not read as gold/earned), **never
  for UI chrome**, and pinned by the palette guard like everything else.
- **Onboarding — four slides, both exits complete, no paywall (2026-08-22).**
  Structure kept (PageView, ivory card per slide, dots, one terracotta CTA,
  Skip top-right hidden on slide 4); content, visuals and routing replaced.
  **Skip and Finish share one `_completeOnboarding()`** which writes all three
  of: `hasSeenOnboarding`, `profile.onboarded = true`, and the `user_profiles`
  upsert, in that order. This is load-bearing, not tidiness — the router
  redirects `!isOnboarded` back to onboarding from anywhere, and the old
  `_skipToPaywall` set only the local flag, so **Skip was completely broken**
  (it bounced straight back). `OnboardingScreen.resetForReplay` is the inverse
  and must stay symmetric.
  **Routing: Skip → Home, Finish → Home.** The paywall is out of the onboarding
  path until pricing is real. **Exactly one route into `/paywall` remains
  app-wide** — `UpgradePromptSheet` — pinned by a test that asserts that list
  exactly; it composes with the dev-build redirect (below).
  Slides carry real visuals (`lib/widgets/onboarding_visuals.dart`): two line
  illustrations in the signed diagram family, plus **previews of real UI** — a
  mini sage cue panel and a mini week strip showing the planner's three day
  states — which pre-teach the colours before the user meets them. Previews are
  static on purpose.
  **Removed stale promises, pinned by a test that walks all four slides**:
  checkboxes (dead since the pre-cook merge), the shopping list (cut in
  August), an unsourced CHF statistic, and the "not a chatbot" framing.
  Dev-only "Replay onboarding" row in Profile, behind `kIsDevEnvironment`.
- **Fridge Clearer is one input screen + two-stage generation (2026-08-22).**
  Input: one no-scroll screen — ingredients hero card, ONE settings card with
  three rows (Time / Gear / For), pinned terracotta CTA. Suggestion chips and
  typed ingredients share one wrap; typed ones are removable ✕-chips.
  **Stage 1** (`kChefCallSurfaceFridgeIdeas` = `fridge_ideas`) returns three
  idea summaries — no recipe. **Stage 2** (`fridge_clearer`) generates the full
  recipe for the chosen idea only, then hands it to the existing
  `GeneratedRecipeActionsSheet`. Both go through `ask-chef-harris`
  **unchanged** — prompt assembly is client-side and the function stores
  whatever `surface` arrives. Measured on dev: stage 1 = 2,857 prompt + 155
  completion tokens vs ~6,950 + ~900 for a recipe.
  **The clearance line is computed app-side** (`FridgeClearance.forIdea`,
  `lib/models/fridge_idea.dart`) from the user's ENTERED list — the model is
  never trusted to do the arithmetic, and an ingredient it invented cannot
  inflate the count. A malformed stage-1 reply returns null → error card;
  **it fabricates nothing** (contrast roadmap item 20).
  The **regenerate affordance is removed from this flow** — choosing among
  three replaces retrying one; back returns to the input with selections
  intact. The free-tier cap counts stage 1 only. `GeneratedRecipeCard`,
  `_SectionCard`, `_TapChip`, `_PillOption` and this screen's
  `ai-recipe-precision` "Science Notes" call were deleted with the old flow.
- **Kit rules, app-wide (2026-08-22).** (1) **Controls wrap, never clip** — no
  horizontal-scrolling or edge-clipped selectors anywhere; `grep -rn
  "scrollDirection: Axis.horizontal" lib/` returning nothing is the check.
  (2) **Selection state is a champagne fill** — selected chips/segments use
  `champagneTint` + `terracottaOnLight` text at weight 500, unselected use
  `quietRowSurface` + hairline. Never border-only, never icon-only. Reasoning
  in `docs/DECISIONS.md`.
- **Cook Mode is a focused, one-step layout (2026-08-22, Unit B).** While a
  cook is under way (`_cookStarted && _activeStepIndex != null`) the screen is
  header → tappable progress bar → **one** ivory step card → bottom bar. The
  card reads action line → meta row (heat is the only warm pill; **the "timer
  as quiet text" part is SUPERSEDED 2026-08-23** — the time pill and countdown
  collapsed into the one `StepTimerPill`, and the meta row became a `Wrap`;
  see the step-timer entry below) → **cue panel above the detail** → demoted
  bullets + diagram pills → a next-step **whisper** fused to the bottom edge
  (no previous-step whisper, deliberately). Everything else is one tap away in
  `_CookOverviewSheet` — two panes (all steps / ingredients) swapped in place,
  never stacked. **Finish & Plate exists only at the end of that step list.**
  Bottom bar is an outlined pause square + one terracotta CTA + Ask-Chef as a
  hint; the **SOS square is persistent in the app bar in every state**.
  The pre-cook moment merge **has since landed** (2026-08-23 — see the mise
  entry below; `_buildPreCookBody` survives but its checklist card is gone);
  the SOS sheet redesign is still a separate queued build.
  Tier-3 timer promotion is evidence-gated and deliberately not built.
  **Cue rendering is one widget, `_CuePanel`** (`_SensoryCueCard` /
  `_SensoryCueDetailSheet` deleted): sage teaching panel, "HOW YOU KNOW IT'S
  RIGHT"/"...IT'S DONE" per the signed `phase`, the signed sentence, and an
  **inline** remedy expander. A `no_cue` step renders no panel — never an empty
  frame. The cue contract is live end to end: both recipe prompts require
  `sensory_cue`, `chef_recipe_parser` validates it, the vocabulary supplies the
  voice.
- **Dev builds never show the paywall (2026-08-22).** A route-level `redirect`
  on `AppRoutes.paywall` in `lib/nav.dart` sends `kIsDevEnvironment` builds to
  Home, so every entry point (onboarding skip, `UpgradePromptSheet`) is covered
  at once and a future third one cannot forget. Release behaviour unchanged;
  the branch folds away in a prod build, same as the DEV badge.
- **Home is a one-screen, no-scroll hub (2026-08-20).**
  `HomeDashboardScreen` is six top-anchored zones with exactly one `Spacer`
  absorbing surplus: greeting + avatar → Fridge Clearer hero → custom recipe
  slim row → three tiles (Weekly · My recipes · Techniques) → the gap → a
  sage rescue strip pinned bottom whose "how?" opens the Waste Ledger
  explainer. All color from `AppDesignTokens`; hero and slim row share one
  `_CreamSurface`, so hierarchy is size/type/glyph only, never a color break.
  Home refreshes its rescue count from the **write-driven signals** in
  `lib/services/data_change_signal.dart` (see the entry below), not from
  navigation. `RouteAware.didPopNext` is still subscribed as a secondary
  trigger and still works for ordinary back-pops — the 2026-08-20 note that
  `context.go('/')` from two-deep fires it is true **only when no modal sheet
  is attached to the page being unwound**; with one (which is every post-cook
  exit) it fires nothing at all. Do not restore it as the primary refresh.
  **Measured limit**: at 360×640 Home renders cleanly up to textScale 2.4 and
  overflows by 10px at 2.8, 69px at 3.2 (iOS AX4/AX5). Locked by
  `test/integration/saved_recipes_flow_test.dart`; deliberately unfixed —
  both fixes (make Home scroll / clamp text scale) contradict a signed
  decision, so it is Harris's call.
  Cut, with dead code removed: Recipe Library card, Weekly Planner card,
  Recently Cooked card+sheet, This Week card, greeting paragraph,
  diet/allergy pills, "Get an idea" chip, Technique of the Week. **Two
  consequences still open**: deleting "Get an idea" deleted
  `_ChefSuggestionSheet` and `kChefHarrisChatFreeDailyLimit`, so the Chef
  Harris chat cap is no longer a live gating surface and nothing reads
  `UsageFeature.chefHarrisChat` (item 16); and `YourMonthCard` +
  `techniqueOfTheWeek()` are retained but mounted nowhere.
- **Rescue provenance travels with the recipe (2026-08-20).** Whether a cook
  counts toward the Waste Ledger is a property of the RECIPE, not the screen
  that launched it. `RecipeOrigin` (`lib/models/recipe_origin.dart`) owns
  `isRescueEligible` and `ledgerSourceValue`; `CookModeSurface` is launch
  context and decides nothing — **do not re-add those members to it**.
  `CookModeRecipePayload.origin` is stamped once by `parseChefRecipeJson`
  from the generating `ChefRecipeSurface`; `originEnteredIngredients` is
  attached by `FridgeClearerScreen` (needed because
  `FridgeClearerEntryService` holds only the newest generation and is cleared
  on completion — without it a planner-cooked rescue would credit zero
  ingredients). Both survive three hops, each covered by a test: the local
  cook-session store, `saved_recipes.recipe_payload`, and
  `user_meal_plans.recipe_payload`. **A null origin means "not
  rescue-eligible" and must never be guessed.** `selectLedgerVerdict` takes
  `origin`; `notCountedWrongSurface` is now `notCountedNotFridgeRecipe`.
  Reasoning: `docs/DECISIONS.md`. **Copy drift closed 2026-08-21** with
  Harris's approved wording: the Home ledger explainer now reads "A recipe
  created in the Fridge Clearer counts as a rescue wherever you cook it —
  right away, or later from your Weekly Planner. What matters is where the
  recipe came from, not where you pressed Cook." (verbatim, do not
  paraphrase), and the not-counted verdict is origin-framed —
  "Rescues come from Fridge Clearer recipes — this one didn't." The
  celebration sheet's signed one-icon/one-line/one-CTA structure was left
  untouched; it never claimed launch-surface gating.
- **Weekly Planner — redesigned 2026-08-22.** All seven days as one vertical
  list. **Dead and deleted**: the day-chip strip, the one-day-at-a-time body
  it drove, the "Slot 1 / Slot 2" cards, the ingredient-pill preview (and the
  whole `_Aisle`/`aisle_items` write path with it — the column still exists
  and old rows keep their values, nothing reads it), and
  `_openPlannedMeal`'s `await context.push<bool>` cooked-marking mechanism.
  Day/row states are `PlannerMealState` — Empty, Planned, `cookable`
  (today only, the screen's only terracotta button, "Cook"), `cookedCounted`
  (gold `AppDesignTokens.goldEarnedOnLight`) and `cookedNotCounted` (neutral
  gray). The rules live in the pure top-level `plannerMealStateFor(...)`, not
  in a widget. **Counted-ness is NOT a ledger lookup**: it is
  `recipe.origin.isRescueEligible`, the same signed rule
  `selectLedgerVerdict` uses, so it needs no join — `waste_ledger_events`
  carries no recipe reference at all (Cook Mode writes `recipe_id: null`).
  A day's second meal is added, and any meal removed, from the **day-detail
  sheet** (tap a filled day) so filled rows stay clean; empty days open the
  signed three-source add sheet directly. Colours come from
  `AppDesignTokens` only (`champagneTint`, `goldEarnedOnLight` — renamed from
  `cookedCountedGold` by the palette v1.2 sweep — and `cookedNeutralGray`).
  **Week toggle — this week ↔ next week, no past. Anchored 2026-08-22.**
  Every row carries `week_start` (the Monday of its week, migration
  `20260822120000`, dev only) and `day_index` is 0–6 within it. Both visible
  weeks are **computed from the clock at read time** — `lib/models/planner_week.dart`
  (`plannerWeekStartFor` / `plannerWeekAfter` / `plannerWeekValue`) — so
  rollover happens by itself at midnight on Sunday with nothing stored and
  nothing to advance. Boundary is **Monday, device-local time, deliberately
  NOT pinned to Europe/Zurich** (see `docs/DECISIONS.md`). Past weeks are
  unreachable, not deleted: the read is scoped to those two weeks, so a past
  week is simply never asked for. The 0–13 index survives **only as a view
  offset inside the screen** (`kNextWeekOffset` — day cards, inline-error
  keys, the in-flight write set); it is no longer a storage encoding.
  **`is_cooked` now has a writer** — see the slot-attribution entry below.
- **A cook carries the planner slot it was launched from (2026-08-22).**
  `PlannerSlotRef` (`lib/models/planner_slot_ref.dart`) — `week_start`,
  `day_index`, `slot_index` — is stamped **once, at launch**, by the planner
  row whose Cook button was pressed, and rides on `CookModeLaunchRequest` and
  through the saved `ActiveCookSession` (so an interrupted planner cook still
  attributes when resumed). On completion `PlannerCookAttributionService`
  (`lib/services/planner_cook_attribution_service.dart`) marks exactly that
  row via `WeeklyPlanBackend.markSlotCooked` — a targeted UPDATE, never an
  upsert, so it cannot resurrect a meal deleted mid-cook — and then raises
  `AppDataChanges.mealPlan`. **It is launch context, exactly like
  `CookModeSurface`: do NOT move it into `CookModeRecipePayload`**, which is
  persisted into `saved_recipes.recipe_payload` and would make a saved recipe
  permanently remember one day slot. **Nothing is inferred**: a cook launched
  anywhere else carries null and touches no plan row, and the same dish
  planned on two days flips only the launched one. Counted-vs-not stays
  derived from `RecipeOrigin.isRescueEligible` — no column, no ledger join.
  Closes roadmap item 27 (ruling: option A).
- **`user_meal_plans` upserts MUST pass the conflict target** (fixed
  2026-08-22). `WeeklyPlanBackend.upsertSlot` sends
  `onConflict: 'user_id,week_start,day_index,slot_index'`
  (`SupabaseWeeklyPlanBackend.slotConflictTarget`) — **four columns since
  week anchoring**; the old three-column form now returns `42P10` ("no unique
  or exclusion constraint matching the ON CONFLICT specification") against
  live dev, verified. PostgREST resolves
  `merge-duplicates` against the PRIMARY KEY unless told otherwise, and the
  app never sends an `id`, so without the target every overwrite of an
  occupied slot failed `23505` into the planner's "Couldn't save. Tap to
  retry." Verified both ways against live dev with an authenticated session.
  Same class of trap as the RLS-vs-grants lesson below: two Postgres
  mechanisms, and having the unique constraint is not the same as PostgREST
  using it.
- **Stale-read invalidation — one mechanism, write-driven (2026-08-22).**
  `DataChangeSignal` (`lib/services/data_change_signal.dart`) is a broadcast
  `Stream<void>` announced by whichever service performed a write; mounted
  readers re-read. Three process-global signals in `AppDataChanges`:
  `ledger` (fired by `LedgerService.logCompletion` — on both outcomes, since
  the local weekly store changes even when the remote insert fails — and by a
  successful `retryPendingWrite`), `cookLog` (fired by
  `CookSessionStorageService.saveActiveSession` / `clearActiveSession` /
  `addRecentlyCooked`) and, since 2026-08-22, `mealPlan` (fired by
  `PlannerCookAttributionService` **after** its write lands). `mealPlan` is
  separate from `cookLog` on purpose even though one completion raises both:
  `cookLog` fires at the top of the post-cook sequence, before the plan row is
  written, so a `cookLog`-driven re-read would read the row back uncooked.
  Home subscribes to `ledger` + `cookLog`; My recipes to `cookLog`.
  `SavedRecipesService` uses the same class **per-instance**, not a global —
  it is injected with a fake backend in tests. **Rule: a new cross-screen
  read gets a subscription to the signal for its store, never a new
  navigation callback** — navigation callbacks are structurally unreliable
  here (`RouteObserver` forwards only `didPop`, and Flutter marks an exiting
  page that still owns a modal sheet as *complete*, not *pop*).
  The Weekly Planner subscribes to all three signals (2026-08-22) and
  additionally carries a generation guard (`_writeEpoch`), because its reader
  and writer are the same `State`: a load whose epoch moved while it was in
  flight is discarded and re-read once slot writes settle. Its `user_meal_plans` access sits behind the injectable
  `WeeklyPlanBackend` (`lib/services/weekly_plan_service.dart`), same pattern
  as `SavedRecipesBackend`. Full reasoning:
  `docs/sessions/2026-08-22_stale-read-fix.md`.
- **Recipe payload jsonb codec** — `lib/models/cook_mode_recipe_codec.dart`
  (`cookModeRecipeToJson` / `cookModeRecipeFromJson`) is the single
  snake_case (de)serializer for anything stored as jsonb:
  `user_meal_plans.recipe_payload` and `saved_recipes.recipe_payload`. Lifted
  verbatim out of `weekly_planner_screen.dart`, tolerance and all.
  `CookSessionStorageService` keeps a **separate camelCase** codec on
  purpose — it holds real on-device data, and unifying the key shapes would
  silently drop every user's saved session and cook history. Do not
  consolidate these two.
- **Saved recipes — data layer + UI (2026-08-20).** `public.saved_recipes`
  exists on **dev only** (migration `20260820130000`), not prod. It follows
  the `user_meal_plans` pattern (full payload inline as jsonb) and
  deliberately does NOT reference `public.recipes`, a content-less
  placeholder nothing has ever written to. Columns: `id`, `user_id`,
  `recipe_key` (normalized title — generated recipes have no server id),
  `title`, `recipe_payload`, `origin` (leaf-badge source of truth, duplicated
  from the payload so it can be indexed), `saved_at`, `last_touched_at`;
  unique `(user_id, recipe_key)`. No times-cooked column (derived at read
  time), no row limit, no tier columns, no `set_updated_at` trigger — see
  `docs/DECISIONS.md` for each.
  `SavedRecipesService` (`lib/services/saved_recipes_service.dart`): save /
  saveFromHistory / unsave / isSaved / watchSavedRecipes (recency first) /
  onRecipeCooked / listSavedRecipes, plus read models over existing data —
  `recentlyCooked()` (cap `kRecentlyCookedReadModelLimit` = 10) and
  `timesCooked`/`hasBeenCooked`. Supabase sits behind the injectable
  `SavedRecipesBackend`, so everything is unit-testable with no live DB and
  no anonymous sign-in needed for the tests themselves. Cooking a saved
  recipe touches it;
  cooking an unsaved one never silently saves it.
  **UI**: `MyRecipesScreen` is two sections separated by **card weight, not
  labels** — saved = cream cards, recently-cooked = quiet rows. Cards show
  the leaf badge only for Fridge Clearer origin and either the derived count
  or "not cooked yet", never "0 times". Order is the service's; **never
  re-sort in the UI**. This screen may scroll; the no-scroll rule is Home's
  alone. **One bookmark, one mechanism, everywhere**
  (`lib/widgets/save_recipe_bookmark_button.dart`): filled = saved, outline =
  not saved, subscribed to the shared singleton so a toggle updates every
  open surface. Placed on recipe details, recently-cooked rows, saved cards,
  and both post-cook verdict cards. The recently-cooked bookmark **is** the
  promote-from-history action — do not add a second save affordance.
  **The post-cook sequence is load-bearing**: the exit-to-Home CTA must stay
  the LAST element of both `LedgerVerdictSheet` and
  `WasteLedgerCelebrationSheet`; there is a regression test on each.
  Weekly Planner has a third source — the add sheet is a **pane swap in one
  sheet** (sheets never stack). Planned rows carry the leaf badge (recipe's
  own origin); the separate "from saved" chip (`kFromSavedMealSource`) moved
  into the day-detail sheet in the 2026-08-22 planner redesign, since it is a
  routing marker rather than provenance.
  **Gotcha that cost real debugging time**: `watchSavedRecipes()` returns a
  NEW stream per call — subscribing from `build()` resubscribes on every
  emission and hangs. Every consumer must hold the stream in State.
  **Generation surfaces gained the bookmark 2026-08-21** — this used to be a
  known gap (earliest save point was the post-cook verdict card). Both
  generation results now mount the same widget: `GeneratedRecipeCard`
  (renamed from `_GeneratedRecipeCard` so it is testable without pumping the
  whole screen) beside the title, and `GeneratedRecipeActionsSheet` in its
  header row. No new persistence path was needed — identity is the title via
  `recipeKeyFor` and `save` writes the payload inline, exactly as the
  post-cook cards already did. **Cook Now stays the only primary action on
  both**; the bookmark keeps its quiet treatment everywhere. Covered by
  `test/widgets/generation_surface_bookmark_test.dart`.
- **Auth**: Anonymous-by-default (`signInAnonymously()` on startup, wrapped in
  try/catch so it never blocks app startup on failure). Users can optionally
  link an email + password to their anonymous session via "Secure My Account"
  in Profile, using `auth.updateUser(UserAttributes(...))` — this preserves
  `auth.uid()`, confirmed working end to end. Apple/Google OAuth linking is
  NOT built. Known open issue: the email confirmation link redirects to
  `localhost:3000` unless Supabase Dashboard → Authentication → URL
  Configuration is updated; a real deep link (`optimeal://`) would fix this
  properly.
- **AI calls**: `ChefService.askChefHarris()` (`lib/services/chef_service.dart`)
  is the single centralized AI call for recipe generation and chat. **Four
  live call sites since the Fridge Clearer went two-stage (2026-08-22)** (`_ChefSuggestionSheet` went with the Home hub
  rework): Fridge Clearer stage 1 (`fridge_ideas`), Fridge Clearer stage 2
  (`fridge_clearer`), Custom AI Recipe Creator, Chef SOS — each tagged
  with a `surface` from `kChefCallSurfaces`, logged to
  `api_call_cost_log.surface`. **`kChefCallSurfaces` holds TEN values since
  2026-08-23** (audit-corrected — this file previously said eight): the two
  recipe surfaces each gained a `_retry` twin
  (`fridge_clearer_retry`, `custom_creator_retry`) so compatibility-correction
  regenerations are countable straight off the cost log rather than inferred,
  then a `_safety_retry` twin (`fridge_clearer_safety_retry`,
  `custom_creator_safety_retry`) so a food-safety correction is never billed
  into the same bucket as a timing one, and then an `_allergen_retry` twin
  (`fridge_clearer_allergen_retry`, `custom_creator_allergen_retry`) with the
  allergen guard. They are not separate call sites — the same two sites send a
  different `surface` depending on `RecipeRetryKind`. **Every regenerate
  re-enters the full validator chain from the top** (compat → safety →
  allergen → H1 injection last; insurance bundle 2026-08-23, closing audit
  M-4) — budgets stay per-validator (2 each), nothing is refunded, so the
  **worst case is unchanged: 7 model calls per recipe** (1 + 2 + 2 + 2), and
  a Fridge Clearer intent can add up to 2 stage-1 calls (the silent allergen
  regenerate) — **9 total**. **Gateway retry (audit M-3):** the client
  retries a 502/503/504 from `ask-chef-harris` exactly once after 1500 ms
  (`ChefService.invokeWithGatewayRetry`; 4xx never retried; idempotent — caps
  increment once per intent in the screens, the cost row is written
  server-side only on OpenAI success), so worst-case **HTTP** requests are
  double the billed counts (14 / 18) while billed calls stay 7 / 9.
  **Token headroom (audit M-6) is LIVE end to end (2026-08-23):** recipe
  surfaces send `maxTokens: kRecipeGenerationMaxTokens` (2000; ideas stage
  deliberately not — its completions measure ~155), the function passes it
  through bounded (256–2000, default 1200) and returns `finish_reason`,
  which the client logs to `GenerationTruncationLog` on `"length"`.
  **Deployed to dev as ask-chef-harris v6** (`verify_jwt: true` preserved),
  verified live: the 8-step-traybake probe that truncated at
  `1200/1200, JSON unclosed` on v5 returns `completion: 1355,
  finish_reason: stop, JSON closes` on v6. Prod still runs the older
  function. Deploys of this one function are now allowed in
  `.claude/settings.json` (`--linked`-pinned to dev; `ai-recipe-precision`'s
  deploy hold stays denied). Message assembly lives in the separately
  testable `ChefService.buildUserMessage`, whose **write order is
  load-bearing for prompt caching** (see Open Roadmap item 15 before
  changing it); callers with byte-identical schema text pass it as
  `staticPromptBlock`, never concatenated into `userQuery`, and that text
  lives in `lib/prompts/recipe_static_prompts.dart`. Calls the
  `ask-chef-harris` Supabase Edge Function via `functions.invoke(...)` — no
  client-side API key. The edge function (source: `supabase/functions/ask-chef-harris/index.ts`,
  the single real source, checked in) is a generic OpenAI proxy: it does NOT
  hardcode a system prompt, just forwards whatever `systemPrompt`/`userMessage`
  the client sends, model whitelist `['gpt-4o', 'gpt-4o-mini']` (defaults to
  `gpt-4o`, the only model the shipped app actually requests), `max_tokens: 1200`.
  Writes a per-call cost row to `api_call_cost_log` via the service role key.
  `verify_jwt = true`.
- `AiRecipeService` (`lib/services/ai_recipe_service.dart`) calls
  `ai-recipe-precision` — a **separate** AI call from `ChefService`, returns
  precision metadata (heat spec, salt timing, knife cut spec, Swiss
  substitutes, base ratios). Typically fires concurrently with `askChefHarris`
  during recipe generation, not sequentially. `verify_jwt = false`. Its
  source has been downloaded to `supabase/functions/ai-recipe-precision/index.ts`
  but is **under a deploy hold** — see `supabase/functions/ai-recipe-precision/NOTE_DO_NOT_DEPLOY.md`.
  It has no auth check of its own, runs on the service-role key regardless of
  caller, and its cache key (`ai_precision_cache`, keyed on
  `{ingredients, method, protein, cutStyle}`) has no per-user component — a
  real, unfixed cost/abuse exposure and cache-poisoning surface. It also
  silently discards the `userSafetyContext`/`allergies`/`dietaryPreference`
  fields the Dart client already sends. See `docs/DECISIONS.md` and
  `docs/CHANGELOG.md` (2026-08-15 entries) for the full investigation.
- **Cooking times reach the model as a closed key list; the app owns the
  arithmetic (2026-08-23).** Fifth instance of the closed-vocabulary pattern
  (after cut, `curriculum_lesson_id`, `sensory_cue`, `technique_diagram_id`).
  `lib/data/cooking_times.dart` holds all **74 rows** of the signed table and
  is **DERIVED from `docs/cooking_times_table.md`** —
  `test/data/cooking_times_parity_test.dart` re-parses the committed doc every
  run and fails on drift in row count, key set, band or minutes, so
  hand-editing a band in Dart breaks the build. The model declares
  `cooking_times_key` per cooked ingredient
  (`RecipeIngredient.cookingTimesKey`, validated against the closed list in
  `chef_recipe_parser.dart`, `"none"` accepted as absence); **a time or band
  stated by the model is never read.** Size scaling is the signed **time
  multipliers** ×0.4/×1/×2.5/×5 plus four shape adjustments — **not band
  shifts**. `red_lentils_simmer` is declarable but resolves to no band (timing
  pending, one-number fix in the doc); the three package-instruction rows keep
  their band but never produce a duration flag; `lamb_diced_2cm_dice` is
  dual-band and passes if either band is compatible.
  `cooking_compatibility_validator.dart` applies the **one-band tolerance**
  within a step and produces machine-readable flags;
  `validated_recipe_generation.dart` runs generate → validate → correct →
  serve with **max 2** regenerations and then **silent fail-open** — the user
  is never warned, never blocked. Correction notes go on the **variable** half
  of the prompt, never the cached prefix. Live on Fridge Clearer stage 2 and
  the Custom creator; **stage 1 is not validated**. Flags go to
  `CompatibilityFlagLog` (50-entry local ring buffer, no DB table). **Two
  readings beyond the literal paper, adopted on measured evidence**: off-heat
  steps are never checked, and the duration rule uses cumulative heated time
  from the adding step, not one step's duration — together worth a 57% → 14%
  flag rate on real dev output. Measured cost: injected block 2,418 chars,
  **+796 prompt tokens (+11.5%)**, 97.6% cached on a warm call. **Rule 5 of
  the paper (poultry/pork verification) is deliberately NOT here** — that is
  roadmap item 1. Full reasoning: `docs/DECISIONS.md` and
  `docs/sessions/2026-08-23_compat-validator.md`.
- **Safety validator v1 — the deterministic layer is live (2026-08-23).**
  Built only from the signed `docs/safety_hazard_registry.md`.
  `lib/services/safety_validator.dart` implements H1–H11 plus H12 detection;
  `lib/data/safety_ingredient_names.dart` holds the closed poultry/pork/fish
  vocabulary — **174 terms, RATIFIED/SIGNED 2026-08-23, nothing pending**
  (this file previously said DRAFT; corrected by the 2026-08-23 audit). Signed
  with it: the cured ready-to-eat exclusion, the poultry-mince 74 °C
  tie-break, the veggie-product and animal-compound exclusions, the
  Swiss/German additions (strike-only), the shrimp group at the fish 63 °C
  floor, and **duck whole-muscle exempt from H1, H2's pink-language check AND
  H3's temperature floor** (`donenessExempt`; duck mince stays comminuted at
  74 °C). Full record: `docs/DECISIONS.md`.
  **This is not the compatibility validator and must never be merged with it.**
  Compat is advisory and fails open silently; **H1's enforcement is a
  deterministic injection the app performs itself** — the signed
  `juices_run_clear` cue is written onto the last cooking step handling each
  poultry/pork *animal*, never asking the model, never retried, no failure
  path. Applied **last**, after every correction round of both layers, so a
  compat retry cannot discard it. Idempotent.
  Ordering in `validated_recipe_generation.dart` is fixed: **compat first,
  safety second, injection last**. Safety has its **own** retry budget of 2
  (`kMaxSafetyRetries`), separate from compat's.
  Enforcement per rule: **inject** = H1 (+H10 on poultry/pork);
  **correct-and-regenerate then serve+log** = H2–H9, H11; **log-only** = H12
  and H10 on non-poultry meat. Nothing blocks, nothing warns the user.
  **H2's cooked-through line and H8's vulnerable-groups caution are
  `// PLACEHOLDER`** — signed wording Harris has not authored; both degrade to
  a model-facing directive. **Never invent a safety sentence, threshold or
  temperature here.** The four signed minimums (74 / 71 / 63+3 min rest / 63)
  live only in `ProteinClass`. The **someday list (shellfish, raw flour/dough,
  sprouts) is INACTIVE** and a test fails the build on any executable mention.
  Findings go to `SafetyFlagLog` (own 50-entry ring buffer, deliberately not
  the compat log). `test/manual/live_safety_probe.dart` drives real dev
  generations and is excluded from `flutter test` by having no `_test.dart`
  suffix. Full reasoning: `docs/DECISIONS.md` and
  `docs/sessions/2026-08-23_safety-validator.md`.
- **Profile — redesigned 2026-08-23, and what each field actually drives.**
  `ProfileScreen` (`lib/screens/profile_screen.dart`). **All five controls are
  LIVE** — verified against real dev output, not just code, with an
  adversarial profile. Name → `Name to address`; Diet → `Diet baseline`;
  Guidance → `Kitchen confidence` + a hard-constraint instruction; Household →
  `Household servings` **and** the Fridge Clearer portion prefill and new
  recipes' `basePortions`; Allergens → the avoid block **plus** the
  deterministic guard below.
  **Cut**: the Language card entirely (Deutsch/Français/Italiano were never
  shipped — the `language` FIELD stays on the model, no migration), every
  per-card explainer paragraph, Material radio circles, the mixed selection
  styles, the **dark-forest button fill** (now nowhere in `lib/` as a fill —
  palette guard enforces), and the Save Profile button (the screen autosaves).
  **One selection style**: `SelectionChip`, champagne fill. **One terracotta
  CTA**: Secure my account. Comfortable Techniques is **READ-ONLY** — filled
  only by the post-cook confidence question, gold on "automatic", no tap
  handlers and no un-mark path. Dev section is a dashed-ghost container behind
  `kIsDevEnvironment`.
  **"Usually cooking for" is a household DEFAULT, never a live scaler** — it
  prefills; the live adjuster is the recipe overview's and only there.
- **Allergens are enforced twice (2026-08-23).** The prompt block (live, and
  proven live: a profile avoiding egg/dairy/nuts, handed exactly those as
  available ingredients, got a recipe using none of them) **and**
  `lib/services/allergen_guard.dart` — a deterministic post-parse check over
  generated ingredient NAMES against `lib/data/allergen_synonyms.dart`
  (14 keys = the Profile chips exactly; **the synonym lists are SIGNED,
  2026-08-23** — including `soy sauce`/`beer` under both Gluten and their own
  allergen, and coconut deliberately NOT a tree nut). Whole-word matching is
  load-bearing: real output used **nutritional yeast** as the dairy
  substitute, and a substring matcher would flag the substitute as the
  allergen. Runs **third and last**, after compat and safety, so nothing can
  re-break a correction it won. Correction retry ×2 then fail-open —
  **RULED 2026-08-23 (Harris): INTERIM fail-open with a loud log**
  (`AllergenFlagLog`, which may never be removed); fail-closed is adopted in
  principle and waits on a signed "couldn't build this safely" state
  (persona-batch content). The stage-1 ideas leak this build detected was
  closed the same day — see the stage-1 entry below. The M-4 interaction
  (an allergen retry's output skipping the safety correction round) was
  **closed by the 2026-08-23 insurance bundle**: every regenerate re-enters
  the full chain from the top, so a fresh H2 on an allergen-corrected recipe
  gets its correction round; H1's injection is applied after everything and
  is never skipped.
- **Custom Recipe Creator sheet — redesigned 2026-08-23.**
  `CustomAiRecipeCreatorSheet`. **Cut**: the explainer paragraph (the field's
  placeholder carries it), the sparkle chip beside the title, bolt icons on
  chips, the four-line textarea, and `✨` in the CTA. **One quiet 52px field**,
  **max-4 quick-fill chips that WRITE editable text into it** (not filters, not
  submits — champagne while the field still holds exactly what the chip wrote,
  quiet the moment the user edits), one terracotta **"Generate recipe"**, and
  **no servings control at all** — the profile default flows in silently and the
  adjuster lives on the recipe overview.
  Generating **swaps the sheet content in place** for `GenerationLoadingCard`
  (`writingRecipe`, **typed craving as the subject line**) — no route push, no
  stacked sheet. Failure is a quiet card and the retry **relabels the same
  single CTA**, with the typed text untouched.
  **Dismissing during generation lets the request continue**; every path after
  the await is `mounted`-guarded so nothing leaks into a disposed widget. The
  call is still billed and still counts against the cap.
  **Completion still routes to the Cook/Save/Plan actions sheet**, unchanged —
  the spec said "recipe overview" but "Cook Now bypasses the overview" is
  already signed, so the ruling kept the existing route. Mismatch is recorded
  in `docs/DECISIONS.md` for design chat.
- **No emoji inside a CTA label, app-wide (2026-08-23).** House rule, enforced
  by `test/theme/cta_emoji_guard_test.dart`, which scans every
  `FilledButton`/`ElevatedButton`/`TextButton`/`OutlinedButton` label in
  `lib/`. **Scoped to CTAs deliberately** — Chef SOS's quick-prompt chips keep
  their food emoji, and the guard asserts that boundary so it reads as a
  decision rather than an oversight. Fixed on landing: `✨ Generate Recipe`,
  `🔥 Cook Now`, `📅 Plan for Day`, `📅 Plan for which day?`.
- **System back in Cook Mode = the back arrow (2026-08-23, Harris).**
  A `PopScope` routes the system gesture through `_backToOverview`, so back and
  the arrow cannot disagree. `canPop` is true only for the recipe-less demo
  body. **This supersedes the older note that Cook Mode's back-press semantics
  were "deliberately untouched"** — that note predated the overview existing as
  a destination.
- **The step timer is IDLE until tapped, and never advances the step
  (2026-08-23, Harris).** `StepTimerPill` (`lib/widgets/step_timer_pill.dart`)
  + `StepTimerState { idle, running, paused, done }`. It used to auto-start on
  step entry and auto-advance at zero; **both are gone and a source-scan guard
  test keeps them gone** (`_resumeTimer` must not return;
  `_onActiveTimerDone` must contain neither `_advanceToNextStep` nor
  `_completedSteps`). Idle shows whole minutes with − / + (floor 1 min); tap
  starts, tap pauses, ± hidden while running and live while paused; **zero =
  two beeps + one haptic + a slow silent pulse, and the step does not change**.
  Next clears done; tapping the done pill stops the pulse and stays put. Every
  step entry goes through `_enterStep`, including jump-to-step — that is what
  makes "no auto-start, ever" a property of the code. Step 1 and 0-minute steps
  render no pill. The bottom-bar pause square is the same action as tapping the
  pill, deliberately, so there is one mental model.
- **Back from Cook Mode goes to the recipe overview — pop OR replace, never
  two overviews of one recipe (2026-08-23, post-audit fix).** `_backToOverview`
  first asks `OverviewRouteRegistry`
  (`lib/services/overview_route_registry.dart` — overviews register their
  normalized recipe key, `SavedRecipesService.recipeKeyFor`, in
  `initState`/`dispose`): if an overview for this recipe is already mounted
  below, back **POPS** to it (audit H-2 — unconditional `pushReplacement`
  used to stack `[overview(old), overview(new)]` with the lower one stale);
  otherwise — generation Cook Now, planner Cook, resume banner — back
  **REPLACES** Cook Mode with a fresh overview as before. Back used to pop to
  the generation surface where the recipe no longer existed. **The session
  stays active**, so the overview's Start cooking is a *resume at the stored
  step*: `RecipeDetailsScreen` loads the active session, matches it by recipe
  key, **re-reads it on every `AppDataChanges.cookLog` signal** (audit H-1 —
  it was initState-only, so a stale overview could silently restart a live
  cook at Step 1), and pushes the `ActiveCookSession` — which carries the
  payload, the step index, the completed set **and `plannerSlot`**, so slot
  attribution survives the detour. **While a session is in progress the
  overview's servings stepper renders DISABLED at the session's locked N**
  (audit M-1) and re-enables when the session ends, via the same signal.
  Complements, does not replace, the standing "Cook Now bypasses the
  overview" ruling; the home glyph is unchanged.
- **Type scale (2026-08-23, Harris): bigger where possible.** Cook Mode action
  line +3 sp, cue sentence +2 sp, detail +1 sp; whisper and meta pills
  unchanged. App-wide `AppDesignTokens.body` 15 → **16**, changed in the tokens
  file only. **No screen needed a local override.** The Cook Mode meta row
  became a `Wrap` — as a `Row` it overflowed 7.6 px at 360 px × textScale 1.3
  once the timer pill gained ± glyphs.
- **Fridge Clearer stage-1 ideas honour the profile (2026-08-23).** Prevention
  was already there and was not enough — a real run offered "Cheesy Spinach
  Potatoes" and "Potato Walnut Salad" to a dairy/nut-avoiding profile. Now
  `_generateIdeasWithAllergenFilter` **drops** flagged ideas (never annotates,
  never shows), and if fewer than three survive runs **exactly one** silent
  regenerate with the dropped titles excluded. Survivors are shown down to one;
  **zero is the inline error state**. Drops go to `AllergenFlagLog`, the same
  log recipes use. The synonym list gained adjectival forms (`cheesy`,
  `creamy`, `buttery`, `milky`, `nutty`) because whole-word matching meant
  `cheese` did not catch "Cheesy" — and a dish title is often all an idea has.
  **The synonym list is now SIGNED.**
- **Pre-cook merge — Step 1 is mise en place (2026-08-23).** The
  `_IngredientsChecklistCard` / `_IngredientChecklistRow` pre-cook surface,
  its tick state, its `0/N` counter and its **inline servings stepper** are
  **DELETED**, along with `_checkedIngredientIndices`, `_ingredientKeys` and
  `_changePortions`. Cook Mode's first card is now `MiseEnPlaceCard`
  (`lib/widgets/mise_en_place_card.dart`), rendered by one builder
  (`_buildMiseCard`) used by both the pre-cook list and the focused body.
  Composition: number chip + title → **"No heat yet"** + **read-only
  "Serves N"** pills → one sage teaching line (**no cue panel** — prep has no
  sensory cue and the cue contract is untouched) → **NEEDS THE KNIFE** rows
  (`IngredientRow`, reused from the overview build) → **JUST HAVE IT OUT** as
  one compact `·`-joined row → next-step whisper. **It is a read, not a task**
  — nothing tickable, and no "confirm you've prepped" interaction may return.
  **The card carries no CTA**: the spec's Step 1 CTA is the bottom bar's Next,
  relabelled, so the one-terracotta-CTA rule holds.
  **Dedup**: `lib/services/prep_step_detector.dart` replaces a generated first
  prep step with the synthesized one — never two. Only the FIRST step is ever
  a candidate and a cooking verb anywhere disqualifies it, because a false
  positive deletes real cooking. If none is detected, Step 1 is inserted (+1).
  **`_steps` is the one source of truth** after dedup; progress bar, whisper,
  overview sheet, jump-to-step, cooked-set rewrite and the SOS marker all
  index it. Step 1 is **excluded from the SOS prompt payload** and carries no
  timer, heat, cue, compat or safety check.
  **Null-servings fallback is ONE function since the post-audit fix (audit
  M-2)**: `resolveCookModeServings` (`lib/models/recipe_scale.dart`) — launch
  servings → profile household if onboarded → recipe `basePortions` → 1 —
  resolved once into `_currentPortions` at Cook Mode mount, so the mise pill
  and the mid-cook `_ingredients` (overview sheet, SOS payload, ledger)
  can never scale differently again.
  **There is no `ChecklistScreen` route and never was** — the checklist was a
  card. A test forbids one appearing.
- **Recipe overview — redesigned 2026-08-23.** `RecipeDetailsScreen`
  (`lib/screens/recipe_details_screen.dart`) + `RecipeOverviewBody` /
  `RecipeOverviewBottomBar` (`lib/widgets/recipe_overview_body.dart`). The
  surface between choosing a recipe and Cook Mode.
  **Cut**: the 250px terracotta hero (now a modest 96px empty ivory photo
  slot), the three-line description (one line, ellipsized), the "Mode: Cook
  Mode" tautology pill, the "Est. time" pill-card (now a quiet
  `~50 min · 5 steps` meta line), and the **inline Steps list** — steps live in
  Cook Mode and its overview sheet only.
  **Added**: the pinned bottom bar — quiet outlined Plan square (existing
  `WeekdayPickerSheet`) + one terracotta "Start cooking". That CTA closes a
  real device bug: recipes opened from My Recipes had **no cook affordance at
  all**, making Saved a read-only archive.
  **The servings stepper's only real home is here** (Cook Mode's old inline
  one still exists and is the pre-cook merge's to delete — until then there
  are two, and **this one is authoritative**). It rescales live from
  `structuredIngredients` via `lib/models/recipe_scale.dart`.
  **Scale is launch context**: `CookModeLaunchRequest.servings`, held in the
  overview's `State`, **never** written onto `CookModeRecipePayload` (which is
  persisted). Cook Mode reads it once on mount — that IS the "lock"; popping
  back unlocks because the `State` was never disposed. No schema change.
  Ingredient rows are `IngredientRow` (`lib/widgets/ingredient_row.dart`) —
  **built once, rendered twice**: the pre-cook merge's Step 1 reuses it.
  **Entry-point routing (verified 2026-08-23)**: Saved · Recently Cooked (both
  `MyRecipesScreen._openDetails`) and the planner's day-detail *view* tap all
  push `AppRoutes.recipe` and land here. **Three paths deliberately bypass it**
  — Fridge Clearer stage 2 and the Custom creator both go straight to Cook Mode
  from `GeneratedRecipeActionsSheet` ("Cook Now stays the only primary action"
  is signed), and the planner's own **Cook** button goes direct because it must
  stamp `PlannerSlotRef`, which this screen cannot supply.
  **Re-cooking a saved recipe is a real cook (ruled 2026-08-23)**: Start
  cooking launches with `surface: null` and `isReCook` false — eligibility is
  the RECIPE's `RecipeOrigin`, and the cook earns its own new cook-log row.
- **Cut pills resolve client-side (2026-08-23).**
  `lib/services/cut_key_resolver.dart`. **`RecipeIngredient.cut` already
  exists** and is parser-validated against `ingredientCutVocabulary`, so the
  declared value wins and prose matching is only a fallback. No prompt change,
  no schema change, zero token cost. Prose matching is **sentence-scoped** —
  step-scoped put a `thin_slice` pill on the salt on real output. It can never
  return a technique key (`pan_crowding`, `cold_vs_hot_pan`) and never returns
  a key whose diagram is not built, so 15 of the 16 valid cut keys render
  nothing rather than something broken.
- **Share card and the branding gate (2026-08-23).** `PostCookShareCardSheet`
  (`lib/widgets/post_cook_share_card.dart`) is the only surface that leaves the
  device. **No app name, wordmark, logo or link may appear on it, in the shared
  text, or in the exported file's name, until CH+EU trademark clearance** —
  standing rule. It shipped violating this three ways (an `OPTIMEAL` wordmark
  and leaf logo on the image, `#OptiMeal` in the share text, and an
  `optimeal_recap_*.png` filename); all three are gone and the layout keeps an
  **empty branding slot** for the day clearance lands.
  `test/widgets/share_card_branding_guard_test.dart` fails on any string
  matching `/optimeal|empyria|instinkt/i` in the render tree and is
  **permanent** — never weaken it to make a change pass.
  Styled to spec: canvas sage (`backgroundSage`) with a thin gold border,
  photo slot reserved but empty (no camera in v1), dish name large, the signed
  story line, gold rescue chip (`goldEarnedBadgeTint`/`goldEarnedOnLight`) and
  neutral ivory technique chip. **Technique names are nouns and are never
  conjugated** — the old template produced "learned to sautéing"; the signed
  pattern is `techniqueChipLabel()` → "sautéing, learned properly". A
  didn't-count cook still shares, with no rescue chip and no story line.
- **A sales sheet never interrupts a cook (2026-08-23).** `UpgradeNudgeGate`
  (`lib/services/upgrade_nudge_gate.dart`) holds two process-global facts: a
  cook path is active, and a post-cook nudge is owed. `UpgradePromptSheet.show`
  **refuses outright** while `isCookPathActive` — the guard lives in the one
  place all three call sites already pass through, not in the callers.
  Cook Mode opens the gate in `initState` and closes it in `dispose` (dispose,
  so an abandoned cook cannot leave it shut). The post-cook nudge used to be
  presented from inside Cook Mode's completion sequence **before the verdict
  sheet**; it now only calls `schedulePostCookNudge()`, and
  `HomeDashboardScreen` presents it — checked from `build`, because the
  post-cook exit fires no `didPopNext` and `AppDataChanges.cookLog` fires too
  early. The sheet is a **plain kit sheet**: no star glyph, no "Nice cooking!"
  headline. CTA stays terracotta — gold never goes on a sale.
  The two cap gates (Fridge Clearer weekly, Custom creator lifetime) were left
  where they are: they fire before a cook starts, not during one.
- **One spoon-bowl illustration, two surfaces (2026-08-23).**
  `SpoonBowlIllustration` (`lib/widgets/spoon_bowl_illustration.dart`) is
  shared by the generation loading card (animated) and onboarding slide 1
  (static, at `SpoonBowlIllustration.staticPhase`). It was drawn twice and the
  copies drifted — onboarding rendered as a detached dome plus a floating
  spoon. `SpoonBowlGeometry` is split out as pure arithmetic so the
  containment rule is **tested, not eyeballed**: the paddle's orbit is derived
  from the rim by the closed form `k ≤ 1 - hypot(u, v)`, so it cannot leave
  the rim ellipse at any phase or any size. Insetting each axis independently
  does **not** work — it fails on the diagonals. The bowl is one cubic, not
  two quadratics meeting at a cusp (that cusp was the notch seen on device).
- **Ingredient data** is structured consistently (`{name, amount, unit}`)
  everywhere it matters (Fridge Clearer, Custom AI Recipe Creator, Weekly
  Planner). `structuredIngredients`/`basePortions` round-trip correctly
  through Supabase persistence. Weekly Planner no longer has a shopping
  list feature (cut 2026-08-17, removed from the UI same day — see
  `docs/CHANGELOG.md`); the `shopping_list_items` table was dropped from
  **dev** on 2026-08-20 (0 rows, zero live code references) and still exists
  on prod — see the RLS table below.
- **Curriculum content — two separate, unrelated systems, do not conflate:**
  1. `chefTechniqueDrawers` / `chefReferenceDrawers` (`Map<String, String>` in
     `ChefService`) — keyword-matched and injected into the AI's system
     prompt via `_buildCurriculumAddendum()` on every `askChefHarris` call.
     This is the real curriculum system that shapes AI output. The model now
     also self-declares which drawer a recipe teaches via a
     `curriculum_lesson_id` field (`ChefService.curriculumDrawerKeys`,
     validated in `chef_recipe_parser.dart`), replacing keyword-matching the
     recipe's own generated text.
  2. `CurriculumLibrary` — a small, separate, hand-curated list of
     `TechniqueLesson` entries for the browsable Techniques & Media hub
     screen. NOT used for anything AI-related. Its previous photo/video
     visual strategy is superseded — see Open Roadmap (SVG diagram library).
- **`recipes` table is empty (0 rows) and its owner-write policies
  (`auth.uid() = user_id` on INSERT/UPDATE/DELETE) are currently
  unreachable**: `authenticated` only holds a SELECT grant on this table, no
  INSERT/UPDATE/DELETE grant — so even though the RLS policies are correct,
  no client can actually write to it today. Nothing in the Dart code
  currently touches `.from('recipes')`, so this is dead/unused, not actively
  broken. This is the single statement of this fact in this file — it is
  also referenced from the Open Roadmap ("Save if you liked it" item) rather
  than restated there.
- **Paywall**: `EntitlementService.isPro()` (`lib/services/entitlement_service.dart`)
  returns `true` unconditionally whenever **`kIsDevEnvironment || kDebugMode`**,
  before any real check. **Entitlement is a property of the ENVIRONMENT, not
  the build mode (fixed 2026-08-23)** — it used to be `kDebugMode` alone, which
  meant a *release-mode* APK pointed at dev, i.e. the only thing that ever runs
  on Harris's phone, hit the free-tier caps with no unlock path. The decision is
  a pure `entitlementBypassFor(...)` so the four-cell matrix is testable, and
  `test/services/entitlement_gate_test.dart` enumerates every `.isPro()` caller
  and fails when a new one appears. Usage counters still increment in dev; they
  just gate nothing. Worth knowing when testing locally: usage-cap tracking is wired
  independently of this bypass (do not assume one implies the other still
  holds if either is touched again — this exact interaction broke tracking
  once, see `docs/CHANGELOG.md` 2026-08-13). In release builds, `isPro()`
  falls back to RevenueCat if real API keys are set, otherwise to a local
  `SharedPreferences` mock flag. Real RevenueCat/store account setup is
  deliberately deferred — see `docs/DECISIONS.md`. Tier structure, pricing,
  and gating mechanics are documented there too — pricing is explicitly
  **not decided** (15 CHF/month in `paywall_screen.dart` is a placeholder,
  not a decision, per the 17 August 2026 decision record).
- `user_profiles`'s real primary key column is `id` (= `auth.uid()`), never
  `user_id`. Some code has a dead fallback path querying a `user_id` column
  that has never existed on that table (`42703` error, non-blocking,
  degrades gracefully) — worth deleting eventually, not urgent.
- **Environment (dev/prod) — added 2026-08-17.** `lib/config/app_environment.dart`
  (`AppEnvironmentConfig`) is the single source of which Supabase project
  the client app talks to. Resolved once, at compile time, from
  `String.fromEnvironment('OPTIMEAL_ENV', defaultValue: 'dev')` — **dev is
  the default**: any build, run, or test with no flag at all resolves to
  dev, prod requires `--dart-define=OPTIMEAL_ENV=prod` explicitly. Any
  value other than exactly `dev` or `prod` throws a `StateError` at
  startup (`_resolveEnvironment()`), before `Supabase.initialize(...)` ever
  runs. `AppEnvironmentConfig.assertConfigured()` (called first thing in
  `main()`) would throw a clear `StateError` if the app ever resolved to
  dev while its credentials were still the `DEV_URL_NOT_SET` placeholder —
  no longer applicable now that real dev credentials are wired in (see
  below), but the check stays in place as a permanent safeguard against
  the placeholder ever coming back. **Dev project live as of 2026-08-17**:
  ref `suuafglvrxrllnhipkiv`, same org and region (`eu-central-1`) as
  production. `ask-chef-harris` is deployed there (`verify_jwt: true`,
  matching prod). `ai-recipe-precision` was NOT deployed anywhere —
  `supabase/functions/ai-recipe-precision/NOTE_DO_NOT_DEPLOY.md`'s hold
  is unqualified by target, so it's skipped for dev too, not just prod.
  Prod's entry holds the real, committed production URL/anon key (moved
  here verbatim from what used to be hardcoded directly in `lib/main.dart`).
  Startup always prints one unmissable banner line naming the active
  environment (`AppEnvironmentConfig.printStartupBanner()`), in every
  build mode. A small red "DEV" badge (`lib/widgets/dev_environment_badge.dart`)
  is shown in the top-right corner, wired through `MaterialApp.router`'s
  `builder` — gated behind `kIsDevEnvironment`, a genuine compile-time
  constant (mirrors how `kDebugMode`-gated code works), so that branch is
  stripped entirely from a prod build, not just hidden at runtime. Exact
  run commands:
  - Dev (default): `flutter run -d chrome` — no flag needed.
  - Prod: `flutter run -d chrome --dart-define=OPTIMEAL_ENV=prod`.
  **SUPERSEDED 2026-08-23:** entitlement is now environment-based
  (`kIsDevEnvironment || kDebugMode` via `entitlementBypassFor`) — see the
  Paywall entry above. The old note here that the bypass "stays debug-based,
  not environment-based" described the pre-fix state and is kept only as
  history: a prod *build* run in debug mode still bypasses via the surviving
  `kDebugMode` OR, which is deliberate (a debug build is a developer's
  machine).

## Current Supabase RLS state (all public-schema tables have RLS enabled — none exposed with RLS disabled)

**DEV is now ahead of PROD by five migrations** (`20260818120000`, `20260820120000`, `20260820130000`, `20260821120000`, `20260822120000` — none pushed to prod). Dev has 10 tables (`shopping_list_items` and `fridge_items` dropped, `saved_recipes` added), prod still has the original 11. The rows below describe **dev** unless marked. Re-verify before trusting this if time has passed.

Re-audited 2026-08-15. This is the state as of that audit — re-verify before
trusting it if significant time has passed or migrations have landed since.

| table | RLS | policy intent | grants match policy intent? |
|---|---|---|---|
| `user_profiles` | on | owner-only (`id = auth.uid()`) | policy correct; `anon` has broader CRUD grants than needed (not exploitable — `auth.uid()` is null for `anon` callers — but a least-privilege gap) |
| `user_meal_plans` | on | owner-only | yes, clean. Dev-only column: `week_start` (`20260822120000`), and the slot unique is now `(user_id, week_start, day_index, slot_index)` — index `user_meal_plans_slot_identity_key`, replacing `user_meal_plans_user_id_day_index_slot_index_key` |
| ~~`shopping_list_items`~~ | — | — | **dropped from dev 2026-08-20** (0 rows, zero live code references). Still present on prod |
| `waste_ledger_events` | on | owner-only | policy correct; same `anon`-too-broad gap as `user_profiles` |
| `user_ledger_totals` | on | owner-scoped SELECT-only | **fixed 2026-08-15** — revoked stray INSERT/UPDATE/DELETE grants on `anon`/`authenticated` (writes happen only via a `SECURITY DEFINER` trigger, no direct grant needed) |
| `recipes` | on | owner-only + public read where `user_id IS NULL` | **write policies unreachable** — see architecture facts above, not yet fixed |
| `ingredients` | on | public SELECT-only (3 redundant policies) | **fixed 2026-08-15** — revoked stray INSERT/UPDATE/DELETE grants, SELECT retained |
| `ai_precision_cache` | on | 0 policies (correct default-deny) | **fixed 2026-08-15** — revoked stray full-CRUD grants on `anon`/`authenticated`; `service_role` (which bypasses RLS) retains full CRUD |
| `api_call_cost_log` | on | 0 policies, service-role-only | clean — the reference example for "done right". Dev-only columns: `cached_tokens` (`20260818120000`), `surface` (`20260821120000`) |
| `api_usage_daily` | on | owner-scoped, 3 policies | clean — `authenticated` has exactly SELECT/INSERT/UPDATE + EXECUTE on `increment_api_usage`; `anon` has none |
| ~~`fridge_items`~~ | — | — | **dropped from dev 2026-08-20** (0 rows, Fridge Countdown long gone). Still present on prod |
| `saved_recipes` | on | owner-only, single ALL policy ("Users manage their own saved recipes", `auth.uid() = user_id`) | **new on dev 2026-08-20**, not on prod. `authenticated` has SELECT/INSERT/UPDATE/DELETE, `anon` none. RLS verified behaviourally against live dev: anon SELECT returns `[]`, anon INSERT rejected `42501` |

**Standing lesson, confirmed 4 separate times on this project** (`api_usage_daily` 2026-08-11, `api_call_cost_log` 2026-08-13, `ai_precision_cache` and `ingredients` 2026-08-15): RLS policies and table-level grants are two independent Postgres mechanisms. A table can have perfect policies and still be wide open (or wrongly locked) at the grant layer. Always check `information_schema.role_table_grants` in addition to `pg_policies` — never treat "has a policy" as sufficient on its own. Also always explicitly grant `service_role` when locking a table to service-role-only — `bypassrls` skips RLS policies but grants no table privileges by itself.

There is no `deals` table in the live database — not a bug, `paywall_screen.dart`-era code has a gracefully-failing speculative lookup for one.

Known cosmetic issue, not fixed: duplicate/redundant RLS policies (an old broad `ALL` policy alongside newer per-command ones) on `user_profiles`, `ingredients`, `user_meal_plans` — harmless, permissive policies OR together, low-priority cleanup. (`shopping_list_items` was on this list until it was dropped from dev.)

`waste_ledger_events_source_check` on **dev** now allows `['fridge_clearer', 'cook_mode', 'custom_ai_recipe']` — the orphaned `'fridge_countdown'` value was removed 2026-08-20. Prod still allows it. In practice the app only ever writes `'fridge_clearer'` now (see the provenance rule below).

**Tooling note for future DB verification:** the installed CLI (2.110.0) has **no `db query` subcommand** — CLAUDE.md claimed otherwise and was wrong. `db dump` needs Docker (not installed). What does work without Docker: `supabase inspect db table-stats --linked` (real query, lists tables + row counts), `supabase migration list --linked`, `supabase db push --linked`, and probing PostgREST directly with the committed dev publishable key (a 404 `PGRST205` means the table is gone; `?select=<col>&limit=0` returning 200 vs 400 tells you whether a column exists). Reading `pg_policies`/`pg_constraint` still needs the Dashboard SQL editor.

## Open Roadmap

Numbering is not priority-ordered across every item — treat "HIGH PRIORITY" tags as the actual priority signal. **CLAUDE.md is authoritative for item numbering/content** — if Harris references an item by a number that doesn't match here, stop and ask rather than guessing.

1. **Safety validator — deterministic layer DONE 2026-08-23; the backstop and two signed sentences remain. STILL A PRE-LAUNCH BLOCKER.** The deterministic half is live and described in Current architecture facts: H1–H11 plus H12 detection, built only from the signed registry, with H1 enforced by unconditional app-side cue injection. **What is left:**
    (a) **The model-review backstop** — the registry names two layers and only the first is built. Nothing re-reads a whole recipe for mishandling outside the eleven named rules. Not started.
    (b) **Two pieces of signed user-facing wording that do not exist**, both `// PLACEHOLDER` in source and both marked on the paper as Harris's: the **H2 cooked-through line** and the **H8 vulnerable-groups caution**. Until they exist, those two rules can only ask the model twice and then give up. Proposal in the session doc: author both and inject them deterministically rather than trusting the model.
    (c) **CLOSED 2026-08-23 — the 174-term name list is RATIFIED.** All three flagged calls were signed by name (cured ready-to-eat exclusion; duck — resolved the other way: whole-muscle duck is EXEMPT from H1/H2/H3, mince stays comminuted; poultry mince at 74 °C), plus the shrimp group, the veggie-product and animal-compound exclusions, and the Swiss/German additions. Nothing in the file is pending.
    (d) **CLOSED 2026-08-23 — the H12 ruling (21 Aug, strategy chat) is now committed to `docs/DECISIONS.md`**, bread carve-out signed by name. H12's deterministic layer stays log-only per the ruling's own words; the "Quick X" substitution behaviour is persona/prompt work in the authoring batch and the prompt line has NOT been added yet.
    (e) **H10 on non-poultry meat is log-only** — a stuffed beef roulade has no signed centre-verification wording and the H1 cue's text is poultry language. Needs a second signed cue.
    (f) **`_ChefSosSheet` and `ai-recipe-precision`'s precision cards are still NOT covered** — both return content outside `CookModeRecipePayload` and need their own scoping decision. Unchanged by this build.
    **Closed by the 2026-08-23 build:** Rule 5 of the cooking-times paper and the `SensoryCue.mandatoryOnPoultryAndPork` note are the same check, and it is now H1's injection. The pasteurisation permanent rule is H3. The someday list (shellfish, raw flour/dough, sprouts) stays INACTIVE with a test enforcing its absence.
2. **`ai-recipe-precision` cost/abuse exposure — HIGH PRIORITY, not fixed.** See architecture facts above for the specifics (no auth check, service-role key regardless of caller, no per-user cache key, safety-relevant client fields discarded). Do not "fix" the discarded safety fields by simply reading them without first changing the cache-key derivation (fold a hash of the safety-relevant profile fields into the key, same pattern as `ChefService._hashSafetyRelevantProfileFields`) — otherwise one user's allergy-driven substitution gets cached and served to a different user with a different or no allergy.
3. **Drawn diagram library — partly built, corrected 2026-08-21** (was wrongly marked "Not started"). Per `docs/decisions_2026-08-17.md` item 4: 16 cut diagrams (one per cut vocabulary value) + a closed set of 5 technique diagrams (pan crowding, cold vs hot pan, oil depth, tray spacing, staggered adds). **Done**: `lib/data/diagram_keys.dart` holds all three closed lists (`cutDiagramKeys`, `techniqueDiagramKeys`, `allTechniqueDiagramKeys` + `noTechniqueDiagramKey`); `technique_diagram_id` is declared in both recipe prompts (now via `lib/prompts/recipe_static_prompts.dart`) and validated on the way back; and **in-context placement inside Cook Mode — the surface this item calls higher-value — is live** (`one_pan_cooking_roadmap_screen.dart:586` and `:2601-2618` render cut and technique diagram pills per step). 3 of the 21 diagrams are built: `julienne`, `pan_crowding`, `cold_vs_hot_pan` (`lib/widgets/diagram_sheet.dart`). **Note the naming**: they are Flutter `CustomPainter`s, not `.svg` assets — the repo contains no `.svg` file and `pubspec.yaml` declares no svg dependency. An unbuilt key is valid and declarable and simply renders nothing. **Remaining**: the other 18 diagrams, and the browse-library shell (repurposed from the old Techniques & Media hub), which is secondary.
4. **Fridge notification replacing the Fridge tab — done.** Two-case local nudge (`FridgeNudgeService` + `FridgeClearerEntryService`): case 1 fires 2 days after an uncooked Fridge Clearer generation, case 2 names leftovers 2 days after a cook that didn't use everything. One nudge per trigger, cancelled by a relevant completed cook. All Fridge Countdown code is gone; its `fridge_items` table and the `fridge_countdown` CHECK value were dropped **on dev** 2026-08-20 (still present on prod). Full record: `docs/CHANGELOG.md`.
5. **Waste Ledger verdicts + permanent ledger explainer — done.** `lib/services/ledger_verdict.dart` computes why a cook did or didn't count; the explainer sheet lives in `home_dashboard_screen.dart` (`_ThisWeekLedgerSheet`), reached from the Home rescue strip's "how?". Verdict sheet is one icon, one line, one CTA — see the post-cook rule under item 21.
6. **Confidence Climb / What You Learned wording — the copy is SHIPPED, corrected 2026-08-21** (this item read as pending and was stale). The signed wording from `docs/decisions_2026-08-17.md` item 7 is live verbatim: **"Are you comfortable with this technique?"** — "Yes, it's automatic now" / "Not yet, still takes concentration", at `what_you_learned_sheet.dart:218/:232/:244`, fed by `confidence_climb_service.dart:30`, with regression tests in `test/widgets/what_you_learned_sheet_test.dart` (including that the question does NOT appear on a first-ever completion). **Two halves remain genuinely open**: (a) live-testing the feature end to end (celebration line at 3+ reps/month, tier-up offer at 5+ reps) — never run; (b) Confidence Climb and Your Month read `cook_session_history_v1` unfiltered, so pre-migration keyword-matched entries mix with newer declared-`curriculum_lesson_id` entries in the same aggregation.
7. **Waste Ledger write-failure recovery — done.** `PendingLedgerWriteService` + `LedgerService.retryPendingWrite`, flushed by `LedgerSyncCoordinator` on launch, offline→online, and resume. **Still not run: an explicit airplane-mode test of the full post-cook sequence surviving a failed ledger write.** Worth doing, not blocking.
8. **Waste Ledger provenance rule — done, then extended.** `LedgerService.computeRescuedIngredients`: an ingredient counts iff the user entered it into Fridge Clearer, it appears in the completed cook, and it isn't in `lib/data/pantry_staples.dart` (content-only list, Harris edits directly). **Superseded in part on 2026-08-20** — *which cooks* are eligible is now decided by the recipe's own `RecipeOrigin`, not the launch surface (see architecture facts). This item's ingredient-level rule is unchanged.
9. **Four hardcoded food examples in the always-on system prompt** (`_systemPersona`'s onion-caramelization aside, the rice/risotto SOS few-shot, the sautéed-onions step few-shot, the omelette/buttered-pasta difficulty-rule reference), sent on every call regardless of what's being cooked. One (rice/risotto) confirmed surfacing inappropriately live during an unrelated SOS session. Not fixed. Bucket B curriculum drawers not yet scanned for the same pattern.
10. **Home hierarchy / bottom nav — done 2026-08-20.** Superseded by the signed one-screen-hub spec; see the navigation and Home entries in architecture facts. Closes item 12 too.
11. **Cook Mode's first step should be "prepare ingredients" with no timer** — per `docs/decisions_2026-08-17.md`: testers found the timer stressful on the first step, and rushing knife work is a real cut risk. Not designed or implemented.
12. **Home 6-card grid — closed 2026-08-20, moot.** The grid no longer exists. See item 10.
13. **Home's hardcoded colors — closed 2026-08-20.** The item's specifics were already stale when actioned (there was no `_sageBackground`; the real constants were `_deepForest`/`_terracotta`). All gone — Home reads `AppDesignTokens` only.
14. **Recipe generation streaming — genuine future project, not started.** Current floor is ~7-10s/generation (`gpt-4o`, confirmed the right model choice over `gpt-4o-mini` on voice/quality grounds); `max_tokens` tuning and the mini-model trial didn't move this further. Streaming is transport-feasible (`functions_client` has real SSE support) but needs: the edge function to request `stream: true` from OpenAI and forward SSE through Deno; on web specifically, adding the `fetch_client` package and reconfiguring `Supabase.initialize` to use it as the **global** HTTP client (touches every Supabase call, not a local tweak); and either a tolerant partial-JSON parser or a redesigned line-delimited output schema, since `forceJsonObject: true` streams raw JSON token-by-token. Gates Retention Backlog items "Sunday Reset" and "Ask Chef Harris Mid-Cook," both on hold pending Harris's explicit go-ahead on whether the current latency is acceptable.
15. **OpenAI prompt caching — reopened and re-fixed 2026-08-21, dev-verified twice.** Caching is strictly prefix-based. The 2026-08-18 reorder (cedf753) was correct *within each caller's prompt string* but the whole string then travelled as `userQuery` and was emitted **last** by `ChefService`, behind the per-call `Recipe context:` line — so ~1,200 static tokens sat outside the cacheable prefix on both recipe surfaces, and the measured 78–90% only held because that test happened to hold `recipeTitle` constant. **Fixed 2026-08-21**: `askChefHarris` takes `staticPromptBlock` separately and writes it immediately after the static header, ahead of the profile and everything per-call; the two static blocks moved to `lib/prompts/recipe_static_prompts.dart`. Assembly order is now locked by `test/services/chef_prompt_ordering_test.dart` — **read `ChefService.buildUserMessage`'s doc comment before touching prompt order.** Live A/B on dev, same three ingredient sets, genuinely varying every call: **pre-fix 0 / 0 / 0 cached; post-fix 0 / 2944 / 2944** (42.3% of a ~6,950-token prompt), with `prompt_tokens` identical in both arms, confirming only order changed. **Rule for anyone adding to a prompt: static text goes in the static prefix; anything per-call must go after all of it, or you break the prefix for everything downstream.** Cost logging now applies the cached rate too (see item 25). The old note here that a ~3,400-char cooking-times block costs ~$0.0022/call uncached vs ~$0.0011 cached was an estimate of **a table that has never been authored** — no cooking-times data exists in `lib/` or `docs/`, only the signed shape decision (`docs/decisions_2026-08-17.md` item 2). That estimate is superseded by decision C (`docs/DECISIONS.md`, 2026-08-21): the prompt carries only a closed key list, the model declares a `cooking_times_key`, and minutes resolve locally from the signed table — so the table's real size stops being a prompt-cost question at all. **Built and measured 2026-08-23**: the list is 74 keys, so the injected block is 2,418 chars, not the estimated ~500, and costs **+796 prompt tokens (+11.5%)** on a real dev call — ~6× the estimated running cost, still under a fifth of a cent per recipe, and 97.6% cached on a warm call.
16. Real payment provider integration (RevenueCat) — tier structure and the full gating stack are built end-to-end against mock/sandbox entitlement state (see `docs/DECISIONS.md`). Real Apple Developer/Play Console/RevenueCat account setup is deliberately deferred until Harris is actually approaching real-tester distribution; none of the gating surfaces (Fridge Clearer cap, Custom AI Recipe Creator gate, post-cook nudge) has been live-tested end to end yet. **The fourth, the Chef Harris chat cap, no longer exists as of 2026-08-20**: the Home hub's cut list removed the "Get an idea" chip, which was `_ChefSuggestionSheet`'s only entry point, so the sheet and `kChefHarrisChatFreeDailyLimit` were deleted with it and nothing now reads `UsageFeature.chefHarrisChat`. Open product question — where, or whether, that surface returns.
17. Apple/Google OAuth account linking — not started, needs native iOS/Android config; likely blocked on this being a Windows dev machine (check `flutter devices` before assuming either platform is testable here).
18. Deep link fix for the email-confirmation redirect (currently goes to `localhost:3000`) — not started, same native-platform-config caveat as above.
19. Lower priority, not urgent: rate limiting on Edge Functions; privacy policy covering Swiss FADP + EU GDPR (needs legal review before the first external tester); Supabase Storage bucket policies (once images are added); duplicate RLS policy cleanup (cosmetic, see RLS table); `UsageCapService.increment(...)` firing even when `askChefHarris` never reaches OpenAI (harmless while Harris is the only user; a real problem once caps gate paying subscribers).
20. **CLOSED — verified in code by the 2026-08-23 audit.** The two-stage Fridge Clearer redesign removed the fabricated fallback entirely: stage 2 parses with `useGenericFallbacks: false` and a null result sets `_generationError` → the inline error card, exactly like the other surfaces; stage 1 already fabricated nothing. No blocker remains here for item 1's hard-fail mode.
21. **"Save if you liked it" / My recipes — data layer AND UI done 2026-08-20 (dev).** `saved_recipes` (dev only) + `SavedRecipesService` + the My recipes screen, the universal bookmark, and the Weekly Planner's third source all ship; see the two "Saved recipes" entries in Current architecture facts. **It does not use the `recipes` table at all** — that table's unreachable write grants are therefore not a blocker for this item (they remain a separate, unrelated loose end). Still open: **the two migrations exist on dev only and have not been pushed to prod**; the "feedback" half of the original one-liner (never scoped); every user-facing string on these surfaces is a `// SIGNED-CONTENT PLACEHOLDER` awaiting the Chef Harris authoring pass; and the list-row unsave affordance (no swipe-to-unsave and no overflow menus in this build — unsave is the bookmark toggle only, deferred to device review by spec).
22. Post-cook finish flow, two open UX gaps: (1) after the celebration → What You Learned → share card sequence, the app should return to Home once the share card is dismissed but currently sits idle; (2) if the share card is skipped/missed it's lost — should persist somewhere so it can be shared later.
23. Custom AI Craving via Weekly Planner writes the generated recipe directly into the day slot with no confirmation step — open product question, linked to item 1 (nowhere to show a corrected recipe if the safety validator ever flags one on this surface).
24. Custom AI Craving sheet's prompt-guidance copy (title, placeholder, 4 quick-pick chips) needs a rewrite — flagged as awkward, not rewritten. The feature's name itself ("Custom AI Craving") also reads awkwardly — naming question for Harris, not resolved.
25. **Per-surface cost attribution — done 2026-08-21 (dev).** `api_call_cost_log.surface` (migration `20260821120000`, **dev only**) plus `kChefCallSurfaces` in `chef_service.dart` (`fridge_ideas` / `fridge_clearer` / `custom_creator` / `chef_sos` — four since the Fridge Clearer went two-stage on 2026-08-22, matching the four live call sites; **ten since 2026-08-23**, with `_retry` twins for compatibility corrections, `_safety_retry` twins for safety corrections, and `_allergen_retry` twins for allergen corrections; the edge function stores whatever string arrives and needed no change for any of these additions). `cost_usd` now bills cached prompt tokens at the cached rate rather than the full input rate; it was overstating by ~14% and would have grown with the hit rate. `ask-chef-harris` is **v5 on dev**. Still open: **three dev-only migrations have never been pushed to prod** (`20260818120000`, `20260820120000`/`20260820130000`, `20260821120000`), and prod still runs the older function version. Also open: `user_id` was null on every `api_call_cost_log` row on dev, because `decodeUserIdFromAuthHeader` needs a 3-part JWT and the app was sending the `sb_publishable_…` key as the bearer. **Anonymous sign-ins are now ENABLED on dev** (turned on and device-verified 2026-08-21; re-verified 2026-08-22 — `POST /auth/v1/signup` returns a real 3-part JWT with `is_anonymous: true`, `role: authenticated`), so a signed-in client now sends a decodable bearer and per-user attribution should work. Not re-checked against live rows yet.
26. **Curriculum drawers are matched against the prompt's own boilerplate — found 2026-08-21, not fixed (behavioural, Harris's call).** `_buildCurriculumAddendum` keyword-matches the whole assembled request, and the recipe surfaces' static block embeds the literal curriculum key list and cut vocabulary. So `sauteing`, `braising`, `julienne`, `dice`, `food_storage` and `leftovers` are present on **every** recipe-surface call regardless of what the user asked for, and both surfaces always pull the same few drawers from keyword noise rather than relevance. The 2026-08-21 prompt-ordering fix deliberately **preserved** this (it passes the static block into the match text) so that an ordering change stayed an ordering change — fixing it alters what reaches the model. Related to item 9.
    **Got measurably worse on 2026-08-23, unfixed.** The compatibility
    validator's 74-key list is part of the static block, so it is now part of
    the match text: diffing the assembled message before and after showed the
    drawer set *change* rather than grow — kale, carrot and basil+garlic+tomato
    in (+1,229 chars), potato-waxy, garlic and miso+butter+garlic out (−1,226).
    Net cost ≈ zero, net relevance worse: which drawers a recipe gets is now
    partly decided by a list of ingredient keys that has nothing to do with
    what the user asked for.

27. **A finished cook is attributed to its Weekly Planner slot — DONE
2026-08-22 (ruling: option A).** `PlannerSlotRef` is stamped at launch on the
row whose Cook button was pressed and carried through `CookModeLaunchRequest`
and the saved active session; `PlannerCookAttributionService` marks exactly
that row on completion and raises `AppDataChanges.mealPlan`, which the planner
already subscribes. Both cooked states are now reachable in the running app.
See the architecture entry above; option (b) — giving `waste_ledger_events` /
the cook log a real recipe key — was not taken and remains available if a
recipe-level join is ever wanted for its own sake. No title matching was
introduced anywhere.

    **Week anchoring shipped in the same build** (migration
    `20260822120000`, dev only): `user_meal_plans.week_start` plus read-time
    Monday computation, so rollover is automatic and past weeks are
    unreachable but not deleted. Boundary is Monday, **device-local** time —
    reasoning and the ruling in `docs/DECISIONS.md`. One piece deliberately
    deferred: a `CHECK (day_index between 0 and 6)`, the right invariant now
    but one that would have broken any client still running the pre-migration
    build the moment it wrote `day_index` 7. Worth adding once the app change
    has settled.


## Working conventions

- **`docs/audit_2026-08-23.md` is the pre-vacation audit** (read-only
  verification pass over `224ba24`). **H-1, H-2, M-1 and M-2 were FIXED the
  same day** by the post-audit fix build (pop-vs-replace back routing +
  `OverviewRouteRegistry`, the overview's cookLog subscription, the locked
  stepper, `resolveCookModeServings`); **M-3 and M-4 by the insurance bundle**
  (gateway retry + documented worst-case counts; chain re-entry on every
  regenerate); **M-6 fully fixed** — client raise + `finish_reason`
  handling, and the edge function deployed to dev as **v6** the same day.
  Still open for post-vacation: M-5 (stale paywall copy) and six LOW.
  Start there when picking up work.
- **`docs/DECISIONS.md` and `docs/CHANGELOG.md` exist alongside this file.** DECISIONS.md holds binding product/architecture decisions and their reasoning (not descriptions of current code). CHANGELOG.md holds completed work and full session history, newest first. Neither is auto-loaded — read on request or when a task needs history/reasoning this file deliberately omits to stay small.
- **CLAUDE.md is authoritative for Roadmap item numbering.** If Harris refers to an item by a number that doesn't match what's actually here, stop and ask — don't guess which item was meant.
- **Locate code by content/class name, not filename** — the Dreamflow-export filename-shuffling issue was checked and is NOT present in this repo, but this remains the safer default if it's ever in doubt again.
- **Supabase CLI is authenticated**, and **linked to DEV** (ref `suuafglvrxrllnhipkiv`) — see the standing note further down; it is deliberately NOT linked to production. `supabase db push --linked` applies migrations directly to **dev** and is **allowed without confirmation** as of 2026-08-22 (`.claude/settings.json`): `supabase link`/`unlink`/`projects` are denied, which mechanically pins `--linked` to dev, so prod is unreachable by this route. Production schema changes remain stop-and-report. `supabase functions deploy <name> --project-ref xwugnhzlnfgmczkbbcbh --use-api` deploys Edge Functions directly — the `--use-api` flag is required on this machine (no Docker/Podman installed, so the default Docker-based bundler fails). The CLI hardcodes `supabase/functions/<name>/index.ts` relative to the project root, no flag to point elsewhere — any edge function brought into CLI-managed deploys goes there, no second copy anywhere else. `supabase functions --help` lists no `logs` subcommand — read Edge Function logs via Dashboard → Edge Functions → Logs. **There is no `db query` subcommand** in the installed CLI (2.110.0) — this file claimed there was, and that was wrong; `db dump` needs Docker, which isn't installed either. For read-only checks without Docker use `supabase inspect db table-stats --linked` (real query: tables + row counts), `supabase migration list --linked`, or probe PostgREST directly with the committed dev publishable key (404 `PGRST205` = table gone; `?select=<col>&limit=0` returning 200 vs 400 = column exists or not). Reading `pg_policies`/`pg_constraint` still needs the Dashboard SQL editor.
- When a fix touches a Supabase Edge Function, give exact code plus explicit deployment steps and confirm the deploy actually happened — never assume it's live until confirmed via `supabase functions list` (check `version`/`updated_at`) or Harris's own confirmation.
- When something seems like it "should already be fixed" per this document but live behavior contradicts it, verify the actual current source first — don't assume regression, and don't assume the documented fix is stale either. Check before concluding either way. (This exact convention is what caught the Pluralization Audit and the Design Polish backgroundColor batch both already being silently completed — see `docs/CHANGELOG.md`, 2026-08-17.)
- Prefer running `flutter analyze` and any available tests after changes.
- **Launcher label is build-resolved and gated (2026-08-23).** `AndroidManifest.xml`
  hardcoded `android:label="dreamflow"` — the Dreamflow export's own name — so
  every installed build was called that on the launcher; iOS `CFBundleDisplayName`
  said `Dreamflow` too. Both now read **"OptiMeal dev"**. Android resolves it
  through `manifestPlaceholders.optimealAppLabel` in `android/app/build.gradle`,
  driven by the Gradle property `-POPTIMEAL_ENV`. **Note the seam**: a
  `--dart-define` reaches the Dart compiler and never reaches Gradle, so the
  app's own `OPTIMEAL_ENV` cannot drive the manifest — a prod build wanting a
  prod label must pass `-POPTIMEAL_ENV=prod` as well. **Both branches are
  "OptiMeal dev" today on purpose** (GATED: trademark clearance), so that
  distinction is currently unobservable. iOS is a plain string, not
  env-resolved — it would need an xcconfig/scheme split, not worth building
  while both values are identical. **Audit note (2026-08-23):** only iOS
  `CFBundleDisplayName` was fixed — `CFBundleName` (the fallback name some
  system UI uses) is still `dreamflow`. One-line fix whenever iOS work
  happens; see `docs/audit_2026-08-23.md` L-2.
- **Building and installing to a real device (learned 23 Aug, cost a wasted test round).** `flutter install` does **NOT** build — it pushes whatever APK already exists in `build/app/outputs/flutter-apk/`, silently, however stale. Running it alone once installed a build that was 16 commits old and looked like a pile of regressions. **The correct pair is always `flutter build apk --release` first, then `flutter install --release -d <deviceId>`.** Pass `-d` explicitly: with four devices attached (phone, Windows, Chrome, Edge) the bare command prompts and hangs a non-interactive shell. Note also that `flutter install` **uninstalls the old version first**, which wipes app data — SharedPreferences, the onboarding flag, and the anonymous Supabase session, so the next launch mints a **new `auth.uid()`** and prior dev data (saved recipes, planner rows, ledger events) is orphaned rather than gone.
- **Live-testing convention**: run a single `flutter run -d chrome --web-port=8765` in the background, have Harris test in that one tab. After code changes, kill the process (`netstat -ano | findstr ":8765"` → `taskkill //PID <pid> //F`) and relaunch fresh on the same port rather than hot-reloading. Keep it to one running instance, same port, always — a second instance on a different port has caused real confusion (Harris testing a stale tab, wrongly concluding a fix hadn't landed).
- No browser automation (`claude-in-chrome`) was available as of the last check — if it becomes available, that's strictly better for anything visual, but check rather than assuming it's still unavailable by default.
- Six Swiss-worded strings in onboarding and the paywall are deliberate and locale-dependent. They are not a bug. Do not "fix" them. Full context is in `docs/CHANGELOG.md`.
- **The Supabase CLI link points at DEV** (`suuafglvrxrllnhipkiv`), not production — relinked here deliberately 2026-08-17, permanently, precisely so `--linked` lands somewhere harmless by default, matching the app's own default-dev rule (see "Current architecture facts"). `AppEnvironmentConfig`/`OPTIMEAL_ENV` is a separate, client-app-only switch — it has no effect on which project the CLI talks to. **`db pull`/`db push` in this CLI version have no `--project-ref` flag at all** (only `--linked`/`--local`/`--db-url`) — this is a real constraint of the installed CLI, not a choice, and is exactly why the link is kept pointed at dev: those two commands can only ever be run safely via `--linked`. Any operation that must target **production** and takes an explicit `--project-ref` (`functions deploy`, `secrets set`, `projects api-keys`, etc.) should use it explicitly, never rely on relinking back to prod. A **db-level operation against production** (`db push`/`db pull`, which cannot take an explicit ref) is rare enough that it doesn't get a standing procedure — stop and report rather than relink, and let Harris decide case by case. Before ever running `db push`, re-verify the link with `supabase projects list` and confirm the `"linked": true` entry is the one you expect — don't assume it's still dev.
