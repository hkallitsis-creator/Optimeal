// GENERATED-FROM-DOC. The authority for every row below is
// `docs/cooking_times_table.md`, which is itself a transcription of Chef
// Harris's signed paper worksheet (`docs/scans/`, signed 17.08.2026, v0.1).
//
// Do NOT hand-edit the row list to change a band or a minute figure. Change
// the markdown table, then re-derive. `test/data/cooking_times_parity_test.dart`
// re-parses the committed markdown on every run and fails loudly if this file
// and the doc disagree on row count, key set, band, or any numeric minute.
//
// This is the fifth instance of the project's closed-vocabulary pattern (after
// the cut vocabulary, `curriculum_lesson_id`, `sensory_cue` and
// `technique_diagram_id`): the model declares a key from a closed list, and the
// APP resolves that key to authoritative numbers locally. Per the signed
// option-C decision (`docs/DECISIONS.md`, 21 August 2026) the model never
// states an authoritative cooking time — it only names which row it means.

import 'package:flutter/foundation.dart';

/// The six time bands from section 1 of the signed table. Bands, not raw
/// minutes, are what compatibility is judged on.
enum CookBand { b1, b2, b3, b4, b5, b6 }

extension CookBandInfo on CookBand {
  /// `'B1'` … `'B6'` — the form used in the doc, in prompts and in flag logs.
  String get label => 'B${index + 1}';

  /// Inclusive lower bound in minutes.
  int get minMinutes => const [0, 3, 6, 10, 16, 26][index];

  /// Inclusive upper bound in minutes; null for the open-ended B6.
  int? get maxMinutes => const [2, 5, 9, 15, 25, null][index];

  /// A single representative figure for the band, used when a row has a band
  /// but no minute figure for the method in hand. B6 is open-ended, so it
  /// takes its lower bound.
  int get representativeMinutes =>
      maxMinutes == null ? minMinutes : ((minMinutes + maxMinutes!) / 2).round();

  /// How many bands apart two bands are. `0` = same band, `1` = adjacent.
  int distanceTo(CookBand other) => (index - other.index).abs();
}

/// Maps a scaled time in minutes back onto a band. This is the direction the
/// signed size-scaling rule runs in: multiply the reference time, then see
/// which band the result lands in (see [SizeRelativeToReference]).
CookBand bandForMinutes(num minutes) {
  final m = minutes.round();
  if (m <= 2) return CookBand.b1;
  if (m <= 5) return CookBand.b2;
  if (m <= 9) return CookBand.b3;
  if (m <= 15) return CookBand.b4;
  if (m <= 25) return CookBand.b5;
  return CookBand.b6;
}

/// Which of the three tables in the doc a row came from.
enum CookingTimeSection { vegetables, proteins, starches }

/// The five density classes from section 3, used to place an ingredient that
/// has no row of its own. Carried on vegetable rows only, as in the doc.
enum DensityClass { d1, d2, d3, d4, d5 }

extension DensityClassInfo on DensityClass {
  String get label => 'D${index + 1}';

  /// Default band at a 1cm reference cut. D5 is a two-band range in the doc;
  /// its lower bound is used here and its full range is [defaultBandRange].
  CookBand get defaultBand => const [
        CookBand.b1,
        CookBand.b2,
        CookBand.b3,
        CookBand.b4,
        CookBand.b4,
      ][index];

  List<CookBand> get defaultBandRange => index == 4
      ? const [CookBand.b4, CookBand.b5]
      : [defaultBand];
}

/// Thickness relative to a row's own reference cut. The four multipliers are
/// signed and stand as printed (section 2 of the doc). Note these are TIME
/// multipliers, not band shifts — the doc calls this out explicitly, because
/// the two are not equivalent (x0.4 on a 12 min B4 gives 4.8 min, a B2, which
/// is a two-band drop).
enum SizeRelativeToReference { half, reference, double, triple }

extension SizeMultiplier on SizeRelativeToReference {
  double get multiplier => const [0.4, 1.0, 2.5, 5.0][index];
}

/// Shape adjustments, applied after thickness scaling (section 2).
enum CutShape {
  /// Same shape as the row's reference cut — no adjustment.
  asReference,

  /// Strips, julienne, batons: smallest dimension, then x0.8.
  stripsJulienneBatons,

  /// Whole and round items: x1.5 on top of thickness scaling.
  wholeOrRound,

