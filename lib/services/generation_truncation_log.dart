import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where `finish_reason: "length"` generations go — a model reply that hit
/// `max_tokens` mid-JSON (audit M-6).
///
/// Its own ring buffer, same 50-entry shape as the compatibility, safety and
/// allergen logs and separate for the same reason each of those is: this one
/// answers "how often does a recipe not fit the token budget", which decides
/// whether the budget is right — and a truncation is neither a timing flag
/// nor a hazard, so it must not evict (or hide among) either.
///
/// DORMANT until the `ask-chef-harris` redeploy: the deployed function does
/// not return `finish_reason` yet (it also hardcodes `max_tokens: 1200` —
/// the client already sends the raise, the function ignores it; the exact
/// diff is in `docs/sessions/2026-08-23_insurance-bundle.md`). The truncated
/// content itself still fails the recipe parser, so the user-facing behaviour
/// is already the existing retry/error path — this log is the observability
/// half that was missing.
abstract final class GenerationTruncationLog {
  static const String storageKey = 'generation_truncation_log_v1';
  static const int maxEntries = 50;

  static Future<void> record({
    required String? surface,
    required int contentChars,
    Map? usage,
  }) async {
    final entry = <String, dynamic>{
      'at': DateTime.now().toUtc().toIso8601String(),
      'surface': surface ?? 'unset',
      'finish_reason': 'length',
      'content_chars': contentChars,
      if (usage != null) 'completion_tokens': usage['completion_tokens'],
    };

    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getStringList(storageKey) ?? const <String>[];
      final next = <String>[jsonEncode(entry), ...existing];
      await prefs.setStringList(
        storageKey,
        next.length > maxEntries ? next.sublist(0, maxEntries) : next,
      );
    } catch (e) {
      debugPrint(
          'GenerationTruncationLog: write failed ($e) — generation unaffected');
    }

    debugPrint('GenerationTruncationLog: ${jsonEncode(entry)}');
  }

  /// Newest first.
  static Future<List<Map<String, dynamic>>> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return (prefs.getStringList(storageKey) ?? const <String>[])
          .map((s) => jsonDecode(s) as Map<String, dynamic>)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }
}
