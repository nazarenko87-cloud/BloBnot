import 'package:blobnot/utils/calc_engine.dart';
import 'package:flutter_test/flutter_test.dart';

/// Press a sequence written the way you would read it off the keypad:
/// digits and `.`, `+ - * /`, `=`, `%`, and named keys in braces.
CalcEngine run(String keys, [CalcEngine? engine]) {
  final e = engine ?? CalcEngine();
  final named = {
    'CE': CalcKey.clearEntry,
    'C': CalcKey.clear,
    'BS': CalcKey.backspace,
    'inv': CalcKey.inverse,
    'sqr': CalcKey.square,
    'sqrt': CalcKey.squareRoot,
    'neg': CalcKey.negate,
    'MS': CalcKey.memoryStore,
    'MR': CalcKey.memoryRecall,
    'M+': CalcKey.memoryAdd,
    'M-': CalcKey.memorySubtract,
    'MC': CalcKey.memoryClear,
  };
  for (final m in RegExp(r'\{([^}]+)\}|.').allMatches(keys)) {
    final token = m.group(1) ?? m.group(0)!;
    if (token == ' ') continue;
    final key =
        named[token] ??
        switch (token) {
          '.' => CalcKey.dot,
          '+' => CalcKey.add,
          '-' => CalcKey.subtract,
          '*' => CalcKey.multiply,
          '/' => CalcKey.divide,
          '=' => CalcKey.equals,
          '%' => CalcKey.percent,
          _ => CalcKey.digits[int.parse(token)],
        };
    e.press(key);
  }
  return e;
}

void main() {
  group('basic arithmetic', () {
    test('evaluates left to right like the Windows calculator', () {
      expect(run('2+3*4=').display, '20');
      expect(run('10-4/2=').display, '3');
    });

    test('hides binary floating-point noise', () {
      expect(run('0.1+0.2=').display, '0.3');
    });

    test('groups thousands in the display', () {
      expect(run('1234567.5').display, '1,234,567.5');
      expect(run('1000000*1000=').display, '1,000,000,000');
    });

    test('shows the expression line', () {
      final e = run('12+7=');
      expect(e.expression, '12 + 7 =');
      expect(e.display, '19');
    });

    test('a second operator applies the pending one first', () {
      final e = run('5+3*');
      expect(e.display, '8');
      expect(e.expression, '8 ×');
    });

    test('pressing another operator only replaces the pending one', () {
      expect(run('5+-2=').display, '3');
    });
  });

  group('equals', () {
    test('repeats the last operation', () {
      expect(run('2+3===').display, '11');
      expect(run('3*2==').display, '12');
    });

    test('repeats with a newly typed number', () {
      expect(run('2+3=10=').display, '13');
    });

    test('with no right operand uses the left one', () {
      expect(run('5+=').display, '10');
    });

    test('a new number after = starts over', () {
      final e = run('2+3=7');
      expect(e.display, '7');
      expect(e.expression, '');
    });
  });

  group('errors', () {
    test('division by zero shows a message and blocks until reset', () {
      final e = run('5/0=');
      expect(e.hasError, isTrue);
      expect(e.display, 'Cannot divide by zero');
      expect(e.plainValue, isNull);
      run('7', e);
      expect(e.hasError, isFalse);
      expect(e.display, '7');
    });

    test('an operator after an error just clears it', () {
      final e = run('5/0=+');
      expect(e.hasError, isFalse);
      expect(e.display, '0');
    });

    test('square root of a negative is invalid input', () {
      expect(run('4{neg}{sqrt}').display, 'Invalid input');
    });

    test('1/x of zero is an error', () {
      expect(run('0{inv}').hasError, isTrue);
    });
  });

  group('percent', () {
    test('with + it is a percentage of the left operand', () {
      expect(run('200+10%=').display, '220');
    });

    test('with × it is a plain fraction', () {
      expect(run('50*10%=').display, '5');
    });

    test('on its own it yields zero', () {
      expect(run('10%').display, '0');
    });
  });

  group('unary keys', () {
    test('square, root and inverse', () {
      expect(run('9{sqrt}').display, '3');
      expect(run('12{sqr}').display, '144');
      expect(run('4{inv}').display, '0.25');
    });

    test('work on the right operand and keep the pending operation', () {
      final e = run('10+9{sqrt}');
      expect(e.expression, '10 + √(9)');
      run('=', e);
      expect(e.display, '13');
    });

    test('negate flips the sign and leaves zero alone', () {
      expect(run('5{neg}').display, '−5');
      expect(run('{neg}').display, '0');
    });
  });

  group('editing', () {
    test('backspace removes the last digit and bottoms out at 0', () {
      expect(run('123{BS}').display, '12');
      expect(run('7{BS}{BS}').display, '0');
    });

    test('backspace does not edit a computed result', () {
      expect(run('2+3={BS}').display, '5');
    });

    test('a second decimal point is ignored', () {
      expect(run('1.2.3').display, '1.23');
    });

    test('a leading dot becomes 0.', () {
      expect(run('.5').display, '0.5');
    });

    test('input stops at 16 digits', () {
      expect(run('12345678901234567890').plainValue, '1234567890123456');
    });

    test('CE clears the entry but keeps the pending operation', () {
      expect(run('5+3{CE}4=').display, '9');
    });

    test('C clears everything but memory', () {
      final e = run('5{MS}2+3{C}');
      expect(e.display, '0');
      expect(e.expression, '');
      expect(e.memory, 5);
    });
  });

  group('memory', () {
    test('store, add, subtract and recall', () {
      final e = run('10{MS}5{M+}2{M-}');
      expect(e.memory, 13);
      run('{C}{MR}', e);
      expect(e.display, '13');
    });

    test('memory clear empties it', () {
      expect(run('4{MS}{MC}').memory, isNull);
    });

    test('recalled value is an operand', () {
      expect(run('3{MS}{C}10+{MR}=').display, '13');
    });
  });

  group('formatNumber', () {
    test('drops a trailing .0 and uses exponents only at the extremes', () {
      expect(formatNumber(5.0), '5');
      expect(formatNumber(-0.5), '-0.5');
      expect(formatNumber(1e20), '1e+20');
      expect(formatNumber(1e-7), '0.0000001');
    });
  });
}
