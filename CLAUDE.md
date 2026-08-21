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
  leading slot fits only one button). Applied to Cook Mode (glyph only; its
  back-press semantics are untouched), recipe details, and the Weekly
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
  `goldEarnedOnLight`. Known open: several earned-moment surfaces (post-cook
  celebration, share card) still render terracotta rather than gold — audited
  and listed in `docs/sessions/2026-08-22_palette-v12-swap.md`, deliberately
  not redesigned in a token swap.
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
  is the single centralized AI call for recipe generation and chat. **Three
  live call sites, not four** (`_ChefSuggestionSheet` went with the Home hub
  rework): Fridge Clearer, Custom AI Recipe Creator, Chef SOS — each tagged
  with a `surface` from `kChefCallSurfaces`, logged to
  `api_call_cost_log.surface`. Message assembly lives in the separately
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
  returns `true` unconditionally whenever `kDebugMode` is true, before any
  real check — a deliberate debug bypass, dead code in release builds, but
  worth knowing when testing locally: usage-cap tracking is wired
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
  **`EntitlementService.isPro()`'s `kDebugMode` bypass was deliberately
  left untouched** — it stays debug-based, not environment-based. A prod
  *build* run in debug mode (e.g. local `flutter run` with the prod flag)
  still bypasses entitlement checks; that's an intentional, separate
  decision not made as part of this environment split — do not conflate
  the two mechanisms or assume fixing one changes the other.

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

