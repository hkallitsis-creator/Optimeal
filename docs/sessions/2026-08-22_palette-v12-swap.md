# Session — Palette v1.2 (variant D) token swap (2026-08-22)

## Prompt (verbatim)

```
AUTONOMY: Full file/test/git permission. No confirmation questions.
STOP CONDITIONS: Prod Supabase = stop-and-report always. Dev
(suuafglvrxrllnhipkiv) read-only; no migrations, no deploys needed
this session. Spec ambiguity = note and continue, never guess.

BUILD — PALETTE v1.2 (VARIANT D) TOKEN SWAP, APP-WIDE
Surgical token-level build. NO layout changes, NO functional changes,
NO refactors beyond token consolidation. This is Unit A of the signed
Cook Mode/Palette spec card (2026-08-21), embedded below — the spec
is WHAT and WHERE; you own HOW.

━━━ SPEC (verbatim from design_spec_cookmode_palette_2026-08-21.md §2) ━━━
Token-level change in the design tokens file (grep AppDesignTokens /
0xFF across .dart — two token sets exist in the codebase, old + new;
the swap must catch both or consolidate to one).

| Token (semantic)                  | Current  | v1.2 (D)        |
|-----------------------------------|----------|-----------------|
| Background sage (canvas)          | #C5D3C1  | #B3C29A         |
| Card surface (was cream)          | #FBF9F4  | ivory #F8F3E9   |
| CTA terracotta (= act)            | #D94A1E  | #C05C35         |
| Terracotta text-on-light          | #B3532F  | #A44E2B         |
| Champagne tint (terracotta bgs:   | #F5DDD2  | #F7DBCB         |
|   heat pills, step chips, SOS)    |          |                 |
| Neutral pill tint                 | #EDE8DC  | #EFE8D8         |
| Sage teaching panel (on cards)    | #DCE5D6  | #DDE6C6         |
| Sage strip on canvas (Home rescue | #DCE5D6  | #DDE6C6 (verify |
|   strip)                          |          | separation vs   |
|                                   |          | new canvas —    |
|                                   |          | device item)    |
| Quiet row surface                 | #FDF9F2  | #FDFBF5         |
| NEW — Gold (= earned)             | —        | #EDA24E fills/  |
|                                   |          | borders ·       |
|                                   |          | #C77E1F glyphs/ |
|                                   |          | text on light · |
|                                   |          | #FBEED8 badge   |
|                                   |          | tint            |

Semantic rules: terracotta = act now · sage panel = Harris teaching
(panels only; canvas decorative) · gold = earned moments ONLY
(counted-verdict badge, rescue milestone, tier-up, share accent);
gold NEVER on CTAs, teaching panels, or large container fills —
glyphs, badges, thin borders, small text only. Home rescue strip
stays sage, not gold. Contrast: gold text on light uses #C77E1F
(pure #EDA24E fails small-text readability — same pattern as
terracotta fill vs text).
━━━ END SPEC ━━━

IMPLEMENTATION NOTES:
- "Current" values above are the spec's snapshot; the live codebase
  has drifted (recent builds already landed some v1.2 values:
  champagneTint #F7DBCB, cookedCountedGold #C77E1F,
  cookedNeutralGray #8B918E). Treat the v1.2 column as the target
  truth, not the diff. cookedNeutralGray #8B918E stays (provisionally
  signed).
- CONSOLIDATE to one token set in app_design_tokens.dart. Every
  widget references semantic tokens; zero 0xFF literals outside the
  tokens file when you're done. Report the full grep proof.
- Old-set tokens that map to a v1.2 semantic get migrated to it;
  colors you find that map to NO v1.2 semantic (and aren't the
  signed diagram palette below) get listed in the report as
  unmapped — pick the nearest semantic token, flag each one.
- EXEMPT from the sweep: the signed diagram palette inside
  CustomPainter diagram code (#E8804A, #F2A06E, #C9D6C0, black
  outlines) — separately signed, untouched. Also exempt: DEV badge
  styling if it uses deliberate non-palette color.
- Semantic-rule audit while you're in there: report (don't redesign)
  any existing usage that violates the rules — gold outside earned
  moments, terracotta on non-action elements, sage panels used
  decoratively on cards.

TESTS: keep all 263 green. Add a palette guard test: parses the lib/
tree and fails if any 0xFF literal exists outside
app_design_tokens.dart and the exempted diagram painters — so drift
can't return silently.

VERIFICATION:
- flutter test all passing, exact count; flutter analyze ≤46, exact
  count
- Grep proof of zero stray literals
- git status clean, committed and pushed

DOC STEP (permanent rule): commit this prompt verbatim + full report
to docs/sessions/2026-08-22_palette-v12-swap.md. Update
docs/CHANGELOG.md. Record in docs/DECISIONS.md: palette v1.2 D is
the sole token set; guard test enforces it.

Report verbatim: consolidation decisions, unmapped colors +
assignments, semantic-rule violations found, files touched,
test/analyze counts, push confirmation, ambiguities.
```

