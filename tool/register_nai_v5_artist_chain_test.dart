import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:novel_studio/data/models/generation_capabilities.dart';

const _defaultWorkspace =
    r'C:\Users\admin\AppData\Roaming\org.exception0x0194\nai3_autodraw\novel_studio';

Future<void> main(List<String> args) async {
  final options = _Options.parse(args);
  final workspace = Directory(options.workspacePath);
  final queueFile = File(options.queuePath);
  if (!await workspace.exists()) {
    throw StateError('Workspace does not exist: ${workspace.path}');
  }
  if (!await queueFile.exists()) {
    throw StateError('V5 test queue does not exist: ${queueFile.path}');
  }

  final queue = _readList(queueFile);
  final payloads = await _readPayloads(options.payloadManifestPath);
  final artistFile = File(
    '${workspace.path}${Platform.pathSeparator}library'
    '${Platform.pathSeparator}artist_chains.json',
  );
  if (!await artistFile.exists()) {
    throw StateError(
        'Artist-chain library file does not exist: ${artistFile.path}');
  }
  final decodedChains = jsonDecode(await artistFile.readAsString());
  if (decodedChains is! List) {
    throw const FormatException('artist_chains.json must be a JSON array.');
  }
  final rawChains = [
    for (final entry in decodedChains)
      if (entry is Map) entry.cast<String, dynamic>(),
  ];
  final chainsById = {
    for (final chain in rawChains)
      if (chain['id'] is String) chain['id'] as String: chain,
  };
  final manifestEntries = <Map<String, dynamic>>[];
  final replacedChains = <String>{};
  var registeredCount = 0;

  for (final item in queue) {
    final chainId = item['artistChainId'] as String?;
    final outputPath = item['outputPath'] as String?;
    if (chainId == null || outputPath == null) continue;
    final chain = chainsById[chainId];
    if (chain == null) {
      manifestEntries.add({
        'status': 'failed',
        'reason': 'artist chain not found',
        'artistChainId': chainId,
        'attempt': item['attempt'],
      });
      continue;
    }
    final image = File(outputPath);
    if (!await image.exists()) {
      manifestEntries.add({
        'status': 'failed',
        'reason': 'image not generated',
        'artistChainId': chainId,
        'artistChainName': chain['name']?.toString() ?? chainId,
        'outputPath': image.path,
        'attempt': item['attempt'],
      });
      continue;
    }

    final reference = _relativeReference(workspace.path, image.path);
    final refs = _decodeModelPreviewRefs(chain['modelPreviewRefs']);
    final v5Refs = refs.putIfAbsent(generationPreviewFamilyV5, () => []);
    if (item['replaceV5'] == true && replacedChains.add(chainId)) {
      v5Refs.clear();
    }
    if (!v5Refs.contains(reference)) {
      v5Refs.add(reference);
      chain['modelPreviewRefs'] = refs;
      registeredCount += 1;
    }

    final payloadEntry = payloads[item['id'] as String?];
    final payload = payloadEntry?['payload'];
    final payloadJson = payload is Map
        ? jsonEncode(payload)
        : jsonEncode({
            'prompt': item['prompt'],
            'negativePrompt': item['negativePrompt'],
            'model': item['model'],
            'seed': item['seed'],
          });
    final bytes = await image.readAsBytes();
    manifestEntries.add({
      'status': 'generated',
      'artistChainId': chainId,
      'artistChainName': chain['name']?.toString() ?? chainId,
      'imageRef': reference,
      'absoluteImagePath': image.path,
      'source': 'NovelAI API',
      'model': item['model'] ?? naiDiffusion5Full,
      'width': item['width'] ?? 832,
      'height': item['height'] ?? 1216,
      'seed': item['seed'],
      'sampler': item['sampler'] ?? 'k_euler_ancestral',
      'steps': item['steps'] ?? 28,
      'scale': item['scale'] ?? 6.5,
      'cfgRescale': item['cfg_rescale'] ?? 0.1,
      'qualityPreset': item['quality_preset'] ?? 'none',
      'ucPresetMode': item['uc_preset_mode'] ?? 'none',
      'vibeTransfer': 'omitted: NAI V5 does not support Vibe Transfer',
      'qualityTerms': item['qualityTerms'],
      'mediumGuard': item['mediumGuard'],
      'mediumGuardPolicy': item['mediumGuardPolicy'],
      'attempt': item['attempt'],
      'characterCardId': item['characterCardId'],
      'characterCardName': item['characterCardName'],
      'characterCardPrompt': item['characterCardPrompt'],
      'characterCardIdentityTags': item['characterCardIdentityTags'],
      'characterCardAnchorTags': item['characterCardAnchorTags'],
      'positivePrompt': item['prompt'],
      'negativePrompt': item['negativePrompt'],
      'payloadSha256': sha256.convert(utf8.encode(payloadJson)).toString(),
      'payload': payload ?? jsonDecode(payloadJson),
      'pngCommentVerification': _pngCommentVerification(bytes),
    });
  }

  if (registeredCount > 0) {
    final backup = File(
      '${artistFile.path}.bak-before-v5-test-${_timestamp()}.json',
    );
    if (await artistFile.exists()) {
      await artistFile.copy(backup.path);
      stdout.writeln('Backup: ${backup.path}');
    }
    final tempFile = File('${artistFile.path}.tmp-v5-test');
    await tempFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(rawChains),
    );
    if (await artistFile.exists()) await artistFile.delete();
    await tempFile.rename(artistFile.path);
  }

  final manifestFile = File(options.manifestPath);
  await manifestFile.parent.create(recursive: true);
  await manifestFile.writeAsString(
    const JsonEncoder.withIndent('  ').convert({
      'schemaVersion': 2,
      'generatedAt': DateTime.now().toIso8601String(),
      'testType': 'artist-chain-v5-controlled-preview',
      'testRunId': queue.isEmpty ? null : queue.first['testRunId'],
      'model': naiDiffusion5Full,
      'previewFamily': generationPreviewFamilyV5,
      'dimensions': {'width': 832, 'height': 1216},
      'seedPolicy': 'same fixed seed per chain',
      'seed': queue.isEmpty ? null : queue.first['seed'],
      'sampler': 'k_euler_ancestral',
      'steps': 28,
      'scale': 6.5,
      'cfgRescale': 0.1,
      'vibeTransfer': 'not used: unsupported by NAI V5',
      'qualityTerms': queue.isEmpty ? null : queue.first['qualityTerms'],
      'qualityPreset': queue.isEmpty ? null : queue.first['quality_preset'],
      'ucPresetMode': queue.isEmpty ? null : queue.first['uc_preset_mode'],
      'mediumGuard': queue.isEmpty ? null : queue.first['mediumGuard'],
      'mediumGuardPolicy':
          queue.isEmpty ? null : queue.first['mediumGuardPolicy'],
      'attemptCount':
          queue.map((item) => item['attempt']).whereType<int>().toSet().length,
      'characterSource': 'workspace character-card library',
      'characterAssignment':
          'deterministic shuffle by the test seed; one card per artist chain',
      'v5Registration':
          'replace the prior V5 ref for each successfully generated chain',
      'entries': manifestEntries,
    }),
  );

  stdout.writeln(
    'Registered $registeredCount V5 preview ref(s); '
    '${manifestEntries.where((entry) => entry['status'] == 'generated').length} '
    'image(s) generated.',
  );
  stdout.writeln('Manifest: ${manifestFile.path}');
}

