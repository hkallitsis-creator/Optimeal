import 'dart:convert';

/// Local-only user profile for onboarding + AI personalization.
///
/// Stored in SharedPreferences as JSON.
class UserProfile {
  const UserProfile({
    required this.displayName,
    required this.language,
    required this.diet,
    required this.allergies,
    required this.kitchenConfidence,
    required this.householdServings,
    required this.createdAt,
    required this.updatedAt,
    required this.onboarded,
  });

  final String displayName;
  /// ISO-ish language code used for UI + AI personalization.
  /// Supported: en, de, fr, it.
  final String language;
  final UserDiet diet;
  final List<String> allergies;
  final KitchenConfidence kitchenConfidence;
  final int householdServings;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool onboarded;

  static UserProfile empty() => UserProfile(
    displayName: '',
    language: 'en',
    diet: UserDiet.omnivore,
    allergies: const [],
    kitchenConfidence: KitchenConfidence.beginner,
    householdServings: 1,
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
    onboarded: false,
  );

  UserProfile copyWith({
    String? displayName,
    String? language,
    UserDiet? diet,
    List<String>? allergies,
    KitchenConfidence? kitchenConfidence,
    int? householdServings,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? onboarded,
  }) =>
      UserProfile(
        displayName: displayName ?? this.displayName,
        language: language ?? this.language,
        diet: diet ?? this.diet,
        allergies: allergies ?? this.allergies,
        kitchenConfidence: kitchenConfidence ?? this.kitchenConfidence,
        householdServings: householdServings ?? this.householdServings,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        onboarded: onboarded ?? this.onboarded,
      );

  Map<String, dynamic> toJson() => {
    'displayName': displayName,
    'language': language,
    'diet': diet.name,
    'allergies': allergies,
    'kitchenConfidence': kitchenConfidence.name,
    'householdServings': householdServings,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'onboarded': onboarded,
  };

  static UserProfile fromJson(Map<String, dynamic> json) {
    final createdAt = DateTime.tryParse(json['createdAt']?.toString() ?? '');
    final updatedAt = DateTime.tryParse(json['updatedAt']?.toString() ?? '');

    final allergiesRaw = json['allergies'];
    final allergies = allergiesRaw is List
        ? allergiesRaw.map((e) => e.toString()).where((e) => e.trim().isNotEmpty).toList(growable: false)
        : const <String>[];

    return UserProfile(
      displayName: (json['displayName'] ?? '').toString(),
      language: _coerceLanguageCode((json['language'] ?? '').toString()),
      diet: UserDiet.fromName((json['diet'] ?? '').toString()),
      allergies: allergies,
      kitchenConfidence: KitchenConfidence.fromName((json['kitchenConfidence'] ?? '').toString()),
      householdServings: int.tryParse(json['householdServings']?.toString() ?? '') ?? 1,
      createdAt: createdAt ?? DateTime.now(),
      updatedAt: updatedAt ?? DateTime.now(),
      onboarded: json['onboarded'] == true,
    );
  }

  static String _coerceLanguageCode(String raw) {
    final v = raw.trim().toLowerCase();
    switch (v) {
      case 'en':
      case 'de':
      case 'fr':
      case 'it':
        return v;
      default:
        return 'en';
    }
  }

  String toPrefsString() => jsonEncode(toJson());

  static UserProfile? fromPrefsString(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return UserProfile.fromJson(decoded);
      if (decoded is Map) return UserProfile.fromJson(decoded.cast<String, dynamic>());
      return null;
    } catch (_) {
      return null;
    }
  }
}

enum UserDiet {
  omnivore,
  vegetarian,
  pescatarian,
  vegan,
  flexitarian;

  static UserDiet fromName(String name) {
    for (final v in UserDiet.values) {
      if (v.name == name) return v;
    }
    return UserDiet.omnivore;
  }
}

enum KitchenConfidence {
  beginner,
  fastEfficient,
  confident;

  static KitchenConfidence fromName(String name) {
    for (final v in KitchenConfidence.values) {
      if (v.name == name) return v;
    }
    return KitchenConfidence.beginner;
  }
}
