import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisa_exe/main.dart';
import 'package:paisa_exe/paisa_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('hiding and revealing a transaction works with the PIN', (
    tester,
  ) async {
    var hasPin = false;
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.paisaexe.app/legacy'),
      (call) async => null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.paisaexe.app/privacy'),
      (call) async {
        switch (call.method) {
          case 'hasPrivacyPin':
            return hasPin;
          case 'loadHiddenTransactions':
            return '[]';
          case 'saveHiddenTransactions':
            return null;
          case 'setPrivacyPin':
            hasPin = true;
            return null;
          case 'verifyPrivacyPin':
            return {
              'success':
                  call.arguments is Map &&
                  (call.arguments as Map)['pin'] == '1234',
              'retryAfterSeconds': 0,
              'attemptsRemaining': 3,
            };
          default:
            return null;
        }
      },
    );

    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({});
    final store = await PaisaStore.load();
    final now = DateTime.now();
    await store.addTransaction({
      'date':
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
      'type': 'expense',
      'amount': 140.0,
      'description': 'Canteen lunch',
      'category': 'Food & snacks',
    });
    await tester.pumpWidget(PaisaApp(store: store));
    await tester.pump(const Duration(milliseconds: 4000));
    await tester.pump(const Duration(milliseconds: 700));

    await tester.tap(find.byIcon(Icons.swap_vert_rounded).first);
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(milliseconds: 700));

    final openMenu = find.byType(PopupMenuButton<String>);
    expect(openMenu, findsWidgets);
    await tester.tap(openMenu.first);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
    await tester.tap(find.text('Hide transaction'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }

    // First hide needs a PIN to be created.
    expect(find.text('Create a hidden transaction PIN'), findsOneWidget);
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(fields.evaluate().length - 2), '1234');
    await tester.enterText(fields.at(fields.evaluate().length - 1), '1234');
    await tester.tap(find.text('Save PIN'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(tester.takeException(), isNull);
    expect(store.hiddenTransactions, isNotEmpty);
    final hiddenId = store.hiddenTransactions.first['id'];

    // Now reveal it again: filter to Hidden so the row is on screen.
    await tester.tap(find.text('Hidden'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    await tester.tap(find.byType(PopupMenuButton<String>).first);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
    await tester.tap(find.text('Show transaction · PIN'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }

    expect(find.text('Show this transaction?'), findsOneWidget);
    final pinFields = find.byType(TextField);
    await tester.enterText(pinFields.last, '1234');
    await tester.tap(find.text('Unlock'));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    expect(tester.takeException(), isNull);
    expect(
      store.transactions.firstWhere(
        (t) => '${t['id']}' == '$hiddenId',
      )['hidden'],
      isNot(true),
    );
  });
}
