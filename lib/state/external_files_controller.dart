import 'dart:io';

import 'package:flutter/foundation.dart';

/// A .txt/.md file opened for viewing from outside the vault (via "Open
/// file…"). Edits stay in memory until explicitly saved into the vault as a
/// note — opening one never touches the original file on disk.
class ExternalFile {
  ExternalFile({required this.path, required this._content});

  final String path;
  String _content;
  String get content => _content;
  bool _dirty = false;
  bool get dirty => _dirty;

  String get title => path.split(RegExp(r'[\\/]')).last;
}

/// Holds the set of externally-opened files (see [ExternalFile]), separate
/// from the vault's own notes.
class ExternalFilesController extends ChangeNotifier {
  final List<ExternalFile> _files = [];
  int? _activeIndex;

  List<ExternalFile> get files => List.unmodifiable(_files);
  ExternalFile? get active =>
      _activeIndex != null ? _files[_activeIndex!] : null;
  bool get hasOpenFiles => _files.isNotEmpty;

  /// Opens [path] in a new tab, or focuses it if already open.
  Future<void> open(String path) async {
    final existing = _files.indexWhere((f) => f.path == path);
    if (existing >= 0) {
      _activeIndex = existing;
      notifyListeners();
      return;
    }
    final content = await File(path).readAsString();
    _files.add(ExternalFile(path: path, content: content));
    _activeIndex = _files.length - 1;
    notifyListeners();
  }

  void select(int index) {
    _activeIndex = index;
    notifyListeners();
  }

  void editActive(String content) {
    final file = active;
    if (file == null) return;
    file._content = content;
    file._dirty = true;
    notifyListeners();
  }

  void close(int index) {
    _files.removeAt(index);
    if (_files.isEmpty) {
      _activeIndex = null;
    } else if (_activeIndex != null) {
      _activeIndex = _activeIndex!.clamp(0, _files.length - 1);
    }
    notifyListeners();
  }

  /// Marks the active file as saved (called after it's been imported into
  /// the vault as a note).
  void markSaved() {
    active?._dirty = false;
    notifyListeners();
  }
}
