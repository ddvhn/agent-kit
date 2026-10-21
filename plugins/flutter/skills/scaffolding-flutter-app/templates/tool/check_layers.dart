// Fails when a package imports something its layer may not depend on.
// Run from the workspace root: dart run tool/check_layers.dart
// Existing app with known violations: dart run tool/check_layers.dart
// --write-baseline records them in tool/layer_baseline.txt; later runs fail
// only on violations that are not in the baseline.
import 'dart:io';

final class _Layer {
  const _Layer({
    required this.package,
    this.allow,
    this.deny = const {},
    this.dartLibraries,
  });

  /// The package name in `package:` URIs (it may differ from the folder).
  final String package;

  /// Packages this layer may import besides itself; null = any not denied.
  final Set<String>? allow;

  /// URI prefixes this layer must never import.
  final Set<String> deny;

  /// `dart:` libraries this layer may import; null = any not denied.
  final Set<String>? dartLibraries;
}

/// Platform-free code: no dart:ui, dart:io, web, or isolate libraries.
const _pureDart = {
  'async',
  'collection',
  'convert',
  'core',
  'math',
  'typed_data',
};

/// Test-only barrels: never imported from any `lib/`.
const _testOnly = {'package:data/testing.dart'};

/// Keys are package folders relative to the workspace root (for a shared
/// module: 'modules/common/domain'); '.' is the app itself. A configured
/// folder that does not exist fails the check. Dev-only packages
/// (modules/mock_api) are not listed: they import test-only barrels by
/// design, and every listed lib/ is denied their imports.
const _layers = {
  '.': _Layer(package: 'foo_app', deny: {'package:mock_api/'}),
  'modules/utils': _Layer(
    package: 'utils',
    allow: {'log', 'collection', 'meta'},
    dartLibraries: _pureDart,
  ),
  'modules/domain': _Layer(
    package: 'domain',
    allow: {
      'utils',
      'log',
      'collection',
      'equatable',
      'get_it',
      'meta',
      'rxdart',
    },
    dartLibraries: _pureDart,
  ),
  'modules/data': _Layer(
    package: 'data',
    deny: {
      'package:ui/',
      'package:localization/',
      'package:bloc/',
      'package:bloc_presentation/',
      'package:flutter_bloc/',
      'package:go_router/',
      'package:domain/domain_usecase.dart',
      'package:mock_api/',
    },
  ),
  'modules/localization': _Layer(
    package: 'localization',
    allow: {'flutter', 'flutter_localizations', 'intl'},
  ),
  'modules/logger': _Layer(
    package: 'log',
    allow: {'stack_trace'},
    deny: {'dart:ui', 'dart:html'},
  ),
  'modules/ui': _Layer(
    package: 'ui',
    // Prefixes, so a new Firebase, Google Cloud, or Isar package is covered.
    deny: {
      'package:data/',
      'package:cloud_',
      'package:dio/',
      'package:firebase_',
      'package:generated_api/',
      'package:http/',
      'package:isar',
      'package:mock_api/',
      'package:path_provider/',
      'package:shared_preferences/',
    },
  ),
};

/// A whole directive, so conditional alternatives (`if (dart.library.io)
/// '…'`) are checked like the default URI.
final _directive = RegExp(r'^\s*(?:import|export)\b[^;]*;', multiLine: true);
final _uri = RegExp(r'''['"]([^'"]+)['"]''');

const _baselinePath = 'tool/layer_baseline.txt';

void main(List<String> args) {
  final missing = _layers.keys
      .where((path) => !Directory('$path/lib').existsSync())
      .toList();
  if (missing.isNotEmpty) {
    stderr.writeln('Configured packages without lib/: ${missing.join(', ')}');
    exitCode = 1;
    return;
  }
  final violations = _violations();
  final baselineFile = File(_baselinePath);
  if (args.contains('--write-baseline')) {
    baselineFile.writeAsStringSync(
      violations.isEmpty ? '' : '${violations.join('\n')}\n',
    );
    stdout.writeln('Wrote ${violations.length} known violations.');
    return;
  }
  final baseline = baselineFile.existsSync()
      ? baselineFile.readAsLinesSync().where((line) => line.isNotEmpty).toSet()
      : const <String>{};
  final fresh = violations.where((v) => !baseline.contains(v)).toList();
  final fixed = baseline.difference(violations.toSet());
  for (final line in fixed) {
    stdout.writeln('Fixed, remove from $_baselinePath: $line');
  }
  if (fresh.isEmpty) {
    stdout.writeln('Layer check passed.');
    return;
  }
  for (final violation in fresh) {
    stderr.writeln(violation);
  }
  exitCode = 1;
}

List<String> _violations() {
  final violations = <String>[];
  for (final MapEntry(key: path, value: layer) in _layers.entries) {
    final files = Directory('$path/lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where((file) => !file.path.endsWith('.g.dart'))
        .where((file) => !file.path.endsWith('.freezed.dart'));
    for (final file in files) {
      final source = file.readAsStringSync();
      for (final directive in _directive.allMatches(source)) {
        for (final match in _uri.allMatches(directive.group(0)!)) {
          final uri = match.group(1)!;
          if (_problem(layer, uri) case final problem?) {
            violations.add('${file.path}: $uri ($problem)');
          }
        }
      }
    }
  }
  return violations..sort();
}

String? _problem(_Layer layer, String uri) {
  final name = layer.package;
  if (_testOnly.contains(uri)) return 'test-only barrel';
  if (layer.deny.any(uri.startsWith)) return '$name must not import this';
  if (uri.startsWith('dart:')) {
    final libraries = layer.dartLibraries;
    final library = uri.substring('dart:'.length);
    return libraries == null || libraries.contains(library)
        ? null
        : '$name must stay platform-free';
  }
  if (!uri.startsWith('package:')) return null;
  final package = uri.substring('package:'.length).split('/').first;
  if (package == name) return null;
  if (uri.startsWith('package:$package/src/')) {
    return 'import $package through its barrel';
  }
  final allow = layer.allow;
  if (allow != null && !allow.contains(package)) {
    return '$name may not depend on $package';
  }
  return null;
}
