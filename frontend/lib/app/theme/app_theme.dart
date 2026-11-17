import 'package:material_ui/material_ui.dart';

import '../../features/rooms/domain/entities/room.dart';
import '../../features/triage_queue/domain/entities/patient.dart';

abstract final class AppTheme {
  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF00796B),
      brightness: brightness,
    );
    // Clearly visible keyboard focus: a 3 px ring in addition to Material's faint overlay.
    final focusRing = ButtonStyle(
      side: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.focused)
            ? BorderSide(color: scheme.tertiary, width: 3)
            : null,
      ),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
      focusColor: scheme.primary.withValues(alpha: 0.25),
      filledButtonTheme: FilledButtonThemeData(style: focusRing),
      outlinedButtonTheme: OutlinedButtonThemeData(style: focusRing),
      iconButtonTheme: IconButtonThemeData(style: focusRing),
      visualDensity: VisualDensity.adaptivePlatformDensity,
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: brightness == Brightness.light
                ? const Color(0xFFD9DEE3)
                : const Color(0xFF3A4046),
          ),
        ),
      ),
    );
  }
}

/// Status colours. They are never the only signal: every use also shows a text label and an icon.
abstract final class StatusColors {
  static Color urgency(Urgency u) => switch (u) {
    Urgency.critical => const Color(0xFFC62828),
    Urgency.high => const Color(0xFFE65100),
    Urgency.medium => const Color(0xFFF9A825),
    Urgency.low => const Color(0xFF2E7D32),
  };

  static IconData urgencyIcon(Urgency u) => switch (u) {
    Urgency.critical => Icons.priority_high,
    Urgency.high => Icons.arrow_upward,
    Urgency.medium => Icons.remove,
    Urgency.low => Icons.arrow_downward,
  };

  static Color room(RoomStatus s) => switch (s) {
    RoomStatus.available => const Color(0xFF2E7D32),
    RoomStatus.occupied => const Color(0xFFC62828),
    RoomStatus.cleaning => const Color(0xFF1565C0),
  };

  static IconData roomIcon(RoomStatus s) => switch (s) {
    RoomStatus.available => Icons.check_circle_outline,
    RoomStatus.occupied => Icons.person,
    RoomStatus.cleaning => Icons.cleaning_services_outlined,
  };
}
