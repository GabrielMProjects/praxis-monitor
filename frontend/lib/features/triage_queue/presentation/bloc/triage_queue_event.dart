part of 'triage_queue_bloc.dart';

sealed class TriageQueueEvent extends Equatable {
  const TriageQueueEvent();
  @override
  List<Object?> get props => [];
}

/// Initial load + start listening to live updates.
final class QueueStarted extends TriageQueueEvent {
  const QueueStarted();
}

/// Manual retry after an error.
final class QueueRefreshRequested extends TriageQueueEvent {
  const QueueRefreshRequested();
}

final class DemoPatientAdded extends TriageQueueEvent {
  const DemoPatientAdded();
}

final class PatientUrgencyChanged extends TriageQueueEvent {
  const PatientUrgencyChanged(this.patient, this.urgency);
  final Patient patient;
  final Urgency urgency;
  @override
  List<Object?> get props => [patient, urgency];
}

final class PatientRemoved extends TriageQueueEvent {
  const PatientRemoved(this.patientId);
  final String patientId;
  @override
  List<Object?> get props => [patientId];
}

/// Internal: a snapshot arrived from the live stream.
final class QueueUpdated extends TriageQueueEvent {
  const QueueUpdated(this.patients);
  final List<Patient> patients;
  @override
  List<Object?> get props => [patients];
}

/// Internal: the live stream reported an error.
final class QueueStreamFailed extends TriageQueueEvent {
  const QueueStreamFailed(this.message);
  final String message;
  @override
  List<Object?> get props => [message];
}
