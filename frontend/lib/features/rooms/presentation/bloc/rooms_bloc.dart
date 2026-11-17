import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/error/app_exception.dart';
import '../../domain/entities/room.dart';
import '../../domain/repositories/room_repository.dart';

part 'rooms_event.dart';
part 'rooms_state.dart';

class RoomsBloc extends Bloc<RoomsEvent, RoomsState> {
  RoomsBloc({required this._repository}) : super(const RoomsState()) {
    on<RoomsStarted>(_onStarted);
    on<RoomsRefreshRequested>((e, emit) => _load(emit));
    on<RoomStatusChangeRequested>(
      (e, emit) =>
          _action(emit, () => _repository.changeStatus(e.roomId, e.status)),
    );
    on<PatientAssignmentRequested>(
      (e, emit) =>
          _action(emit, () => _repository.assignPatient(e.roomId, e.patientId)),
    );
    on<CallNextRequested>(
      (e, emit) => _action(emit, () => _repository.callNext(e.roomId)),
    );
    on<TreatmentCompletionRequested>(
      (e, emit) => _action(emit, () => _repository.completeTreatment(e.roomId)),
    );
    on<RoomsUpdated>(
      (e, emit) => emit(
        state.copyWith(
          status: RoomsStatus.loaded,
          rooms: e.rooms,
          clearError: true,
        ),
      ),
    );
    on<RoomsStreamFailed>(_onStreamFailed);
  }

  final RoomRepository _repository;
  StreamSubscription<List<Room>>? _subscription;

  Future<void> _onStarted(RoomsStarted event, Emitter<RoomsState> emit) async {
    await _subscription?.cancel();
    _subscription = _repository.watchRooms().listen(
      (rooms) => add(RoomsUpdated(rooms)),
      onError: (Object e) => add(RoomsStreamFailed(_message(e))),
    );
    await _load(emit);
  }

  Future<void> _load(Emitter<RoomsState> emit) async {
    if (state.status != RoomsStatus.loaded) {
      emit(state.copyWith(status: RoomsStatus.loading, clearError: true));
    }
    try {
      emit(
        state.copyWith(
          status: RoomsStatus.loaded,
          rooms: await _repository.fetchRooms(),
          clearError: true,
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(status: RoomsStatus.failure, errorMessage: _message(e)),
      );
    }
  }

  /// Runs a user action, then re-reads the rooms via REST (correct even without WebSocket).
  Future<void> _action(
    Emitter<RoomsState> emit,
    Future<void> Function() run,
  ) async {
    try {
      await run();
      emit(
        state.copyWith(
          status: RoomsStatus.loaded,
          rooms: await _repository.fetchRooms(),
          clearError: true,
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          actionErrorId: state.actionErrorId + 1,
          actionError: _message(e),
        ),
      );
    }
  }

  void _onStreamFailed(RoomsStreamFailed event, Emitter<RoomsState> emit) {
    if (state.rooms.isEmpty) {
      emit(
        state.copyWith(
          status: RoomsStatus.failure,
          errorMessage: event.message,
        ),
      );
    } else {
      emit(
        state.copyWith(
          actionErrorId: state.actionErrorId + 1,
          actionError: event.message,
        ),
      );
    }
  }

  String _message(Object e) =>
      e is AppException ? e.message : 'Unerwarteter Fehler.';

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    return super.close();
  }
}
