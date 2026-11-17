import 'dart:math';

import 'patient.dart';

/// Creates purely synthetic patient names/urgencies for the "Demo-Patient hinzufügen" action.
class DemoPatientGenerator {
  DemoPatientGenerator([Random? random]) : _random = random ?? Random();

  final Random _random;
  int _counter = 0;

  static const _firstNames = [
    'Alex',
    'Sam',
    'Robin',
    'Kim',
    'Jules',
    'Charlie',
    'Maxi',
    'Toni',
    'Eli',
    'Noa',
  ];
  static const _lastNames = [
    'Beispiel',
    'Muster',
    'Testfall',
    'Demo',
    'Probe',
    'Platzhalter',
  ];

  ({String name, Urgency urgency}) next() {
    _counter++;
    final name =
        '${_firstNames[_random.nextInt(_firstNames.length)]} '
        '${_lastNames[_random.nextInt(_lastNames.length)]} #$_counter';
    return (
      name: name,
      urgency: Urgency.values[_random.nextInt(Urgency.values.length)],
    );
  }
}
