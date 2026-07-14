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
  String? glyph;
  Offset pos = Offset.zero;
  Offset vel = Offset.zero;
  bool pinned = false;
}

class GraphView extends StatefulWidget {
  const GraphView({super.key, this.onHide});

  /// When set, a "hide graph" button is shown in the header (in-flow, next
  /// to the "Graph N · M" label — not floated over it).
  final VoidCallback? onHide;

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

  /// Below this total kinetic energy the layout is considered settled and the
  /// ticker is stopped, so an idle graph costs zero frames.
  static const _sleepEnergy = 0.05;

  void _wake() {
    if (!_ticker.isActive) _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  /// Rebuild nodes/edges only when the link structure actually changes.
  /// Link targets are matched case-insensitively.
  void _rebuildIfNeeded(List<Note> notes) {
    final titles = notes.map((n) => n.title.toLowerCase()).toSet();
    final sig = StringBuffer();
    for (final n in notes) {
      sig.write(n.title);
      sig.write('>');
      sig.write(
        n.outgoingLinks
            .map((l) => l.toLowerCase())
            .where(titles.contains)
            .join(','),
      );
      sig.write(';');
    }
    if (sig.toString() == _signature) return;
    _signature = sig.toString();

    // Preserve positions of nodes that survive the rebuild so the layout
    // does not jump when only a link changes.
    final oldPos = {for (final n in _nodes) n.title: n.pos};
    final byTitle = {for (final n in notes) n.title: n.path};
    final nodes = <_Node>[];
    final index = <String, int>{};
    for (final n in notes) {
      index[n.title.toLowerCase()] = nodes.length;
      nodes.add(_Node(n.title, byTitle[n.title])
        ..pos = oldPos[n.title] ??
            Offset(_rng.nextDouble() * 300, _rng.nextDouble() * 300));
    }
    final edges = <(int, int)>[];
    for (final n in notes) {
      final from = index[n.title.toLowerCase()]!;
      for (final link in n.outgoingLinks) {
        final to = index[link.toLowerCase()];
        if (to != null && to != from) edges.add((from, to));
      }
    }
    _nodes = nodes;
    _edges = edges;
    _wake(); // re-settle the new layout
  }

  void _step() {
    if (_nodes.isEmpty) {
      _ticker.stop();
      return;
    }
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
    var energy = 0.0;
    for (var i = 0; i < _nodes.length; i++) {
      if (_nodes[i].pinned || _dragging == i) continue;
      _nodes[i].pos += _nodes[i].vel;
      energy += _nodes[i].vel.distanceSquared;
    }
    if (mounted) setState(() {});
    // Stop animating once the layout has settled (dragging keeps it awake).
    if (_dragging == null && energy < _sleepEnergy) _ticker.stop();
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
    final glyphByTitle = {
      for (final n in controller.notes) n.title: controller.glyphFor(n),
    };
    for (final node in _nodes) {
      node.glyph = glyphByTitle[node.title];
    }
    final accent = Theme.of(context).colorScheme.primary;
    final currentTitle = controller.current?.title;

    return LayoutBuilder(
      builder: (context, constraints) {
        _paintCenter = Offset(constraints.maxWidth / 2, constraints.maxHeight / 2);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Graph  ${_nodes.length} · ${_edges.length}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (widget.onHide != null)
                    IconButton(
                      tooltip: 'Hide graph',
                      iconSize: 18,
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.close_fullscreen),
                      onPressed: widget.onHide,
                    ),
                ],
              ),
            ),
            Expanded(
              child: GestureDetector(
                onPanStart: (d) => setState(() {
                  _dragging = _hitTest(d.localPosition);
                  _wake();
                }),
                onPanUpdate: (d) {
                  if (_dragging != null) {
                    setState(() {
                      _nodes[_dragging!].pos = d.localPosition;
                      _nodes[_dragging!].vel = Offset.zero;
                    });
                  }
                },
                onPanEnd: (_) => setState(() {
                  _dragging = null;
                  _wake();
                }),
                onDoubleTapDown: (d) {
                  final hit = _hitTest(d.localPosition);
                  if (hit != null) {
                    setState(() {
                      _nodes[hit].pinned = !_nodes[hit].pinned;
                      _wake();
                    });
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
                    surface: Theme.of(context).scaffoldBackgroundColor,
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

/// Amber ring for regular nodes (original v1.0 neon-ring style).
const _kNodeRing = Color(0xFFE0A34F);

class _GraphPainter extends CustomPainter {
  _GraphPainter({
    required this.nodes,
    required this.edges,
    required this.accent,
    required this.surface,
    required this.currentTitle,
    required this.labelColor,
  });

  final List<_Node> nodes;
  final List<(int, int)> edges;
  final Color accent;
  final Color surface;
  final String? currentTitle;
  final Color labelColor;

  @override
  void paint(Canvas canvas, Size size) {
    // Soft glow underlay + crisp line so connections read clearly.
    final edgeGlow = Paint()
      ..color = accent.withValues(alpha: 0.2)
      ..strokeWidth = 3
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    final edgePaint = Paint()
      ..color = accent.withValues(alpha: 0.55)
      ..strokeWidth = 1.4;
    for (final (from, to) in edges) {
      canvas.drawLine(nodes[from].pos, nodes[to].pos, edgeGlow);
      canvas.drawLine(nodes[from].pos, nodes[to].pos, edgePaint);
    }
    for (final node in nodes) {
      final isCurrent = node.title == currentTitle;
      final ring = isCurrent ? accent : _kNodeRing;
      final r = isCurrent ? 15.0 : 12.0;

      // Outlined ring node with the letter/glyph inside (original style).
      final glow = Paint()
        ..color = ring.withValues(alpha: node.pinned ? 0.55 : 0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
      canvas.drawCircle(node.pos, r + 2, glow);
      canvas.drawCircle(node.pos, r, Paint()..color = surface);
      canvas.drawCircle(
        node.pos,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = isCurrent ? 2.4 : 1.8
          ..color = ring,
      );

      final inner = node.glyph ??
          (node.title.isEmpty
              ? '?'
              : node.title.characters.first.toUpperCase());
      final gp = TextPainter(
        text: TextSpan(
          text: inner,
          style: TextStyle(
            fontSize: node.glyph != null ? r : r * 0.9,
            fontWeight: FontWeight.w700,
            color: node.glyph != null ? null : ring,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      gp.paint(canvas, node.pos - Offset(gp.width / 2, gp.height / 2));

      final tp = TextPainter(
        text: TextSpan(
          text: node.title,
          style: TextStyle(fontSize: 11, color: labelColor),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: 120);
      tp.paint(canvas, node.pos + Offset(-tp.width / 2, r + 4));
    }
  }

  @override
  bool shouldRepaint(covariant _GraphPainter old) => true;
}
