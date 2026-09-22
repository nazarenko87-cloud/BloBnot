import 'package:blobnot/services/saf_vault_storage.dart';
import 'package:blobnot/services/vault_backend.dart';
import 'package:blobnot/utils/hot_tasks.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Android backend talks to the native side over the `bloknot/saf`
/// channel. These tests stand in for that native side, so the Dart half of
/// the Android path is covered on the desktop test runner.
///
/// Writes answer `null`: the native bridge must never hand the channel codec
/// a Kotlin `Unit` or a DocumentFile — doing so crashed the app on every save.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('bloknot/saf');
  const tree = 'content://com.example.documents/tree/vault';
  late List<MethodCall> calls;
  late Map<String, String> files;

  setUp(() {
    calls = [];
    files = {};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          final args = (call.arguments as Map?)?.cast<String, Object?>() ?? {};
          final path = args['path'] as String?;
          switch (call.method) {
            case 'readFile':
              return files[path] ?? '';
            case 'writeFile':
              files[path!] = args['content'] as String;
              return null;
            case 'hasPermission':
              return true;
            case 'listMarkdown' || 'listFolder':
              return <Object?>[];
            case 'listDirs':
              return <Object?>[];
            default:
              return null;
          }
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('a content:// id selects the SAF backend', () {
    expect(isSafId(tree), isTrue);
    expect(openBackend(tree), isA<SafVaultStorage>());
    expect(openBackend(r'C:\vault'), isNot(isA<SafVaultStorage>()));
  });

  test('hot tasks round-trip through the channel', () async {
    final storage = SafVaultStorage(tree);
    final task = HotTask(
      id: 0,
      text: 'Call Oleg',
      created: DateTime(2026, 9, 22, 9, 15),
    );
    await storage.writeText(kHotTasksPath, serializeHotTasks([task]));

    final write = calls.firstWhere((c) => c.method == 'writeFile');
    expect(write.arguments['tree'], tree);
    expect(write.arguments['path'], '_hot/tasks.md');

    final back = parseHotTasks(
      await storage.readText(kHotTasksPath),
      now: DateTime(2026, 9, 22, 10),
    );
    expect(back.single.text, 'Call Oleg');
    expect(back.single.created, task.created);
  });

  test('a missing file reads as empty rather than throwing', () async {
    final storage = SafVaultStorage(tree);
    expect(await storage.readText(kHotArchivePath), '');
  });

  test('a failing native call surfaces as an exception', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          throw PlatformException(code: 'saf_error', message: 'no permission');
        });
    final storage = SafVaultStorage(tree);
    await expectLater(
      storage.writeText(kHotTasksPath, 'x'),
      throwsA(isA<PlatformException>()),
    );
  });
}
