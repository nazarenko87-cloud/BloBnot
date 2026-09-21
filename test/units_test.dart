import 'package:blobnot/utils/units.dart';
import 'package:flutter_test/flutter_test.dart';

UnitCategory cat(String id) => kUnitCategories.firstWhere((c) => c.id == id);

void main() {
  test('length', () {
    expect(convertUnits(cat('length'), 1, 'm', 'ft'), closeTo(3.28084, 1e-5));
    expect(convertUnits(cat('length'), 1, 'mi', 'km'), closeTo(1.609344, 1e-9));
    expect(convertUnits(cat('length'), 12, 'in', 'ft'), closeTo(1, 1e-12));
  });

  test('weight', () {
    expect(convertUnits(cat('weight'), 1, 'kg', 'lb'), closeTo(2.20462, 1e-5));
    expect(convertUnits(cat('weight'), 16, 'oz', 'lb'), closeTo(1, 1e-12));
  });

  test('temperature uses offsets, not ratios', () {
    final t = cat('temperature');
    expect(convertUnits(t, 100, '°C', '°F'), closeTo(212, 1e-9));
    expect(convertUnits(t, 32, '°F', '°C'), closeTo(0, 1e-9));
    expect(convertUnits(t, 0, 'K', '°C'), closeTo(-273.15, 1e-9));
    expect(convertUnits(t, -40, '°C', '°F'), closeTo(-40, 1e-9));
  });

  test('area, volume, speed, time, data', () {
    expect(convertUnits(cat('area'), 1, 'ha', 'm²'), closeTo(10000, 1e-9));
    expect(convertUnits(cat('volume'), 1, 'm³', 'l'), closeTo(1000, 1e-9));
    expect(convertUnits(cat('speed'), 36, 'km/h', 'm/s'), closeTo(10, 1e-9));
    expect(convertUnits(cat('time'), 2.5, 'h', 'min'), closeTo(150, 1e-9));
    expect(convertUnits(cat('data'), 1, 'GB', 'MB'), closeTo(1024, 1e-9));
  });

  test('converting to the same unit is the identity', () {
    for (final c in kUnitCategories) {
      for (final u in c.units) {
        expect(convertUnits(c, 7.5, u.name, u.name), closeTo(7.5, 1e-9));
      }
    }
  });

  test('every category defaults to two of its own, different units', () {
    for (final c in kUnitCategories) {
      expect(
        c.units.map((u) => u.name),
        containsAll([c.defaultFrom, c.defaultTo]),
      );
      expect(c.defaultFrom, isNot(c.defaultTo));
      expect(double.tryParse(c.sample), isNotNull);
      expect(c.units.map((u) => u.name).toSet().length, c.units.length);
    }
  });
}
