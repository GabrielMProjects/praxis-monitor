// Automated end-to-end test: REAL Spring Boot jar (own process, own port) + the REAL Flutter data stack
// (ApiClient, repositories, StompRealtimeClient, BLoCs) over real HTTP and a real WebSocket.
// Includes a genuine connection loss (backend process killed) and automatic reconnect + REST re-sync.
//
// Run: scripts\e2e.ps1   (builds the jar, then `flutter test e2e/praxis_e2e_test.dart`)
// Env: E2E_BACKEND_JAR (required), E2E_PORT (default 18080), JAVA_BIN (default `java`)
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:praxis_monitor/core/error/app_exception.dart';
import 'package:praxis_monitor/core/network/api_client.dart';
import 'package:praxis_monitor/core/network/realtime_client.dart';
import 'package:praxis_monitor/core/network/stomp_realtime_client.dart';
import 'package:praxis_monitor/features/rooms/data/datasources/room_remote_data_source.dart';
import 'package:praxis_monitor/features/rooms/data/repositories/room_repository_impl.dart';
import 'package:praxis_monitor/features/rooms/domain/entities/room.dart';
import 'package:praxis_monitor/features/rooms/presentation/bloc/rooms_bloc.dart';
import 'package:praxis_monitor/features/triage_queue/data/datasources/patient_remote_data_source.dart';
import 'package:praxis_monitor/features/triage_queue/data/repositories/patient_repository_impl.dart';
import 'package:praxis_monitor/features/triage_queue/domain/entities/patient.dart';
import 'package:praxis_monitor/features/triage_queue/presentation/bloc/triage_queue_bloc.dart';

final _jar = Platform.environment['E2E_BACKEND_JAR'];
final _port = int.parse(Platform.environment['E2E_PORT'] ?? '18080');
final _java = Platform.environment['JAVA_BIN'] ?? 'java';

Process? _backend;

