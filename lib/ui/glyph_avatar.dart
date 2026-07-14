import 'dart:math';

import 'package:flutter/material.dart';

import '../models/note.dart';
import 'pulse.dart';

/// Note medallion: emoji glyph (or first letter) inside a fixed 34×34 box so
/// it never overflows its list row. When the note contains a checklist the
/// medallion shows task status two ways (v1.3 behaviour):
/// - a progress ring around the rim, and
/// - a bottom-up fill tint proportional to completion.
/// [pulse] adds a glowing pulse (active reminder).
class GlyphAvatar extends StatelessWidget {
  const GlyphAvatar({
    super.key,
    required this.note,
    required this.glyph,
    this.style = 'ring',
    this.pulse = false,
    this.onTap,
  });

  final Note note;
  final String? glyph;

  /// 'ring' | 'fill' | 'tint' (Settings → Glyph style, v1.3).
  final String style;
  final bool pulse;
  final VoidCallback? onTap;

  static const double _box = 34;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final progress = note.checklistProgress;
    final fill = style == 'fill';

    Widget avatar = CustomPaint(
      painter: _MedallionPainter(
        progress: progress,
        color: accent,
        style: style,
      ),
      child: Center(
        child: Text(
          glyph ??
              (note.title.isEmpty
                  ? '?'
                  : note.title.characters.first.toUpperCase()),
          style: TextStyle(
            fontSize: glyph != null ? 15 : 13,
            fontWeight: FontWeight.w600,
            color: fill ? Theme.of(context).colorScheme.surface : accent,
          ),
        ),
      ),
    );

    avatar = SizedBox(width: _box, height: _box, child: avatar);

    if (onTap != null) {
      avatar = InkWell(
        borderRadius: BorderRadius.circular(_box),
        onTap: onTap,
        child: avatar,
      );
    }

    return Pulse(enabled: pulse, child: avatar);
  }
}

class _MedallionPainter extends CustomPainter {
  _MedallionPainter({
    required this.progress,
    required this.color,
    required this.style,
  });

  final double? progress;
  final Color color;
  final String style;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 2;

    switch (style) {
      case 'fill':
        canvas.drawCircle(center, r, Paint()..color = color);
      case 'tint':
        final rect = RRect.fromRectAndRadius(
          Rect.fromCircle(center: center, radius: r),
          Radius.circular(r * 0.45),
        );
        canvas.drawRRect(rect, Paint()..color = color.withValues(alpha: 0.20));
        canvas.drawRRect(
          rect,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4
            ..color = color.withValues(alpha: 0.45),
        );
      default: // ring
        canvas.drawCircle(
          center,
          r,
          Paint()..color = color.withValues(alpha: 0.08),
        );
        canvas.drawCircle(
          center,
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6
            ..color = color.withValues(alpha: progress == null ? 0.55 : 0.18),
        );
    }

    if (progress != null) {
      // Bottom-up completion fill.
      final fillHeight = 2 * r * progress!.clamp(0.0, 1.0);
      canvas.save();
      canvas.clipPath(
        Path()..addOval(Rect.fromCircle(center: center, radius: r)),
      );
      canvas.drawRect(
        Rect.fromLTWH(
          center.dx - r,
          center.dy + r - fillHeight,
          2 * r,
          fillHeight,
        ),
        Paint()..color = color.withValues(alpha: 0.30),
      );
      canvas.restore();

      // Progress ring.
      final track = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..color = color.withValues(alpha: 0.18);
      final arc = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..color = color;
      canvas.drawCircle(center, r, track);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: r),
        -pi / 2,
        2 * pi * progress!,
        false,
        arc,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MedallionPainter old) =>
      old.progress != progress || old.color != color || old.style != style;
}
