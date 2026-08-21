import 'package:flutter_test/flutter_test.dart';

import 'package:optimeal/models/planner_slot_ref.dart';
import 'package:optimeal/services/data_change_signal.dart';
import 'package:optimeal/services/planner_cook_attribution_service.dart';
import 'package:optimeal/services/weekly_plan_service.dart';

import '../support/fake_weekly_plan_backend.dart';

/// CLAUDE.md roadmap item 27, ruling: option A. A finished cook marks the
/// planner slot it was LAUNCHED from, and nothing else — no title matching, no
/// inference of any kind.

/// A fixed pair of anchored weeks, so nothing here depends on when the suite
/// runs. `_week` is a real Monday.
const String _week = '2026-08-24';
const String _nextWeek = '2026-08-31';

Map<String, dynamic> _row({
  required int dayIndex,
  int slotIndex = 0,
  required String title,
  bool cooked = false,
  String userId = 'user-1',
  String weekStart = _week,
}) =>
    {
      'user_id': userId,
      'week_start': weekStart,
      'day_index': dayIndex,
      'slot_index': slotIndex,
      'title': title,
      'source': 'Custom AI Craving',
      'is_cooked': cooked,
    };

bool _cookedAt(FakeWeeklyPlanBackend backend, int day, int slot,
        {String weekStart = _week}) =>
    backend.rows.firstWhere((r) =>
        r['week_start'] == weekStart &&
        r['day_index'] == day &&
        r['slot_index'] == slot)['is_cooked'] as bool;

