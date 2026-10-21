// The coverage gate (testing rule → Rules): line coverage of handwritten
// code per package, after the closed list in coverage-exclusions.txt.
// Run by scripts/test.sh unit after each package wrote coverage/lcov.info.
// Usage: dart run tool/check_coverage.dart [--min=100] <package folder>...
import 'dart:io';

void main(List<String> args) {
  final minArg = args.firstWhere(
    (arg) => arg.startsWith('--min='),
    orElse: () => '--min=100',
  );
  final min = double.parse(minArg.substring('--min='.length));
  final exclusions = File('coverage-exclusions.txt')
      .readAsLinesSync()
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty && !line.startsWith('#'))
      .map(_globToRegExp)
      .toList();
  var failed = false;
  for (final package in args.where((arg) => !arg.startsWith('--'))) {
    if (!Directory('$package/test').existsSync()) {
      stderr.writeln('$package has no test/ folder: every package is tested');
      failed = true;
      continue;
    }
    final lcov = File('$package/coverage/lcov.info');
    if (!lcov.existsSync()) {
      stderr.writeln('$package/coverage/lcov.info is missing: run its tests');
      failed = true;
      continue;
    }
    bool isExcluded(String file) =>
        exclusions.any((pattern) => pattern.hasMatch(file));
    var lines = 0;
    var hits = 0;
    final missed = <String>[];
    final reported = <String>{};
    var file = '';
    var excluded = false;
    for (final line in lcov.readAsLinesSync()) {
      if (line.startsWith('SF:')) {
        file = _packagePath(line.substring(3));
        reported.add(file);
        excluded = isExcluded(file);
      } else if (line.startsWith('DA:') && !excluded) {
        final [number, count, ...] = line.substring(3).split(',');
        lines++;
        if (int.parse(count) > 0) {
          hits++;
        } else {
          missed.add('$package/$file:$number');
        }
      }
    }
    // A file no test loads never appears in lcov.info: count it as missed.
    final unloaded = Directory('$package/lib')
        .listSync(recursive: true)
        .whereType<File>()
        .map((entry) => _packagePath(entry.path))
        .where((path) => path.endsWith('.dart'))
        .where((path) => !reported.contains(path) && !isExcluded(path))
        .where((path) => _hasCode(File('$package/$path')))
        .toList();
    final percent = lines == 0 ? 100.0 : hits * 100 / lines;
    stdout.writeln('$package: ${percent.toStringAsFixed(1)}% of $lines lines');
    if (percent < min || unloaded.isNotEmpty) {
      failed = true;
      for (final path in unloaded) {
        stderr.writeln('$package/$path: not loaded by any test');
      }
      missed.take(50).forEach(stderr.writeln);
    }
  }
  if (failed) exit(1);
}

/// False for files without executable lines, which never appear in
/// lcov.info: barrels (directives only) and declaration-only files (abstract
/// interfaces, mixins of abstract members, typedefs). Strings, comments, and
/// everything inside parentheses (parameter lists with their defaults, even
/// across lines) are dropped first; what is left has code when a line has a
/// body or an initializer (`=>`, `=`, a `{` that is not a type
/// declaration's) or declares a constructor (`Foo(` or `const Foo.named(`).
bool _hasCode(File file) =>
    _outsideParentheses(file.readAsStringSync()).split('\n').any(_lineHasCode);

bool _lineHasCode(String line) {
  var text = line.trim();
  if (_typeDeclaration.hasMatch(text)) {
    // `class Foo {` declares; anything after its brace is checked as code.
    final brace = text.indexOf('{');
    if (brace < 0) return false;
    text = text.substring(brace + 1).trim();
  }
  if (text.isEmpty ||
      text == ';' ||
      RegExp(
        r'^(import|export|library|part|show|hide|if|as|typedef)\b',
      ).hasMatch(text)) {
    return false;
  }
  if (text.contains('=')) return true;
  if (text.contains('{') && text != '}') return true;
  return _constructor.hasMatch(text);
}

final _typeDeclaration = RegExp(
  r'^((abstract|sealed|base|final|interface|mixin)\s+)*'
  r'(class|mixin|enum|extension)\b',
);
final _constructor = RegExp(r'^(const\s+)?[A-Z]\w*(\.\w+)?\(');

/// The source without comments, string contents, and anything between
/// parentheses (the parentheses stay, so `dispose({bool x = false});`
/// becomes `dispose();`).
String _outsideParentheses(String source) {
  final text = source
      .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
      .replaceAll(RegExp(r"'(?:\\.|[^'\\\n])*'"), "''")
      .replaceAll(RegExp(r'"(?:\\.|[^"\\\n])*"'), '""')
      .replaceAll(RegExp(r'//.*'), '');
  final out = StringBuffer();
  var depth = 0;
  for (final char in text.split('')) {
    if (char == '(') {
      if (depth == 0) out.write(char);
      depth++;
    } else if (char == ')') {
      depth = depth > 0 ? depth - 1 : 0;
      if (depth == 0) out.write(char);
    } else if (depth == 0 || char == '\n') {
      out.write(char);
    }
  }
  return out.toString();
}

/// `lib/…` relative to the package, whatever form the reporter wrote.
String _packagePath(String path) {
  final normalized = path.replaceAll(r'\', '/');
  if (normalized.startsWith('lib/')) return normalized;
  final index = normalized.lastIndexOf('/lib/');
  return index < 0 ? normalized : normalized.substring(index + 1);
}

/// `*` within a path segment, `**/` across segments.
RegExp _globToRegExp(String glob) {
  final pattern = StringBuffer('^');
  for (var i = 0; i < glob.length; i++) {
    final char = glob[i];
    if (char != '*') {
      pattern.write(RegExp.escape(char));
    } else if (glob.startsWith('**/', i)) {
      pattern.write('(.*/)?');
      i += 2;
    } else if (glob.startsWith('**', i)) {
      pattern.write('.*');
      i += 1;
    } else {
      pattern.write('[^/]*');
    }
  }
  pattern.write(r'$');
  return RegExp(pattern.toString());
}
