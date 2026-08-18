import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import 'package:optimeal/services/ledger_service.dart';
import 'package:optimeal/services/pending_ledger_write_service.dart';

/// Abstraction over `connectivity_plus` so [LedgerSyncCoordinator]'s
/// trigger logic (when to flush) can be unit-tested without a real
/// platform channel — same pattern as `FridgeNudgeScheduler`.
abstract class ConnectivityMonitor {
  /// Emits true when online, false when offline, on every connectivity
  /// change. Does not need to emit an initial value — [checkIsOnline]
  /// covers the startup read.
  Stream<bool> get onStatusChanged;

  Future<bool> checkIsOnline();
}

class ConnectivityPlusMonitor implements ConnectivityMonitor {
  final _connectivity = Connectivity();

  bool _resultIsOnline(List<ConnectivityResult> results) =>
      results.any((r) => r != ConnectivityResult.none);

  @override
  Stream<bool> get onStatusChanged =>
      _connectivity.onConnectivityChanged.map(_resultIsOnline);

  @override
  Future<bool> checkIsOnline() async =>
      _resultIsOnline(await _connectivity.checkConnectivity());
}

/// Flushes writes queued in [PendingLedgerWriteService] at the two moments
/// they're actually likely to succeed — reconnecting after being offline,
/// and resuming the app — since nothing previously ever retried them at
/// all (see the device-test-round I2 investigation: `retryPendingWrite`
/// existed but had zero callers).
///
/// [flush] is injected so this class's actual job — the connectivity/resume
/// TRIGGER logic — can be unit-tested independently of the real Supabase
/// retry mechanics, which need a live client and aren't unit-testable.
/// See test/services/ledger_sync_coordinator_test.dart.
class LedgerSyncCoordinator {
  LedgerSyncCoordinator({
    ConnectivityMonitor? connectivityMonitor,
    Future<void> Function()? flush,
  })  : _connectivity = connectivityMonitor ?? ConnectivityPlusMonitor(),
        _flush = flush ?? _defaultFlush;

  static final LedgerSyncCoordinator instance = LedgerSyncCoordinator();

  final ConnectivityMonitor _connectivity;
  final Future<void> Function() _flush;

  StreamSubscription<bool>? _sub;

  /// Null until the first read. Deliberately tri-state (unknown / offline /
  /// online) rather than defaulting to false — defaulting to "was offline"
  /// would make the very first connectivity event after [start] always
  /// look like a reconnect and flush redundantly (harmless, but noisy).
  bool? _lastKnownOnline;

  bool _started = false;

  static Future<void> _defaultFlush() async {
    final pendingWriteService = PendingLedgerWriteService();
    final ledgerService = LedgerService();
    final pending = await pendingWriteService.loadAll();
    for (final write in pending) {
      try {
        await ledgerService.retryPendingWrite(write);
      } catch (e) {
        debugPrint(
            'LedgerSyncCoordinator: retry failed for ${write.idempotencyKey}: $e');
      }
    }
  }

  /// Call once at app startup. Begins listening for connectivity changes
  /// and, if already online, attempts an immediate flush — covers a write
  /// queued in a previous session that's now being reopened already
  /// connected, which a pure connectivity-change listener would never see.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    try {
      final isOnline = await _connectivity.checkIsOnline();
      _lastKnownOnline = isOnline;
      if (isOnline) unawaited(_flush());
    } catch (e) {
      debugPrint(
          'LedgerSyncCoordinator.start: initial connectivity check failed: $e');
    }
    _sub = _connectivity.onStatusChanged.listen(_onConnectivityEvent);
  }

  void _onConnectivityEvent(bool isOnline) {
    final wasOnline = _lastKnownOnline;
    _lastKnownOnline = isOnline;
    // Only flush on a genuine offline -> online transition, not on every
    // "still online" event some platforms re-emit, and never on going
    // offline.
    if (isOnline && wasOnline == false) {
      unawaited(_flush());
    }
  }

  /// Call from a `WidgetsBindingObserver.didChangeAppLifecycleState` on
  /// `AppLifecycleState.resumed`. Always attempts a flush regardless of
  /// last-known connectivity — a resumed app is the cheapest, most
  /// reliable moment to retry: if still offline the attempt just fails
  /// harmlessly and the write stays queued for the next trigger.
  void onAppResume() {
    unawaited(_flush());
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
    _started = false;
  }
}
