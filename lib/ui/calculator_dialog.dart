import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../state/vault_controller.dart';
import '../utils/calc_engine.dart';
import '../utils/units.dart';
import 'theme.dart';

/// Classic calculator (Windows-style standard mode) plus offline unit
/// converters, with "Insert into note" for the result.
Future<void> showCalculatorDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => const CalculatorDialog(),
  );
}

class CalculatorDialog extends StatefulWidget {
  const CalculatorDialog({super.key});

  @override
  State<CalculatorDialog> createState() => _CalculatorDialogState();
}

class _CalculatorDialogState extends State<CalculatorDialog> {
  final _engine = CalcEngine();

  /// Null in standard mode, otherwise the converter category.
  UnitCategory? _category;
  String _from = '';
  String _to = '';
  String _input = '0';

  bool get _converting => _category != null;

  void _press(CalcKey key) => setState(() => _engine.press(key));

  void _setMode(UnitCategory? category) {
    setState(() {
      _category = category;
      _swapBack = null;
      if (category != null) {
        _from = category.defaultFrom;
        _to = category.defaultTo;
        _input = category.sample;
      }
    });
  }

  double get _inputValue => double.tryParse(_input) ?? 0;

  double _converted(String unit) =>
      convertUnits(_category!, _inputValue, _from, unit);

  static String _show(double v) =>
      formatDisplay(formatNumber(double.parse(v.toStringAsPrecision(10))));

  void _convKey(String k) {
    setState(() {
      switch (k) {
        case 'CE':
          _input = '0';
        case 'BS':
          _input = _input.substring(0, _input.length - 1);
          if (_input.isEmpty || _input == '-') _input = '0';
        case 'neg':
          if (_input != '0') {
            _input = _input.startsWith('-') ? _input.substring(1) : '-$_input';
          }
        case '.':
          if (!_input.contains('.')) _input += '.';
        default:
          if (_input.replaceAll(RegExp(r'[-.]'), '').length >= 14) return;
          if (_input == '0' || _input == '-0') {
            final sign = _input.startsWith('-') ? '-' : '';
            _input = k == '00' ? _input : '$sign$k';
          } else {
            _input += k;
          }
      }
    });
  }

  /// What the input was before the last swap, and what the swap turned it
  /// into — so swapping straight back restores the typed number exactly
  /// instead of a float that drifted on the round trip.
  ({String typed, String swapped})? _swapBack;

  void _swap() {
    setState(() {
      final back = _swapBack;
      final String next;
      if (back != null && back.swapped == _input) {
        next = back.typed;
        _swapBack = null;
      } else {
        next = formatNumber(
          double.parse(_converted(_to).toStringAsPrecision(12)),
        );
        _swapBack = (typed: _input, swapped: next);
      }
      final previousFrom = _from;
      _from = _to;
      _to = previousFrom;
      _input = next;
    });
  }

