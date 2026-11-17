import 'dart:async';

import '../../../../core/network/realtime_client.dart';
import '../../domain/entities/patient.dart';
import '../../domain/repositories/patient_repository.dart';
import '../datasources/patient_remote_data_source.dart';
import '../models/patient_model.dart';

class PatientRepositoryImpl implements PatientRepository {
  PatientRepositoryImpl({required this._remote, required this._realtime});

  final PatientRemoteDataSource _remote;
  final RealtimeClient _realtime;

  @override
  Future<List<Patient>> fetchQueue() => _remote.fetchQueue();

  @override
  Stream<List<Patient>> watchQueue() {
    late final StreamController<List<Patient>> controller;
    StreamSubscription<RealtimeEvent>? eventSub;
    StreamSubscription<ConnectionStatus>? statusSub;

    Future<void> resync() async {
      try {
        final queue = await _remote.fetchQueue();
        if (!controller.isClosed) controller.add(queue);
      } catch (e, st) {
        if (!controller.isClosed) controller.addError(e, st);
      }
    }

    controller = StreamController<List<Patient>>(
      onListen: () {
        eventSub = _realtime.events
            .where((e) => e.type == 'QUEUE_CHANGED')
            .listen((event) {
              try {
                final payload = event.payload as Map<String, dynamic>;
                controller.add(PatientModel.listFromJson(payload['patients']));
              } catch (_) {
                resync(); // unreadable event: ask the server for the truth
              }
            });
        // After every (re)connect the REST snapshot is authoritative. The very first
        // `connected` is also a harmless re-sync of the initial load.
        statusSub = _realtime.status
            .where((s) => s == ConnectionStatus.connected)
            .listen((_) => resync());
      },
      onCancel: () async {
        await eventSub?.cancel();
        await statusSub?.cancel();
      },
    );
    return controller.stream;
  }

  @override
  Future<Patient> createPatient({
    required String name,
    required Urgency urgency,
  }) => _remote.create(name, urgency);

  @override
  Future<Patient> updatePatient({
    required String id,
    required String name,
    required Urgency urgency,
  }) => _remote.update(id, name, urgency);

  @override
  Future<void> removePatient(String id) => _remote.remove(id);
}
