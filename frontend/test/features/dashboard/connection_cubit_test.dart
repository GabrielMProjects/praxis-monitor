import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:praxis_monitor/core/network/realtime_client.dart';
import 'package:praxis_monitor/features/dashboard/presentation/cubit/connection_cubit.dart';

import '../../support/fakes.dart';

void main() {
  late FakeRealtimeClient client;

  setUp(() => client = FakeRealtimeClient());
  tearDown(() => client.dispose());

  blocTest<ConnectionCubit, ConnectionStatus>(
    'mirrors disconnect and reconnect of the shared WebSocket',
    build: () => ConnectionCubit(client),
    act: (_) {
      client.setStatus(ConnectionStatus.connecting);
      client.setStatus(ConnectionStatus.connected);
      client.setStatus(ConnectionStatus.disconnected); // connection lost
      client.setStatus(ConnectionStatus.connected); // automatic reconnect
    },
    expect: () => [
      ConnectionStatus.connecting,
      ConnectionStatus.connected,
      ConnectionStatus.disconnected,
      ConnectionStatus.connected,
    ],
  );

  test('close cancels the status subscription', () async {
    final cubit = ConnectionCubit(client);
    await cubit.close();
    expect(() => client.setStatus(ConnectionStatus.connected), returnsNormally);
  });
}
