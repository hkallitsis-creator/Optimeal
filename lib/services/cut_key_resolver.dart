
/// Works out which **cut** diagram, if any, belongs on an ingredient row.
///
/// # A correction to this build's brief, recorded rather than assumed
///
/// The brief stated that `RecipeIngredient` is name/amount/unit only and that
/// there is no per-ingredient cut key. **That is not the case**:
/// `RecipeIngredient.cut` exists, is parsed from the model's declared `cut`
/// field, and is already validated against the closed
/// [ingredientCutVocabulary] on the way in (`chef_recipe_parser.dart`), with
/// anything outside the list dropped to null. Cook Mode already resolves step
/// diagrams from it.
///
/// So the declared value is used **first**, and the text-matching fallback in
/// this file only runs when the model declared nothing. That is strictly
/// better than resolving from prose in every case: a declared key is the
/// model's own statement about the ingredient, whereas a text match is an
/// inference from a sentence that may be describing something else in the
/// same step. No prompt was changed either way, so the zero-token-cost
/// constraint holds.
///
/// # What this never does
///
/// * It never invents a key. Matching is against [ingredientCutVocabulary]
///   exactly, whole-word.
/// * It never attaches a **technique** diagram to an ingredient row.
///   `pan_crowding` and `cold_vs_hot_pan` are facts about a pan, not about a
///   carrot, and this file cannot return them — it only ever considers cut
///   keys, which is enforced by a test as well as by construction.
/// * It never returns a key with no built diagram. Callers render a pill only
///   when this returns non-null, so an unbuilt-but-valid key (15 of the 16)
///   produces no pill rather than a broken one.
library;

import 'package:optimeal/models/recipe_model.dart';
import 'package:optimeal/screens/one_pan_cooking_roadmap_screen.dart';
import 'package:optimeal/widgets/diagram_sheet.dart';

/// Cut keys that are worth matching from prose, and the words that mean them.
///
/// `whole` and `none` are deliberately absent: "whole" appears in recipe text
/// constantly ("cook whole", "the whole time") and means nothing about knife
/// work, and `none` is the vocabulary's explicit absence value.
const Map<String, List<String>> kCutSynonyms = {
  'julienne': ['julienne', 'julienned', 'matchstick', 'matchsticks'],
  'small_dice': ['small dice', 'finely diced', 'finely dice', 'fine dice'],
  'medium_dice': ['medium dice', 'diced', 'dice', 'cubed', 'cube'],
  'large_dice': ['large dice', 'roughly diced', 'chunks', 'chunky'],
  'thin_slice': ['thinly sliced', 'thinly slice', 'thin slice', 'thin slices'],
  'thick_slice': ['thickly sliced', 'thick slice', 'thick slices'],
  'rough_chop': ['roughly chopped', 'rough chop', 'roughly chop', 'chopped', 'chop'],
  'minced': ['minced', 'mince'],
  'grated': ['grated', 'grate', 'shredded'],
  'crushed': ['crushed', 'crush'],
  'torn': ['torn', 'tear'],
  'halved': ['halved', 'halve'],
  'quartered': ['quartered', 'quarter'],
  'wedges': ['wedges', 'wedge'],
};

final Map<String, RegExp> _synonymCache = {};

RegExp _wordPattern(String phrase) => _synonymCache.putIfAbsent(
      phrase,
      () => RegExp('\\b${RegExp.escape(phrase)}\\b', caseSensitive: false),
    );

/// The cut key for [ingredient], or null.
///
/// [steps] supplies the recipe's own prose as a fallback source; only steps
/// that actually mention this ingredient are read, so a step dicing an onion
/// cannot put a dice pill on the parsley.
///
/// Returns a key **only when a diagram exists for it** — see the library doc.
String? resolveCutDiagramKey({
  required RecipeIngredient ingredient,
  List<CookModeStepPayload> steps = const [],
}) {
  final key = resolveCutKey(ingredient: ingredient, steps: steps);
  if (key == null) return null;
  return diagramFor(key) == null ? null : key;
}

