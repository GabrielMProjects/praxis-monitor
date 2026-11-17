// Offline sanity check for the GitHub Actions configuration (syntax + security hygiene).
// Run from the repo root:
//   dart --packages=frontend/.dart_tool/package_config.json scripts/validate-workflows.dart
// (uses the `yaml` package that Flutter already pulls in; nothing extra to install).
// It cannot replace a real run on GitHub, but it catches YAML errors, unpinned actions and missing permissions.
import 'dart:io';

import 'package:yaml/yaml.dart';

final _sha = RegExp(r'^[0-9a-f]{40}$');
var errors = 0;

void fail(String file, String message) {
  errors++;
  stderr.writeln('FAIL $file: $message');
}

void main() {
  final files = [
    ...Directory('.github/workflows').listSync().whereType<File>().where((f) => f.path.endsWith('.yml') || f.path.endsWith('.yaml')),
    File('.github/dependabot.yml'),
  ];
  for (final file in files) {
    final doc = loadYaml(file.readAsStringSync());
    if (doc is! YamlMap) {
      fail(file.path, 'not a mapping');
      continue;
    }
    if (file.path.contains('dependabot')) {
      final updates = doc['updates'] as YamlList;
      final ecosystems = updates.map((u) => u['package-ecosystem']).toSet();
      for (final e in ['maven', 'pub', 'github-actions']) {
        if (!ecosystems.contains(e)) fail(file.path, 'missing ecosystem $e');
      }
      continue;
    }
    if (doc['permissions'] == null) fail(file.path, 'top-level permissions missing (least privilege)');
    if (doc['on'] == null && doc[true] == null) fail(file.path, 'no trigger');
    final jobs = doc['jobs'] as YamlMap;
    for (final entry in jobs.entries) {
      final job = entry.value as YamlMap;
      if (job['timeout-minutes'] == null) fail(file.path, 'job ${entry.key} has no timeout-minutes');
      for (final step in (job['steps'] as YamlList)) {
        final uses = (step as YamlMap)['uses'] as String?;
        if (uses == null) continue;
        final ref = uses.split('@').last;
        if (!_sha.hasMatch(ref)) fail(file.path, 'job ${entry.key}: action not pinned to a commit SHA: $uses');
      }
    }
    final text = file.readAsStringSync();
    if (text.contains('pull_request_target')) fail(file.path, 'uses pull_request_target');
    stdout.writeln('ok   ${file.path}: ${jobs.length} job(s)');
  }
  if (errors > 0) exit(1);
  stdout.writeln('Workflow validation passed.');
}
