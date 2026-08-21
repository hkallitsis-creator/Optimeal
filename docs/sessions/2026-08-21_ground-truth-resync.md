# Session — Ground-truth resync (2026-08-21)

Read-only except the two doc commits in step 5. No dev DB access in scope.
No prod contact. Repo HEAD at session start: `10b1d7e`, working tree clean.

---

## Prompt (verbatim)

```
AUTONOMY: Full file/test/git permission. No confirmation questions.
STOP CONDITIONS: Prod Supabase = stop-and-report always. No dev DB access
in scope this session. Spec ambiguity = note and continue, never guess.
READ-ONLY except the two doc commits in step 5.

TASK:
1. Run `git log --oneline 10b1d7e~10..HEAD` and report verbatim.
2. Report CLAUDE.md's current-state / recent-changes / open-items sections.
3. Bookmark fix check: grep for bookmark/save capability on freshly
   generated (not-yet-persisted) recipes — the fix would let a recipe
   just returned from generation be saved before any other action.
   Report exists (file/line evidence) or absent.
4. Cooking-times table check: grep the repo (lib/ and docs/) for any
   committed cooking-times data — signed table, Dart map, or doc.
   Report exists (path) or absent.
5. Doc commits (the only writes):
   a. Create docs/sessions/2026-08-21_prompt-caching-numbers.md containing
      the numbers-session prompt and your full report from that session
      verbatim (both are in your context/history; if not, say so and
      commit a placeholder noting they'll be pasted in).
   b. Create docs/sessions/2026-08-21_ground-truth-resync.md containing
      this prompt verbatim plus your report below.
   Commit both with clear messages. Do not push unless push is your
   normal flow for doc commits — if unsure, commit only and say so.
6. Confirm test count and flutter analyze count unchanged (177 / 54).

Report verbatim: git log, CLAUDE.md state, bookmark finding, cooking-times
table finding, doc commit hashes, test/analyze counts, git status.

PERMANENT RULE (applies to this and every future session): every prompt
received and every report produced gets committed under docs/sessions/
as part of the same session.
```

---

## Report

### 1. `git log --oneline 10b1d7e~10..HEAD` — verbatim

```
10b1d7e review: cross-build integration tests, two dead-code fixes, CLAUDE.md accuracy
cfaa1f6 docs: record the saved-recipes UI; correct two stale CLI claims in CLAUDE.md
a81ad64 feat: My recipes screen, universal bookmark, planner third source
5cae722 docs: record recipe-carried provenance, the dev DB cleanup, and saved_recipes
edd429e feat: saved_recipes table (dev) + SavedRecipesService data layer
1bd00c8 fix: rescue provenance travels with the recipe, not the launch surface
0d55add docs: record Home hub, nav-bar removal, and the Home first-frame crash fix
0e695c7 feat: remove bottom nav app-wide, rebuild Home as a one-screen hub
a53fe79 fix: defer GoRouterState access to post-frame (Home crash) + landmine sweep
cedf753 perf: stable prompt prefix for OpenAI caching, cached-token logging; CLAUDE.md corrections
```

Ten commits, `cedf753` through `10b1d7e`. Note the range `10b1d7e~10..HEAD`
excludes `cedf753`'s own parent and starts *at* `cedf753`, so the
prompt-caching commit is the oldest entry shown.

### 2. CLAUDE.md state

326 lines, five `##` sections plus the title:

| line | section | role |
|---|---|---|
| 1 | `# OptiMeal — Project Context for Claude Code` | title |
| 3 | `## What this is` | orientation |
| 18 | `## Current architecture facts (confirmed from real source, not assumed)` | **current state** |
| 253 | `## Current Supabase RLS state (all public-schema tables have RLS enabled — none exposed with RLS disabled)` | **current state** |
| 285 | `## Open Roadmap` | **open items** (24 numbered) |
| 314 | `## Working conventions` | process rules |

**There is no recent-changes section, by design.** CLAUDE.md's own
convention block states that completed work and session history live in
`docs/CHANGELOG.md` (newest first) and binding reasoning in
`docs/DECISIONS.md`, neither auto-loaded. So "recent changes" is answered
by the git log in §1 and by CHANGELOG.md, not by CLAUDE.md.

