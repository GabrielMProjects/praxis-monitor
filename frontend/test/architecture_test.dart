import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the feature-first architecture: features never import each other (only the dashboard composes them),
/// and the domain layer never depends on data/presentation or Flutter.
void main() {
  final lib = Directory('lib');

  Iterable<File> dartFiles(String path) =>
      Directory(path)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'));

  List<String> imports(File f) =>
      f.readAsLinesSync().where((l) => l.startsWith('import ')).toList();

  test('triage_queue and rooms features do not depend on each other', () {
    for (final (feature, other) in [
      ('triage_queue', 'rooms'),
      ('rooms', 'triage_queue'),
    ]) {
      for (final file in dartFiles('${lib.path}/features/$feature')) {
        final bad = imports(file).where(
          (l) => l.contains('/features/$other/') || l.contains('../$other/'),
        );
        expect(bad, isEmpty, reason: '${file.path} imports the $other feature');
      }
    }
  });

  test('domain layers are free of Flutter, data and presentation imports', () {
    for (final feature in ['triage_queue', 'rooms']) {
      for (final file in dartFiles('${lib.path}/features/$feature/domain')) {
        for (final line in imports(file)) {
          expect(
            line.contains('package:flutter') ||
                line.contains('material_ui') ||
                line.contains('/data/') ||
                line.contains('/presentation/'),
            isFalse,
            reason: '${file.path}: $line',
          );
        }
      }
    }
  });

  test('widgets and pages never use HTTP or WebSocket directly', () {
    for (final file in dartFiles(
      '${lib.path}/features',
    ).followedBy(dartFiles('${lib.path}/shared'))) {
      if (!file.path.contains('presentation') &&
          !file.path.contains('shared')) {
        continue;
      }
      for (final line in imports(file)) {
        expect(
          line.contains('package:http') ||
              line.contains('stomp_dart_client') ||
              line.contains('core/network/api_client') ||
              line.contains('core/network/stomp_realtime_client'),
          isFalse,
          reason: '${file.path}: $line',
        );
      }
    }
  });
}
