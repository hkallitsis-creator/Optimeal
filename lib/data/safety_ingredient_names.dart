/// Closed ingredient-name vocabulary for the safety validator's deterministic
/// layer (roadmap item 1, `docs/safety_hazard_registry.md`).
///
/// # STATUS: DRAFT — NOT SIGNED
///
/// H1's detection line on the signed registry reads *"Identification via a
/// closed poultry/pork name list (drafted separately for review)"*. That list
/// was never in the repo — the 2026-08-22 transcription recorded its absence
/// as open item 6. **This file is that draft, written by Claude, and it is not
/// signed content.** Every list below is Harris's to strike, extend or reword;
/// the full text goes in the session report for exactly that purpose.
///
/// What this file must never contain is a **threshold**. The four temperatures
/// in [ProteinClass] are transcribed from the signed H3 table and nothing else
/// numeric lives here.
///
/// ## Matching contract
///
/// Terms are matched **whole-word, case-insensitively**, with an optional
/// trailing `s`/`es`. Whole-word matching is not decoration: `cod` inside
/// `cooked` and `ham` inside `hamburger` are both real collisions this
/// vocabulary would otherwise produce on every recipe.
///
/// ## The cured ready-to-eat exclusion — the biggest judgement here
///
/// [SafetyIngredientName.curedReadyToEat] marks pork products that are cured,
/// ready to eat, and never cooked to a verified core temperature: prosciutto,
/// bacon, pancetta, chorizo, a Swiss cervelat. They are pork by any ordinary
/// reading, so a literal H1 would demand a `juices_run_clear` cue on every
/// carbonara step that adds pancetta — a cue whose signed text ("cut into the
/// thickest part … no pink flesh") is meaningless for a lardon and would read
/// as nonsense to the user.
///
/// So they are **excluded from H1 qualification** and reported separately.
/// This is a scope decision, not a safety threshold, and it is DRAFT like
/// everything else here. It is called out first in the session report because
/// it is the one exclusion that silences a rule rather than narrowing it.
library;

import 'package:flutter/foundation.dart';

/// The four protein classes of the signed H3 table, and only those.
///
/// Temperatures are transcribed from `docs/safety_hazard_registry.md` H3,
/// confirmed by Harris on 2026-08-22 ("all 4 stand"). Do not add a class with
/// a temperature that is not on that table.
enum ProteinClass {
  /// Signed minimum 74 °C.
  poultry,

  /// Signed minimum 71 °C. Covers minced meat of any species and sausage.
  mincedOrSausage,

  /// Signed minimum 63 °C **plus a stated 3-minute rest**. The registry is
  /// explicit that 63 °C without the rest is not the signed condition.
  porkWholeMuscle,

  /// Signed minimum 63 °C.
  fish,
}

extension ProteinClassRule on ProteinClass {
  /// The signed instantaneous minimum in °C.
  int get minimumCelsius => switch (this) {
        ProteinClass.poultry => 74,
        ProteinClass.mincedOrSausage => 71,
        ProteinClass.porkWholeMuscle => 63,
        ProteinClass.fish => 63,
      };

  /// True only for pork whole-muscle, the one two-part entry on the table.
  bool get requiresStatedRest => this == ProteinClass.porkWholeMuscle;

  /// Minutes of rest the signed entry requires, or null where none is signed.
  int? get restMinutes => this == ProteinClass.porkWholeMuscle ? 3 : null;

  /// Used in model-facing correction directives, so it names the class the
  /// way the registry does.
  String get label => switch (this) {
        ProteinClass.poultry => 'poultry',
        ProteinClass.mincedOrSausage => 'minced meat or sausage',
        ProteinClass.porkWholeMuscle => 'whole-muscle pork',
        ProteinClass.fish => 'fish',
      };
}

/// One declarable name in the closed vocabulary.
@immutable
class SafetyIngredientName {
  const SafetyIngredientName(
    this.term, {
    this.poultry = false,
    this.pork = false,
    this.comminuted = false,
    this.fish = false,
    this.curedReadyToEat = false,
    this.notFollowedBy = const [],
  });

  /// Lowercase match term. Matched whole-word with an optional trailing s/es.
  final String term;

  final bool poultry;
  final bool pork;

  /// Minced, ground, or otherwise comminuted — H2's trigger, and the reason a
  /// name can be poultry *and* comminuted at once (chicken mince).
  final bool comminuted;

  final bool fish;

  /// Cured and ready to eat — excluded from H1. See the library doc.
  final bool curedReadyToEat;

