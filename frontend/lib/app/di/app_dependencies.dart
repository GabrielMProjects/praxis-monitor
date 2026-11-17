import 'package:http/http.dart' as http;

import '../../core/network/api_client.dart';
import '../../core/network/realtime_client.dart';
import '../../core/network/stomp_realtime_client.dart';
import '../../features/rooms/data/datasources/room_remote_data_source.dart';
import '../../features/rooms/data/repositories/room_repository_impl.dart';
import '../../features/rooms/domain/repositories/room_repository.dart';
import '../../features/triage_queue/data/datasources/patient_remote_data_source.dart';
import '../../features/triage_queue/data/repositories/patient_repository_impl.dart';
import '../../features/triage_queue/domain/repositories/patient_repository.dart';

/// Composition root (manual constructor injection - no service locator needed at this size).
/// Owns exactly one HTTP client and ONE shared realtime client for the whole app.
class AppDependencies {
  AppDependencies({RealtimeClient? realtime, http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client(),
      realtime = realtime ?? StompRealtimeClient() {
    final api = ApiClient(client: _httpClient);
    patients = PatientRepositoryImpl(
      remote: PatientRemoteDataSource(api),
      realtime: this.realtime,
    );
    rooms = RoomRepositoryImpl(
      remote: RoomRemoteDataSource(api),
      realtime: this.realtime,
    );
  }

  final http.Client _httpClient;
  final RealtimeClient realtime;
  late final PatientRepository patients;
  late final RoomRepository rooms;

  Future<void> dispose() async {
    await realtime.dispose();
    _httpClient.close();
  }
}
