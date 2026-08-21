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

  final List<Completer<List<Map<String, dynamic>>>> _pendingReads = [];
  final List<List<Map<String, dynamic>>> _snapshots = [];

  int get pendingReadCount => _pendingReads.length;

  String _slotKey(int day, int slot) => '$day-$slot';

  int _indexOf(String userId, int day, int slot) => rows.indexWhere((r) =>
      r['user_id'] == userId &&
      _slotKey(r['day_index'] as int, r['slot_index'] as int) ==
          _slotKey(day, slot));

  /// Releases the oldest held read with the snapshot it captured.
  void completeRead() {
    final completer = _pendingReads.removeAt(0);
    completer.complete(_snapshots.removeAt(0));
  }

  @override
  Future<List<Map<String, dynamic>>> listForUser(String userId) {
    listCalls++;
    final snapshot = rows
        .where((r) => r['user_id'] == userId)
        .map((r) => Map<String, dynamic>.from(r))
        .toList(growable: false);
    if (!holdReads) return Future.value(snapshot);

    final completer = Completer<List<Map<String, dynamic>>>();
    _pendingReads.add(completer);
    _snapshots.add(snapshot);
    return completer.future;
  }

  @override
  Future<void> upsertSlot(Map<String, dynamic> row) async {
    upsertCalls++;
    final i = _indexOf(row['user_id'] as String, row['day_index'] as int,
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
    required int dayIndex,
    required int slotIndex,
  }) async {
    deleteCalls++;
    final i = _indexOf(userId, dayIndex, slotIndex);
    if (i != -1) rows.removeAt(i);
  }
}
