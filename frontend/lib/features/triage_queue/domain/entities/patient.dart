import 'package:equatable/equatable.dart';

/// Demo urgency levels (technical demonstration, not clinically validated).
enum Urgency {
  critical(1, 'Kritisch'),
  high(2, 'Hoch'),
  medium(3, 'Mittel'),
  low(4, 'Niedrig');

  const Urgency(this.priority, this.label);
  final int priority;
  final String label;

  /// Backend enum name, e.g. `CRITICAL`.
  String get apiName => name.toUpperCase();

  static Urgency fromApi(String value) => Urgency.values.firstWhere(
    (u) => u.apiName == value,
    orElse: () => throw FormatException('Unknown urgency $value'),
  );
}

enum PatientStatus {
  waiting('Wartet'),
  inTreatment('In Behandlung'),
  completed('Abgeschlossen');

  const PatientStatus(this.label);
  final String label;

  static PatientStatus fromApi(String value) => switch (value) {
    'WAITING' => PatientStatus.waiting,
    'IN_TREATMENT' => PatientStatus.inTreatment,
    'COMPLETED' => PatientStatus.completed,
    _ => throw FormatException('Unknown patient status $value'),
  };
}

class Patient extends Equatable {
  const Patient({
    required this.id,
    required this.name,
    required this.urgency,
    required this.arrivedAt,
    required this.status,
    this.queuePosition,
  });

  final String id;
  final String name;
  final Urgency urgency;
  final DateTime arrivedAt;
  final PatientStatus status;

  /// 1-based position in the waiting queue (null when not waiting).
  final int? queuePosition;

  @override
  List<Object?> get props => [
    id,
    name,
    urgency,
    arrivedAt,
    status,
    queuePosition,
  ];
}
