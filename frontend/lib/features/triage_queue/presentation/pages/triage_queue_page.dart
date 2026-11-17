import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../shared/widgets/state_views.dart';
import '../bloc/triage_queue_bloc.dart';
import '../widgets/assign_room_dialog.dart';
import '../widgets/patient_tile.dart';

/// Waiting-queue section of the dashboard (header with demo action + live list).
class TriageQueuePage extends StatelessWidget {
  const TriageQueuePage({
    super.key,
    required this.assignableRooms,
    required this.onAssign,
  });

  /// Rooms currently available for a patient (provided by the dashboard; this feature knows no rooms feature).
  final List<RoomOption> assignableRooms;

  /// Called when the user picked a room for a patient.
  final void Function(String roomId, String patientId) onAssign;

  @override
  Widget build(BuildContext context) {
    return BlocListener<TriageQueueBloc, TriageQueueState>(
      listenWhen: (p, c) => p.actionErrorId != c.actionErrorId,
      listener: (context, state) {
        if (state.actionError != null) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(state.actionError!)));
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              runSpacing: 8,
              children: [
                BlocBuilder<TriageQueueBloc, TriageQueueState>(
                  builder: (context, state) => Semantics(
                    header: true,
                    liveRegion:
                        true, // screen readers announce queue size changes
                    child: Text(
                      'Warteschlange (${state.patients.length})',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ),
                FilledButton.icon(
                  onPressed: () => context.read<TriageQueueBloc>().add(
                    const DemoPatientAdded(),
                  ),
                  icon: const Icon(Icons.person_add_alt_1),
                  label: const Text('Demo-Patient hinzufügen'),
                ),
              ],
            ),
          ),
          Expanded(
            child: _QueueBody(
              assignableRooms: assignableRooms,
              onAssign: onAssign,
            ),
          ),
        ],
      ),
    );
  }
}

class _QueueBody extends StatelessWidget {
  const _QueueBody({required this.assignableRooms, required this.onAssign});

  final List<RoomOption> assignableRooms;
  final void Function(String roomId, String patientId) onAssign;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TriageQueueBloc, TriageQueueState>(
      builder: (context, state) {
        switch (state.status) {
          case QueueStatus.initial:
          case QueueStatus.loading:
            return const LoadingView(message: 'Lade Warteschlange …');
          case QueueStatus.failure:
            return ErrorView(
              message:
                  state.errorMessage ??
                  'Warteschlange konnte nicht geladen werden.',
              onRetry: () => context.read<TriageQueueBloc>().add(
                const QueueRefreshRequested(),
              ),
            );
          case QueueStatus.loaded:
            if (state.patients.isEmpty) {
              return const EmptyView(
                icon: Icons.event_seat_outlined,
                message: 'Keine wartenden Patienten',
                hint: 'Mit „Demo-Patient hinzufügen“ einen synthetischen Patienten anlegen.',
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              itemCount: state.patients.length,
              itemBuilder: (context, i) {
                final patient = state.patients[i];
                return PatientTile(
                  key: ValueKey(patient.id),
                  patient: patient,
                  canAssign: assignableRooms.isNotEmpty,
                  onUrgencyChanged: (u) => context.read<TriageQueueBloc>().add(
                    PatientUrgencyChanged(patient, u),
                  ),
                  onRemove: () => context.read<TriageQueueBloc>().add(
                    PatientRemoved(patient.id),
                  ),
                  onAssign: () async {
                    final roomId = await showAssignRoomDialog(
                      context,
                      patientName: patient.name,
                      rooms: assignableRooms,
                    );
                    if (roomId != null) onAssign(roomId, patient.id);
                  },
                );
              },
            );
        }
      },
    );
  }
}
