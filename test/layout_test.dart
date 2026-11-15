import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisa_exe/main.dart';
import 'package:paisa_exe/paisa_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Loads Roboto so overflow reports use real glyph metrics instead of the
/// blocky test font.
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

void _mockChannels(WidgetTester tester) {
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    const MethodChannel('com.paisaexe.app/legacy'),
    (call) async => null,
  );
  messenger.setMockMethodCallHandler(
    const MethodChannel('com.paisaexe.app/privacy'),
    (call) async => call.method == 'loadHiddenTransactions' ? '[]' : null,
  );
}

void main() {
  for (final (width, scale) in const [
    (360.0, 1.0),
    (393.0, 1.0),
    (411.0, 1.0),
    (360.0, 1.3),
  ]) {
    testWidgets('no overflow on a ${width.toInt()}dp screen at ${scale}x', (
      tester,
    ) async {
      await tester.runAsync(_loadRoboto);
      tester.view.physicalSize = Size(width * 2.625, 880 * 2.625);
      tester.view.devicePixelRatio = 2.625;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      final overflows = <String>[];
      final original = FlutterError.onError;
      FlutterError.onError = (details) {
        final text = details.toString();
        if (text.contains('overflowed')) overflows.add(text);
      };
      addTearDown(() => FlutterError.onError = original);

      SharedPreferences.setMockInitialValues({});
      _mockChannels(tester);
      final store = await PaisaStore.load();
      await tester.pumpWidget(PaisaApp(store: store));
      await tester.pump(const Duration(milliseconds: 4000));
      await tester.pump(const Duration(milliseconds: 700));

      Future<void> tapIcon(IconData icon) async {
        await tester.tap(find.byIcon(icon).first);
        await tester.pump(const Duration(milliseconds: 700));
        await tester.pump(const Duration(milliseconds: 700));
      }

      await tapIcon(Icons.swap_vert_rounded);
      await tapIcon(Icons.restaurant_menu_rounded);
      await tapIcon(Icons.donut_small_outlined);
      await tapIcon(Icons.insights_rounded);
      await tapIcon(Icons.more_horiz_rounded);

      final moreList = find
          .descendant(
            of: find.byType(SettingsScreen),
            matching: find.byType(Scrollable),
          )
          .first;
      for (var i = 0; i < 4; i++) {
        await tester.drag(moreList, const Offset(0, -900));
        await tester.pump(const Duration(milliseconds: 400));
      }

      if (overflows.isNotEmpty) {
        // ignore: avoid_print
        print(
          'OVERFLOW at ${width.toInt()}dp ${scale}x:\n'
          '${overflows.map(_summarize).join('\n----\n')}',
        );
      }
      expect(overflows, isEmpty);
    });
  }
}

String _summarize(String text) => text
    .split('\n')
    .where(
      (line) =>
          line.contains('overflowed') ||
          line.contains('error-causing') ||
          line.contains('creator:') ||
          line.contains('lib/main.dart'),
    )
    .map((line) => line.trim())
    .join('\n');
