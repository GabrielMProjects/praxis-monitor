import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:praxis_monitor/core/error/app_exception.dart';
import 'package:praxis_monitor/core/network/api_client.dart';
import 'package:praxis_monitor/core/network/realtime_client.dart';
import 'package:praxis_monitor/features/triage_queue/data/datasources/patient_remote_data_source.dart';
import 'package:praxis_monitor/features/triage_queue/data/repositories/patient_repository_impl.dart';
import 'package:praxis_monitor/features/triage_queue/domain/entities/patient.dart';

import '../../support/fakes.dart';

void main() {
  late FakeRealtimeClient realtime;
  late int queueRequests;
  late http.Response Function(http.Request) respond;
  late PatientRepositoryImpl repo;

  setUp(() {
    realtime = FakeRealtimeClient();
    queueRequests = 0;
    respond = (r) => http.Response('[]', 200);
    final api = ApiClient(
      client: MockClient((r) async {
        if (r.method == 'GET' && r.url.path == '/api/queue') queueRequests++;
        return respond(r);
      }),
      baseUrl: 'http://test',
    );
    repo = PatientRepositoryImpl(
      remote: PatientRemoteDataSource(api),
      realtime: realtime,
    );
  });

  tearDown(() => realtime.dispose());

  test('fetchQueue maps JSON to entities in server order', () async {
    respond = (r) => http.Response(
      '[${_json(patientJson('a', urgency: 'CRITICAL', position: 1))},${_json(patientJson('b', urgency: 'LOW', position: 2))}]',
      200,
    );

    final queue = await repo.fetchQueue();

    expect(queue.map((p) => p.id), ['a', 'b']);
    expect(queue.first.urgency, Urgency.critical);
    expect(queue.first.queuePosition, 1);
    expect(queue.first.arrivedAt.toUtc(), DateTime.utc(2026, 1, 1, 10, 0, 5));
  });

  test('createPatient posts the API enum name', () async {
    late String body;
    respond = (r) {
      body = r.body;
      return http.Response(_json(patientJson('n')), 201);
    };
    final created = await repo.createPatient(
      name: 'Demo',
      urgency: Urgency.critical,
    );
    expect(body, contains('"urgency":"CRITICAL"'));
    expect(created.id, 'n');
  });

  test('unknown enum value in a response becomes ParseException', () {
    respond = (r) =>
        http.Response('[${_json(patientJson('a', urgency: 'NORMAL'))}]', 200);
    expect(repo.fetchQueue(), throwsA(isA<ParseException>()));
  });

  test(
    'watchQueue emits the sorted queue carried by QUEUE_CHANGED events',
    () async {
      final emitted = <List<Patient>>[];
      final sub = repo.watchQueue().listen(emitted.add);
      await pumpEventQueue();

      realtime.emitEvent('QUEUE_CHANGED', {
        'patients': [
          patientJson('x', urgency: 'CRITICAL', position: 1),
          patientJson('y', position: 2),
        ],
      });
      await pumpEventQueue();

      expect(emitted, hasLength(1));
      expect(emitted.single.map((p) => p.id), ['x', 'y']);
      await sub.cancel();
    },
  );

  test('other event types are ignored', () async {
    final emitted = <List<Patient>>[];
    final sub = repo.watchQueue().listen(emitted.add);
    realtime.emitEvent('ROOM_STATUS_CHANGED', roomJson('r1'));
    realtime.emitEvent('PATIENT_ADDED', patientJson('p'));
    await pumpEventQueue();
    expect(emitted, isEmpty);
    await sub.cancel();
  });

  test('every (re)connect re-syncs the queue via REST', () async {
    respond = (r) =>
        http.Response('[${_json(patientJson('fresh', position: 1))}]', 200);
    final emitted = <List<Patient>>[];
    final sub = repo.watchQueue().listen(emitted.add);

    realtime.setStatus(ConnectionStatus.connected);
    await pumpEventQueue();
    expect(queueRequests, 1);
    expect(emitted.last.single.id, 'fresh');

    // connection lost -> nothing happens; restored -> REST snapshot again
    realtime.setStatus(ConnectionStatus.disconnected);
    await pumpEventQueue();
    expect(queueRequests, 1);

    respond = (r) => http.Response(
      '[${_json(patientJson('after-outage', position: 1))}]',
      200,
    );
    realtime.setStatus(ConnectionStatus.connected);
    await pumpEventQueue();
    expect(queueRequests, 2);
    expect(emitted.last.single.id, 'after-outage');
    await sub.cancel();
  });

  test(
    'failed re-sync is delivered as a stream error, stream stays usable',
    () async {
      respond = (r) => http.Response('{"message":"boom"}', 500);
      final errors = <Object>[];
      final emitted = <List<Patient>>[];
      final sub = repo.watchQueue().listen(emitted.add, onError: errors.add);

      realtime.setStatus(ConnectionStatus.connected);
      await pumpEventQueue();
      expect(errors.single, isA<ApiException>());

      realtime.emitEvent('QUEUE_CHANGED', {
        'patients': [patientJson('z', position: 1)],
      });
      await pumpEventQueue();
      expect(emitted.single.single.id, 'z');
      await sub.cancel();
    },
  );

  test('malformed QUEUE_CHANGED payload triggers a REST re-sync instead of crashing', () async {
    respond = (r) =>
        http.Response('[${_json(patientJson('truth', position: 1))}]', 200);
    final emitted = <List<Patient>>[];
    final sub = repo.watchQueue().listen(emitted.add);

    realtime.emitEvent('QUEUE_CHANGED', {'patients': 'garbage'});
    await pumpEventQueue();

    expect(queueRequests, 1);
    expect(emitted.single.single.id, 'truth');
    await sub.cancel();
  });

  test('cancelling the stream releases realtime subscriptions', () async {
    final sub = repo.watchQueue().listen((_) {});
    await sub.cancel();
    realtime.setStatus(ConnectionStatus.connected);
    realtime.emitEvent('QUEUE_CHANGED', {'patients': []});
    await pumpEventQueue();
    expect(queueRequests, 0);
  });
}

String _json(Map<String, dynamic> map) => jsonEncode(map);
