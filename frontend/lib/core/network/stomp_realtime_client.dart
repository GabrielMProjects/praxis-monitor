import 'dart:async';
import 'dart:convert';

import 'package:stomp_dart_client/stomp_dart_client.dart';

import '../constants/api_constants.dart';
import 'realtime_client.dart';

StompClient _defaultFactory(StompConfig config) => StompClient(config: config);

/// STOMP-over-WebSocket implementation with automatic reconnect.
///
/// stomp_dart_client re-runs `onConnect` after every successful (re)connect and drops
/// all subscriptions when the socket closes. We therefore (1) cancel stale subscriptions
/// before subscribing again, so each topic has at most one live subscription, and
/// (2) announce `connected` so repositories can re-sync via REST.
class StompRealtimeClient implements RealtimeClient {
  StompRealtimeClient({
    this._url = ApiConstants.wsUrl,
    this._reconnectDelay = ApiConstants.reconnectDelay,
    this._topics = const [ApiConstants.queueTopic, ApiConstants.roomsTopic],
    this._clientFactory = _defaultFactory,
  });

  final String _url;
  final Duration _reconnectDelay;
  final List<String> _topics;
  final StompClient Function(StompConfig) _clientFactory;

  final _events = StreamController<RealtimeEvent>.broadcast();
  final _status = StreamController<ConnectionStatus>.broadcast();
  final List<StompUnsubscribe> _subscriptions = [];

  StompClient? _client;
  ConnectionStatus _current = ConnectionStatus.disconnected;
  bool _disposed = false;

  @override
  Stream<RealtimeEvent> get events => _events.stream;

  @override
  Stream<ConnectionStatus> get status =>
      replayCurrent(() => _current, _status.stream);

  @override
  ConnectionStatus get currentStatus => _current;

  @override
  void connect() {
    if (_disposed || _client != null) return;
    _setStatus(ConnectionStatus.connecting);
    _client = _clientFactory(
      StompConfig(
        url: _url,
        reconnectDelay: _reconnectDelay,
        onConnect: _onConnect,
        onDisconnect: (_) => _onLost(),
        onWebSocketDone: _onLost,
        onWebSocketError: (_) => _onLost(),
        onStompError: (_) => _onLost(),
      ),
    )..activate();
  }

  void _onConnect(StompFrame frame) {
    final client = _client;
    if (_disposed || client == null) return; // late callback after dispose
    _cancelSubscriptions();
    for (final topic in _topics) {
      _subscriptions.add(
        client.subscribe(destination: topic, callback: _onMessage),
      );
    }
    _setStatus(ConnectionStatus.connected);
  }

  void _onMessage(StompFrame frame) {
    final body = frame.body;
    if (body == null || _disposed) return;
    try {
      final json = jsonDecode(body);
      if (json is Map<String, dynamic> && json['type'] is String) {
        _events.add(RealtimeEvent.fromJson(json));
      }
    } on FormatException {
      // ignore malformed frame; REST re-sync on next reconnect restores consistency
    }
  }

  void _onLost() {
    if (_disposed) return;
    _cancelSubscriptions();
    // stomp_dart_client schedules the reconnect itself (reconnectDelay).
    _setStatus(ConnectionStatus.disconnected);
  }

  void _cancelSubscriptions() {
    for (final unsubscribe in _subscriptions) {
      try {
        unsubscribe();
      } catch (_) {
        // socket already closed
      }
    }
    _subscriptions.clear();
  }

  void _setStatus(ConnectionStatus next) {
    if (_disposed || next == _current) return;
    _current = next;
    _status.add(next);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _cancelSubscriptions();
    _client?.deactivate();
    _client = null;
    await _events.close();
    await _status.close();
  }
}