---

## What was actually in the codebase

The spec expected **two** token sets. There were **three**:

1. `AppDesignTokens` (`lib/theme/app_design_tokens.dart`) — 8 colours, the
   "new" set, referenced by most widgets.
2. `LightModeColors` / `DarkModeColors` (`lib/theme.dart`) — 42 colour
   literals, the "old" set, feeding the Material-3 `ColorScheme`.
3. Two private statics on `ProfileScreen` — `deepForest` `#1E3A2B` (an exact
   duplicate of the token) and `terracotta` `#D96B43` (a *third* terracotta,
   drifted from both `#D94A1E` and the v1.2 `#C05C35`), used at 8 call sites.

Plus one loose literal in `post_cook_share_card.dart` (`0xFF14261B`, a gradient
stop).

That is the whole population: **55 `0xFF` occurrences across 4 files**. Every
other colour in the app was already either a token reference or a
`withValues(alpha:)` derivation of one.

---

## Consolidation decisions

**One file defines colour; everything else binds to it.** `AppDesignTokens`
holds every hex. `LightModeColors`/`DarkModeColors` were rewritten as
Material-3 *role bindings* — `static const lightPrimary =
AppDesignTokens.ctaTerracotta;` — so the `ColorScheme` still gets its role
names and no second palette exists. Their class docs now say so explicitly, so
the next person adding a role knows to reach for a token.

**Renames.** `surfaceCream` → `surfaceIvory` (84 call sites, mechanical and
compiler-checked): the token's whole point is that it is no longer cream, and
leaving the old name would have re-created the drift this sweep exists to kill.
`cookedCountedGold` → `goldEarnedOnLight`, same value `#C77E1F`, because the
spec makes gold a palette family rather than a Weekly Planner detail — the
planner's counted check is one instance of "gold glyph on light", not its own
semantic. `cookedNeutralGray` kept its name: it has no v1.2 semantic, it is
explicitly outside the table, and it pairs with a state rather than a family.

**Two sage tokens with the same value, on purpose.** `sageTeachingPanel` and
`sageStripOnCanvas` are both `#DDE6C6` today. Collapsing them to one token
would be tidier and wrong: the spec's own device item is whether the strip
separates from the deepened canvas, and if it has to move, it must move without
dragging every teaching panel with it.

**Non-palette colours quarantined rather than mapped.** Material error roles
(`#BA1A1A`, `#FFDAD6`, `#410002`) and the dark scheme moved into a clearly
marked "non-palette system colours" section of the tokens file — so that file
is still the single place a colour is defined, without pretending these have
brand semantics. Pure white and black became `Colors.white` / `Colors.black`
rather than tokens.

---

## Unmapped colours and where each went

Old-set values with no v1.2 semantic. Nearest token picked, each flagged — any
of these is a one-line revert if the assignment is wrong.