List<Map<String, dynamic>> _readList(File file) {
  final decoded = jsonDecode(file.readAsStringSync());
  if (decoded is! List) {
    throw const FormatException('V5 test queue must be a JSON array.');
  }
  return [
    for (final entry in decoded)
      if (entry is Map) entry.cast<String, dynamic>(),
  ];
}

Future<Map<String, Map<String, dynamic>>> _readPayloads(String path) async {
  final file = File(path);
  if (!await file.exists()) return {};
  final decoded = jsonDecode(await file.readAsString());
  if (decoded is! List) return {};
  return {
    for (final entry in decoded)
      if (entry is Map && entry['id'] is String)
        entry['id'] as String: entry.cast<String, dynamic>(),
  };
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

String _relativeReference(String workspacePath, String imagePath) {
  final workspace = _normalize(workspacePath);
  final image = _normalize(imagePath);
  if (!image.startsWith('$workspace/')) {
    throw StateError('Generated image is outside workspace: $imagePath');
  }
  return image.substring(workspace.length + 1);
}

String _normalize(String path) => path
    .replaceAll('\\', '/')
    .replaceAll(RegExp(r'/+'), '/')
    .replaceFirst(RegExp(r'/$'), '')
    .toLowerCase();

Map<String, dynamic> _pngCommentVerification(Uint8List bytes) {
  const signature = [137, 80, 78, 71, 13, 10, 26, 10];
  if (bytes.length < signature.length || !_startsWithBytes(bytes, signature)) {
    return const {'status': 'invalid-png'};
  }
  var offset = signature.length;
  while (offset + 12 <= bytes.length) {
    final length = _uint32(bytes, offset);
    final typeOffset = offset + 4;
    final dataOffset = offset + 8;
    final end = dataOffset + length + 4;
    if (end > bytes.length) break;
    final type =
        String.fromCharCodes(bytes.sublist(typeOffset, typeOffset + 4));
    if (type == 'tEXt' || type == 'iTXt') {
      final data = bytes.sublist(dataOffset, dataOffset + length);
      final text = String.fromCharCodes(data);
      final lower = text.toLowerCase();
      if (lower.contains('comment') || lower.contains('description')) {
        return {
          'status': 'present',
          'chunk': type,
          'sha256': sha256.convert(data).toString(),
        };
      }
    }
    offset = end;
    if (type == 'IEND') break;
  }
  return const {'status': 'absent'};
}

bool _startsWithBytes(Uint8List bytes, List<int> prefix) {
  for (var index = 0; index < prefix.length; index++) {
    if (bytes[index] != prefix[index]) return false;
  }
  return true;
}

int _uint32(Uint8List bytes, int offset) {
  return (bytes[offset] << 24) |
      (bytes[offset + 1] << 16) |
      (bytes[offset + 2] << 8) |
      bytes[offset + 3];
}

String _timestamp() => DateTime.now()
    .toIso8601String()
    .replaceAll(RegExp(r'[^0-9]'), '')
    .substring(0, 14);

class _Options {
  final String workspacePath;
  final String queuePath;
  final String payloadManifestPath;
  final String manifestPath;

  const _Options({
    required this.workspacePath,
    required this.queuePath,
    required this.payloadManifestPath,
    required this.manifestPath,
  });

  factory _Options.parse(List<String> args) {
    var workspacePath = _defaultWorkspace;
    String? queuePath;
    String? payloadManifestPath;
    String? manifestPath;
    for (final arg in args) {
      if (arg.startsWith('--workspace=')) {
        workspacePath = arg.substring('--workspace='.length);
      } else if (arg.startsWith('--queue=')) {
        queuePath = arg.substring('--queue='.length);
      } else if (arg.startsWith('--payload-manifest=')) {
        payloadManifestPath = arg.substring('--payload-manifest='.length);
      } else if (arg.startsWith('--manifest=')) {
        manifestPath = arg.substring('--manifest='.length);
      }
    }
    final outputDirectory = '$workspacePath${Platform.pathSeparator}assets'
        '${Platform.pathSeparator}references${Platform.pathSeparator}'
        'artist-chain-v5-previews';
    return _Options(
      workspacePath: workspacePath,
      queuePath: queuePath ??
          '$outputDirectory${Platform.pathSeparator}v5-test-queue.json',
      payloadManifestPath: payloadManifestPath ??
          '$outputDirectory${Platform.pathSeparator}v5-request-payloads.json',
      manifestPath: manifestPath ??
          '$outputDirectory${Platform.pathSeparator}v5-test-manifest.json',
    );
  }
}
