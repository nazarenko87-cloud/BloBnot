import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'app_paths.dart';
import 'safe_file.dart';

/// Local launch password: salted SHA-256, stored in the app's settings file
/// (app-local — deliberately does NOT travel with the vault).
class PasswordStore {
  PasswordStore({File? file}) : _override = file;

  final File? _override;

  Future<File> get _file async => _override ?? await AppPaths.settingsFile();

  Future<Map<String, dynamic>> _read() async {
    // Throws [UnreadableFileException] when the file is there but locked:
    // "no password" must never be concluded from a failed read, or the lock
    // screen would be skipped and the next write would erase the hash.
    final raw = await readJsonFile(await _file);
    return raw is Map<String, dynamic> ? raw : {};
  }

  Future<void> _write(Map<String, dynamic> data) async {
    final file = await _file;
    await writeFileAtomic(file, jsonEncode(data));
  }

  static String hashOf(String password, String salt) =>
      sha256.convert(utf8.encode('$salt$password')).toString();

  Future<bool> hasPassword() async => await load() != null;

  /// Current salt+hash record, or null when no password is set.
  Future<({String salt, String hash})?> load() async {
    final data = await _read();
    final salt = data['pwSalt'];
    final hash = data['pwHash'];
    if (salt is! String || hash is! String || hash.isEmpty) return null;
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
