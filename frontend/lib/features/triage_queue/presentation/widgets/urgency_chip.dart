import 'package:material_ui/material_ui.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../shared/widgets/status_chip.dart';
import '../../domain/entities/patient.dart';

class UrgencyChip extends StatelessWidget {
  const UrgencyChip({super.key, required this.urgency});
  final Urgency urgency;

  @override
  Widget build(BuildContext context) => StatusChip(
    label: '${urgency.label} (${urgency.priority})',
    color: StatusColors.urgency(urgency),
    icon: StatusColors.urgencyIcon(urgency),
  );
}
