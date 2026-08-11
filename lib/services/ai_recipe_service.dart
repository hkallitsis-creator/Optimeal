import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Thrown when the AI recipe edge-function integration fails.
class AiRecipeServiceException implements Exception {
  AiRecipeServiceException(this.message, {this.cause, this.stackTrace});

  final String message;
  final Object? cause;
  final StackTrace? stackTrace;

  @override
  String toString() => 'AiRecipeServiceException: $message${cause == null ? '' : '\nCause: $cause'}';
}

/// Technical cooking “precision” metadata returned by the `ai-recipe-precision` edge function.
///
/// Notes:
/// - Shapes are kept flexible (`Map<String, dynamic>`) so the edge function can evolve
///   without forcing coordinated app releases.
/// - [source] is expected to be either "cache" or "generated".
class PrecisionData {
  const PrecisionData({
    this.heatSpec,
    this.saltTiming,
    this.knifeCutSpec,
    this.swissSubstitutes,
    this.baseRatios,
    required this.source,
  });

  final Map<String, dynamic>? heatSpec;
  final String? saltTiming;
  final String? knifeCutSpec;
  final Map<String, dynamic>? swissSubstitutes;
  final Map<String, dynamic>? baseRatios;
  final String source;

  factory PrecisionData.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic>? readMap(Object? v) => v is Map ? Map<String, dynamic>.from(v as Map) : null;
    String? readString(Object? v) => v is String && v.trim().isNotEmpty ? v : null;

    final src = (json['source'] is String) ? (json['source'] as String) : 'generated';
    return PrecisionData(
      heatSpec: readMap(json['heatSpec'] ?? json['heat_spec']),
      saltTiming: readString(json['saltTiming'] ?? json['salt_timing']),
      knifeCutSpec: readString(json['knifeCutSpec'] ?? json['knife_cut_spec'] ?? json['cutSpec'] ?? json['cut_spec']),
      swissSubstitutes: readMap(json['swissSubstitutes'] ?? json['swiss_substitutes'] ?? json['substitutes']),
      baseRatios: readMap(json['baseRatios'] ?? json['base_ratios'] ?? json['ratios']),
      source: (src == 'cache' || src == 'generated') ? src : 'generated',
    );
  }

  Map<String, dynamic> toJson() => {
        'heatSpec': heatSpec,
        'saltTiming': saltTiming,
        'knifeCutSpec': knifeCutSpec,
        'swissSubstitutes': swissSubstitutes,
        'baseRatios': baseRatios,
        'source': source,
      };
}

class AiRecipeService {
  SupabaseClient get _db => Supabase.instance.client;

  // User profile cache (loaded from `user_profiles`).
  Map<String, dynamic>? _cachedUserProfile;
  DateTime? _profileLoadedAt;

  Future<Map<String, dynamic>?> _getUserProfile() async {
    try {
      final loadedAt = _profileLoadedAt;
      if (_cachedUserProfile != null && loadedAt != null) {
        final age = DateTime.now().difference(loadedAt);
        if (age.inMinutes < 10) return _cachedUserProfile;
      }

      final user = _db.auth.currentUser;
      if (user == null) return null;

      // Preferred schema (per migration): `id` references auth.users.
      try {
        final Map<String, dynamic>? row = await _db.from('user_profiles').select().eq('id', user.id).maybeSingle();
        if (row != null) {
          _cachedUserProfile = Map<String, dynamic>.from(row);
          _profileLoadedAt = DateTime.now();
          return _cachedUserProfile;
        }
      } catch (e) {
        // Back-compat fallback (some schemas use `user_id`).
        debugPrint('AiRecipeService._getUserProfile: query by id failed, retrying user_id. Error: $e');
      }

      try {
        final Map<String, dynamic>? row = await _db.from('user_profiles').select().eq('user_id', user.id).maybeSingle();
        if (row != null) {
          _cachedUserProfile = Map<String, dynamic>.from(row);
          _profileLoadedAt = DateTime.now();
          return _cachedUserProfile;
        }
      } catch (e) {
        debugPrint('AiRecipeService._getUserProfile: query by user_id failed: $e');
      }

      _cachedUserProfile = null;
      _profileLoadedAt = DateTime.now();
      return null;
    } catch (e) {
      debugPrint('AiRecipeService._getUserProfile failed: $e');
      return null;
    }
  }

  /// Clears and re-loads the cached user profile.
  ///
  /// Not called anywhere yet; exists to support future “profile updated” events.
  Future<void> refreshUserProfile() async {
    _cachedUserProfile = null;
    _profileLoadedAt = null;
    await _getUserProfile();
  }

