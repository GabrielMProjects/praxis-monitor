import '../../../../core/network/api_client.dart';
import '../../domain/entities/room.dart';
import '../models/room_model.dart';

class RoomRemoteDataSource {
  RoomRemoteDataSource(this._api);
  final ApiClient _api;

  Future<List<Room>> fetchRooms() async =>
      RoomModel.listFromJson(await _api.get('/api/rooms'));

  Future<void> changeStatus(String roomId, RoomStatus status) async {
    await _api.put(
      '/api/rooms/$roomId/status',
      body: {'status': status.apiName},
    );
  }

  Future<void> assign(String roomId, String patientId) async {
    await _api.post(
      '/api/rooms/$roomId/assign',
      body: {'patientId': patientId},
    );
  }

  Future<void> callNext(String roomId) async {
    await _api.post('/api/rooms/$roomId/call-next');
  }

  Future<void> completeTreatment(String roomId) async {
    await _api.post('/api/rooms/$roomId/complete-treatment');
  }
}
