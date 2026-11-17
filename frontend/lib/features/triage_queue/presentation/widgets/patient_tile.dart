import 'package:material_ui/material_ui.dart';

import '../../domain/entities/patient.dart';
import 'urgency_chip.dart';

class PatientTile extends StatelessWidget {
  const PatientTile({
    super.key,
    required this.patient,
    required this.canAssign,
    required this.onUrgencyChanged,
    required this.onAssign,
    required this.onRemove,
  });

  final Patient patient;

  /// Whether at least one room is available (otherwise "Aufrufen" is disabled).
  final bool canAssign;
  final ValueChanged<Urgency> onUrgencyChanged;
  final VoidCallback onAssign;
  final VoidCallback onRemove;

  static String formatTime(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';

  /// Screen-reader summary of the visual info block, e.g.
  /// "Position 1: Alex Muster, Dringlichkeit Kritisch (1), Ankunft 09:05:07, Status: Wartet".
  String get _summary =>
      'Position ${patient.queuePosition ?? '-'}: ${patient.name}, '
      'Dringlichkeit ${patient.urgency.label} (${patient.urgency.priority}), '
      'Ankunft ${formatTime(patient.arrivedAt)}, Status: ${patient.status.label}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Semantics(
          container: true,
          explicitChildNodes: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // One announced summary instead of many loose text fragments.
              Semantics(
                container: true,
                label: _summary,
                child: ExcludeSemantics(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 16,
                            child: Text('${patient.queuePosition ?? '–'}'),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              patient.name,
                              style: theme.textTheme.titleMedium,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 12,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          UrgencyChip(urgency: patient.urgency),
                          Text('Ankunft ${formatTime(patient.arrivedAt)}'),
                          Text('Status: ${patient.status.label}'),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const ExcludeSemantics(
                        child: Text('Dringlichkeit ändern:'),
                      ),
                      Semantics(
                        label: 'Dringlichkeit ändern für ${patient.name}',
                        child: DropdownButton<Urgency>(
                          value: patient.urgency,
                          isDense: true,
                          focusColor: theme.colorScheme.primary.withValues(
                            alpha: 0.25,
                          ),
                          items: [
                            for (final u in Urgency.values)
                              DropdownMenuItem(value: u, child: Text(u.label)),
                          ],
                          onChanged: (u) {
                            if (u != null && u != patient.urgency) {
                              onUrgencyChanged(u);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  Tooltip(
                    excludeFromSemantics: true,
                    message: canAssign
                        ? 'Patient in einen freien Raum rufen'
                        : 'Kein Raum verfügbar',
                    child: FilledButton.tonalIcon(
                      onPressed: canAssign ? onAssign : null,
                      icon: const Icon(Icons.meeting_room_outlined),
                      label: Text(
                        canAssign ? 'Aufrufen' : 'Aufrufen (kein Raum frei)',
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '${patient.name} aus der Warteschlange entfernen',
                    onPressed: onRemove,
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
