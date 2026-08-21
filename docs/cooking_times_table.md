# Cooking Times Reference — transcription of the signed scan

**Authority: the scan, not this file.**
`docs/scans/cooking_times_reference_pages_1-3.pdf` (pages 1–3) and
`docs/scans/cooking_times_reference_pages_4-6.pdf` (pages 4–6).
A second scan of pages 4–6 (`..._second_scan.pdf`) is byte-different but shows
the same sheets with the same marks; it is kept only as a backup exposure.

**Signed.** Page 6 carries "Reviewed and corrected by: **Chef Harris**",
date **17.08.2026**, version **0.1**, with a signature and all seven review
checklist items ticked. The printed footer still reads "draft, unreviewed" —
that is pre-printed boilerplate on every page and is superseded by the
signature block, exactly as the sheet's own closing line says: *"Signing this
sheet means the values above are yours, not Claude's."*

**Status: ⚠ TRANSCRIBED, AWAITING HARRIS'S VERIFICATION.** Four items are
flagged below and in the session record. Until they are resolved this file must
not be used to build the compatibility validator.

## How to read this file

Every printed value is reproduced exactly. Harris's handwriting is reproduced
in a **Harris's mark** column and quoted verbatim.

A blue tick (✓) in the paper's "Correction" column means the printed row was
reviewed and stands. That is the sheet's own instruction — the column is
headed *"The final column is deliberately blank - write your corrections
there"*, so a tick with no writing is an explicit "as printed".

The `key` column is **derived by transcription, not present on the paper**. It
is a mechanical snake_case join of ingredient and reference cut, provided so
the next build can lift a Dart map without re-reading the scan. Change it
freely; nothing on the paper depends on it.

---

## 1. Bands

The unit the validator actually reasons in. From page 1.

| Band | Time to done | Meaning |
|---|---|---|
| B1 | 0–2 min | Flash, wilt, or finish only |
| B2 | 3–5 min | Quick |
| B3 | 6–9 min | Medium |
| B4 | 10–15 min | Slow |
| B5 | 16–25 min | Very slow |
| B6 | 26+ min | Needs its own head start entirely |

