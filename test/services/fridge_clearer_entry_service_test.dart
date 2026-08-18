import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:optimeal/services/fridge_clearer_entry_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('FridgeClearerEntryService', () {
    test('peekEnteredIngredients returns empty when nothing was ever recorded', () async {
      final service = FridgeClearerEntryService();
      expect(await service.peekEnteredIngredients(), isEmpty);
    });

    test('recordEnteredIngredients then peekEnteredIngredients round-trips the list', () async {
      final service = FridgeClearerEntryService();
      await service.recordEnteredIngredients(['Zucchini', 'Eggs']);
      expect(await service.peekEnteredIngredients(), ['Zucchini', 'Eggs']);
    });

    test('peekEnteredIngredients does not clear the stored value', () async {
      final service = FridgeClearerEntryService();
      await service.recordEnteredIngredients(['Zucchini']);
      await service.peekEnteredIngredients();
      expect(await service.peekEnteredIngredients(), ['Zucchini']);
    });

    test('clear removes the stored value', () async {
      final service = FridgeClearerEntryService();
      await service.recordEnteredIngredients(['Zucchini']);
      await service.clear();
      expect(await service.peekEnteredIngredients(), isEmpty);
    });

    test('a second recordEnteredIngredients replaces the first rather than merging', () async {
      final service = FridgeClearerEntryService();
      await service.recordEnteredIngredients(['Zucchini']);
      await service.recordEnteredIngredients(['Eggs', 'Cheese']);
      expect(await service.peekEnteredIngredients(), ['Eggs', 'Cheese']);
    });
  });
}
