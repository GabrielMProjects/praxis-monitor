import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:praxis_monitor/core/error/app_exception.dart';
import 'package:praxis_monitor/core/network/realtime_client.dart';
import 'package:praxis_monitor/features/dashboard/presentation/cubit/connection_cubit.dart';
import 'package:praxis_monitor/features/dashboard/presentation/pages/dashboard_page.dart';
import 'package:praxis_monitor/features/rooms/domain/entities/room.dart';
import 'package:praxis_monitor/features/rooms/presentation/bloc/rooms_bloc.dart';
import 'package:praxis_monitor/features/triage_queue/domain/entities/patient.dart';
import 'package:praxis_monitor/features/triage_queue/presentation/bloc/triage_queue_bloc.dart';

import '../../support/fakes.dart';

void main() {
  late MockPatientRepository patients;
  late MockRoomRepository rooms;
  late FakeRealtimeClient realtime;
  late StreamController<List<Patient>> liveQueue;

  setUpAll(() {
    registerFallbackValue(Urgency.low);
    registerFallbackValue(RoomStatus.available);
  });

  setUp(() {
    patients = MockPatientRepository();
    rooms = MockRoomRepository();
    realtime = FakeRealtimeClient();
    liveQueue = StreamController<List<Patient>>.broadcast();
    when(() => patients.watchQueue()).thenAnswer((_) => liveQueue.stream);
    when(() => rooms.watchRooms()).thenAnswer((_) => const Stream.empty());
    when(() => patients.fetchQueue()).thenAnswer(
      (_) async => [
        patient(
          'a',
          name: 'Alex Beispiel',
          urgency: Urgency.critical,
          position: 1,
        ),
        patient('b', name: 'Sam Muster', urgency: Urgency.low, position: 2),
      ],
    );
    when(() => rooms.fetchRooms()).thenAnswer(
      (_) async => [
        room('1'),
        room(
          '2',
          status: RoomStatus.occupied,
          patientId: 'x',
          patientName: 'Robin Demo',
        ),
        room('3', status: RoomStatus.cleaning),
      ],
    );
  });

  tearDown(() async {
    await liveQueue.close();
    await realtime.dispose();
  });

  Future<void> pumpDashboard(
    WidgetTester tester, {
    Size size = const Size(1200, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider(create: (_) => ConnectionCubit(realtime)),
          BlocProvider(
            create: (_) =>
                TriageQueueBloc(repository: patients)
                  ..add(const QueueStarted()),
          ),
          BlocProvider(
            create: (_) =>
                RoomsBloc(repository: rooms)..add(const RoomsStarted()),
          ),
        ],
        child: const MaterialApp(home: DashboardPage()),
      ),
    );
  }

  testWidgets(
    'wide layout: queue and rooms side by side with labelled statuses',
    (tester) async {
      realtime.setStatus(ConnectionStatus.connected);
      await pumpDashboard(tester);
      await tester.pump();
      await tester.pump();

      expect(find.text('Warteschlange (2)'), findsOneWidget);
      expect(find.text('Alex Beispiel'), findsOneWidget);
      expect(find.text('Kritisch (1)'), findsOneWidget);
      expect(find.text('Niedrig (4)'), findsOneWidget);
      expect(find.text('Behandlungsräume (1 von 3 verfügbar)'), findsOneWidget);
      expect(find.text('Verfügbar'), findsOneWidget);
      expect(find.text('Belegt'), findsOneWidget);
      expect(find.text('Reinigung'), findsOneWidget);
      expect(find.text('Patient: Robin Demo'), findsOneWidget);
      expect(find.text('Live verbunden'), findsOneWidget);
      expect(find.textContaining('Technische Demonstration'), findsOneWidget);
    },
  );

  testWidgets('narrow layout uses tabs and shows the queue first', (
    tester,
  ) async {
    await pumpDashboard(tester, size: const Size(420, 900));
    await tester.pump();
    await tester.pump();

    expect(find.byType(TabBar), findsOneWidget);
    expect(find.text('Alex Beispiel'), findsOneWidget);

    await tester.tap(find.text('Räume'));
    await tester.pumpAndSettle();
    expect(find.text('Belegt'), findsOneWidget);
  });

  testWidgets('loading state is visible before data arrives', (tester) async {
    final completer = Completer<List<Patient>>();
    when(() => patients.fetchQueue()).thenAnswer((_) => completer.future);
    await pumpDashboard(tester);
    await tester.pump();
    expect(find.text('Lade Warteschlange …'), findsOneWidget);
    completer.complete([]);
    await tester.pump();
    await tester.pump();
    expect(
      find.text('Keine wartenden Patienten'),
      findsOneWidget,
    ); // empty state
  });

  testWidgets('load error shows message and retry reloads', (tester) async {
    var calls = 0;
    when(() => patients.fetchQueue()).thenAnswer((_) async {
      if (calls++ == 0) throw const NetworkException();
      return [patient('a', name: 'Alex Beispiel', position: 1)];
    });
    await pumpDashboard(tester);
    await tester.pump();
    await tester.pump();

    expect(find.text(const NetworkException().message), findsOneWidget);
    await tester.tap(find.text('Erneut versuchen'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Alex Beispiel'), findsOneWidget);
  });

  testWidgets('connection loss shows warning banner; reconnect removes it', (
    tester,
  ) async {
    realtime.setStatus(ConnectionStatus.connected);
    await pumpDashboard(tester);
    await tester.pump();

    realtime.setStatus(ConnectionStatus.disconnected);
    await tester.pump();
    expect(find.textContaining('Echtzeit-Verbindung getrennt'), findsOneWidget);
    expect(find.text('Getrennt'), findsOneWidget);
    expect(
      find.text('Alex Beispiel'),
      findsOneWidget,
    ); // stale data stays visible

    realtime.setStatus(ConnectionStatus.connected);
    await tester.pump();
    expect(find.textContaining('Echtzeit-Verbindung getrennt'), findsNothing);
  });

  testWidgets('live queue update from the stream re-renders in server order', (
    tester,
  ) async {
    await pumpDashboard(tester);
    await tester.pump();
    await tester.pump();

    liveQueue.add([
      patient(
        'c',
        name: 'Neu Kritisch',
        urgency: Urgency.critical,
        position: 1,
      ),
      patient(
        'a',
        name: 'Alex Beispiel',
        urgency: Urgency.critical,
        position: 2,
      ),
    ]);
    await tester.pump();
    await tester.pump();

    expect(find.text('Warteschlange (2)'), findsOneWidget);
    expect(find.text('Neu Kritisch'), findsOneWidget);
    expect(find.text('Sam Muster'), findsNothing);
    final firstY = tester.getTopLeft(find.text('Neu Kritisch')).dy;
    final secondY = tester.getTopLeft(find.text('Alex Beispiel')).dy;
    expect(firstY, lessThan(secondY));
  });

  testWidgets(
    '"Demo-Patient hinzufügen" creates a patient; a rejected action shows a snackbar',
    (tester) async {
      when(
        () => patients.createPatient(
          name: any(named: 'name'),
          urgency: any(named: 'urgency'),
        ),
      ).thenThrow(const ApiException(400, 'Validation failed'));
      await pumpDashboard(tester);
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('Demo-Patient hinzufügen'));
      await tester.pump();
      await tester.pump();

      verify(
        () => patients.createPatient(
          name: any(named: 'name'),
          urgency: any(named: 'urgency'),
        ),
      ).called(1);
      expect(find.text('Validation failed'), findsOneWidget);
    },
  );

  testWidgets(
    'call next in an available room and complete treatment dispatch room actions',
    (tester) async {
      when(() => rooms.callNext(any())).thenAnswer((_) async {});
      when(() => rooms.completeTreatment(any())).thenAnswer((_) async {});
      await pumpDashboard(tester);
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('Nächsten aufrufen'));
      await tester.pump();
      await tester.tap(find.text('Behandlung abschließen'));
      await tester.pump();

      verify(() => rooms.callNext('1')).called(1);
      verify(() => rooms.completeTreatment('2')).called(1);
    },
  );

  testWidgets('"Aufrufen" opens the room dialog and assigns the chosen room', (
    tester,
  ) async {
    when(() => rooms.assignPatient(any(), any())).thenAnswer((_) async {});
    await pumpDashboard(tester);
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Aufrufen').first);
    await tester.pumpAndSettle();
    expect(find.text('Alex Beispiel – Raum wählen'), findsOneWidget);
    await tester.tap(find.text('Raum 1').last);
    await tester.pumpAndSettle();

    verify(() => rooms.assignPatient('1', 'a')).called(1);
  });
}
