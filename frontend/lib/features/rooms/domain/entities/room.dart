import 'package:equatable/equatable.dart';

enum RoomStatus {
  available('Verfügbar'),
  occupied('Belegt'),
  cleaning('Reinigung');

  const RoomStatus(this.label);
  final String label;

  String get apiName => name.toUpperCase();

  static RoomStatus fromApi(String value) => RoomStatus.values.firstWhere(
    (s) => s.apiName == value,
    orElse: () => throw FormatException('Unknown room status $value'),
  );
}

class Room extends Equatable {
  const Room({
    required this.id,
    required this.name,
    required this.status,
    this.patientId,
    this.patientName,
  });

  final String id;
  final String name;
  final RoomStatus status;
  final String? patientId;
  final String? patientName;

  @override
  List<Object?> get props => [id, name, status, patientId, patientName];
}
