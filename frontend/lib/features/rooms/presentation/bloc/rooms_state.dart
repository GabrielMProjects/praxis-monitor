part of 'rooms_bloc.dart';

enum RoomsStatus { initial, loading, loaded, failure }

final class RoomsState extends Equatable {
  const RoomsState({
    this.status = RoomsStatus.initial,
    this.rooms = const [],
    this.errorMessage,
    this.actionErrorId = 0,
    this.actionError,
  });

  final RoomsStatus status;
  final List<Room> rooms;
  final String? errorMessage;
  final int actionErrorId;
  final String? actionError;

  Iterable<Room> get availableRooms =>
      rooms.where((r) => r.status == RoomStatus.available);

  RoomsState copyWith({
    RoomsStatus? status,
    List<Room>? rooms,
    String? errorMessage,
    bool clearError = false,
    int? actionErrorId,
    String? actionError,
  }) => RoomsState(
    status: status ?? this.status,
    rooms: rooms ?? this.rooms,
    errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    actionErrorId: actionErrorId ?? this.actionErrorId,
    actionError: actionError ?? this.actionError,
  );

  @override
  List<Object?> get props => [
    status,
    rooms,
    errorMessage,
    actionErrorId,
    actionError,
  ];
}