/// The cut key for [ingredient] regardless of whether a diagram is built.
///
/// Split from [resolveCutDiagramKey] so the resolver's real match rate can be
/// measured — "how often do we know the cut" and "how often can we draw it"
/// are different questions, and with 3 of 21 diagrams built they have very
/// different answers.
String? resolveCutKey({
  required RecipeIngredient ingredient,
  List<CookModeStepPayload> steps = const [],
}) {
  // 1. The model's own declared value, already validated against the closed
  //    vocabulary by the parser. Authoritative.
  final declared = ingredient.cut;
  if (declared != null && declared != 'none' && declared.isNotEmpty) {
    return declared;
  }

  // 2. The ingredient's own name/note — "carrots, julienned".
  final fromName = _matchIn(ingredient.name);
  if (fromName != null) return fromName;

  // 3. Step prose, but only from steps that mention this ingredient.
  final needle = _headNoun(ingredient.name);
  if (needle.isEmpty) return null;

  for (final step in steps) {
    // Sentence-scoped, not step-scoped. Found on real dev output: a step that
    // said "thinly slice the potatoes" and "season with salt" put a
    // `thin_slice` pill on the SALT, and a step mentioning both feta and
    // lemon wedges put `wedges` on the feta. Requiring the ingredient and the
    // cut phrase to share a sentence is what makes the match about this
    // ingredient rather than about the step.
    for (final sentence in _sentences('${step.title}. ${step.bullets.join('. ')}')) {
      if (!_ingredientPattern(needle).hasMatch(sentence)) continue;
      final match = _matchIn(sentence);
      if (match != null) return match;
    }
  }

  return null;
}

/// Splits on sentence and clause boundaries. Semicolons and dashes count:
/// "slice the potato; season the fish" is two instructions, not one.
final RegExp _sentenceBreak = RegExp(r'[.;!?\n]|\s+[—–-]\s+');

Iterable<String> _sentences(String text) => text
    .split(_sentenceBreak)
    .map((s) => s.trim())
    .where((s) => s.isNotEmpty);

/// Longest phrase wins, so "small dice" is not swallowed by "dice".
String? _matchIn(String text) {
  if (text.trim().isEmpty) return null;

  String? best;
  var bestLength = 0;
  kCutSynonyms.forEach((key, phrases) {
    for (final phrase in phrases) {
      if (phrase.length <= bestLength) continue;
      if (_wordPattern(phrase).hasMatch(text)) {
        best = key;
        bestLength = phrase.length;
      }
    }
  });
  return best;
}

/// The word most likely to be the ingredient itself — the last word of the
/// name, reduced to a singular stem. "Spring onions" → "onion".
///
/// Stripping "es" before "s" matters: a naive single-character strip turns
/// "potatoes" into "potatoe", which then matches nothing, and the prose
/// fallback silently stops working for exactly the ingredients recipes talk
/// about most.
String _headNoun(String name) {
  final cleaned = name
      .toLowerCase()
      .replaceAll(RegExp(r'[(),.]'), ' ')
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (cleaned.isEmpty) return '';

  var head = cleaned.last;
  if (head.length > 4 && head.endsWith('es')) {
    head = head.substring(0, head.length - 2);
  } else if (head.length > 3 && head.endsWith('s')) {
    head = head.substring(0, head.length - 1);
  }
  return head;
}

/// Matches an ingredient stem in prose, tolerating the plural the stem was
/// derived from. Separate from [_wordPattern], which matches exact cut
/// phrases and must NOT be loosened.
RegExp _ingredientPattern(String stem) => _synonymCache.putIfAbsent(
      'ingredient::$stem',
      () => RegExp(r'\b' '${RegExp.escape(stem)}' r'(?:e?s)?\b',
          caseSensitive: false),
    );
