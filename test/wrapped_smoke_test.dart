import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisa_exe/main.dart';
import 'package:paisa_exe/paisa_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void _mockChannels(WidgetTester tester) {
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
          return false;
        case 'loadHiddenTransactions':
          return '[]';
        case 'saveHiddenTransactions':
          return null;
        default:
          return null;
      }
    },
  );
}

Future<void> _loadRoboto() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) return;
  final dir = Directory('$root/bin/cache/artifacts/material_fonts');
  if (!dir.existsSync()) return;
  for (final name in const [
    'roboto-regular.ttf',
    'roboto-medium.ttf',
    'roboto-bold.ttf',
    'roboto-black.ttf',
  ]) {
    final file = File('${dir.path}/$name');
    if (!file.existsSync()) continue;
    final loader = FontLoader('Roboto')
      ..addFont(file.readAsBytes().then((b) => ByteData.view(b.buffer)));
    await loader.load();
  }
}

void main() {
  testWidgets('Monthly Wrapped opens from Insights without errors', (
    tester,
  ) async {
    await tester.runAsync(_loadRoboto);
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final errors = <String>[];
    final original = FlutterError.onError;
    FlutterError.onError = (details) {
      final text = details.toString();
      // The ListTile-in-card hint is a debug-only style assertion.
      if (!text.contains('ListTile background color')) errors.add(text);
      original?.call(details);
    };
    addTearDown(() => FlutterError.onError = original);

    SharedPreferences.setMockInitialValues({});
    _mockChannels(tester);
    final store = await PaisaStore.load();
    await store.addTransaction({
      'date':
          '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-12',
      'type': 'expense',
      'amount': 420.0,
      'description': 'Canteen week',
      'category': 'Food & snacks',
    });
    store.transactions.add({
      'id': 'hidden-1',
      'date':
          '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-05',
      'amount': 480.0,
      'type': 'expense',
      'description': 'Hidden test expense',
      'category': 'Food & snacks',
      'hidden': true,
    });
    await tester.pumpWidget(PaisaApp(store: store));
    await tester.pump(const Duration(milliseconds: 4000));
    await tester.pump(const Duration(milliseconds: 700));

    await tester.tap(find.byIcon(Icons.insights_rounded).first);
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(milliseconds: 700));

    final insightsList = find
        .descendant(
          of: find.byType(InsightsScreen),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.text('Monthly Wrapped'),
      250,
      scrollable: insightsList,
    );
    await tester.pump(const Duration(milliseconds: 600));

    final entry = find.text('Monthly Wrapped');
    expect(entry, findsOneWidget);
    await tester.tap(entry);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 1700));

    final chart = find.byType(CustomPaint).last;
    await tester.tapAt(tester.getCenter(chart) + const Offset(0, -70));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }

    if (errors.isNotEmpty) {
      // ignore: avoid_print
      print('WRAPPED ERRORS:\n${errors.join('\n---\n')}');
    }
    expect(find.text('THE BREAKDOWN'), findsOneWidget);
    expect(errors, isEmpty);
  });
}
