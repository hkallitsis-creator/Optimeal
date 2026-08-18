import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:optimeal/data/pantry_staples.dart';
import 'package:optimeal/services/pending_ledger_write_service.dart';

/// Result of [LedgerService.logCompletion] or [LedgerService.retryPendingWrite].
///
/// Deliberately a sealed return type rather than a thrown exception: the
/// caller needs to distinguish "the waste_ledger_events row exists" from
/// "it doesn't," and a post-insert read-back failure (the follow-up
/// user_ledger_totals lookup) must never be able to collapse those two
/// cases together. See CLAUDE.md Roadmap item 27.
sealed class LedgerCompletionResult {
  const LedgerCompletionResult();
}

/// The waste_ledger_events row exists — either freshly inserted, or
/// already present from a prior attempt under the same idempotency key
/// (a 23505 unique-violation on retry is treated as success here, not
/// failure — see [LedgerService._performLedgerInsert]).
class LedgerCompletionSuccess extends LedgerCompletionResult {
  const LedgerCompletionSuccess({
    required this.ingredientsRescued,
    required this.ingredientsRescuedList,
    required this.lifetimeIngredientsRescued,
  });

  final int ingredientsRescued;
  final List<String> ingredientsRescuedList;

  /// Null only when the write itself succeeded but the follow-up
  /// `user_ledger_totals` read-back failed — the row exists, the figure
  /// just couldn't be confirmed. Never used to signal write failure.
  final int? lifetimeIngredientsRescued;
}

/// The waste_ledger_events row was never written. [payload] is the exact
/// map that was (or would have been) passed to `.insert(...)` — hand it
/// to [PendingLedgerWriteService] verbatim so a retry can reuse the same
/// idempotency key rather than generating a new one.
class LedgerCompletionWriteFailed extends LedgerCompletionResult {
  const LedgerCompletionWriteFailed({
    required this.payload,
    required this.error,
  });

  final Map<String, dynamic> payload;
  final Object error;
}

/// Service for writing and reading the user's waste-ledger metrics.
class LedgerService {
  SupabaseClient get _db => Supabase.instance.client;

  final PendingLedgerWriteService _pendingWriteService = PendingLedgerWriteService();

  static const String _weeklyEventsPrefsKey = 'waste_ledger_weekly_events_v1';

  /// The Waste Ledger provenance rule (device-test round F13, Harris's
  /// decision — replaces the old `freshProduceOnly` blocklist entirely).
  /// An ingredient counts as rescued iff and only if:
  /// (a) the user entered it into Fridge Clearer ([enteredIngredients]),
  /// (b) it appears in the completed cook ([cookedIngredients]), AND
  /// (c) it is not on the [pantryStaples] exclusion list.
  ///
  /// Counting is the default; exclusion is the exception — the inverse
  /// bias from the old blocklist, which grew to wrongly exclude genuinely
  /// perishable items (potatoes, onions) just for having a longer shelf
  /// life than lettuce. An ingredient the recipe added on its own (never
  /// entered by the user) never counts, regardless of how fresh it is —
  /// rule (a) alone excludes it.
  ///
  /// [cookedIngredients] matching is case-insensitive substring (cooked
  /// strings carry amounts/prep notes, e.g. "300g Zucchini (diced)").
  static List<String> computeRescuedIngredients({
    required List<String> enteredIngredients,
    required List<String> cookedIngredients,
  }) {
    final cookedLower = cookedIngredients.map((e) => e.toLowerCase()).toList(growable: false);
    final out = <String>[];
    for (final raw in enteredIngredients) {
      final e = raw.trim();
      if (e.isEmpty) continue;
      if (isPantryStaple(e)) continue;
      final appearsInCook = cookedLower.any((c) => c.contains(e.toLowerCase()));
      if (!appearsInCook) continue;
      out.add(e);
    }
    return out;
  }

  /// 16 cryptographically-random bytes, hex-encoded. Deliberately not
  /// derived from the rescue's content (ingredients, source, etc.) — a
  /// content hash would collide when a user legitimately rescues the same
  /// ingredients twice, silently swallowing the second real rescue as a
  /// "duplicate" and reintroducing the exact undercount this exists to
  /// prevent. Generated once per rescue attempt; retries must reuse the
  /// same key rather than calling this again.
  static String _generateIdempotencyKey() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static int _readIntFromRow(Map<String, dynamic>? row, List<String> keys) {
    if (row == null) return 0;
    for (final k in keys) {
      final v = row[k];
      if (v is int) return v;
      if (v is num) return v.toInt();
      final parsed = int.tryParse('${v ?? ''}');
      if (parsed != null) return parsed;
    }
    return 0;
  }