  /// Shredded or grated: always B1, regardless of density. Short-circuits
  /// every other factor.
  shreddedOrGrated,

  /// Sliced discs: go by disc thickness only — no extra factor of its own.
  slicedDiscs,
}

extension CutShapeFactor on CutShape {
  double get factor => const [1.0, 0.8, 1.5, 1.0, 1.0][index];

  bool get forcesB1 => this == CutShape.shreddedOrGrated;
}

/// One row of the signed table.
@immutable
class CookingTimeRow {
  const CookingTimeRow({
    required this.key,
    required this.name,
    required this.section,
    required this.referenceCut,
    required this.minutes,
    required this.bands,
    this.densityClass,
    this.minutesAdvisory = false,
    this.bandPending = false,
  });

  /// The declarable key. This is what the model puts in `cooking_times_key`.
  final String key;

  /// Human-readable ingredient name, as printed.
  final String name;

  final CookingTimeSection section;

  /// The cut the [minutes] figures assume. Scaling is relative to this.
  final String referenceCut;

  /// Method name to minutes. Vegetables use `saute`/`roast`/`boil`/`steam`,
  /// proteins `pan`/`roast`/`simmer`, starches the single key `time`. A method
  /// the doc leaves blank for a row is simply absent here.
  final Map<String, int> minutes;

  /// Normally one band. Two rows are exceptions:
  ///  * `lamb_diced_2cm_dice` carries a dual band (B3 pan-fried / B6 braised)
  ///    — the sheet's only dual-band row, and unresolved on paper.
  ///  * `red_lentils_simmer` carries none — see [bandPending].
  final List<CookBand> bands;

  /// Vegetables only; null elsewhere, matching the doc.
  final DensityClass? densityClass;

  /// True for the three rows Harris ruled are governed by the packet
  /// ("package instructions but always try as well"): dried pasta, white rice,
  /// brown rice. Their band stands and is checked; their minute figure is
  /// advisory and must never on its own produce a duration flag.
  final bool minutesAdvisory;

  /// True only for `red_lentils_simmer`, whose figure Harris marked pending
  /// ("even faster" than the printed 18 min, no number given). Every timing
  /// check skips a pending row. Closing this is a one-number edit to the doc:
  /// fill in the time and band cells and re-derive.
  final bool bandPending;

  /// True when this row is minced/comminuted rather than whole muscle.
  /// DERIVED, not a column in the doc — the doc encodes the distinction in the
  /// row identity itself (`beef_mince_loose` vs `beef_steak_2cm_med_rare`).
  /// Kept as an explicit set rather than substring matching so it cannot drift
  /// silently as keys are added.
  bool get isComminuted => _comminutedKeys.contains(key);

  @override
  String toString() => 'CookingTimeRow($key, ${bands.map((b) => b.label).join('/')})';
}

const Set<String> _comminutedKeys = {
  'pork_mince_loose',
  'beef_mince_loose',
  'sausage_whole',
};

