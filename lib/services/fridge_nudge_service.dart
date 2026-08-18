import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'package:optimeal/nav.dart';

/// A scheduled local notification, abstracted so [FridgeNudgeService]'s
/// scheduling *rules* (fires once, cancels on cook, never repeats) can be
/// unit-tested without a real platform channel — `flutter_local_notifications`
/// has no test-mode implementation, unlike `shared_preferences`.
///
/// Actual notification delivery can only be verified on a real device.
abstract class FridgeNudgeScheduler {
  /// Wires up the plugin and its tap/action callback. Safe to call multiple
  /// times. Called eagerly at app startup (see main.dart) so a cold-start
  /// notification tap has a callback to land on — this does NOT request the
  /// permission or schedule anything, both of which stay strictly
  /// in-context (see [requestPermission]).
  Future<void> ensureInitialized();

  /// Requests the OS notification permission, if not already granted.
  /// Must only be called once there's an actual notification to schedule
  /// (docs/decisions_2026-08-17.md item 5 / CLAUDE.md D2 — requested in
  /// context, not at app launch).
  Future<void> requestPermission();

  /// Schedules exactly one notification at [fireTime]. Scheduling again
  /// with the same [id] replaces any still-pending notification under that
  /// id — this is how "one nudge only" is enforced, not by tracking state
  /// externally.
  Future<void> scheduleAt(
    DateTime fireTime, {
    required int id,
    required String title,
    required String body,
  });

  /// Cancels a pending notification by [id]. A no-op if nothing is pending.
  Future<void> cancel(int id);
}

class FlutterLocalNotificationsFridgeNudgeScheduler
    implements FridgeNudgeScheduler {
  FlutterLocalNotificationsFridgeNudgeScheduler() {
    tz_data.initializeTimeZones();
  }

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  static const _androidDetails = AndroidNotificationDetails(
    'fridge_nudge_channel',
    'Fridge nudges',
    channelDescription: 'A single nudge when fridge ingredients might go unused.',
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
    category: AndroidNotificationCategory.reminder,
    actions: <AndroidNotificationAction>[
      AndroidNotificationAction(fridgeNudgeActionFridgeClearer, 'Fridge Clearer'),
      AndroidNotificationAction(fridgeNudgeActionAiGenerator, 'AI generator'),
    ],
  );

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);
    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: handleFridgeNudgeResponse,
    );
    _initialized = true;
  }

  @override
  Future<void> ensureInitialized() => _ensureInitialized();

  @override
  Future<void> requestPermission() async {
    await _ensureInitialized();
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.requestNotificationsPermission();
  }

  @override
  Future<void> scheduleAt(
    DateTime fireTime, {
    required int id,
    required String title,
    required String body,
  }) async {
    await _ensureInitialized();
    await _plugin.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.from(fireTime, tz.local),
      const NotificationDetails(android: _androidDetails),
      // Inexact — avoids requiring the Android 12+ SCHEDULE_EXACT_ALARM
      // grant for a nudge that's inherently not time-critical.
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      // Android-only usage; this parameter only affects the iOS legacy
      // scheduling path, which isn't wired up here.
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  @override
  Future<void> cancel(int id) async {
    await _ensureInitialized();
    await _plugin.cancel(id);
  }
}

const String fridgeNudgeActionFridgeClearer = 'fridge_clearer';
const String fridgeNudgeActionAiGenerator = 'ai_generator';

/// Top-level so it can be used as a background notification-tap callback per
/// flutter_local_notifications' requirements. Deep-links via the app's
/// existing GoRouter instance, held by [AppRouter.lastRouter] once the app
/// has started at least once.
@pragma('vm:entry-point')
void handleFridgeNudgeResponse(NotificationResponse response) {
  final router = AppRouter.lastRouter;
  if (router == null) return;
  switch (response.actionId) {
    case fridgeNudgeActionFridgeClearer:
      router.push(AppRoutes.aiFridgeScrapGenerator);
      break;
    case fridgeNudgeActionAiGenerator:
      router.go(AppRoutes.homeOpenAiGenerator);
      break;
    default:
      // Plain tap (no action button) — just open the app to Home.
      router.go(AppRoutes.home);
  }
}

