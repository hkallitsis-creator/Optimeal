import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The raw `user_meal_plans` operations, behind a seam.
///
/// Same pattern (and same reason) as `SavedRecipesBackend`: the Weekly
/// Planner's real logic — optimistic placement, the load/write ordering rules,
/// retry — should be testable without a live database or a signed-in user.
/// Until 2026-08-22 the screen talked to `Supabase.instance.client` directly,
/// which is why its load-clobbers-a-just-placed-meal bug had no regression
/// test to catch it.
///
/// The row shape is the screen's, not this layer's: [upsertSlot] takes the map
/// the screen builds and [listForUser] hands rows back untouched. This is a
/// transport seam, not a model.
abstract class WeeklyPlanBackend {
  /// Null when there is no signed-in user — and also when Supabase was never
  /// initialized. Callers treat null as "stay local, stop the loader".
  String? get currentUserId;

  /// All of the user's planned slots. Ordered by day then slot, though the
  /// screen re-indexes anyway.
  Future<List<Map<String, dynamic>>> listForUser(String userId);

  Future<void> upsertSlot(Map<String, dynamic> row);

  Future<void> deleteSlot({
    required String userId,
    required int dayIndex,
    required int slotIndex,
  });
}

class SupabaseWeeklyPlanBackend implements WeeklyPlanBackend {
  static const String table = 'user_meal_plans';

  SupabaseClient get _db => Supabase.instance.client;

  @override
  String? get currentUserId {
    try {
      return _db.auth.currentUser?.id;
    } catch (e) {
      debugPrint('WeeklyPlanBackend: Supabase unavailable, staying local: $e');
      return null;
    }
  }

  @override
  Future<List<Map<String, dynamic>>> listForUser(String userId) async {
    final rows = await _withJwtRetry(() => _db
        .from(table)
        .select()
        .eq('user_id', userId)
        .order('day_index', ascending: true)
        .order('slot_index', ascending: true));
    return rows.map((r) => Map<String, dynamic>.from(r)).toList(growable: false);
  }

  @override
  Future<void> upsertSlot(Map<String, dynamic> row) =>
      _withJwtRetry(() => _db.from(table).upsert(row));

  @override
  Future<void> deleteSlot({
    required String userId,
    required int dayIndex,
    required int slotIndex,
  }) =>
      _withJwtRetry(() => _db
          .from(table)
          .delete()
          .eq('user_id', userId)
          .eq('day_index', dayIndex)
          .eq('slot_index', slotIndex));

  /// PGRST303 ("JWT issued at future") fires when Supabase's PostgREST layer
  /// thinks our access token was issued in the future. In practice this is
  /// almost always a *stale* cached token rather than a real problem — a
  /// forced `refreshSession()` mints a fresh token and the retry succeeds.
  ///
  /// Lifted verbatim from `_WeeklyPlannerScreenState` when this seam was
  /// extracted: it is a Supabase transport concern, so it belongs on this side
  /// of the seam, not in the screen.
  static bool isJwtClockSkewError(Object e) {
    if (e is PostgrestException) {
      return e.code == 'PGRST303' ||
          e.message.toLowerCase().contains('jwt issued at future');
    }
    return e.toString().toLowerCase().contains('jwt issued at future');
  }

  Future<T> _withJwtRetry<T>(Future<T> Function() action) async {
    try {
      return await action();
    } catch (e) {
      if (!isJwtClockSkewError(e)) rethrow;
      debugPrint(
          'WeeklyPlanBackend: JWT clock-skew error detected, refreshing session and retrying once.');
      try {
        await _db.auth.refreshSession();
      } catch (refreshError) {
        debugPrint('WeeklyPlanBackend: session refresh failed: $refreshError');
        rethrow;
      }
      return await action();
    }
  }
}
