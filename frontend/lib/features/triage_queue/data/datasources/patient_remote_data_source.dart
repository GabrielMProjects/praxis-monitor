import '../../../../core/network/api_client.dart';
import '../../domain/entities/patient.dart';
import '../models/patient_model.dart';

/// REST access for patients and the queue.
class PatientRemoteDataSource {
  PatientRemoteDataSource(this._api);
  final ApiClient _api;

  Future<List<Patient>> fetchQueue() async =>
      PatientModel.listFromJson(await _api.get('/api/queue'));

  Future<Patient> create(String name, Urgency urgency) async =>
      PatientModel.fromJson(
        await _api.post(
          '/api/patients',
          body: PatientModel.toRequestJson(name: name, urgency: urgency),
        ),
      );

  Future<Patient> update(String id, String name, Urgency urgency) async =>
      PatientModel.fromJson(
        await _api.put(
          '/api/patients/$id',
          body: PatientModel.toRequestJson(name: name, urgency: urgency),
        ),
      );

  Future<void> remove(String id) async {
    await _api.delete('/api/patients/$id');
  }
}