/// Schedules and cancels the two-case "unused Fridge Clearer ingredients"
/// nudge (docs/decisions_2026-08-17.md item 5; two-case spec is Harris's
/// 18 Aug decision, superseding the original single-case version):
///
/// - **Case 1 (uncooked generation)**: a recipe was generated but never
///   cooked — nudge 2 days after generation, copy unchanged from the
///   original single-case version.
/// - **Case 2 (leftover ingredients)**: a recipe WAS cooked, but some of
///   the ingredients the user entered never appeared in the cooked
///   recipe's own ingredient list — nudge 2 days after that cook, naming
///   only the leftover ingredients (entered minus the recipe's own list).
///
/// Both share the same hard rules: one nudge per trigger, never repeated,
/// never rescheduled for the same ingredients (a fresh case-1 trigger
/// simply replaces any still-pending case-1 nudge, same for case 2 — no
/// stacking), and both are cancelled by a subsequent genuine (non-re-cook)
/// completed cook on CookModeSurface.fridgeClearer (see
/// OnePanCookingRoadmapScreen._logCookSessionCompletion).
///
/// Case 2 needs to know what the user actually entered at generation
/// time — the Waste Ledger provenance rule (F13) independently needs the
/// exact same thing at the exact same moment, so that's persisted once,
/// centrally, by [FridgeClearerEntryService] rather than duplicated here.
/// [onFridgeClearerCookCompleted] takes the entered list as a parameter;
/// the caller (OnePanCookingRoadmapScreen._logCookSessionCompletion) reads
/// it once from that shared store and passes it to both this service and
/// LedgerService.
class FridgeNudgeService {
  FridgeNudgeService({FridgeNudgeScheduler? scheduler})
      : _scheduler = scheduler ?? FlutterLocalNotificationsFridgeNudgeScheduler();

  static final FridgeNudgeService instance = FridgeNudgeService();

  final FridgeNudgeScheduler _scheduler;

  static const int notificationId = 9001;
  static const int leftoverNotificationId = 9002;
  static const String _pendingSinceKey = 'fridge_nudge_pending_since_v1';
  static const String _leftoverPendingSinceKey = 'fridge_nudge_leftover_pending_since_v1';
  static const Duration nudgeDelay = Duration(days: 2);

  /// Case 1 copy — unchanged from the original single-case version. One
  /// short, warm-voiced line, under 15 words.
  static const String notificationTitle = "Still got those fridge ingredients?";
  static const String notificationBody =
      "Let's use them before they turn — Fridge Clearer or a quick AI recipe.";

  /// Case 2 title — fixed, since the ingredients themselves go in the body.
  static const String leftoverNotificationTitle = "A few fridge ingredients didn't make the cut";

  /// Case 2 body: names the specific leftover ingredients (max 3, "+N more"
  /// beyond that so this stays a plausible single-line notification body
  /// regardless of list length). Warm, under 15 words for a typical
  /// 1-3-ingredient case.
  static String leftoverNotificationBody(List<String> leftoverIngredients) {
    final names = leftoverIngredients.map((e) => e.trim()).where((e) => e.isNotEmpty).toList(growable: false);
    if (names.isEmpty) return "Let's use up what's left before it turns.";
    final shown = names.take(3).toList();
    final extra = names.length - shown.length;
    final list = extra > 0 ? '${shown.join(', ')}, +$extra more' : shown.join(', ');
    return "$list didn't make it into your last cook — let's use them up.";
  }

  /// Call once at app startup (see main.dart). Wires the tap/action
  /// callback only — never requests permission or schedules anything.
  /// Never throws; a failure here should not block startup.
  Future<void> initialize() async {
    try {
      await _scheduler.ensureInitialized();
    } catch (e) {
      debugPrint('FridgeNudgeService: initialize failed: $e');
    }
  }