/// A backend that fails every write, to prove the post-cook sequence is never
/// put at risk by this side effect.
class _ThrowingBackend extends FakeWeeklyPlanBackend {
  @override
  Future<void> markSlotCooked({
    required String userId,
    required String weekStart,
    required int dayIndex,
    required int slotIndex,
    required bool cooked,
  }) async {
    markCookedCalls++;
    throw Exception('network is down');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('marks exactly the launched slot cooked', () async {
    final backend = FakeWeeklyPlanBackend();
    backend.rows.add(_row(dayIndex: 2, title: 'Zucchini Fritters'));
    final service = PlannerCookAttributionService(backend: backend);

    final wrote = await service.markCookedFromCompletion(
      slot: const PlannerSlotRef(weekStart: _week, dayIndex: 2, slotIndex: 0),
      isReCook: false,
    );

    expect(wrote, isTrue);
    expect(_cookedAt(backend, 2, 0), isTrue);
    expect(backend.markCookedTargets, [(weekStart: _week, dayIndex: 2, slotIndex: 0)]);
  });

  test(
      'the same dish planned on two days: only the launched day is even '
      'addressed', () async {
    final backend = FakeWeeklyPlanBackend();
    // Identical titles — the exact case a title-matching heuristic would get
    // wrong, and the reason this attribution is carried rather than derived.
    backend.rows.add(_row(dayIndex: 1, title: 'Zucchini Fritters'));
    backend.rows.add(_row(dayIndex: 4, title: 'Zucchini Fritters'));
    final service = PlannerCookAttributionService(backend: backend);

    await service.markCookedFromCompletion(
      slot: const PlannerSlotRef(weekStart: _week, dayIndex: 4, slotIndex: 0),
      isReCook: false,
    );

    expect(_cookedAt(backend, 1, 0), isFalse);
    expect(_cookedAt(backend, 4, 0), isTrue);
    expect(backend.markCookedTargets, [(weekStart: _week, dayIndex: 4, slotIndex: 0)]);
  });

  test('the second meal of a day is addressed by its own slot index', () async {
    final backend = FakeWeeklyPlanBackend();
    backend.rows.add(_row(dayIndex: 3, slotIndex: 0, title: 'Soup'));
    backend.rows.add(_row(dayIndex: 3, slotIndex: 1, title: 'Tart'));
    final service = PlannerCookAttributionService(backend: backend);

    await service.markCookedFromCompletion(
      slot: const PlannerSlotRef(weekStart: _week, dayIndex: 3, slotIndex: 1),
      isReCook: false,
    );

    expect(_cookedAt(backend, 3, 0), isFalse);
    expect(_cookedAt(backend, 3, 1), isTrue);
  });

  test('a cook launched from anywhere else touches no plan row at all',
      () async {
    final backend = FakeWeeklyPlanBackend();
    backend.rows.add(_row(dayIndex: 2, title: 'Zucchini Fritters'));
    final service = PlannerCookAttributionService(backend: backend);

    final wrote =
        await service.markCookedFromCompletion(slot: null, isReCook: false);

    expect(wrote, isFalse);
    expect(backend.markCookedCalls, 0);
    expect(backend.upsertCalls, 0);
    expect(backend.deleteCalls, 0);
    expect(_cookedAt(backend, 2, 0), isFalse);
  });

  test('a re-cook never marks a slot', () async {
    final backend = FakeWeeklyPlanBackend();
    backend.rows.add(_row(dayIndex: 2, title: 'Zucchini Fritters'));
    final service = PlannerCookAttributionService(backend: backend);

    final wrote = await service.markCookedFromCompletion(
      slot: const PlannerSlotRef(weekStart: _week, dayIndex: 2, slotIndex: 0),
      isReCook: true,
    );

    expect(wrote, isFalse);
    expect(backend.markCookedCalls, 0);
  });

  test('no signed-in user: nothing is written and nothing throws', () async {
    final backend = FakeWeeklyPlanBackend()..currentUserId = null;
    backend.rows.add(_row(dayIndex: 2, title: 'Zucchini Fritters'));
    final service = PlannerCookAttributionService(backend: backend);

    final wrote = await service.markCookedFromCompletion(
      slot: const PlannerSlotRef(weekStart: _week, dayIndex: 2, slotIndex: 0),
      isReCook: false,
    );

    expect(wrote, isFalse);
    expect(backend.markCookedCalls, 0);
  });

  test('a failed write is swallowed — the post-cook sequence must not break',
      () async {
    final backend = _ThrowingBackend();
    final service = PlannerCookAttributionService(backend: backend);

    final wrote = await service.markCookedFromCompletion(
      slot: const PlannerSlotRef(weekStart: _week, dayIndex: 2, slotIndex: 0),
      isReCook: false,
    );

    expect(wrote, isFalse);
    expect(backend.markCookedCalls, 1);
  });

  test('a slot removed while it was being cooked is a no-op, not an error',
      () async {
    final backend = FakeWeeklyPlanBackend();
    final service = PlannerCookAttributionService(backend: backend);

    final wrote = await service.markCookedFromCompletion(
      slot: const PlannerSlotRef(weekStart: _week, dayIndex: 6, slotIndex: 1),
      isReCook: false,
    );

    // The UPDATE ran and matched nothing. It must never fall back to an
    // insert: that would resurrect a meal the user deleted.
    expect(wrote, isTrue);
    expect(backend.rows, isEmpty);
  });

  group('the mealPlan signal', () {
    test('fires after a successful write', () async {
      final backend = FakeWeeklyPlanBackend();
      backend.rows.add(_row(dayIndex: 0, title: 'Soup'));
      final service = PlannerCookAttributionService(backend: backend);

      var fired = 0;
      final sub = AppDataChanges.mealPlan.listen(() => fired++);
      addTearDown(sub.cancel);

      await service.markCookedFromCompletion(
        slot: const PlannerSlotRef(weekStart: _week, dayIndex: 0, slotIndex: 0),
        isReCook: false,
      );
      await Future<void>.delayed(Duration.zero);

      expect(fired, 1);
    });

    test('does not fire when there was nothing to attribute', () async {
      final backend = FakeWeeklyPlanBackend();
      final service = PlannerCookAttributionService(backend: backend);

      var fired = 0;
      final sub = AppDataChanges.mealPlan.listen(() => fired++);
      addTearDown(sub.cancel);

      await service.markCookedFromCompletion(slot: null, isReCook: false);
      await Future<void>.delayed(Duration.zero);

      expect(fired, 0);
    });
  });

  test('the same weekday in two weeks is two different slots', () async {
    final backend = FakeWeeklyPlanBackend();
    backend.rows.add(_row(dayIndex: 2, title: 'Zucchini Fritters'));
    backend.rows.add(
        _row(dayIndex: 2, title: 'Zucchini Fritters', weekStart: _nextWeek));
    final service = PlannerCookAttributionService(backend: backend);

    // The case week anchoring exists for: without week_start in the identity,
    // this write would match both rows.
    await service.markCookedFromCompletion(
      slot: const PlannerSlotRef(
          weekStart: _nextWeek, dayIndex: 2, slotIndex: 0),
      isReCook: false,
    );

    expect(_cookedAt(backend, 2, 0), isFalse);
    expect(_cookedAt(backend, 2, 0, weekStart: _nextWeek), isTrue);
  });

  group('PlannerSlotRef round trip', () {
    test('survives the json hop the active cook session uses', () {
      const slot =
          PlannerSlotRef(weekStart: _week, dayIndex: 5, slotIndex: 1);
      expect(PlannerSlotRef.fromJson(slot.toJson()), slot);
    });

    test('the week is part of identity, not decoration', () {
      expect(
        const PlannerSlotRef(weekStart: _week, dayIndex: 5, slotIndex: 1),
        isNot(const PlannerSlotRef(
            weekStart: _nextWeek, dayIndex: 5, slotIndex: 1)),
      );
    });

    test('anything unusable reads as no slot rather than a guessed one', () {
      expect(PlannerSlotRef.fromJson(null), isNull);
      expect(PlannerSlotRef.fromJson(const {}), isNull);
      expect(PlannerSlotRef.fromJson(const {'dayIndex': 2}), isNull);
      expect(
          PlannerSlotRef.fromJson(
              const {'weekStart': _week, 'dayIndex': -1, 'slotIndex': 0}),
          isNull);
      // A session saved before week anchoring: no honest week to invent, since
      // the plan it belonged to may since have rolled over.
      expect(
          PlannerSlotRef.fromJson(const {'dayIndex': 2, 'slotIndex': 0}),
          isNull);
    });
  });

  test('the real backend exposes markSlotCooked as part of the seam', () {
    // Guards against the attribution write quietly bypassing WeeklyPlanBackend
    // and reaching for Supabase.instance directly, which is what made the
    // planner untestable before the seam existed.
    expect(SupabaseWeeklyPlanBackend(), isA<WeeklyPlanBackend>());
  });
}
