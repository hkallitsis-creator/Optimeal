# Session — cooking-times + safety hazard registry transcription (2026-08-22)

## Prompt (verbatim)

```
AUTONOMY: Full file/test/git permission. No confirmation questions.
STOP CONDITIONS: Prod Supabase = stop-and-report always. Dev
read-only; no migrations, no deploys. This session touches DOCS and
DATA FILES only — no app code, no validators (they're the next
builds). Ambiguity = flag, never guess — on THIS task that rule is
absolute: a guessed temperature or time is worse than a blank.

TRANSCRIPTION SESSION — cooking-times table + safety hazard registry
into the repo as the durable, machine-readable record.

INPUT FILES: Harris has placed the scan PDFs at: <<< HARRIS: WRITE
LOCATION HERE, e.g. docs/scans/ or C:\Users\hkall\Desktop >>>
Two documents: (1) the signed cooking-times table (handwritten
corrections present, some partially legible), (2) the signed Safety
Hazard Registry (corrected from draft v0.1: 11 entries with Harris's
corrected temperatures, possibly 2 extra rows filled).

STEP 1 — commit the scans themselves to docs/scans/ (originals are
the ground truth; the repo keeps them forever).

STEP 2 — transcribe each into a structured file:
- docs/cooking_times_table.md — every row: ingredient/key, band/
  minutes, and the signed scaling rules if present on the paper
  (band shifts: half thickness = down one band, double = up one,
  triple = up two; one-band compatibility tolerance; whole-muscle
  vs minced distinction). Structure it so the next build can
  mechanically derive the Dart map (~26 declared keys, Option C).
- docs/safety_hazard_registry.md — every entry: hazard name, rule,
  Harris's corrected temperature/threshold, scope notes. Include the
  someday-list (shellfish, raw flour, sprouts) marked INACTIVE.
  Record the registry as SIGNED with the scan as authority.

STEP 3 — the flag list. Every value where the handwriting is not
100% certain gets: [FLAG-n] file · row · what you read · why unsure
(e.g. "could be 63 or 68"). Transcribe your best reading into the
doc but mark it ⚠ pending. Numbers you are certain of are NOT
flagged — flag discipline matters in both directions: a flood of
false flags buries the real ones.

STEP 4 — STOP. Print the complete flag list as a short numbered
checklist for Harris to verify against the paper. Do NOT proceed to
validators. After Harris replies with corrections/confirmations,
apply them, remove the ⚠ marks, and record both documents as
VERIFIED in docs/DECISIONS.md (cooking-times: unblocks compat
validator; registry: unblocks safety validator deterministic layer).

VERIFICATION: flutter test still 346 (no code touched); git clean,
committed and pushed — one commit for transcription, one after
Harris's confirmations.

DOC STEP (permanent rule): commit this prompt verbatim + full report
to docs/sessions/2026-08-22_transcription.md. Update
docs/CHANGELOG.md.

Report verbatim: files committed, row counts per document, the flag
list, push confirmation.
```

### Follow-up (verbatim)

```
The scan PDFs are on my Desktop now: C:\Users\hkall\Desktop
Find the two scans there (cooking-times table + safety hazard
registry — likely Adobe Scan PDFs), tell me which files you
identified as which before transcribing, then continue the session
from Step 1.
```

---

## Finding and identifying the scans

The prompt's INPUT FILES line was an unfilled template placeholder. The first
pass searched the repo, Desktop, Downloads and Documents and found neither
document — only the pre-correction `OptiMeal_Safety_Hazard_Registry_Draft_v0.1
.pdf` and its markdown source, both explicitly "NOT AUTHORITATIVE". That was
reported as a blocker rather than transcribed, because v0.1's numbers are the
ones the signed sheet was meant to correct.

After Harris placed the files, the Desktop held **six** scanned PDFs, none
named for its contents. `pdftoppm` is not installed, so the Read tool cannot
render PDFs. They were identified by pulling the embedded JPEG page images
straight out of the PDF byte streams (scan for `FFD8FF` … `FFD9`), rotating
them −90° (the pages are portrait, scanned landscape), and reading (a) a
contact sheet of each file's first-page header and (b) a labelled grid of every
page's bottom-right corner, which carries the printed page number.

That gave an unambiguous map:

| Document | Files | Pages | Footer style |
|---|---|---|---|
| Cooking Times Reference | `optimeal docss.pdf` + `Adobe Scan Aug 18 2026.pdf` | 1–3, 4–6 | "OptiMeal - internal working document" |
| Safety Hazard Registry | `Adobe Scan Aug 21 2026.pdf` + `Adobe Scan Aug 21 2026 1.pdf` | 1–3, 4–6 | "OptiMeal / Empyria … v0.1 - 2026-08" |
| *duplicate* | `optimeal doc.pdf` | 4–6 | second exposure of the cooking-times back half |
| *out of scope* | `optimeal docs.pdf` | 1–4 | **Sensory Doneness Cues** worksheet |

Each document was scanned in two halves. The duplicate was confirmed as the
same physical sheets by comparing printed content **and** handwritten ticks
side by side — identical in both.

