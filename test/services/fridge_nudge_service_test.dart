import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:optimeal/services/fridge_nudge_service.dart';

class ScheduleCall {
  ScheduleCall(this.fireTime, this.id, this.title, this.body);
  final DateTime fireTime;
  final int id;
  final String title;
  final String body;
}

class FakeFridgeNudgeScheduler implements FridgeNudgeScheduler {
  int ensureInitializedCalls = 0;
  int requestPermissionCalls = 0;
  final List<ScheduleCall> scheduleCalls = [];
  final List<int> cancelCalls = [];

  @override
  Future<void> ensureInitialized() async => ensureInitializedCalls++;

  @override
  Future<void> requestPermission() async => requestPermissionCalls++;

  @override
  Future<void> scheduleAt(
    DateTime fireTime, {
    required int id,
    required String title,
    required String body,
  }) async {
    scheduleCalls.add(ScheduleCall(fireTime, id, title, body));
  }

  @override
  Future<void> cancel(int id) async => cancelCalls.add(id);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('FridgeNudgeService', () {
    test('onFridgeClearerIngredientsGenerated schedules exactly one nudge, ~2 days out', () async {
      final scheduler = FakeFridgeNudgeScheduler();
      final service = FridgeNudgeService(scheduler: scheduler);

      final before = DateTime.now();
      await service.onFridgeClearerIngredientsGenerated();
      final after = DateTime.now();

      expect(scheduler.requestPermissionCalls, 1);
      expect(scheduler.scheduleCalls, hasLength(1));
      final call = scheduler.scheduleCalls.single;
      expect(call.id, FridgeNudgeService.notificationId);
      expect(call.fireTime.isAfter(before.add(FridgeNudgeService.nudgeDelay).subtract(const Duration(seconds: 5))), isTrue);
      expect(call.fireTime.isBefore(after.add(FridgeNudgeService.nudgeDelay).add(const Duration(seconds: 5))), isTrue);
      expect(await service.hasPendingNudge(), isTrue);
    });

    test('notification copy is under 15 words for both title and body', () {
      expect(FridgeNudgeService.notificationTitle.split(RegExp(r'\s+')).length, lessThan(15));
      expect(FridgeNudgeService.notificationBody.split(RegExp(r'\s+')).length, lessThan(15));
    });

    test('a second generation replaces the pending nudge rather than stacking a second one', () async {
      final scheduler = FakeFridgeNudgeScheduler();
      final service = FridgeNudgeService(scheduler: scheduler);

      await service.onFridgeClearerIngredientsGenerated();
      await service.onFridgeClearerIngredientsGenerated();

      // Two schedule calls happened (each generation is its own trigger),
      // but both use the same stable id, so the platform plugin replaces
      // the pending alarm rather than stacking two — "one nudge only".
      expect(scheduler.scheduleCalls, hasLength(2));
      expect(scheduler.scheduleCalls.map((c) => c.id).toSet(), {FridgeNudgeService.notificationId});
      expect(await service.hasPendingNudge(), isTrue);
    });

    test('onRelevantCookCompleted cancels a pending nudge and clears pending state', () async {
      final scheduler = FakeFridgeNudgeScheduler();
      final service = FridgeNudgeService(scheduler: scheduler);

      await service.onFridgeClearerIngredientsGenerated();
      expect(await service.hasPendingNudge(), isTrue);

      await service.onRelevantCookCompleted();

      expect(scheduler.cancelCalls, [FridgeNudgeService.notificationId]);
      expect(await service.hasPendingNudge(), isFalse);
    });

    test('onRelevantCookCompleted with no pending nudge is a harmless no-op', () async {
      final scheduler = FakeFridgeNudgeScheduler();
      final service = FridgeNudgeService(scheduler: scheduler);

      await service.onRelevantCookCompleted();

      expect(scheduler.cancelCalls, isEmpty);
      expect(await service.hasPendingNudge(), isFalse);
    });

    test('hasPendingNudge starts false before any generation', () async {
      final scheduler = FakeFridgeNudgeScheduler();
      final service = FridgeNudgeService(scheduler: scheduler);

      expect(await service.hasPendingNudge(), isFalse);
      expect(scheduler.scheduleCalls, isEmpty);
    });

    test('a completed cook after cancellation does not re-cancel or error', () async {
      final scheduler = FakeFridgeNudgeScheduler();
      final service = FridgeNudgeService(scheduler: scheduler);

      await service.onFridgeClearerIngredientsGenerated();
      await service.onRelevantCookCompleted();
      await service.onRelevantCookCompleted();

      // Only the first completion actually cancelled anything.
      expect(scheduler.cancelCalls, [FridgeNudgeService.notificationId]);
    });
  });
}
