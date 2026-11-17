import '../../../../core/error/app_exception.dart';
import '../../domain/entities/room.dart';

abstract final class RoomModel {
  static Room fromJson(Object? json) {
    try {
      final map = json as Map<String, dynamic>;
      return Room(
        id: map['id'] as String,
        name: map['name'] as String,
        status: RoomStatus.fromApi(map['status'] as String),
        patientId: map['patientId'] as String?,
        patientName: map['patientName'] as String?,
      );
    } on FormatException {
      throw const ParseException();
    } on TypeError {
      throw const ParseException();
    }
  }

  static List<Room> listFromJson(Object? json) {
    if (json is! List) throw const ParseException();
    return json.map(fromJson).toList(growable: false);
  }
}