  /// Logs one completion event to `waste_ledger_events` and returns
  /// updated totals, counting only ingredients that pass the provenance
  /// rule — see [computeRescuedIngredients].
  ///
  /// [source] must be one of: 'fridge_clearer', 'cook_mode', 'custom_ai_recipe',
  /// 'fridge_countdown'. In practice, callers should use
  /// [CookModeSurface.ledgerSourceValue] rather than a literal — see
  /// CLAUDE.md Roadmap item 28.
  ///
  /// Does not throw for expected failure modes (auth, network, database) —
  /// returns [LedgerCompletionWriteFailed] instead, with the pending write
  /// already queued in [PendingLedgerWriteService] so it can be retried
  /// later. A thrown exception here would mean something unexpected went
  /// wrong, not a normal "the insert failed" case.
  Future<LedgerCompletionResult> logCompletion({
    required String source,
    String? recipeId,
    required List<String> enteredIngredients,
    required List<String> cookedIngredients,
  }) async {
    final user = _db.auth.currentUser;
    if (user == null) {
      debugPrint('LedgerService.logCompletion: not authenticated, cannot log.');
      return LedgerCompletionWriteFailed(
        payload: const {},
        error: Exception('Not authenticated: cannot log ledger completion.'),
      );
    }

    final rescuedIngredients = computeRescuedIngredients(
      enteredIngredients: enteredIngredients,
      cookedIngredients: cookedIngredients,
    );
    final ingredientsCount = rescuedIngredients.length;

    // Persist locally for weekly rollups (no backend dependency). This is
    // best-effort and should never block the main logging flow. Must run
    // exactly once per real rescue attempt — never called from the retry
    // path (_performLedgerInsert / retryPendingWrite), which would
    // otherwise append a second local weekly event for the same rescue.
    await _appendWeeklyEvent(rescuedIngredients);

    final idempotencyKey = _generateIdempotencyKey();
    final payload = <String, dynamic>{
      'user_id': user.id,
      'source': source,
      'recipe_id': (recipeId != null && recipeId.trim().isNotEmpty) ? recipeId.trim() : null,
      'ingredients_rescued': rescuedIngredients,
      'ingredients_count': ingredientsCount,
      'idempotency_key': idempotencyKey,
    };

    final result = await _performLedgerInsert(payload);
    if (result is LedgerCompletionWriteFailed) {
      await _pendingWriteService.add(
        PendingLedgerWrite(idempotencyKey: idempotencyKey, payload: payload, queuedAt: DateTime.now()),
      );
    }
    return result;
  }

  /// Retries a single previously-failed write from [PendingLedgerWriteService].
  ///
  /// Applies the stale-uid check from CLAUDE.md Roadmap item 27 first: if
  /// anonymous auth has since issued a different uid (e.g. after a
  /// reinstall), a write carrying the old one would fail RLS forever with
  /// no way to ever succeed — so it's discarded rather than retried.
  ///
  /// Clears the pending record on success (a fresh insert, or a 23505
  /// meaning an earlier attempt already landed — [_performLedgerInsert]
  /// reports both as [LedgerCompletionSuccess], so one check covers both).
  /// Left in place on any other failure so a later retry can try again.
  ///
  /// Not called from anywhere yet — no automatic trigger, no UI wired to
  /// it. Dead code until that's built as its own piece of work.
  Future<LedgerCompletionResult> retryPendingWrite(PendingLedgerWrite write) async {
    final currentUser = _db.auth.currentUser;
    final storedUserId = write.payload['user_id'] as String?;
    if (currentUser == null || storedUserId == null || storedUserId != currentUser.id) {
      debugPrint(
        'LedgerService.retryPendingWrite: stale or missing user_id for ${write.idempotencyKey}, discarding.',
      );
      await _pendingWriteService.clear(write.idempotencyKey);
      return LedgerCompletionWriteFailed(
        payload: write.payload,
        error: Exception('Pending ledger write discarded: stale user_id.'),
      );
    }

    final result = await _performLedgerInsert(write.payload);
    if (result is LedgerCompletionSuccess) {
      await _pendingWriteService.clear(write.idempotencyKey);
    }
    return result;
  }

