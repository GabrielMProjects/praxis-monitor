import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../../../rooms/presentation/bloc/rooms_bloc.dart';
import '../../../rooms/presentation/pages/rooms_page.dart';
import '../../../triage_queue/presentation/bloc/triage_queue_bloc.dart';
import '../../../triage_queue/presentation/pages/triage_queue_page.dart';
import '../../../triage_queue/presentation/widgets/assign_room_dialog.dart'
    show RoomOption;
import '../widgets/connection_banner.dart';

/// Responsive dashboard: two columns on wide screens, tabs on narrow ones.
///
/// This is the only place that knows both features: it hands the queue page the rooms it may assign to and
/// the rooms page whether anyone is waiting, so neither feature depends on the other.
class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  static const double wideBreakpoint = 900;

  @override
  Widget build(BuildContext context) {
    final rooms = context.watch<RoomsBloc>().state;
    final hasWaiting = context
        .watch<TriageQueueBloc>()
        .state
        .patients
        .isNotEmpty;
    final queuePage = TriageQueuePage(
      assignableRooms: [
        for (final r in rooms.availableRooms)
          RoomOption(id: r.id, name: r.name),
      ],
      onAssign: (roomId, patientId) => context.read<RoomsBloc>().add(
        PatientAssignmentRequested(roomId, patientId),
      ),
    );
    final roomsPage = RoomsPage(hasWaitingPatients: hasWaiting);
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= wideBreakpoint;
        final appBar = AppBar(
          title: const Text('Praxis Monitor'),
          actions: const [ConnectionIndicator(), SizedBox(width: 12)],
          bottom: wide
              ? null
              : const TabBar(
                  tabs: [
                    Tab(
                      icon: Icon(Icons.groups_outlined),
                      text: 'Warteschlange',
                    ),
                    Tab(icon: Icon(Icons.meeting_room_outlined), text: 'Räume'),
                  ],
                ),
        );
        final content = Column(
          children: [
            const _DemoDisclaimer(),
            const ConnectionBanner(),
            Expanded(
              child: wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          flex: 3,
                          child: _Section(order: 0, child: queuePage),
                        ),
                        const VerticalDivider(width: 1),
                        Expanded(
                          flex: 2,
                          child: _Section(order: 1, child: roomsPage),
                        ),
                      ],
                    )
                  : TabBarView(
                      children: [
                        _Section(order: 0, child: queuePage),
                        _Section(order: 1, child: roomsPage),
                      ],
                    ),
            ),
          ],
        );
        final scaffold = Scaffold(
          appBar: appBar,
          body: SafeArea(child: content),
        );
        return wide
            ? scaffold
            : DefaultTabController(length: 2, child: scaffold);
      },
    );
  }
}

/// Keeps one column's controls together for keyboard traversal. Flutter's default reading-order
/// policy would otherwise zig-zag row by row between the side-by-side columns.
class _Section extends StatelessWidget {
  const _Section({required this.order, required this.child});

  final double order;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: FocusTraversalOrder(order: NumericFocusOrder(order), child: child),
    );
  }
}

class _DemoDisclaimer extends StatelessWidget {
  const _DemoDisclaimer();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.secondaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: const Text(
        'Technische Demonstration mit synthetischen Daten – kein medizinisches Entscheidungssystem.',
        style: TextStyle(fontSize: 12),
      ),
    );
  }
}