  String _buildUserSafetyContext(Map<String, dynamic>? profile) {
    if (profile == null) return '';

    String readString(String key) {
      final v = profile[key];
      if (v is String) return v.trim();
      return '';
    }

    final dietaryPreference = readString('dietary_preference');
    final portionSizeRaw = profile['portion_size'];
    final portionSize = (portionSizeRaw is int)
        ? portionSizeRaw
        : (portionSizeRaw is num)
            ? portionSizeRaw.toInt()
            : int.tryParse('${portionSizeRaw ?? ''}') ?? 0;
    final skillLevel = readString('skill_level');

    final allergiesRaw = profile['allergies'];
    final allergies = <String>[];
    if (allergiesRaw is List) {
      for (final a in allergiesRaw) {
        final s = a?.toString().trim();
        if (s != null && s.isNotEmpty) allergies.add(s);
      }
    }

    // Column name is `allergies_custom` per migration, but accept alt names too.
    final customAllergyText = (
      readString('allergies_custom').isNotEmpty
          ? readString('allergies_custom')
          : (readString('custom_allergy_text').isNotEmpty ? readString('custom_allergy_text') : readString('custom_allergies'))
    ).trim();

    final hasAllergies = allergies.isNotEmpty || customAllergyText.isNotEmpty;
    final allergyLine = hasAllergies
        ? <String>[...allergies, if (customAllergyText.isNotEmpty) customAllergyText].join(', ')
        : 'No known allergies reported.';

    final dietLine = dietaryPreference.isNotEmpty ? dietaryPreference : 'Not specified';
    final portionLine = portionSize > 0 ? '$portionSize people' : 'Not specified';
    final skillLine = skillLevel.isNotEmpty ? skillLevel : 'Not specified';

    return '''
---
USER SAFETY & PERSONALIZATION CONTEXT (MANDATORY — DO NOT IGNORE):
- Dietary restriction: $dietLine. Every ingredient and suggestion MUST comply with this restriction. Never suggest meat for Vegetarian/Vegan, never suggest fish/meat for Pescatarian-incompatible items, etc.
- ALLERGIES (SAFETY-CRITICAL, NON-NEGOTIABLE): $allergyLine. You must NEVER include any ingredient, derivative, or cross-contaminant risk tied to these allergens under any circumstances, even if the user's own message asks for a dish that traditionally contains them. If a requested dish inherently requires an allergen, substitute it and clearly flag the substitution.
- Household portion size: $portionLine. Scale all ingredient quantities accordingly.
- Skill level: $skillLine. If Beginner, use simple language, avoid unexplained jargon, add extra safety/timing guidance. If Intermediate, assume comfort with standard techniques. If Advanced, you may use precise technical language (knife specs in mm, Maillard timing, acid balancing) without over-explaining basics.
---
''';
  }

  String _hashSafetyRelevantProfileFields(Map<String, dynamic>? profile) {
    if (profile == null) return '';

    final dietaryPreference = (profile['dietary_preference'] ?? '').toString().trim();
    final skillLevel = (profile['skill_level'] ?? '').toString().trim();

    final allergiesRaw = profile['allergies'];
    final allergies = <String>[];
    if (allergiesRaw is List) {
      for (final a in allergiesRaw) {
        final s = a?.toString().trim();
        if (s != null && s.isNotEmpty) allergies.add(s);
      }
    }
    allergies.sort();

    final customAllergyText = (
      (profile['allergies_custom'] ?? '').toString().trim().isNotEmpty
          ? (profile['allergies_custom'] ?? '').toString().trim()
          : (profile['custom_allergy_text'] ?? '').toString().trim()
    ).trim();

    final payload = jsonEncode({
      'dietary_preference': dietaryPreference,
      'skill_level': skillLevel,
      'allergies': allergies,
      'custom_allergy_text': customAllergyText,
    });

    return sha256.convert(utf8.encode(payload)).toString();
  }

  Map<String, dynamic> _buildPrecisionRequestBody({
    required List<String> ingredients,
    required String method,
    required String protein,
    required String cutStyle,
    required Map<String, dynamic>? profile,
    required String safetyContext,
    required String profileSafetyHash,
  }) {
    List<String> normalizeList(List<String> xs) => xs.map((e) => e.trim()).where((e) => e.isNotEmpty).toList(growable: false);
    String normalizeString(String s) => s.trim();

    String? readProfileString(String key) {
      final v = profile?[key];
      if (v is String) {
        final s = v.trim();
        return s.isEmpty ? null : s;
      }
      return null;
    }

    int? readProfileInt(String key) {
      final v = profile?[key];
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v == null) return null;
      return int.tryParse(v.toString());
    }

