import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:optimeal/services/ledger_sync_coordinator.dart';

class FakeConnectivityMonitor implements ConnectivityMonitor {
  final _controller = StreamController<bool>.broadcast();
  bool initialOnline = true;
  int checkIsOnlineCalls = 0;

  @override
  Stream<bool> get onStatusChanged => _controller.stream;

  @override
  Future<bool> checkIsOnline() async {
    checkIsOnlineCalls++;
    return initialOnline;
  }

  void emit(bool isOnline) => _controller.add(isOnline);

  Future<void> close() => _controller.close();
}

void main() {
  group('LedgerSyncCoordinator trigger logic', () {
    test('start() with an already-online device flushes immediately', () async {
      final monitor = FakeConnectivityMonitor()..initialOnline = true;
      var flushCalls = 0;
      final coordinator = LedgerSyncCoordinator(
        connectivityMonitor: monitor,
        flush: () async => flushCalls++,
      );

      await coordinator.start();
      // flush() is fire-and-forget (unawaited) inside start(); pump the
      // microtask queue so it has a chance to run before asserting.
      await Future<void>.delayed(Duration.zero);

      expect(flushCalls, 1);
      await coordinator.dispose();
      await monitor.close();
    });

    test('start() with an already-offline device does not flush', () async {
      final monitor = FakeConnectivityMonitor()..initialOnline = false;
      var flushCalls = 0;
      final coordinator = LedgerSyncCoordinator(
        connectivityMonitor: monitor,
        flush: () async => flushCalls++,
      );

      await coordinator.start();
      await Future<void>.delayed(Duration.zero);

      expect(flushCalls, 0);
      await coordinator.dispose();
      await monitor.close();
    });

    test('a genuine offline -> online transition flushes exactly once', () async {
      final monitor = FakeConnectivityMonitor()..initialOnline = false;
      var flushCalls = 0;
      final coordinator = LedgerSyncCoordinator(
        connectivityMonitor: monitor,
        flush: () async => flushCalls++,
      );

      await coordinator.start();
      await Future<void>.delayed(Duration.zero);
      expect(flushCalls, 0, reason: 'started offline, no flush yet');

      monitor.emit(true);
      await Future<void>.delayed(Duration.zero);

      expect(flushCalls, 1);
      await coordinator.dispose();
      await monitor.close();
    });

    test('going offline never triggers a flush', () async {
      final monitor = FakeConnectivityMonitor()..initialOnline = true;
      var flushCalls = 0;
      final coordinator = LedgerSyncCoordinator(
        connectivityMonitor: monitor,
        flush: () async => flushCalls++,
      );

      await coordinator.start();
      await Future<void>.delayed(Duration.zero);
      expect(flushCalls, 1, reason: 'initial online flush');

      monitor.emit(false);
      await Future<void>.delayed(Duration.zero);

      expect(flushCalls, 1, reason: 'going offline must not add a flush');
      await coordinator.dispose();
      await monitor.close();
    });

    test('repeated "still online" events do not re-flush', () async {
      final monitor = FakeConnectivityMonitor()..initialOnline = true;
      var flushCalls = 0;
      final coordinator = LedgerSyncCoordinator(
        connectivityMonitor: monitor,
        flush: () async => flushCalls++,
      );

      await coordinator.start();
      await Future<void>.delayed(Duration.zero);
      expect(flushCalls, 1);

      monitor.emit(true);
      monitor.emit(true);
      await Future<void>.delayed(Duration.zero);

      expect(flushCalls, 1, reason: 'still-online repeats are not a reconnect');
      await coordinator.dispose();
      await monitor.close();
    });

    test('onAppResume() always flushes, regardless of last-known connectivity', () async {
      final monitor = FakeConnectivityMonitor()..initialOnline = false;
      var flushCalls = 0;
      final coordinator = LedgerSyncCoordinator(
        connectivityMonitor: monitor,
        flush: () async => flushCalls++,
      );

      await coordinator.start();
      await Future<void>.delayed(Duration.zero);
      expect(flushCalls, 0);

      coordinator.onAppResume();
      await Future<void>.delayed(Duration.zero);

      expect(flushCalls, 1);
      await coordinator.dispose();
      await monitor.close();
    });

    test('dispose() stops further connectivity-driven flushes', () async {
      final monitor = FakeConnectivityMonitor()..initialOnline = false;
      var flushCalls = 0;
      final coordinator = LedgerSyncCoordinator(
        connectivityMonitor: monitor,
        flush: () async => flushCalls++,
      );

      await coordinator.start();
      await coordinator.dispose();

      monitor.emit(true);
      await Future<void>.delayed(Duration.zero);

      expect(flushCalls, 0);
      await monitor.close();
    });
  });
}
