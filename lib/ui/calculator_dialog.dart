import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/calc.dart';

/// Built-in calculator (v1.0 feature): type an expression, see the result
/// live, Enter or the copy button puts it on the clipboard.
Future<void> showCalculatorDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => const _CalculatorDialog(),
  );
}

class _CalculatorDialog extends StatefulWidget {
  const _CalculatorDialog();

  @override
  State<_CalculatorDialog> createState() => _CalculatorDialogState();
}

class _CalculatorDialogState extends State<_CalculatorDialog> {
  final _ctrl = TextEditingController();
  double? _result;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String get _resultText {
    final r = _result;
    if (r == null) return '—';
    return r == r.roundToDouble() ? r.toInt().toString() : r.toString();
  }

  Future<void> _copy() async {
    if (_result == null) return;
    await Clipboard.setData(ClipboardData(text: _resultText));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Result copied')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return AlertDialog(
      title: const Text('Calculator'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _ctrl,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: '2 * (3 + 4.5)',
                prefixIcon: Icon(Icons.calculate_outlined),
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _result = evaluate(v)),
              onSubmitted: (_) => _copy(),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  '= $_resultText',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Copy result',
                  icon: const Icon(Icons.copy, size: 18),
                  onPressed: _copy,
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
