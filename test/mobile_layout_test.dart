import 'dart:io';

import 'package:blobnot/services/settings_store.dart';
import 'package:blobnot/state/external_files_controller.dart';
import 'package:blobnot/state/vault_controller.dart';
import 'package:blobnot/ui/editor_pane.dart';
import 'package:blobnot/ui/home_page.dart';
import 'package:blobnot/ui/mobile/mobile_home.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// On a phone-width viewport HomePage is a Keep-style card list: notes open
/// on their own page with a back arrow, "+" writes a quick note, and the
/// drawer holds the other views and the project filters.
void main() {
  late Directory dir;
  late VaultController controller;

  Future<void> pumpPhone(WidgetTester tester) async {
    await tester.runAsync(() async {
      dir = await Directory.systemTemp.createTemp('blobnot_mobile');
      AppSettings.overrideFile = File('${dir.path}/app_settings.json');
      File('${dir.path}/Alpha.md').writeAsStringSync('# Alpha\nbody text');
      File('${dir.path}/Beta.md').writeAsStringSync('# Beta\nother text');
      Directory('${dir.path}/Work').createSync();
      File('${dir.path}/Work/Gamma.md').writeAsStringSync('# Gamma\nwork');
      controller = VaultController();
      await controller.openVault(dir.path);
    });

    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: controller),
          ChangeNotifierProvider(create: (_) => ExternalFilesController()),
        ],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await tester.pump();
  }

  Future<void> cleanUp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => controller.reload());
    controller.dispose();
    AppSettings.overrideFile = null;
    await tester.runAsync(() async {
      for (var i = 0; i < 10; i++) {
        try {
          await dir.delete(recursive: true);
          return;
        } on FileSystemException {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }
    });
  }

  testWidgets(
    'home shows note cards; a note opens with a back arrow',
    (tester) async {
      await pumpPhone(tester);

      expect(find.byType(MobileHome), findsOneWidget);
      expect(find.byType(EditorPane), findsNothing);
      expect(find.byKey(const Key('note-card-Alpha')), findsOneWidget);
      expect(find.byKey(const Key('note-card-Gamma')), findsOneWidget);
      // The heading is the card title, not repeated in the preview.
      expect(find.text('body text'), findsOneWidget);

      await tester.tap(find.byKey(const Key('note-card-Beta')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('mobile-note-screen')), findsOneWidget);
      expect(controller.current?.title, 'Beta');
      expect(find.widgetWithText(AppBar, 'Beta'), findsOneWidget);

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('mobile-note-screen')), findsNothing);
      expect(find.byType(MobileHome), findsOneWidget);

      await cleanUp(tester);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  testWidgets('search narrows the cards', (tester) async {
    await pumpPhone(tester);

    await tester.enterText(find.byKey(const Key('mobile-search')), 'other');
    await tester.pump();

    expect(find.byKey(const Key('note-card-Beta')), findsOneWidget);
    expect(find.byKey(const Key('note-card-Alpha')), findsNothing);

    await cleanUp(tester);
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets(
    '+ writes a quick note titled from its first line',
    (tester) async {
      await pumpPhone(tester);

      await tester.tap(find.byKey(const Key('mobile-fab')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('quick-body')),
        'Buy cable\nfor the office',
      );
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('quick-done')));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('quick-note-screen')), findsNothing);
      final file = File('${dir.path}/Buy cable.md');
      expect(file.existsSync(), isTrue);
      expect(
        file.readAsStringSync(),
        '# Buy cable\n\nBuy cable\nfor the office\n',
      );
      expect(find.byKey(const Key('note-card-Buy cable')), findsOneWidget);

      await cleanUp(tester);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  testWidgets(
    'an empty quick note is discarded',
    (tester) async {
      await pumpPhone(tester);
      final before = controller.notes.length;

      await tester.tap(find.byKey(const Key('mobile-fab')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      expect(controller.notes.length, before);

      await cleanUp(tester);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  testWidgets(
    'a drawer project filters the cards',
    (tester) async {
      await pumpPhone(tester);

      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('drawer-hot')), findsOneWidget);
      expect(find.byKey(const Key('drawer-dashboard')), findsOneWidget);
      await tester.tap(find.byKey(const Key('drawer-project-Work')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('note-card-Gamma')), findsOneWidget);
      expect(find.byKey(const Key('note-card-Alpha')), findsNothing);

      // The chip clears the filter.
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('mobile-filter-chip')),
          matching: find.byTooltip('Clear filter'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('note-card-Alpha')), findsOneWidget);

      await cleanUp(tester);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  testWidgets(
    'long-press offers pin, and pinned cards come first',
    (tester) async {
      await pumpPhone(tester);

      await tester.longPress(find.byKey(const Key('note-card-Beta')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pin'));
      await tester.pumpAndSettle();

      expect(controller.isPinned('Beta'), isTrue);
      expect(find.text('PINNED'), findsOneWidget);
      expect(find.text('OTHERS'), findsOneWidget);

      await cleanUp(tester);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
