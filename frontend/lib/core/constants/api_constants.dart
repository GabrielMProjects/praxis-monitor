/// Backend endpoints. Override at build/run time, e.g.
/// `flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8080 --dart-define=WS_URL=ws://localhost:8080/ws`
abstract final class ApiConstants {
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8080',
  );
  static const String wsUrl = String.fromEnvironment(
    'WS_URL',
    defaultValue: 'ws://localhost:8080/ws',
  );

  static const Duration requestTimeout = Duration(seconds: 10);
  static const Duration reconnectDelay = Duration(seconds: 3);

  static const String queueTopic = '/topic/queue';
  static const String roomsTopic = '/topic/rooms';
}
