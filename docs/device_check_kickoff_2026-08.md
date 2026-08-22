# Device check kickoff — August 2026 (pre-vacation freeze)

Generated 2026-08-23 from the specs built 22–23 August, at tag
`vacation-2026-08`. Companion: `docs/audit_2026-08-23.md` (read it first —
its H-1/H-2/M-1 findings shape several checks below).

**Build/install pair, always:** `flutter build apk --release` then
`flutter install --release -d <deviceId>`. `flutter install` alone pushes a
stale APK, and it wipes app data (new `auth.uid()`, onboarding replays, prior
dev rows orphaned). A release-mode APK against dev is **entitled**: no caps,
no upgrade sheet — that is the fixed entitlement rule working, not a bug.

Every unchecked box is unverified on a physical device. Items Harris has
already ruled on are excluded.

---

## 1. Home cluster

- [ ] One screen, no scroll, six zones; only the gap flexes. At your text
      scale nothing overflows (known limit: clean to ~2.4× at 360×640).
- [ ] Rescue strip updates **in place** after a counted cook lands you back
      on Home — no restart needed.
- [ ] Resume banner appears for an interrupted cook and resumes at the right
      step; discarding it clears it everywhere.
- [ ] Post-cook upgrade nudge appears **only after** the verdict's CTA lands
      you on Home — never mid-cook, never over the verdict — and at most once
      per cook. (In an entitled dev build it should never appear at all.)
- [ ] The fridge-nudge notification's two actions deep-link correctly
      (Fridge Clearer; Home + auto-opened creator sheet).

## 2. Weekly Planner

- [ ] Seven days, one vertical list; this-week ↔ next-week toggle; no past
      navigation anywhere.
- [ ] Today with an uncooked meal is the only terracotta Cook on screen;
      next week shows no Cook, no checks, no tint.
- [ ] Cook from a planner row → finish → the exact row flips (gold if the
      recipe was Fridge Clearer origin, gray otherwise), in place, while the
      planner sits under Cook Mode. Same dish on two days: only the launched
      one flips.
- [ ] A planner cook interrupted, resumed from the Home banner, still flips
      its row on completion.
- [ ] **Detour attribution:** planner Cook → back arrow (overview) → Start
      cooking (resume) → finish → the row still flips.
- [ ] Overwrite an occupied slot; delete a meal from the day-detail sheet;
      second meal added there; inline "Couldn't save. Tap to retry" only on
      a genuine failure (airplane mode).
- [ ] Sunday→Monday rollover happens by itself (or simulate by device date).

## 3. Recipe overview

- [ ] Stepper rescales all quantities instantly; eggs at odd scales read
      "2 eggs · rounded up", never "1.5 eggs"; ≥100 g/ml rounds to nearest 5;
      ½/¼/¾ on spoons.
- [ ] Quantities lock on Start cooking; Step 1's read-only pill matches the
      chosen N; backing out re-enables the stepper.
- [ ] Description never wraps past one line; long titles wrap.
- [ ] Bookmark toggles and persists; saving pre-cook shows in My recipes as
      "not cooked yet".
- [ ] Plan opens the weekday picker; a planned recipe carries the leaf.
- [ ] Cut pills open the right diagram; **no pill on unbuilt cuts** (only
      `julienne` is drawn — most recipes will show none; that is correct).
- [ ] One terracotta CTA; gear chips wrap at 360 px.
- [ ] Start cooking works from all three overview entry points: Saved,
      Recently Cooked, planner day-detail view tap.
- [ ] **Audit H-1/H-2 repro (expect the bugs — do not be surprised):**
      overview → Start cooking → advance steps → back arrow → back again →
      the *older* overview underneath does not know about the session; its
      Start cooking silently restarts at Step 1. Confirm on device, then fix
      post-vacation.
- [ ] **Audit M-1:** on the resume path the stepper is live but ignored —
      confirm the mismatch reads as badly on device as on paper.

## 4. Pre-cook mise (Step 1)

- [ ] Step 1 is "Set up your board": no timer, no tick-boxes, no counter,
      read-only Serves pill, "No heat yet".
- [ ] NEEDS THE KNIFE rows match the overview's scaled quantities; JUST HAVE
      IT OUT is one compact `·`-joined row that wraps.
- [ ] Never two prep steps: a generation opening with its own "Prepare
      Ingredients" shows one mise step; one opening with "Preheat Oven"
      keeps it as Step 2.
- [ ] Bottom-bar Next is relabelled on Step 1 and is the only terracotta CTA.
- [ ] Resume never lands you on the mise step when you were mid-cook.

## 5. Cook Mode (focused layout + timer)

