import '../../../../core/error/app_exception.dart';
import '../../domain/entities/patient.dart';

/// JSON <-> domain mapping for patients (same shape in REST and WebSocket payloads).
abstract final class PatientModel {
  static Patient fromJson(Object? json) {
    try {
      final map = json as Map<String, dynamic>;
      return Patient(
        id: map['id'] as String,
        name: map['name'] as String,
        urgency: Urgency.fromApi(map['urgency'] as String),
        arrivedAt: DateTime.parse(map['arrivedAt'] as String).toLocal(),
        status: PatientStatus.fromApi(map['status'] as String),
        queuePosition: map['queuePosition'] as int?,
      );
    } on FormatException {
      throw const ParseException();
    } on TypeError {
      throw const ParseException();
    }
  }

  static List<Patient> listFromJson(Object? json) {
    if (json is! List) throw const ParseException();
    return json.map(fromJson).toList(growable: false);
  }

  static Map<String, dynamic> toRequestJson({
    required String name,
    required Urgency urgency,
  }) => {'name': name, 'urgency': urgency.apiName};
}