    List<String>? readProfileStringList(String key) {
      final v = profile?[key];
      if (v is! List) return null;
      final out = <String>[];
      for (final item in v) {
        final s = item?.toString().trim();
        if (s != null && s.isNotEmpty) out.add(s);
      }
      return out.isEmpty ? null : out;
    }

    // These fields may be null for users who haven’t finished onboarding.
    // In that case we either omit them or provide a safe default (e.g. servings).
    final dietaryPreference = readProfileString('dietary_preference') ?? readProfileString('dietaryPreference');
    final skillLevel = readProfileString('skill_level') ?? readProfileString('skillLevel');
    final servings = readProfileInt('portion_size') ?? readProfileInt('servings');
    final allergies = readProfileStringList('allergies') ?? readProfileStringList('allergens');

    // Base request fields (what the edge function historically expects).
    // We include both camelCase + snake_case variants to be resilient if the
    // function’s handler expects one or the other.
    final body = <String, dynamic>{
      'ingredients': normalizeList(ingredients),
      'method': normalizeString(method),
      'protein': normalizeString(protein),
      'cutStyle': normalizeString(cutStyle),
      'cut_style': normalizeString(cutStyle),

      // User context fields (safe to ignore server-side if unknown).
      if (safetyContext.trim().isNotEmpty) 'userSafetyContext': safetyContext,
      if (safetyContext.trim().isNotEmpty) 'user_safety_context': safetyContext,
      if (profileSafetyHash.trim().isNotEmpty) 'profileSafetyHash': profileSafetyHash,
      if (profileSafetyHash.trim().isNotEmpty) 'profile_safety_hash': profileSafetyHash,

      // Profile fields that some versions of the function may expect.
      if (dietaryPreference != null) 'dietaryPreference': dietaryPreference,
      if (dietaryPreference != null) 'dietary_preference': dietaryPreference,
      if (skillLevel != null) 'skillLevel': skillLevel,
      if (skillLevel != null) 'skill_level': skillLevel,
      if (allergies != null) 'allergens': allergies,
      if (allergies != null) 'allergies': allergies,
      if (servings != null && servings > 0) 'servings': servings,
    };

    // Ensure we never serialize nulls (some edge functions treat null as “missing but invalid”).
    body.removeWhere((_, v) => v == null);
    return body;
  }

  /// Calls the `ai-recipe-precision` edge function and parses its response into [PrecisionData].
  ///
  /// Failure behavior: throws [AiRecipeServiceException] (no fallback).
  Future<PrecisionData> getPrecisionData({
    required List<String> ingredients,
    required String method,
    required String protein,
    required String cutStyle,
  }) async {
    try {
      final profile = await _getUserProfile();
      final safetyContext = _buildUserSafetyContext(profile);
      final profileSafetyHash = _hashSafetyRelevantProfileFields(profile);

      final body = _buildPrecisionRequestBody(
        ingredients: ingredients,
        method: method,
        protein: protein,
        cutStyle: cutStyle,
        profile: profile,
        safetyContext: safetyContext,
        profileSafetyHash: profileSafetyHash,
      );

      debugPrint('AiRecipeService.getPrecisionData → invoking ai-recipe-precision');
      debugPrint('AiRecipeService.getPrecisionData → payload: ${jsonEncode(body)}');

      final res = await _db.functions.invoke('ai-recipe-precision', body: body);
      final jsonMap = _coerceJsonMap(res.data);
      final dataMap = _unwrapDataEnvelope(jsonMap);
      return PrecisionData.fromJson(dataMap);
    } catch (e, st) {
      debugPrint('AiRecipeService.getPrecisionData failed: $e');
      debugPrint('AiRecipeService.getPrecisionData stack: $st');
      throw AiRecipeServiceException(
        'Failed to generate precision data.',
        cause: e,
        stackTrace: st,
      );
    }
  }

  Map<String, dynamic> _coerceJsonMap(Object? data) {
    if (data == null) throw const FormatException('Edge function returned null data.');

    if (data is Map) return Map<String, dynamic>.from(data as Map);
    if (data is String) {
      final decoded = jsonDecode(data);
      if (decoded is Map) return Map<String, dynamic>.from(decoded as Map);
    }

    throw FormatException('Unexpected response data type: ${data.runtimeType}');
  }

  Map<String, dynamic> _unwrapDataEnvelope(Map<String, dynamic> json) {
    final data = json['data'];
    if (data is Map) return Map<String, dynamic>.from(data as Map);
    return json;
  }

}