**Compatibility rule** (printed as "needs Harris's confirmation"; the page-6
checklist item *"Confirmed the one-band tolerance is the right compatibility
rule"* is ticked, so it is confirmed):

> Same band, or one band apart, may go in together. Two or more bands apart
> requires a staggered add, or a different cut size to bring them closer.

The worked example on the paper: potato at 2cm dice is B4, spinach is B1 —
three bands apart.

## 2. Size and shape scaling

From page 1. The page-6 checklist item *"Confirmed or replaced the four
size-scaling multipliers"* is ticked and the "Your correction" column is blank,
so these four stand as printed.

> Time is governed by the shortest distance to the centre, not by volume. A
> 1cm-thick slice cooks in roughly the time of a 1cm dice, however wide the
> slice.

| Cut vs the reference cut | Multiply time by | Harris's mark |
|---|---|---|
| Half the thickness | × 0.4 | (blank — stands) |
| Reference | × 1 | (blank — stands) |
| Double the thickness | × 2.5 | (blank — stands) |
| Triple the thickness | × 5 | (blank — stands) |

**Shape adjustments, applied after the above:**

- Strips, julienne and batons: take the smallest dimension, then × 0.8.
- Whole and round items: × 1.5 on top of thickness scaling.
- Shredded or grated: **always B1**, regardless of density.
- Sliced discs: go by disc thickness only.

> **Note for the next build.** The session prompt described these as *band
> shifts* ("half thickness = down one band, double = up one, triple = up two").
> The paper does not say that — it specifies **time multipliers**, and the band
> is then whatever the scaled time falls into. The paper is the authority.
> The two are not equivalent: × 0.4 on a 12 min B4 gives 4.8 min, which is B2,
> a two-band drop rather than one.

## 3. Density classes

Used when an ingredient is not in the tables below. From page 1.

| Class | Character | Examples | Default band at 1cm |
|---|---|---|---|
| D1 | Leaf and herb | spinach, rocket, basil, chard leaf | B1 |
| D2 | High-water soft | courgette, tomato, mushroom, pepper | B2 |
| D3 | Fibrous medium | broccoli, cauliflower, green bean, leek | B3 |
| D4 | Dense starchy | potato, carrot, parsnip, celeriac | B4 |
| D5 | Hard root, winter squash | swede, turnip, pumpkin | B4–B5 |

## 4. Vegetables — 42 rows

Pages 2–3. Times are to tender, in a preheated pan or oven at the method's
normal temperature. Every row carries a ✓ and no written change.

| key | Ingredient | Class | Reference cut | Sauté | Roast 200C | Boil | Steam | Band | Harris's mark |
|---|---|---|---|---|---|---|---|---|---|
| `spinach_whole_leaf` | Spinach | D1 | whole leaf | 1 | – | 1 | 2 | B1 | ✓ |
| `rocket_whole_leaf` | Rocket | D1 | whole leaf | 1 | – | – | – | B1 | ✓ |
| `chard_leaf_ribbon` | Chard leaf | D1 | ribbon | 2 | – | 2 | 3 | B1 | ✓ |
| `chard_stem_1cm` | Chard stem | D3 | 1cm | 6 | 15 | 6 | 8 | B3 | ✓ |
| `kale_torn` | Kale | D1 | torn | 4 | 10 | 4 | 5 | B2 | ✓ |
| `cabbage_1cm_ribbon` | Cabbage | D3 | 1cm ribbon | 6 | 20 | 6 | 8 | B3 | ✓ |
| `spring_onion_1cm` | Spring onion | D2 | 1cm | 2 | – | – | – | B1 | ✓ |
| `onion_soften_1cm_dice` | Onion, soften | D2 | 1cm dice | 5 | 25 | – | – | B2 | ✓ |
| `onion_caramelise_1cm_dice` | Onion, caramelise | D2 | 1cm dice | 35 | – | – | – | B6 | ✓ |
| `shallot_sliced` | Shallot | D2 | sliced | 4 | 20 | – | – | B2 | ✓ |
| `garlic_minced` | Garlic | D2 | minced | 1 | – | – | – | B1 | ✓ |
| `leek_1cm_slice` | Leek | D3 | 1cm slice | 6 | 20 | 6 | 7 | B3 | ✓ |
| `mushroom_button_quartered` | Mushroom, button | D2 | quartered | 6 | 18 | – | – | B3 | ✓ |
| `mushroom_sliced_5mm` | Mushroom, sliced | D2 | 5mm slice | 4 | 15 | – | – | B2 | ✓ |
| `courgette_1cm_dice` | Courgette | D2 | 1cm dice | 5 | 18 | 4 | 5 | B2 | ✓ |
| `aubergine_2cm_dice` | Aubergine | D2 | 2cm dice | 9 | 25 | – | – | B3 | ✓ |
| `bell_pepper_2cm_piece` | Bell pepper | D2 | 2cm piece | 6 | 20 | – | – | B3 | ✓ |
| `bell_pepper_1cm_strip` | Bell pepper | D2 | 1cm strip | 4 | 15 | – | – | B2 | ✓ |
| `tomato_fresh_wedge` | Tomato, fresh | D2 | wedge | 4 | 20 | – | – | B2 | ✓ |
| `cherry_tomato_whole` | Cherry tomato | D2 | whole | 5 | 18 | – | – | B2 | ✓ |
| `asparagus_whole_spear` | Asparagus | D3 | whole spear | 5 | 12 | 3 | 4 | B2 | ✓ |
| `green_bean_whole` | Green bean | D3 | whole | 7 | 18 | 5 | 6 | B3 | ✓ |
| `broccoli_floret_3cm` | Broccoli floret | D3 | 3cm floret | 7 | 18 | 4 | 5 | B3 | ✓ |
| `cauliflower_floret_3cm` | Cauliflower floret | D3 | 3cm floret | 8 | 22 | 6 | 7 | B3 | ✓ |
| `brussels_sprout_halved` | Brussels sprout | D3 | halved | 9 | 22 | 7 | 8 | B3 | ✓ |
| `fennel_1cm_wedge` | Fennel | D3 | 1cm wedge | 8 | 25 | 7 | 8 | B3 | ✓ |
| `celery_1cm_slice` | Celery | D3 | 1cm slice | 6 | – | 6 | 7 | B3 | ✓ |
| `pak_choi_halved` | Pak choi | D2 | halved | 4 | – | 3 | 4 | B2 | ✓ |
| `carrot_1cm_dice` | Carrot | D4 | 1cm dice | 10 | 25 | 8 | 10 | B4 | ✓ |
| `carrot_5mm_slice` | Carrot | D4 | 5mm slice | 6 | 18 | 5 | 6 | B3 | ✓ |
| `potato_waxy_2cm_dice` | Potato, waxy | D4 | 2cm dice | 15 | 30 | 12 | 15 | B4 | ✓ |
| `potato_waxy_1cm_dice` | Potato, waxy | D4 | 1cm dice | 8 | 20 | 7 | 9 | B3 | ✓ |
| `potato_floury_2cm_dice` | Potato, floury | D4 | 2cm dice | 14 | 30 | 15 | 18 | B4 | ✓ |
| `sweet_potato_2cm_dice` | Sweet potato | D4 | 2cm dice | 12 | 25 | 10 | 12 | B4 | ✓ |
| `parsnip_2cm_dice` | Parsnip | D4 | 2cm dice | 13 | 28 | 10 | 12 | B4 | ✓ |
| `celeriac_2cm_dice` | Celeriac | D4 | 2cm dice | 14 | 30 | 12 | 14 | B4 | ✓ |
| `beetroot_2cm_dice` | Beetroot | D4 | 2cm dice | 20 | 45 | 25 | 25 | B5 | ✓ |
| `swede_2cm_dice` | Swede | D5 | 2cm dice | 18 | 40 | 18 | 20 | B5 | ✓ |
| `turnip_2cm_dice` | Turnip | D5 | 2cm dice | 14 | 30 | 12 | 14 | B4 | ✓ |
| `pumpkin_squash_2cm_dice` | Pumpkin, squash | D5 | 2cm dice | 12 | 28 | 10 | 12 | B4 | ✓ |
| `peas_frozen_whole` | Peas, frozen | D2 | whole | 2 | – | 2 | 3 | B1 | ✓ |
| `sweetcorn_kernels_whole` | Sweetcorn kernels | D2 | whole | 3 | 15 | 3 | 4 | B2 | ✓ |

## 5. Proteins — 21 rows

Page 4. Every row carries a ✓ and no written change.

**Harris's rule, applied to every row in this section** (printed, and the
page-6 checklist item confirming its exact wording is ticked):

