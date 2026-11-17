import 'package:material_ui/material_ui.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../shared/widgets/status_chip.dart';
import '../../domain/entities/room.dart';

class RoomCard extends StatelessWidget {
  const RoomCard({
    super.key,
    required this.room,
    required this.hasWaitingPatients,
    required this.onCallNext,
    required this.onStartCleaning,
    required this.onFinishCleaning,
    required this.onCompleteTreatment,
  });

  final Room room;
  final bool hasWaitingPatients;
  final VoidCallback onCallNext;
  final VoidCallback onStartCleaning;
  final VoidCallback onFinishCleaning;
  final VoidCallback onCompleteTreatment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = StatusColors.room(room.status);
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(room.name, style: theme.textTheme.titleMedium),
                ),
                StatusChip(
                  label: room.status.label,
                  color: color,
                  icon: StatusColors.roomIcon(room.status),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(switch (room.status) {
              RoomStatus.occupied =>
                'Patient: ${room.patientName ?? room.patientId}',
              RoomStatus.cleaning => 'Wird gereinigt',
              RoomStatus.available => 'Bereit für den nächsten Patienten',
            }),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 4, children: _actions()),
          ],
        ),
      ),
    );
  }

  List<Widget> _actions() => switch (room.status) {
    RoomStatus.available => [
      FilledButton.tonalIcon(
        onPressed: hasWaitingPatients ? onCallNext : null,
        icon: const Icon(Icons.campaign_outlined),
        label: const Text('Nächsten aufrufen'),
      ),
      OutlinedButton.icon(
        onPressed: onStartCleaning,
        icon: const Icon(Icons.cleaning_services_outlined),
        label: const Text('Reinigung starten'),
      ),
    ],
    RoomStatus.occupied => [
      FilledButton.icon(
        onPressed: onCompleteTreatment,
        icon: const Icon(Icons.task_alt),
        label: const Text('Behandlung abschließen'),
      ),
    ],
    RoomStatus.cleaning => [
      FilledButton.icon(
        onPressed: onFinishCleaning,
        icon: const Icon(Icons.check),
        label: const Text('Reinigung beendet'),
      ),
    ],
  };
}
