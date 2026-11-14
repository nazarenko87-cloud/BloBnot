part of 'editor_pane.dart';

/// The note's fields, shown above the preview as a compact two-column card.
class _PropertiesCard extends StatelessWidget {
  const _PropertiesCard({required this.properties});

  final Map<String, String> properties;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurface.withValues(alpha: 0.55);
    return Container(
      key: const Key('properties-card'),
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final e in properties.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 120,
                    child: Text(
                      e.key,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: muted, fontSize: 13),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      e.value.isEmpty ? '—' : e.value,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// A bounded, clickable preview of an attached image (dropped, attached, or
/// pasted from the clipboard) — tapping it opens [_ImageViewerDialog] with
/// the full-size picture.
class _AttachmentThumbnail extends StatelessWidget {
  const _AttachmentThumbnail({required this.file, required this.alt});

  final File file;
  final String alt;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => showDialog<void>(
          context: context,
          barrierColor: Colors.black87,
          builder: (context) => _ImageViewerDialog(file: file, alt: alt),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 260, maxHeight: 200),
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: Image.file(
              file,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stack) => Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.broken_image_outlined, size: 18),
                    const SizedBox(width: 6),
                    Text(alt, style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Full-size image view opened by tapping an [_AttachmentThumbnail]. Pinch
/// or scroll to zoom, tap the backdrop or the close button to dismiss.
class _ImageViewerDialog extends StatelessWidget {
  const _ImageViewerDialog({required this.file, required this.alt});

  final File file;
  final String alt;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: Stack(
        alignment: Alignment.center,
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: InteractiveViewer(
              child: Image.file(
                file,
                errorBuilder: (context, error, stack) =>
                    Text(alt, style: const TextStyle(color: Colors.white)),
              ),
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: IconButton.filledTonal(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _BacklinksPanel extends StatelessWidget {
  const _BacklinksPanel({required this.note});

  final Note note;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<VaultController>();
    final backlinks = controller.backlinksTo(note.title);
    if (backlinks.isEmpty) return const SizedBox.shrink();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Divider(height: 1),
        ExpansionTile(
          dense: true,
          title: Text(
            'Backlinks (${backlinks.length})',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          children: [
            for (final n in backlinks)
              ListTile(
                dense: true,
                leading: const Icon(Icons.arrow_back, size: 16),
                title: Text(n.title),
                onTap: () => controller.select(n),
              ),
          ],
        ),
      ],
    );
  }
}

class _AttachmentCard extends StatelessWidget {
  const _AttachmentCard({
    required this.name,
    required this.store,
    required this.onDelete,
  });

  final String name;
  final AttachmentStore store;
  final VoidCallback onDelete;

  static const _imageExts = {'.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp'};

  IconData get _typeIcon {
    final ext = name.contains('.')
        ? name.substring(name.lastIndexOf('.')).toLowerCase()
        : '';
    if (_imageExts.contains(ext)) return Icons.image_outlined;
    if (ext == '.pdf') return Icons.picture_as_pdf_outlined;
    if ({'.mp3', '.wav', '.ogg'}.contains(ext)) return Icons.audiotrack;
    if ({'.mp4', '.mkv', '.avi'}.contains(ext)) return Icons.movie_outlined;
    if ({'.zip', '.rar', '.7z'}.contains(ext)) return Icons.folder_zip_outlined;
    return Icons.insert_drive_file_outlined;
  }

  Future<void> _download(BuildContext context) async {
    final location = await getSaveLocation(suggestedName: name);
    if (location == null) return; // user cancelled the picker
    final path = await store.saveAs(name, location.path);
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Saved: $path')));
    }
  }

  Future<String> _sizeLabel() async {
    try {
      final bytes = await File(store.pathOf(name)).length();
      if (bytes < 1024) return '$bytes B';
      if (bytes < 1024 * 1024) {
        return '${(bytes / 1024).toStringAsFixed(2)} KB';
      }
      return '${(bytes / 1024 / 1024).toStringAsFixed(2)} MB';
    } on IOException {
      return 'missing';
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Material(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => store.open(name),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: accent.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                Icon(_typeIcon, size: 22, color: accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      FutureBuilder<String>(
                        future: _sizeLabel(),
                        builder: (context, snap) => Text(
                          'img-size: ${snap.data ?? '…'}',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.attach_file, size: 18, color: accent),
                PopupMenuButton<String>(
                  tooltip: 'Attachment menu',
                  icon: const Icon(Icons.more_horiz, size: 18),
                  onSelected: (v) => switch (v) {
                    'open' => store.open(name),
                    'download' => _download(context),
                    'delete' => onDelete(),
                    _ => null,
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'open', child: Text('Open')),
                    PopupMenuItem(value: 'download', child: Text('Download')),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AttachmentsPanel extends StatelessWidget {
  const _AttachmentsPanel({
    required this.note,
    required this.onAttach,
    required this.onDeleted,
  });

  final Note note;
  final VoidCallback onAttach;

  /// Called after a file is physically deleted, with its name, so the
  /// caller can strip its markdown link from the live editor text.
  final void Function(String name) onDeleted;

  @override
  Widget build(BuildContext context) {
    final names = AttachmentStore.referencedIn(note.body);
    if (names.isEmpty) return const SizedBox.shrink();
    final controller = context.read<VaultController>();
    final store = AttachmentStore(controller.vaultRoot!);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Divider(height: 1),
        ExpansionTile(
          dense: true,
          title: Text(
            'Attachments (${names.length})',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          children: [
            for (final name in names)
              _AttachmentCard(
                name: name,
                store: store,
                onDelete: () => _confirmDelete(context, store, name),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonalIcon(
                  icon: const Icon(Icons.attach_file, size: 18),
                  label: const Text('Attach file'),
                  onPressed: onAttach,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    AttachmentStore store,
    String name,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "$name"?'),
        content: const Text(
          'The file will be removed from the attachments folder and its '
          'link removed from the note.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await store.delete(name);
    onDeleted(name);
  }
}
