import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../shared/widgets/state_views.dart';
import '../../domain/entities/room.dart';
import '../bloc/rooms_bloc.dart';
import '../widgets/room_card.dart';

/// Treatment-room section of the dashboard.
class RoomsPage extends StatelessWidget {
  const RoomsPage({super.key, required this.hasWaitingPatients});

  /// Whether the queue is non-empty (enables "Nächsten aufrufen"); provided by the dashboard.
  final bool hasWaitingPatients;

  @override
  Widget build(BuildContext context) {
    return BlocListener<RoomsBloc, RoomsState>(
      listenWhen: (p, c) => p.actionErrorId != c.actionErrorId,
      listener: (context, state) {
        if (state.actionError != null) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(state.actionError!)));
        }
      },
      child: BlocBuilder<RoomsBloc, RoomsState>(
        builder: (context, state) {
          final header = Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Semantics(
              header: true,
              liveRegion: true,
              child: Text(
                'Behandlungsräume (${state.availableRooms.length} von ${state.rooms.length} verfügbar)',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
          );
          final Widget body = switch (state.status) {
            RoomsStatus.initial ||
            RoomsStatus.loading => const LoadingView(message: 'Lade Räume …'),
            RoomsStatus.failure => ErrorView(
              message:
                  state.errorMessage ?? 'Räume konnten nicht geladen werden.',
              onRetry: () =>
                  context.read<RoomsBloc>().add(const RoomsRefreshRequested()),
            ),
            RoomsStatus.loaded when state.rooms.isEmpty => const EmptyView(
              icon: Icons.meeting_room_outlined,
              message: 'Keine Räume konfiguriert',
            ),
            RoomsStatus.loaded => _RoomList(
              rooms: state.rooms,
              hasWaitingPatients: hasWaitingPatients,
            ),
          };
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              Expanded(child: body),
            ],
          );
        },
      ),
    );
  }
}

class _RoomList extends StatelessWidget {
  const _RoomList({required this.rooms, required this.hasWaitingPatients});
  final List<Room> rooms;
  final bool hasWaitingPatients;

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<RoomsBloc>();
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      itemCount: rooms.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final room = rooms[i];
        return RoomCard(
          key: ValueKey(room.id),
          room: room,
          hasWaitingPatients: hasWaitingPatients,
          onCallNext: () => bloc.add(CallNextRequested(room.id)),
          onStartCleaning: () =>
              bloc.add(RoomStatusChangeRequested(room.id, RoomStatus.cleaning)),
          onFinishCleaning: () => bloc.add(
            RoomStatusChangeRequested(room.id, RoomStatus.available),
          ),
          onCompleteTreatment: () =>
              bloc.add(TreatmentCompletionRequested(room.id)),
        );
      },
    );
  }
}
