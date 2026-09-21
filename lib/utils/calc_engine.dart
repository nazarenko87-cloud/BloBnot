import 'dart:math' as math;

/// Keys of the standard calculator, laid out like the Windows one.
enum CalcKey {
  d0,
  d1,
  d2,
  d3,
  d4,
  d5,
  d6,
  d7,
  d8,
  d9,
  dot,
  add,
  subtract,
  multiply,
  divide,
  equals,
  percent,
  clearEntry,
  clear,
  backspace,
  inverse,
  square,
  squareRoot,
  negate,
  memoryClear,
  memoryRecall,
  memoryAdd,
  memorySubtract,
  memoryStore;

  static const digits = [d0, d1, d2, d3, d4, d5, d6, d7, d8, d9];

  bool get isDigit => index <= d9.index;
  bool get isOperator =>
      this == add || this == subtract || this == multiply || this == divide;
}

const _maxDigits = 16;

/// Standard-mode calculator with the Windows calculator's semantics:
/// immediate left-to-right evaluation, repeat `=`, `%` relative to the
/// pending operand, and memory keys.
class CalcEngine {
  String _entry = '0';
  double? _accumulator;
  CalcKey? _op;
  bool _typing = false;

  /// Whether [_entry] counts as the right-hand operand of [_op].
  bool _hasOperand = true;
  bool _afterEquals = false;
  ({CalcKey op, double operand})? _repeat;
  String _expression = '';
  String? _error;
  double? _memory;

  /// The big number, formatted for display (or the error message).
  String get display => _error ?? formatDisplay(_entry);

  /// The smaller line above it, e.g. `12 + 7 =`.
  String get expression => _error == null ? _expression : '';

  bool get hasError => _error != null;
  double? get memory => _memory;

  /// The current value for "insert into note", without digit grouping.
  String? get plainValue => _error == null ? _entry : null;

  double get _value => double.parse(_entry);

  void press(CalcKey key) {
    if (_error != null) {
      _reset(keepMemory: true);
      if (!key.isDigit && key != CalcKey.dot) return;
    }
    switch (key) {
      case CalcKey.dot:
        _digit('.');
      case CalcKey.add ||
          CalcKey.subtract ||
          CalcKey.multiply ||
          CalcKey.divide:
        _operator(key);
      case CalcKey.equals:
        _equals();
      case CalcKey.percent:
        _percent();
      case CalcKey.inverse || CalcKey.square || CalcKey.squareRoot:
        _unary(key);
      case CalcKey.negate:
        _negate();
      case CalcKey.clearEntry:
        _entry = '0';
        _typing = false;
        _hasOperand = true;
        if (_afterEquals) {
          _expression = '';
          _afterEquals = false;
        }
      case CalcKey.clear:
        _reset(keepMemory: true);
      case CalcKey.backspace:
        _backspace();
      case CalcKey.memoryStore:
        _memory = _value;
        _typing = false;
      case CalcKey.memoryAdd:
        _memory = (_memory ?? 0) + _value;
        _typing = false;
      case CalcKey.memorySubtract:
        _memory = (_memory ?? 0) - _value;
        _typing = false;
      case CalcKey.memoryRecall:
        final m = _memory;
        if (m != null) _setResult(m);
      case CalcKey.memoryClear:
        _memory = null;
      default:
        _digit('${key.index}');
    }
  }

  void _reset({required bool keepMemory}) {
    final memory = _memory;
    _entry = '0';
    _accumulator = null;
    _op = null;
    _typing = false;
    _hasOperand = true;
    _afterEquals = false;
    _repeat = null;
    _expression = '';
    _error = null;
    _memory = keepMemory ? memory : null;
  }

  void _digit(String d) {
    if (_afterEquals && _op == null) {
      _expression = '';
      _afterEquals = false;
    }
    if (!_typing) {
      _entry = d == '.' ? '0.' : d;
      _typing = true;
    } else {
      if (d == '.' && _entry.contains('.')) return;
      if (_entry.replaceAll(RegExp(r'[-.]'), '').length >= _maxDigits) return;
      if (_entry == '0' && d != '.') {
        _entry = d;
      } else if (_entry == '-0' && d != '.') {
        _entry = '-$d';
      } else {
        _entry += d;
      }
    }
    _hasOperand = true;
  }

  void _operator(CalcKey key) {
    final pending = _op;
    if (pending != null && _hasOperand) {
      final r = _apply(_accumulator!, pending, _value);
      if (r == null) return _fail('Cannot divide by zero');
      _accumulator = r;
      _entry = formatNumber(r);
    } else if (pending == null) {
      _accumulator = _value;
    }
    _op = key;
    _hasOperand = false;
    _typing = false;
    _afterEquals = false;
    _expression =
        '${formatDisplay(formatNumber(_accumulator!))} ${_symbol(key)}';
  }

