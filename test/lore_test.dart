import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisa_exe/lore.dart';
import 'package:paisa_exe/main.dart';
import 'package:paisa_exe/paisa_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _emptyContext = LoreContext(flags: {}, profile: LoreProfile.empty());

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
  group('LoreState', () {
    test('repairs malformed saved state instead of throwing', () {
      final state = LoreState.fromJson({
        'current': 99,
        'read': [1, 'x', 9, 2],
        'introduced': 'nope',
        'flags': {'contract': 'signed', 'big': 42, 'bad': <String>[]},
        'choices': {'3': 'sign'},
        'scroll': {'2': 120.5, '7': -4, '9': 12, 'x': 3},
      });

      expect(state.current, 3);
      expect(state.read, {1, 2});
      expect(state.introduced, isEmpty);
      expect(state.flags['contract'], 'signed');
      expect(state.flags['big'], '42');
      expect(state.flags.containsKey('bad'), isFalse);
      expect(state.choiceFor(3), 'sign');
      expect(state.scrollFor(2), 120.5);
      expect(state.scrollFor(7), 0);
    });

    test('reading an earlier chapter never skips or rewinds progress', () {
      var state = LoreState.initial().markRead(1);
      expect(state.current, 2);

      state = state.markRead(2);
      expect(state.current, 3);

      state = state.markRead(1);
      expect(state.current, 3);
      expect(state.isRead(1), isTrue);
    });

    test('a chapter choice can only be made once', () {
      final options = buildLoreChapter(3, _emptyContext).choice!.options;
      var state = LoreState.initial().markRead(1).markRead(2);
      state = state.choose(3, options.first);
      expect(state.choiceFor(3), 'sign');
      expect(state.flags['contract'], 'signed');

      state = state.choose(3, options.last);
      expect(state.choiceFor(3), 'sign');
      expect(state.flags['contract'], 'signed');
    });

    test('scroll offsets survive a JSON round trip', () {
      final state = LoreState.initial()
          .withScroll(2, 312.4)
          .markRead(1)
          .markRead(2);
      final restored = LoreState.fromJson(state.toJson());
      expect(restored.scrollFor(2), 312.4);
      expect(restored.current, 3);
      expect(restored.read, {1, 2});
    });
  });

  group('Lore chapters', () {
    test('every chapter and both branches contain finished prose', () {
      const signed = LoreContext(
        flags: {'contract': 'signed', 'advance': 'true'},
        profile: LoreProfile.empty(),
      );
      const unsigned = LoreContext(
        flags: {'contract': 'none', 'asked': 'true'},
        profile: LoreProfile.empty(),
      );
      for (var number = 1; number <= loreChapterCount; number++) {
        final chapter = buildLoreChapter(number, _emptyContext);
        expect(chapter.title, isNotEmpty);
        expect(chapter.blocks.length, greaterThan(4));
        final text = chapter.blocks.map((block) => block.text).join(' ');
        expect(text.length, greaterThan(500));
        expect(text.toLowerCase(), isNot(contains('coming soon')));
        expect(text.toLowerCase(), isNot(contains('to be written')));
        expect(text.toLowerCase(), isNot(contains('insert chapter')));
        expect(text, isNot(contains('...')));
      }

      final signedFour = buildLoreChapter(4, signed);
      final unsignedFour = buildLoreChapter(4, unsigned);
      expect(
        signedFour.visibleBlocks(signed).map((b) => b.text).join(' '),
        contains('The money arrives'),
      );
      expect(
        unsignedFour.visibleBlocks(unsigned).map((b) => b.text).join(' '),
        contains('Mira does not sign'),
      );
      expect(
        unsignedFour.visibleBlocks(unsigned).map((b) => b.text).join(' '),
        isNot(contains('The money arrives')),
      );
    });

    test('the empty ledger still gets a complete story', () {
      final profile = LoreProfile.fromTransactions(const []);
      expect(profile.hasHistory, isFalse);
      final context = LoreContext(flags: const {}, profile: profile);
      for (var number = 1; number <= loreChapterCount; number++) {
        expect(buildLoreChapter(number, context).blocks, isNotEmpty);
      }
      final chapterOne = buildLoreChapter(1, context);
      expect(
        chapterOne.visibleBlocks(context).map((b) => b.text).join(' '),
        isNot(contains('late dinner')),
      );
    });

    test('spending patterns only tint the prose', () async {
      final now = DateTime.now();
      final transactions = <Map<String, dynamic>>[
        for (var i = 0; i < 6; i++)
          {
            'type': 'expense',
            'amount': 120,
            'date': '${now.year}-${now.month}-${now.day}',
            'created': DateTime(
              now.year,
              now.month,
              now.day,
              2,
            ).toIso8601String(),
            'category': 'Food & snacks',
          },
      ];
      final profile = LoreProfile.fromTransactions(transactions, now: now);
      expect(profile.lateNights, isTrue);
      expect(profile.foodHeavy, isTrue);
      final context = LoreContext(flags: const {}, profile: profile);
      final chapter = buildLoreChapter(1, context);
      expect(
        chapter.visibleBlocks(context).map((b) => b.text).join(' '),
        contains('late dinner'),
      );
    });

    test('all three endings resolve chapter six', () {
      for (final ending in const ['return', 'keeper', 'burn']) {
        final context = LoreContext(
          flags: {'ending': ending},
          profile: LoreProfile.empty(),
        );
        final chapter = buildLoreChapter(6, context);
        expect(chapter.endingChosen, isTrue);
        expect(chapter.choice, isNull);
        final text = chapter
            .visibleBlocks(context)
            .map((b) => b.text)
            .join(' ');
        expect(text.length, greaterThan(700));
        expect(text, contains('rain thins to nothing'));
      }
    });
  });

  group('Lore persistence', () {
    testWidgets('story state survives a store reload and demos are cleared', (
      tester,
    ) async {
      _mockChannels(tester);
      SharedPreferences.setMockInitialValues({});
      final store = await PaisaStore.load();
      await store.addTransaction({
        'date': '2026-10-01',
        'type': 'expense',
        'amount': 99,
        'description': 'Real lunch',
        'category': 'Food & snacks',
      });
      await store.addTransaction({
        'id': 'legacy-demo',
        'date': '2026-10-01',
        'type': 'expense',
        'amount': 12,
        'description': 'DEMO · Old sample',
        'category': 'Food & snacks',
        'demo': true,
      });
      await store.saveLoreState(
        LoreState.initial()
            .markRead(1)
            .markRead(2)
            .markRead(3)
            .choose(3, buildLoreChapter(3, _emptyContext).choice!.options.first)
            .markRead(4)
            .toJson(),
      );

      final reloaded = await PaisaStore.load();
      final state = LoreState.fromJson(reloaded.loreState);
      expect(state.current, 5);
      expect(state.choiceFor(3), 'sign');
      expect(state.flags['contract'], 'signed');
      expect(reloaded.transactions.where((t) => t['demo'] == true), isEmpty);
      expect(
        reloaded.transactions.where((t) => t['description'] == 'Real lunch'),
        hasLength(1),
      );
    });
  });

  group('Lore screen', () {
    testWidgets('opens from More, advances a chapter, and keeps its record', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);

      SharedPreferences.setMockInitialValues({});
      _mockChannels(tester);
      final store = await PaisaStore.load();
      await tester.pumpWidget(PaisaApp(store: store));
      await tester.pump(const Duration(milliseconds: 2600));
      await tester.pump(const Duration(milliseconds: 700));

      await tester.tap(find.byIcon(Icons.more_horiz_rounded).first);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));

      final moreList = find
          .descendant(
            of: find.byType(SettingsScreen),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.text('Enter the story'),
        200,
        scrollable: moreList,
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Enter the story'));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 800));

      expect(find.text('The Warm Coin'), findsOneWidget);
      expect(find.text('CHAPTER I'), findsOneWidget);

      // Tapping the prose reveals the opening line immediately.
      await tester.tap(find.byType(ListView).last);
      await tester.pump();
      expect(
        find.textContaining('The coin is warm when the woman'),
        findsOneWidget,
      );

      await tester.tap(find.text('Continue'));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.text('The Passbook'), findsOneWidget);
      final saved = LoreState.fromJson(store.loreState);
      expect(saved.current, 2);
      expect(saved.isRead(1), isTrue);

      await tester.tap(find.byIcon(Icons.menu_book_rounded).first);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('THE ARCHIVE'), findsOneWidget);
      expect(find.text('The Warm Coin'), findsOneWidget);

      // Tear the route down so the short typewriter timer is cancelled before
      // the test ends.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('reduced motion shows the complete opening line at once', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360 * 2.625, 880 * 2.625);
      tester.view.devicePixelRatio = 2.625;
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      SharedPreferences.setMockInitialValues({});
      _mockChannels(tester);
      final store = await PaisaStore.load();
      await store.saveSettings(reduceAnimations: true);
      await tester.pumpWidget(PaisaApp(store: store));
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.byIcon(Icons.more_horiz_rounded).first);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Enter the story'));
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.textContaining('The coin is warm when the woman'),
        findsOneWidget,
      );
      expect(find.text('The Warm Coin'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });
}
