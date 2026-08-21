import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final currentPath = _argument(args, '--current=') ??
      r'C:\Users\admin\AppData\Roaming\org.exception0x0194\nai3_autodraw\novel_studio\assets\references\artist-chain-v5-previews\r3c-strong-quality-conditional\v5-deletion-proposal.json';
  final priorPath = _argument(args, '--prior=') ??
      r'C:\Users\admin\AppData\Roaming\org.exception0x0194\nai3_autodraw\novel_studio\assets\references\artist-chain-v5-previews\r3c-strong-quality-conditional\v5-deletion-proposal.json.bak-before-delete-20260821174345.json';
  final current = await _read(currentPath);
  final prior = await _read(priorPath);
  final byId = <String, Map<String, dynamic>>{};
  for (final raw in [
    ...(prior['removedArtistChains'] as List? ?? const []),
    ...(current['removedArtistChains'] as List? ?? const []),
  ]) {
    if (raw is Map) {
      final entry = raw.cast<String, dynamic>();
      final id = entry['artistChainId']?.toString() ?? '';
      if (id.isNotEmpty) byId[id] = entry;
    }
  }
  final allFiles = <String>{
    for (final source in [prior, current])
      ...(source['deletedFiles'] as List? ?? const []).whereType<String>(),
  };
  final allBackups = <String>{
    for (final source in [prior, current])
      ...(source['backups'] as List? ?? const []).whereType<String>(),
  };
  final removedRefs = <String>{
    for (final chain in byId.values) ...[
      ...(chain['removedV5Refs'] as List? ?? const []).whereType<String>(),
      ...(chain['removedV45Refs'] as List? ?? const []).whereType<String>(),
    ],
  };
  final merged = <String, dynamic>{
    'schemaVersion': 1,
    'status': 'executed',
    'generatedAt': DateTime.now().toIso8601String(),
    'keptException': null,
    'rootCauseNote': 'ningen_mame 2号 画师串过长且结构化/原始 prompt 重复，造成头像墙；用户确认一并删除。',
    'removedArtistChains': byId.values.toList(growable: false),
    'summary': {
      'removedArtistChains': byId.length,
      'removedUnsharedReferences': removedRefs.length,
      'removedFiles': allFiles.length,
      'remainingArtistChains': current['summary'] is Map
          ? (current['summary'] as Map)['remainingArtistChains']
          : null,
      'sharedReferencesNotDeleted': 0,
    },
    'backups': allBackups.toList(growable: false),
    'deletedFiles': allFiles.toList(growable: false),
    'sharedReferencesNotDeleted': const <String>[],
  };
  await File(currentPath).writeAsString(
    const JsonEncoder.withIndent('  ').convert(merged),
  );
  stdout.writeln('Merged deletion log: $currentPath');
  stdout.writeln('Removed chain records: ${byId.length}');
}

Future<Map<String, dynamic>> _read(String path) async {
  final decoded = jsonDecode(await File(path).readAsString());
  if (decoded is! Map) throw FormatException('Expected JSON object: $path');
  return decoded.cast<String, dynamic>();
}

String? _argument(List<String> args, String prefix) {
  for (final arg in args) {
    if (arg.startsWith(prefix)) return arg.substring(prefix.length);
  }
  return null;
}
