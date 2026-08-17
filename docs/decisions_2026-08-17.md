# OptiMeal — Decision Record, 17 August 2026

Reconstructed from session notes after the chat transcript became unavailable.
Harris to verify each line against his own recollection and correct anything wrong.
Nothing here is a proposal — all of it was decided.

---

## 1. Sensory cue vocabulary — DONE

- 26 entries drafted, reviewed and re-voiced by Harris, signed.
- Schema gained two fields, both forced by Harris's own handwritten entries:
  - **`phase`** — separates *readiness* (is the pan hot enough to receive food; fires
    before the timer starts) from *doneness* (fires when the timer ends). Same
    vocabulary, opposite ends of a step.
  - **`if_overshot`** — "you have gone too far", distinct from "not ready yet".
    Overshooting is the more common beginner failure, so this field may teach more
    than the other one.
- **`no_cue`** escape value required, exactly like the explicit `none` in the cut
  vocabulary. Without it a thin list forces bad matches, and a wrong cue is worse
  than a missing one.
- `juices_run_clear` is mandatory on poultry and pork steps. Absence is a validator
  flag regardless of stated time.
- Once cut and re-voiced, this becomes a **data file, not prompt text**. Adding a cue
  later is a content edit, not a code change and not a prompt rewrite.

**Source documents are safe:** `OptiMeal_Sensory_Cues_Draft.pdf` and
`sensory Cue Vocabulary.pdf` are both in the project files, signed copy included.

---

## 2. Cooking times table — SIGNED

- Size scaling expressed as **band shifts**, not multipliers:
  - half thickness → down one band
  - double → up one band
  - triple → up two bands
- **One-band compatibility tolerance** confirmed.
- **Whole-muscle vs minced** distinction confirmed as a real split in the table.

---

## 3. Cuts

| Item | Decision |
|---|---|
| Shopping list | **CUT.** Currently live in Weekly Planner — needs removal. |
| Video / media section | Video content **CUT** (see item 4 — the shell survives, repurposed). |
| Fridge tab | **CUT.** Replaced — see item 5. |
| Pasteurisation equivalence table | **DROPPED.** See item 8. |
| Cut reference photo library | **CUT as a photo shoot.** See item 4. |

---

## 4. Visual assets — drawn diagrams, not photographs

- Cut reference visuals will be **deterministic SVG diagrams**. Not AI-generated
  images, and not a real photo shoot.
- **This removed the photo library from the vacation deliverables list.**
- The media section shell is **repurposed as a drawn-diagram learning library**,
  containing:
  - the 16 cut diagrams (one per cut vocabulary value)
  - a closed set of technique diagrams: **pan crowding, cold vs hot pan, oil depth,
    tray spacing, staggered adds**
- **In-context placement inside recipes is the higher-value surface.** The browse
  library is secondary and gets built second.
- Technique diagrams get a closed **`technique_diagram_id`** key list that the model
  declares from — same pattern as cut vocabulary and curriculum drawer keys. Third
  and fourth instances of the pattern that has now worked repeatedly.

---

## 5. Fridge tab replacement

The tab is gone. In its place:

- **A single local scheduled notification**, fired 2 days after unused Fridge Clearer
  ingredients.
- **One nudge only. Never repeated.**
- Two CTAs on the notification: **Fridge Clearer** and the **AI generator**.

This dissolves the Fridge Countdown cold-start dead end rather than solving it.

---

## 6. Waste Ledger legibility — option B

- **Every completed cook gets a verdict** explaining why it did or did not count.
- Plus a **permanent explainer on the ledger screen** itself.

Rationale on record: Harris wrote the spec and still experienced correct behaviour as
inconsistent, because nothing in the UI explained the rules. A tester never would.

---

## 7. Confidence question wording — FINAL

> **"Are you comfortable with this technique?"**
>
> - Yes, it's automatic now
> - Not yet, still takes concentration

This resolves the open "What You Learned repeats the same technique forever" problem.

---

## 8. Pasteurisation equivalence table — DROPPED

The interim rule becomes the **permanent** rule:

> Flag a temperature below the instantaneous minimum with no hold time stated.

**This removed the pasteurisation table from the vacation deliverables list.**

---

## 9. Pricing — NOT DECIDED

- Harris has **not** committed to CHF 6.99/month, CHF 69.99/year, or any other figure.
- Pricing is **deliberately deferred** until the app is functioning and proven good.
- The **15 CHF/month currently in the paywall is a placeholder in code, not a decision.**

---

## Vacation deliverables — revised list

Two of the original four are gone. What remains:

1. **Per-hazard sign-off** — the table is still blank. Harris fills in only the hazards
   he would change, plus a line confirming the rest stand. Two entries (shellfish;
   raw flour and sprouts) are unsourced placeholders needing attention.
2. **Cooking-times table** — signed (item 2). Confirm whether anything remains to write
   by hand, or whether this is now closed.

Removed: pasteurisation equivalence table (item 8), cut reference photo library (item 4).

---

## Still open, carried forward

- `LedgerService.freshProduceOnly` blocklist — confirmed live, not theoretical. Real fix
  is provenance the app already has, not name-guessing.
- Four hardcoded food examples in the always-on system prompt, sent on every call. Bucket B
  curriculum drawers not yet scanned for the same pattern.
- Confidence Climb and Your Month read `cook_session_history_v1` unfiltered — pre-migration
  keyword entries mix with declared-key entries.
- Post-cook sequence surviving a failed ledger write — untested, airplane mode test not run.
- Home hierarchy and bottom nav should lead with Fridge Clearer and the AI generator.
- Cook Mode first step should be "prepare ingredients" with **no timer** — testers found the
  timer stressful, and rushing knife work is how people cut themselves.
- Dev/prod separation — a stale Chrome tab wrote three real rows into the live database.
- Legal review of Terms and Privacy Notice before the first external tester.
- CLAUDE.md is 186.4k chars against a 150k auto-load limit — being read truncated.
- Prompt caching raised in priority: ~7,095-char static system prompt sent identically
  on every call, including SOS.