**Current architecture facts** — 14 bullets: no-bottom-nav navigation +
depth rule (2026-08-20); Home as a one-screen no-scroll hub (2026-08-20,
with the measured textScale 2.4/2.8/3.2 overflow limit left deliberately
unfixed); rescue provenance carried by `RecipeOrigin` rather than
`CookModeSurface` (2026-08-20); the `cook_mode_recipe_codec.dart` jsonb
codec and the deliberate camelCase/snake_case split against
`CookSessionStorageService`; saved recipes data layer + UI (dev only);
anonymous-by-default auth with optional email linking; `ChefService`
/`ask-chef-harris` as the single AI call; `AiRecipeService`
/`ai-recipe-precision` and its deploy hold; structured ingredient data;
the two unrelated curriculum systems; the empty `recipes` table with
unreachable write grants; the paywall and its `kDebugMode` bypass;
`user_profiles`'s `id` primary key; and the dev/prod environment split
(`OPTIMEAL_ENV`, dev-by-default).

**Current Supabase RLS state** — a 12-row table. Dev is ahead of prod:
dev has 10 tables (`shopping_list_items` and `fridge_items` dropped,
`saved_recipes` added by the 2026-08-20 migrations), prod still has the
original 11. Carries the standing grants-vs-policies lesson (confirmed
four separate times) and notes the dev-only
`waste_ledger_events_source_check` narrowing.

**Open Roadmap** — 24 items. By CLAUDE.md's own labels:

- **Open, flagged HIGH PRIORITY**: 1 (safety validator, pre-launch
  blocker), 2 (`ai-recipe-precision` cost/abuse exposure)
- **Open**: 3, 6, 9, 11, 14, 16, 17, 18, 19, 20, 22, 23, 24
- **Done / closed**: 4, 5, 7, 8, 10, 12, 13, 15
- **Done with named remainders**: 21 (migrations not pushed to prod; the
  "feedback" half never scoped; every user-facing string still a
  `// SIGNED-CONTENT PLACEHOLDER`; no list-row unsave affordance)

**Two items are stale against the actual source** — flagged, not edited,
since this session is read-only outside `docs/sessions/`:

