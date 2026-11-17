import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../constants/api_constants.dart';
import '../error/app_exception.dart';

/// Thin JSON-over-HTTP client. The only place that talks HTTP; maps failures to [AppException].
class ApiClient {
  ApiClient({
    required this._client,
    this._baseUrl = ApiConstants.baseUrl,
    this._timeout = ApiConstants.requestTimeout,
  });

  final http.Client _client;
  final String _baseUrl;
  final Duration _timeout;

  Future<dynamic> get(String path) => _send('GET', path);
  Future<dynamic> post(String path, {Object? body}) =>
      _send('POST', path, body: body);
  Future<dynamic> put(String path, {Object? body}) =>
      _send('PUT', path, body: body);
  Future<dynamic> delete(String path) => _send('DELETE', path);

  Future<dynamic> _send(String method, String path, {Object? body}) async {
    final request = http.Request(method, Uri.parse('$_baseUrl$path'));
    request.headers['Accept'] = 'application/json';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }

    final http.Response response;
    try {
      response = await http.Response.fromStream(
        await _client.send(request).timeout(_timeout),
      );
    } on TimeoutException {
      throw const NetworkException(
        'Zeitüberschreitung bei der Anfrage an den Server.',
      );
    } on http.ClientException {
      throw const NetworkException();
    } catch (_) {
      throw const NetworkException();
    }

    final text = utf8.decode(response.bodyBytes);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (text.isEmpty) return null;
      try {
        return jsonDecode(text);
      } on FormatException {
        throw const ParseException();
      }
    }
    throw ApiException(
      response.statusCode,
      _errorMessage(response.statusCode, text),
    );
  }

  String _errorMessage(int status, String text) {
    try {
      final json = jsonDecode(text);
      if (json is Map<String, dynamic>) {
        final message = json['message'];
        final details = json['details'];
        final detailText = details is List && details.isNotEmpty
            ? ' (${details.join(', ')})'
            : '';
        if (message is String && message.isNotEmpty) {
          return '$message$detailText';
        }
      }
    } on FormatException {
      // fall through
    }
    return 'Anfrage fehlgeschlagen (HTTP $status).';
  }
}
