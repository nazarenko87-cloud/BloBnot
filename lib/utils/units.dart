/// Offline unit conversion for the calculator's converter modes.
library;

class Unit {
  const Unit(this.name, this.factor);

  final String name;

  /// How many base units one of these is. Unused for temperature, which is
  /// an offset scale rather than a ratio.
  final double factor;
}

class UnitCategory {
  const UnitCategory({
    required this.id,
    required this.name,
    required this.units,
    required this.defaultFrom,
    required this.defaultTo,
    required this.sample,
    this.note,
  });

  final String id;
  final String name;
  final List<Unit> units;
  final String defaultFrom;
  final String defaultTo;

  /// Value the mode opens with, so it shows a real conversion straight away.
  final String sample;
  final String? note;

  bool get isTemperature => id == 'temperature';

  Unit unit(String name) => units.firstWhere((u) => u.name == name);
}

const kUnitCategories = <UnitCategory>[
  UnitCategory(
    id: 'length',
    name: 'Length',
    units: [
      Unit('mm', .001),
      Unit('cm', .01),
      Unit('m', 1),
      Unit('km', 1000),
      Unit('in', .0254),
      Unit('ft', .3048),
      Unit('yd', .9144),
      Unit('mi', 1609.344),
    ],
    defaultFrom: 'm',
    defaultTo: 'ft',
    sample: '5',
  ),
  UnitCategory(
    id: 'weight',
    name: 'Weight',
    units: [
      Unit('mg', 1e-6),
      Unit('g', .001),
      Unit('kg', 1),
      Unit('t', 1000),
      Unit('oz', .028349523125),
      Unit('lb', .45359237),
    ],
    defaultFrom: 'kg',
    defaultTo: 'lb',
    sample: '12',
  ),
  UnitCategory(
    id: 'temperature',
    name: 'Temperature',
    units: [Unit('°C', 1), Unit('°F', 1), Unit('K', 1)],
    defaultFrom: '°C',
    defaultTo: '°F',
    sample: '25',
  ),
  UnitCategory(
    id: 'area',
    name: 'Area',
    units: [
      Unit('mm²', 1e-6),
      Unit('cm²', 1e-4),
      Unit('m²', 1),
      Unit('ha', 1e4),
      Unit('km²', 1e6),
      Unit('ft²', .09290304),
      Unit('acre', 4046.8564224),
    ],
    defaultFrom: 'm²',
    defaultTo: 'ft²',
    sample: '18',
  ),
  UnitCategory(
    id: 'volume',
    name: 'Volume',
    units: [
      Unit('ml', .001),
      Unit('l', 1),
      Unit('m³', 1000),
      Unit('gal (US)', 3.785411784),
      Unit('fl oz (US)', .0295735295625),
    ],
    defaultFrom: 'l',
    defaultTo: 'gal (US)',
    sample: '20',
  ),
  UnitCategory(
    id: 'speed',
    name: 'Speed',
    units: [
      Unit('m/s', 1),
      Unit('km/h', 1 / 3.6),
      Unit('mph', .44704),
      Unit('knot', 1852 / 3600),
    ],
    defaultFrom: 'km/h',
    defaultTo: 'mph',
    sample: '90',
  ),
  UnitCategory(
    id: 'time',
    name: 'Time',
    units: [
      Unit('s', 1),
      Unit('min', 60),
      Unit('h', 3600),
      Unit('day', 86400),
      Unit('week', 604800),
    ],
    defaultFrom: 'h',
    defaultTo: 'min',
    sample: '2.5',
  ),
  UnitCategory(
    id: 'data',
    name: 'Data',
    units: [
      Unit('B', 1),
      Unit('KB', 1024),
      Unit('MB', 1048576),
      Unit('GB', 1073741824),
      Unit('TB', 1099511627776),
    ],
    defaultFrom: 'GB',
    defaultTo: 'MB',
    sample: '1.5',
    note: '1 KB = 1024 B, the way Windows counts',
  ),
];

double _toCelsius(double v, String unit) => switch (unit) {
  '°F' => (v - 32) * 5 / 9,
  'K' => v - 273.15,
  _ => v,
};

double _fromCelsius(double c, String unit) => switch (unit) {
  '°F' => c * 9 / 5 + 32,
  'K' => c + 273.15,
  _ => c,
};

double convertUnits(
  UnitCategory category,
  double value,
  String from,
  String to,
) {
  if (category.isTemperature) {
    return _fromCelsius(_toCelsius(value, from), to);
  }
  return value * category.unit(from).factor / category.unit(to).factor;
}
