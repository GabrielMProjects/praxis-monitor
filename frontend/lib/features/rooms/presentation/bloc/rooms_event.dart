part of 'rooms_bloc.dart';

sealed class RoomsEvent extends Equatable {
  const RoomsEvent();
  @override
  List<Object?> get props => [];
}

final class RoomsStarted extends RoomsEvent {
  const RoomsStarted();
}

final class RoomsRefreshRequested extends RoomsEvent {
  const RoomsRefreshRequested();
}

final class RoomStatusChangeRequested extends RoomsEvent {
  const RoomStatusChangeRequested(this.roomId, this.status);
  final String roomId;
  final RoomStatus status;
  @override
  List<Object?> get props => [roomId, status];
}

final class PatientAssignmentRequested extends RoomsEvent {
  const PatientAssignmentRequested(this.roomId, this.patientId);
  final String roomId;
  final String patientId;
  @override
  List<Object?> get props => [roomId, patientId];
}

final class CallNextRequested extends RoomsEvent {
  const CallNextRequested(this.roomId);
  final String roomId;
  @override
  List<Object?> get props => [roomId];
}

final class TreatmentCompletionRequested extends RoomsEvent {
  const TreatmentCompletionRequested(this.roomId);
  final String roomId;
  @override
  List<Object?> get props => [roomId];
}

final class RoomsUpdated extends RoomsEvent {
  const RoomsUpdated(this.rooms);
  final List<Room> rooms;
  @override
  List<Object?> get props => [rooms];
}

final class RoomsStreamFailed extends RoomsEvent {
  const RoomsStreamFailed(this.message);
  final String message;
  @override
  List<Object?> get props => [message];
}