- [ ] One step card: action line → meta row (wraps, never clips at large
      text) → cue panel → detail → next-step whisper; no whisper on the last
      step.
- [ ] Timer is **idle until tapped** on every step entry — including
      jump-to-step from the overview sheet. Tap starts, tap pauses; ± live
      while idle/paused, hidden while running; floor 1 min.
- [ ] Zero: two beeps + one haptic + slow pulse; **the step does not
      change**. Muted device: haptic + pulse only.
- [ ] Bottom-bar pause square behaves identically to tapping the pill.
- [ ] Progress bar and whisper both open the two-pane sheet; panes swap in
      place; ingredients pane answers "how much X" at the locked scale;
      Finish & Plate only at the end of the list, behind a confirm.
- [ ] Jump forward marks intervening steps done; jump back clears them; the
      bar tracks.
- [ ] SOS square present in every state; SOS answers stay consistent with
      the on-screen recipe; Step 1 never appears in its context.
- [ ] Cue panel: readiness vs doneness label per phase, inline remedy
      expander, absent entirely on a `no_cue` step.

## 6. Back-to-overview / system back

- [ ] Back arrow and system gesture (incl. predictive back) both land on
      this recipe's overview with the session kept.
- [ ] Overview's Start cooking resumes at the stored step with the stored
      scale and completed set.
- [ ] Round trip does not stack Cook Modes; count your back-presses to exit
      (audit H-2 predicts one extra overview when the overview launched the
      cook).
- [ ] Home glyph from Cook Mode → Home; resume banner appears.

## 7. Fridge Clearer (input + two stages)

- [ ] Input is one screen, no scroll; chips wrap; typed ingredients become
      removable ✕-chips in the same wrap; champagne selection everywhere.
- [ ] "For" defaults silently from the profile household.
- [ ] Stage 1 returns three idea cards; clearance line arithmetic matches
      your entered list; "X stay" phrasing.
- [ ] Back → Let's Cook with identical chips produces genuinely new ideas
      (0 repeats expected — the freshness fix).
- [ ] With allergens set: no idea containing an allergen is ever shown; if
      everything is dropped twice, the inline error appears (never an empty
      or annotated menu).
- [ ] Tap an idea → waiting card names the dish → Cook/Save/Plan sheet; all
      three act on a real recipe.
- [ ] A cooked stage-2 recipe counts as a rescue with the right ingredient
      credit — including when cooked later from the planner.
- [ ] Planner's "Clear Fridge Leftovers" source lands on the same ideas
      screen and pops the payload back to the planner.

## 8. Waiting card

- [ ] Same card at all four generation points; stage 1 = one static line,
      stage 2 = cycling lines with the dish/craving as subject.
- [ ] Spoon stays inside the bowl through the whole stir; no notch at the
      bowl base (the geometry fix — this is the exact prior device finding).
- [ ] No progress bar anywhere; reduced-motion setting freezes it composed.

## 9. Custom creator sheet

- [ ] One 52 px field; chips write editable text and wear champagne only
      while the field holds exactly what they wrote; first keystroke clears
      it.
- [ ] No servings control; generated recipe arrives at the profile default.
- [ ] Generate swaps the sheet body in place (no second sheet, no route);
      failure is a quiet card whose retry keeps the typed text.
- [ ] Dismiss during generation: nothing crashes; the call completes and is
      billed (known, ruled).
- [ ] Same sheet and behaviour from Home's slim row and the planner's
      Custom source.
- [ ] No emoji in any CTA anywhere in the app.

## 10. Onboarding

- [ ] Four slides, real visuals (spoon-bowl matches the waiting card's;
      mini cue panel; mini week strip), dots, Skip hidden on slide 4.
- [ ] **Skip completes**: from any slide, Skip lands on Home and stays
      there (no bounce back into onboarding). Finish likewise.
- [ ] No stale promises anywhere in the four slides (no checkboxes,
      shopping list, CHF statistic, "not a chatbot").
- [ ] Dev-only "Replay onboarding" row works and replays once.

## 11. Post-cook + share

- [ ] Sequence: What You Learned (repeat completions get the confidence
      question) → tier-up offer when earned → share card → verdict LAST,
      whose one CTA exits to Home.