  /// The insert-only path, shared by [logCompletion] and [retryPendingWrite].
  /// Deliberately does not call [_appendWeeklyEvent] — that must only ever
  /// run once per real rescue attempt, in [logCompletion], never on retry.
  ///
  /// Splits the insert and the post-insert totals read into separate
  /// `try` blocks so a read-back failure can never make this method
  /// report that the write itself failed.
  Future<LedgerCompletionResult> _performLedgerInsert(Map<String, dynamic> payload) async {
    try {
      await _db.from('waste_ledger_events').insert(payload);
    } on PostgrestException catch (e) {
      if (e.code != '23505') {
        debugPrint('LedgerService: waste_ledger_events insert failed: $e');
        return LedgerCompletionWriteFailed(payload: payload, error: e);
      }
      // Unique violation on idempotency_key: a prior attempt with this
      // exact key already inserted the row. Treat as success, not error.
      debugPrint('LedgerService: insert returned 23505 for ${payload['idempotency_key']} — already written, treating as success.');
    } catch (e) {
      debugPrint('LedgerService: waste_ledger_events insert failed: $e');
      return LedgerCompletionWriteFailed(payload: payload, error: e);
    }

    final userId = payload['user_id'] as String;
    int? lifetimeIngredientsRescued;
    try {
      final totalsRow = await _db.from('user_ledger_totals').select().eq('user_id', userId).maybeSingle();
      lifetimeIngredientsRescued = _readIntFromRow(totalsRow, ['lifetime_ingredients_rescued']);
    } catch (e) {
      debugPrint('LedgerService: user_ledger_totals read-back failed after a successful write: $e');
      // lifetimeIngredientsRescued stays null. The row exists either way —
      // this must not turn into a reported write failure.
    }

    final ingredientsRescuedList = ((payload['ingredients_rescued'] as List?) ?? const []).cast<String>();
    return LedgerCompletionSuccess(
      ingredientsRescued: (payload['ingredients_count'] as int?) ?? ingredientsRescuedList.length,
      ingredientsRescuedList: ingredientsRescuedList,
      lifetimeIngredientsRescued: lifetimeIngredientsRescued,
    );
  }

  /// Returns a weekly + lifetime summary for the Waste Ledger.
  ///
  /// Weekly data is computed from local on-device events persisted by
  /// [logCompletion] (timestamp + ingredients list).
  ///
  /// Returned map keys:
  /// - weeklyIngredientsRescued (int)
  /// - weeklyIngredientsList (List<String>)
  /// - lifetimeIngredientsRescued (int)
  Future<Map<String, dynamic>> getWeeklySummary() async {
    try {
      final events = await _loadWeeklyEvents();
      final start = _startOfCurrentWeekLocal();

      final weeklyIngredients = <String>[];
      for (final e in events) {
        if (e.timestamp.isBefore(start)) continue;
        weeklyIngredients.addAll(e.ingredients);
      }

      // Keep existing lifetime logic as-is (still sourced from the current
      // ledger totals store).
      final user = _db.auth.currentUser;
      int lifetimeIngredientsRescued = 0;
      if (user != null) {
        final totalsRow = await _db.from('user_ledger_totals').select().eq('user_id', user.id).maybeSingle();
        final v = totalsRow?['lifetime_ingredients_rescued'];
        if (v is int) lifetimeIngredientsRescued = v;
        if (v is num) lifetimeIngredientsRescued = v.toInt();
        if (v != null && lifetimeIngredientsRescued == 0) {
          lifetimeIngredientsRescued = int.tryParse('$v') ?? 0;
        }
      }

      return {
        'weeklyIngredientsRescued': weeklyIngredients.length,
        'weeklyIngredientsList': weeklyIngredients,
        'lifetimeIngredientsRescued': lifetimeIngredientsRescued,
      };
    } catch (e, st) {
      debugPrint('LedgerService.getWeeklySummary failed: $e\n$st');
      return {
        'weeklyIngredientsRescued': 0,
        'weeklyIngredientsList': <String>[],
        'lifetimeIngredientsRescued': 0,
      };
    }
  }

