// Regex corpus runner for Dart (V8 Irregexp port — ECMAScript-spec parity)
// stdin:  JSON array of {id, pattern, testText, flags}
// stdout: JSON object of {id: {matches: [{match, index}], error}}
// exit code: always 0 — per-pattern errors go in the error field
//
// Run: dart run test/corpus/runners/run_dart.dart < input.json

import 'dart:convert';
import 'dart:io';

void main() {
  final input = stdin.transform(utf8.decoder).join();
  input.then((raw) {
    final entries = jsonDecode(raw) as List<dynamic>;
    final results = <String, Map<String, dynamic>>{};
    for (final e in entries.cast<Map<String, dynamic>>()) {
      final id = e['id'] as String;
      try {
        final flags = (e['flags'] as String?) ?? '';
        final rx = RegExp(
          e['pattern'] as String,
          multiLine: flags.contains('m'),
          caseSensitive: !flags.contains('i'),
          dotAll: flags.contains('s'),
          unicode: flags.contains('u'),
        );
        final text = e['testText'] as String;
        final matches = <Map<String, dynamic>>[];
        // Always emit all matches regardless of 'g' flag — see docs/v1-corpus-fix-spec.md
        // and matches the bridge's behavior.
        for (final m in rx.allMatches(text)) {
          matches.add({'match': m.group(0), 'index': m.start});
        }
        results[id] = {'matches': matches, 'error': null};
      } catch (err) {
        results[id] = {'matches': [], 'error': err.toString()};
      }
    }
    stdout.write(jsonEncode(results));
  });
}