  /// Call once, right after a Fridge Clearer recipe generation succeeds.
  /// Schedules the case-1 nudge (copy unchanged from the original
  /// single-case version).
  Future<void> onFridgeClearerIngredientsGenerated() async {
    try {
      await _scheduler.requestPermission();
      final fireTime = DateTime.now().add(nudgeDelay);
      await _scheduler.scheduleAt(
        fireTime,
        id: notificationId,
        title: notificationTitle,
        body: notificationBody,
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_pendingSinceKey, fireTime.toIso8601String());
    } catch (e) {
      debugPrint('FridgeNudgeService: failed to schedule nudge: $e');
    }
  }

  /// Call once a genuine (non-re-cook) Fridge Clearer cook completes, with
  /// the ingredients the user originally entered for this generation
  /// ([enteredIngredients], from [FridgeClearerEntryService]) and that
  /// recipe's own ingredient list as actually cooked ([cookedIngredients]
  /// — post-scaling display strings are fine, matching is substring-based).
  /// If any entered ingredient never appears in [cookedIngredients],
  /// schedules the case-2 leftover nudge naming only those. A no-op if
  /// [enteredIngredients] is empty or nothing is left over.
  Future<void> onFridgeClearerCookCompleted({
    required List<String> enteredIngredients,
    required List<String> cookedIngredients,
  }) async {
    try {
      final leftovers = _leftoverIngredients(enteredIngredients, cookedIngredients);
      if (leftovers.isEmpty) return;

      await _scheduler.requestPermission();
      final fireTime = DateTime.now().add(nudgeDelay);
      await _scheduler.scheduleAt(
        fireTime,
        id: leftoverNotificationId,
        title: leftoverNotificationTitle,
        body: leftoverNotificationBody(leftovers),
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_leftoverPendingSinceKey, fireTime.toIso8601String());
    } catch (e) {
      debugPrint('FridgeNudgeService: failed to schedule leftover nudge: $e');
    }
  }

  /// Entered ingredients not matched (case-insensitive substring) against
  /// any of [cookedIngredients] — e.g. entered "zucchini" is considered
  /// used if any cooked-ingredient string contains "zucchini" (cooked
  /// strings carry amounts/prep notes, e.g. "300g Zucchini (diced)").
  static List<String> _leftoverIngredients(List<String> entered, List<String> cookedIngredients) {
    final cookedLower = cookedIngredients.map((e) => e.toLowerCase()).toList(growable: false);
    final leftovers = <String>[];
    for (final raw in entered) {
      final e = raw.trim();
      if (e.isEmpty) continue;
      final lower = e.toLowerCase();
      final usedInRecipe = cookedLower.any((c) => c.contains(lower));
      if (!usedInRecipe) leftovers.add(e);
    }
    return leftovers;
  }

  /// Call once a genuine (non-re-cook) Fridge Clearer cook completes —
  /// cancels any still-pending case-1 AND case-2 nudge. Called before
  /// [onFridgeClearerCookCompleted] so a brand-new case-2 nudge scheduled
  /// by that call isn't immediately cancelled by this one.
  Future<void> onRelevantCookCompleted() async {
    if (await hasPendingNudge()) {
      try {
        await _scheduler.cancel(notificationId);
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_pendingSinceKey);
      } catch (e) {
        debugPrint('FridgeNudgeService: failed to cancel nudge: $e');
      }
    }
    if (await hasPendingLeftoverNudge()) {
      try {
        await _scheduler.cancel(leftoverNotificationId);
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_leftoverPendingSinceKey);
      } catch (e) {
        debugPrint('FridgeNudgeService: failed to cancel leftover nudge: $e');
      }
    }
  }

  Future<bool> hasPendingNudge() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_pendingSinceKey);
  }

  Future<bool> hasPendingLeftoverNudge() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_leftoverPendingSinceKey);
  }
}
