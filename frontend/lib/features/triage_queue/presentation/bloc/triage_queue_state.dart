part of 'triage_queue_bloc.dart';

enum QueueStatus { initial, loading, loaded, failure }

final class TriageQueueState extends Equatable {
  const TriageQueueState({
    this.status = QueueStatus.initial,
    this.patients = const [],
    this.errorMessage,
    this.actionErrorId = 0,
    this.actionError,
  });

  final QueueStatus status;
  final List<Patient> patients;

  /// Load failure (shown instead of the list when there is no data yet).
  final String? errorMessage;

  /// Failure of a user action (e.g. 409); shown as a transient message. The id makes
  /// repeated identical errors distinct for listeners.
  final int actionErrorId;
  final String? actionError;

  TriageQueueState copyWith({
    QueueStatus? status,
    List<Patient>? patients,
    String? errorMessage,
    bool clearError = false,
    int? actionErrorId,
    String? actionError,
  }) => TriageQueueState(
    status: status ?? this.status,
    patients: patients ?? this.patients,
    errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    actionErrorId: actionErrorId ?? this.actionErrorId,
    actionError: actionError ?? this.actionError,
  );

  @override
  List<Object?> get props => [
    status,
    patients,
    errorMessage,
    actionErrorId,
    actionError,
  ];
}