  /// Words that, immediately after [term], mean this is not the ingredient.
  ///
  /// Exists for exactly one entry: **`mince`**, which in a recipe is as often
  /// the imperative verb as the noun. Found on real dev output — "Mince the
  /// garlic" in a cabbage recipe matched the comminuted-meat vocabulary and
  /// burned both H2 correction retries on a dish containing no meat at all.
  /// A negative lookahead on the verb's usual objects separates the two
  /// readings deterministically, and leaves "500 g mince" matching.
  final List<String> notFollowedBy;

  /// Which signed H3 classes this name falls under. A name can carry two:
  /// chicken mince is poultry (74 °C) and comminuted (71 °C) at the same time.
  Set<ProteinClass> get proteinClasses => {
        if (poultry) ProteinClass.poultry,
        if (comminuted) ProteinClass.mincedOrSausage,
        if (pork && !comminuted) ProteinClass.porkWholeMuscle,
        if (fish) ProteinClass.fish,
      };

  /// True when H1's doneness rule applies to this name.
  bool get qualifiesForDonenessRule =>
      (poultry || pork) && !curedReadyToEat;

  @override
  String toString() => term;
}

// ─────────────────────────────────────────────────────────────────────────────
// THE DRAFT LISTS
//
// Grouped so each group can be struck or kept on its own. Generous with
// synonyms, cuts and dish names on purpose: a missed name is a missed safety
// check, whereas a spurious name costs at most one unnecessary cue.
// ─────────────────────────────────────────────────────────────────────────────

/// Poultry, whole muscle. H1 applies; H3 class = poultry (74 °C).
const List<SafetyIngredientName> kPoultryWholeMuscleDraft = [
  SafetyIngredientName('chicken', poultry: true),
  SafetyIngredientName('chicken breast', poultry: true),
  SafetyIngredientName('chicken thigh', poultry: true),
  SafetyIngredientName('chicken drumstick', poultry: true),
  SafetyIngredientName('drumstick', poultry: true),
  SafetyIngredientName('chicken wing', poultry: true),
  SafetyIngredientName('chicken leg', poultry: true),
  SafetyIngredientName('chicken quarter', poultry: true),
  SafetyIngredientName('chicken fillet', poultry: true),
  SafetyIngredientName('chicken supreme', poultry: true),
  SafetyIngredientName('chicken tender', poultry: true),
  SafetyIngredientName('chicken tenderloin', poultry: true),
  SafetyIngredientName('chicken escalope', poultry: true),
  SafetyIngredientName('chicken schnitzel', poultry: true),
  SafetyIngredientName('chicken cutlet', poultry: true),
  SafetyIngredientName('whole chicken', poultry: true),
  SafetyIngredientName('poussin', poultry: true),
  SafetyIngredientName('capon', poultry: true),
  SafetyIngredientName('turkey', poultry: true),
  SafetyIngredientName('turkey breast', poultry: true),
  SafetyIngredientName('turkey steak', poultry: true),
  SafetyIngredientName('turkey escalope', poultry: true),
  SafetyIngredientName('turkey crown', poultry: true),
  SafetyIngredientName('turkey thigh', poultry: true),
  SafetyIngredientName('turkey leg', poultry: true),
  SafetyIngredientName('duck', poultry: true),
  SafetyIngredientName('duck breast', poultry: true),
  SafetyIngredientName('magret', poultry: true),
  SafetyIngredientName('duck leg', poultry: true),
  SafetyIngredientName('duck thigh', poultry: true),
  SafetyIngredientName('goose', poultry: true),
  SafetyIngredientName('goose breast', poultry: true),
  SafetyIngredientName('guinea fowl', poultry: true),
  SafetyIngredientName('quail', poultry: true),
  SafetyIngredientName('pheasant', poultry: true),
  SafetyIngredientName('partridge', poultry: true),
  SafetyIngredientName('pigeon', poultry: true),
  SafetyIngredientName('squab', poultry: true),
];

/// Poultry, comminuted. H1 and H2 both apply; H3 classes = poultry (74 °C)
/// AND minced (71 °C), and the validator takes the higher of the two.
const List<SafetyIngredientName> kPoultryMincedDraft = [
  SafetyIngredientName('chicken mince', poultry: true, comminuted: true),
  SafetyIngredientName('minced chicken', poultry: true, comminuted: true),
  SafetyIngredientName('ground chicken', poultry: true, comminuted: true),
  SafetyIngredientName('chicken burger', poultry: true, comminuted: true),
  SafetyIngredientName('chicken patty', poultry: true, comminuted: true),
  SafetyIngredientName('chicken meatball', poultry: true, comminuted: true),
  SafetyIngredientName('chicken sausage', poultry: true, comminuted: true),
  SafetyIngredientName('turkey mince', poultry: true, comminuted: true),
  SafetyIngredientName('minced turkey', poultry: true, comminuted: true),
  SafetyIngredientName('ground turkey', poultry: true, comminuted: true),
  SafetyIngredientName('turkey burger', poultry: true, comminuted: true),
  SafetyIngredientName('turkey patty', poultry: true, comminuted: true),
  SafetyIngredientName('turkey meatball', poultry: true, comminuted: true),
  SafetyIngredientName('duck mince', poultry: true, comminuted: true),
  SafetyIngredientName('minced duck', poultry: true, comminuted: true),
];

