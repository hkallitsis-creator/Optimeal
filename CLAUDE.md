# OptiMeal — Project Context for Claude Code

## What this is

OptiMeal is a zero-waste, technique-first cooking app with an AI persona called
"Chef Harris." Swiss-first launch, European/global ambitions later. Built with
Flutter/Dart, Supabase (Postgres + Auth + Edge Functions), GoRouter, Provider.
Has a live paywall. Approaching real-tester stage.

This project was previously built and iterated on entirely inside **Dreamflow**
(an AI app-builder chat interface) and has just been exported into this repo so
work can continue with Claude Code directly. That means:

- File names in this repo *should* now match their actual class names, since
  they came from a real export rather than Dreamflow's chat-upload flow. The
  previous working environment had a known, confirmed, permanent quirk where
  uploaded filenames were shuffled and did not match file content (e.g. a file
  named `profile_screen.dart` might actually contain `CulinaryMasterclassScreen`).
  **Verify this is no longer the case** by spot-checking a few files early on —
  if filenames still don't match content, treat that the same way: always
  locate code by class name / content, never trust the filename alone.
- There is no established "single Dreamflow prompt" formatting constraint here.
  Claude Code can just read files, edit them directly, and run `flutter analyze`
  / tests. Work normally — no need to produce paste-able prose blocks.