  void _insert() {
    final String? text;
    if (_converting) {
      text =
          '${formatNumber(double.parse(_converted(_to).toStringAsPrecision(10)))} $_to';
    } else {
      text = _engine.plainValue;
    }
    final messenger = ScaffoldMessenger.of(context);
    if (text == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Nothing to insert')),
      );
      return;
    }
    final inserted = context.read<VaultController>().insertIntoNote(text);
    if (!inserted) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Open a note first, then insert')),
      );
      return;
    }
    Navigator.pop(context);
    messenger.showSnackBar(SnackBar(content: Text('Inserted $text')));
  }

  /// Numpad keys do not reliably carry a character (it depends on NumLock
  /// and platform), so they are mapped by key rather than by text.
  static final _numpad = <LogicalKeyboardKey, String>{
    LogicalKeyboardKey.numpad0: '0',
    LogicalKeyboardKey.numpad1: '1',
    LogicalKeyboardKey.numpad2: '2',
    LogicalKeyboardKey.numpad3: '3',
    LogicalKeyboardKey.numpad4: '4',
    LogicalKeyboardKey.numpad5: '5',
    LogicalKeyboardKey.numpad6: '6',
    LogicalKeyboardKey.numpad7: '7',
    LogicalKeyboardKey.numpad8: '8',
    LogicalKeyboardKey.numpad9: '9',
    LogicalKeyboardKey.numpadDecimal: '.',
    LogicalKeyboardKey.numpadAdd: '+',
    LogicalKeyboardKey.numpadSubtract: '-',
    LogicalKeyboardKey.numpadMultiply: '*',
    LogicalKeyboardKey.numpadDivide: '/',
  };

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final ch = _numpad[key] ?? event.character;
    if (key == LogicalKeyboardKey.escape) {
      Navigator.pop(context);
      return KeyEventResult.handled;
    }
    if (_converting) {
      String? k;
      if (ch != null && RegExp(r'^[0-9]$').hasMatch(ch)) k = ch;
      if (ch == '.' || ch == ',') k = '.';
      if (key == LogicalKeyboardKey.backspace) k = 'BS';
      if (key == LogicalKeyboardKey.delete) k = 'CE';
      if (k == null) return KeyEventResult.ignored;
      _convKey(k);
      return KeyEventResult.handled;
    }
    CalcKey? k;
    if (ch != null && RegExp(r'^[0-9]$').hasMatch(ch)) {
      k = CalcKey.digits[int.parse(ch)];
    } else {
      k = switch (ch) {
        '.' || ',' => CalcKey.dot,
        '+' => CalcKey.add,
        '-' => CalcKey.subtract,
        '*' => CalcKey.multiply,
        '/' => CalcKey.divide,
        '%' => CalcKey.percent,
        '=' => CalcKey.equals,
        _ => null,
      };
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      k = CalcKey.equals;
    } else if (key == LogicalKeyboardKey.backspace) {
      k = CalcKey.backspace;
    } else if (key == LogicalKeyboardKey.delete) {
      k = CalcKey.clearEntry;
    }
    if (k == null) return KeyEventResult.ignored;
    _press(k);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      clipBehavior: Clip.antiAlias,
      child: Focus(
        autofocus: true,
        onKeyEvent: _onKey,
        child: SizedBox(
          width: 340,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(context),
                if (_converting)
                  ..._converter(context)
                else
                  ..._standard(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
      child: Row(
        children: [
          PopupMenuButton<String>(
            tooltip: 'Modes',
            icon: const Icon(Icons.menu),
            onSelected: (id) => _setMode(
              id == 'standard'
                  ? null
                  : kUnitCategories.firstWhere((c) => c.id == id),
            ),
            itemBuilder: (context) => [
              const PopupMenuItem(
                enabled: false,
                height: 28,
                child: Text('CALCULATOR', style: TextStyle(fontSize: 11)),
              ),
              _modeItem(
                'standard',
                Icons.calculate_outlined,
                'Standard',
                !_converting,
              ),
              const PopupMenuItem(
                enabled: false,
                height: 28,
                child: Text('CONVERTER', style: TextStyle(fontSize: 11)),
              ),
              for (final c in kUnitCategories)
                _modeItem(c.id, _iconFor(c.id), c.name, _category?.id == c.id),
            ],
          ),
          Expanded(
            child: Text(
              _category?.name ?? 'Standard',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
          ),
          IconButton(
            tooltip: 'Insert into note',
            icon: Icon(Icons.note_add_outlined, color: accent),
            onPressed: _insert,
          ),
          IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  PopupMenuItem<String> _modeItem(
    String id,
    IconData icon,
    String label,
    bool selected,
  ) => PopupMenuItem(
    value: id,
    child: Row(
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(fontWeight: selected ? FontWeight.w700 : null),
        ),
      ],
    ),
  );

  static IconData _iconFor(String id) => switch (id) {
    'length' => Icons.straighten,
    'weight' => Icons.scale_outlined,
    'temperature' => Icons.thermostat,
    'area' => Icons.square_foot,
    'volume' => Icons.water_drop_outlined,
    'speed' => Icons.speed,
    'time' => Icons.schedule,
    _ => Icons.storage,
  };

  List<Widget> _standard(BuildContext context) {
    final muted = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.6);
    final accent = Theme.of(context).colorScheme.primary;
    final memory = _engine.memory;
    Widget memKey(String label, CalcKey key, {bool needsMemory = false}) =>
        Expanded(
          child: TextButton(
            onPressed: needsMemory && memory == null ? null : () => _press(key),
            child: Text(label, style: const TextStyle(fontSize: 12)),
          ),
        );

    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
        child: Text(
          _engine.expression,
          key: const Key('calc-expression'),
          textAlign: TextAlign.right,
          style: TextStyle(color: muted, fontSize: 14),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
        child: SizedBox(
          height: 60,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(
              _engine.display,
              key: const Key('calc-display'),
              style: TextStyle(
                fontSize: _engine.hasError ? 24 : 46,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Row(
          children: [
            memKey('MC', CalcKey.memoryClear, needsMemory: true),
            memKey('MR', CalcKey.memoryRecall, needsMemory: true),
            memKey('M+', CalcKey.memoryAdd),
            memKey('M−', CalcKey.memorySubtract),
            memKey('MS', CalcKey.memoryStore),
          ],
        ),
      ),
      if (memory != null)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'M = ${formatDisplay(formatNumber(memory))}',
            style: TextStyle(color: accent, fontSize: 12),
          ),
        ),
      _KeyGrid(
        columns: 4,
        keys: [
          _k('%', CalcKey.percent),
          _k('CE', CalcKey.clearEntry),
          _k('C', CalcKey.clear),
          _k('⌫', CalcKey.backspace, icon: Icons.backspace_outlined),
          _k('¹/x', CalcKey.inverse, fn: true),
          _k('x²', CalcKey.square, fn: true),
          _k('²√x', CalcKey.squareRoot, fn: true),
          _k('÷', CalcKey.divide),
          for (final row in const [
            [7, 8, 9],
            [4, 5, 6],
            [1, 2, 3],
          ]) ...[
            for (final d in row)
              _k('$d', CalcKey.digits[d], kind: _KeyKind.digit),
            _k(
              switch (row.first) {
                7 => '×',
                4 => '−',
                _ => '+',
              },
              switch (row.first) {
                7 => CalcKey.multiply,
                4 => CalcKey.subtract,
                _ => CalcKey.add,
              },
            ),
          ],
          _k('+/−', CalcKey.negate, kind: _KeyKind.digit),
          _k('0', CalcKey.d0, kind: _KeyKind.digit),
          _k('.', CalcKey.dot, kind: _KeyKind.digit),
          _k('=', CalcKey.equals, kind: _KeyKind.equals),
        ],
      ),
    ];
  }

  _KeySpec _k(
    String label,
    CalcKey key, {
    _KeyKind kind = _KeyKind.operator,
    bool fn = false,
    IconData? icon,
  }) {
    final disabled =
        _engine.hasError &&
        !key.isDigit &&
        key != CalcKey.dot &&
        key != CalcKey.clear &&
        key != CalcKey.clearEntry &&
        key != CalcKey.backspace;
    return _KeySpec(
      label: label,
      kind: kind,
      italic: fn,
      icon: icon,
      onTap: disabled ? null : () => _press(key),
    );
  }

  List<Widget> _converter(BuildContext context) {
    final category = _category!;
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurface.withValues(alpha: 0.6);
    Widget unitPicker(String value, ValueChanged<String> onChanged, Key key) =>
        DropdownButton<String>(
          key: key,
          value: value,
          isDense: true,
          underline: const SizedBox.shrink(),
          items: [
            for (final u in category.units)
              DropdownMenuItem(value: u.name, child: Text(u.name)),
          ],
          onChanged: (v) {
            if (v == null) return;
            setState(() {
              onChanged(v);
              _swapBack = null;
            });
          },
        );

    Widget bigValue(String text, Color? color, Key key) => SizedBox(
      height: 46,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          key: key,
          style: TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.w600,
            color: color,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );

    final others = category.units.where(
      (u) => u.name != _from && u.name != _to,
    );
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            bigValue(formatDisplay(_input), null, const Key('conv-from')),
            unitPicker(_from, (v) => _from = v, const Key('conv-from-unit')),
            const SizedBox(height: 4),
            OutlinedButton.icon(
              onPressed: _swap,
              icon: const Icon(Icons.swap_vert, size: 16),
              label: const Text('Swap'),
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                shape: const StadiumBorder(),
              ),
            ),
            const SizedBox(height: 4),
            bigValue(
              _show(_converted(_to)),
              scheme.primary,
              const Key('conv-to'),
            ),
            unitPicker(_to, (v) => _to = v, const Key('conv-to-unit')),
          ],
        ),
      ),
      if (others.isNotEmpty)
        Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: scheme.onSurface.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Wrap(
            spacing: 14,
            runSpacing: 2,
            children: [
              for (final u in others)
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: _show(_converted(u.name)),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      TextSpan(text: ' ${u.name}'),
                    ],
                  ),
                  style: TextStyle(fontSize: 12, color: muted),
                ),
            ],
          ),
        ),
      _KeyGrid(
        columns: 3,
        keys: [
          _c('CE', 'CE'),
          _c('+/−', 'neg', kind: _KeyKind.digit),
          _c('⌫', 'BS', icon: Icons.backspace_outlined),
          for (final d in const [7, 8, 9, 4, 5, 6, 1, 2, 3])
            _c('$d', '$d', kind: _KeyKind.digit),
          _c('00', '00', kind: _KeyKind.digit),
          _c('0', '0', kind: _KeyKind.digit),
          _c('.', '.', kind: _KeyKind.digit),
        ],
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Text(
          category.note ?? 'Converted offline, no internet needed',
          style: TextStyle(fontSize: 11, color: muted),
        ),
      ),
    ];
  }

  _KeySpec _c(
    String label,
    String key, {
    _KeyKind kind = _KeyKind.operator,
    IconData? icon,
  }) => _KeySpec(
    label: label,
    kind: kind,
    icon: icon,
    onTap: () => _convKey(key),
  );
}

