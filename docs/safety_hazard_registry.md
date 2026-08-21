# Safety Hazard Registry — transcription of the signed scan

**Authority: the scan, not this file.**
`docs/scans/safety_hazard_registry_pages_1-3.pdf` (pages 1–3) and
`docs/scans/safety_hazard_registry_pages_4-6.pdf` (pages 4–6).

**Signed.** Page 6 carries "Reviewed and corrected by: **Chef Harris**",
date **21.08.26**, version **"0.1 draft"**, with all eight review checklist
items ticked. The sheet's own closing line: *"Signing this sheet means the
rules above are yours, not Claude's. Until it is signed, treat every rule in
this document as unverified, and the safety validator's deterministic layer
does not get built from it."*

**Status: VERIFIED by Chef Harris, 2026-08-22.** Both open questions — the H3
temperatures and the H6 time limit — were put to him against the paper and
confirmed to stand exactly as printed. **Nothing in this document is pending.**
The deterministic layer of the safety validator may be built from it.

## How to read this file

Every entry on the paper has a `KEEP [ ] / STRIKE [ ]` pair and a "Your
correction" box. On the returned sheet:

- **KEEP is ticked on all eleven active rules. Nothing was struck.**
- **Every "Your correction" box is empty.** Verified at high contrast; the
  boxes are blank paper, not faint writing.
- The only handwriting in the document is: the eleven KEEP ticks, the H12
  entry, the eight checklist ticks, one checklist note, and the signature.

Per the sheet's own instruction — *"tick KEEP, or strike the whole entry, or
reword it in the correction space"* — a ticked KEEP with an empty correction
box means the drafted rule is adopted as written.

That was straightforward for H1, H2, H4, H5, H7–H11. It was **not**
straightforward for H3 and H6, whose drafted numbers the page-6 checklist
claims were corrected while their correction boxes were left blank. Rather than
assume, both were put to Harris directly on 2026-08-22. **His answer: "all 4
stand" (H3) and "2 hours stand" (H6).** So the empty box does mean "reviewed,
correct as drafted" throughout, and the checklist tick meant "I did the
checking", not "I rewrote something". Both entries are now confirmed values,
not inherited drafts.

---

## Active rules — eleven

### H1 — Poultry and pork doneness is verified, never assumed

- **KEEP** ✓ · correction box empty
- **Status on the paper:** *"ALREADY SIGNED (cooking-times doc) and enforcement
  confirmed 19 Aug. Listed for completeness: nothing to re-sign here."*
- **Rule as the app enforces it:** Every step that cooks poultry or pork
  carries the signed `juices_run_clear` verification: cut into the thickest
  part — white throughout, clear juices, no pink — or a thermometer in the
  thickest part.
- **Detection:** Deterministic. Any poultry/pork step missing the
  `juices_run_clear` cue is flagged regardless of stated time. Identification
  via a closed poultry/pork name list (drafted separately for review).
- **On flag:** The app sets the signed cue on the step itself — deterministic
  injection, never forgotten, no regeneration needed.

### H2 — Minced and comminuted meat is cooked through — no pink, ever

- **KEEP** ✓ · correction box empty
- **Rule:** Whole-muscle beef and lamb are surface-pathogen cases: a proper
  sear addresses them and interior doneness is preference (Harris's signed
  reasoning). Minced, burgers, sausage, and anything comminuted are not —
  surface becomes interior. These are always cooked through with no pink
  remaining.
- **Detection:** Deterministic where possible: minced/burger/sausage ingredient
  plus any rare/pink/medium doneness language, or a missing cooked-through
  instruction, is flagged. Model backstop for phrasing the trigger list misses.
- **On flag:** Correction directive and regenerate; if it persists, the
  cooked-through instruction is injected in Harris's signed wording (**wording
  still to be authored — see the structural questions below**).

### H3 — Temperature floor: no core temperature below the instantaneous minimum without a stated hold time

- **KEEP** ✓ · correction box empty · **temperatures CONFIRMED by Harris
  2026-08-22: "all 4 stand"**
- **Status on the paper:** *"rule already PERMANENT (17 Aug decision). The
  temperatures below are Claude's drafts and are the part needing your
  correction."*
- **Rule:** Any stated core temperature below the instantaneous minimum for
  that protein, with no hold time stated, is flagged.
- **Signed minimums** — printed as drafts, confirmed unchanged by Harris on
  2026-08-22. **These are the values the deterministic layer is built from:**

  | Protein class | Signed minimum |
  |---|---|
  | Poultry | **74 °C** |
  | Minced meat and sausage | **71 °C** |
  | Pork, whole-muscle | **63 °C plus 3 min rest** |
  | Fish | **63 °C** |

  The printed line ends *"Correct, replace, or strike any value."* No value was
  struck, replaced or written, and Harris confirmed on 2026-08-22 that this was
  deliberate: **"all 4 stand"**.

  Note the pork entry is the one with two parts: 63 °C **and** a 3-minute rest.
  A stated 63 °C with no rest is not the signed condition.
