import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:praxis_monitor/core/error/app_exception.dart';
import 'package:praxis_monitor/features/triage_queue/domain/entities/demo_patient_generator.dart';
import 'package:praxis_monitor/features/triage_queue/domain/entities/patient.dart';
import 'package:praxis_monitor/features/triage_queue/presentation/bloc/triage_queue_bloc.dart';

import '../../support/fakes.dart';

void main() {
  late MockPatientRepository repo;
  late StreamController<List<Patient>> live;

  final a = patient('a', urgency: Urgency.critical, position: 1);
  final b = patient('b', urgency: Urgency.low, position: 2);

  setUpAll(() {
    registerFallbackValue(Urgency.low);
  });

  setUp(() {
    repo = MockPatientRepository();
    live = StreamController<List<Patient>>.broadcast();
    when(() => repo.watchQueue()).thenAnswer((_) => live.stream);
    when(() => repo.fetchQueue()).thenAnswer((_) async => [a, b]);
  });

  tearDown(() => live.close());

  TriageQueueBloc build() => TriageQueueBloc(repository: repo);

  blocTest<TriageQueueBloc, TriageQueueState>(
    'loads the queue: loading -> loaded, keeps server order',
    build: build,
    act: (bloc) => bloc.add(const QueueStarted()),
    expect: () => [
      const TriageQueueState(status: QueueStatus.loading),
      TriageQueueState(status: QueueStatus.loaded, patients: [a, b]),
    ],
  );

  blocTest<TriageQueueBloc, TriageQueueState>(
    'initial load failure -> failure state with message; retry succeeds',
    build: build,
    setUp: () {
      var calls = 0;
      when(() => repo.fetchQueue()).thenAnswer((_) async {
        if (calls++ == 0) throw const NetworkException();
        return [a];
      });
    },
    act: (bloc) async {
      bloc.add(const QueueStarted());
      await Future<void>.delayed(Duration.zero);
      bloc.add(const QueueRefreshRequested());
    },
    expect: () => [
      const TriageQueueState(status: QueueStatus.loading),
      isA<TriageQueueState>()
          .having((s) => s.status, 'status', QueueStatus.failure)
          .having(
            (s) => s.errorMessage,
            'error',
            const NetworkException().message,
          ),
      isA<TriageQueueState>().having(
        (s) => s.status,
        'status',
        QueueStatus.loading,
      ),
      TriageQueueState(status: QueueStatus.loaded, patients: [a]),
    ],
  );

  blocTest<TriageQueueBloc, TriageQueueState>(
    'live updates replace the queue (WebSocket path)',
    build: build,
    act: (bloc) async {
      bloc.add(const QueueStarted());
      await Future<void>.delayed(const Duration(milliseconds: 10));
      live.add([b]);
    },
    skip: 2,
    expect: () => [
      TriageQueueState(status: QueueStatus.loaded, patients: [b]),
    ],
  );

  blocTest<TriageQueueBloc, TriageQueueState>(
    'stream error after data was loaded surfaces as transient action error, list stays',
    build: build,
    act: (bloc) async {
      bloc.add(const QueueStarted());
      await Future<void>.delayed(const Duration(milliseconds: 10));
      live.addError(const NetworkException());
    },
    skip: 2,
    expect: () => [
      isA<TriageQueueState>()
          .having((s) => s.patients, 'patients', [a, b])
          .having(
            (s) => s.actionError,
            'actionError',
            const NetworkException().message,
          )
          .having((s) => s.status, 'status', QueueStatus.loaded),
    ],
  );

  blocTest<TriageQueueBloc, TriageQueueState>(
    'demo patient: creates via repository, then reloads the queue',
    build: () =>
        TriageQueueBloc(repository: repo, generator: DemoPatientGenerator()),
    setUp: () {
      when(
        () => repo.createPatient(
          name: any(named: 'name'),
          urgency: any(named: 'urgency'),
        ),
      ).thenAnswer((_) async => a);
    },
    act: (bloc) => bloc.add(const DemoPatientAdded()),
    expect: () => [
      TriageQueueState(status: QueueStatus.loaded, patients: [a, b]),
    ],
    verify: (_) {
      verify(
        () => repo.createPatient(
          name: any(named: 'name'),
          urgency: any(named: 'urgency'),
        ),
      ).called(1);
      verify(() => repo.fetchQueue()).called(1);
    },
  );

  blocTest<TriageQueueBloc, TriageQueueState>(
    'urgency change calls updatePatient with name and new urgency',
    build: build,
    setUp: () {
      when(
        () => repo.updatePatient(
          id: any(named: 'id'),
          name: any(named: 'name'),
          urgency: any(named: 'urgency'),
        ),
      ).thenAnswer((_) async => b);
    },
    act: (bloc) => bloc.add(PatientUrgencyChanged(b, Urgency.critical)),
    verify: (_) => verify(
      () => repo.updatePatient(
        id: 'b',
        name: 'Patient b',
        urgency: Urgency.critical,
      ),
    ).called(1),
  );

  blocTest<TriageQueueBloc, TriageQueueState>(
    'removal calls repository and reloads',
    build: build,
    setUp: () => when(() => repo.removePatient('a')).thenAnswer((_) async {}),
    act: (bloc) => bloc.add(const PatientRemoved('a')),
    verify: (_) {
      verify(() => repo.removePatient('a')).called(1);
      verify(() => repo.fetchQueue()).called(1);
    },
  );

  blocTest<TriageQueueBloc, TriageQueueState>(
    'rejected action (409) sets actionError and does not clear the list',
    build: build,
    seed: () => TriageQueueState(status: QueueStatus.loaded, patients: [a]),
    setUp: () =>
        when(() => repo.removePatient('a'))
            .thenThrow(const ApiException(409, 'Patient a is IN_TREATMENT')),
    act: (bloc) => bloc.add(const PatientRemoved('a')),
    expect: () => [
      TriageQueueState(
        status: QueueStatus.loaded,
        patients: [a],
        actionErrorId: 1,
        actionError: 'Patient a is IN_TREATMENT',
      ),
    ],
  );

  test('close cancels the live subscription (no leak)', () async {
    final bloc = build()..add(const QueueStarted());
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(live.hasListener, isTrue);
    await bloc.close();
    expect(live.hasListener, isFalse);
  });

  test('DemoPatientGenerator produces unique synthetic names', () {
    final g = DemoPatientGenerator();
    final names = {for (var i = 0; i < 20; i++) g.next().name};
    expect(names, hasLength(20));
  });
}