/// Pork, whole muscle. H1 applies; H3 class = pork whole-muscle
/// (63 °C **plus a stated 3-minute rest**).
const List<SafetyIngredientName> kPorkWholeMuscleDraft = [
  SafetyIngredientName('pork', pork: true),
  SafetyIngredientName('pork loin', pork: true),
  SafetyIngredientName('pork chop', pork: true),
  SafetyIngredientName('pork tenderloin', pork: true),
  SafetyIngredientName('pork fillet', pork: true),
  SafetyIngredientName('pork belly', pork: true),
  SafetyIngredientName('pork shoulder', pork: true),
  SafetyIngredientName('pork butt', pork: true),
  SafetyIngredientName('boston butt', pork: true),
  SafetyIngredientName('pork steak', pork: true),
  SafetyIngredientName('pork medallion', pork: true),
  SafetyIngredientName('pork escalope', pork: true),
  SafetyIngredientName('pork schnitzel', pork: true),
  SafetyIngredientName('pork cutlet', pork: true),
  SafetyIngredientName('pork collar', pork: true),
  SafetyIngredientName('pork neck', pork: true),
  SafetyIngredientName('pork shank', pork: true),
  SafetyIngredientName('pork joint', pork: true),
  SafetyIngredientName('pork roast', pork: true),
  SafetyIngredientName('pulled pork', pork: true),
  SafetyIngredientName('pork rib', pork: true),
  SafetyIngredientName('spare rib', pork: true),
  SafetyIngredientName('baby back rib', pork: true),
  SafetyIngredientName('pork knuckle', pork: true),
  SafetyIngredientName('ham hock', pork: true),
  SafetyIngredientName('gammon', pork: true),
  SafetyIngredientName('suckling pig', pork: true),
  SafetyIngredientName('schweinsbraten', pork: true),
];

/// Pork and mixed-species comminuted, plus sausage.
/// H2 applies; H3 class = minced/sausage (71 °C).
const List<SafetyIngredientName> kMincedAndSausageDraft = [
  SafetyIngredientName('pork mince', pork: true, comminuted: true),
  SafetyIngredientName('minced pork', pork: true, comminuted: true),
  SafetyIngredientName('ground pork', pork: true, comminuted: true),
  SafetyIngredientName('pork patty', pork: true, comminuted: true),
  SafetyIngredientName('pork burger', pork: true, comminuted: true),
  SafetyIngredientName('pork meatball', pork: true, comminuted: true),
  SafetyIngredientName('sausage meat', pork: true, comminuted: true),
  SafetyIngredientName('sausage', pork: true, comminuted: true),
  SafetyIngredientName('bratwurst', pork: true, comminuted: true),
  SafetyIngredientName('chipolata', pork: true, comminuted: true),
  SafetyIngredientName('banger', pork: true, comminuted: true),
  SafetyIngredientName('italian sausage', pork: true, comminuted: true),
  SafetyIngredientName('salsiccia', pork: true, comminuted: true),
  SafetyIngredientName('luganighe', pork: true, comminuted: true),
  SafetyIngredientName('toulouse sausage', pork: true, comminuted: true),
  SafetyIngredientName('breakfast sausage', pork: true, comminuted: true),
  SafetyIngredientName('boerewors', pork: true, comminuted: true),
  SafetyIngredientName('merguez', comminuted: true),
  SafetyIngredientName('beef mince', comminuted: true),
  SafetyIngredientName('minced beef', comminuted: true),
  SafetyIngredientName('ground beef', comminuted: true),
  SafetyIngredientName('lamb mince', comminuted: true),
  SafetyIngredientName('minced lamb', comminuted: true),
  SafetyIngredientName('ground lamb', comminuted: true),
  SafetyIngredientName('veal mince', comminuted: true),
  SafetyIngredientName('minced veal', comminuted: true),
  // Also the imperative verb — see [SafetyIngredientName.notFollowedBy].
  SafetyIngredientName('mince', comminuted: true, notFollowedBy: [
    'the', 'a', 'an', 'your', 'it', 'them', 'together',
    'finely', 'roughly', 'coarsely',
    'garlic', 'onion', 'shallot', 'herbs', 'parsley', 'coriander',
    'ginger', 'chilli', 'chili', 'celery', 'carrot',
  ]),
  SafetyIngredientName('ground meat', comminuted: true),
  SafetyIngredientName('minced meat', comminuted: true),
  SafetyIngredientName('hackfleisch', comminuted: true),
  SafetyIngredientName('burger', comminuted: true),
  SafetyIngredientName('burger patty', comminuted: true),
  SafetyIngredientName('beef burger', comminuted: true),
  SafetyIngredientName('hamburger', comminuted: true),
  SafetyIngredientName('meatball', comminuted: true),
  SafetyIngredientName('meatloaf', comminuted: true),
  SafetyIngredientName('kofta', comminuted: true),
  SafetyIngredientName('keema', comminuted: true),
  SafetyIngredientName('larb', comminuted: true),
  SafetyIngredientName('picadillo', comminuted: true),
  SafetyIngredientName('bolognese', comminuted: true),
  SafetyIngredientName('ragu', comminuted: true),
  SafetyIngredientName('chili con carne', comminuted: true),
];

