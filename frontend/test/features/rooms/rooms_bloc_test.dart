import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:praxis_monitor/core/error/app_exception.dart';
import 'package:praxis_monitor/features/rooms/domain/entities/room.dart';
import 'package:praxis_monitor/features/rooms/presentation/bloc/rooms_bloc.dart';

import '../../support/fakes.dart';

void main() {
  late MockRoomRepository repo;
  late StreamController<List<Room>> live;
  final r1 = room('1');
  final r2 = room(
    '2',
    status: RoomStatus.occupied,
    patientId: 'p',
    patientName: 'Demo',
  );

  setUpAll(() => registerFallbackValue(RoomStatus.available));

  setUp(() {
    repo = MockRoomRepository();
    live = StreamController<List<Room>>.broadcast();
    when(() => repo.watchRooms()).thenAnswer((_) => live.stream);
    when(() => repo.fetchRooms()).thenAnswer((_) async => [r1, r2]);
  });

  tearDown(() => live.close());

  blocTest<RoomsBloc, RoomsState>(
    'loads rooms: loading -> loaded',
    build: () => RoomsBloc(repository: repo),
    act: (b) => b.add(const RoomsStarted()),
    expect: () => [
      const RoomsState(status: RoomsStatus.loading),
      RoomsState(status: RoomsStatus.loaded, rooms: [r1, r2]),
    ],
  );

  blocTest<RoomsBloc, RoomsState>(
    'load failure -> failure state',
    build: () => RoomsBloc(repository: repo),
    setUp: () =>
        when(() => repo.fetchRooms()).thenThrow(const NetworkException()),
    act: (b) => b.add(const RoomsStarted()),
    expect: () => [
      const RoomsState(status: RoomsStatus.loading),
      RoomsState(
        status: RoomsStatus.failure,
        errorMessage: const NetworkException().message,
      ),
    ],
  );

  blocTest<RoomsBloc, RoomsState>(
    'live update from WebSocket stream replaces rooms',
    build: () => RoomsBloc(repository: repo),
    act: (b) async {
      b.add(const RoomsStarted());
      await Future<void>.delayed(const Duration(milliseconds: 10));
      live.add([room('1', status: RoomStatus.cleaning), r2]);
    },
    skip: 2,
    expect: () => [
      RoomsState(
        status: RoomsStatus.loaded,
        rooms: [
          room('1', status: RoomStatus.cleaning),
          r2,
        ],
      ),
    ],
  );

  blocTest<RoomsBloc, RoomsState>(
    'call next / assign / complete / status change delegate to repository and reload',
    build: () => RoomsBloc(repository: repo),
    setUp: () {
      when(() => repo.callNext(any())).thenAnswer((_) async {});
      when(() => repo.assignPatient(any(), any())).thenAnswer((_) async {});
      when(() => repo.completeTreatment(any())).thenAnswer((_) async {});
      when(() => repo.changeStatus(any(), any())).thenAnswer((_) async {});
    },
    act: (b) => b
      ..add(const CallNextRequested('1'))
      ..add(const PatientAssignmentRequested('1', 'p9'))
      ..add(const TreatmentCompletionRequested('2'))
      ..add(const RoomStatusChangeRequested('2', RoomStatus.available)),
    verify: (_) {
      verify(() => repo.callNext('1')).called(1);
      verify(() => repo.assignPatient('1', 'p9')).called(1);
      verify(() => repo.completeTreatment('2')).called(1);
      verify(() => repo.changeStatus('2', RoomStatus.available)).called(1);
      verify(() => repo.fetchRooms()).called(4);
    },
  );

  blocTest<RoomsBloc, RoomsState>(
    'forbidden transition (409) becomes a transient action error',
    build: () => RoomsBloc(repository: repo),
    seed: () => RoomsState(status: RoomsStatus.loaded, rooms: [r1]),
    setUp: () =>
        when(() => repo.callNext('1'))
            .thenThrow(const ApiException(409, 'The waiting queue is empty')),
    act: (b) => b.add(const CallNextRequested('1')),
    expect: () => [
      RoomsState(
        status: RoomsStatus.loaded,
        rooms: [r1],
        actionErrorId: 1,
        actionError: 'The waiting queue is empty',
      ),
    ],
  );

  test('availableRooms only contains AVAILABLE rooms', () {
    expect(RoomsState(rooms: [r1, r2]).availableRooms.map((r) => r.id), ['1']);
  });

  test('close cancels the subscription', () async {
    final bloc = RoomsBloc(repository: repo)..add(const RoomsStarted());
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await bloc.close();
    expect(live.hasListener, isFalse);
  });
}
