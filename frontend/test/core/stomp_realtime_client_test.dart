import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:praxis_monitor/core/network/realtime_client.dart';
import 'package:praxis_monitor/core/network/stomp_realtime_client.dart';
import 'package:stomp_dart_client/stomp_dart_client.dart';

class MockStompClient extends Mock implements StompClient {}

void main() {
  late MockStompClient stomp;
  late StompConfig config;
  late int factoryCalls;
  late List<String> subscribedTopics;
  late Map<String, void Function(StompFrame)> callbacks;
  late int unsubscribeCalls;
  late StompRealtimeClient client;

  setUp(() {
    stomp = MockStompClient();
    factoryCalls = 0;
    subscribedTopics = [];
    callbacks = {};
    unsubscribeCalls = 0;

    when(() => stomp.activate()).thenReturn(null);
    when(() => stomp.deactivate()).thenReturn(null);
    when(
      () => stomp.subscribe(
        destination: any(named: 'destination'),
        headers: any(named: 'headers'),
        callback: any(named: 'callback'),
      ),
    ).thenAnswer((invocation) {
      final destination = invocation.namedArguments[#destination] as String;
      subscribedTopics.add(destination);
      callbacks[destination] =
          invocation.namedArguments[#callback] as void Function(StompFrame);
      return ({Map<String, String>? unsubscribeHeaders}) => unsubscribeCalls++;
    });

    client = StompRealtimeClient(
      url: 'ws://test/ws',
      reconnectDelay: const Duration(milliseconds: 10),
      clientFactory: (c) {
        factoryCalls++;
        config = c;
        return stomp;
      },
    );
  });

  tearDown(() => client.dispose());

  StompFrame message(String body) => StompFrame(command: 'MESSAGE', body: body);

  test('starts disconnected; connect() moves to connecting and activates the client with URL and reconnect delay', () {
    expect(client.currentStatus, ConnectionStatus.disconnected);
    client.connect();

    expect(client.currentStatus, ConnectionStatus.connecting);
    expect(config.url, 'ws://test/ws');
    expect(config.reconnectDelay, const Duration(milliseconds: 10));
    verify(() => stomp.activate()).called(1);
  });

  test('connect() is idempotent (no second client, no double activation)', () {
    client.connect();
    client.connect();
    expect(factoryCalls, 1);
    verify(() => stomp.activate()).called(1);
  });

  test(
    'onConnect subscribes to both topics once and reports connected',
    () async {
      final states = <ConnectionStatus>[];
      final sub = client.status.listen(states.add);
      client.connect();
      config.onConnect(StompFrame(command: 'CONNECTED'));
      await pumpEventQueue();

      expect(subscribedTopics, ['/topic/queue', '/topic/rooms']);
      expect(states, [
        ConnectionStatus.disconnected,
        ConnectionStatus.connecting,
        ConnectionStatus.connected,
      ]);
      await sub.cancel();
    },
  );

  test('valid message becomes a RealtimeEvent; malformed or foreign frames are ignored', () async {
    final events = <RealtimeEvent>[];
    final sub = client.events.listen(events.add);
    client.connect();
    config.onConnect(StompFrame(command: 'CONNECTED'));

    callbacks['/topic/queue']!(
      message(
        '{"type":"QUEUE_CHANGED","occurredAt":"x","payload":{"patients":[]}}',
      ),
    );
    callbacks['/topic/queue']!(message('{not json'));
    callbacks['/topic/queue']!(message('{"noType":1}'));
    callbacks['/topic/rooms']!(StompFrame(command: 'MESSAGE')); // no body
    callbacks['/topic/rooms']!(
      message('{"type":"ROOM_STATUS_CHANGED","payload":{"id":"room-1"}}'),
    );
    await pumpEventQueue();

    expect(events.map((e) => e.type), ['QUEUE_CHANGED', 'ROOM_STATUS_CHANGED']);
    await sub.cancel();
  });

  test('connection loss -> disconnected and subscriptions released; reconnect -> subscribed again exactly once per topic', () async {
    client.connect();
    config.onConnect(StompFrame(command: 'CONNECTED'));
    expect(unsubscribeCalls, 0);

    config.onWebSocketDone();
    expect(client.currentStatus, ConnectionStatus.disconnected);
    expect(unsubscribeCalls, 2);

    config.onConnect(StompFrame(command: 'CONNECTED')); // library reconnected
    expect(client.currentStatus, ConnectionStatus.connected);
    expect(subscribedTopics, [
      '/topic/queue',
      '/topic/rooms',
      '/topic/queue',
      '/topic/rooms',
    ]);
    expect(
      factoryCalls,
      1,
      reason: 'reconnect is done by the library, not by a new client',
    );
  });

  test(
    'onConnect without prior loss cancels stale subscriptions (no duplicates)',
    () {
      client.connect();
      config.onConnect(StompFrame(command: 'CONNECTED'));
      config.onConnect(StompFrame(command: 'CONNECTED'));
      expect(unsubscribeCalls, 2);
    },
  );

  test(
    'websocket error, stomp error and disconnect frame all report disconnected',
    () {
      for (final trigger in <void Function()>[
        () => config.onWebSocketError(Exception('x')),
        () => config.onStompError(StompFrame(command: 'ERROR')),
        () => config.onDisconnect(StompFrame(command: 'DISCONNECT')),
      ]) {
        client = StompRealtimeClient(
          clientFactory: (c) {
            config = c;
            return stomp;
          },
        );
        client.connect();
        config.onConnect(StompFrame(command: 'CONNECTED'));
        trigger();
        expect(client.currentStatus, ConnectionStatus.disconnected);
      }
    },
  );

  test(
    'dispose deactivates the client, closes streams and ignores late callbacks',
    () async {
      final events = <RealtimeEvent>[];
      client.events.listen(events.add);
      client.connect();
      config.onConnect(StompFrame(command: 'CONNECTED'));

      await client.dispose();

      verify(() => stomp.deactivate()).called(1);
      expect(unsubscribeCalls, 2);
      config.onConnect(
        StompFrame(command: 'CONNECTED'),
      ); // must not throw or resurrect
      config.onWebSocketDone();
      await client.dispose(); // idempotent
      client.connect(); // no-op after dispose
      expect(factoryCalls, 1);
      expect(events, isEmpty);
    },
  );
}
