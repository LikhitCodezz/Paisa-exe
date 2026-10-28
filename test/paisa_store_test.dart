import 'package:flutter_test/flutter_test.dart';
import 'package:paisa_exe/paisa_store.dart';

void main() {
  group('PaisaStore.allowanceCycle', () {
    test('monthly anchor on the 1st is not shifted by a transaction date', () {
      final schedule = {
        'enabled': true,
        'frequency': 'monthly',
        'nextDate': '2026-04-17',
        'anchorDay': 1,
      };

      final before = PaisaStore.allowanceCycle(DateTime(2026, 4, 17), schedule);
      final payday = PaisaStore.allowanceCycle(DateTime(2026, 5, 1), schedule);
      final after = PaisaStore.allowanceCycle(DateTime(2026, 5, 2), schedule);

      expect(before.isPayday, isFalse);
      expect(before.daysUntil, 14);
      expect(before.payday, DateTime(2026, 5, 1));
      expect(payday.isPayday, isTrue);
      expect(payday.progress, 0);
      expect(after.isPayday, isFalse);
      expect(after.daysUntil, 30);
      expect(after.payday, DateTime(2026, 6, 1));
    });

    test('monthly anchor beyond a short month lands on its last day', () {
      final cycle = PaisaStore.allowanceCycle(DateTime(2027, 2, 27), {
        'enabled': true,
        'frequency': 'monthly',
        'nextDate': '2027-02-17',
        'anchorDay': 31,
      });

      expect(cycle.isPayday, isFalse);
      expect(cycle.daysUntil, 1);
      expect(cycle.payday, DateTime(2027, 2, 28));
      expect(cycle.progress, 1);
    });

    test('weekly and fortnightly schedules remain anchored to nextDate', () {
      final weekly = PaisaStore.allowanceCycle(DateTime(2026, 4, 20), {
        'enabled': true,
        'frequency': 'weekly',
        'nextDate': '2026-04-17',
      });
      final fortnightly = PaisaStore.allowanceCycle(DateTime(2026, 4, 30), {
        'enabled': true,
        'frequency': 'fortnightly',
        'nextDate': '2026-04-17',
      });

      expect(weekly.payday, DateTime(2026, 4, 24));
      expect(weekly.daysUntil, 4);
      expect(fortnightly.payday, DateTime(2026, 5, 1));
      expect(fortnightly.daysUntil, 1);
      expect(fortnightly.progress, closeTo(12 / 13, 1e-12));
    });
  });
}