- **Detection:** Deterministic — parse stated temperatures in steps against the
  signed minimum for the identified protein class.
- **On flag:** Correction directive naming the protein and the signed minimum;
  regenerate.

### H4 — Marinade that touched raw meat is never served as-is

- **KEEP** ✓ · correction box empty
- **Rule:** A marinade that has been in contact with raw meat, poultry, or fish
  is discarded, or brought to a full boil before any use as a sauce, glaze, or
  drizzle. Late-stage brushing with raw-meat marinade counts as serving it.
- **Detection:** Deterministic trigger — marinade language plus
  serve/drizzle/glaze/reserve language without a boil instruction between them.
  Model backstop for indirect phrasings.
- **On flag:** Correction directive; regenerate with the boil-or-discard
  instruction required.

### H5 — Cooked rice and grains: cool fast, chill promptly, reheat hard, once

- **KEEP** ✓ · correction box empty
- **Rule:** Cooked rice and grains left warm grow *Bacillus cereus*, and
  reheating does not undo the toxin. Recipes never instruct leaving cooked rice
  at room temperature beyond brief cooling; leftover rice is reheated piping
  hot throughout, once. Directly relevant to Fridge Clearer, where leftover
  rice is a common input.
- **Detection:** Deterministic trigger — rice/grain plus room-temperature
  holding language or overnight-on-counter language; leftover-rice usage
  without a reheat-thoroughly instruction. Model backstop otherwise.
- **On flag:** Correction directive; regenerate.

### H6 — No holding perishable food in the danger zone

- **KEEP** ✓ · correction box empty · **figure CONFIRMED by Harris 2026-08-22:
  "2 hours stand"**
- **Rule:** No step instructs holding cooked or perishable food at room
  temperature beyond **2 hours** — printed as a draft figure, confirmed
  unchanged — and never overnight on the counter. Cooling for storage happens
  fast and moves to the fridge.
- **Detection:** Deterministic trigger — rest/hold/leave language with a stated
  duration beyond the signed limit on perishable ingredients. Model backstop
  for unstated-duration phrasings such as "leave out until the evening".
- **On flag:** Correction directive; regenerate.

### H7 — No partial cooking of meat to finish later

- **KEEP** ✓ · correction box empty
- **Rule:** Meat, poultry, and fish are never partially cooked with the
  intention of finishing after a gap — the interior spends too long in the
  danger zone. Par-cooking vegetables is fine; interrupting protein cookery is
  not.
- **Detection:** Deterministic trigger — par-cook/partially cook/finish later
  language on a protein step with a gap between. Model backstop otherwise.
- **On flag:** Correction directive; regenerate.

### H8 — Raw or undercooked egg in no-cook preparations is called out

- **KEEP** ✓ · correction box empty
- **Rule:** Preparations that serve raw or barely-cooked egg — fresh
  mayonnaise, aioli, tiramisu, mousse, sauces that never reach cooking
  temperature — must state that the eggs are raw and instruct pasteurised or
  very fresh eggs, with a caution for vulnerable groups (pregnant, elderly,
  young children, immunocompromised).
- **Detection:** Deterministic trigger — egg in the ingredient list with no
  cooking step reaching it, or named raw-egg dish patterns. Model backstop
  otherwise.
- **On flag:** Correction directive adding the note; regenerate. **Wording of
  the user-facing caution is signed content — still to be authored** (see the
  structural questions below).

### H9 — Fish served raw must be fit for raw consumption

- **KEEP** ✓ · correction box empty
- **Rule:** Ceviche, tartare, sushi-style and cured-only preparations must
  instruct sushi-grade or previously-frozen fish. Acid does not kill parasites
  — citrus "cooking" in ceviche is texture, not safety.
- **Detection:** Deterministic trigger — raw-fish dish patterns (ceviche,
  tartare, crudo, sushi, gravlax) without the sushi-grade/previously-frozen
  instruction. Model backstop otherwise.
- **On flag:** Correction directive; regenerate.

### H10 — Stuffed and rolled meats: the centre counts as the inside of a burger

- **KEEP** ✓ · correction box empty
- **Rule:** Stuffing and rolling turns surface into interior, same reasoning as
  mince. Doneness on stuffed or rolled poultry and meat is verified at the
  centre of the stuffing or roll, not the flesh alone.
- **Detection:** Deterministic trigger — stuffed/rolled/roulade language on a
  meat or poultry step; the verification instruction must reference the centre.
  Can reuse the cue-injection path from H1.
- **On flag:** Inject or regenerate with centre-verification in Harris's signed
  wording.

### H11 — Leftovers are reheated piping hot throughout, once

- **KEEP** ✓ · correction box empty
- **Rule:** Reheated leftovers reach piping hot all the way through — not
  warmed — and are reheated once, never cycled. Directly relevant to Fridge
  Clearer's leftover inputs.