const List<CookingTimeRow> _rows = [
  CookingTimeRow(
    key: 'spinach_whole_leaf',
    name: 'Spinach',
    section: CookingTimeSection.vegetables,
    referenceCut: 'whole leaf',
    densityClass: DensityClass.d1,
    minutes: {'saute': 1, 'boil': 1, 'steam': 2},
    bands: [CookBand.b1],
  ),
  CookingTimeRow(
    key: 'rocket_whole_leaf',
    name: 'Rocket',
    section: CookingTimeSection.vegetables,
    referenceCut: 'whole leaf',
    densityClass: DensityClass.d1,
    minutes: {'saute': 1},
    bands: [CookBand.b1],
  ),
  CookingTimeRow(
    key: 'chard_leaf_ribbon',
    name: 'Chard leaf',
    section: CookingTimeSection.vegetables,
    referenceCut: 'ribbon',
    densityClass: DensityClass.d1,
    minutes: {'saute': 2, 'boil': 2, 'steam': 3},
    bands: [CookBand.b1],
  ),
  CookingTimeRow(
    key: 'chard_stem_1cm',
    name: 'Chard stem',
    section: CookingTimeSection.vegetables,
    referenceCut: '1cm',
    densityClass: DensityClass.d3,
    minutes: {'saute': 6, 'roast': 15, 'boil': 6, 'steam': 8},
    bands: [CookBand.b3],
  ),
  CookingTimeRow(
    key: 'kale_torn',
    name: 'Kale',
    section: CookingTimeSection.vegetables,
    referenceCut: 'torn',
    densityClass: DensityClass.d1,
    minutes: {'saute': 4, 'roast': 10, 'boil': 4, 'steam': 5},
    bands: [CookBand.b2],
  ),
  CookingTimeRow(
    key: 'cabbage_1cm_ribbon',
    name: 'Cabbage',
    section: CookingTimeSection.vegetables,
    referenceCut: '1cm ribbon',
    densityClass: DensityClass.d3,
    minutes: {'saute': 6, 'roast': 20, 'boil': 6, 'steam': 8},
    bands: [CookBand.b3],
  ),
  CookingTimeRow(
    key: 'spring_onion_1cm',
    name: 'Spring onion',
    section: CookingTimeSection.vegetables,
    referenceCut: '1cm',
    densityClass: DensityClass.d2,
    minutes: {'saute': 2},
    bands: [CookBand.b1],
  ),
  CookingTimeRow(
    key: 'onion_soften_1cm_dice',
    name: 'Onion, soften',
    section: CookingTimeSection.vegetables,
    referenceCut: '1cm dice',
    densityClass: DensityClass.d2,
    minutes: {'saute': 5, 'roast': 25},
    bands: [CookBand.b2],
  ),
  CookingTimeRow(
    key: 'onion_caramelise_1cm_dice',
    name: 'Onion, caramelise',
    section: CookingTimeSection.vegetables,
    referenceCut: '1cm dice',
    densityClass: DensityClass.d2,
    minutes: {'saute': 35},
    bands: [CookBand.b6],
  ),
  CookingTimeRow(
    key: 'shallot_sliced',
    name: 'Shallot',
    section: CookingTimeSection.vegetables,
    referenceCut: 'sliced',
    densityClass: DensityClass.d2,
    minutes: {'saute': 4, 'roast': 20},
    bands: [CookBand.b2],
  ),
  CookingTimeRow(
    key: 'garlic_minced',
    name: 'Garlic',
    section: CookingTimeSection.vegetables,
    referenceCut: 'minced',
    densityClass: DensityClass.d2,
    minutes: {'saute': 1},
    bands: [CookBand.b1],
  ),
  CookingTimeRow(
    key: 'leek_1cm_slice',
    name: 'Leek',
    section: CookingTimeSection.vegetables,
    referenceCut: '1cm slice',
    densityClass: DensityClass.d3,
    minutes: {'saute': 6, 'roast': 20, 'boil': 6, 'steam': 7},
    bands: [CookBand.b3],
  ),
  CookingTimeRow(
    key: 'mushroom_button_quartered',
    name: 'Mushroom, button',
    section: CookingTimeSection.vegetables,
    referenceCut: 'quartered',
    densityClass: DensityClass.d2,
    minutes: {'saute': 6, 'roast': 18},
    bands: [CookBand.b3],
  ),
  CookingTimeRow(
    key: 'mushroom_sliced_5mm',
    name: 'Mushroom, sliced',
    section: CookingTimeSection.vegetables,
    referenceCut: '5mm slice',
    densityClass: DensityClass.d2,
    minutes: {'saute': 4, 'roast': 15},
    bands: [CookBand.b2],
  ),
  CookingTimeRow(
    key: 'courgette_1cm_dice',
    name: 'Courgette',
    section: CookingTimeSection.vegetables,
    referenceCut: '1cm dice',
    densityClass: DensityClass.d2,
    minutes: {'saute': 5, 'roast': 18, 'boil': 4, 'steam': 5},
    bands: [CookBand.b2],
  ),
  CookingTimeRow(
    key: 'aubergine_2cm_dice',
    name: 'Aubergine',
    section: CookingTimeSection.vegetables,
    referenceCut: '2cm dice',
    densityClass: DensityClass.d2,
    minutes: {'saute': 9, 'roast': 25},
    bands: [CookBand.b3],
  ),
  CookingTimeRow(
    key: 'bell_pepper_2cm_piece',
    name: 'Bell pepper',
    section: CookingTimeSection.vegetables,
    referenceCut: '2cm piece',
    densityClass: DensityClass.d2,
    minutes: {'saute': 6, 'roast': 20},
    bands: [CookBand.b3],
  ),
  CookingTimeRow(
    key: 'bell_pepper_1cm_strip',
    name: 'Bell pepper',
    section: CookingTimeSection.vegetables,
    referenceCut: '1cm strip',
    densityClass: DensityClass.d2,
    minutes: {'saute': 4, 'roast': 15},
    bands: [CookBand.b2],
  ),
  CookingTimeRow(
    key: 'tomato_fresh_wedge',
    name: 'Tomato, fresh',
    section: CookingTimeSection.vegetables,
    referenceCut: 'wedge',
    densityClass: DensityClass.d2,
    minutes: {'saute': 4, 'roast': 20},
    bands: [CookBand.b2],
  ),
  CookingTimeRow(
    key: 'cherry_tomato_whole',
    name: 'Cherry tomato',
    section: CookingTimeSection.vegetables,
    referenceCut: 'whole',
    densityClass: DensityClass.d2,
    minutes: {'saute': 5, 'roast': 18},
    bands: [CookBand.b2],
  ),
  CookingTimeRow(
    key: 'asparagus_whole_spear',
    name: 'Asparagus',
    section: CookingTimeSection.vegetables,
    referenceCut: 'whole spear',
    densityClass: DensityClass.d3,
    minutes: {'saute': 5, 'roast': 12, 'boil': 3, 'steam': 4},
    bands: [CookBand.b2],
  ),
  CookingTimeRow(
    key: 'green_bean_whole',
    name: 'Green bean',
    section: CookingTimeSection.vegetables,
    referenceCut: 'whole',
    densityClass: DensityClass.d3,
    minutes: {'saute': 7, 'roast': 18, 'boil': 5, 'steam': 6},
    bands: [CookBand.b3],
  ),
  CookingTimeRow(
    key: 'broccoli_floret_3cm',
    name: 'Broccoli floret',
    section: CookingTimeSection.vegetables,
    referenceCut: '3cm floret',
    densityClass: DensityClass.d3,
    minutes: {'saute': 7, 'roast': 18, 'boil': 4, 'steam': 5},
    bands: [CookBand.b3],
  ),
  CookingTimeRow(
    key: 'cauliflower_floret_3cm',
    name: 'Cauliflower floret',
    section: CookingTimeSection.vegetables,
    referenceCut: '3cm floret',
    densityClass: DensityClass.d3,
    minutes: {'saute': 8, 'roast': 22, 'boil': 6, 'steam': 7},
    bands: [CookBand.b3],
  ),
  CookingTimeRow(
    key: 'brussels_sprout_halved',
    name: 'Brussels sprout',
    section: CookingTimeSection.vegetables,
    referenceCut: 'halved',
    densityClass: DensityClass.d3,
    minutes: {'saute': 9, 'roast': 22, 'boil': 7, 'steam': 8},
    bands: [CookBand.b3],
  ),
  CookingTimeRow(
    key: 'fennel_1cm_wedge',
    name: 'Fennel',
    section: CookingTimeSection.vegetables,
    referenceCut: '1cm wedge',
    densityClass: DensityClass.d3,
    minutes: {'saute': 8, 'roast': 25, 'boil': 7, 'steam': 8},
    bands: [CookBand.b3],
  ),
  CookingTimeRow(
    key: 'celery_1cm_slice',
    name: 'Celery',
    section: CookingTimeSection.vegetables,
    referenceCut: '1cm slice',
    densityClass: DensityClass.d3,
    minutes: {'saute': 6, 'boil': 6, 'steam': 7},
    bands: [CookBand.b3],
  ),
  CookingTimeRow(
    key: 'pak_choi_halved',
    name: 'Pak choi',
    section: CookingTimeSection.vegetables,
    referenceCut: 'halved',
    densityClass: DensityClass.d2,
    minutes: {'saute': 4, 'boil': 3, 'steam': 4},
    bands: [CookBand.b2],
  ),
  CookingTimeRow(
    key: 'carrot_1cm_dice',
    name: 'Carrot',
    section: CookingTimeSection.vegetables,
    referenceCut: '1cm dice',
    densityClass: DensityClass.d4,
    minutes: {'saute': 10, 'roast': 25, 'boil': 8, 'steam': 10},
    bands: [CookBand.b4],
  ),
  CookingTimeRow(
    key: 'carrot_5mm_slice',
    name: 'Carrot',
    section: CookingTimeSection.vegetables,
    referenceCut: '5mm slice',
    densityClass: DensityClass.d4,
    minutes: {'saute': 6, 'roast': 18, 'boil': 5, 'steam': 6},
    bands: [CookBand.b3],
  ),
  CookingTimeRow(
    key: 'potato_waxy_2cm_dice',
    name: 'Potato, waxy',
    section: CookingTimeSection.vegetables,
    referenceCut: '2cm dice',
    densityClass: DensityClass.d4,
    minutes: {'saute': 15, 'roast': 30, 'boil': 12, 'steam': 15},
    bands: [CookBand.b4],
  ),
  CookingTimeRow(
    key: 'potato_waxy_1cm_dice',
    name: 'Potato, waxy',
    section: CookingTimeSection.vegetables,
    referenceCut: '1cm dice',
    densityClass: DensityClass.d4,
    minutes: {'saute': 8, 'roast': 20, 'boil': 7, 'steam': 9},
    bands: [CookBand.b3],
  ),
  CookingTimeRow(
    key: 'potato_floury_2cm_dice',
    name: 'Potato, floury',
    section: CookingTimeSection.vegetables,
    referenceCut: '2cm dice',
    densityClass: DensityClass.d4,
    minutes: {'saute': 14, 'roast': 30, 'boil': 15, 'steam': 18},
    bands: [CookBand.b4],
  ),
  CookingTimeRow(
    key: 'sweet_potato_2cm_dice',
    name: 'Sweet potato',
    section: CookingTimeSection.vegetables,
    referenceCut: '2cm dice',
    densityClass: DensityClass.d4,
    minutes: {'saute': 12, 'roast': 25, 'boil': 10, 'steam': 12},
    bands: [CookBand.b4],
  ),
  CookingTimeRow(
    key: 'parsnip_2cm_dice',
    name: 'Parsnip',
    section: CookingTimeSection.vegetables,
    referenceCut: '2cm dice',
    densityClass: DensityClass.d4,
    minutes: {'saute': 13, 'roast': 28, 'boil': 10, 'steam': 12},
    bands: [CookBand.b4],
  ),
  CookingTimeRow(
    key: 'celeriac_2cm_dice',
    name: 'Celeriac',
    section: CookingTimeSection.vegetables,
    referenceCut: '2cm dice',
    densityClass: DensityClass.d4,
    minutes: {'saute': 14, 'roast': 30, 'boil': 12, 'steam': 14},
    bands: [CookBand.b4],
  ),
  CookingTimeRow(
    key: 'beetroot_2cm_dice',
    name: 'Beetroot',
    section: CookingTimeSection.vegetables,
    referenceCut: '2cm dice',
    densityClass: DensityClass.d4,
    minutes: {'saute': 20, 'roast': 45, 'boil': 25, 'steam': 25},
    bands: [CookBand.b5],
  ),
  CookingTimeRow(
    key: 'swede_2cm_dice',
    name: 'Swede',
    section: CookingTimeSection.vegetables,
    referenceCut: '2cm dice',
    densityClass: DensityClass.d5,
    minutes: {'saute': 18, 'roast': 40, 'boil': 18, 'steam': 20},
    bands: [CookBand.b5],
  ),
  CookingTimeRow(
    key: 'turnip_2cm_dice',
    name: 'Turnip',
    section: CookingTimeSection.vegetables,
    referenceCut: '2cm dice',
    densityClass: DensityClass.d5,
    minutes: {'saute': 14, 'roast': 30, 'boil': 12, 'steam': 14},
    bands: [CookBand.b4],
  ),
  CookingTimeRow(
    key: 'pumpkin_squash_2cm_dice',
    name: 'Pumpkin, squash',
    section: CookingTimeSection.vegetables,
    referenceCut: '2cm dice',
    densityClass: DensityClass.d5,
    minutes: {'saute': 12, 'roast': 28, 'boil': 10, 'steam': 12},
    bands: [CookBand.b4],
  ),
  CookingTimeRow(
    key: 'peas_frozen_whole',
    name: 'Peas, frozen',
    section: CookingTimeSection.vegetables,
    referenceCut: 'whole',
    densityClass: DensityClass.d2,
    minutes: {'saute': 2, 'boil': 2, 'steam': 3},
    bands: [CookBand.b1],
  ),
  CookingTimeRow(
    key: 'sweetcorn_kernels_whole',
    name: 'Sweetcorn kernels',
    section: CookingTimeSection.vegetables,
    referenceCut: 'whole',
    densityClass: DensityClass.d2,
    minutes: {'saute': 3, 'roast': 15, 'boil': 3, 'steam': 4},
    bands: [CookBand.b2],
  ),
  CookingTimeRow(
    key: 'chicken_breast_whole_2_5cm',
    name: 'Chicken breast',
    section: CookingTimeSection.proteins,
    referenceCut: 'whole, 2.5cm',
    minutes: {'pan': 14, 'roast': 20, 'simmer': 15},
    bands: [CookBand.b4],
  ),
  CookingTimeRow(
    key: 'chicken_breast_2cm_strips',
    name: 'Chicken breast',
    section: CookingTimeSection.proteins,
    referenceCut: '2cm strips',
    minutes: {'pan': 7, 'simmer': 8},
    bands: [CookBand.b3],
  ),
  CookingTimeRow(
    key: 'chicken_breast_2cm_dice',
    name: 'Chicken breast',
    section: CookingTimeSection.proteins,
    referenceCut: '2cm dice',
    minutes: {'pan': 8, 'roast': 18, 'simmer': 9},
    bands: [CookBand.b3],
  ),
  CookingTimeRow(
    key: 'chicken_thigh_boneless_whole',
    name: 'Chicken thigh, boneless',
    section: CookingTimeSection.proteins,
    referenceCut: 'whole',
    minutes: {'pan': 16, 'roast': 30, 'simmer': 25},
    bands: [CookBand.b5],
  ),
  CookingTimeRow(
    key: 'chicken_thigh_2cm_dice',
    name: 'Chicken thigh',
    section: CookingTimeSection.proteins,
    referenceCut: '2cm dice',
    minutes: {'pan': 10, 'roast': 22, 'simmer': 15},
    bands: [CookBand.b4],
  ),
  CookingTimeRow(
    key: 'chicken_bone_in_whole_pieces',
    name: 'Chicken, bone-in',
    section: CookingTimeSection.proteins,
    referenceCut: 'whole pieces',
    minutes: {'roast': 40, 'simmer': 35},
    bands: [CookBand.b6],
  ),
  CookingTimeRow(
    key: 'turkey_breast_2cm_dice',
    name: 'Turkey breast',
    section: CookingTimeSection.proteins,
    referenceCut: '2cm dice',
    minutes: {'pan': 8, 'roast': 18, 'simmer': 9},
    bands: [CookBand.b3],
  ),
  CookingTimeRow(
    key: 'pork_loin_2cm_medallion',
    name: 'Pork loin',
    section: CookingTimeSection.proteins,
    referenceCut: '2cm medallion',
    minutes: {'pan': 8, 'roast': 20},
    bands: [CookBand.b3],
  ),
  CookingTimeRow(
    key: 'pork_diced_2cm_dice',
    name: 'Pork, diced',
    section: CookingTimeSection.proteins,
    referenceCut: '2cm dice',
    minutes: {'pan': 10, 'roast': 22, 'simmer': 45},
    bands: [CookBand.b4],
  ),
  CookingTimeRow(
    key: 'pork_mince_loose',
    name: 'Pork mince',
    section: CookingTimeSection.proteins,
    referenceCut: 'loose',
    minutes: {'pan': 8},
    bands: [CookBand.b3],
  ),
  CookingTimeRow(
    key: 'sausage_whole',
    name: 'Sausage',
    section: CookingTimeSection.proteins,
    referenceCut: 'whole',
    minutes: {'pan': 12, 'roast': 25},
    bands: [CookBand.b4],
  ),
  CookingTimeRow(
    key: 'beef_mince_loose',
    name: 'Beef mince',
    section: CookingTimeSection.proteins,
    referenceCut: 'loose',
    minutes: {'pan': 8},
    bands: [CookBand.b3],
  ),
  CookingTimeRow(
    key: 'beef_steak_2cm_med_rare',
    name: 'Beef steak',
    section: CookingTimeSection.proteins,
    referenceCut: '2cm, med-rare',
    minutes: {'pan': 6},
    bands: [CookBand.b3],
  ),
  CookingTimeRow(
    key: 'beef_stewing_3cm_dice',
    name: 'Beef, stewing',
    section: CookingTimeSection.proteins,
    referenceCut: '3cm dice',
    minutes: {'pan': 8, 'simmer': 120},
    bands: [CookBand.b6],
  ),
  CookingTimeRow(
    key: 'lamb_diced_2cm_dice',
    name: 'Lamb, diced',
    section: CookingTimeSection.proteins,
    referenceCut: '2cm dice',
    minutes: {'pan': 8, 'roast': 22, 'simmer': 90},
    bands: [CookBand.b3, CookBand.b6],
  ),
  CookingTimeRow(
    key: 'white_fish_fillet_2cm_thick',
    name: 'White fish fillet',
    section: CookingTimeSection.proteins,
    referenceCut: '2cm thick',
    minutes: {'pan': 7, 'roast': 12, 'simmer': 8},
    bands: [CookBand.b3],
  ),
  CookingTimeRow(
    key: 'salmon_fillet_2_5cm_thick',
    name: 'Salmon fillet',
    section: CookingTimeSection.proteins,
    referenceCut: '2.5cm thick',
    minutes: {'pan': 8, 'roast': 14},
    bands: [CookBand.b3],
  ),
  CookingTimeRow(
    key: 'prawns_raw_peeled',
    name: 'Prawns, raw',
    section: CookingTimeSection.proteins,
    referenceCut: 'peeled',
    minutes: {'pan': 3, 'simmer': 3},
    bands: [CookBand.b2],
  ),
  CookingTimeRow(
    key: 'egg_scrambled_beaten',
    name: 'Egg, scrambled',
    section: CookingTimeSection.proteins,
    referenceCut: 'beaten',
    minutes: {'pan': 3},
    bands: [CookBand.b2],
  ),
  CookingTimeRow(
    key: 'halloumi_1cm_slice',
    name: 'Halloumi',
    section: CookingTimeSection.proteins,
    referenceCut: '1cm slice',
    minutes: {'pan': 4},
    bands: [CookBand.b2],
  ),
  CookingTimeRow(
    key: 'tofu_firm_2cm_cube',
    name: 'Tofu, firm',
    section: CookingTimeSection.proteins,
    referenceCut: '2cm cube',
    minutes: {'pan': 8, 'roast': 20},
    bands: [CookBand.b3],
  ),
  CookingTimeRow(
    key: 'dried_pasta',
    name: 'Dried pasta',
    section: CookingTimeSection.starches,
    referenceCut: '–',
    minutes: {'time': 9},
    bands: [CookBand.b3],
    minutesAdvisory: true,
  ),
  CookingTimeRow(
    key: 'fresh_pasta',
    name: 'Fresh pasta',
    section: CookingTimeSection.starches,
    referenceCut: '–',
    minutes: {'time': 3},
    bands: [CookBand.b2],
  ),
  CookingTimeRow(
    key: 'white_rice_absorption',
    name: 'White rice',
    section: CookingTimeSection.starches,
    referenceCut: 'absorption',
    minutes: {'time': 18},
    bands: [CookBand.b5],
    minutesAdvisory: true,
  ),
  CookingTimeRow(
    key: 'risotto_rice_stirred',
    name: 'Risotto rice',
    section: CookingTimeSection.starches,
    referenceCut: 'stirred',
    minutes: {'time': 16},
    bands: [CookBand.b5],
  ),
  CookingTimeRow(
    key: 'brown_rice_absorption',
    name: 'Brown rice',
    section: CookingTimeSection.starches,
    referenceCut: 'absorption',
    minutes: {'time': 35},
    bands: [CookBand.b6],
    minutesAdvisory: true,
  ),
  CookingTimeRow(
    key: 'couscous_steeped',
    name: 'Couscous',
    section: CookingTimeSection.starches,
    referenceCut: 'steeped',
    minutes: {'time': 5},
    bands: [CookBand.b2],
  ),
  CookingTimeRow(
    key: 'bulgur_absorption',
    name: 'Bulgur',
    section: CookingTimeSection.starches,
    referenceCut: 'absorption',
    minutes: {'time': 12},
    bands: [CookBand.b4],
  ),
  CookingTimeRow(
    key: 'red_lentils_simmer',
    name: 'Red lentils',
    section: CookingTimeSection.starches,
    referenceCut: 'simmer',
    minutes: {},
    bands: [],
    bandPending: true,
  ),
  CookingTimeRow(
    key: 'green_puy_lentils_simmer',
    name: 'Green, Puy lentils',
    section: CookingTimeSection.starches,
    referenceCut: 'simmer',
    minutes: {'time': 30},
    bands: [CookBand.b6],
  ),
  CookingTimeRow(
    key: 'quinoa_absorption',
    name: 'Quinoa',
    section: CookingTimeSection.starches,
    referenceCut: 'absorption',
    minutes: {'time': 15},
    bands: [CookBand.b4],
  ),
  CookingTimeRow(
    key: 'gnocchi_fresh_boil',
    name: 'Gnocchi, fresh',
    section: CookingTimeSection.starches,
    referenceCut: 'boil',
    minutes: {'time': 3},
    bands: [CookBand.b2],
  ),
];

