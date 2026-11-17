import 'dart:async';

import '../../../../core/network/realtime_client.dart';
import '../../domain/entities/room.dart';
import '../../domain/repositories/room_repository.dart';
import '../datasources/room_remote_data_source.dart';
import '../models/room_model.dart';

class RoomRepositoryImpl implements RoomRepository {
  RoomRepositoryImpl({required this._remote, required this._realtime});

  final RoomRemoteDataSource _remote;
  final RealtimeClient _realtime;

  @override
  Future<List<Room>> fetchRooms() => _remote.fetchRooms();

  @override
  Stream<List<Room>> watchRooms() {
    late final StreamController<List<Room>> controller;
    StreamSubscription<RealtimeEvent>? eventSub;
    StreamSubscription<ConnectionStatus>? statusSub;
    var rooms = <Room>[];

    Future<void> resync() async {
      try {
        rooms = (await _remote.fetchRooms()).toList();
        if (!controller.isClosed) controller.add(List.unmodifiable(rooms));
      } catch (e, st) {
        if (!controller.isClosed) controller.addError(e, st);
      }
    }

    controller = StreamController<List<Room>>(
      onListen: () {
        eventSub = _realtime.events
            .where((e) => e.type == 'ROOM_STATUS_CHANGED')
            .listen((event) {
              try {
                final updated = RoomModel.fromJson(event.payload);
                final index = rooms.indexWhere((r) => r.id == updated.id);
                if (index < 0) {
                  resync(); // unknown room -> take the server's list
                  return;
                }
                rooms = [...rooms]..[index] = updated;
                controller.add(List.unmodifiable(rooms));
              } catch (_) {
                resync();
              }
            });
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
  Future<void> changeStatus(String roomId, RoomStatus status) =>
      _remote.changeStatus(roomId, status);

  @override
  Future<void> assignPatient(String roomId, String patientId) =>
      _remote.assign(roomId, patientId);

  @override
  Future<void> callNext(String roomId) => _remote.callNext(roomId);

  @override
  Future<void> completeTreatment(String roomId) =>
      _remote.completeTreatment(roomId);
}
