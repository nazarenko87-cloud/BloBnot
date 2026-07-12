import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/note.dart';
import '../state/vault_controller.dart';

/// A node in the wiki-link graph.
class _Node {
  _Node(this.title, this.pathByTitle);
  final String title;
  final String? pathByTitle;
  Offset pos = Offset.zero;
  Offset vel = Offset.zero;
  bool pinned = false;
}

class GraphView extends StatefulWidget {
  const GraphView({super.key});

  @override
  State<GraphView> createState() => _GraphViewState();
}

class _GraphViewState extends State<GraphView>
    with SingleTickerProviderStateMixin {
  late final _ticker = createTicker((_) => _step());
  final _rng = Random(7);
  List<_Node> _nodes = [];
  List<(int, int)> _edges = [];
  String _signature = '';
  int? _dragging;

  @override
  void initState() {
    super.initState();
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  /// Rebuild nodes/edges only when the link structure actually changes.
  void _rebuildIfNeeded(List<Note> notes) {
    final titles = notes.map((n) => n.title).toSet();
    final sig = StringBuffer();
    for (final n in notes) {
      sig.write(n.title);
      sig.write('>');
      sig.write(n.outgoingLinks.where(titles.contains).join(','));
      sig.write(';');
    }
    if (sig.toString() == _signature) return;
    _signature = sig.toString();

    final byTitle = {for (final n in notes) n.title: n.path};
    final nodes = <_Node>[];
    final index = <String, int>{};
    for (final n in notes) {
      index[n.title] = nodes.length;
      nodes.add(_Node(n.title, byTitle[n.title])
        ..pos = Offset(_rng.nextDouble() * 300, _rng.nextDouble() * 300));
    }
    final edges = <(int, int)>[];
    for (final n in notes) {
      final from = index[n.title]!;
      for (final link in n.outgoingLinks) {
        final to = index[link];
        if (to != null && to != from) edges.add((from, to));
      }
    }
    _nodes = nodes;
    _edges = edges;
  }

  void _step() {
    if (_nodes.isEmpty) return;
    const repulsion = 1600.0;
    const springLen = 90.0;
    const springK = 0.02;
    const damping = 0.85;
    final center = _paintCenter;

    for (var i = 0; i < _nodes.length; i++) {
      final a = _nodes[i];
      if (a.pinned || _dragging == i) continue;
      var force = Offset.zero;
      for (var j = 0; j < _nodes.length; j++) {
        if (i == j) continue;
        final d = a.pos - _nodes[j].pos;
        final dist = d.distance.clamp(0.01, 500.0);
        force += d / dist * (repulsion / (dist * dist));
      }
      // Pull toward center so disconnected nodes don't fly away.
      force += (center - a.pos) * 0.008;
      a.vel = (a.vel + force) * damping;
    }
    for (final (from, to) in _edges) {
      final a = _nodes[from];
      final b = _nodes[to];
      final d = b.pos - a.pos;
      final dist = d.distance.clamp(0.01, 500.0);
      final f = d / dist * ((dist - springLen) * springK);
      if (!a.pinned && _dragging != from) a.vel += f;
      if (!b.pinned && _dragging != to) b.vel -= f;
    }
    for (var i = 0; i < _nodes.length; i++) {
      if (_nodes[i].pinned || _dragging == i) continue;
      _nodes[i].pos += _nodes[i].vel;
    }
    if (mounted) setState(() {});
  }

  Offset _paintCenter = const Offset(150, 200);

  int? _hitTest(Offset local) {
    for (var i = _nodes.length - 1; i >= 0; i--) {
      if ((_nodes[i].pos - local).distance <= 16) return i;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<VaultController>();
    _rebuildIfNeeded(controller.notes);
    final accent = Theme.of(context).colorScheme.primary;
    final currentTitle = controller.current?.title;

    return LayoutBuilder(
      builder: (context, constraints) {
        _paintCenter = Offset(constraints.maxWidth / 2, constraints.maxHeight / 2);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text(
                'Graph  ${_nodes.length} · ${_edges.length}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Expanded(
              child: GestureDetector(
                onPanStart: (d) => setState(() => _dragging = _hitTest(d.localPosition)),
                onPanUpdate: (d) {
                  if (_dragging != null) {
                    setState(() => _nodes[_dragging!].pos = d.localPosition);
                  }
                },
                onPanEnd: (_) => setState(() => _dragging = null),
                onDoubleTapDown: (d) {
                  final hit = _hitTest(d.localPosition);
                  if (hit != null) {
                    setState(() => _nodes[hit].pinned = !_nodes[hit].pinned);
                  }
                },
                onTapUp: (d) {
                  final hit = _hitTest(d.localPosition);
                  if (hit == null) return;
                  final path = _nodes[hit].pathByTitle;
                  if (path == null) return;
                  for (final n in controller.notes) {
                    if (n.path == path) {
                      controller.select(n);
                      break;
                    }
                  }
                },
                child: CustomPaint(
                  painter: _GraphPainter(
                    nodes: _nodes,
                    edges: _edges,
                    accent: accent,
                    currentTitle: currentTitle,
                    labelColor: Theme.of(context).textTheme.bodySmall?.color ??
                        Colors.grey,
                  ),
                  size: Size.infinite,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _GraphPainter extends CustomPainter {
  _GraphPainter({
    required this.nodes,
    required this.edges,
    required this.accent,
    required this.currentTitle,
    required this.labelColor,
  });

  final List<_Node> nodes;
  final List<(int, int)> edges;
  final Color accent;
  final String? currentTitle;
  final Color labelColor;

  @override
  void paint(Canvas canvas, Size size) {
    final edgePaint = Paint()
      ..color = accent.withValues(alpha: 0.35)
      ..strokeWidth = 1.2;
    for (final (from, to) in edges) {
      canvas.drawLine(nodes[from].pos, nodes[to].pos, edgePaint);
    }
    for (final node in nodes) {
      final isCurrent = node.title == currentTitle;
      final r = isCurrent ? 12.0 : 9.0;
      final glow = Paint()
        ..color = accent.withValues(alpha: node.pinned ? 0.5 : 0.25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawCircle(node.pos, r + 4, glow);
      canvas.drawCircle(
        node.pos,
        r,
        Paint()..color = isCurrent ? accent : accent.withValues(alpha: 0.8),
      );
      final tp = TextPainter(
        text: TextSpan(
          text: node.title,
          style: TextStyle(fontSize: 11, color: labelColor),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: 120);
      tp.paint(canvas, node.pos + Offset(-tp.width / 2, r + 3));
    }
  }

  @override
  bool shouldRepaint(covariant _GraphPainter old) => true;
}