Future<void> _startBackend() async {
  _backend = await Process.start(_java, ['-jar', _jar!, '--server.port=$_port']);
  _backend!.stdout.drain<void>();
  _backend!.stderr.drain<void>();
  final client = http.Client();
  try {
    for (var i = 0; i < 90; i++) {
      try {
        final r = await client.get(Uri.parse('http://localhost:$_port/api/rooms'));
        if (r.statusCode == 200) return;
      } catch (_) {}
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    throw StateError('backend did not become ready');
  } finally {
    client.close();
  }
}

Future<void> _stopBackend() async {
  final p = _backend;
  if (p == null) return;
  p.kill();
  await p.exitCode.timeout(const Duration(seconds: 15));
  _backend = null;
}

Future<void> waitFor(bool Function() condition, {String what = 'condition', Duration timeout = const Duration(seconds: 20)}) async {
  final end = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(end)) fail('Timed out waiting for: $what');
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

void main() {
  late http.Client httpClient;
  late StompRealtimeClient realtime;
  late PatientRepositoryImpl patients;
  late RoomRepositoryImpl rooms;
  late TriageQueueBloc queueBloc;
  late RoomsBloc roomsBloc;

  // Latest values seen on the LIVE streams (WebSocket + reconnect re-sync), not via direct REST calls.
  var liveQueue = <Patient>[];
  var liveRooms = <Room>[];
  var queueMessages = 0;
  final statuses = <ConnectionStatus>[];
  final subs = <StreamSubscription<dynamic>>[];

  List<String> names(List<Patient> l) => l.map((p) => p.name).toList();

  setUpAll(() async {
    expect(_jar, isNotNull, reason: 'set E2E_BACKEND_JAR (use scripts/e2e.ps1)');
    await _startBackend();

    httpClient = http.Client();
    final api = ApiClient(client: httpClient, baseUrl: 'http://localhost:$_port');
    realtime = StompRealtimeClient(url: 'ws://localhost:$_port/ws', reconnectDelay: const Duration(milliseconds: 500));
    patients = PatientRepositoryImpl(remote: PatientRemoteDataSource(api), realtime: realtime);
    rooms = RoomRepositoryImpl(remote: RoomRemoteDataSource(api), realtime: realtime);
    queueBloc = TriageQueueBloc(repository: patients);
    roomsBloc = RoomsBloc(repository: rooms);

    subs.add(realtime.status.listen(statuses.add));
    subs.add(patients.watchQueue().listen((q) {
      liveQueue = q;
      queueMessages++;
    }));
    subs.add(rooms.watchRooms().listen((r) => liveRooms = r));

    realtime.connect();
    queueBloc.add(const QueueStarted());
    roomsBloc.add(const RoomsStarted());
  });

  tearDownAll(() async {
    for (final s in subs) {
      await s.cancel();
    }
    await queueBloc.close();
    await roomsBloc.close();
    await realtime.dispose();
    httpClient.close();
    await _stopBackend();
  });

  test('1. connects over a real WebSocket and the BLoCs load the initial REST state', () async {
    await waitFor(() => realtime.currentStatus == ConnectionStatus.connected, what: 'WebSocket connected');
    await waitFor(() => queueBloc.state.status == QueueStatus.loaded && roomsBloc.state.status == RoomsStatus.loaded, what: 'initial load');
    expect(roomsBloc.state.rooms, hasLength(4));
    expect(roomsBloc.state.rooms.every((r) => r.status == RoomStatus.available), isTrue);
    expect(queueBloc.state.patients, isEmpty);
  });

  test('2. created patients arrive sorted by urgency, then arrival (FIFO) - via WebSocket', () async {
    await patients.createPatient(name: 'e2e-low-1', urgency: Urgency.low);
    await patients.createPatient(name: 'e2e-crit', urgency: Urgency.critical);
    await patients.createPatient(name: 'e2e-low-2', urgency: Urgency.low);

    await waitFor(() => liveQueue.length == 3, what: 'live queue has 3 patients');
    expect(names(liveQueue), ['e2e-crit', 'e2e-low-1', 'e2e-low-2']);
    expect(liveQueue.map((p) => p.queuePosition), [1, 2, 3]);
    await waitFor(() => names(queueBloc.state.patients).length == 3, what: 'bloc state');
    expect(names(queueBloc.state.patients), ['e2e-crit', 'e2e-low-1', 'e2e-low-2']);
  });

  test('3. urgency change reorders keeping the original arrival rank; removal updates the queue', () async {
    final low2 = liveQueue.firstWhere((p) => p.name == 'e2e-low-2');
    await patients.updatePatient(id: low2.id, name: low2.name, urgency: Urgency.high);
    await waitFor(() => names(liveQueue).first == 'e2e-crit' && names(liveQueue)[1] == 'e2e-low-2', what: 'reordered');
    expect(names(liveQueue), ['e2e-crit', 'e2e-low-2', 'e2e-low-1']);

    final low1 = liveQueue.firstWhere((p) => p.name == 'e2e-low-1');
    await patients.removePatient(low1.id);
    await waitFor(() => liveQueue.length == 2, what: 'removal');
    expect(names(liveQueue), ['e2e-crit', 'e2e-low-2']);
  });

  test('4. call next and explicit assignment occupy rooms; forbidden transitions give 409', () async {
    roomsBloc.add(const CallNextRequested('room-1'));
    await waitFor(() => liveRooms.any((r) => r.id == 'room-1' && r.status == RoomStatus.occupied), what: 'room-1 occupied');
    expect(liveRooms.firstWhere((r) => r.id == 'room-1').patientName, 'e2e-crit');
    await waitFor(() => names(liveQueue).length == 1, what: 'queue shrank');
    expect(names(liveQueue), ['e2e-low-2']);

    // occupied room refuses another patient; a room that is not occupied cannot complete a treatment
    await expectLater(rooms.assignPatient('room-1', liveQueue.single.id), throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 409)));
    await expectLater(rooms.completeTreatment('room-3'), throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 409)));

    await rooms.assignPatient('room-2', liveQueue.single.id);
    await waitFor(() => liveQueue.isEmpty && liveRooms.any((r) => r.id == 'room-2' && r.status == RoomStatus.occupied), what: 'room-2 occupied');
  });

  test('5. completing a treatment sends the room to CLEANING; it becomes AVAILABLE only explicitly', () async {
    await rooms.completeTreatment('room-1');
    await waitFor(() => liveRooms.any((r) => r.id == 'room-1' && r.status == RoomStatus.cleaning), what: 'cleaning');
    expect(liveRooms.firstWhere((r) => r.id == 'room-1').patientId, isNull);

    await rooms.changeStatus('room-1', RoomStatus.available);
    await waitFor(() => liveRooms.any((r) => r.id == 'room-1' && r.status == RoomStatus.available), what: 'available again');
  });

  test('6. real connection loss: status goes disconnected; after restart it reconnects and re-syncs via REST', () async {
    expect(roomsBloc.state.rooms.any((r) => r.status == RoomStatus.occupied), isTrue, reason: 'state exists before the outage');

    await _stopBackend();
    await waitFor(() => realtime.currentStatus == ConnectionStatus.disconnected, what: 'disconnected after backend died', timeout: const Duration(seconds: 40));

    await _startBackend(); // fresh in-memory state: no patients, all rooms available
    await waitFor(() => realtime.currentStatus == ConnectionStatus.connected, what: 'automatic reconnect', timeout: const Duration(seconds: 40));

    // the REST snapshot after reconnect replaced the stale state (no manual reload)
    await waitFor(() => liveRooms.every((r) => r.status == RoomStatus.available) && liveRooms.length == 4, what: 're-synced rooms');
    await waitFor(() => liveQueue.isEmpty, what: 're-synced queue');
    expect(statuses, containsAllInOrder([ConnectionStatus.connected, ConnectionStatus.disconnected, ConnectionStatus.connected]));
  });

  test('7. after reconnect events arrive exactly once (no duplicate subscriptions)', () async {
    final before = queueMessages;
    await patients.createPatient(name: 'e2e-after-reconnect', urgency: Urgency.medium);
    await waitFor(() => liveQueue.length == 1, what: 'event after reconnect');
    await Future<void>.delayed(const Duration(seconds: 1)); // a duplicate subscription would deliver a 2nd message
    expect(queueMessages - before, 1);
    expect(names(liveQueue), ['e2e-after-reconnect']);
  });
}
