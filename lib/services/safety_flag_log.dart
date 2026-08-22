import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:optimeal/services/safety_validator.dart';

/// Where safety validator outcomes go.
///
/// **A separate buffer from `CompatibilityFlagLog`, on purpose.** The two logs
/// answer different questions and have different lifetimes as evidence: the
/// compatibility log answers "how often does the model break the one-band
/// rule", a tuning question, while this one answers "did a safety rule fire,
/// and did the guarantee actually apply" — which is the evidence behind a
/// pre-launch blocker. Interleaving them in one ring buffer would let a noisy
/// week of timing flags evict the safety history, and 50 entries is not many.
///
/// Same shape as the compatibility log otherwise, deliberately: bounded ring
/// buffer, newest first, every write wrapped so a logging failure can never
/// break a generation.
///
/// Local, not a Supabase table — same reasoning as the compatibility log. The
/// case for a table starts when there are real testers whose flag rates cannot
/// be read off their own phones.
abstract final class SafetyFlagLog {
  static const String storageKey = 'safety_flag_log_v1';
  static const int maxEntries = 50;

  /// Records one completed safety pass. Called for every validated
  /// generation, clean or not — a log that only holds failures cannot
  /// produce a rate.
  static Future<void> record({
    required String surface,
    required SafetyReport report,
    required int retriesUsed,
    required bool servedWithFindings,
  }) async {
    final entry = <String, dynamic>{
      'at': DateTime.now().toUtc().toIso8601String(),
      'surface': surface,
      'retries_used': retriesUsed,
      'served_with_findings': servedWithFindings,
      'injections_applied': report.injections.length,
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
      debugPrint('SafetyFlagLog: write failed ($e) — generation unaffected');
    }

    debugPrint('SafetyFlagLog: ${jsonEncode(entry)}');
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
      debugPrint('SafetyFlagLog: read failed ($e)');
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