  void _equals() {
    final double a;
    final CalcKey op;
    final double b;
    final pending = _op;
    final repeat = _repeat;
    if (pending != null) {
      a = _accumulator!;
      op = pending;
      b = _hasOperand ? _value : _accumulator!;
    } else if (repeat != null) {
      a = _value;
      op = repeat.op;
      b = repeat.operand;
    } else {
      _expression = '${formatDisplay(_entry)} =';
      _afterEquals = true;
      _typing = false;
      return;
    }
    final r = _apply(a, op, b);
    if (r == null) return _fail('Cannot divide by zero');
    _expression =
        '${formatDisplay(formatNumber(a))} ${_symbol(op)} '
        '${formatDisplay(formatNumber(b))} =';
    _repeat = (op: op, operand: b);
    _op = null;
    _accumulator = null;
    _setResult(r);
    _afterEquals = true;
  }

  /// Windows semantics: with + or −, `%` is a percentage of the left operand
  /// (200 + 10 % → 200 + 20); with × or ÷ it is just a fraction (10 % → 0.1).
  void _percent() {
    final pending = _op;
    final v = _value;
    final double r;
    if (pending == null) {
      r = 0;
    } else if (pending == CalcKey.add || pending == CalcKey.subtract) {
      r = _accumulator! * v / 100;
    } else {
      r = v / 100;
    }
    _setResult(r);
    _expression = '${_pendingPrefix()}${formatDisplay(_entry)}';
  }

  void _unary(CalcKey key) {
    final v = _value;
    final double? r = switch (key) {
      CalcKey.inverse => v == 0 ? null : 1 / v,
      CalcKey.square => v * v,
      _ => v < 0 ? null : math.sqrt(v),
    };
    if (r == null) {
      return _fail(
        key == CalcKey.inverse ? 'Cannot divide by zero' : 'Invalid input',
      );
    }
    final shown = formatDisplay(_entry);
    final label = switch (key) {
      CalcKey.inverse => '1/($shown)',
      CalcKey.square => 'sqr($shown)',
      _ => '√($shown)',
    };
    _expression = '${_pendingPrefix()}$label';
    _setResult(r);
    _afterEquals = false;
  }

  void _negate() {
    if (_entry == '0') return;
    _entry = _entry.startsWith('-') ? _entry.substring(1) : '-$_entry';
    _hasOperand = true;
  }

  void _backspace() {
    if (_typing) {
      _entry = _entry.substring(0, _entry.length - 1);
      if (_entry.isEmpty || _entry == '-') _entry = '0';
    } else if (_afterEquals) {
      _expression = '';
      _afterEquals = false;
    }
  }

  void _setResult(double r) {
    _entry = formatNumber(r);
    _typing = false;
    _hasOperand = true;
  }

  void _fail(String message) {
    _error = message;
    _op = null;
    _accumulator = null;
    _typing = false;
  }

  String _pendingPrefix() {
    final op = _op;
    if (op == null) return '';
    return '${formatDisplay(formatNumber(_accumulator!))} ${_symbol(op)} ';
  }

  static double? _apply(double a, CalcKey op, double b) => switch (op) {
    CalcKey.add => a + b,
    CalcKey.subtract => a - b,
    CalcKey.multiply => a * b,
    CalcKey.divide => b == 0 ? null : a / b,
    _ => null,
  };

  static String _symbol(CalcKey op) => switch (op) {
    CalcKey.add => '+',
    CalcKey.subtract => '−',
    CalcKey.multiply => '×',
    _ => '÷',
  };
}

/// A result as a plain decimal string: at most 15 significant digits (hides
/// binary noise like 0.1 + 0.2), exponent form only for very large or small
/// magnitudes.
String formatNumber(double n) {
  if (n.isNaN || n.isInfinite) return 'NaN';
  if (n == 0) return '0';
  final a = n.abs();
  if (a >= 1e16 || a < 1e-9) {
    return n.toStringAsExponential(9).replaceFirst(RegExp(r'\.?0+e'), 'e');
  }
  var s = double.parse(n.toStringAsPrecision(15)).toString();
  if (s.endsWith('.0')) s = s.substring(0, s.length - 2);
  if (s.contains('e')) {
    // Dart prints some in-range values (e.g. 1e-7) in exponent form.
    s = double.parse(s).toStringAsFixed(15).replaceFirst(RegExp(r'\.?0+$'), '');
  }
  return s;
}

/// Group thousands for display: `-1234567.5` → `−1,234,567.5`.
String formatDisplay(String raw) {
  if (raw.contains('e') || raw == 'NaN') return raw.replaceFirst('-', '−');
  final negative = raw.startsWith('-');
  final body = negative ? raw.substring(1) : raw;
  final dot = body.indexOf('.');
  final intPart = dot < 0 ? body : body.substring(0, dot);
  final frac = dot < 0 ? '' : body.substring(dot);
  final grouped = intPart.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  return '${negative ? '−' : ''}$grouped$frac';
}