The Sensory Doneness Cues worksheet was committed for preservation but **not
read and not transcribed**: it is a third document, outside this session's
stated scope, and it needs its own pass.

## Step 1 — scans committed

Six PDFs into `docs/scans/`, bytes unmodified, renamed for legibility, with
`docs/scans/README.md` recording every original filename so provenance is
traceable.

## Step 2 — transcriptions

`docs/cooking_times_table.md` and `docs/safety_hazard_registry.md`.

### Row counts

**Cooking Times Reference — 74 ingredient rows**

| Section | Rows | Pages |
|---|---|---|
| Vegetables | 42 | 2–3 |
| Proteins | 21 | 4 |
| Starches and grains | 11 | 4–5 |

Plus 6 bands, 4 size-scaling multipliers, 4 shape adjustments, 5 density
classes, the compatibility rule, the poultry/pork verification rule, and the
whole-muscle-vs-minced reasoning.

**Safety Hazard Registry — 11 active + 1 filled blank + 3 inactive**

| Group | Count | Detail |
|---|---|---|
| Active rules | 11 | H1–H11, **all KEEP-ticked, none struck** |
| Blank entries filled | 1 | H12 Fermentation Processes (handwritten). H13 left blank |
| Someday list | 3 | S1 shellfish, S2 raw flour/dough, S3 raw sprouts — all INACTIVE |

### Both documents are signed

| Document | Signed by | Date | Version field | Checklist |
|---|---|---|---|---|
| Cooking Times | Chef Harris + signature | 17.08.2026 | 0.1 | 7 of 7 ticked |
| Hazard Registry | Chef Harris + signature | 21.08.26 | "0.1 draft" | 8 of 8 ticked |

The "draft, unreviewed" footer on every page is pre-printed boilerplate,
superseded by the signature block per each sheet's own closing line.

### The shape of Harris's review

Worth stating plainly, because it drives the flags. **The vast majority of the
review is ticks, not rewrites.** Every one of the 74 cooking-times rows carries
a ✓ with no written change. All 11 registry rules are KEEP-ticked with an empty
correction box. The only substantive handwriting in either document is:

- five annotations on the starches-and-grains table,
- the H12 fermentation entry,
- one checklist note ("Not any, simply what I thought"),
- two signatures and dates.

Under the sheets' own instructions a tick with an empty correction box means
"as printed, and now mine". That reading is clean for 9 of the 11 rules and for
all 74 rows. It collides with the checklist for exactly two entries, and those
are the two most consequential flags below.

## Step 3 — the flag list

Six items. Each says what was read and why it is not certain. Types are marked
because two different kinds of doubt are mixed here and it matters which is
which: a **reading** flag means the ink is ambiguous; an **interpretation**
flag means the ink is perfectly clear and its meaning is not.

Deliberately **not** flagged, to keep the list honest: every printed number
(printed type is not uncertain); the ticks themselves; the spellings
"exapample" and "adviced" in H12 (transcribed as written, meaning unaffected);
and the phrase "don't trust time" on Brown rice, where the final word's
letterforms are messy but the only possible reading in a table of times is
"time", and it is not a value.

---

### ⚠ FLAG-1 — *interpretation* — cooking times, p4, starches

