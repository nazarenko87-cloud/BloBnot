import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// A file that exists but could not be read (locked by a sync client, a
/// network hiccup). Callers must NOT fall back to defaults and save them:
/// that is how a moment's lock used to wipe a whole metadata file.
class UnreadableFileException implements IOException {
  UnreadableFileException(this.path, this.cause);

  final String path;
  final Object cause;

  @override
  String toString() => 'Could not read $path ($cause)';
}

const _readAttempts = 4;
const _readPause = Duration(milliseconds: 150);

/// Text of [file], or null when it does not exist. A read that fails is
/// retried a few times (cloud drives lock files briefly) and then reported
/// as [UnreadableFileException] instead of being mistaken for "no file".
Future<String?> readTextFile(File file) async {
  Object? last;
  for (var attempt = 0; attempt < _readAttempts; attempt++) {
    try {
      if (!await file.exists()) return null;
      // Tolerate a stray invalid byte rather than refuse the whole file.
      return utf8.decode(await file.readAsBytes(), allowMalformed: true);
    } on IOException catch (e) {
      last = e;
      await Future<void>.delayed(_readPause);
    }
  }
  throw UnreadableFileException(file.path, last ?? 'unknown error');
}

/// Decoded JSON of [file]; null when the file is missing or empty.
///
/// A file that is not valid JSON is copied to `<name>.corrupt` first and
/// then treated as missing, so whatever was in it can still be recovered
/// after the app saves a fresh one. Throws [UnreadableFileException] when
/// the file is there but cannot be read.
Future<Object?> readJsonFile(File file) async {
  final text = await readTextFile(file);
  if (text == null || text.trim().isEmpty) return null;
  try {
    return jsonDecode(text);
  } on FormatException {
    try {
      await File('${file.path}.corrupt').writeAsString(text, flush: true);
    } on IOException {
      // The backup is best effort.
    }
    return null;
  }
}

/// Like [readJsonFile] for a file that holds one flat JSON object, but a
/// damaged file is not simply treated as empty: whatever `"key": "text"`
/// pairs can still be read out of it are returned. The app settings file
/// keeps the launch password this way — a half-written file must not turn
/// into "no password set".
Future<Map<String, dynamic>> readJsonObjectLenient(File file) async {
  final text = await readTextFile(file);
  if (text == null || text.trim().isEmpty) return {};
  try {
    final raw = jsonDecode(text);
    return raw is Map<String, dynamic> ? raw : {};
  } on FormatException {
    try {
      await File('${file.path}.corrupt').writeAsString(text, flush: true);
    } on IOException {
      // The backup is best effort.
    }
    final salvaged = <String, dynamic>{};
    final pair = RegExp(r'"((?:[^"\\]|\\.)*)"\s*:\s*"((?:[^"\\]|\\.)*)"');
    for (final m in pair.allMatches(text)) {
      try {
        final key = jsonDecode('"${m.group(1)}"');
        final value = jsonDecode('"${m.group(2)}"');
        if (key is String && value is String) salvaged[key] = value;
      } on FormatException {
        // An unreadable pair is skipped; the others still count.
      }
    }
    return salvaged;
  }
}

final Map<String, Future<void>> _writeQueues = {};

/// Writes [text] to [file] so that a crash or a sync client reading mid-write
/// never sees a truncated file: the text goes to `<name>.tmp`, which then
/// replaces the target in one rename. Writes to the same path are queued,
/// so two saves fired close together cannot interleave.
Future<void> writeFileAtomic(File file, String text) {
  final key = file.absolute.path.toLowerCase();
  final previous = _writeQueues[key] ?? Future<void>.value();
  final run = previous.then((_) => _writeNow(file, text));
  // The queue itself never fails; the caller still gets this write's error.
  final tail = run.catchError((Object _) {});
  _writeQueues[key] = tail;
  unawaited(
    tail.whenComplete(() {
      if (identical(_writeQueues[key], tail)) _writeQueues.remove(key);
    }),
  );
  return run;
}

Future<void> _writeNow(File file, String text) async {
  await file.parent.create(recursive: true);
  final tmp = File('${file.path}.tmp');
  try {
    await tmp.writeAsString(text, flush: true);
    await tmp.rename(file.path);
  } on FileSystemException {
    // Some folders refuse the replace-by-rename (a file held open by a sync
    // client, a provider without rename): write in place instead.
    await file.writeAsString(text, flush: true);
    try {
      if (await tmp.exists()) await tmp.delete();
    } on IOException {
      // A leftover .tmp is harmless; the next save replaces it.
    }
  }
}
