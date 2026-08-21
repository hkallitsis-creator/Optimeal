# Scans — the ground truth

These PDFs are the **authority**. The markdown transcriptions in `docs/` are
convenience copies for machines and for reading on a screen; where a
transcription and a scan disagree, the scan wins and the transcription is the
bug.

Committed 2026-08-22. Do not delete, do not "clean up", do not re-compress.

## Provenance

Adobe Scan captures of paper worksheets Chef Harris reviewed, corrected and
signed by hand. Renamed on the way in for legibility; bytes are unmodified.

| File here | Original filename on Harris's Desktop | Pages | Document |
|---|---|---|---|
| `cooking_times_reference_pages_1-3.pdf` | `optimeal docss.pdf` | 1–3 | Cooking Times Reference |
| `cooking_times_reference_pages_4-6.pdf` | `Adobe Scan Aug 18 2026.pdf` | 4–6 | Cooking Times Reference |
| `cooking_times_reference_pages_4-6_second_scan.pdf` | `optimeal doc.pdf` | 4–6 | Cooking Times Reference — **duplicate exposure** |
| `safety_hazard_registry_pages_1-3.pdf` | `Adobe Scan Aug 21 2026.pdf` | 1–3 | Safety Hazard Registry |
| `safety_hazard_registry_pages_4-6.pdf` | `Adobe Scan Aug 21 2026 1.pdf` | 4–6 | Safety Hazard Registry |
| `sensory_doneness_cues_worksheet.pdf` | `optimeal docs.pdf` | 1–4 | Sensory Doneness Cues — **not transcribed** |

Each document was scanned in two halves, hence two files per document. Page
numbers in the table are the numbers printed in each page's own footer, which
is how the halves were matched up.

`cooking_times_reference_pages_4-6_second_scan.pdf` is a second pass over the
same three sheets. Same printed content, same handwritten marks; it differs
only in exposure. Kept because a second exposure of handwriting is worth having
and costs 750KB.

`sensory_doneness_cues_worksheet.pdf` was on the Desktop alongside the other
two documents and is clearly part of the same series, but it was **outside the
scope of the 2026-08-22 transcription session** and has not been read or
transcribed. It is committed here purely so it is not lost. It needs its own
session.

## Which document is signed, and when

| Document | Signature | Date on the sheet | Version field |
|---|---|---|---|
| Cooking Times Reference | Chef Harris, with signature | 17.08.2026 | 0.1 |
| Safety Hazard Registry | Chef Harris, with signature | 21.08.26 | 0.1 draft |

Both carry a pre-printed "draft, unreviewed" footer on every page. That is
boilerplate from before the sheets were filled in and is superseded by the
signature block on the last page of each.

## Reading the scans

The page images are embedded JPEGs, landscape-oriented (the pages are portrait,
so they need a −90° rotation to read). `pdftoppm` is not installed on this
machine; the images can be pulled straight out of the PDF byte stream by
scanning for JPEG SOI/EOI markers, which is how the 2026-08-22 session read
them.