**File:** `cooking_times_reference_pages_4-6.pdf`, page 4, Starches and grains
**Rows:** White rice / Risotto rice
**Read:** two handwritten lines — *"package instructions or experience"* on the
White rice line, and *"16–20 min."* on the Risotto rice line.
**Why unsure:** the two lines are written as one block in a single hand and may
be one annotation wrapping onto a second line ("package instructions or
experience, 16–20 min", all about **White rice**) rather than two annotations
on two rows. Both readings are plausible from the printed values: White rice is
printed 18 min and Risotto 20 min, and 16–20 contains both.
**Question:** does "16–20 min." correct **White rice**, or **Risotto rice**, or
both?

### ⚠ FLAG-2 — *interpretation* — cooking times, p4, starches

**File:** `cooking_times_reference_pages_4-6.pdf`, page 4, Starches and grains
**Row:** Fresh pasta (probably)
**Read:** a single ✓ sitting between the Fresh pasta line and the White rice
line, lower than the other row ticks on the page.
**Why unsure:** vertical position is between two rows. Every other row on the
sheet has its tick clearly on the row's baseline.
**Question:** is that tick confirming **Fresh pasta**?

### ⚠ FLAG-3 — *reading + missing value* — cooking times, p5, starches

**File:** `cooking_times_reference_pages_4-6.pdf`, page 5, Starches and grains
**Row:** Red lentils — printed 18 min, B5
**Read:** *"even faster"*
**Why unsure:** two separate problems. (a) The second word's initial letter is
formed like a capital R — "Raster"/"Rooster" are what the letterforms literally
suggest; "faster" is the only sensible word in context and this hand's lowercase
"f" does loop like an R elsewhere. (b) More importantly, **no replacement number
is given**, so the row cannot be derived: "faster" than 18 min could be B4, B3
or B2.
**Question:** confirm the word, and give red lentils a number or a band.

### ⚠ FLAG-4 — *interpretation* — cooking times, p4–5, starches

**File:** `cooking_times_reference_pages_4-6.pdf`, pages 4–5
**Rows:** Dried pasta, White rice, Brown rice
**Read:** *"package instructions + trying"*, *"package instructions or
experience"*, *"always try / don't trust time"* — all legible.
**Why unsure:** these are not numeric corrections. They say the printed number
is an estimate that the package or the cook's own taste overrides. The validator
has no representation for that today.
**Question:** should these three rows keep their printed bands for compatibility
purposes and simply never be used to flag a stated duration? Or be excluded from
the timing check entirely?

### ⚠ FLAG-5 — *interpretation, safety-critical* — hazard registry, H3

**File:** `safety_hazard_registry_pages_1-3.pdf`, page 2
**Entry:** H3, temperature floor
**Read:** KEEP is ticked. **The "Your correction" box is empty** — verified at
high contrast, it is blank paper. The drafted minimums printed on the sheet are
**poultry 74 °C; minced meat and sausage 71 °C; pork whole-muscle 63 °C plus
3 min rest; fish 63 °C**.
**Why unsure:** the sheet's status line says *"The temperatures below are
Claude's drafts and are the part needing your correction"*, and the page-6
checklist item *"Corrected or replaced every draft temperature in H3"* **is
ticked** — but nothing was written. Either the four drafted values were reviewed
and stand (and the tick means "done, they were right"), or the correction was
intended and not written down. These are the numbers the deterministic safety
layer would be built from.
**Question:** do those four values stand exactly as printed?

### ⚠ FLAG-6 — *interpretation, safety-critical* — hazard registry, H6

**File:** `safety_hazard_registry_pages_1-3.pdf`, page 3
**Entry:** H6, danger zone
**Read:** KEEP is ticked. **The "Your correction" box is empty.** The rule text
prints *"beyond roughly 2 hours (DRAFT figure - correct it)"*.
**Why unsure:** identical shape to FLAG-5 — the page-6 checklist item
*"Corrected the draft 2-hour figure in H6"* **is ticked**, but no figure was
written.
**Question:** does the 2-hour limit stand as printed?

---

## Step 4 — STOP

Stopped here as instructed. No validator work started. Both transcriptions
carry a `⚠ TRANSCRIBED, AWAITING HARRIS'S VERIFICATION` status line and inline
⚠ markers at each flagged row. Nothing has been recorded as VERIFIED in
`docs/DECISIONS.md` — that happens on the second commit, after Harris answers.

## Files committed

**New**
- `docs/scans/` — six PDFs + `README.md` (provenance table, original filenames)
- `docs/cooking_times_table.md`
- `docs/safety_hazard_registry.md`
- `docs/sessions/2026-08-22_transcription.md` (this file)

**Changed**
- `docs/CHANGELOG.md`

No application code was touched.

## Verification

`flutter test`: **346 passing**, unchanged. `flutter analyze`: **44 issues**,
unchanged. Both confirm no code was touched.

## Ambiguities beyond the flag list

1. **The prompt described the scaling rules as band shifts** ("half thickness =
   down one band, double = up one, triple = up two"). The paper specifies
   **time multipliers** (× 0.4 / × 1 / × 2.5 / × 5) with the band derived from
   the scaled time. These are not equivalent — × 0.4 on a 12 min B4 gives
   4.8 min, which is B2, a two-band drop. The paper is the authority and was
   transcribed; noting it because the next build was evidently expecting the
   other model.
2. **"~26 declared keys, Option C"** vs **74 ingredient rows** on the paper.
   Either the closed key list is 74 long, or it is a coarser vocabulary these
   rows resolve into. The paper does not answer this; it is a design decision
   for the validator build.
3. **`lamb_diced_2cm_dice` carries two bands, "B3 / B6"** — the only dual-band
   row on the sheet, presumably fast-fry versus braise. Transcribed as printed;
   how a dual band resolves is undecided.
4. **H12 has no rule / detection / on-flag structure**, unlike H1–H11. It is
   prose about what Chef Harris should *say* when asked for kimchi, which is
   generation-prompt behaviour rather than a post-generation check — it may not
   belong in the deterministic layer at all.
5. **Two pieces of signed user-facing wording still do not exist**, though the
   checklist item "Wrote or scheduled the signed wording" is ticked: the H2
   cooked-through line and the H8 vulnerable-groups caution.
6. **The closed poultry/pork name list** that H1's detection depends on is
   described on the paper as "drafted separately for your review". It has not
   been seen and is not in the repo.
7. **The registry's version field says "0.1 draft"** even though it is signed.
   Cooking-times says "0.1". Neither was bumped to a released version number.
8. **A third signed-series worksheet exists** — Sensory Doneness Cues, 4 pages.
   Committed to `docs/scans/` so it cannot be lost, deliberately unread. Note
   that `lib/data/sensory_cue_vocabulary.dart` already exists in the app and
   describes itself as signed 17.08.2026, so this scan may be that document's
   paper original, a later revision, or something else entirely — unknown until
   someone reads it.
