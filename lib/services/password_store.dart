import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// Local launch password: salted SHA-256, stored in `~/.bloknot/settings.json`
/// (app-local — deliberately does NOT travel with the vault).
class PasswordStore {
  PasswordStore({File? file}) : _file = file ?? _defaultFile();

  final File _file;

  static File _defaultFile() {
    final home =
        Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        '.';
    return File(p.join(home, '.bloknot', 'settings.json'));
  }

  Future<Map<String, dynamic>> _read() async {
    try {
      if (!await _file.exists()) return {};
      return jsonDecode(await _file.readAsString()) as Map<String, dynamic>;
    } on FormatException {
      return {};
    } on IOException {
      return {};
    }
  }

  Future<void> _write(Map<String, dynamic> data) async {
    await _file.parent.create(recursive: true);
    await _file.writeAsString(jsonEncode(data));
  }

  static String hashOf(String password, String salt) =>
      sha256.convert(utf8.encode('$salt$password')).toString();

  Future<bool> hasPassword() async => await load() != null;

  /// Current salt+hash record, or null when no password is set.
  Future<({String salt, String hash})?> load() async {
    final data = await _read();
    final salt = data['pwSalt'] as String?;
    final hash = data['pwHash'] as String?;
    if (salt == null || hash == null || hash.isEmpty) return null;
    return (salt: salt, hash: hash);
  }

  Future<bool> verify(String password) async {
    final rec = await load();
    if (rec == null) return false;
    return hashOf(password, rec.salt) == rec.hash;
  }

  Future<void> setPassword(String password) async {
    final data = await _read();
    final salt = base64Encode(
      List<int>.generate(16, (_) => Random.secure().nextInt(256)),
    );
    data['pwSalt'] = salt;
    data['pwHash'] = hashOf(password, salt);
    await _write(data);
  }

  Future<void> clearPassword() async {
    final data = await _read()
      ..remove('pwSalt')
      ..remove('pwHash');
    await _write(data);
  }
}
