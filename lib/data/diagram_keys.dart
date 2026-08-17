/// Closed key lists for the drawn SVG diagram system — deterministic
/// diagrams, not AI-generated images, not photos. See
/// docs/decisions_2026-08-17.md item 4 and docs/DECISIONS.md "Visual
/// assets — drawn diagrams, not photographs".
///
/// Two independent diagram families, looked up differently:
/// - Cut diagrams: keyed by an ingredient's EXISTING declared "cut" value
///   (lib/models/recipe_model.dart's `ingredientCutVocabulary`) — no new
///   prompt field, no new model field, just a lookup.
/// - Technique diagrams: a NEW per-step declared "technique_diagram_id"
///   field, the fourth instance of the closed-vocabulary pattern (after
///   cut vocabulary, curriculum_lesson_id, and sensory_cue).
library;

/// Mirrors `ingredientCutVocabulary` (lib/models/recipe_model.dart) 1:1,
/// including 'none'. Deliberately duplicated as its own list rather than a
/// re-export — this list's job is "which cuts a diagram COULD exist for,"
/// not "what a valid cut value is" (that's still `ingredientCutVocabulary`'s
/// job); keeping them textually separate means the diagram system can't
/// accidentally start being read as the source of truth for cut validation.
/// Only 1 of these 16 has a real built asset today (julienne) — see
/// lib/widgets/diagram_sheet.dart's asset map. The other 15 keys exist so
/// the lookup and closed-set shape are already correct as more diagrams are
/// added later, one at a time — an unbuilt key simply has no asset and
/// renders nothing (see lib/widgets/diagram_sheet.dart).
const List<String> cutDiagramKeys = [
  'whole',
  'halved',
  'quartered',
  'wedges',
  'rough_chop',
  'small_dice',
  'medium_dice',
  'large_dice',
  'thin_slice',
  'thick_slice',
  'julienne',
  'grated',
  'minced',
  'crushed',
  'torn',
  'none',
];

/// Escape value for `technique_diagram_id` — exactly like
/// [SensoryCueVocabulary.noCueKey] (lib/data/sensory_cue_vocabulary.dart)
/// and cut vocabulary's own explicit 'none'. A wrong diagram is worse than
/// no diagram. Unlike sensory_cue, this field is OPTIONAL on the model's
/// side — omitting it entirely is just as valid as declaring this value.
const String noTechniqueDiagramKey = 'none';

/// The closed set of real technique diagram keys, per
/// docs/decisions_2026-08-17.md item 4 — exactly these five. Does NOT
/// include [noTechniqueDiagramKey]; see [allTechniqueDiagramKeys] for the
/// full declarable set including the escape value.
const List<String> techniqueDiagramKeys = [
  'pan_crowding',
  'cold_vs_hot_pan',
  'oil_depth',
  'tray_spacing',
  'staggered_adds',
];

/// Every value the model may declare for "technique_diagram_id", including
/// the escape value. Validate model declarations against this list.
const List<String> allTechniqueDiagramKeys = [
  ...techniqueDiagramKeys,
  noTechniqueDiagramKey,
];

/// Only 2 of the 5 technique diagram keys have a real built asset today
/// (pan_crowding, cold_vs_hot_pan) — see lib/widgets/diagram_sheet.dart's
/// asset map. oil_depth, tray_spacing, and staggered_adds are valid,
/// declarable, parsed keys with no asset yet; they render nothing (no
/// placeholder, no broken state) until a real SVG is added for each.