enum _KeyKind { digit, operator, equals }

class _KeySpec {
  const _KeySpec({
    required this.label,
    required this.kind,
    required this.onTap,
    this.italic = false,
    this.icon,
  });

  final String label;
  final _KeyKind kind;
  final VoidCallback? onTap;
  final bool italic;
  final IconData? icon;
}

class _KeyGrid extends StatelessWidget {
  const _KeyGrid({required this.columns, required this.keys});

  final int columns;
  final List<_KeySpec> keys;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rows = <List<_KeySpec>>[
      for (var i = 0; i < keys.length; i += columns)
        keys.sublist(i, (i + columns).clamp(0, keys.length)),
    ];
    return Padding(
      padding: const EdgeInsets.all(6),
      child: Column(
        children: [
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.all(1.5),
              child: Row(
                children: [
                  for (final spec in row)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(1.5),
                        child: _Key(spec: spec, scheme: scheme),
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

class _Key extends StatelessWidget {
  const _Key({required this.spec, required this.scheme});

  final _KeySpec spec;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final isEquals = spec.kind == _KeyKind.equals;
    final background = switch (spec.kind) {
      _KeyKind.equals => scheme.primary,
      _KeyKind.digit => scheme.onSurface.withValues(alpha: 0.09),
      _KeyKind.operator => scheme.onSurface.withValues(alpha: 0.045),
    };
    final foreground = isEquals ? onAccent(scheme.primary) : scheme.onSurface;
    final enabled = spec.onTap != null;
    return Opacity(
      opacity: enabled ? 1 : 0.35,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(7),
        child: InkWell(
          borderRadius: BorderRadius.circular(7),
          onTap: spec.onTap,
          child: SizedBox(
            height: 48,
            child: Center(
              child: spec.icon != null
                  ? Icon(
                      spec.icon,
                      size: 20,
                      color: foreground,
                      semanticLabel: spec.label,
                    )
                  : Text(
                      spec.label,
                      style: TextStyle(
                        color: foreground,
                        fontSize: isEquals
                            ? 24
                            : (spec.kind == _KeyKind.digit ? 20 : 17),
                        fontWeight: spec.kind == _KeyKind.digit
                            ? FontWeight.w600
                            : FontWeight.w400,
                        fontStyle: spec.italic ? FontStyle.italic : null,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