> Regardless of the time given, doneness on poultry and pork is verified, never
> assumed. The step must instruct: check core temperature with a thermometer,
> or cut into the thickest part — the flesh should be opaque and white
> throughout with clear juices, no pink flesh and no pink or red juice.
>
> The validator treats a missing verification instruction on a poultry or pork
> step as a flag, independently of whether the stated time looks reasonable.

**Whole-muscle versus minced** (printed as "Point requiring your explicit
confirmation"; the page-6 checklist item *"Confirmed the whole-muscle versus
minced distinction in the proteins section"* is ticked, so it is confirmed):

> Whole-muscle beef and lamb are surface-pathogen cases, so a sear addresses
> them and interior doneness is a preference rather than a safety matter.
> Minced and comminuted meat is not, because surface becomes interior. This is
> the reasoning that makes rare steak acceptable and rare burger not.

| key | Protein | Reference cut | Pan | Roast 200C | Simmer | Band | Verify by | Harris's mark |
|---|---|---|---|---|---|---|---|---|
| `chicken_breast_whole_2_5cm` | Chicken breast | whole, 2.5cm | 14 | 20 | 15 | B4 | Yes | ✓ |
| `chicken_breast_2cm_strips` | Chicken breast | 2cm strips | 7 | – | 8 | B3 | Yes | ✓ |
| `chicken_breast_2cm_dice` | Chicken breast | 2cm dice | 8 | 18 | 9 | B3 | Yes | ✓ |
| `chicken_thigh_boneless_whole` | Chicken thigh, boneless | whole | 16 | 30 | 25 | B5 | Yes | ✓ |
| `chicken_thigh_2cm_dice` | Chicken thigh | 2cm dice | 10 | 22 | 15 | B4 | Yes | ✓ |
| `chicken_bone_in_whole_pieces` | Chicken, bone-in | whole pieces | – | 40 | 35 | B6 | Yes | ✓ |
| `turkey_breast_2cm_dice` | Turkey breast | 2cm dice | 8 | 18 | 9 | B3 | Yes | ✓ |
| `pork_loin_2cm_medallion` | Pork loin | 2cm medallion | 8 | 20 | – | B3 | Yes | ✓ |
| `pork_diced_2cm_dice` | Pork, diced | 2cm dice | 10 | 22 | 45 | B4 | Yes | ✓ |
| `pork_mince_loose` | Pork mince | loose | 8 | – | – | B3 | Yes | ✓ |
| `sausage_whole` | Sausage | whole | 12 | 25 | – | B4 | Yes | ✓ |
| `beef_mince_loose` | Beef mince | loose | 8 | – | – | B3 | Colour through | ✓ |
| `beef_steak_2cm_med_rare` | Beef steak | 2cm, med-rare | 6 | – | – | B3 | Surface sear | ✓ |
| `beef_stewing_3cm_dice` | Beef, stewing | 3cm dice | sear 8 | – | 120 | B6 | Tenderness | ✓ |
| `lamb_diced_2cm_dice` | Lamb, diced | 2cm dice | 8 | 22 | 90 | B3 / B6 | Surface sear | ✓ |
| `white_fish_fillet_2cm_thick` | White fish fillet | 2cm thick | 7 | 12 | 8 | B3 | Flakes, opaque | ✓ |
| `salmon_fillet_2_5cm_thick` | Salmon fillet | 2.5cm thick | 8 | 14 | – | B3 | Opaque at edge | ✓ |
| `prawns_raw_peeled` | Prawns, raw | peeled | 3 | – | 3 | B2 | Opaque, curled | ✓ |
| `egg_scrambled_beaten` | Egg, scrambled | beaten | 3 | – | – | B2 | Set | ✓ |
| `halloumi_1cm_slice` | Halloumi | 1cm slice | 4 | – | – | B2 | Colour | ✓ |
| `tofu_firm_2cm_cube` | Tofu, firm | 2cm cube | 8 | 20 | – | B3 | Colour | ✓ |

> `lamb_diced_2cm_dice` carries **two bands, "B3 / B6"**, as printed. It is the
> only dual-band row on the sheet — presumably fast-fry versus braise. Left
> exactly as written; the next build has to decide how a dual band resolves.

## 6. Starches and grains — 11 rows

Pages 4–5. **This is the only section with written corrections.**

| key | Item | Reference | Time | Band | Harris's mark |
|---|---|---|---|---|---|
| `dried_pasta` | Dried pasta | – | 9 | B3 | *"package instructions + trying"* |
| `fresh_pasta` | Fresh pasta | – | 3 | B2 | ✓ ⚠ **[FLAG-2]** — tick sits between this row and the next |
| `white_rice_absorption` | White rice | absorption | 18 | B5 | *"package instructions or experience"* ⚠ **[FLAG-1]** |
| `risotto_rice_stirred` | Risotto rice | stirred | 20 | B5 | *"16–20 min."* ⚠ **[FLAG-1]** — may belong to White rice above |
| `brown_rice_absorption` | Brown rice | absorption | 35 | B6 | *"always try / don't trust time"* |
| `couscous_steeped` | Couscous | steeped | 5 | B2 | ✓ |
| `bulgur_absorption` | Bulgur | absorption | 12 | B4 | ✓ |
| `red_lentils_simmer` | Red lentils | simmer | 18 | B5 | *"even faster"* ⚠ **[FLAG-3]** — no replacement value given |
| `green_puy_lentils_simmer` | Green, Puy lentils | simmer | 30 | B6 | ✓ |
| `quinoa_absorption` | Quinoa | absorption | 15 | B4 | ✓ |
| `gnocchi_fresh_boil` | Gnocchi, fresh | boil | 3 | B2 | ✓ |

**What the starch annotations mean for the validator.** Three of them
("package instructions + trying", "package instructions or experience",
"always try / don't trust time") are not numeric corrections — they say the
printed number is an estimate and the package or the cook's own taste
overrides it. That is a *behaviour* instruction, not a value, and the next
build needs a ruling on how it is encoded (see [FLAG-4]).

## 7. How the validator uses this

Printed on page 6, unmodified:

1. Read each step's `ingredients_added` and the cut declared for each ingredient.
2. Resolve every ingredient to a band via the table, the class default, and size scaling.
3. Within a single step, compare bands. More than one band apart is a flag.
4. Compare each ingredient's band against the step's stated duration. Materially longer is a flag.
5. Any poultry or pork step without a verification instruction is a flag, regardless of time.
6. On flag, inject a correction and regenerate rather than blocking the user.

## 8. Sign-off block, as it appears on page 6

| Reviewed and corrected by | Date | Version |
|---|---|---|
| Chef Harris *(handwritten, with signature)* | 17.08.2026 | 0.1 |

Review checklist — **all seven ticked**:

- ✓ Corrected any time that is wrong. These were drafts. *(a second tick appears in this row's Notes column)*
- ✓ Confirmed or replaced the four size-scaling multipliers.
- ✓ Confirmed the one-band tolerance is the right compatibility rule.
- ✓ Confirmed the whole-muscle versus minced distinction in the proteins section.
- ✓ Confirmed the exact wording of the doneness verification instruction.
- ✓ Added any ingredient common in Swiss home kitchens that is missing.
- ✓ Confirmed the band definitions match how the app should actually behave.

## 9. Row counts

| Section | Rows |
|---|---|
| Vegetables | 42 |
| Proteins | 21 |
| Starches and grains | 11 |
| **Total** | **74** |

Plus 6 bands, 4 scaling multipliers, 4 shape adjustments, 5 density classes.

> **Note for the next build.** The session prompt anticipated "~26 declared
> keys, Option C". The paper carries **74 ingredient rows**. If the model is to
> declare a key from a closed list, that list either is 74 long or is a coarser
> vocabulary that these 74 rows resolve into. That is a design decision, not a
> transcription one, and it is not answered anywhere on the paper.
