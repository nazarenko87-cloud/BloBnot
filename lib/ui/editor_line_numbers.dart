part of 'editor_pane.dart';

/// Line numbers beside the editor, each set level with its line as laid
/// out: a wrapped line takes several rows and a heading is taller, so the
/// positions come from the text's real layout, not a fixed line height.
class _LineNumbers extends StatefulWidget {
  const _LineNumbers({
    required this.text,
    required this.scale,
    required this.editable,
  });

  final TextEditingController text;
  final double scale;

  /// The editor's laid-out text, or null before the first layout.
  final RenderEditable? Function() editable;

  @override
  State<_LineNumbers> createState() => _LineNumbersState();
}

class _LineNumbersState extends State<_LineNumbers> {
  /// Bottom edge of each line's first row, in the editor's coordinates.
  List<double> _bottoms = const [];

  @override
  void initState() {
    super.initState();
    widget.text.addListener(_scheduleMeasure);
    _scheduleMeasure();
  }

  @override
  void didUpdateWidget(_LineNumbers old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) {
      old.text.removeListener(_scheduleMeasure);
      widget.text.addListener(_scheduleMeasure);
    }
    // Width or font changes re-wrap the text.
    _scheduleMeasure();
  }

  @override
  void dispose() {
    widget.text.removeListener(_scheduleMeasure);
    super.dispose();
  }

  bool _pending = false;

  void _scheduleMeasure() {
    if (_pending) return;
    _pending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pending = false;
      if (!mounted) return;
      final editable = widget.editable();
      if (editable == null || !editable.hasSize) return;
      final text = widget.text.text;
      final bottoms = <double>[];
      var offset = 0;
      while (true) {
        // The first character's box spans its whole row (the editor uses
        // BoxHeightStyle.max) even when it is a hidden live-preview mark.
        final boxes = offset < text.length
            ? editable.getBoxesForSelection(
                TextSelection(baseOffset: offset, extentOffset: offset + 1),
              )
            : const <TextBox>[];
        bottoms.add(
          boxes.isNotEmpty
              ? boxes.first.bottom
              : editable
                    .getLocalRectForCaret(TextPosition(offset: offset))
                    .bottom,
        );
        final next = text.indexOf('\n', offset);
        if (next < 0) break;
        offset = next + 1;
      }
      if (!_same(bottoms, _bottoms)) setState(() => _bottoms = bottoms);
    });
  }

  static bool _same(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if ((a[i] - b[i]).abs() > 0.5) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontFamily: 'monospace',
      fontSize: 13 * widget.scale,
      color: Colors.grey.shade600,
    );
    return SizedBox(
      width: 44,
      child: CustomPaint(painter: _LineNumberPainter(_bottoms, style)),
    );
  }
}

class _LineNumberPainter extends CustomPainter {
  _LineNumberPainter(this.bottoms, this.style);

  final List<double> bottoms;
  final TextStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < bottoms.length; i++) {
      final tp = TextPainter(
        text: TextSpan(text: '${i + 1}', style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      // Sit on the same baseline-ish as the line's first row, right-aligned.
      final y = bottoms[i] - tp.height - style.fontSize! * 0.3;
      tp.paint(canvas, Offset(size.width - 8 - tp.width, y));
      tp.dispose();
    }
  }

  @override
  bool shouldRepaint(_LineNumberPainter old) =>
      old.bottoms != bottoms || old.style != style;
}