1. **Safety validator for Chef Harris output — HIGH PRIORITY, PRE-LAUNCH BLOCKER.** No check of any kind exists between OpenAI's raw output and what the user sees. `askChefHarris` only checks non-emptiness. Four surfaces each independently parse raw output via now-shared `parseChefRecipeJson` (`chef_recipe_parser.dart`, refactor already done and device-verified — see `docs/CHANGELOG.md`), but nothing validates the *content* against food-safety rules after parsing. Likely shape: a deterministic rules layer for enumerable hazards + a model-review backstop, preferring regeneration/correction over a hard block (matches this app's fail-forward pattern elsewhere). **The hazard list is Harris's to supply, do not invent one.** Per the pasteurisation-table cut (`docs/decisions_2026-08-17.md` item 8), the permanent rule for that specific hazard is already decided: flag any stated temperature below the instantaneous minimum with no hold time stated — fold this in directly rather than waiting on a full equivalence table (which was dropped). The broader per-hazard sign-off table is still blank; two entries (shellfish; raw flour and sprouts) are unsourced placeholders. `_ChefSosSheet` and `ai-recipe-precision`'s precision cards are NOT covered by whatever chokepoint gets built for `CookModeRecipePayload` — both return content outside that shape and need a separate scoping decision. `SensoryCue.mandatoryOnPoultryAndPork` (`lib/data/sensory_cue_vocabulary.dart`) already exists — true only for `juices_run_clear` — flagging that a step's absence of this cue on a poultry/pork recipe should be a validator check once this item is built; not implemented as part of the sensory cue integration itself, since it belongs here.
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
15. **OpenAI prompt caching — reopened and re-fixed 2026-08-21, dev-verified twice.** Caching is strictly prefix-based. The 2026-08-18 reorder (cedf753) was correct *within each caller's prompt string* but the whole string then travelled as `userQuery` and was emitted **last** by `ChefService`, behind the per-call `Recipe context:` line — so ~1,200 static tokens sat outside the cacheable prefix on both recipe surfaces, and the measured 78–90% only held because that test happened to hold `recipeTitle` constant. **Fixed 2026-08-21**: `askChefHarris` takes `staticPromptBlock` separately and writes it immediately after the static header, ahead of the profile and everything per-call; the two static blocks moved to `lib/prompts/recipe_static_prompts.dart`. Assembly order is now locked by `test/services/chef_prompt_ordering_test.dart` — **read `ChefService.buildUserMessage`'s doc comment before touching prompt order.** Live A/B on dev, same three ingredient sets, genuinely varying every call: **pre-fix 0 / 0 / 0 cached; post-fix 0 / 2944 / 2944** (42.3% of a ~6,950-token prompt), with `prompt_tokens` identical in both arms, confirming only order changed. **Rule for anyone adding to a prompt: static text goes in the static prefix; anything per-call must go after all of it, or you break the prefix for everything downstream.** Cost logging now applies the cached rate too (see item 25). The old note here that a ~3,400-char cooking-times block costs ~$0.0022/call uncached vs ~$0.0011 cached was an estimate of **a table that has never been authored** — no cooking-times data exists in `lib/` or `docs/`, only the signed shape decision (`docs/decisions_2026-08-17.md` item 2). That estimate is superseded by decision C (`docs/DECISIONS.md`, 2026-08-21): the prompt carries only a ~500-char closed key list, the model declares a `cooking_times_key`, and minutes resolve locally from the signed table — so the recurring per-call prompt cost is roughly a seventh of the old estimate and the table's real size stops being a prompt-cost question at all.
16. Real payment provider integration (RevenueCat) — tier structure and the full gating stack are built end-to-end against mock/sandbox entitlement state (see `docs/DECISIONS.md`). Real Apple Developer/Play Console/RevenueCat account setup is deliberately deferred until Harris is actually approaching real-tester distribution; none of the gating surfaces (Fridge Clearer cap, Custom AI Recipe Creator gate, post-cook nudge) has been live-tested end to end yet. **The fourth, the Chef Harris chat cap, no longer exists as of 2026-08-20**: the Home hub's cut list removed the "Get an idea" chip, which was `_ChefSuggestionSheet`'s only entry point, so the sheet and `kChefHarrisChatFreeDailyLimit` were deleted with it and nothing now reads `UsageFeature.chefHarrisChat`. Open product question — where, or whether, that surface returns.
17. Apple/Google OAuth account linking — not started, needs native iOS/Android config; likely blocked on this being a Windows dev machine (check `flutter devices` before assuming either platform is testable here).
18. Deep link fix for the email-confirmation redirect (currently goes to `localhost:3000`) — not started, same native-platform-config caveat as above.
19. Lower priority, not urgent: rate limiting on Edge Functions; privacy policy covering Swiss FADP + EU GDPR (needs legal review before the first external tester); Supabase Storage bucket policies (once images are added); duplicate RLS policy cleanup (cosmetic, see RLS table); `UsageCapService.increment(...)` firing even when `askChefHarris` never reaches OpenAI (harmless while Harris is the only user; a real problem once caps gate paying subscribers).
20. Fridge Clearer fabricates a hardcoded fallback recipe on `_parseCookModeRecipe` returning null, instead of showing "no recipe" like the other 3 recipe-generating surfaces do. Blocks the safety validator's hard-fail mode (item 1) on this surface. Small fix: the screen already has `_generationError` state + a wired `_InlineErrorCard` used for real exceptions — the parse-failure branch just needs to set `_generationError` instead of building a fallback recipe. Not started.
21. **"Save if you liked it" / My recipes — data layer AND UI done 2026-08-20 (dev).** `saved_recipes` (dev only) + `SavedRecipesService` + the My recipes screen, the universal bookmark, and the Weekly Planner's third source all ship; see the two "Saved recipes" entries in Current architecture facts. **It does not use the `recipes` table at all** — that table's unreachable write grants are therefore not a blocker for this item (they remain a separate, unrelated loose end). Still open: **the two migrations exist on dev only and have not been pushed to prod**; the "feedback" half of the original one-liner (never scoped); every user-facing string on these surfaces is a `// SIGNED-CONTENT PLACEHOLDER` awaiting the Chef Harris authoring pass; and the list-row unsave affordance (no swipe-to-unsave and no overflow menus in this build — unsave is the bookmark toggle only, deferred to device review by spec).
22. Post-cook finish flow, two open UX gaps: (1) after the celebration → What You Learned → share card sequence, the app should return to Home once the share card is dismissed but currently sits idle; (2) if the share card is skipped/missed it's lost — should persist somewhere so it can be shared later.
23. Custom AI Craving via Weekly Planner writes the generated recipe directly into the day slot with no confirmation step — open product question, linked to item 1 (nowhere to show a corrected recipe if the safety validator ever flags one on this surface).
24. Custom AI Craving sheet's prompt-guidance copy (title, placeholder, 4 quick-pick chips) needs a rewrite — flagged as awkward, not rewritten. The feature's name itself ("Custom AI Craving") also reads awkwardly — naming question for Harris, not resolved.
25. **Per-surface cost attribution — done 2026-08-21 (dev).** `api_call_cost_log.surface` (migration `20260821120000`, **dev only**) plus `kChefCallSurfaces` in `chef_service.dart` (`fridge_clearer` / `custom_creator` / `chef_sos` — three, matching the three live call sites). `cost_usd` now bills cached prompt tokens at the cached rate rather than the full input rate; it was overstating by ~14% and would have grown with the hit rate. `ask-chef-harris` is **v5 on dev**. Still open: **three dev-only migrations have never been pushed to prod** (`20260818120000`, `20260820120000`/`20260820130000`, `20260821120000`), and prod still runs the older function version. Also open: `user_id` was null on every `api_call_cost_log` row on dev, because `decodeUserIdFromAuthHeader` needs a 3-part JWT and the app was sending the `sb_publishable_…` key as the bearer. **Anonymous sign-ins are now ENABLED on dev** (turned on and device-verified 2026-08-21; re-verified 2026-08-22 — `POST /auth/v1/signup` returns a real 3-part JWT with `is_anonymous: true`, `role: authenticated`), so a signed-in client now sends a decodable bearer and per-user attribution should work. Not re-checked against live rows yet.
26. **Curriculum drawers are matched against the prompt's own boilerplate — found 2026-08-21, not fixed (behavioural, Harris's call).** `_buildCurriculumAddendum` keyword-matches the whole assembled request, and the recipe surfaces' static block embeds the literal curriculum key list and cut vocabulary. So `sauteing`, `braising`, `julienne`, `dice`, `food_storage` and `leftovers` are present on **every** recipe-surface call regardless of what the user asked for, and both surfaces always pull the same few drawers from keyword noise rather than relevance. The 2026-08-21 prompt-ordering fix deliberately **preserved** this (it passes the static block into the match text) so that an ordering change stayed an ordering change — fixing it alters what reaches the model. Related to item 9.

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

