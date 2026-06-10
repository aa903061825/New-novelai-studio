import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('known user-facing English strings are not hardcoded in UI', () {
    final offenders = <String, List<String>>{};
    const forbiddenSnippets = [
      r'No metadata found in imported picture.',
      r'Found metadata in imported picture.',
      r'Import image metadata?',
      r"const Text('Cancel')",
      r"const Text('OK')",
      r'Import parameters',
      r'Imported $count metadata fields.',
      r'Target image size',
      r'Target size set to ${size.width} x ${size.height}.',
      r'Invalid value. Please enter a number between 0.0 and 1.0.',
      r'Debug Settings',
      r'Debug API',
      r'Debug API Endpoint',
      r'Reset welcome dialog version',
      r'Legacy Prompt Conditioning Mode',
      r"Text('Global')",
      r'Defaults:',
      r'Manual:',
      r"labelText: 'Sampler'",
      r"labelText: 'Noise Schedule'",
      r"labelText: 'Width'",
      r"labelText: 'Height'",
      r'Dynamic Thresholding',
      r"labelText: 'Seed'",
      r"const Text('Save')",
      r'Delete this asset?',
      r"const Text('Delete')",
      r'Add custom category',
      r'Prewarm tag cache',
      r'Add character',
      r'Add artist chain',
      r'Add tag',
      r'Edit asset',
      r'Delete asset',
      r"label: const Text('Send')",
      r"tooltip: 'Previous'",
      r"tooltip: 'Next'",
      r"tooltip: 'Delete'",
      r"tooltip: 'Rename'",
      r"tooltip: 'Close'",
      r"tooltip: fullscreen ? 'Exit fullscreen' : 'Fullscreen'",
      r'Show details',
      r'Preview image',
      r'No image path',
      r'Image file not found',
      r'Select language...',
      r'roles ${summary.roleCount}',
      r'chunks ${summary.chunkCount}',
      r'attention ${summary.attentionCount}',
      r'????? AI ????',
    ];

    for (final entity in Directory('lib/ui').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      final matches = [
        for (final snippet in forbiddenSnippets)
          if (source.contains(snippet)) snippet,
      ];
      if (matches.isNotEmpty) {
        offenders[entity.path] = matches;
      }
    }

    expect(offenders, isEmpty);
  });
}
