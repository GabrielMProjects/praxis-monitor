import 'dart:async';

import 'package:mocktail/mocktail.dart';
import 'package:praxis_monitor/core/network/realtime_client.dart';
import 'package:praxis_monitor/features/rooms/domain/entities/room.dart';
import 'package:praxis_monitor/features/rooms/domain/repositories/room_repository.dart';
import 'package:praxis_monitor/features/triage_queue/domain/entities/patient.dart';
import 'package:praxis_monitor/features/triage_queue/domain/repositories/patient_repository.dart';

class MockPatientRepository extends Mock implements PatientRepository {}

class MockRoomRepository extends Mock implements RoomRepository {}

/// Controllable realtime channel: tests push events and connection states by hand.
class FakeRealtimeClient implements RealtimeClient {
  final _events = StreamController<RealtimeEvent>.broadcast();
  final _status = StreamController<ConnectionStatus>.broadcast();
  ConnectionStatus _current = ConnectionStatus.disconnected;
  int connectCalls = 0;
  bool disposed = false;

  @override
  Stream<RealtimeEvent> get events => _events.stream;

  @override
  Stream<ConnectionStatus> get status =>
      replayCurrent(() => _current, _status.stream);

  @override
  ConnectionStatus get currentStatus => _current;

  @override
  void connect() => connectCalls++;

  @override
  Future<void> dispose() async {
    disposed = true;
    await _events.close();
    await _status.close();
  }

  void emitEvent(String type, Object? payload) =>
      _events.add(RealtimeEvent(type: type, payload: payload));

  void setStatus(ConnectionStatus status) {
    _current = status;
    _status.add(status);
  }
}

Patient patient(
  String id, {
  String? name,
  Urgency urgency = Urgency.medium,
  PatientStatus status = PatientStatus.waiting,
  int? position,
}) => Patient(
  id: id,
  name: name ?? 'Patient $id',
  urgency: urgency,
  arrivedAt: DateTime.utc(2026, 1, 1, 10, 0, 5),
  status: status,
  queuePosition: position,
);

Room room(
  String id, {
  RoomStatus status = RoomStatus.available,
  String? patientId,
  String? patientName,
}) => Room(
  id: id,
  name: 'Raum $id',
  status: status,
  patientId: patientId,
  patientName: patientName,
);

Map<String, dynamic> patientJson(
  String id, {
  String urgency = 'HIGH',
  String status = 'WAITING',
  int? position,
}) => {
  'id': id,
  'name': 'Patient $id',
  'urgency': urgency,
  'priority': 2,
  'arrivedAt': '2026-01-01T10:00:05Z',
  'status': status,
  'queuePosition': position,
};

Map<String, dynamic> roomJson(
  String id, {
  String status = 'AVAILABLE',
  String? patientId,
  String? patientName,
}) => {
  'id': id,
  'name': 'Raum $id',
  'status': status,
  'patientId': patientId,
  'patientName': patientName,
};
