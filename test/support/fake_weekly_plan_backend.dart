import 'dart:async';

import 'package:optimeal/services/weekly_plan_service.dart';

/// In-memory stand-in for `public.user_meal_plans`.
///
/// The point of this fake is TIMING, not storage: [listForUser] can be held
/// open with [holdReads] so a test can reproduce the real ordering that made
/// a just-placed meal vanish — a read issued before a write, returning after
/// it. Same seam pattern as `FakeSavedRecipesBackend`.
class FakeWeeklyPlanBackend implements WeeklyPlanBackend {
  FakeWeeklyPlanBackend({this.currentUserId = 'user-1', this.holdReads = false});

  @override
  String? currentUserId;

  /// When true, every [listForUser] parks on a completer until
  /// [completeRead] is called. The snapshot it then returns is whatever
  /// [rows] held **at the moment the read was issued**, exactly like a real
  /// query that ran before a later insert.
  bool holdReads;

  final List<Map<String, dynamic>> rows = [];

  int listCalls = 0;
  int upsertCalls = 0;
  int deleteCalls = 0;
  int markCookedCalls = 0;

  /// Every `(week, day, slot)` [markSlotCooked] was called with, in order — so
  /// a test can assert not just which row ended up cooked but that no other row
  /// was even addressed.
  final List<({String weekStart, int dayIndex, int slotIndex})>
      markCookedTargets = [];

  /// Every `weekStarts` list [listForWeeks] was called with, so a test can
  /// prove the read was week-scoped rather than fetching everything and
  /// filtering client-side.
  final List<List<String>> readWeekScopes = [];

  final List<Completer<List<Map<String, dynamic>>>> _pendingReads = [];
  final List<List<Map<String, dynamic>>> _snapshots = [];

  int get pendingReadCount => _pendingReads.length;

  String _slotKey(String week, int day, int slot) => '$week|$day-$slot';

  int _indexOf(String userId, String week, int day, int slot) =>
      rows.indexWhere((r) =>
          r['user_id'] == userId &&
          _slotKey(r['week_start'] as String, r['day_index'] as int,
                  r['slot_index'] as int) ==
              _slotKey(week, day, slot));

  /// Releases the oldest held read with the snapshot it captured.
  void completeRead() {
    final completer = _pendingReads.removeAt(0);
    completer.complete(_snapshots.removeAt(0));
  }

  /// Mirrors the real query's `week_start IN (...)` filter, which is what makes
  /// past weeks unreachable — a fake that returned everything would hide the
  /// bug this scoping exists to prevent.
  @override
  Future<List<Map<String, dynamic>>> listForWeeks(
    String userId, {
    required List<String> weekStarts,
  }) {
    listCalls++;
    readWeekScopes.add(List<String>.from(weekStarts));
    final snapshot = rows
        .where((r) =>
            r['user_id'] == userId && weekStarts.contains(r['week_start']))
        .map((r) => Map<String, dynamic>.from(r))
        .toList(growable: false);
    if (!holdReads) return Future.value(snapshot);

    final completer = Completer<List<Map<String, dynamic>>>();
    _pendingReads.add(completer);
    _snapshots.add(snapshot);
    return completer.future;
  }

  /// Enforces the real table's slot identity, which since migration
  /// `20260822120000` includes `week_start` — the same four columns
  /// `SupabaseWeeklyPlanBackend.slotConflictTarget` names.
  @override
  Future<void> upsertSlot(Map<String, dynamic> row) async {
    upsertCalls++;
    final i = _indexOf(
        row['user_id'] as String,
        row['week_start'] as String,
        row['day_index'] as int,
        row['slot_index'] as int);
    if (i == -1) {
      rows.add(Map<String, dynamic>.from(row));
    } else {
      rows[i] = {...rows[i], ...row};
    }
  }

  @override
  Future<void> deleteSlot({
    required String userId,
    required String weekStart,
    required int dayIndex,
    required int slotIndex,
  }) async {
    deleteCalls++;
    final i = _indexOf(userId, weekStart, dayIndex, slotIndex);
    if (i != -1) rows.removeAt(i);
  }

  /// Mirrors the real UPDATE: touches only an existing row, and matching
  /// nothing is a silent no-op rather than an insert.
  @override
  Future<void> markSlotCooked({
    required String userId,
    required String weekStart,
    required int dayIndex,
    required int slotIndex,
    required bool cooked,
  }) async {
    markCookedCalls++;
    markCookedTargets.add(
        (weekStart: weekStart, dayIndex: dayIndex, slotIndex: slotIndex));
    final i = _indexOf(userId, weekStart, dayIndex, slotIndex);
    if (i == -1) return;
    rows[i] = {...rows[i], 'is_cooked': cooked};
  }
}
