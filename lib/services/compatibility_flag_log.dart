import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:optimeal/services/cooking_compatibility_validator.dart';

/// Where compatibility validator outcomes go.
///
/// **Local, not a table.** The session brief allowed a Supabase table if one
/// were genuinely needed; it is not, yet. Every consumer of this data today is
/// the developer answering "how often does the model break the one-band rule,
/// and does the correction note work?", which a device-local log answers
/// completely. A table would add a migration, an RLS policy, a grant, a write
/// path on the hot generation route and a per-call round trip, to answer the
/// same question from a different machine. The case FOR a table starts the
/// moment there are real testers whose flag rates cannot be read off their
/// phones — see the session record.
///
/// Bounded ring buffer, newest first, [maxEntries] deep: this writes on a
/// generation path that a user may hit many times a day, and an unbounded log
/// in `SharedPreferences` is a slow leak.
///
/// Every write is wrapped so a logging failure can never break a generation.
/// The whole design is fail-open; a log that could throw would undo that.
abstract final class CompatibilityFlagLog {
  static const String storageKey = 'compatibility_flag_log_v1';
  static const int maxEntries = 50;

  /// Records one completed generation. Called for every validated generation,
  /// clean or not — a log that only holds failures cannot produce a rate.
  static Future<void> record({
    required String surface,
    required CompatibilityReport report,
    required int retriesUsed,
    required bool servedWithFlags,
  }) async {
    final entry = <String, dynamic>{
      'at': DateTime.now().toUtc().toIso8601String(),
      'surface': surface,
      'retries_used': retriesUsed,
      'served_with_flags': servedWithFlags,
      ...report.toJson(),
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
      debugPrint('CompatibilityFlagLog: write failed ($e) — generation unaffected');
    }

    // Mirrored to the device log so a live dev session can watch the rate
    // without reading storage back. Compiles out of release builds.
    debugPrint('CompatibilityFlagLog: ${jsonEncode(entry)}');
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
      debugPrint('CompatibilityFlagLog: read failed ($e)');
      return const [];
    }
  }

  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(storageKey);
    } catch (_) {
      // Nothing to recover from — this is a developer convenience.
    }
  }
}