  /// Count of fresh-produce ingredients rescued so far this calendar month,
  /// computed from the same local weekly-events store [getWeeklySummary]
  /// already uses (90-day retention comfortably covers a month) — no new
  /// capture logic, just a different date filter. Backs the "Your Month"
  /// recap card (CLAUDE.md Retention Features Backlog item 3).
  Future<int> getMonthlyIngredientsRescuedCount() async {
    try {
      final events = await _loadWeeklyEvents();
      final now = DateTime.now();
      var count = 0;
      for (final e in events) {
        if (e.timestamp.year == now.year && e.timestamp.month == now.month) {
          count += e.ingredients.length;
        }
      }
      return count;
    } catch (e, st) {
      debugPrint('LedgerService.getMonthlyIngredientsRescuedCount failed: $e\n$st');
      return 0;
    }
  }

  DateTime _startOfCurrentWeekLocal() {
    final now = DateTime.now();
    final todayMidnight = DateTime(now.year, now.month, now.day);
    return todayMidnight.subtract(Duration(days: todayMidnight.weekday - DateTime.monday));
  }

  Future<void> _appendWeeklyEvent(List<String> freshIngredients) async {
    if (freshIngredients.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final events = await _loadWeeklyEvents(prefs: prefs);
      events.add(_WeeklyLedgerEvent(timestamp: DateTime.now(), ingredients: List<String>.from(freshIngredients)));

      // Opportunistically prune very old events to keep storage tidy.
      final cutoff = DateTime.now().subtract(const Duration(days: 90));
      events.removeWhere((e) => e.timestamp.isBefore(cutoff));

      await prefs.setString(_weeklyEventsPrefsKey, _encodeWeeklyEvents(events));
    } catch (e, st) {
      debugPrint('LedgerService: failed to persist weekly ledger event: $e\n$st');
    }
  }

  Future<List<_WeeklyLedgerEvent>> _loadWeeklyEvents({SharedPreferences? prefs}) async {
    try {
      final p = prefs ?? await SharedPreferences.getInstance();
      final raw = p.getString(_weeklyEventsPrefsKey);
      final decoded = _decodeWeeklyEvents(raw);
      // Sanitize storage if corrupted entries were skipped.
      await p.setString(_weeklyEventsPrefsKey, _encodeWeeklyEvents(decoded));
      return decoded;
    } catch (e, st) {
      debugPrint('LedgerService: failed to load weekly ledger events: $e\n$st');
      return <_WeeklyLedgerEvent>[];
    }
  }

  String _encodeWeeklyEvents(List<_WeeklyLedgerEvent> events) {
    final list = events
        .map((e) => {
              'ts': e.timestamp.toIso8601String(),
              'ingredients': e.ingredients,
            })
        .toList(growable: false);
    return jsonEncode(list);
  }

  List<_WeeklyLedgerEvent> _decodeWeeklyEvents(String? raw) {
    if (raw == null || raw.trim().isEmpty) return <_WeeklyLedgerEvent>[];

    // Backward/robust parsing: use a very small JSON-ish parser via
    // SharedPreferences string storage. Prefer JSON when possible.
    //
    // If the stored format isn't valid JSON (e.g., from an older build), we
    // gracefully reset.
    try {
      // Attempt JSON first.
      final dynamic decoded = jsonDecode(raw);
      if (decoded is! List) return <_WeeklyLedgerEvent>[];
      final out = <_WeeklyLedgerEvent>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        final tsRaw = item['ts'];
        final ingredientsRaw = item['ingredients'];
        final ts = DateTime.tryParse('${tsRaw ?? ''}');
        if (ts == null) continue;
        if (ingredientsRaw is! List) continue;
        final ingredients = <String>[];
        for (final i in ingredientsRaw) {
          final s = '${i ?? ''}'.trim();
          if (s.isEmpty) continue;
          ingredients.add(s);
        }
        if (ingredients.isEmpty) continue;
        out.add(_WeeklyLedgerEvent(timestamp: ts, ingredients: ingredients));
      }
      return out;
    } catch (_) {
      return <_WeeklyLedgerEvent>[];
    }
  }
}

class _WeeklyLedgerEvent {
  _WeeklyLedgerEvent({required this.timestamp, required this.ingredients});

  final DateTime timestamp;
  final List<String> ingredients;
}
