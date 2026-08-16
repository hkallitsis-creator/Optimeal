import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:optimeal/services/pending_ledger_write_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('PendingLedgerWriteService', () {
    test('add then loadAll returns the written record', () async {
      final service = PendingLedgerWriteService();
      final write = PendingLedgerWrite(
        idempotencyKey: 'abc123',
        payload: const {'source': 'cook_mode', 'ingredients_rescued': 3},
        queuedAt: DateTime.utc(2026, 8, 16, 12, 0, 0),
      );

      await service.add(write);
      final all = await service.loadAll();

      expect(all, hasLength(1));
      expect(all.first.idempotencyKey, 'abc123');
      expect(all.first.payload, {'source': 'cook_mode', 'ingredients_rescued': 3});
      expect(all.first.queuedAt, DateTime.utc(2026, 8, 16, 12, 0, 0));
    });

    test('loadAll returns an empty list when nothing has been written', () async {
      final service = PendingLedgerWriteService();
      final all = await service.loadAll();
      expect(all, isEmpty);
    });

    test('clear removes only the record with the matching idempotency key', () async {
      final service = PendingLedgerWriteService();
      await service.add(PendingLedgerWrite(
        idempotencyKey: 'key-1',
        payload: const {'source': 'cook_mode'},
        queuedAt: DateTime.utc(2026, 8, 16),
      ));
      await service.add(PendingLedgerWrite(
        idempotencyKey: 'key-2',
        payload: const {'source': 'fridge_clearer'},
        queuedAt: DateTime.utc(2026, 8, 16),
      ));

      await service.clear('key-1');
      final all = await service.loadAll();

      expect(all, hasLength(1));
      expect(all.first.idempotencyKey, 'key-2');
    });

    test('clear on a key that does not exist is a harmless no-op', () async {
      final service = PendingLedgerWriteService();
      await service.add(PendingLedgerWrite(
        idempotencyKey: 'key-1',
        payload: const {'source': 'cook_mode'},
        queuedAt: DateTime.utc(2026, 8, 16),
      ));

      await service.clear('does-not-exist');
      final all = await service.loadAll();

      expect(all, hasLength(1));
      expect(all.first.idempotencyKey, 'key-1');
    });

    test('round-trips a payload containing a list of ingredient strings', () async {
      final service = PendingLedgerWriteService();
      final write = PendingLedgerWrite(
        idempotencyKey: 'key-list',
        payload: const {
          'source': 'cook_mode',
          'ingredients_rescued_list': ['Chicken thigh', 'Cabbage', 'Onion'],
        },
        queuedAt: DateTime.utc(2026, 8, 16),
      );

      await service.add(write);
      final all = await service.loadAll();

      expect(all, hasLength(1));
      expect(all.first.payload['ingredients_rescued_list'], ['Chicken thigh', 'Cabbage', 'Onion']);
    });
  });
}
