/// Errors surfaced to the presentation layer. [message] is always user-readable.
sealed class AppException implements Exception {
  const AppException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Backend unreachable / timeout.
class NetworkException extends AppException {
  const NetworkException([
    super.message = 'Server nicht erreichbar. Läuft das Backend auf Port 8080?',
  ]);
}

/// Backend answered with a 4xx/5xx (e.g. 409 forbidden state transition).
class ApiException extends AppException {
  const ApiException(this.statusCode, super.message);
  final int statusCode;
}

/// Unexpected response shape.
class ParseException extends AppException {
  const ParseException([super.message = 'Unerwartete Antwort des Servers.']);
}
