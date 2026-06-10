import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/regenerate_script_recast_ai_cache.dart' as runner;

void main() {
  test(
    'run script recast AI cache regeneration tool',
    () async {
      final argsText = Platform.environment['SCRIPT_RECAST_REGEN_ARGS'] ?? '';
      final args = _splitArgs(argsText);
      expect(
        args,
        isNotEmpty,
        reason: 'Set SCRIPT_RECAST_REGEN_ARGS before running this test.',
      );
      await runner.runRegenerateScriptRecastAiCache(args);
    },
    timeout: const Timeout(Duration(hours: 6)),
  );
}

List<String> _splitArgs(String input) {
  final args = <String>[];
  final buffer = StringBuffer();
  var quote = '';
  var escaped = false;

  void flush() {
    if (buffer.isEmpty) return;
    args.add(buffer.toString());
    buffer.clear();
  }

  for (final unit in input.runes) {
    final char = String.fromCharCode(unit);
    if (escaped) {
      buffer.write(char);
      escaped = false;
      continue;
    }
    if (char == r'\') {
      escaped = true;
      continue;
    }
    if (quote.isNotEmpty) {
      if (char == quote) {
        quote = '';
      } else {
        buffer.write(char);
      }
      continue;
    }
    if (char == '"' || char == "'") {
      quote = char;
      continue;
    }
    if (char.trim().isEmpty) {
      flush();
      continue;
    }
    buffer.write(char);
  }
  if (escaped) {
    buffer.write(r'\');
  }
  flush();
  return args;
}
