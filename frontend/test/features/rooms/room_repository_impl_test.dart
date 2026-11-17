import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:praxis_monitor/core/network/api_client.dart';
import 'package:praxis_monitor/core/network/realtime_client.dart';
import 'package:praxis_monitor/features/rooms/data/datasources/room_remote_data_source.dart';
import 'package:praxis_monitor/features/rooms/data/repositories/room_repository_impl.dart';
import 'package:praxis_monitor/features/rooms/domain/entities/room.dart';

import '../../support/fakes.dart';

void main() {
  late FakeRealtimeClient realtime;
  late List<http.Request> requests;
  late String roomsBody;
  late RoomRepositoryImpl repo;

  setUp(() {
    realtime = FakeRealtimeClient();
    requests = [];
    roomsBody = jsonEncode([roomJson('room-1'), roomJson('room-2')]);
    repo = RoomRepositoryImpl(
      remote: RoomRemoteDataSource(
        ApiClient(
          client: MockClient((r) async {
            requests.add(r);
            return r.url.path == '/api/rooms'
                ? http.Response(roomsBody, 200)
                : http.Response('{}', 200);
          }),
          baseUrl: 'http://test',
        ),
      ),
      realtime: realtime,
    );
  });

  tearDown(() => realtime.dispose());

  test('fetchRooms maps statuses', () async {
    roomsBody = jsonEncode([
      roomJson(
        'room-1',
        status: 'OCCUPIED',
        patientId: 'p',
        patientName: 'Demo',
      ),
    ]);
    final rooms = await repo.fetchRooms();
    expect(rooms.single.status, RoomStatus.occupied);
    expect(rooms.single.patientName, 'Demo');
  });

  test('action endpoints hit the documented URLs', () async {
    await repo.changeStatus('room-1', RoomStatus.cleaning);
    await repo.assignPatient('room-1', 'p1');
    await repo.callNext('room-2');
    await repo.completeTreatment('room-1');

    expect(requests.map((r) => '${r.method} ${r.url.path}'), [
      'PUT /api/rooms/room-1/status',
      'POST /api/rooms/room-1/assign',
      'POST /api/rooms/room-2/call-next',
      'POST /api/rooms/room-1/complete-treatment',
    ]);
    expect(jsonDecode(requests[0].body), {'status': 'CLEANING'});
    expect(jsonDecode(requests[1].body), {'patientId': 'p1'});
  });

  test('ROOM_STATUS_CHANGED updates exactly that room in the list', () async {
    final emitted = <List<Room>>[];
    final sub = repo.watchRooms().listen(emitted.add);
    realtime.setStatus(
      ConnectionStatus.connected,
    ); // initial sync fills the cache
    await pumpEventQueue();

    realtime.emitEvent(
      'ROOM_STATUS_CHANGED',
      roomJson('room-2', status: 'CLEANING'),
    );
    await pumpEventQueue();

    expect(emitted.last.map((r) => r.status), [
      RoomStatus.available,
      RoomStatus.cleaning,
    ]);
    await sub.cancel();
  });

  test(
    'reconnect re-syncs rooms from REST (stale local state is replaced)',
    () async {
      final emitted = <List<Room>>[];
      final sub = repo.watchRooms().listen(emitted.add);
      realtime.setStatus(ConnectionStatus.connected);
      await pumpEventQueue();

      realtime.setStatus(ConnectionStatus.disconnected);
      roomsBody = jsonEncode([
        roomJson('room-1', status: 'CLEANING'),
        roomJson('room-2'),
      ]); // changed while offline
      realtime.setStatus(ConnectionStatus.connected);
      await pumpEventQueue();

      expect(emitted.last.first.status, RoomStatus.cleaning);
      await sub.cancel();
    },
  );

  test('update for an unknown room triggers a REST re-sync', () async {
    final emitted = <List<Room>>[];
    final sub = repo.watchRooms().listen(emitted.add);
    roomsBody = jsonEncode([roomJson('room-9')]);
    realtime.emitEvent('ROOM_STATUS_CHANGED', roomJson('room-9'));
    await pumpEventQueue();
    expect(emitted.single.single.id, 'room-9');
    await sub.cancel();
  });
}
