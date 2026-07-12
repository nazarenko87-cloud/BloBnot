import 'package:flutter/material.dart';

/// The 18 "Bubble" characters recovered from the original v1.3 build.
const List<String> kStickers = [
  'angry',
  'artist',
  'base',
  'cool',
  'crying',
  'driving',
  'gamer',
  'hidden',
  'love',
  'sad',
  'shocked',
  'shopping',
  'sick',
  'sick_retching',
  'sleepy',
  'sporty',
  'surprised',
  'thinking',
];

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
            for (final name in kStickers)
              InkWell(
                onTap: () =>
                    Navigator.pop(context, 'assets/stickers/$name.png'),
                child: Tooltip(
                  message: name,
                  child: Image.asset('assets/stickers/$name.png'),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
