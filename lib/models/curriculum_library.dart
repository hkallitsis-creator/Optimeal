import 'package:optimeal/models/technique_lesson.dart';

/// Shared, importable curriculum content source.
///
/// This is intentionally a single canonical list so curriculum lesson content
/// can be referenced from anywhere (Cook Mode, planning flows, media hub, etc.)
/// without duplicating the lesson definitions.
class CurriculumLibrary {
  static const List<TechniqueLesson> lessons = [
    TechniqueLesson(
      id: 'pan-sauce-123',
      title: 'Pan Sauce Ratio: The 1–2–3 Instinct',
      category: TechniqueCategory.matrixesRatios,
      durationSeconds: 134,
      shortDescription:
          'Build pan sauces by instinct: deglaze, enrich, balance — the ratio stays consistent across proteins.',
      breakdownSteps: [
        TechniqueBreakdownStep(label: 'Deglaze', detail: 'Add wine/stock to lift fond; reduce until syrupy.'),
        TechniqueBreakdownStep(label: 'Enrich', detail: 'Whisk in butter/cream off heat for gloss.'),
        TechniqueBreakdownStep(label: 'Balance', detail: 'Finish with acid + salt; taste for cling.'),
      ],
    ),
    TechniqueLesson(
      id: 'emulsions',
      title: 'Emulsions That Never Break (Vinaigrette → Aioli)',
      category: TechniqueCategory.matrixesRatios,
      durationSeconds: 242,
      shortDescription: 'Use temperature, droplet size, and patience so emulsions hold every time.',
      breakdownSteps: [
        TechniqueBreakdownStep(label: 'Anchor', detail: 'Start with a stable base (mustard/egg yolk).'),
        TechniqueBreakdownStep(label: 'Stream', detail: 'Add oil slowly at first; speed up after it tightens.'),
        TechniqueBreakdownStep(label: 'Rescue', detail: 'If it breaks, start fresh base and whisk the broken mix in.'),
      ],
    ),
    TechniqueLesson(
      id: 'knife-grip',
      title: 'Knife Grip, Speed, and Safer Rhythm',
      category: TechniqueCategory.knifeHeatManagement,
      durationSeconds: 198,
      shortDescription: 'Get faster by getting calmer: grip, guide hand, and cadence — not force.',
      breakdownSteps: [
        TechniqueBreakdownStep(label: 'Pinch grip', detail: 'Thumb + index pinch the blade; rest wraps handle.'),
        TechniqueBreakdownStep(label: 'Claw', detail: 'Knuckles guide the blade; fingertips tucked.'),
        TechniqueBreakdownStep(label: 'Rhythm', detail: 'Let the tip lead; move food with the guide hand.'),
      ],
    ),
    TechniqueLesson(
      id: 'heat-zones',
      title: 'Heat Zones: Sear, Sweat, Simmer (One Pan)',
      category: TechniqueCategory.knifeHeatManagement,
      durationSeconds: 311,
      shortDescription: 'Use one pan like three burners by shifting food + pan position.',
      breakdownSteps: [
        TechniqueBreakdownStep(label: 'Sear', detail: 'High heat, dry surface, don’t crowd.'),
        TechniqueBreakdownStep(label: 'Sweat', detail: 'Lower heat; cover to soften aromatics without color.'),
        TechniqueBreakdownStep(label: 'Simmer', detail: 'Gentle bubbles; adjust with liquid + lid.'),
      ],
    ),
    TechniqueLesson(
      id: 'creme-yogurt',
      title: 'Crème Fraîche ↔ Yogurt: When It Works',
      category: TechniqueCategory.europeanSubstitutes,
      durationSeconds: 167,
      shortDescription: 'Swap by fat % and acidity; learn when yogurt curdles and how to prevent it.',
      breakdownSteps: [
        TechniqueBreakdownStep(label: 'Off-heat finish', detail: 'Stir yogurt in after heat drops to avoid splitting.'),
        TechniqueBreakdownStep(label: 'Stabilize', detail: 'Add starch or tempered dairy for hot sauces.'),
      ],
    ),
    TechniqueLesson(
      id: 'gruyere-swaps',
      title: 'Gruyère Swaps by Melt + Salt Profile',
      category: TechniqueCategory.europeanSubstitutes,
      durationSeconds: 216,
      shortDescription: 'Match by melt behavior first, then salt — your gratins will always behave.',
      breakdownSteps: [
        TechniqueBreakdownStep(label: 'Melt test', detail: 'Low heat: does it weep oil or stretch?'),
        TechniqueBreakdownStep(label: 'Blend', detail: 'Mix one melter + one flavor cheese for balance.'),
      ],
    ),
    TechniqueLesson(
      id: 'revive-herbs',
      title: 'Revive Limp Herbs + Greens in 90 Seconds',
      category: TechniqueCategory.zeroWasteCrisperHacks,
      durationSeconds: 119,
      shortDescription: 'Ice bath + trim reset hydration; learn the cue for when to stop soaking.',
      breakdownSteps: [
        TechniqueBreakdownStep(label: 'Trim', detail: 'Cut stems cleanly to open channels.'),
        TechniqueBreakdownStep(label: 'Shock', detail: '30–60s in ice water; then spin dry.'),
      ],
    ),
    TechniqueLesson(
      id: 'peel-to-stock',
      title: 'Peel-to-Stock: Your New Free Flavor Base',
      category: TechniqueCategory.zeroWasteCrisperHacks,
      durationSeconds: 148,
      shortDescription: 'Keep a freezer bag of clean scraps; simmer into quick stock on demand.',
      breakdownSteps: [
        TechniqueBreakdownStep(label: 'Scrap rules', detail: 'Avoid bitter skins; keep it clean and dry.'),
        TechniqueBreakdownStep(label: 'Simmer', detail: 'Bare simmer 45–60 min; don’t boil hard.'),
      ],
    ),
  ];

  static TechniqueLesson? byId(String id) {
    final needle = id.trim();
    if (needle.isEmpty) return null;
    for (final lesson in lessons) {
      if (lesson.id == needle) return lesson;
    }
    return null;
  }

  static List<TechniqueLesson> resolveAll(Iterable<String> ids) {
    final out = <TechniqueLesson>[];
    for (final id in ids) {
      final lesson = byId(id);
      if (lesson != null) out.add(lesson);
    }
    return out;
  }
}
