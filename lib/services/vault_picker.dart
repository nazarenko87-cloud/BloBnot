import 'dart:io';

import 'package:file_selector/file_selector.dart';

import 'saf_channel.dart';

/// Prompt the user for a vault location and return its id, or null if they
/// cancelled.
///
/// On Android this opens the SAF folder picker and returns a persisted
/// `content://` tree URI (so the vault can be a Google-Drive-synced folder).
/// On desktop it returns a plain directory path via the native folder chooser.
/// `getDirectoryPath` is not supported on Android, hence the split.
Future<String?> pickVaultId() async {
  if (Platform.isAndroid) return SafChannel.pickTree();
  return getDirectoryPath();
}
