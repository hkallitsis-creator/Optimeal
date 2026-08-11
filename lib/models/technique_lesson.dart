/// Data models for the Techniques & Media hub and Chef Assistant technique cards.
///
/// This file is intentionally model-definition only. It is designed to be
/// compatible with Supabase/Postgres JSON payloads (string keys, num casting,
/// nullable fields, etc.).

enum TechniqueCategory {
  matrixesRatios,
  knifeHeatManagement,
  europeanSubstitutes,
  zeroWasteCrisperHacks;

  /// Stable wire-format identifier (recommended for Supabase storage).
  String get wireValue => switch (this) {
        TechniqueCategory.matrixesRatios => 'matrixes_ratios',
        TechniqueCategory.knifeHeatManagement => 'knife_heat_management',
        TechniqueCategory.europeanSubstitutes => 'european_substitutes',
        TechniqueCategory.zeroWasteCrisperHacks => 'zero_waste_crisper_hacks',
      };

  static TechniqueCategory fromWireValue(String value) {
    final normalized = value.trim().toLowerCase();
    return switch (normalized) {
      'matrixes_ratios' || 'matrices_ratios' || 'matrixesratios' || 'matrixes-ratios' =>
        TechniqueCategory.matrixesRatios,
      'knife_heat_management' ||
      'knifeheatmanagement' ||
      'knife-heat-management' =>
        TechniqueCategory.knifeHeatManagement,
      'european_substitutes' ||
      'europeansubstitutes' ||
      'european-substitutes' ||
      'swiss_substitutes' ||
      'swisssubstitutes' ||
      'swiss-substitutes' =>
        TechniqueCategory.europeanSubstitutes,
      'zero_waste_crisper_hacks' ||
      'zerowastecrisperhacks' ||
      'zero-waste-crisper-hacks' =>
        TechniqueCategory.zeroWasteCrisperHacks,
      _ => throw FormatException('Unknown TechniqueCategory: $value'),
    };
  }
}

class TechniqueBreakdownStep {
  final String label;
  final String detail;

  const TechniqueBreakdownStep({required this.label, required this.detail});

  factory TechniqueBreakdownStep.fromJson(Map<String, dynamic> json) {
    return TechniqueBreakdownStep(
      label: _readString(json, const ['label']) ?? '',
      detail: _readString(json, const ['detail']) ?? '',
    );
  }

  Map<String, dynamic> toJson() => {'label': label, 'detail': detail};
}

/// Media Hub lesson content model.
///
/// Text + breakdown steps are the primary content — see CLAUDE.md
/// "Curriculum content strategy" for why this is deliberately not
/// video-first. [photoUrls] is the first-class visual field (a short
/// sequence of real still photos); [externalVideoUrl] is an optional,
/// separately-curated link to a creator's video, added manually later.
/// A lesson may have photos, a link, both, or neither — UI must fall back
/// to text-only rather than assuming either is present.
class TechniqueLesson {
  final String id;
  final String title;
  final TechniqueCategory category;
  final List<String> photoUrls;
  final String? externalVideoUrl;
  final int durationSeconds;
  final String shortDescription;
  final List<TechniqueBreakdownStep> breakdownSteps;

  const TechniqueLesson({
    required this.id,
    required this.title,
    required this.category,
    this.photoUrls = const <String>[],
    this.externalVideoUrl,
    required this.durationSeconds,
    required this.shortDescription,
    required this.breakdownSteps,
  });

  factory TechniqueLesson.fromJson(Map<String, dynamic> json) {
    final categoryRaw =
        _readString(json, const ['category', 'technique_category', 'techniqueCategory']);
    final stepsRaw = json['breakdown_steps'] ?? json['breakdownSteps'] ?? json['steps'];
    final photosRaw = json['photo_urls'] ?? json['photoUrls'];

    return TechniqueLesson(
      id: _readString(json, const ['id']) ?? '',
      title: _readString(json, const ['title']) ?? '',
      category: categoryRaw == null ? TechniqueCategory.matrixesRatios : TechniqueCategory.fromWireValue(categoryRaw),
      photoUrls: _readStringList(photosRaw),
      externalVideoUrl: _readString(json, const ['external_video_url', 'externalVideoUrl']),
      durationSeconds: _readInt(json, const ['duration_seconds', 'durationSeconds']) ?? 0,
      shortDescription: _readString(json, const ['short_description', 'shortDescription', 'description']) ?? '',
      breakdownSteps: _readStepsList(stepsRaw),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'category': category.wireValue,
        'photo_urls': photoUrls,
        'external_video_url': externalVideoUrl,
        'duration_seconds': durationSeconds,
        'short_description': shortDescription,
        'breakdown_steps': breakdownSteps.map((s) => s.toJson()).toList(growable: false),
      };
}

/// Structured technique-card model used in Chef Assistant / Cook Mode responses.
///
/// This is intentionally separate from [TechniqueLesson].
class CulinaryMatrixCard {
  final String id;
  final String title;
  final String heatCue;
  final String timingNote;
  final String? knifeCutSpec;
  final String whyThisWorks;
  final String? ratioSummary;

  const CulinaryMatrixCard({
    required this.id,
    required this.title,
    required this.heatCue,
    required this.timingNote,
    required this.knifeCutSpec,
    required this.whyThisWorks,
    required this.ratioSummary,
  });

  factory CulinaryMatrixCard.fromJson(Map<String, dynamic> json) {
    return CulinaryMatrixCard(
      id: _readString(json, const ['id']) ?? '',
      title: _readString(json, const ['title']) ?? '',
      heatCue: _readString(json, const ['heat_cue', 'heatCue']) ?? '',
      timingNote: _readString(json, const ['timing_note', 'timingNote']) ?? '',
      knifeCutSpec: _readString(json, const ['knife_cut_spec', 'knifeCutSpec']),
      whyThisWorks: _readString(json, const ['why_this_works', 'whyThisWorks']) ?? '',
      ratioSummary: _readString(json, const ['ratio_summary', 'ratioSummary']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'heat_cue': heatCue,
        'timing_note': timingNote,
        'knife_cut_spec': knifeCutSpec,
        'why_this_works': whyThisWorks,
        'ratio_summary': ratioSummary,
      };
}

String? _readString(Map<String, dynamic> json, List<String> keys) {
  for (final k in keys) {
    final v = json[k];
    if (v == null) continue;
    if (v is String) return v;
    return v.toString();
  }
  return null;
}

int? _readInt(Map<String, dynamic> json, List<String> keys) {
  for (final k in keys) {
    final v = json[k];
    if (v == null) continue;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) {
      final parsed = int.tryParse(v);
      if (parsed != null) return parsed;
      final parsedDouble = double.tryParse(v);
      if (parsedDouble != null) return parsedDouble.toInt();
    }
  }
  return null;
}

List<String> _readStringList(dynamic raw) {
  if (raw == null) return const [];
  if (raw is List) {
    return raw
        .where((e) => e != null)
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
  }
  return const [];
}

List<TechniqueBreakdownStep> _readStepsList(dynamic raw) {
  if (raw == null) return const [];
  if (raw is List) {
    return raw
        .where((e) => e != null)
        .map((e) {
          if (e is TechniqueBreakdownStep) return e;
          if (e is Map<String, dynamic>) return TechniqueBreakdownStep.fromJson(e);
          if (e is Map) return TechniqueBreakdownStep.fromJson(Map<String, dynamic>.from(e));
          return null;
        })
        .whereType<TechniqueBreakdownStep>()
        .toList(growable: false);
  }
  return const [];
}