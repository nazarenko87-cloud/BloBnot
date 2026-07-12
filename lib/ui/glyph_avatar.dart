import 'dart:math';

import 'package:flutter/material.dart';

import '../models/note.dart';

/// Note medallion: emoji glyph (or first letter), with a progress ring when
/// the note contains a checklist (v1.3 behaviour).
class GlyphAvatar extends StatelessWidget {
  const GlyphAvatar({
    super.key,
    required this.note,
    required this.glyph,
    this.radius = 14,
    this.onTap,
  });

  final Note note;
  final String? glyph;
  final double radius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final progress = note.checklistProgress;

    Widget avatar = CircleAvatar(
      radius: radius,
      backgroundColor: accent.withValues(alpha: 0.2),
      child: Text(
        glyph ??
            (note.title.isEmpty
                ? '?'
                : note.title.characters.first.toUpperCase()),
        style: TextStyle(
          fontSize: glyph != null ? radius : radius * 0.85,
          color: accent,
        ),
      ),
    );

    if (progress != null) {
      avatar = CustomPaint(
        painter: _RingPainter(progress: progress, color: accent),
        child: Padding(padding: const EdgeInsets.all(2), child: avatar),
      );
    }

    return onTap == null
        ? avatar
        : InkWell(borderRadius: BorderRadius.circular(99), onTap: onTap, child: avatar);
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = color.withValues(alpha: 0.15);
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(rect.deflate(1), 0, 2 * pi, false, track);
    canvas.drawArc(rect.deflate(1), -pi / 2, 2 * pi * progress, false, arc);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.progress != progress || old.color != color;
}