- [ ] Share card: sage canvas, thin gold border, dish name, story line,
      gold rescue chip + neutral technique chip ("sautéing, learned
      properly" — never "learned to sautéing").
- [ ] **No app name/wordmark/logo on the image, in the share text, or in
      the exported filename** (branding gate).
- [ ] A didn't-count cook still shares: no rescue chip, no story line.
- [ ] Not-counted verdicts use the origin framing ("Rescues come from
      Fridge Clearer recipes — this one didn't.").
- [ ] Airplane-mode cook: post-cook sequence completes; the ledger write
      queues and flushes on reconnect (roadmap item 7's never-run check).

## 12. Profile

- [ ] Autosave — no Save button; selections persist as made (kill the app
      and reopen to confirm).
- [ ] One selection style (champagne chips); one terracotta CTA (Secure my
      account); no Language card; no explainer paragraphs.
- [ ] Allergens/diet demonstrably shape generations (adversarial check:
      avoid dairy + nuts, offer cheese + walnuts as ingredients).
- [ ] Household prefills the Fridge Clearer "For" and new recipes'
      basePortions; changing it never rescales an open recipe.
- [ ] Comfortable Techniques is read-only, filled only by the post-cook
      question, gold on "automatic".
- [ ] Dev section (dashed ghost) visible on dev, absent in a prod build.

## 13. Type scale

- [ ] Cook Mode action line/cue/detail read comfortably at arm's length on
      the Pixel; whisper stays visibly quieter.
- [ ] At system font size Large/Largest: meta row wraps (never clips), Home
      still fits, planner rows survive.

## 14. Launcher

- [ ] The installed app is named **"OptiMeal dev"**, not "dreamflow".

---

## KNOWN-UNBUILT (do not file as bugs)

- **Chef SOS sheet redesign** — queued; today's sheet is the old surface.
- **Diagram batch** — 3 of 21 diagrams exist (`julienne`, `pan_crowding`,
  `cold_vs_hot_pan`); cut/technique pills render only for built diagrams, so
  most ingredient rows and steps show none. The browse-library shell is also
  unbuilt.
- **Persona/authoring batch** — 123 `// PLACEHOLDER` strings ship as drafts
  (onboarding copy, mise card strings, verdicts, sales copy, ideas header,
  H2/H8 safety sentences…). Wording complaints are authoring-batch work, not
  defects.
- **Pre-cook shell around the mise card** — the old pre-cook body (header,
  Start Cooking card, step list) still frames Step 1; only the checklist card
  was deleted. Restyling that shell was never specced.
- **Custom-creator completion routing** — spec says overview, ruling kept the
  Cook/Save/Plan sheet; the mismatch is recorded and design chat owns it.
- **Planner headcount tier** — R5's planner tier of the servings precedence
  has no data source (`PlannerSlotRef` carries no headcount); always null.
- **Fahrenheit conversion** — H3 flags a °F temperature for restatement,
  never converts.

## KNOWN-OPEN (rulings/authoring still owed — from DECISIONS.md)

- **Allergen guard fail-closed**: adopted in principle, waits on a signed
  "couldn't build this safely" state (persona batch). Interim = fail-open
  with a loud log.
- **H2 cooked-through line and H8 vulnerable-groups caution**: Harris to
  author; until then both rules can only ask the model twice.
- **H10 on non-poultry meat**: needs a second signed centre-verification cue;
  log-only today.
- **Safety model-review backstop** (registry layer 2): not started.
- **H12 prompt line** ("Quick X" substitution behaviour): authoring batch.
- **Red lentils**: one number owed to `docs/cooking_times_table.md`; timing
  checks skip the key until then. **Lamb dual-band**: regime unresolved,
  permissive reading ships.
- **Compat validator's two beyond-paper readings** (off-heat steps skipped;
  cumulative heated time): adopted on measured evidence, open to reversal.
- **74-key vocabulary vs coarser list**: 74 shipped; open to overrule.
- **Geschnetzeltes** filed as pork so H1 fires at all; veal reading would
  need its own line.
- **`cookedNeutralGray`** provisionally signed pending this device pass;
  **sage strip vs deepened canvas separation** is likewise a named device
  item.
- **Jump-to-step completed-set rewrite** and **`CuePhase.during`'s label**:
  flagged ambiguities, never ruled.
- **Pricing**: NOT DECIDED; 15 CHF is a placeholder.
- **`ai-recipe-precision`** cost/abuse exposure (roadmap item 2): HIGH,
  unfixed, function under deploy hold.
- **Post-cook UX gaps** (roadmap item 22): app idles after the share card is
  dismissed from the verdictless path; a skipped share card is lost.
- **Planner Custom source writes the generated recipe into the slot with no
  confirmation** (roadmap item 23).
- **"Custom AI Craving" naming + prompt-guidance copy** (roadmap item 24).
- **Audit findings** `docs/audit_2026-08-23.md`: H-1, H-2, M-1…M-6 — all
  unfixed by decision (read-only session).
