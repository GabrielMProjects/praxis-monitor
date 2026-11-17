import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:praxis_monitor/features/triage_queue/domain/entities/patient.dart';
import 'package:praxis_monitor/features/triage_queue/presentation/widgets/patient_tile.dart';

import '../../support/fakes.dart';

Widget wrap(Widget child) => MaterialApp(
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  testWidgets(
    'shows name, position, urgency label with priority, arrival time and status text',
    (tester) async {
      await tester.pumpWidget(
        wrap(
          PatientTile(
            patient: Patient(
              id: 'a',
              name: 'Alex Beispiel #1',
              urgency: Urgency.critical,
              arrivedAt: DateTime(2026, 1, 1, 9, 5, 7),
              status: PatientStatus.waiting,
              queuePosition: 1,
            ),
            canAssign: true,
            onUrgencyChanged: (_) {},
            onAssign: () {},
            onRemove: () {},
          ),
        ),
      );

      expect(find.text('Alex Beispiel #1'), findsOneWidget);
      expect(
        find.text('Kritisch (1)'),
        findsOneWidget,
      ); // label, not only colour
      expect(find.text('Ankunft 09:05:07'), findsOneWidget);
      expect(find.text('Status: Wartet'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
    },
  );

  testWidgets('Aufrufen is disabled without a free room and enabled with one', (
    tester,
  ) async {
    var assigned = 0;
    Widget tile(bool canAssign) => wrap(
      PatientTile(
        patient: patient('a', position: 1),
        canAssign: canAssign,
        onUrgencyChanged: (_) {},
        onAssign: () => assigned++,
        onRemove: () {},
      ),
    );

    await tester.pumpWidget(tile(false));
    expect(
      find.text('Aufrufen (kein Raum frei)'),
      findsOneWidget,
    ); // reason is visible, not only a tooltip
    await tester.tap(
      find.text('Aufrufen (kein Raum frei)'),
      warnIfMissed: false,
    );
    expect(assigned, 0);

    await tester.pumpWidget(tile(true));
    await tester.tap(find.text('Aufrufen'));
    expect(assigned, 1);
  });

  testWidgets(
    'changing the dropdown reports the new urgency; keyboard-reachable remove button works',
    (tester) async {
      Urgency? changed;
      var removed = false;
      await tester.pumpWidget(
        wrap(
          PatientTile(
            patient: patient('a', urgency: Urgency.medium, position: 2),
            canAssign: true,
            onUrgencyChanged: (u) => changed = u,
            onAssign: () {},
            onRemove: () => removed = true,
          ),
        ),
      );

      await tester.tap(find.byType(DropdownButton<Urgency>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kritisch').last);
      await tester.pumpAndSettle();
      expect(changed, Urgency.critical);

      await tester.tap(
        find.byTooltip('Patient a aus der Warteschlange entfernen'),
      );
      expect(removed, isTrue);
    },
  );
}