/// Cured, ready to eat, **excluded from H1**. Present in the vocabulary so
/// the exclusion is explicit and auditable rather than an accidental gap.
const List<SafetyIngredientName> kCuredReadyToEatDraft = [
  SafetyIngredientName('bacon', pork: true, curedReadyToEat: true),
  SafetyIngredientName('lardon', pork: true, curedReadyToEat: true),
  SafetyIngredientName('pancetta', pork: true, curedReadyToEat: true),
  SafetyIngredientName('guanciale', pork: true, curedReadyToEat: true),
  SafetyIngredientName('prosciutto', pork: true, curedReadyToEat: true),
  SafetyIngredientName('parma ham', pork: true, curedReadyToEat: true),
  SafetyIngredientName('serrano ham', pork: true, curedReadyToEat: true),
  SafetyIngredientName('speck', pork: true, curedReadyToEat: true),
  SafetyIngredientName('coppa', pork: true, curedReadyToEat: true),
  SafetyIngredientName('salami', pork: true, curedReadyToEat: true),
  SafetyIngredientName('chorizo', pork: true, curedReadyToEat: true),
  SafetyIngredientName('nduja', pork: true, curedReadyToEat: true),
  SafetyIngredientName('cervelat', pork: true, curedReadyToEat: true),
  SafetyIngredientName('frankfurter', pork: true, curedReadyToEat: true),
  SafetyIngredientName('wiener', pork: true, curedReadyToEat: true),
  SafetyIngredientName('hot dog', pork: true, curedReadyToEat: true),
  SafetyIngredientName('kielbasa', pork: true, curedReadyToEat: true),
  SafetyIngredientName('landjaeger', pork: true, curedReadyToEat: true),
  SafetyIngredientName('cooked ham', pork: true, curedReadyToEat: true),
];

/// Fish. Needed by H3 (63 °C), H4 and H9. Not poultry or pork, so H1 never
/// applies to these.
const List<SafetyIngredientName> kFishDraft = [
  SafetyIngredientName('fish', fish: true),
  SafetyIngredientName('salmon', fish: true),
  SafetyIngredientName('cod', fish: true),
  SafetyIngredientName('haddock', fish: true),
  SafetyIngredientName('pollock', fish: true),
  SafetyIngredientName('hake', fish: true),
  SafetyIngredientName('halibut', fish: true),
  SafetyIngredientName('sea bass', fish: true),
  SafetyIngredientName('seabass', fish: true),
  SafetyIngredientName('sea bream', fish: true),
  SafetyIngredientName('bream', fish: true),
  SafetyIngredientName('trout', fish: true),
  SafetyIngredientName('tuna', fish: true),
  SafetyIngredientName('swordfish', fish: true),
  SafetyIngredientName('mackerel', fish: true),
  SafetyIngredientName('sardine', fish: true),
  SafetyIngredientName('anchovy', fish: true),
  SafetyIngredientName('plaice', fish: true),
  SafetyIngredientName('sole', fish: true),
  SafetyIngredientName('monkfish', fish: true),
  SafetyIngredientName('snapper', fish: true),
  SafetyIngredientName('perch', fish: true),
  SafetyIngredientName('pike', fish: true),
  SafetyIngredientName('zander', fish: true),
  SafetyIngredientName('arctic char', fish: true),
  SafetyIngredientName('char', fish: true),
  SafetyIngredientName('tilapia', fish: true),
  SafetyIngredientName('catfish', fish: true),
  SafetyIngredientName('herring', fish: true),
  SafetyIngredientName('felchen', fish: true),
  SafetyIngredientName('egli', fish: true),
];

