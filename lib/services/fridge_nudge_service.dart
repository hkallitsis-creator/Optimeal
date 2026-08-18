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

/// Schedules and cancels the single "unused Fridge Clearer ingredients"
/// nudge notification (docs/decisions_2026-08-17.md item 5).
///
/// Trigger: a successful Fridge Clearer recipe generation — the earliest
/// durable, already-existing event in the code for "the user committed to
/// some fridge ingredients." FridgeClearerScreen itself never persists the
/// raw ingredient selection (it's ephemeral UI state), so there is nothing
/// earlier to hook. See CLAUDE.md Package D0 report for the full reasoning
/// and the alternatives considered.
///
/// Cancellation: a genuine (non-re-cook) completed cook on
/// CookModeSurface.fridgeClearer, called from
/// OnePanCookingRoadmapScreen._logCookSessionCompletion.
///
/// Only one nudge is ever pending at a time — scheduling a new one (from a
/// fresh generation) replaces any still-pending nudge under the same
/// notification id, rather than stacking multiple. This is a deliberate
/// simplification: flag for Harris to veto if separate per-generation
/// nudges are wanted instead.
class FridgeNudgeService {
  FridgeNudgeService({FridgeNudgeScheduler? scheduler})
      : _scheduler = scheduler ?? FlutterLocalNotificationsFridgeNudgeScheduler();

  static final FridgeNudgeService instance = FridgeNudgeService();

  final FridgeNudgeScheduler _scheduler;

  static const int notificationId = 9001;
  static const String _pendingSinceKey = 'fridge_nudge_pending_since_v1';
  static const Duration nudgeDelay = Duration(days: 2);

  /// One short, warm-voiced copy line — kept here so it's reviewable in one
  /// place. Under 15 words.
  static const String notificationTitle = "Still got those fridge ingredients?";
  static const String notificationBody =
      "Let's use them before they turn — Fridge Clearer or a quick AI recipe.";

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

  /// Call once a genuine (non-re-cook) Fridge Clearer cook completes.
  Future<void> onRelevantCookCompleted() async {
    if (!await hasPendingNudge()) return;
    try {
      await _scheduler.cancel(notificationId);
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_pendingSinceKey);
    } catch (e) {
      debugPrint('FridgeNudgeService: failed to cancel nudge: $e');
    }
  }

  Future<bool> hasPendingNudge() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_pendingSinceKey);
  }
}