- **Item 6** is written as pending ("Replace the current celebration/
  tier-up copy with…"). The signed wording is **already implemented
  verbatim**: `lib/widgets/what_you_learned_sheet.dart:218` ("Are you
  comfortable with this technique?"), `:232` ("Yes, it's automatic now"),
  `:244` ("Not yet, still takes concentration"), with
  `lib/services/confidence_climb_service.dart:30` feeding it and
  regression tests in `test/widgets/what_you_learned_sheet_test.dart`.
  The item's *other* two halves are genuinely still open: live-testing at
  3+/5+ reps, and the unfiltered `cook_session_history_v1` aggregation.
- **Item 3** says "Not started." Substantially built: closed key lists in
  `lib/data/diagram_keys.dart` (`cutDiagramKeys` 16, `techniqueDiagramKeys`
  5, `allTechniqueDiagramKeys`, `noTechniqueDiagramKey`), the declarable
  `technique_diagram_id` prompt field in both recipe prompt builders
  (`fridge_clearer_screen.dart:242,257`;
  `custom_ai_recipe_creator_sheet.dart:97,110`), and — the surface the
  item calls higher-value — **in-context placement inside Cook Mode is
  live** (`one_pan_cooking_roadmap_screen.dart:586, 2601-2618` renders cut
  and technique diagram pills per step). Three of the 21 diagrams are
  built: `julienne`, `pan_crowding`, `cold_vs_hot_pan`
  (`lib/widgets/diagram_sheet.dart:16-21`). Worth noting for the item's
  own wording: they are Flutter `CustomPainter`s, **not** `.svg` assets —
  the repo contains no `.svg` file and `pubspec.yaml` declares no svg
  dependency or asset bundle. What remains is the other 18 diagrams and
  the browse-library shell.

### 3. Bookmark on freshly generated recipes — **ABSENT**

The capability does not exist. A recipe just returned from generation
still cannot be saved before some other action.

`SaveRecipeBookmarkButton` has exactly five mount points, none of them a
generation-result surface:

| file:line | surface |
|---|---|
| `lib/screens/recipe_details_screen.dart:63` | recipe details |
| `lib/screens/my_recipes_screen.dart:313` | saved cards |
| `lib/screens/my_recipes_screen.dart:368` | recently-cooked rows |
| `lib/widgets/ledger_verdict_sheet.dart:74` | post-cook verdict |
| `lib/widgets/waste_ledger_celebration_sheet.dart:82` | post-cook celebration |

Both generation-result surfaces are clean of it:

- **`_GeneratedRecipeCard`** (`lib/screens/fridge_clearer_screen.dart:1125-1141`)
  — constructor takes `recipe`, `portions`, `showPlanForDay`, `onCookNow`,
  `onPlanForDay`, `onTryAnother`. Three actions only: Cook Now
  (`:1250`), Plan for Day / Try Another (`:1277`), Try Another (`:1306`).
  No bookmark parameter, no bookmark widget. Decisive: the file's import
  block (`:1-28`) includes neither
  `widgets/save_recipe_bookmark_button.dart` nor
  `services/saved_recipes_service.dart`.
- **`GeneratedRecipeActionsSheet`** (`lib/widgets/generated_recipe_actions_sheet.dart`,
  152 lines, read in full) — two actions, "🔥 Cook Now" (`:96-111`) and
  "📅 Plan for Day" (`:118-143`), plus a close button. Its ten imports
  (`:1-10`) contain neither the bookmark widget nor `SavedRecipesService`.

No route into `recipe_details_screen.dart` from either surface either, so
the indirect path is closed too. This matches CLAUDE.md's stated known gap
("a freshly generated recipe cannot be bookmarked … the earliest save
point is the post-cook verdict card") — verified against source, not
assumed from the doc.

### 4. Committed cooking-times data — **ABSENT**

No table, no Dart map, no data doc. Only *decision records about* a table
that was never authored:

| path | what it is |
|---|---|
| `docs/decisions_2026-08-17.md:32-40` | `## 2. Cooking times table — SIGNED` — three bullets: size scaling as band shifts (half thickness → down one band, double → up one, triple → up two), one-band compatibility tolerance confirmed, whole-muscle vs minced confirmed as a real split |
| `docs/CHANGELOG.md:730-733` | the same decision restated in the changelog entry |

`lib/data/` holds only `diagram_keys.dart`, `pantry_staples.dart`,
`sensory_cue_vocabulary.dart`. There is no cooking-times file anywhere in
`lib/`, no band-shift constant, no temperature/time map. Greps for
`cooking_times_key` / `cookingTimesKey` / `time band` / `band shift` return
only the two decision-record hits above; the `cook time` hits in
`lib/chef_curiculum_*.dart` are prose asides inside curriculum drawers
(e.g. substitution notes), not a structured table.

So the ~3,400-char figure used in last session's Part 2 arithmetic and in
CLAUDE.md item 15 is an **estimate of a block that does not exist yet** —
the signed decision defines its *shape* (bands, tolerance, the
whole-muscle/minced split) but no content has been written. Worth knowing
before the declared-`cooking_times_key` decision: there is nothing to
measure yet, and the real char count could land either side of 3,400.

### 5. Doc commits

| commit | file |
|---|---|
| `69cbad8` | `docs/sessions/2026-08-21_prompt-caching-numbers.md` |
| *(this file)* | `docs/sessions/2026-08-21_ground-truth-resync.md` |

Committed on `main` (the repo's established flow — every commit in §1 is
on main, including the four `docs:` ones). **Not pushed.** `origin` exists
and `main` tracks `origin/main`, and every prior commit had reached the
remote before this session, which is decent evidence that pushing is the
normal flow — but it is circumstantial, so the prompt's own fallback
applies: commit only, and say so.

### 6. Baselines

```
flutter test      177 tests, "All tests passed!"   — unchanged
flutter analyze   54 issues found                   — unchanged
                  (0 error, 9 warning, 45 info)
```

Both match the 177 / 54 expected. Neither could have moved — the only
writes were two Markdown files under `docs/`.

### Stop conditions

Prod Supabase: never contacted. No dev DB access either — none was needed,
and none was in scope. No spec ambiguity required a guess; the two
CLAUDE.md staleness findings in §2 are noted rather than acted on, per the
read-only constraint.
