/// The deterministic half of allergen enforcement.
///
/// # Why a prompt instruction is not enough
///
/// The prompt already carries an allergen block, and on real dev output it
/// works: a profile avoiding egg, dairy and tree nuts, deliberately handed
/// "eggs, cheese, walnuts" as available ingredients, still produced a recipe
/// using none of them. **That is the model complying, which is not the same
/// thing as a guarantee**, and the difference matters more here than anywhere
/// else in the app because the failure mode is an allergic reaction.
///
/// This check is what does not depend on the model having a good day.
///
/// # What it inspects
///
/// The generated ingredient **names** — the list the user shops from and cooks
/// from. Step prose is deliberately NOT scanned: a step saying "unlike a
/// classic carbonara, there is no egg here" is correct and would be flagged by
/// a prose scan, and a rule that fires on recipes doing the right thing is a
/// rule people learn to ignore.
library;

import 'package:flutter/foundation.dart';
import 'package:optimeal/data/allergen_synonyms.dart';
import 'package:optimeal/screens/one_pan_cooking_roadmap_screen.dart';

/// One ingredient that trips an allergen the user asked to avoid.
@immutable
class AllergenViolation {
  const AllergenViolation({
    required this.allergenLabel,
    required this.ingredientName,
    required this.matchedWord,
  });

  /// The Profile chip the user selected, e.g. "Tree Nuts".
  final String allergenLabel;

  /// The generated ingredient's name, verbatim.
  final String ingredientName;

  /// The synonym that matched, for the log and the correction sentence.
  final String matchedWord;

  Map<String, dynamic> toJson() => {
        'allergen': allergenLabel,
        'ingredient': ingredientName,
        'matched': matchedWord,
      };

  String get correctionSentence =>
      'The ingredient "$ingredientName" contains $allergenLabel '
      '(matched on "$matchedWord"), which this user has told us to avoid. '
      'Remove it entirely and rebuild the recipe around a substitute — do not '
      'simply rename it or mark it optional.';

  @override
  String toString() => correctionSentence;
}

/// Every avoided allergen present in [recipe]'s ingredient list.
///
/// [avoided] is `UserProfile.allergies`; an empty list means there is nothing
/// to check and this returns empty without doing any work.
List<AllergenViolation> findAllergenViolations({
  required CookModeRecipePayload recipe,
  required List<String> avoided,
}) {
  if (avoided.isEmpty) return const [];

  final structured = recipe.structuredIngredients;
  final names = structured != null && structured.isNotEmpty
      ? structured.map((i) => i.name).toList(growable: false)
      : recipe.ingredients;

  final out = <AllergenViolation>[];
  for (final name in names) {
    for (final label in allergensIn(name, avoided)) {
      out.add(AllergenViolation(
        allergenLabel: label,
        ingredientName: name,
        matchedWord: matchedSynonym(name, label) ?? label,
      ));
    }
  }
  return out;
}

/// The correction note appended to a retry prompt, on the **variable** half so
/// the cached static prefix is untouched.
String buildAllergenCorrectionNote(List<AllergenViolation> violations) {
  if (violations.isEmpty) return '';
  final buffer = StringBuffer(
    'ALLERGEN CORRECTION REQUIRED. This user cannot eat the following, and '
    'your previous version included it anyway. This is not a preference. '
    'Fix every point and return the whole recipe again in the same JSON '
    'shape:\n',
  );
  for (final v in violations) {
    buffer.writeln('- ${v.correctionSentence}');
  }
  return buffer.toString().trimRight();
}

/// Allergen labels tripped by a stage-1 idea (title plus its ingredient
/// lists), used to detect the leak described in the session record.
///
/// Stage 1 is **detection only** today — see the decision record. It offered
/// "Cheesy Potato Skillet" and "Spinach Walnut Salad" to a profile avoiding
/// dairy and tree nuts on real dev output, so the leak is real; what to do
/// about it (filter, regenerate, or annotate) is Harris's ruling.
Set<String> allergensInIdeaText(String text, List<String> avoided) =>
    allergensIn(text, avoided);
