import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:praxis_monitor/core/error/app_exception.dart';
import 'package:praxis_monitor/core/network/api_client.dart';

ApiClient clientFor(
  Future<http.Response> Function(http.Request) handler, {
  Duration? timeout,
}) => ApiClient(
  client: MockClient(handler),
  baseUrl: 'http://test',
  timeout: timeout ?? const Duration(seconds: 1),
);

void main() {
  test('GET decodes JSON and builds the URL from baseUrl', () async {
    late Uri seen;
    final api = clientFor((r) async {
      seen = r.url;
      return http.Response('[{"a":1}]', 200);
    });
    expect(await api.get('/api/queue'), [
      {'a': 1},
    ]);
    expect(seen.toString(), 'http://test/api/queue');
  });

  test('POST sends JSON body with content type', () async {
    late http.Request seen;
    final api = clientFor((r) async {
      seen = r;
      return http.Response('{}', 201);
    });
    await api.post('/api/patients', body: {'name': 'x'});
    expect(seen.headers['Content-Type'], contains('application/json'));
    expect(jsonDecode(seen.body), {'name': 'x'});
  });

  test('204 returns null', () async {
    final api = clientFor((r) async => http.Response('', 204));
    expect(await api.delete('/api/patients/1'), isNull);
  });

  test('409 becomes ApiException with the backend message', () async {
    final api = clientFor(
      (r) async => http.Response(
        '{"status":409,"error":"Conflict","message":"Room room-1 is OCCUPIED","details":[]}',
        409,
        headers: {'content-type': 'application/json'},
      ),
    );
    await expectLater(
      api.post('/api/rooms/room-1/call-next'),
      throwsA(
        isA<ApiException>()
            .having((e) => e.statusCode, 'status', 409)
            .having((e) => e.message, 'message', 'Room room-1 is OCCUPIED'),
      ),
    );
  });

  test('400 validation details are appended to the message', () async {
    final api = clientFor(
      (r) async => http.Response(
        '{"status":400,"message":"Validation failed","details":["name: must not be blank"]}',
        400,
      ),
    );
    await expectLater(
      api.post('/api/patients', body: {}),
      throwsA(
        isA<ApiException>().having(
          (e) => e.message,
          'message',
          contains('name: must not be blank'),
        ),
      ),
    );
  });

  test('non-JSON error body falls back to a generic message', () async {
    final api = clientFor((r) async => http.Response('<html>oops</html>', 500));
    await expectLater(
      api.get('/x'),
      throwsA(
        isA<ApiException>().having(
          (e) => e.message,
          'message',
          contains('HTTP 500'),
        ),
      ),
    );
  });

  test('connection failure becomes NetworkException', () async {
    final api = clientFor((r) async => throw http.ClientException('refused'));
    await expectLater(api.get('/x'), throwsA(isA<NetworkException>()));
  });

  test('timeout becomes NetworkException', () async {
    final api = clientFor(
      (r) => Completer<http.Response>().future,
      timeout: const Duration(milliseconds: 20),
    );
    await expectLater(api.get('/x'), throwsA(isA<NetworkException>()));
  });

  test('invalid JSON in a 200 response becomes ParseException', () async {
    final api = clientFor((r) async => http.Response('{not json', 200));
    await expectLater(api.get('/x'), throwsA(isA<ParseException>()));
  });
}
