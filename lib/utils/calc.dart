/// Tiny arithmetic expression evaluator for the built-in calculator:
/// + - * / % ( ) with decimal numbers. Returns null on invalid input.
double? evaluate(String input) {
  final parser = _Parser(input.replaceAll(',', '.'));
  try {
    final v = parser.expression();
    parser.skipWs();
    return parser.atEnd ? v : null;
  } on FormatException {
    return null;
  }
}

class _Parser {
  _Parser(this.src);

  final String src;
  int pos = 0;

  bool get atEnd => pos >= src.length;

  void skipWs() {
    while (!atEnd && src[pos] == ' ') {
      pos++;
    }
  }

  double expression() {
    var v = term();
    while (true) {
      skipWs();
      if (!atEnd && (src[pos] == '+' || src[pos] == '-')) {
        final op = src[pos++];
        final r = term();
        v = op == '+' ? v + r : v - r;
      } else {
        return v;
      }
    }
  }

  double term() {
    var v = factor();
    while (true) {
      skipWs();
      if (!atEnd && (src[pos] == '*' || src[pos] == '/' || src[pos] == '%')) {
        final op = src[pos++];
        final r = factor();
        v = switch (op) {
          '*' => v * r,
          '/' => v / r,
          _ => v % r,
        };
      } else {
        return v;
      }
    }
  }

  double factor() {
    skipWs();
    if (atEnd) throw const FormatException();
    if (src[pos] == '-') {
      pos++;
      return -factor();
    }
    if (src[pos] == '(') {
      pos++;
      final v = expression();
      skipWs();
      if (atEnd || src[pos] != ')') throw const FormatException();
      pos++;
      return v;
    }
    final start = pos;
    bool isDigitOrDot(String c) =>
        c == '.' || (c.codeUnitAt(0) >= 0x30 && c.codeUnitAt(0) <= 0x39);
    while (!atEnd && isDigitOrDot(src[pos])) {
      pos++;
    }
    if (pos == start) throw const FormatException();
    final v = double.tryParse(src.substring(start, pos));
    if (v == null) throw const FormatException();
    return v;
  }
}