| old value | old role | assigned to | note |
|---|---|---|---|
| `#284236` | `lightOnSurface`, `lightOutline`, `lightSecondary`, `lightOnPrimaryContainer` | `deepForest` `#1E3A2B` | Two deep forests existed. Folded into the token; default on-surface text darkens very slightly. |
| `#4A5568` "Dark Slate" | `lightOnSurfaceVariant` | `textCharcoal` `#2C3531` | A leftover from the pre-OptiMeal template palette — v1.2 has no slate. **This is the widest-reaching mapping**: it changes every `scheme.onSurfaceVariant` subtext from blue-grey to the palette's warm charcoal. |
| `#F2EFE9` | `lightWarmCreamTint` (inputs/chips) | `neutralPillTint` `#EFE8D8` | Exactly the v1.2 semantic; the old value simply predates it having a name. |
| `#DCE8E1` | `lightPrimaryContainer` | `sageTeachingPanel` `#DDE6C6` | A pale sage container; nearest semantic. Low blast radius — `primaryContainer` is barely used. |
| `#F3F6F4` | `lightSurfaceVariant` / `surfaceContainerHighest` | `quietRowSurface` `#FDFBF5` | Cool near-white → the palette's warm equivalent. |
| `#D96B43` | `ProfileScreen.terracotta` | `ctaTerracotta` `#C05C35` | A third terracotta. Used for selected diet/allergy chips. |
| `#1E3A2B` | `ProfileScreen.deepForest` | `deepForest` | Exact duplicate, no visual change. |
| `#14261B` | share-card gradient stop | new token `deepForestShade` | Genuinely needed as a second stop of the same hue; promoted rather than mapped away. |
| `#FFFFFF` / `#000000` | various on-colours, shadow | `Colors.white` / `Colors.black` | Not palette. |
| error + dark-scheme values | Material roles | non-palette section, verbatim | v1.2 is a light-only palette and says nothing about either. |

**The signed diagram-palette exemption had nothing to exempt.** `#E8804A`,
`#F2A06E`, `#C9D6C0` appear nowhere in the repo. `technique_diagrams.dart`
already draws entirely from `AppDesignTokens` (`deepForest` = correct,
`ctaTerracotta` = wrong, `textCharcoal` = line), so it passes the guard on its
own merits and needed no exemption. **Consequence worth knowing**: because
those painters reference the semantic token, the CTA value change moves the
diagrams' "wrong/caution" colour too. That follows the spec, but it is a
visual change to signed teaching content.

**The DEV badge** uses `Colors.red.shade700` / `Colors.black26` / `Colors.white`
— deliberate off-palette, no literal to catch. Listed in the guard's exemption
set anyway, to record the decision rather than because it was failing.

---

## Two semantic assignments landed, not just values

These are the only places the sweep changed *which* token a widget reads. Both
are the v1.2 table landing its own semantics rather than redesign.

**The Home rescue strip.** It filled with `AppDesignTokens.backgroundSage` —
the canvas token itself — and relied entirely on its border to be visible. That
only ever "worked" because the strip and the canvas were the same colour by
accident. The spec lists "sage strip on canvas" as a distinct row precisely
because it must separate from the canvas, so the strip now reads
`sageStripOnCanvas`. It stays **sage, not gold**: a running rescue total is not
an earned moment, and this is the app's most reward-shaped surface, so it is
the clearest test of that rule.

**Eight terracotta text sites → `terracottaOnLight`.** The v1.2 table lists
"terracotta text-on-light" as its own row, and the spec's contrast note names
the fill-vs-text split explicitly. Retargeted: both planner "Retry" affordances,
the today weekday label on filled and empty day cards, the empty-day `+` glyph,
"Add another meal", the curriculum drawer's highlighted words, and Cook Mode's
"Not there yet, or gone too far?" label — that last one being the genuine
small-text case the rule exists for. **Icons and glyphs were left on
`ctaTerracotta`**: terracotta's row says "text-on-light" where gold's says
"glyphs/text", and I did not read a rule into the gap. Flagged below.

Two planner tests asserted terracotta-text and were updated to the new token —
they were asserting the semantic, and the semantic moved.

---

## Semantic-rule audit — violations found, NOT redesigned

Reported only, as instructed. Ordered by how clearly they break a stated rule.

### Gold missing from earned moments (the rule's whole point)

