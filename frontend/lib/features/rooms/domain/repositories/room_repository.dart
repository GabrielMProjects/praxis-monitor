import '../entities/room.dart';

abstract interface class RoomRepository {
  Future<List<Room>> fetchRooms();

  /// Live room list: emits the full list after every server change and after every reconnect
  /// (REST re-sync). Failed re-syncs arrive as stream errors.
  Stream<List<Room>> watchRooms();

  /// AVAILABLE -> CLEANING or CLEANING -> AVAILABLE.
  Future<void> changeStatus(String roomId, RoomStatus status);

  Future<void> assignPatient(String roomId, String patientId);

  /// Calls the head of the queue into the room.
  Future<void> callNext(String roomId);

  /// Patient COMPLETED, room OCCUPIED -> CLEANING.
  Future<void> completeTreatment(String roomId);
}
