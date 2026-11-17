import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:praxis_monitor/features/rooms/domain/entities/room.dart';
import 'package:praxis_monitor/features/rooms/presentation/widgets/room_card.dart';

import '../../support/fakes.dart';

void main() {
  final calls = <String>[];

  Widget card(Room r, {bool waiting = true}) => MaterialApp(
    home: Scaffold(
      body: RoomCard(
        room: r,
        hasWaitingPatients: waiting,
        onCallNext: () => calls.add('next'),
        onStartCleaning: () => calls.add('startCleaning'),
        onFinishCleaning: () => calls.add('finishCleaning'),
        onCompleteTreatment: () => calls.add('complete'),
      ),
    ),
  );

  setUp(calls.clear);

  testWidgets('AVAILABLE: label, call-next and start-cleaning actions', (
    tester,
  ) async {
    await tester.pumpWidget(card(room('1')));
    expect(find.text('Verfügbar'), findsOneWidget);
    await tester.tap(find.text('Nächsten aufrufen'));
    await tester.tap(find.text('Reinigung starten'));
    expect(calls, ['next', 'startCleaning']);
  });

  testWidgets('AVAILABLE without waiting patients: call-next disabled', (
    tester,
  ) async {
    await tester.pumpWidget(card(room('1'), waiting: false));
    await tester.tap(find.text('Nächsten aufrufen'), warnIfMissed: false);
    expect(calls, isEmpty);
  });

  testWidgets(
    'OCCUPIED: shows patient name and offers completing the treatment only',
    (tester) async {
      await tester.pumpWidget(
        card(
          room(
            '1',
            status: RoomStatus.occupied,
            patientId: 'p',
            patientName: 'Demo Patient',
          ),
        ),
      );
      expect(find.text('Belegt'), findsOneWidget);
      expect(find.text('Patient: Demo Patient'), findsOneWidget);
      expect(find.text('Nächsten aufrufen'), findsNothing);
      await tester.tap(find.text('Behandlung abschließen'));
      expect(calls, ['complete']);
    },
  );

  testWidgets('CLEANING: label and explicit finish-cleaning action', (
    tester,
  ) async {
    await tester.pumpWidget(card(room('1', status: RoomStatus.cleaning)));
    expect(find.text('Reinigung'), findsOneWidget);
    await tester.tap(find.text('Reinigung beendet'));
    expect(calls, ['finishCleaning']);
  });
}
