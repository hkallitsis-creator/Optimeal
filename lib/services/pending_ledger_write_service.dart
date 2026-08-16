import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One `waste_ledger_events` insert that failed to reach Supabase and
/// needs a retry. See CLAUDE.md Roadmap item 27.
///
/// [payload] is the exact map that was (or would have been) passed to
/// `.insert(...)` — persisted verbatim, not a hand-selected subset of
/// fields, so a retry can't silently diverge from what the original
/// attempt would have written. [idempotencyKey] must be reused as-is on
/// retry, never regenerated — that's what lets a retry safely collide
/// with a write that actually succeeded server-side despite the client
/// never seeing a successful response.
class PendingLedgerWrite {
  const PendingLedgerWrite({
    required this.idempotencyKey,
    required this.payload,
    required this.queuedAt,
  });

  final String idempotencyKey;
  final Map<String, dynamic> payload;
  final DateTime queuedAt;

  Map<String, dynamic> toJson() => {
        'idempotencyKey': idempotencyKey,
        'payload': payload,
        'queuedAt': queuedAt.toIso8601String(),
      };

  factory PendingLedgerWrite.fromJson(Map<String, dynamic> json) => PendingLedgerWrite(
        idempotencyKey: json['idempotencyKey'] as String,
        payload: Map<String, dynamic>.from(json['payload'] as Map),
        queuedAt: DateTime.parse(json['queuedAt'] as String),
      );
}

/// Locally persists ledger writes that failed to reach Supabase, so they
/// can be retried later — independent of the cook session that produced
/// them. Deliberately its own store, not [CookSessionStorageService]:
/// that service clears its state on completion, but a pending ledger
/// write must outlive the cook session entirely.
///
/// SharedPreferences-backed, matching this project's existing pattern for
/// small local stores (see `LedgerService`'s own weekly-events store,
/// `CookSessionStorageService`, `UserProfileService`).
class PendingLedgerWriteService {
  static const String _prefsKey = 'pending_ledger_writes_v1';

  Future<List<PendingLedgerWrite>> loadAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.trim().isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final out = <PendingLedgerWrite>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        try {
          out.add(PendingLedgerWrite.fromJson(Map<String, dynamic>.from(item)));
        } catch (e) {
          debugPrint('PendingLedgerWriteService.loadAll: skipping corrupted entry: $e');
        }
      }
      return out;
    } catch (e) {
      debugPrint('PendingLedgerWriteService.loadAll failed: $e');
      return const [];
    }
  }

  Future<void> add(PendingLedgerWrite write) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = await loadAll();
      final updated = [...existing, write];
      await prefs.setString(_prefsKey, jsonEncode(updated.map((e) => e.toJson()).toList(growable: false)));
    } catch (e) {
      debugPrint('PendingLedgerWriteService.add failed: $e');
    }
  }

  /// Removes the pending record with [idempotencyKey], if present. A no-op
  /// (not an error) if no record with that key exists.
  Future<void> clear(String idempotencyKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = await loadAll();
      final updated = existing.where((e) => e.idempotencyKey != idempotencyKey).toList(growable: false);
      await prefs.setString(_prefsKey, jsonEncode(updated.map((e) => e.toJson()).toList(growable: false)));
    } catch (e) {
      debugPrint('PendingLedgerWriteService.clear failed: $e');
    }
  }
}