`goldEarnedFill` and `goldEarnedBadgeTint` currently have **zero consumers**,
and `goldEarnedOnLight` has exactly one (the planner's counted check). Every
other surface the spec names as an earned moment is rendered in terracotta:

- **`waste_ledger_celebration_sheet.dart:71–78`** — the celebration sheet's
  icon badge: terracotta tint fill, terracotta glyph. This is *the* rescue
  milestone.
- **`post_cook_share_card.dart:112–116, 214`** — the share button badge and the
  eco glyph. The spec names "share accent" as a gold moment by name.
- **`upgrade_prompt_sheet.dart:48–52`** — the tier-up star, in terracotta.
  Named as a gold moment by the spec.
- The counted-verdict badge in `ledger_verdict_sheet.dart` — worth checking on
  device against the planner check, since only the planner half is gold today.

That is four of the spec's four named gold moments, none of them gold. This is
Unit B-shaped work, not a token swap, but it means the gold family currently
ships almost entirely unused.

### Terracotta on non-action elements

- **`technique_diagrams.dart:130, 179, 235`** — terracotta marks the *wrong*
  way to do something in teaching diagrams. The act-now colour doubling as
  "don't do this" is a real semantic collision, and it is signed content.
- **`technique_lesson_sheet.dart:330, 366`** — bullet dots and accents on
  teaching content.
- **`curriculum_drawer_content.dart:189`** — highlighted words in teaching
  prose (now `terracottaOnLight`, but still terracotta on non-action text).
- **`recipe_details_screen.dart:503`** — decorative bullet dots.
- **`branded_avatar_glyph.dart:22`** — brand glyph, purely decorative.
- **Feature icons in tinted circles** — `onboarding_screen.dart:272–276`,
  `paywall_screen.dart:307–311`, `home_dashboard_screen.dart:439/465`,
  `fridge_clearer_screen.dart:1146–1154`, `culinary_matrix_card.dart:95`.
  Illustrative, not actionable.
- **Progress indicators** — `weekly_planner_screen.dart:893/1127`,
  `fridge_clearer_screen.dart:1463/1601`. Status, not action. Arguably fine as
  "something is happening because you acted".
- **Selected-state fills** — `fridge_clearer_screen.dart:970/1051`,
  `techniques_media_screen.dart:176`, `profile_screen.dart:202/282/894`,
  `paywall_screen.dart:101/110`. Borderline: selection *is* an affordance. Flagged
  as a category for a ruling rather than as individual violations.

### Sage panels used decoratively

None found — but only because `sageTeachingPanel` has no direct consumer yet
beyond the `lightPrimaryContainer` binding. Teaching content today (curriculum
drawers, technique sheets) is rendered on ivory cards with terracotta accents,
not on sage panels. So the rule is not violated; it is simply not yet applied.
That is the other half of the Unit B gap.

### Champagne not yet applied where the spec names it

The spec assigns `champagneTint` to "heat pills, step chips, SOS". Those
surfaces currently draw terracotta at 10–18% alpha instead — 13 sites, listed
below. They are token-derived (no literals) so the guard passes, but they are
not reading the champagne token:

`fridge_clearer_screen.dart:1146` · `home_dashboard_screen.dart:879/893` ·
`onboarding_screen.dart:272` · `paywall_screen.dart:307` ·
`profile_screen.dart:202` · `culinary_matrix_card.dart:110` ·
`post_cook_share_card.dart:112/114` · `technique_lesson_sheet.dart:255` ·
`upgrade_prompt_sheet.dart:48/50` · `waste_ledger_celebration_sheet.dart:71`

**Not converted here.** Swapping an alpha wash for an opaque tint changes how
each of those surfaces sits on its background, and the spec assigns those
elements to the Cook Mode unit. `champagneTint` keeps its one real consumer
(the planner's today row) plus the planner tests.

---

## Files touched

**New**
- `test/theme/palette_token_guard_test.dart` (3 tests)
- `docs/sessions/2026-08-22_palette-v12-swap.md` (this file)

**Rewritten**
- `lib/theme/app_design_tokens.dart` — the v1.2 set, grouped by semantic
  family, with the non-palette quarantine section
- `lib/theme.dart` — `LightModeColors`/`DarkModeColors` as role bindings

**Changed**
- `lib/screens/profile_screen.dart` — private statics removed, 8 call sites
- `lib/widgets/post_cook_share_card.dart` — gradient literal → `deepForestShade`
- `lib/screens/home_dashboard_screen.dart` — rescue strip → `sageStripOnCanvas`
- `lib/screens/weekly_planner_screen.dart`,
  `lib/widgets/curriculum_drawer_content.dart`,
  `lib/screens/one_pan_cooking_roadmap_screen.dart` — terracotta text →
  `terracottaOnLight`
- 22 files total rewritten by the `surfaceCream`/`cookedCountedGold` renames
  (`lib/` and `test/`)
- `test/screens/weekly_planner_redesign_test.dart` — two terracotta-text
  assertions follow the semantic
- `CLAUDE.md`, `docs/CHANGELOG.md`, `docs/DECISIONS.md`

---

## Verification

**Grep proof** — a comment-stripping scan of every `.dart` file in `lib/`
(comments are stripped so that the migration notes recording old hexes, e.g.
"was `0xFF284236`", do not count):

```
TOTAL STRAY COLOUR LITERALS OUTSIDE THE TOKENS FILE: 0
colour literals declared inside the tokens file: 31
colour literals left in theme.dart code: 0
```

Raw `grep -rn "0x[fF][fF]" lib/` now returns 39 hits across 3 files: 33 in
`app_design_tokens.dart` (the palette itself, plus its shadow alpha), and 6
inside doc comments in `theme.dart` and `profile_screen.dart` that document
what each old value was folded into.

**Guard test**: fails on any literal outside the tokens file; asserts the
tokens file still declares the palette (so the sweep cannot pass vacuously by
the palette moving elsewhere); and pins all twelve signed v1.2 hex values by
name, so the values cannot be edited back either.

`flutter test`: **266 passing** (263 baseline + 3 guard), 0 failing.
`flutter analyze`: **46 issues**, 0 errors, 0 warnings — unchanged from the
session start, and none in any file touched.

---

## Ambiguities

1. **Terracotta text vs glyphs.** The v1.2 row says "terracotta text-on-light";
   gold's says "glyphs/text on light". I applied `terracottaOnLight` to text
   only and left icons on `ctaTerracotta`, rather than reading the gold rule
   across. If terracotta glyphs should also take the darker weight, that is a
   handful of sites and one more pass.
2. **The empty-day `+`** is 24px `headline`-weight text. It took
   `terracottaOnLight` for consistency, though the contrast rule is about small
   text and it would have been fine either way.
3. **`#4A5568` → `textCharcoal`** is the widest-reaching unmapped assignment —
   every `scheme.onSurfaceVariant` subtext in the app changes hue. It is the
   right call (the palette has no slate) but it is the one mapping most worth a
   device look.
4. **`lightOnSurface` `#284236` → `deepForest` `#1E3A2B`** darkens default
   on-surface text very slightly, app-wide.
5. **Technique diagrams inherit the CTA change.** They reference the semantic
   token, so their "wrong/caution" marker moved with it. Correct per the spec,
   but it is signed teaching content changing as a side effect.
6. **The diagram-palette exemption was moot** — those hexes do not exist here.
   If they are ever introduced, add the painter file to the guard's exemption
   set rather than weakening the rule.
7. **`cookedNeutralGray` `#8B918E`** stays, per instruction, and is still
   provisionally signed pending a device pass. It now sits beside a real gold
   family, which is the comparison that pass should actually make.
8. **The spec's "Current" column matched almost nothing.** Terracotta
   text-on-light `#B3532F`, champagne `#F5DDD2`, neutral pill `#EDE8DC`, sage
   panel `#DCE5D6` and quiet row `#FDF9F2` were not in the codebase in any
   form. Per instruction I treated the v1.2 column as target truth and did not
   try to reconcile the diff.
