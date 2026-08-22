import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where allergen outcomes go — recipes and Fridge Clearer ideas alike.
///
/// Its own ring buffer, like the compatibility and safety logs, for the same
/// reason those are separate from each other: this one answers "did we ever
/// nearly serve someone something they cannot eat", which is the question
/// that would matter most in a post-mortem and must not be evicted by a busy
/// week of timing flags.
///
/// The guard fails **open** today — see `docs/DECISIONS.md`, where the
/// fail-closed argument is recorded and pending a ruling. Fail-open is only
/// defensible while it is loud, so this log is the load-bearing half of that
/// decision, not an accessory to it.
abstract final class AllergenFlagLog {
  static const String storageKey = 'allergen_flag_log_v1';
  static const int maxEntries = 50;

  /// One recipe served with unresolved violations, or one batch of ideas
  /// dropped before they reached the user.
  static Future<void> record({
    required String surface,
    required String outcome,
    required List<Map<String, dynamic>> details,
    int retriesUsed = 0,
  }) async {
    final entry = <String, dynamic>{
      'at': DateTime.now().toUtc().toIso8601String(),
      'surface': surface,
      'outcome': outcome,
      'retries_used': retriesUsed,
      'details': details,
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
      debugPrint('AllergenFlagLog: write failed ($e) — generation unaffected');
    }

    debugPrint('AllergenFlagLog: ${jsonEncode(entry)}');
  }

  /// Newest first. Malformed entries are skipped rather than thrown on.
  static Future<List<Map<String, dynamic>>> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(storageKey) ?? const <String>[];
      final out = <Map<String, dynamic>>[];
      for (final line in raw) {
        try {
          final decoded = jsonDecode(line);
          if (decoded is Map<String, dynamic>) out.add(decoded);
        } catch (_) {
          // A single corrupt line must not cost the rest of the log.
        }
      }
      return out;
    } catch (e) {
      debugPrint('AllergenFlagLog: read failed ($e)');
      return const [];
    }
  }

  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(storageKey);
    } catch (_) {
      // Developer convenience only.
    }
  }
}
