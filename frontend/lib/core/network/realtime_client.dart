import 'dart:async';

/// Connection state of the single shared WebSocket.
enum ConnectionStatus { connecting, connected, disconnected }

/// Stream that first replays [current] and then forwards [updates]. Subscribes to [updates]
/// synchronously on listen, so no state change can fall into a gap (unlike an sync* generator).
Stream<T> replayCurrent<T>(T Function() current, Stream<T> updates) {
  late final StreamController<T> controller;
  StreamSubscription<T>? subscription;
  controller = StreamController<T>(
    onListen: () {
      controller.add(current());
      subscription = updates.listen(
        controller.add,
        onError: controller.addError,
        onDone: controller.close,
      );
    },
    onCancel: () => subscription?.cancel(),
  );
  return controller.stream;
}

/// One WebSocket message: `{"type": "...", "occurredAt": "...", "payload": {...}}`.
class RealtimeEvent {
  const RealtimeEvent({required this.type, required this.payload});

  factory RealtimeEvent.fromJson(Map<String, dynamic> json) =>
      RealtimeEvent(type: json['type'] as String, payload: json['payload']);

  final String type;
  final dynamic payload;
}

/// Abstraction over the real-time channel (STOMP in production, fakes in tests).
/// There is exactly one instance per app, created in the DI container.
abstract interface class RealtimeClient {
  /// All server events from all topics.
  Stream<RealtimeEvent> get events;

  /// Emits on every connection state change (starts with the current state on listen).
  Stream<ConnectionStatus> get status;

  ConnectionStatus get currentStatus;

  /// Idempotent: a second call while active does nothing (no double subscriptions).
  void connect();

  /// Closes the socket and all streams. The client cannot be reused afterwards.
  Future<void> dispose();
}
