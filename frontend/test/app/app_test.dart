import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:praxis_monitor/app/app.dart';
import 'package:praxis_monitor/app/di/app_dependencies.dart';
import 'package:praxis_monitor/core/network/realtime_client.dart';

import '../support/fakes.dart';

void main() {
  testWidgets(
    'app wires one shared realtime client, loads data over REST and releases resources',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);

      final realtime = FakeRealtimeClient();
      final deps = AppDependencies(
        realtime: realtime,
        httpClient: MockClient((r) async {
          final body = r.url.path == '/api/queue'
              ? [patientJson('a', urgency: 'CRITICAL', position: 1)]
              : [roomJson('room-1'), roomJson('room-2')];
          return http.Response(jsonEncode(body), 200);
        }),
      );

      await tester.pumpWidget(PraxisMonitorApp(dependencies: deps));
      expect(realtime.connectCalls, 1);
      await tester.pump();
      await tester.pump();

      expect(find.text('Patient a'), findsOneWidget);
      expect(find.text('Behandlungsräume (2 von 2 verfügbar)'), findsOneWidget);

      realtime.setStatus(ConnectionStatus.connected);
      await tester.pump();
      await tester.pump();
      expect(find.text('Live verbunden'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      expect(realtime.disposed, isTrue);
    },
  );
}
