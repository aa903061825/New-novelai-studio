import 'dart:convert';
import 'dart:io';

import 'package:novel_studio/data/models/generation_capabilities.dart';

const _defaultWorkspace =
    r'C:\Users\admin\AppData\Roaming\org.exception0x0194\nai3_autodraw\novel_studio';

Future<void> main(List<String> args) async {
  var workspacePath = _defaultWorkspace;
  for (final arg in args) {
    if (arg.startsWith('--workspace=')) {
      workspacePath = arg.substring('--workspace='.length);
    }
  }
  final artistFile = File(
    '$workspacePath${Platform.pathSeparator}library'
    '${Platform.pathSeparator}artist_chains.json',
  );
  final decoded = jsonDecode(await artistFile.readAsString());
  if (decoded is! List) {
    throw const FormatException('artist_chains.json must be a JSON array.');
  }

  var changedChains = 0;
  var classifiedRefs = 0;
  final updated = [
    for (final entry in decoded)
      if (entry is Map)
        _classify(
          entry.cast<String, dynamic>(),
          onChanged: () => changedChains += 1,
          onRefClassified: () => classifiedRefs += 1,
        )
      else
        entry,
  ];

  if (changedChains == 0) {
    stdout.writeln('No unclassified legacy artist preview refs found.');
    return;
  }

  final backup = File(
    '${artistFile.path}.bak-before-preview-family-migration-${_timestamp()}.json',
  );
  await artistFile.copy(backup.path);
  final tempFile = File('${artistFile.path}.tmp-preview-family-migration');
  await tempFile.writeAsString(
    const JsonEncoder.withIndent('  ').convert(updated),
  );
  if (await artistFile.exists()) await artistFile.delete();
  await tempFile.rename(artistFile.path);
  stdout.writeln('Classified $classifiedRefs legacy ref(s) as V4.5.');
  stdout.writeln('Updated $changedChains artist chain(s).');
  stdout.writeln('Backup: ${backup.path}');
}

Map<String, dynamic> _classify(
  Map<String, dynamic> chain, {
  required void Function() onChanged,
  required void Function() onRefClassified,
}) {
  final imageRefs = [
    if (chain['imageRefs'] is List)
      ...(chain['imageRefs'] as List).whereType<String>(),
  ];
  if (imageRefs.isEmpty) return chain;
  final modelPreviewRefs = _decodeModelPreviewRefs(chain['modelPreviewRefs']);
  final classified = modelPreviewRefs.values.expand((refs) => refs).toSet();
  final v45Refs =
      modelPreviewRefs.putIfAbsent(generationPreviewFamilyV45, () => []);
  var changed = false;
  for (final ref in imageRefs) {
    final trimmed = ref.trim();
    if (trimmed.isEmpty || classified.contains(trimmed)) continue;
    v45Refs.add(trimmed);
    classified.add(trimmed);
    changed = true;
    onRefClassified();
  }
  if (changed) {
    chain['modelPreviewRefs'] = modelPreviewRefs;
    onChanged();
  }
  return chain;
}

Map<String, List<String>> _decodeModelPreviewRefs(dynamic value) {
  if (value is! Map) return {};
  return {
    for (final entry in value.entries)
      if (entry.key is String && entry.value is List)
        entry.key as String: [
          ...(entry.value as List).whereType<String>(),
        ],
  };
}

String _timestamp() => DateTime.now()
    .toIso8601String()
    .replaceAll(RegExp(r'[^0-9]'), '')
    .substring(0, 14);