- **Detection:** Deterministic trigger — reheat/warm-up language with low-heat
  or until-warm phrasing on perishable leftovers; missing
  piping-hot-throughout instruction. Model backstop otherwise.
- **On flag:** Correction directive; regenerate.

---

## Blank entries — what Harris added

The sheet provides two blank slots, H12 and H13, under the heading *"Hazards
you see in real kitchens that this draft missed. Same format: rule, how it
shows up, what the app should do."*

### H12 — Fermentation Processes *(handwritten, Harris)*

Transcribed verbatim, including his spelling. One word before "pickle" is
struck through on the paper and is not legible under the strike.

> **H12 – Fermentation Processes**
>
> "I would like that Harris stay out of fermentation if someone for exapample
> asks for Kimchi, Harris should mention that normal long fermentation is not
> adviced, therefore he proposes a "quick ~~[struck]~~ pickle" technique"

Reading notes: "exapample" and "adviced" are as written. The sentence runs on;
the sense is *Chef Harris stays out of fermentation — if someone asks for e.g.
kimchi, he should say that normal long fermentation is not advised, and propose
a "quick pickle" technique instead.*

**This entry has no rule / detection / on-flag structure**, unlike H1–H11.
See the structural questions below.

### H13 — *(left blank)*

No entry written.

---

## Someday list — INACTIVE, not part of v1

Printed on page 5, unchanged: *"Per the 18 Aug decision these are unsourced and
stay OUT of the validator until sourced and signed on their own pass. They are
named here only so they are never forgotten. Do not sign these now."*

| id | Hazard | Status |
|---|---|---|
| S1 | Shellfish handling (live mussels/clams: discard open-before / unopened-after, storage) | **INACTIVE** — unsourced placeholder |
| S2 | Raw flour and raw dough tasting | **INACTIVE** — unsourced placeholder |
| S3 | Raw sprouts consumption | **INACTIVE** — unsourced placeholder |

The page-6 checklist item *"Confirmed the someday list stays inactive and
unsigned"* is ticked. These three must not reach the validator.

---

## Already decided elsewhere

Printed on page 1, listed there so the registry is complete:

- Flag behaviour is **correction-and-regenerate, never blocking** (signed,
  cooking-times doc).
- After **2 failed corrections** the recipe is served and the flag logged
  (confirmed 19 Aug).
- The poultry/pork doneness rule is enforced by deterministic injection of the
  signed `juices_run_clear` cue (confirmed 19 Aug).

The validator has two layers: the deterministic rules on this sheet
(machine-checkable, only ever built from signed entries), and a model-review
backstop that re-reads the whole recipe for general mishandling beyond these
named rules. **This sheet feeds the first layer only. Validator v1 ships on the
signed entries and nothing else.**

---

## Sign-off block, as it appears on page 6

| Reviewed and corrected by | Date | Version |
|---|---|---|
| Chef Harris *(handwritten, with signature)* | 21.08.26 | 0.1 draft |

Review checklist — **all eight ticked**:

- ✓ Struck every hazard I would not stand behind professionally.
- ✓ Reworded every kept rule into my own language where the draft is not how I would say it.
- ✓ Corrected or replaced every draft temperature in H3. These were Claude's drafts. *(No change written; Harris confirmed 2026-08-22 that all four stand.)*
- ✓ Corrected the draft 2-hour figure in H6. *(No change written; Harris confirmed 2026-08-22 that 2 hours stands.)*
- ✓ Confirmed each detection line matches how the mistake actually shows up in a home kitchen.
- ✓ Wrote or scheduled the signed wording for user-facing text (H2 cooked-through line, H8 caution).
- ✓ Added any hazard common in home kitchens that is missing (blank entries). — Notes, handwritten: *"Not any, simply what I thought"*
- ✓ Confirmed the someday list stays inactive and unsigned.

---

## Structural questions for the next build (not transcription flags)

These are not uncertain readings — the paper is clear. They are gaps the
deterministic layer will hit.

1. **H12 has no machine-checkable structure.** It is prose describing what Chef
   Harris should *say*, which is generation-prompt behaviour rather than a
   post-generation check. It may not belong in the deterministic layer at all.
2. **Two pieces of signed user-facing wording do not exist yet**, though the
   checklist item says "wrote or scheduled": the H2 cooked-through line and the
   H8 vulnerable-groups caution. Both are marked on the paper as Harris's to
   author.
3. **The closed poultry/pork name list** H1's detection depends on is noted on
   the paper as "drafted separately for your review" — it is not in this
   document and has not been seen.
4. **Eleven active rules, not seven.** Page 1's framing text argues *"A registry
   of seven rules you own beats eleven where four are approximate."* All eleven
   were kept. Nothing to resolve — recorded because the framing invited a cut
   that did not happen.
