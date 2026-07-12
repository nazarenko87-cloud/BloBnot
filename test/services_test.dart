import 'dart:io';

import 'package:blobnot/services/attachment_store.dart';
import 'package:blobnot/services/password_store.dart';
import 'package:blobnot/services/reminder_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('blobnot_svc');
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  group('ReminderStore', () {
    test('round-trips reminders through reminders.json', () async {
      final store = ReminderStore(tmp.path);
      final when = DateTime(2026, 8, 1, 9, 30);
      await store.save({'My note': when});

      final loaded = await ReminderStore(tmp.path).load();
      expect(loaded, {'My note': when});
      expect(File('${tmp.path}/reminders.json').existsSync(), isTrue);
    });

    test('returns empty map for missing or corrupt file', () async {
      expect(await ReminderStore(tmp.path).load(), isEmpty);
      File('${tmp.path}/reminders.json').writeAsStringSync('not json');
      expect(await ReminderStore(tmp.path).load(), isEmpty);
    });
  });

  group('AttachmentStore', () {
    test('copies file into attachments and de-duplicates names', () async {
      final src = File('${tmp.path}/doc.txt')..writeAsStringSync('hello');
      final store = AttachmentStore(tmp.path);

      final first = await store.add(src.path);
      final second = await store.add(src.path);

      expect(first, 'doc.txt');
      expect(second, 'doc (1).txt');
      expect(await store.exists('doc.txt'), isTrue);
      expect(await store.exists('doc (1).txt'), isTrue);

      await store.delete('doc (1).txt');
      expect(await store.exists('doc (1).txt'), isFalse);
    });

    test('referencedIn finds attachment links in note body', () {
      const body = 'Text [📎 a.pdf](attachments/a.pdf) and '
          '[x](attachments/b%20c.png) but not [w](https://e.com/attachments/z).';
      expect(AttachmentStore.referencedIn(body), ['a.pdf', 'b c.png']);
    });
  });

  group('PasswordStore', () {
    test('set → verify → change → clear lifecycle', () async {
      final store = PasswordStore(file: File('${tmp.path}/settings.json'));

      expect(await store.hasPassword(), isFalse);
      expect(await store.verify('anything'), isFalse);

      await store.setPassword('s3cret');
      expect(await store.hasPassword(), isTrue);
      expect(await store.verify('s3cret'), isTrue);
      expect(await store.verify('wrong'), isFalse);

      await store.setPassword('new');
      expect(await store.verify('s3cret'), isFalse);
      expect(await store.verify('new'), isTrue);

      await store.clearPassword();
      expect(await store.hasPassword(), isFalse);
    });

    test('stores salted hash, not the password', () async {
      final f = File('${tmp.path}/settings.json');
      final store = PasswordStore(file: f);
      await store.setPassword('hunter2');
      final raw = f.readAsStringSync();
      expect(raw.contains('hunter2'), isFalse);
      expect(raw, contains('pwSalt'));
      expect(raw, contains('pwHash'));
    });
  });
}