- **Correction (2026-08-10): the Supabase CLI on this dev machine is already
  authenticated to the live project** (`supabase projects list` returns it;
  ref `xwugnhzlnfgmczkbbcbh`) — it was just never linked to this repo before.
  `supabase link --project-ref xwugnhzlnfgmczkbbcbh` then `supabase db push`
  **was confirmed working this session**: applied both pending migrations
  (`20260728120000_create_user_profiles.sql`,
  `20260810120000_create_api_usage_daily.sql`) directly to the live database,
  verified after via `supabase migration list` showing matching local/remote
  timestamps. So Postgres migrations no longer need manual Dashboard SQL
  Editor paste-and-run — link once, then `supabase db push` going forward.
  (A third migration, `20260811120000_fix_api_usage_daily_grants.sql`, was
  pushed the same way 2026-08-11 — see "Follow-up bug found and fixed
  2026-08-11" in the monetization section below for what it fixed.)
  Always check `supabase migration list` before pushing (idempotent
  `IF NOT EXISTS`/`DROP ... IF EXISTS` guards make re-applying safe, but
  still confirm what's actually pending first) — and per the general
  "hard to reverse / affects shared systems" rule, confirm with Harris
  before pushing schema changes to production, same as any other prod DB
  write. **Confirmed working (2026-08-11)**: `supabase functions deploy
  <name> --project-ref xwugnhzlnfgmczkbbcbh --use-api` deploys Edge
  Functions directly, no Dashboard paste-and-run needed. The `--use-api`
  flag is required on this machine — plain `supabase functions deploy`
  fails because it defaults to a Docker-based bundler and this machine has
  no Docker/Podman installed; `--use-api` bundles server-side instead.
  Verified via `supabase functions list --project-ref xwugnhzlnfgmczkbbcbh`
  showing `version` incremented and `updated_at` matching the deploy time.
  **Path note**: the CLI hardcodes `supabase/functions/<name>/index.ts`
  relative to the project root — there's no flag to point it elsewhere.
  `ask-chef-harris`'s source used to live at
  `lib/supabase/functions/ask-chef-harris/index.ts` — a whole duplicate
  Dreamflow-era Supabase CLI scaffold nested under `lib/` (its own
  `config.toml`, `.temp/cli-latest`, `deno.json`, `.npmrc`), because
  Dreamflow could only write function code locally and had no deploy path
  of its own. **Deleted entirely 2026-08-11** — confirmed via grep that no
  Dart code referenced that path (Flutter never compiles/bundles `.ts`
  files; `ChefService` calls the function by name over HTTP via
  `functions.invoke('ask-chef-harris', ...)`, not by file path) and its
  `config.toml` (`verify_jwt = true`) already matched the live deployed
  state exactly, so nothing was lost. `supabase/functions/ask-chef-harris/index.ts`
  is now the **single real source** — no more sync-by-hand risk. Added a
  minimal `supabase/config.toml` (`verify_jwt = true`) alongside it so
  that setting is explicit for future deploys rather than implicit/
  dashboard-inherited. Any other edge function brought into CLI-managed
  deploys later (e.g. `ai-recipe-precision`, whose source isn't in this
  repo at all yet — see Roadmap item 5) should go straight into
  `supabase/functions/<name>/` — there's no reason to add a second copy
  anywhere else.

## Current architecture facts (confirmed from real source, not assumed)

- **Auth**: Anonymous-by-default (`signInAnonymously()` on startup, in `main()`,
  wrapped in try/catch so it never blocks app startup on failure). Users can
  now optionally link an email + password to their anonymous session via a
  "Secure My Account" flow in the Profile/settings screen, using
  `Supabase.instance.client.auth.updateUser(UserAttributes(email: ..., password: ...))`.
  This preserves `auth.uid()`, so all owned data survives linking. **Confirmed
  working** — tested end to end, email shows attached in Supabase Dashboard →
  Authentication → Users. Apple/Google OAuth linking is NOT built yet (needs
  native iOS/Android capability config, out of scope for a Dreamflow-only fix).
  Known follow-up: the email confirmation link currently redirects to
  `localhost:3000` unless Site URL / Redirect URLs are updated in Supabase
  Dashboard → Authentication → URL Configuration. Longer-term this should be a
  real deep link (`optimeal://` or universal link) so confirmation returns to
  the app itself rather than a browser tab.
- **AI calls**: `ChefService.askChefHarris()` is the single centralized AI
  call for recipe generation and chat. It calls the `ask-chef-harris` Supabase
  Edge Function via `Supabase.instance.client.functions.invoke(...)` — **no
  client-side API key**, confirmed secure (this was previously a live
  vulnerability — a direct `http.post` with an embedded
  `OPENAI_PROXY_API_KEY` via `String.fromEnvironment` — now fixed). The edge
  function itself is a generic OpenAI proxy: it does NOT hardcode any system
  prompt, it just forwards whatever `systemPrompt`/`userMessage` the client
  sends. This means prompt/schema changes for recipe generation are pure
  Dart-side changes, not edge function changes.
- There are TWO other, separate AI-adjacent services, easy to confuse with
  `ChefService`:
  - `AiRecipeService` — calls `ai-recipe-precision` (precision metadata: heat
    spec, salt timing, knife cut spec, Swiss substitutes, base ratios). The
    dead `ai-recipe-voice` call (`getChefHarrisVoice()`) was removed this
    session (2026-08-06) — it was never called from any screen.
  - Do not assume a debug log mentioning `AiRecipeService` means
    `ChefService.askChefHarris` didn't run — they're independent calls that
    typically both fire during recipe generation. In Fridge Clearer
    specifically, they now run **concurrently** (fixed 2026-08-06 — see
    session summary below) rather than sequentially, so one being slow no
    longer means the other is blocked on it.
- **Ingredient data is now consistently structured where it matters.** Every
  recipe-generation flow that can produce structured `{name, amount, unit}`
  ingredients (Fridge Clearer, Custom AI Recipe Creator, Weekly Planner's
  Deal Meal path) does so, and `structuredIngredients`/`basePortions` now
  round-trip correctly through Weekly Planner's Supabase persistence (fixed
  2026-08-06 — previously any planned meal became permanently unscalable the
  moment it was saved and reloaded, silently). The Weekly Planner shopping
  list also now merges/sums same-named ingredients across meals instead of
  listing each meal's items as separate duplicate rows. See session summary
  below for full detail — this was a multi-file fix, not a one-liner.
- **Curriculum content — there are TWO separate, unrelated systems.** Do not
  conflate them:
  1. `chefTechniqueDrawers` / `chefReferenceDrawers` (large `Map<String, String>`
     dictionaries of detailed instructional text, keyed by technique name like
     `stir_frying`, `sauteing`, `food_storage`, `knife_grip_mechanics`, etc.)
     inside `ChefService`. These get keyword-matched against the user's
     request and injected into the AI's system prompt on every
     `askChefHarris` call via `_buildCurriculumAddendum()` — this is the real
     "curriculum drawers" system that actually informs what the AI generates.
  2. `CurriculumLibrary` — a small, separate, hand-curated list of ~8
     `TechniqueLesson` entries (with video/thumbnail URLs, currently
     placeholder `example.com` links) used only by the browsable Techniques &
     Media hub screen. This is NOT used for anything AI-related and should
     stay that way — it's legitimate, separate content for browsing, not for
     the post-cook "What You Learned" recap feature (see session summary
     below) or the "Technique of the Week" home card, both of which use
     system 1 above.
- **Recipes table is currently empty** (confirmed via direct query) — no
  actual leakage occurred despite RLS having been briefly open on it; still
  correctly locked down now regardless (see RLS section below).
- **Paywall is not connected to a real purchase provider.** `isSubscribed` is
  a local `SharedPreferences` boolean with a `// TODO: wire to
  RevenueCat/Stripe in Step 5` still in the code. Not tied to `auth.uid()` or
  any real payment validation. This is a real, currently-unaddressed gap —
  bigger than it looks given the paywall is live. Treat as high priority
  whenever it comes up, separate from the auth-linking work above (linking
  identity does NOT fix this). **This needs a provider decision from Harris
  first** (RevenueCat vs. Stripe, account + product setup in App Store
  Connect/Play Console) — it's blocked on external account setup, not
  something Claude Code can meaningfully implement solo. Don't start this
  without checking in first.
- **The paywall was completely unreachable through normal navigation until
  this session (fixed 2026-08-06, NOT yet live-tested).** `onboarding_screen.dart`'s
  "Skip" button (a primary, always-visible button on onboarding slides 1-3)
  calls `context.go('/paywall')`, but `/paywall` was never registered as a
  route in `nav.dart` and `PaywallScreen` was never imported there — tapping
  Skip hit GoRouter's default "page not found" error screen, a dead end.
  `PaywallScreen` itself was already fully built and correctly self-contained
  (its own close/purchase handlers already navigated home correctly) — only
  the route registration was missing. Fixed by adding
  `AppRoutes.paywall = '/paywall'` and its `GoRoute`. **Verify next session**:
  tap Skip during onboarding and confirm it actually reaches the paywall
  screen now. Also worth asking Harris whether Skip-to-paywall should be the
  *only* entry point, or whether there should be others (e.g. an "Upgrade"
  button in Profile) — that's a product question, not something to decide
  unilaterally.
- **`user_profiles.user_id does not exist` (`42703`)** — a known, non-blocking
  error. `user_profiles`'s real primary key column is `id` (= `auth.uid()`),
  never `user_id`. Some code has a dead fallback path that queries a
  `user_id` column that has never existed on that table. App degrades
  gracefully; worth deleting the dead fallback code eventually, not urgent.

## Monetization / paywall tier structure (decided 2026-08-10 — built against mock/sandbox state)

This is the source of truth for what's free vs. paid. Decided in conversation
with Harris on 2026-08-10, then built the same session — see "Build status"
at the end of this section for exactly what's done vs. still TODO.

**Deliberately deferred**: real Apple Developer / Play Console / RevenueCat
account setup. Harris hasn't cleared the Empyria-vs-OptiMeal trademark
question yet and isn't distributing to real testers yet, so none of that is
worth doing now. Instead, the whole gating/entitlement stack is built and
fully testable against a **local mock entitlement flag** (see
`entitlement_service.dart`) — real accounts get created, and real RevenueCat
keys handed over, only once Harris is actually approaching real-tester
distribution. Do not create real store/RevenueCat accounts unprompted.

**Provider: RevenueCat (confirmed, not Stripe-direct).** Reasoning: Apple/
Google require native IAP (StoreKit/Play Billing) for digital subscriptions
sold inside a native app — App Store Review Guideline 3.1.1 blocks charging
via Stripe directly for that. RevenueCat wraps both platforms' native IAP
behind one API, handles receipt validation/entitlements, free until $2.5k/mo
tracked revenue then 1% — effectively free at current pre-revenue stage.
Apple/Google's own platform cut (15-30%) applies regardless of RevenueCat.

**Tier structure:**

- **Free forever, never gated**: Waste Ledger (including all stats/streaks),
  Cook Mode, basic recipe browsing. This is the core "don't waste food"
  mission and the word-of-mouth engine — explicitly must never be gated,
  including Waste Ledger stats/streaks (gating proof-of-your-own-usage was
  considered and rejected as contradicting the app's premise).
- **Free but usage-capped**: Chef Harris AI chat (5 messages/day, applies
  ONLY to `_ChefSuggestionSheet` in `home_dashboard_screen.dart` — the Home
  "Chef Harris Suggestion" generator), Fridge Clearer AI generation (3 per
  week). Both built and wired. Protects real marginal cost (OpenAI calls) —
  the only tier boundary justified on cost grounds, not value withholding.
  **Explicitly does NOT apply to `_ChefSosSheet`** (Cook Mode's SOS chat,
  same file) — confirmed by Harris 2026-08-10: SOS stays free-forever as
  part of Cook Mode, since asking for help mid-recipe is exactly the moment
  the app needs to be reliable, not the moment to show a paywall.
- **Pro-only**: `CustomAiRecipeCreatorSheet` (Custom AI Recipe Creator), and
  skill-based Smart Suggestions once [[Confidence Climb]] (Retention
  Features Backlog item 2) exists. Both require cook-history data to feel
  valuable, so gating them doesn't feel arbitrary.
- **One exception to the Pro gate**: Custom AI Recipe Creator is usable free
  for the first 2 generations ever (lifetime, not per-week), then converts
  to Pro-only. Gives a real taste of the highest-value feature without
  touching the core free experience or needing a whole-app trial countdown.

**Upgrade prompts — exactly three moments, no others:**
1. Post-cook, after the existing `WasteLedgerCelebrationSheet` →
   `WhatYouLearnedSheet` sequence closes (`one_pan_cooking_roadmap_screen.dart`)
   — a lightweight card (`UpgradePromptSheet`, built), not inserted into
   either existing sheet (keeps Waste Ledger itself untouched per the
   free-forever rule above). People upgrade when they feel successful, not
   when they feel blocked. **Built, not yet live-tested.**
2. The moment someone hits their weekly Fridge Clearer cap. **Built, not
   yet live-tested.**
3. A locked preview of Smart Suggestions, once Confidence Climb exists.
   **Not buildable yet** — Confidence Climb doesn't exist.

**Enforcement mechanism**: `api_usage_daily` Supabase table — migration
written (`supabase/migrations/20260810120000_create_api_usage_daily.sql`),
schema `user_id, feature, usage_date, count` + an `increment_api_usage(p_feature)`
RPC function for race-free increments. **Applied to the live Supabase
project 2026-08-10** via `supabase link --project-ref xwugnhzlnfgmczkbbcbh`
+ `supabase db push` (see "What this is" section at top of this doc for how
that CLI path was discovered/confirmed working). Read/write via
`lib/services/usage_cap_service.dart` (`UsageCapService`), shared by both
AI-cost rate-limiting and paywall-gating checks — one mechanism, not two
competing systems. Fails open (allows the action, logs a debug line) if a
usage check errors, so a transient DB issue never locks someone out of a
feature they're entitled to.

**Current placeholder pricing** (in `paywall_screen.dart`, explicitly marked
`// NOTE: placeholder variables (intentionally easy to A/B later)` — not a
finalized business decision, separate from the tier/gating decision above):
15 CHF/month, annual at 25% off (~135 CHF/year).

**Bundle ID / package name — deliberately still a placeholder.** Both
`ios/Runner.xcodeproj` and Android `namespace`/`applicationId`
(`android/app/build.gradle`) were changed this session from the Flutter
default `com.mycompany.CounterApp` to `com.optimeal.dev.placeholder` (also
updated `MainActivity.kt`'s package declaration to match). This is
explicitly NOT a final decision — Harris is still deciding between OptiMeal
and Empyria branding (trademark check pending on the latter) — and is safe
to keep changing right up until the first real Play Store publish (Android's
`applicationId` can't change after that point; iOS is more forgiving).
Whoever picks up store account setup later must pick the real final value
first and update both project files before creating App Store Connect /
Play Console app records.

**Build status (this session, 2026-08-10)**: tier structure, provider
choice, and the full gating stack are built end-to-end against **mock/
sandbox entitlement state**, real store accounts intentionally deferred.
Done: bundle ID off the Flutter default (see above); `purchases_flutter`
added; `EntitlementService` (`lib/services/entitlement_service.dart`) — real
RevenueCat calls behind empty placeholder API key constants
(`kRevenueCatIosApiKey`/`kRevenueCatAndroidApiKey`), falls back to a local
mock flag (`SharedPreferences` key `isSubscribed`, same one `PaywallScreen`'s
placeholder purchase button already flips) whenever real keys are empty —
this is intentional, not a bug, until real keys exist; `api_usage_daily`
migration written and applied to the live project (see above); `UsageCapService` built;
Fridge Clearer's weekly cap wired with upgrade prompt
(`fridge_clearer_screen.dart`); Custom AI Recipe Creator's 2-free-lifetime-
then-Pro gate wired (`custom_ai_recipe_creator_sheet.dart`); post-cook
upgrade nudge wired (`one_pan_cooking_roadmap_screen.dart`); Chef Harris
chat cap wired to `_ChefSuggestionSheet` only, per Harris's explicit
decision above (`home_dashboard_screen.dart`). **None of this has been
live-tested in a running app yet** — verify next session, same as any
"implemented but never clicked through" item elsewhere in this doc.

Still needed, in order: (1) live-test all four gates (Fridge Clearer cap,
Custom AI Recipe Creator gate, post-cook nudge, Chef Harris chat cap) in a
running app now that the `api_usage_daily` migration is actually applied
(previously untestable — every check 403'd and fell back to fail-open, so
the gates themselves were never really exercised), (2) once Harris is
actually approaching real testers: final bundle ID/package name decision,
then Harris creates Apple Developer + Play Console + RevenueCat accounts
and hands over the real RevenueCat public SDK API keys (iOS + Android) +
entitlement identifier — see Roadmap item 6.

**Live-tested 2026-08-10 (Chrome DevTools, real cook session):** confirmed
`api_usage_daily?select=count...` and the `increment_api_usage` RPC both
403'd against the live Supabase project at that point in the session —
expected, the migration hadn't been applied yet. Also confirmed the
fail-open design actually works in practice: those two 403s did not block
or slow down recipe generation, Cook Mode, or Finish & Plate — everything
else completed normally. **Migration was applied later the same session**
(see "Enforcement mechanism" above) — the 403s should be gone now, but that
specific fix hasn't been re-confirmed live yet (verify next session: same
DevTools Network-tab check, expect 200s). Same session: a full recipe
generation (`ask-chef-harris` + `ai-recipe-precision`) took ~9.4s / ~4.7s
respectively, running
concurrently as expected (2026-08-06 fix) — wall time is bounded by the
slower call, not their sum. This ~6-9s range is current normal, driven by
real OpenAI completion latency through the edge-function proxy with no
response caching yet (see Roadmap item 5) — not a regression to chase.

**Follow-up bug found and fixed 2026-08-11**: those 403s did NOT actually
clear after the migration applied 2026-08-10, contrary to what this doc
predicted — real root cause was different from "migration not applied
yet." The `20260810120000_create_api_usage_daily.sql` migration created
the table, RLS policies, and the `increment_api_usage` function, but never
ran a `GRANT` giving the `authenticated` role table-level SELECT/INSERT/
UPDATE privileges (or `EXECUTE` on the function). **RLS policies and
table-level grants are two separate Postgres mechanisms** — a table can
have perfect owner-scoped RLS policies and still 42501 "permission denied"
for everyone, because RLS only filters rows *after* a grant already allows
the query to run at all. Confirmed via `information_schema.role_table_grants`
against the live project: `user_profiles`/`user_meal_plans` (created
earlier, likely inheriting schema-level default privileges at the time)
had full CRUD grants for `authenticated`, `api_usage_daily` had only
REFERENCES/TRIGGER/TRUNCATE — SELECT/INSERT/UPDATE were simply missing.
Root cause of *why* default privileges didn't carry over to this table
wasn't pinned down, but the fix doesn't depend on that: wrote and pushed
`supabase/migrations/20260811120000_fix_api_usage_daily_grants.sql` with
explicit `grant select, insert, update on public.api_usage_daily to
authenticated;` and `grant execute on function public.increment_api_usage(text)
to authenticated;`. **Confirmed fixed live** — re-queried
`role_table_grants` post-push and saw SELECT/INSERT/UPDATE now present,
and Harris's own live Chrome DevTools screenshot the same session showed
`increment_api_usage`/`api_usage_daily` calls returning clean `200`s.
**Lesson for future migrations on this project**: don't rely on default
privileges applying automatically — include explicit `GRANT` statements
for `authenticated` (and `anon` if a table is ever meant to allow
anonymous-session access beyond what `auth.uid()`-scoped RLS implies) in
every new table migration from now on, rather than assuming Dashboard-era
behavior carries over to CLI-pushed migrations.

This directly unblocks the "live-test all four gates" item at the top of
Roadmap item 6's still-needed list — that testing was previously
impossible (every usage-cap check 403'd and silently fell back to
fail-open, so the gates themselves were never actually exercised even
after the table existed). Worth re-running that full checklist next
session now that the underlying permission bug is actually fixed, not
just the table's existence.

## Curriculum content strategy (decided 2026-08-10 — retired the video-first assumption)

`CurriculumLibrary` (the browsable Techniques & Media hub content — see
"Current architecture facts" above for how this is a completely separate
system from the `chefTechniqueDrawers`/`chefReferenceDrawers` AI-facing
curriculum) was originally shaped as video-first: every `TechniqueLesson`
had a `videoUrl` + `thumbnailUrl`. **Nothing real has ever shipped there —
all 8 entries still used placeholder `example.com` URLs** — so this is a
clean redirect, not walking back a real feature. Decided with Harris
2026-08-10:

- **Primary emphasis stays on text + timing inside Cook Mode itself.**
  That's the actual differentiator — "we tell you why, in the moment, with
  a timer" — not a video library. The Techniques & Media hub is a
  supplementary browsing surface, not where the app's teaching value lives.
- **Where a technique genuinely benefits from a visual, support a short
  sequence of real still photos (3-5 per technique)** instead of video.
  `TechniqueLesson.photoUrls` (`List<String>`) is now the first-class visual
  field — not a video-only shape with photos bolted on.
- **Leave room for an optional external link field** (`externalVideoUrl` on
  `TechniqueLesson`) to curate a real creator's video later, but don't build
  any content for it now — that's a future manual-curation task for Harris,
  not something to scaffold placeholder content for.
- **No vector/animated diagrams for now.** That needs a freelance motion
  designer — out of scope for this phase, revisit only if/when that's
  commissioned.
- `TechniqueLesson` and `TechniquesMediaScreen` must handle a lesson having
  photos, a link, both, or neither — falling back to text-only (title +
  description + breakdown steps) rather than assuming video/photos are
  always present. All 8 current `CurriculumLibrary` entries currently have
  neither (no real photos shot yet, no creator video curated yet) and
  should render correctly in that all-text state.

## Supabase RLS status (as of this handover — verify current state, don't assume)

All of the following were confirmed applied and tested with real policies
(owner-scoped via `auth.uid()`), verified against `pg_policies` directly:

- `user_profiles` — owner-only via `id = auth.uid()`
- `user_meal_plans` — owner-only via `user_id = auth.uid()`
- `shopping_list_items` — owner-only via `user_id = auth.uid()`
- `waste_ledger_events` — owner-only via `user_id = auth.uid()` (pre-existing)
- `user_ledger_totals` — owner read-only via `user_id = auth.uid()` (pre-existing)
- `recipes` — owner-only for rows with a `user_id` set (personal AI-generated
  recipes); public read for rows where `user_id IS NULL` (curated library
  content, if/when that exists)
- `ingredients` — public read-only catalog, no client writes
- `ai_precision_cache` — RLS enabled, **zero client-facing policies at all**
  (intentional — it's a server-only cache, only touched by edge functions
  using the service role key, which bypasses RLS)

Note: there are duplicate/redundant policies on a few tables (both an old
broad "ALL" policy and newer granular per-command policies covering the same
thing) left over from iterative fixes. Harmless — permissive policies OR
together — but worth cleaning up for hygiene when there's a lull.

There is no `deals` table in the actual database — code has a speculative,
gracefully-failing lookup for one (`paywall_screen.dart`-era code, see actual
class names once verified in this repo) that falls back to inferring deals
from `ingredients.badge`. Not a bug, just worth knowing so it isn't
"discovered" again as a missing table.

## Session summary — 2026-08-06 — READ THIS FIRST

A long Claude Code session did a large batch of fixes, one architecture-debt
pass, one new feature, and a general bug-hunt. Below is organized by
**confidence**, since that matters more than a flat changelog: what's
actually been seen working, what was fixed in response to a live bug report
but not re-tested after the fix, and what was implemented but never clicked
through in the running app at all. **Don't assume anything in the second or
third category works until you've actually checked it.**

The post-cook "What You Learned" card feature and the Cook Mode Finish &
Plate bottom-bar states (both described in older versions of this doc as
"actively in progress") are now built, and the two bugs that were blocking
them are fixed and confirmed (see below) — that whole feature area is done,
not in-progress.

### Confirmed working (live-tested this session, or backed by real runtime logs)

- **Onboarding flow end-to-end**, including the new `mounted` guards added
  around its async profile-save/navigation — confirmed via real console logs
  showing multiple successful completions ("Onboarding complete", "Supabase
  upsert success").
- **The curriculum-drawer matching → `WhatYouLearnedSheet` data pipeline** —
  confirmed via real console logs from an actual cook session: a
  braised-chicken-and-cabbage recipe correctly matched `[stir_frying,
  sauteing, pan_searing]` and the sheet resolved 3 lessons. The *data* side
  of this feature works; see below for the rendering bug that was on top of
  it (now fixed).
- **Recipe difficulty now actually reaches the AI.** `chef_service.dart` had
  a fully-written "match recipe difficulty to kitchen confidence" constraint
  (`_recipeDifficultyByKitchenConfidence`) that was never included in the
  `systemPrompt` payload — the user-message told the AI to follow rules that
  didn't exist in what it actually received. Fixed by appending it to the
  system prompt. This is a live AI-behavior change; worth confirming
  generated recipes for "Beginner" vs. "Advanced" kitchen confidence actually
  read as different complexity now.

### Fixed in response to a live bug report — NOT yet re-confirmed after the fix

- **"Yellow line" overflow on `WhatYouLearnedSheet`.** No `SingleChildScrollView`
  wrapping its content — with 2 expandable technique cards, content taller
  than the modal's available space had nowhere to go, triggering Flutter's
  overflow warning stripes. Fixed by wrapping in `SingleChildScrollView`.
- **Resume Cooking banner surviving a finished cook session.**
  `_persistActiveSession()` re-saves progress on every app-lifecycle pause
  (tab switch, backgrounding) as long as cooking had started — and that flag
  is deliberately never cleared after finishing (it's what keeps the Finish
  & Plate UI showing). So finishing correctly cleared the saved session, but
  the next tab-switch silently wrote it right back. Fixed by guarding
  `_persistActiveSession()` with the existing `_ledgerSessionLogged` flag.
- **Start Cooking required scrolling to find.** It was only in
  `_StartCookingCard`, buried below the ingredients checklist. Added it to
  the persistent bottom bar (`_StartCookingBottomBar`) next to SOS, matching
  the pattern already used for Finish & Plate. (The original in-body card
  was left in place too — redundant but harmless.)
- **Onion/garlic counted as "rescued" in Waste Ledger messaging.**
  `LedgerService._pantryStapleKeywords` already existed to exclude long-life
  staples (oil, salt, rice, etc.) from "Nice rescue!" messaging, but didn't
  include onion/garlic/ginger/potato/shallot, which last weeks. Added them,
  with a guard so spring/green onions (genuinely perishable) still count.
- **What You Learned's expanded text was one dense unformatted paragraph.**
  Extracted the parsing/rendering into `lib/widgets/curriculum_drawer_content.dart`
  (shared with the new Technique of the Week feature, see below) — the
  expanded view now renders as labeled bullet sections with
  temperatures/durations bolded inline, parsed from the existing
  `LABEL: sentence. sentence.` drawer format (source text itself untouched,
  since it also feeds the AI prompt).
- **"Got it" button on `WhatYouLearnedSheet` used the wrong brand color**
  (`deepForest` — every other primary button in the app, including the
  sibling "Nice!" button on the Waste Ledger sheet, uses `ctaTerracotta`).
  Fixed to match.

### Implemented this session — compiles clean, but never clicked through in the running app

**Status re-checked 2026-08-11, directly against current source (not
assumed from this doc)** — see the "Status check" list further down for
the full verification, but the short version: ingredient-schema and
Technique of the Week are both still exactly as described below (real,
correct code, still never live-tested end-to-end). Cook Mode step
auto-scroll (further down in this doc, under its own heading) is
**definitively fixed**, resolving the old open contradiction — see that
section for the full trace.

- **Ingredient-schema architecture debt** (was roadmap item 3):
  - Fixed the Cook Mode ingredient checklist keying "prepped" state by the
    *live-rescaled display string* instead of the ingredient's stable name —
    checking an item off, then changing portions, silently un-checked it.
    Also means Cook Mode's checked-state should now actually sync with
    Weekly Planner's shopping-list checkmarks (both key by name now; they
    never matched before since one used a quantity-embedded string).
  - **The big one**: Weekly Planner's Supabase persistence
    (`_cookModePayloadToJson`/`_cookModePayloadFromJson`) only wrote
    `{title, ingredients, kitchen_gear, steps}` — dropping
    `structuredIngredients`/`basePortions`/`description`/`curriculumLessonIds`
    on every save. Any planned meal, from any source, became permanently
    unscalable the moment it was saved and reloaded. Now round-trips fully.
  - Weekly Planner's 3rd "Add meal" fast path (Discount/Deal Meal) never
    asked the AI for structured ingredients at all (prompt only requested
    plain strings) — portion scaling was structurally impossible there, not
    just failure-prone. Prompt + parser now match the other two fast paths.
  - Deleted dead `Recipe`/`RecipeStep`/`.scaledTo()` from `recipe_model.dart`
    (fully unused, would've been a second competing "recipe" concept
    alongside the live `CookModeRecipePayload`/`RecipeIngredient` pattern).
    `RecipeIngredient` itself is very much alive and used throughout.
  - Weekly Planner's shopping list now merges/sums same-named ingredients
    across meals (real qty+unit math where units match, readable combined
    fragments otherwise) instead of listing duplicates.
- **"Technique of the Week" home card** (was roadmap item 4): a compact card
  below the 6-action grid (deliberately not above it — didn't want to undo
  the scroll-fit work, see below) that rotates weekly through all 23
  technique/reference drawer keys (deterministic by ISO week number, no
  stored state) and opens the shared drawer-content sheet on tap.
- **Recipe generation speed** (was roadmap item 5 — this parallelization fix
  is done and confirmed live-tested, but the item itself was reopened
  2026-08-10 with further findings/next steps — see Roadmap item 5 below,
  don't treat this as fully closed): in Fridge Clearer,
  `getPrecisionData` and `askChefHarris` were fully sequential despite being
  completely independent (the recipe prompt never depends on the precision
  result) — now run concurrently. Also capped reference-drawer prompt
  injection at 3 matches in `_buildCurriculumAddendum` (it already capped
  technique matches at 3 but the reference-drawer loop right next to it had
  no cap at all — worst case, one message could inject all 7 reference
  drawers). No edge function changes — still a generic proxy, no caching
  added (would be a separate, bigger piece of work).
- **Home dashboard layout tightening** (small-screen scroll fit): reduced
  `childAspectRatio` 0.78→0.95 plus header/grid/card padding. By the numbers,
  Pixel 7 (412×915) should now fit the header + 6-card grid + bottom nav with
  no scrolling; iPhone SE (375×667) is meaningfully closer but likely still
  needs a little scroll — closing that fully would mean cutting visible
  content (e.g. the diet/allergy chip row), not just tightening spacing, so
  it wasn't done without checking in first. **Not verified against real
  devices**, only worked out from the actual layout code's exact values —
  no browser automation was available this session to check visually.
- **General bug-hunt findings**, beyond the items above:
  - Deleted `lib/screens/dashboard_screen.dart` (`DashboardScreen`) — a
    fully-built duplicate of the home grid, never routed to anywhere.
  - Deleted `lib/screens/checklist_screen.dart` (`ChecklistScreen`) — a
    standalone checklist with fake local-only XP that reset every mount,
    superseded by the real Weekly Planner checklist, never routed to.
  - Deleted `UserProfileController.completeOnboarding()` — never called
    anywhere (onboarding builds its own profile update inline instead).
  - `UserProfileService.save()` caught all exceptions and returned
    normally either way, so if a `SharedPreferences` write ever failed, the
    Profile screen's explicit "Save" button still showed "Profile saved!".
    `save()`/`updateProfile()` now return whether the write actually
    succeeded, and Profile's Save button shows a real error on failure.
    (Left onboarding's own profile-save alone — it has a deliberate,
    already-commented "non-fatal, must still complete onboarding" design.)
  - The paywall-unreachable bug — see "Current architecture facts" above.
  - Checked and found NOT a live issue: `shopping_list_items` Supabase table
    drops `qty` on write (true, but nothing ever reads that column back —
    only `ingredient_name` is ever selected — so it has zero observable
    effect; not worth the churn to fix). The "secure account" confirmation
    UX flagged as possibly-flaky around Supabase's email-confirmation
    setting — but this doc already documents that exact flow as tested
    end-to-end and confirmed working, so trusted that over a code-only guess.

### Cook Mode step auto-scroll — RESOLVED 2026-08-11: definitively fixed, not a bug

The older version of this doc listed this as "not yet started" while later
noting the source looked already wired — an open, unresolved contradiction.
**Resolved 2026-08-11 via a full code trace, not a guess**: both trigger
paths funnel through `_advanceToNextStep()`
(`one_pan_cooking_roadmap_screen.dart`) — the timer-driven auto-advance
(`_onActiveTimerDone` → `_advanceToNextStep`) and the manual "Next Step"
button (`onNextPressed` → `_toggleStepComplete` → `_advanceToNextStep`,
when the active step is the one being marked done). `_advanceToNextStep()`
always calls `_scrollToActiveStep()` via `_postFrame`, which resolves
`_stepKeys[idx].currentContext` and calls `Scrollable.ensureVisible(...)`.
Confirmed each `_stepKeys[i]` is genuinely attached as the `key:` of its
`_CookStepCard`, inside an **eagerly-built** `SliverChildListDelegate.fixed`
(not lazy — so the context always exists once the screen is up), inside a
real `CustomScrollView`. No gaps anywhere in the chain — this is not a bug.
Not separately visually re-confirmed in a running browser (no browser
automation available this session either), but the mechanism is structurally
complete and uses a standard, reliable Flutter API — high confidence.

### What next session should verify first, in order

1. Re-test the two fixed live-reported bugs: yellow-line overflow on What
   You Learned, and the Resume Cooking banner clearing correctly after a
   finished + backgrounded session.
2. Re-test the 4 UX polish items (Start Cooking button reachability,
   onion/garlic no longer in rescue messaging, What You Learned's new
   bulleted formatting, Got it button color).
3. Confirm the paywall is now actually reachable via onboarding's Skip
   button (this was a real, previously-silent gap in the live paywall).
4. Cook a full recipe through Weekly Planner (any of the 3 "Add meal" fast
   paths), save the day's plan, reload the app, and confirm the portion
   stepper still works on that planned meal (this is the persistence fix —
   never actually clicked through, only verified by reading the round-trip
   code both directions).
5. Check the combined shopping list with 2+ meals sharing an ingredient and
   confirm it shows one merged line, not duplicates.
6. Decide on Cook Mode step auto-scroll (see above).
7. Home dashboard scroll fit on a real small phone if possible (SE-class
   screen) — decide whether the current "close but not quite zero-scroll"
   result is acceptable or worth cutting content for.

## Roadmap, in priority order

1. ~~Confirm What You Learned + Finish & Plate fixes~~ — done, see session
   summary above (bugs found along the way are fixed, pending re-test)
2. Cook Mode step auto-scroll — status unclear, see above, needs a decision
3. ~~Architecture debt: ingredient-schema inconsistency + dead
   `ai-recipe-voice` call~~ — done, see session summary above
4. ~~"Technique of the Week" rotating home card~~ — done, see session
   summary above
5. Recipe generation speed — **step (1) shipped 2026-08-11, verdict:
   `max_tokens` alone is NOT the bottleneck — move to step (2) next
   session.** Added `max_tokens: 1200` to the `ask-chef-harris` OpenAI call
   in `supabase/functions/ask-chef-harris/index.ts` (now the single
   source — see path note near the top of this doc), deployed via
   `supabase functions deploy ask-chef-harris --project-ref
   xwugnhzlnfgmczkbbcbh --use-api` — confirmed live via `supabase functions
   list` showing `version: 2` and a matching `updated_at`. Harris then ran
   two real generations in the live app (Chrome DevTools): 16.54s and
   5.92s — too noisy on n=2 to call. **Followed up same session with a
   proper read**: a standalone Node script
   (`time_ask_chef_harris.mjs`, scratchpad — not committed, reproducible
   from the payload shape documented here if needed again) fired 5
   sequential calls directly at the deployed edge function, replicating
   `ChefService.askChefHarris`'s real payload (`_systemPersona` +
   `_curriculumCore` + `_recipeDifficultyByKitchenConfidence` as
   `systemPrompt`, `forceJsonObject: true`, `temperature: 0.25`) with 5
   different dishes but matched-complexity prompts (5 ingredients each,
   same schema block, same portions/time/cookware) so results were
   comparable rather than apples-to-oranges. Result: **7.11s average,
   5.72–9.86s spread, stddev 1.46s** (5/5 succeeded). Modestly below the
   single 9.4s baseline sample, but the decisive finding is that actual
   completions were **1840–2254 chars (~460–565 tokens) — well under the
   1200-token cap**. The cap never actually engages for a typical
   generation, so it structurally cannot explain the faster (or slower)
   runs; the 5.7–9.9s spread is pure OpenAI response-time variance. Per
   the plan agreed with Harris going in: this counts as inconclusive/
   "doesn't move the needle," so **stop tuning `max_tokens` further** —
   it's still a reasonable safety cap against a runaway worst-case
   completion, just not a lever for the typical-case latency Harris is
   actually feeling. Also explicitly re-checked the "is it still running
   sequentially" alternate hypothesis Harris raised: read
   `fridge_clearer_screen.dart` lines 547–559 directly — `precisionCardsFuture`
   and `replyFuture` are both still fired before either is awaited, so the
   2026-08-06 concurrency fix is intact, not regressed; not the
   bottleneck. **Next session: move straight to step (2), the
   `gpt-4o-mini` trial** — compare real outputs side-by-side against
   `gpt-4o` for voice/quality before committing, per the original plan.
   The 2026-08-06 fix
   (parallelized `getPrecisionData`/`askChefHarris`, capped prompt
   injection) is real and confirmed live-tested (~9.4s / ~4.7s running
   concurrently, not sequentially — see monetization section's live-test
   note above), but Harris reported it still doesn't *feel* faster, which
   is expected — that fix reduced wall time from sequential (~14s) to
   concurrent (~9.4s, bounded by the slower call), not down to something
   snappy. Investigated further this session, found:
   - `ask-chef-harris` edge function source is in-repo at
     `supabase/functions/ask-chef-harris/index.ts` (worth knowing — unlike
     most edge functions, this one *is* checked in, not just
     Dashboard-only). It calls OpenAI `gpt-4o`, **no `max_tokens` cap, no
     caching, not streamed** — a single blocking request/response. This is
     the actual critical-path call (always the slower of the two, so it's
     the only one worth optimizing — speeding up `ai-recipe-precision`
     alone wouldn't move total wait time since they run concurrently).
   - `ai-recipe-precision`'s edge function source is **not** in this repo
     (only `ask-chef-harris`'s is) — couldn't inspect its model/config
     directly.
   - The `ai_precision_cache` table (see RLS section above) is **confirmed
     actually in use**, not dead: 38 real rows via `supabase db query
     --linked`, most recent from earlier today (2026-08-10). So
     `ai-recipe-precision` already gets real caching benefit on repeat
     ingredient combos — this is a second, independent confirmation that
     `supabase db query --linked "<SQL>"` works for read-only checks
     against the live project without needing Docker/local Postgres.
   - Recommended next steps, in order: (1) ~~cap `max_tokens` on the
     `ask-chef-harris` OpenAI call~~ — **done 2026-08-11, see above**; (2)
     ~~trial swapping `gpt-4o` → `gpt-4o-mini`~~ — **done 2026-08-11,
     verdict: keep `gpt-4o`, see below**; (3) still NOT a quick
     win, re-investigated 2026-08-11: streaming `ask-chef-harris`.
     **Revised understanding** — the transport layer is more feasible than
     first thought: `functions_client` (the package behind
     `Supabase.instance.client.functions.invoke`) has real built-in SSE
     support (confirmed by reading its actual source,
     `functions_client-2.6.4/lib/src/functions_client.dart` — a
     `text/event-stream` response hands back the raw byte stream directly
     instead of buffering it). **But three other genuine sub-problems
     remain, one of which is out of scope for a quick change**: (a) the
     edge function needs to call OpenAI with `stream: true` and forward
     the SSE stream through Deno — tractable; (b) the package's own doc
     comment is explicit that true incremental delivery **on web**
     requires adding the `fetch_client` package and reconfiguring
     `Supabase.initialize(...)` to use it as the **global** HTTP client —
     since this app is currently only tested via `flutter run -d chrome`
     (no Mac/Android device connected on this machine, per Roadmap item
     8), that's a real blast-radius change touching every Supabase call
     (auth, postgrest, storage, realtime), not a local tweak; (c) still
     unchanged from the original note — `forceJsonObject: true` means
     OpenAI streams raw JSON text token-by-token, not structured deltas,
     so progressively rendering "title first, then steps" needs either a
     tolerant partial-JSON parser or a redesigned line-delimited output
     schema (which would itself need output-format quality testing,
     losing the "zero quality risk" framing), plus the recipe screen
     currently parses one complete JSON string at the end and would need
     real UI work to render partial state. Verdict unchanged: worth doing
     as a real, dedicated future feature — not something to half-build
     inside this latency investigation.
   - **`gpt-4o` vs `gpt-4o-mini` side-by-side trial, done 2026-08-11 —
     verdict: keep `gpt-4o`.** Whitelisted an optional `model` field on
     `ask-chef-harris` (`supabase/functions/ask-chef-harris/index.ts`,
     restricted to `['gpt-4o', 'gpt-4o-mini']` so a caller can never point
     the proxy at an arbitrary model string; defaults to `gpt-4o` when
     omitted, so this is backward-compatible and left in place — harmless,
     useful for any future re-test) and deployed it (now `version: 3`).
     Ran the same 3 comparable dishes through both models via a standalone
     script and built a side-by-side comparison page:
     https://claude.ai/code/artifact/1bfc279f-a030-4921-b6de-6b769709b4b8
     (private artifact — full recipes, timings, and the recommendation
     below). **Speed**: `gpt-4o-mini` averaged 7.55s vs `gpt-4o`'s 8.25s on
     this 3-run sample — about 0.7s faster, smaller than the ±1.5s
     run-to-run noise already established for `gpt-4o` alone, i.e. not a
     clear win. **Quality**: consistent, real voice cost across all 3
     dishes — `gpt-4o-mini`'s recipe descriptions lean generic ("deliciously
     simple!", "in no time!") where `gpt-4o` reaches for something specific
     to the dish ("thyme makes it timeless"); steps are also a shade less
     technically precise (e.g. `gpt-4o` gives "skin-side down, 4 min, then
     flip," `gpt-4o-mini` gives the same step as a looser "sauté until
     browned (~5 min)"). One `gpt-4o-mini` run also had a minor
     schema-consistency slip (a step said "season with salt and pepper"
     but neither was in that run's ingredients list). Given Chef Harris's
     voice/personality is core to the app's identity, not just flavor
     text, a ~0.7s gain isn't worth trading it away — **not switching the
     default.** Move to step (3) (streaming) only as a real future
     project, not urgently — see above.
   - `supabase functions deploy <name>` **confirmed working 2026-08-11**
     with the now-linked CLI — see "Correction 2026-08-10" note near the
     top of this doc for the exact command and the required `--use-api`
     flag.
   - **`ai-recipe-precision` timed the same way, 2026-08-11**: 5-run
     average **3.32s** (2.44–4.17s spread, stddev 0.70s), clearly faster
     than `ask-chef-harris`'s 7.11s average. Since the two run concurrently
     (confirmed intact, see above), the user's actual floor is set by
     `ask-chef-harris` — `ai-recipe-precision` is not worth optimizing
     further right now; it's already well under the other call's time.
   - **Prompt input size measured directly, 2026-08-11**, via a standalone
     script (`tool/measure_prompt_size.dart`, deleted after use — imported
     the real `chefTechniqueDrawers`/`chefReferenceDrawers`/etc. maps and
     ran an exact copy of `_buildCurriculumAddendum`'s matching logic
     against 7 realistic Fridge Clearer-style prompts). Findings: the
     fixed system prompt (persona + curriculum core + difficulty rules) is
     **7095 chars (~1774 tokens)** on its own — a substantial baseline
     even before any per-call addition. The curriculum addendum (injected
     into the **user** message, not the system prompt — worth correcting
     that assumption for next time) added another 0–2009 chars (~0–500
     tokens) depending on genuine keyword matches. Combined input landed
     around **7900–9900 chars (~2000–2500 tokens)** — real, but not large
     enough on its own to be the dominant driver of the 5.7–9.9s
     *completion*-inclusive latency measured earlier (prompt/input
     processing is materially faster than output decode for GPT-4o-class
     models; the output side is still the bigger lever).
   - **Real bug found and fixed along the way, 2026-08-11**: the
     `central_european` cuisine-profile match in `_buildCurriculumAddendum`
     triggered on the bare word `'swiss'` — but `FridgeClearerScreen._buildCookModePrompt`
     always includes the literal boilerplate phrase "Context (Swiss home
     kitchen):" (correct, since this is a Swiss-first app), so that cuisine
     block was being injected into **every single Fridge Clearer call**
     regardless of what was actually being cooked — not genuine relevance
     matching, just an accidental self-match on the app's own boilerplate.
     Confirmed via the measurement script: 3 of 7 test prompts matched
     nothing else and still got a 1021-char addendum purely from this.
     Fixed in `chef_service.dart`'s `cuisineAliases` map: replaced the bare
     `'swiss'` trigger with more specific phrases (`'swiss cuisine'`,
     `'swiss dish'`, `'swiss recipe'`, `'swiss classic'`) so genuine "make
     this taste Swiss" intent still matches without the unconditional tax.
     Re-ran the measurement script after the fix — the 3 previously-affected
     prompts now correctly show 0-char addenda. This was also a mild
     quality/correctness issue independent of latency: every recipe
     (including e.g. an Asian stir-fry request) was getting a central-
     European cuisine profile block injected into its prompt for no reason.
   - **Added permanent lightweight instrumentation**: `ChefService.askChefHarris`
     now `debugPrint`s the real `systemPrompt`/`userMessage` char counts (and
     an estimated token count) right before every real call, so future
     prompt-bloat regressions are visible in the console without needing a
     one-off measurement script again.
   - **Perceived-latency UI improvement, 2026-08-11 (small, parallel task,
     not blocking the investigation above)**: `_InlineGeneratingCard` in
     `fridge_clearer_screen.dart` (the loading card shown during Fridge
     Clearer generation) was a static "Chef Harris is thinking…" line with
     a spinner. Converted to a `StatefulWidget` that rotates through 4
     status messages ("Checking your ingredients…" → "Thinking through
     techniques…" → "Balancing the flavors…" → "Plating the details…")
     every ~2.2s via a `Timer.periodic` + `AnimatedSwitcher` crossfade.
     Doesn't change actual latency — improves how the existing ~7-10s wait
     *feels*. Only wired into Fridge Clearer so far (the flagship AI-
     generation flow this whole investigation centers on) — the same
     pattern could be reused for the other `askChefHarris` call sites
     (Custom AI Recipe Creator, Weekly Planner, home dashboard Chef
     Suggestion, Cook Mode SOS) if it reads well here first; deliberately
     kept local to this file rather than extracted into a shared widget
     until there's a second real call site for it.
6. Real payment provider integration (RevenueCat, confirmed 2026-08-10) —
   tier structure, pricing logic, and the full gating stack are now built
   end-to-end against mock/sandbox entitlement state (same session) — see
   "Monetization / paywall tier structure" above for the full spec and
   build status. Real Apple Developer + Play Console + RevenueCat account
   setup is **deliberately deferred by Harris's own choice**, not blocked —
   revisit once he's actually approaching real-tester distribution and has
   resolved the OptiMeal-vs-Empyria trademark question. Until then: (a) the
   `api_usage_daily` migration still needs manual application to the live
   Supabase project, (b) none of the gating/mock-purchase flow has been
   live-tested in a running app yet. The route-to-paywall bug is fixed.
7. **Post-cook shareable recap card** (added 2026-08-10) — a growth/
   acquisition feature, not just retention: after a cook session completes
   (same moment as the Waste Ledger celebration sheet + What You Learned
   sheet), offer a lightweight, visually clean, screenshot-worthy card
   summarizing that session ("I rescued 4 ingredients and learned to
   braise") with a native share-sheet action, styled to look good posted as
   a share/story rather than just an in-app confirmation. Reuses data
   already available at that point — ingredients rescued from
   `LedgerService.logCompletion`'s per-session result, technique(s) learned
   from the same curriculum-matching pipeline that already feeds
   `WhatYouLearnedSheet` — no new data capture needed, so this is low
   effort. Natural extension of "Rescue Streaks You Can't See Until You
   Look" in the Retention Features Backlog below — keep them visually and
   conceptually consistent when that item gets built. Slotted in roughly
   alongside/just after the payment-provider scaffolding work (item 6
   above), not blocked by it.
8. Apple/Google OAuth account linking (needs native iOS/Android config —
   also likely blocked on this being a Windows dev machine with no Mac for
   iOS and no Android device/emulator currently connected; check `flutter
   devices` before assuming either platform is testable here)
9. Deep link fix for the email-confirmation redirect (see Auth section
   above) — same native-platform-config caveat as #8
10. Lower priority / not urgent: rate limiting on Edge Functions, separate dev
    vs. production Supabase projects before real testers, privacy policy
    covering Swiss FADP + EU GDPR, Supabase Storage bucket policies (once
    profile photos/recipe images are added), duplicate RLS policy cleanup
    (cosmetic, see RLS section above)

## Retention Features Backlog

**Status as of 2026-08-11: items 1, 2, and 4 are built.** Harris explicitly
chose to build these ahead of the old "slot in after payment integration"
plan this session, while keeping all paywall/RevenueCat work (roadmap item
6) deliberately paused and untouched — don't read the code changes below as
implying that pause lifted. Items 3 and 5 remain explicitly on hold (see
below) — not just "not started yet," but a decision Harris hasn't made.

1. **Fridge Countdown — BUILT 2026-08-11.** New `fridge_items` table
   (`supabase/migrations/20260811130000_create_fridge_items.sql` — id,
   user_id, ingredient_name, added_date, estimated_shelf_life_days; RLS
   owner-only **plus explicit GRANTs**, applying the lesson from the
   `api_usage_daily` grants bug earlier this session so it wasn't repeated
   here — confirmed via `information_schema.role_table_grants` after push).
   `FridgeCountdownService` (`lib/services/fridge_countdown_service.dart`):
   CRUD against the table, plus a local keyword-based shelf-life estimator
   (same style as `LedgerService._pantryStapleKeywords`) that pre-fills the
   add-item form. `FridgeItem.isExpiringSoon` = 2 days or fewer remaining
   (including overdue). `FridgeCountdownSheet`
   (`lib/widgets/fridge_countdown_sheet.dart`): item list with a
   color-coded freshness bar per item (red/amber/green — deliberately
   separate semantic colors from the app's brand accent), an add-item
   mini-sheet, delete, and a "Use Tonight" button per item. "Use Tonight"
   builds an urgency-framed prompt (star ingredient, explicit "use it
   tonight/today" framing) and calls `ChefService.askChefHarris` directly
   (not the full `FridgeClearerScreen` UI — reused the same
   parse/curriculum-tag/`GeneratedRecipeActionsSheet` pattern already
   established by `CustomAiRecipeCreatorSheet`), gated under the **same**
   `UsageFeature.fridgeClearerGeneration` weekly cap as Fridge Clearer
   itself (deliberate — same marginal AI cost, avoids a cap-bypass
   loophole). Home dashboard: a terracotta "N items expiring soon" chip
   (`_FridgeCountdownChip`, `home_dashboard_screen.dart`) shown only when
   count > 0, placed right after the 6-action grid. **Compiles clean
   (`flutter analyze`: 0 errors), confirmed booting without runtime errors
   against the live Supabase project this session — not yet clicked
   through by Harris.**

2. **Confidence Climb — BUILT 2026-08-11.** Confirmed first that the
   kitchen-confidence prompt fix (difficulty rules reaching the AI) is
   still solid — verified directly in `chef_service.dart` while adding the
   prompt-size debugPrint earlier this session; unchanged. Turned out
   `curriculumLessonIds` (the technique-tagging this item asked for) was
   **already** flowing onto every `CookModeRecipePayload` at generation
   time, via `ChefService.matchedCurriculumDrawerKeys` — confirmed at all
   three generation call sites (Fridge Clearer, Custom AI Recipe Creator,
   Weekly Planner) and confirmed it round-trips through
   `CookSessionStorageService`'s cook history JSON (de)serialization. So
   **no new tagging logic was needed at all** — `ConfidenceClimbService`
   (`lib/services/confidence_climb_service.dart`) is pure aggregation over
   `CookSessionStorageService.loadCookHistory()` (the 20-entry rolling
   history, not just the 3-item Recently Cooked UI list). Two thresholds
   (both my call, both easy to retune — plain constants in the service):
   celebration line at **3+ reps of the same technique within the current
   calendar month** (e.g. "3rd time this month using Braising — you're
   building real knife + heat control."), tier-up offer at **5+ reps of
   ANY tagged technique** (broad kitchen mileage, not mastery of one move).
   Tier-up is gated one-time **per tier transition** (SharedPreferences
   flag keyed by the *current* tier name, so declining doesn't block a
   later, real offer for the *next* tier). Celebration line renders inside
   the existing `WhatYouLearnedSheet` (new optional `confidenceLine` param
   — the natural fit, since that sheet is already about techniques
   practiced) rather than a new sheet. Tier-up is its own step
   (`ConfidenceTierUpSheet`, `lib/widgets/confidence_tier_up_sheet.dart`,
   modeled directly on `UpgradePromptSheet`'s accept/decline pattern),
   shown after `WhatYouLearnedSheet` closes, updating
   `UserProfile.kitchenConfidence` via `UserProfileController.updateProfile`
   on accept. **Compiles clean, confirmed booting without runtime errors —
   not yet clicked through by Harris** (would need 3+ real cook-history
   entries with matched techniques in the current month to see the
   celebration line, or 5+ to see the tier-up offer).

3. **Sunday Reset — still on hold, decision explicitly deferred by Harris
   2026-08-11.** Originally gated on "recipe generation speed confirmed
   fixed." That investigation concluded this session (see Roadmap item 5):
   the honest floor is **~7-10s per generation**, `max_tokens` capping and
   the `gpt-4o-mini` trial didn't move it further, and the only real lever
   left (streaming) is a genuine future project, not a quick fix.
   Perceived-speed work shipped (rotating status card), but actual
   generation time is not going lower without that larger project. Harris
   has NOT yet decided whether ~7-10s × 5 batched calls (a real 35-50s
   wait) is acceptable for Sunday Reset — **do not start this until he
   explicitly says so**, even though the original blocking condition
   ("speed confirmed fixed") is technically now answered (just not
   answered *favorably*).

4. **Rescue Streaks / "Your Month" card — BUILT 2026-08-11** (Harris's
   session instructions renumbered this ahead of Sunday Reset/Mid-Cook;
   kept as backlog item 4 here since that's still its place in the
   original priority list). Deliberately NOT a visible streak counter and
   deliberately no framing around missed days/gaps — a positive recap, not
   a guilt mechanic, per Harris's explicit instruction. Pure aggregation,
   no new capture logic: `LedgerService` gained one new **read** method,
   `getMonthlyIngredientsRescuedCount()` — same local weekly-events store
   `getWeeklySummary()` already uses (90-day retention comfortably covers a
   month), just filtered by calendar month instead of week-start.
   "New techniques this month" and "most-cooked technique" are both
   computed by `YourMonthCard` (`lib/widgets/your_month_card.dart`)
   directly from `CookSessionStorageService.loadCookHistory()`'s
   already-tagged `curriculumLessonIds` (same data Confidence Climb uses —
   "new" = technique ids seen this month but not in any earlier history
   entry within the 20-entry cap; "most-cooked" = the technique with the
   most reps this month, title resolved via the existing
   `resolveDrawerEntry` helper). Note: the original backlog example said
   "most-cooked **category**," but there's no cuisine/category field
   anywhere in the actual data model — used "most-cooked **technique**"
   instead, the closest thing that's genuinely computable from existing
   data, rather than inventing new categorization logic. Dismissible via a
   SharedPreferences flag keyed by year-month (`your_month_dismissed_v1_
   YYYY-MM`), so it reappears fresh next month even if dismissed this one.
   Hides itself entirely (renders nothing) if there's nothing positive to
   report yet. Placed on Home right after the Fridge Countdown chip, before
   Technique of the Week. **Compiles clean, confirmed booting without
   runtime errors — not yet clicked through by Harris.**

5. **Ask Chef Harris Mid-Cook — still on hold, decision explicitly deferred
   by Harris 2026-08-11.** Same reasoning as Sunday Reset above: originally
   gated on confirmed-fast, ideally-streaming generation. The ~7-10s floor
   is now the confirmed, understood reality (not an open question anymore),
   but Harris hasn't decided whether that's acceptable for a feature that
   "needs to feel instant since it's used mid-task." **Do not start until
   he explicitly says so.**

## Design Polish Backlog (identified 2026-08-11 — none of it built yet)

Harris asked for a design/polish pass this session; findings were captured
but the actual visual changes were deliberately NOT made — this was a
wrap-up session, so this is a clean punch list for next time, not
half-finished work. No `claude-in-chrome` available this session either
(declined again) — so nothing here has a before/after screenshot yet; get
one when this is actually picked up.

1. **Technique of the Week card shows raw drawer text, not a teaser.**
   It's currently rendering `chefTechniqueDrawers`/`chefReferenceDrawers`
   content directly — that text is written in the
   `RATIOS/HEAT/DONENESS`-style compact format meant for the AI prompt, not
   for a person browsing Home. Fix the same way `WhatYouLearnedSheet`
   already handles this exact content type: a short teaser (title + first
   sentence) by default, full technical breakdown behind a tap-to-expand
   disclosure. **Reuse the existing parsing** — `_parseDrawer` and the
   `DrawerCard`/expand-on-tap pattern in
   `lib/widgets/curriculum_drawer_content.dart` already solve this exact
   problem; don't write new extraction logic.
2. **Technique of the Week card has no green accent.** Every other card on
   Home carries some of the app's actual brand green
   (`AppDesignTokens.deepForest`, `#1E3A2B` — not a generic green) except
   this one, which reads as visually disconnected from the rest of the
   page. Add a touch of it (icon color, border tint, something restrained
   — not a full recolor).
3. **Home dashboard 6-card grid feels flat/corporate.** Small icon-in-a-box
   on uniform cream, one generic description line each
   ("Plan Mon–Sun & export shopping lists"). Two independent angles Harris
   flagged, either or both worth trying: (a) larger/bolder icons, and/or a
   subtle colored background wash on 1-2 of the most-used cards (Fridge
   Clearer, Weekly Plan & Shop) instead of uniform cream, for visual
   hierarchy; (b) rewrite the generic description copy into shorter lines
   with more of Chef Harris's established personality, without making the
   functional copy confusing (people still need to know what tapping the
   card does).
4. **Onboarding background doesn't match Home's background.** Home uses
   `AppDesignTokens.backgroundSage` (`#E8EFEA`). Onboarding screens
   currently read as a different/lighter green. **Not yet root-caused** —
   next session, find wherever onboarding's background is actually defined
   and confirm whether it's referencing a different token, a different
   hardcoded value, or something theme-level, then point it at the same
   `backgroundSage` token Home uses.
5. **Post-cook share card (`PostCookShareCardSheet`) color sourcing needs
   confirming.** The bold, high-contrast dark-green direction is correct
   and intentional for a shareable social image — **don't change the
   visual approach** — just confirm its dark green is actually pulled from
   `AppDesignTokens` (presumably `deepForest`) rather than a separate
   hardcoded hex value that happens to look similar. **Not yet checked.**
6. **Paywall/upgrade sheet background falls back to an unstyled default.**
   Root-caused this session: `PaywallScreen` itself (the full `/paywall`
   route) is fine — its `Scaffold` correctly uses
   `AppDesignTokens.backgroundSage` (`paywall_screen.dart:68`). The actual
   problem is `UpgradePromptSheet`
   (`lib/widgets/upgrade_prompt_sheet.dart`): its own content correctly
   wraps in `Material(color: AppDesignTokens.surfaceCream, ...)`, but
   `UpgradePromptSheet.show()` calls `AppBottomSheet.show(...)` **without**
   passing a `backgroundColor` — so `AppBottomSheet`'s default
   (`theme.colorScheme.surface`, a plain white/grey per its own
   implementation in `lib/widgets/app_bottom_sheet.dart`) shows through as
   the outer modal sheet's chrome (rounded corners, edges, drag-handle
   area) around the correctly-cream inner content. Fix: pass
   `backgroundColor: AppDesignTokens.surfaceCream` (or equivalent) at the
   `AppBottomSheet.show` call site in `UpgradePromptSheet.show()`.
7. **Chef Harris Suggestion sheet has the same root cause, but worse.**
   `_ChefSuggestionSheet` (`home_dashboard_screen.dart`,
   `_ChefSuggestionSheetState.build()`) returns a bare `Padding(...)` with
   **no `Material` or background color wrapper anywhere in its own widget
   tree** — unlike `UpgradePromptSheet`, which at least has a correctly-
   colored inner `Material`. It is 100% dependent on `AppBottomSheet`'s
   unstyled default, and the call site
   (`HomeDashboardScreen._showChefSuggestion`) doesn't override it either.
   Same fix shape: either pass `backgroundColor` at the `AppBottomSheet.show`
   call site, or wrap the sheet's own content in a `Material`/`Container`
   using `AppDesignTokens.surfaceCream`, matching the pattern every other
   sheet in the app already uses.

**Worth checking while in this area next session**: given items 6 and 7
share the exact same root cause (an `AppBottomSheet.show()` call site
omitting `backgroundColor`), it may be worth grepping all `AppBottomSheet.show`
call sites in one pass rather than fixing these two in isolation — there
could be other sheets with the same silent fallback that just haven't been
flagged yet.

## Working conventions

- **Locate code by content/class name, not filename**, until you've confirmed
  the export gave files their correct real names (see top of this doc).
- When a fix touches a Supabase Edge Function, give exact code plus explicit
  manual deployment steps (Dashboard → Edge Functions → Deploy → Via Editor).
  Never assume it's live until Harris confirms manual deployment happened.
- When something seems like it "should already be fixed" per this document
  but the live behavior contradicts it, verify the actual current source
  first — don't assume regression, and don't assume the documented fix is
  stale either. Check before concluding either way.
- Prefer running `flutter analyze` and any available tests after changes,
  something that wasn't possible at all in the previous Dreamflow-chat
  workflow — use this now that it's available.
- **Live-testing convention**: run a single `flutter run -d chrome
  --web-port=8765` in the background, and have Harris test in that one
  Chrome tab. After code changes, kill that process (`netstat -ano | findstr
  ":8765"` → `taskkill //PID <pid> //F`) and relaunch fresh on the same port
  rather than hot-reloading — there's no scriptable way to send a hot-restart
  keystroke to a backgrounded process here, and running a second instance on
  a different port caused real confusion earlier this session (Harris tested
  the stale tab and reasonably assumed a fix hadn't landed). Keep it to one
  running instance, same port, always.
- No browser automation (`claude-in-chrome`) was available this session —
  Harris declined the extension. Visual/layout claims this session (e.g. the
  Home dashboard scroll-fit numbers) were worked out from exact layout code
  values against known device viewport sizes, not visually confirmed. If
  `claude-in-chrome` becomes available in a future session, that's strictly
  better for anything visual — but don't assume it's off-limits again by
  default; check.
