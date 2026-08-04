import 'package:flutter/material.dart';

/// The "Клякса-B" sticker set (Claude Design handoff, 2026-07): one shared
/// blob face, ten statuses/reactions for the editor's emoji panel.
const Map<String, String> kStickers = {
  'done': 'готово',
  'error': 'ошибка',
  'loading': 'загрузка',
  'warning': 'внимание',
  'sync': 'синхронизация',
  'like': 'лайк',
  'important': 'важное',
  'heart': 'сердце',
  'idea': 'идея',
  'question': 'вопрос',
};

/// Grid picker; resolves to the chosen sticker's asset path, or null.
Future<String?> showStickerPicker(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Sticker'),
      content: SizedBox(
        width: 380,
        child: GridView.count(
          shrinkWrap: true,
          crossAxisCount: 5,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          children: [
            for (final entry in kStickers.entries)
              InkWell(
                onTap: () =>
                    Navigator.pop(context, 'assets/stickers/${entry.key}.png'),
                child: Tooltip(
                  message: entry.value,
                  // Superellipse (squircle) tiles.
                  child: ClipRSuperellipse(
                    borderRadius: BorderRadius.circular(22),
                    child: Image.asset(
                      'assets/stickers/${entry.key}.png',
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