/// The whole closed vocabulary, in one list.
final List<SafetyIngredientName> kSafetyIngredientNamesDraft =
    List.unmodifiable([
  ...kPoultryWholeMuscleDraft,
  ...kPoultryMincedDraft,
  ...kPorkWholeMuscleDraft,
  ...kMincedAndSausageDraft,
  ...kCuredReadyToEatDraft,
  ...kFishDraft,
]);

// ─────────────────────────────────────────────────────────────────────────────
// MATCHING
// ─────────────────────────────────────────────────────────────────────────────

final Map<String, RegExp> _patternCache = {};

RegExp _patternFor(SafetyIngredientName entry) =>
    _patternCache.putIfAbsent(entry.term, () {
      final escaped = RegExp.escape(entry.term);
      // Optional trailing s/es so "chicken thighs" matches "chicken thigh".
      // Whole-word on both ends: this is what keeps "cod" out of "cooked".
      final buffer = StringBuffer('\\b$escaped(?:es|s)?\\b');
      if (entry.notFollowedBy.isNotEmpty) {
        final alts = entry.notFollowedBy.map(RegExp.escape).join('|');
        buffer.write('(?!\\s+(?:$alts)\\b)');
      }
      return RegExp(buffer.toString(), caseSensitive: false);
    });

/// Every vocabulary entry mentioned in [text], longest term first.
///
/// Longest-first matters: "chicken mince" and "chicken" both match the same
/// phrase, and callers that want the most specific reading take the first hit.
List<SafetyIngredientName> matchSafetyNames(String text) {
  if (text.trim().isEmpty) return const [];
  final hits = <SafetyIngredientName>[];
  for (final entry in kSafetyIngredientNamesDraft) {
    if (_patternFor(entry).hasMatch(text)) hits.add(entry);
  }
  hits.sort((a, b) => b.term.length.compareTo(a.term.length));
  return hits;
}

/// True when [text] mentions poultry or pork that H1's doneness rule covers.
/// Cured ready-to-eat pork does not qualify — see the library doc.
bool mentionsPoultryOrPork(String text) =>
    matchSafetyNames(text).any((n) => n.qualifiesForDonenessRule);

/// Root terms that group several vocabulary entries into one animal.
///
/// Order matters: the first root contained in a term wins, so `pulled pork`
/// and `pork loin` both resolve to `pork`.
const List<String> _donenessFamilyRoots = [
  'chicken',
  'turkey',
  'duck',
  'goose',
  'guinea fowl',
  'poussin',
  'capon',
  'quail',
  'pheasant',
  'partridge',
  'pigeon',
  'squab',
  'pork',
  'gammon',
  'sausage',
  'bratwurst',
  'chipolata',
  'banger',
  'salsiccia',
  'luganighe',
  'boerewors',
  'merguez',
];

/// Which animal a vocabulary entry belongs to, for H1's grouping.
///
/// Without this, `chicken` and `chicken thigh` are two different proteins and
/// a recipe that says "chicken thighs" in one step and "the chicken" in the
/// next gets two doneness cues — one of them on whatever else that second step
/// happened to be doing. Observed on real dev output: a cue landed on a step
/// titled "Add potatoes". Grouping by animal is what the rule actually means.
String donenessFamilyOf(SafetyIngredientName name) {
  for (final root in _donenessFamilyRoots) {
    if (name.term.contains(root)) return root;
  }
  return name.term;
}

/// True when [text] mentions comminuted meat of any species (H2, H3).
bool mentionsComminutedMeat(String text) =>
    matchSafetyNames(text).any((n) => n.comminuted);

/// The signed H3 classes present in [text].
Set<ProteinClass> proteinClassesIn(String text) {
  final out = <ProteinClass>{};
  for (final n in matchSafetyNames(text)) {
    out.addAll(n.proteinClasses);
  }
  return out;
}

/// The governing signed minimum when more than one class is present.
///
/// **This introduces no new number.** Chicken mince is poultry (74 °C) and
/// minced (71 °C) at once, and the registry signs both; a temperature that
/// satisfies the higher satisfies the lower, so the higher governs. Taking
/// the lower would mean a signed minimum was knowingly not applied.
ProteinClass? governingProteinClass(Set<ProteinClass> classes) {
  if (classes.isEmpty) return null;
  return classes.reduce(
    (a, b) => b.minimumCelsius > a.minimumCelsius ? b : a,
  );
}