- **`docs/DECISIONS.md` and `docs/CHANGELOG.md` exist alongside this file.** DECISIONS.md holds binding product/architecture decisions and their reasoning (not descriptions of current code). CHANGELOG.md holds completed work and full session history, newest first. Neither is auto-loaded — read on request or when a task needs history/reasoning this file deliberately omits to stay small.
- **CLAUDE.md is authoritative for Roadmap item numbering.** If Harris refers to an item by a number that doesn't match what's actually here, stop and ask — don't guess which item was meant.
- **Locate code by content/class name, not filename** — the Dreamflow-export filename-shuffling issue was checked and is NOT present in this repo, but this remains the safer default if it's ever in doubt again.
- **Supabase CLI is authenticated**, and **linked to DEV** (ref `suuafglvrxrllnhipkiv`) — see the standing note further down; it is deliberately NOT linked to production. `supabase db push --linked` applies migrations directly to **dev** and is **allowed without confirmation** as of 2026-08-22 (`.claude/settings.json`): `supabase link`/`unlink`/`projects` are denied, which mechanically pins `--linked` to dev, so prod is unreachable by this route. Production schema changes remain stop-and-report. `supabase functions deploy <name> --project-ref xwugnhzlnfgmczkbbcbh --use-api` deploys Edge Functions directly — the `--use-api` flag is required on this machine (no Docker/Podman installed, so the default Docker-based bundler fails). The CLI hardcodes `supabase/functions/<name>/index.ts` relative to the project root, no flag to point elsewhere — any edge function brought into CLI-managed deploys goes there, no second copy anywhere else. `supabase functions --help` lists no `logs` subcommand — read Edge Function logs via Dashboard → Edge Functions → Logs. **There is no `db query` subcommand** in the installed CLI (2.110.0) — this file claimed there was, and that was wrong; `db dump` needs Docker, which isn't installed either. For read-only checks without Docker use `supabase inspect db table-stats --linked` (real query: tables + row counts), `supabase migration list --linked`, or probe PostgREST directly with the committed dev publishable key (404 `PGRST205` = table gone; `?select=<col>&limit=0` returning 200 vs 400 = column exists or not). Reading `pg_policies`/`pg_constraint` still needs the Dashboard SQL editor.
- When a fix touches a Supabase Edge Function, give exact code plus explicit deployment steps and confirm the deploy actually happened — never assume it's live until confirmed via `supabase functions list` (check `version`/`updated_at`) or Harris's own confirmation.
- When something seems like it "should already be fixed" per this document but live behavior contradicts it, verify the actual current source first — don't assume regression, and don't assume the documented fix is stale either. Check before concluding either way. (This exact convention is what caught the Pluralization Audit and the Design Polish backgroundColor batch both already being silently completed — see `docs/CHANGELOG.md`, 2026-08-17.)
- Prefer running `flutter analyze` and any available tests after changes.
- **Live-testing convention**: run a single `flutter run -d chrome --web-port=8765` in the background, have Harris test in that one tab. After code changes, kill the process (`netstat -ano | findstr ":8765"` → `taskkill //PID <pid> //F`) and relaunch fresh on the same port rather than hot-reloading. Keep it to one running instance, same port, always — a second instance on a different port has caused real confusion (Harris testing a stale tab, wrongly concluding a fix hadn't landed).
- No browser automation (`claude-in-chrome`) was available as of the last check — if it becomes available, that's strictly better for anything visual, but check rather than assuming it's still unavailable by default.
- Six Swiss-worded strings in onboarding and the paywall are deliberate and locale-dependent. They are not a bug. Do not "fix" them. Full context is in `docs/CHANGELOG.md`.
- **The Supabase CLI link points at DEV** (`suuafglvrxrllnhipkiv`), not production — relinked here deliberately 2026-08-17, permanently, precisely so `--linked` lands somewhere harmless by default, matching the app's own default-dev rule (see "Current architecture facts"). `AppEnvironmentConfig`/`OPTIMEAL_ENV` is a separate, client-app-only switch — it has no effect on which project the CLI talks to. **`db pull`/`db push` in this CLI version have no `--project-ref` flag at all** (only `--linked`/`--local`/`--db-url`) — this is a real constraint of the installed CLI, not a choice, and is exactly why the link is kept pointed at dev: those two commands can only ever be run safely via `--linked`. Any operation that must target **production** and takes an explicit `--project-ref` (`functions deploy`, `secrets set`, `projects api-keys`, etc.) should use it explicitly, never rely on relinking back to prod. A **db-level operation against production** (`db push`/`db pull`, which cannot take an explicit ref) is rare enough that it doesn't get a standing procedure — stop and report rather than relink, and let Harris decide case by case. Before ever running `db push`, re-verify the link with `supabase projects list` and confirm the `"linked": true` entry is the one you expect — don't assume it's still dev.
