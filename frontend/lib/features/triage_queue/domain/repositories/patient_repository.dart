import '../entities/patient.dart';

abstract interface class PatientRepository {
  /// Waiting queue, sorted by the backend (next patient first).
  Future<List<Patient>> fetchQueue();

  /// Live queue: emits the full sorted queue on every server change and after every
  /// reconnect (REST re-sync). Errors from a failed re-sync are delivered as stream errors.
  Stream<List<Patient>> watchQueue();

  Future<Patient> createPatient({
    required String name,
    required Urgency urgency,
  });

  Future<Patient> updatePatient({
    required String id,
    required String name,
    required Urgency urgency,
  });

  Future<void> removePatient(String id);
}
