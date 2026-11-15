import 'package:flutter_test/flutter_test.dart';
import 'package:paisa_exe/paisa_store.dart';

void main() {
  group('PaisaStore.buildPriceMemoryEntries', () {
    test('groups matching item and place and sorts newest price first', () {
      final entries = PaisaStore.buildPriceMemoryEntries([
        {
          'id': 'old',
          'type': 'expense',
          'amount': 60,
          'date': '2026-10-10',
          'category': 'Food & snacks',
          'priceMemoryItem': 'Cold Coffee',
          'priceMemoryPlace': 'KC Foods',
        },
        {
          'id': 'new',
          'type': 'expense',
          'amount': 70,
          'date': '2026-10-20',
          'category': 'Food & snacks',
          'priceMemoryItem': 'cold   coffee',
          'priceMemoryPlace': 'kc foods',
        },
      ]);

      expect(entries, hasLength(1));
      expect(entries.single.item, 'Cold Coffee');
      expect(entries.single.place, 'KC Foods');
      expect(entries.single.latest['id'], 'new');
      expect(entries.single.previous?['id'], 'old');
    });

    test('uses selected campus food metadata and filters non-purchases', () {
      final entries = PaisaStore.buildPriceMemoryEntries([
        {
          'id': 'food',
          'type': 'expense',
          'amount': 85,
          'date': '2026-10-21',
          'foodItem': 'Paneer paratha',
          'foodShop': 'KC Foods',
        },
        {
          'id': 'demo',
          'type': 'expense',
          'amount': 85,
          'date': '2026-10-21',
          'foodItem': 'Paneer paratha',
          'foodShop': 'KC Foods',
          'demo': true,
        },
        {
          'id': 'ignored',
          'type': 'expense',
          'amount': 85,
          'date': '2026-10-21',
          'priceMemoryItem': 'Paneer paratha',
          'priceMemoryIgnored': true,
        },
        {
          'id': 'income',
          'type': 'income',
          'amount': 500,
          'date': '2026-10-21',
          'priceMemoryItem': 'Pocket money',
        },
        {
          'id': 'zero',
          'type': 'expense',
          'amount': 0,
          'date': '2026-10-21',
          'priceMemoryItem': 'Free sample',
        },
        {
          'id': 'unlabeled',
          'type': 'expense',
          'amount': 12,
          'date': '2026-10-21',
          'description': 'Unspecified snack',
        },
      ]);

      expect(entries, hasLength(1));
      expect(entries.single.item, 'Paneer paratha');
      expect(entries.single.place, 'KC Foods');
    });

    test('keeps the same item at different places as separate records', () {
      final entries = PaisaStore.buildPriceMemoryEntries([
        {
          'type': 'expense',
          'amount': 45,
          'date': '2026-10-21',
          'priceMemoryItem': 'Laundry load',
          'priceMemoryPlace': 'North Gate',
        },
        {
          'type': 'expense',
          'amount': 50,
          'date': '2026-10-20',
          'priceMemoryItem': 'Laundry load',
          'priceMemoryPlace': 'South Gate',
        },
      ]);

      expect(entries, hasLength(2));
      expect(entries.map((entry) => entry.place), ['North Gate', 'South Gate']);
    });

    test('does not learn from transactions marked hidden', () {
      final entries = PaisaStore.buildPriceMemoryEntries([
        {
          'type': 'expense',
          'amount': 85,
          'date': '2026-10-21',
          'foodItem': 'Paneer paratha',
          'foodShop': 'KC Foods',
          'hidden': true,
        },
      ]);

      expect(entries, isEmpty);
    });
  });
}
