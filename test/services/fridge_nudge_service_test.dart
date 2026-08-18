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

  group('FridgeNudgeService — case 1 (uncooked generation)', () {
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

      expect(scheduler.cancelCalls, contains(FridgeNudgeService.notificationId));
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
      expect(scheduler.cancelCalls.where((id) => id == FridgeNudgeService.notificationId), hasLength(1));
    });
  });

  group('FridgeNudgeService — case 2 (leftover ingredients)', () {
    // Note: since device-test round F13, FridgeNudgeService no longer
    // persists the entered-ingredients list itself — that's now
    // FridgeClearerEntryService's job (shared with the Waste Ledger
    // provenance rule). These tests pass enteredIngredients directly, as
    // OnePanCookingRoadmapScreen._logCookSessionCompletion now does after
    // reading it from that shared store.

    test('leftover copy names only the ingredients missing from the cooked recipe', () async {
      final scheduler = FakeFridgeNudgeScheduler();
      final service = FridgeNudgeService(scheduler: scheduler);

      final before = DateTime.now();
      await service.onFridgeClearerCookCompleted(
        enteredIngredients: const ['Zucchini', 'Eggs', 'Cheese'],
        cookedIngredients: const ['300g Zucchini (diced)', '2 Eggs'],
      );
      final after = DateTime.now();

      final leftoverCalls = scheduler.scheduleCalls.where((c) => c.id == FridgeNudgeService.leftoverNotificationId);
      expect(leftoverCalls, hasLength(1));
      final call = leftoverCalls.single;
      expect(call.body, contains('Cheese'));
      expect(call.body, isNot(contains('Zucchini')));
      expect(call.body, isNot(contains('Eggs')));
      expect(call.fireTime.isAfter(before.add(FridgeNudgeService.nudgeDelay).subtract(const Duration(seconds: 5))), isTrue);
      expect(call.fireTime.isBefore(after.add(FridgeNudgeService.nudgeDelay).add(const Duration(seconds: 5))), isTrue);
      expect(await service.hasPendingLeftoverNudge(), isTrue);
    });

    test('no leftover nudge when every entered ingredient appears in the cooked recipe', () async {
      final scheduler = FakeFridgeNudgeScheduler();
      final service = FridgeNudgeService(scheduler: scheduler);

      await service.onFridgeClearerCookCompleted(
        enteredIngredients: const ['Zucchini', 'Eggs'],
        cookedIngredients: const ['300g Zucchini (diced)', '2 Eggs', '1 tbsp Olive Oil'],
      );

      expect(scheduler.scheduleCalls.where((c) => c.id == FridgeNudgeService.leftoverNotificationId), isEmpty);
      expect(await service.hasPendingLeftoverNudge(), isFalse);
    });

    test('no leftover nudge when nothing was entered', () async {
      final scheduler = FakeFridgeNudgeScheduler();
      final service = FridgeNudgeService(scheduler: scheduler);

      await service.onFridgeClearerCookCompleted(
        enteredIngredients: const [],
        cookedIngredients: const ['300g Zucchini'],
      );

      expect(scheduler.scheduleCalls, isEmpty);
      expect(await service.hasPendingLeftoverNudge(), isFalse);
    });

    test('onRelevantCookCompleted cancels a pending leftover nudge', () async {
      final scheduler = FakeFridgeNudgeScheduler();
      final service = FridgeNudgeService(scheduler: scheduler);

      await service.onFridgeClearerCookCompleted(
        enteredIngredients: const ['Zucchini', 'Cheese'],
        cookedIngredients: const ['Zucchini'],
      );
      expect(await service.hasPendingLeftoverNudge(), isTrue);

      await service.onRelevantCookCompleted();

      expect(scheduler.cancelCalls, contains(FridgeNudgeService.leftoverNotificationId));
      expect(await service.hasPendingLeftoverNudge(), isFalse);
    });

    test('leftover title and a short-list body are both under 15 words', () {
      expect(FridgeNudgeService.leftoverNotificationTitle.split(RegExp(r'\s+')).length, lessThan(15));
      final body = FridgeNudgeService.leftoverNotificationBody(['Cheese', 'Cream']);
      expect(body.split(RegExp(r'\s+')).length, lessThan(15));
    });

    test('leftover body caps the shown list and adds a "+N more" tail for long lists', () {
      final body = FridgeNudgeService.leftoverNotificationBody(['A', 'B', 'C', 'D', 'E']);
      expect(body, contains('+2 more'));
      expect(body, isNot(contains('D')));
      expect(body, isNot(contains('E')));
    });
  });
}
