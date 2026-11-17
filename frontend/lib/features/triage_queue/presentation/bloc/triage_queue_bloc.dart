import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/error/app_exception.dart';
import '../../domain/entities/demo_patient_generator.dart';
import '../../domain/entities/patient.dart';
import '../../domain/repositories/patient_repository.dart';

part 'triage_queue_event.dart';
part 'triage_queue_state.dart';

/// Holds the sorted waiting queue. The server order is authoritative: the bloc never re-sorts.
class TriageQueueBloc extends Bloc<TriageQueueEvent, TriageQueueState> {
  TriageQueueBloc({required this._repository, DemoPatientGenerator? generator})
    : _generator = generator ?? DemoPatientGenerator(),
      super(const TriageQueueState()) {
    on<QueueStarted>(_onStarted);
    on<QueueRefreshRequested>(_onRefresh);
    on<DemoPatientAdded>(_onDemoPatientAdded);
    on<PatientUrgencyChanged>(_onUrgencyChanged);
    on<PatientRemoved>(_onRemoved);
    on<QueueUpdated>(
      (e, emit) => emit(
        state.copyWith(
          status: QueueStatus.loaded,
          patients: e.patients,
          clearError: true,
        ),
      ),
    );
    on<QueueStreamFailed>(_onStreamFailed);
  }

  final PatientRepository _repository;
  final DemoPatientGenerator _generator;
  StreamSubscription<List<Patient>>? _subscription;

  Future<void> _onStarted(
    QueueStarted event,
    Emitter<TriageQueueState> emit,
  ) async {
    await _subscription?.cancel();
    // Subscribe first so no server event is missed while the initial load is in flight.
    _subscription = _repository.watchQueue().listen(
      (patients) => add(QueueUpdated(patients)),
      onError: (Object e) => add(QueueStreamFailed(_message(e))),
    );
    await _load(emit);
  }

  Future<void> _onRefresh(
    QueueRefreshRequested event,
    Emitter<TriageQueueState> emit,
  ) => _load(emit);

  Future<void> _load(Emitter<TriageQueueState> emit) async {
    if (state.status != QueueStatus.loaded) {
      emit(state.copyWith(status: QueueStatus.loading, clearError: true));
    }
    try {
      final patients = await _repository.fetchQueue();
      emit(
        state.copyWith(
          status: QueueStatus.loaded,
          patients: patients,
          clearError: true,
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(status: QueueStatus.failure, errorMessage: _message(e)),
      );
    }
  }

  Future<void> _onDemoPatientAdded(
    DemoPatientAdded event,
    Emitter<TriageQueueState> emit,
  ) {
    final demo = _generator.next();
    return _action(
      emit,
      () => _repository.createPatient(name: demo.name, urgency: demo.urgency),
    );
  }

  Future<void> _onUrgencyChanged(
    PatientUrgencyChanged event,
    Emitter<TriageQueueState> emit,
  ) => _action(
    emit,
    () => _repository.updatePatient(
      id: event.patient.id,
      name: event.patient.name,
      urgency: event.urgency,
    ),
  );

  Future<void> _onRemoved(
    PatientRemoved event,
    Emitter<TriageQueueState> emit,
  ) => _action(emit, () => _repository.removePatient(event.patientId));

  /// Runs a user action; on success re-reads the queue via REST so the UI is correct even if the
  /// WebSocket is down. On failure only a transient action error is set; the list stays visible.
  Future<void> _action(
    Emitter<TriageQueueState> emit,
    Future<void> Function() run,
  ) async {
    try {
      await run();
      final patients = await _repository.fetchQueue();
      emit(
        state.copyWith(
          status: QueueStatus.loaded,
          patients: patients,
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

  void _onStreamFailed(
    QueueStreamFailed event,
    Emitter<TriageQueueState> emit,
  ) {
    if (state.patients.isEmpty) {
      emit(
        state.copyWith(
          status: QueueStatus.failure,
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
