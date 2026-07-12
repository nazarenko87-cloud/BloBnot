import 'package:flutter/material.dart';

/// Gentle attention pulse (scale + glow) used for reminder indicators.
class Pulse extends StatefulWidget {
  const Pulse({super.key, required this.enabled, required this.child});

  final bool enabled;
  final Widget child;

  @override
  State<Pulse> createState() => _PulseState();
}

class _PulseState extends State<Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // Created eagerly: a lazy controller would be instantiated during
    // dispose() when the element is already deactivated.
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    if (widget.enabled) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant Pulse old) {
    super.didUpdateWidget(old);
    if (widget.enabled && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.enabled && _controller.isAnimating) {
      _controller
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    final accent = Theme.of(context).colorScheme.primary;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_controller.value);
        return Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.25 + 0.4 * t),
                blurRadius: 4 + 8 * t,
                spreadRadius: 1 + 2 * t,
              ),
            ],
          ),
          child: Transform.scale(scale: 1 + 0.08 * t, child: child),
        );
      },
      child: widget.child,
    );
  }
}