/// Lookup and resolution over the signed table.
abstract final class CookingTimes {
  /// Every row, doc order (vegetables, then proteins, then starches).
  static const List<CookingTimeRow> rows = _rows;

  static final Map<String, CookingTimeRow> _byKey = {
    for (final r in _rows) r.key: r,
  };

  /// The closed key list. This is the vocabulary the model may declare from;
  /// anything outside it is rejected on the way back in.
  static final Set<String> allKeys = _byKey.keys.toSet();

  static CookingTimeRow? row(String? key) => key == null ? null : _byKey[key];

  static bool isKnown(String? key) => key != null && _byKey.containsKey(key);

  /// True when a row exists but carries no usable band — today only
  /// `red_lentils_simmer`. Timing checks skip these by construction.
  static bool isTimingPending(String? key) => row(key)?.bandPending ?? false;

  /// True for the three package-instruction rows. Their band is still checked
  /// for compatibility; their minutes never produce a duration flag.
  static bool hasAdvisoryMinutes(String? key) => row(key)?.minutesAdvisory ?? false;

  /// Resolves a declared key to the band(s) it cooks in, applying the signed
  /// size and shape scaling.
  ///
  /// Returns an empty list when the key is unknown or its timing is pending —
  /// both of which mean "no check possible here", which is the fail-open
  /// outcome by construction rather than by a special case downstream.
  ///
  /// In normal operation [size] and [shape] are left at their defaults: the
  /// declared key already encodes its own cut (`potato_waxy_1cm_dice` vs
  /// `potato_waxy_2cm_dice` are separate rows), so the model picks the row
  /// that matches what it wrote and no scaling is needed. The parameters exist
  /// for the case where a caller genuinely knows the recipe deviates from the
  /// reference cut, and so that the signed multipliers live in code rather
  /// than only in a document.
  static List<CookBand> resolveBands(
    String? key, {
    SizeRelativeToReference size = SizeRelativeToReference.reference,
    CutShape shape = CutShape.asReference,
    String? method,
  }) {
    final r = row(key);
    if (r == null || r.bandPending) return const [];

    if (shape.forcesB1) return const [CookBand.b1];

    final unscaled = size == SizeRelativeToReference.reference && shape.factor == 1.0;
    if (unscaled) return List.unmodifiable(r.bands);

    final factor = size.multiplier * shape.factor;
    return List.unmodifiable([
      for (final b in r.bands) bandForMinutes(_baseMinutes(r, b, method) * factor),
    ]);
  }

  /// The minute figure scaling starts from: the row's own figure for [method]
  /// when there is one, otherwise the band's representative figure. Advisory
  /// minutes are deliberately still used here — scaling a packet time is
  /// better than scaling nothing, and the result is only ever read as a band.
  static int _baseMinutes(CookingTimeRow r, CookBand band, String? method) {
    final byMethod = method == null ? null : r.minutes[method];
    if (byMethod != null) return byMethod;
    if (r.minutes.length == 1 && r.bands.length == 1) return r.minutes.values.first;
    // Dual-band rows have several method figures that disagree by design
    // (lamb: 8 min pan vs 90 min simmer); pick by band rather than by order.
    for (final m in r.minutes.values) {
      if (bandForMinutes(m) == band) return m;
    }
    return band.representativeMinutes;
  }

  /// The compact block injected into the recipe prompts. Keys only, comma
  /// separated, no descriptions — the model does not need to know what a row
  /// means to name it, and every character here sits in the cached prefix of
  /// every recipe call. Sorted for stability: this string must not change
  /// shape between builds or it invalidates the prefix cache for everyone.
  static final String promptKeyList = (allKeys.toList()..sort()).join(', ');
}
