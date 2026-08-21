import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/data/studio/models/script_recast.dart';
import 'package:novel_studio/data/studio/models/script_recast_knowledge.dart';
import 'package:novel_studio/data/studio/services/script_recast_parser_service.dart';
import 'package:novel_studio/data/workspace/workspace_service.dart';

import '../../tool/import_script_recast_image_set_caches.dart';

void main() {
  group('importScriptRecastImageSetCaches', () {
    late Directory sourceRoot;
    late Directory workspaceRoot;

    setUp(() async {
      sourceRoot = await Directory.systemTemp.createTemp(
        'script-recast-image-set-source-',
      );
      workspaceRoot = await Directory.systemTemp.createTemp(
        'script-recast-image-set-workspace-',
      );
    });

    tearDown(() async {
      if (await sourceRoot.exists()) {
        await sourceRoot.delete(recursive: true);
      }
      if (await workspaceRoot.exists()) {
        await workspaceRoot.delete(recursive: true);
      }
    });

    test('writes one cache for each prompt-bearing child script directory',
        () async {
      final first = Directory('${sourceRoot.path}${Platform.pathSeparator}a');
      final second = Directory('${sourceRoot.path}${Platform.pathSeparator}b');
      final empty =
          Directory('${sourceRoot.path}${Platform.pathSeparator}empty');
      await first.create();
      await second.create();
      await empty.create();
      await File('${first.path}${Platform.pathSeparator}p1.json')
          .writeAsString(jsonEncode({'Description': 'artist:first, garden'}));
      await File('${second.path}${Platform.pathSeparator}p1.json')
          .writeAsString(jsonEncode({'Description': 'artist:second, street'}));
      await File('${empty.path}${Platform.pathSeparator}notes.json')
          .writeAsString('{}');

      final service = WorkspaceService();
      await service.createWorkspace(workspaceRoot.path);

      final report = await importScriptRecastImageSetCaches(
        sourceRoot: sourceRoot.path,
        workspaceRoot: workspaceRoot.path,
      );
      final caches = await service.loadRecastScriptCaches();

      expect(report.written, 2);
      expect(report.skipped, 1);
      expect(report.rows.where((row) => row.preservedAiDraft), isEmpty);
      expect(caches.map((cache) => cache.scriptName).toSet(), {'a', 'b'});
      expect(
        caches.map((cache) => cache.scriptSnapshot['frames']).whereType<List>(),
        everyElement(hasLength(1)),
      );
    });

    test('imports PNG prompts stored only in stealth_pngcomp metadata',
        () async {
      final script = Directory(
        '${sourceRoot.path}${Platform.pathSeparator}stealth-only',
      );
      await script.create();
      await File('${script.path}${Platform.pathSeparator}p10.png').writeAsBytes(
        _pngWithStealthMetadata(
          jsonEncode({
            'Description': 'stealth-only prompt, blue room',
            'Comment': {
              'seed': 24680,
              'steps': 28,
            },
          }),
        ),
      );

      final service = WorkspaceService();
      await service.createWorkspace(workspaceRoot.path);

      final report = await importScriptRecastImageSetCaches(
        sourceRoot: sourceRoot.path,
        workspaceRoot: workspaceRoot.path,
        recursive: true,
      );
      final cache = (await service.loadRecastScriptCaches()).single;
      final frames = (cache.scriptSnapshot['frames'] as List).cast<Map>();
      final parsed = frames.single['parsed'] as Map;

      expect(report.written, 1);
      expect(report.rows.single.frameCount, 1);
      expect(frames.single['fileName'], 'p10.png');
      expect(parsed['baseCaption'], 'stealth-only prompt, blue room');
      expect((parsed['generationParams'] as Map)['seed'], 24680);
    });

    test('Node importer reads stealth_pngcomp PNG alpha metadata', () async {
      final script = Directory(
        '${sourceRoot.path}${Platform.pathSeparator}stealth-node',
      );
      await script.create();
      await File('${script.path}${Platform.pathSeparator}p11.png').writeAsBytes(
        _pngWithStealthMetadata(
          jsonEncode({
            'Description': 'node stealth prompt, night street',
            'Comment': {
              'seed': 13579,
            },
          }),
        ),
      );
      await Directory(
        '${workspaceRoot.path}${Platform.pathSeparator}script_recast'
        '${Platform.pathSeparator}cache',
      ).create(recursive: true);

      final result = await Process.run(
        'node',
        [
          'tool/import_script_recast_image_set_caches_node_20260620.mjs',
          '--source-root',
          sourceRoot.path,
          '--workspace',
          workspaceRoot.path,
          '--recursive',
          '--apply',
        ],
        workingDirectory: Directory.current.path,
      );
      expect(
        result.exitCode,
        0,
        reason: 'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
      );

      final report = jsonDecode(result.stdout as String) as Map;
      final row = (report['rows'] as List)
          .cast<Map>()
          .singleWhere((entry) => entry['script_name'] == 'stealth-node');
      expect(row['frame_count'], 1);
      final cacheFile = File(
        '${workspaceRoot.path}${Platform.pathSeparator}script_recast'
        '${Platform.pathSeparator}cache${Platform.pathSeparator}'
        '${row['cache_file_name']}',
      );
      final cache = jsonDecode(await cacheFile.readAsString()) as Map;
      final frames =
          ((cache['scriptSnapshot'] as Map)['frames'] as List).cast<Map>();
      final parsed = frames.single['parsed'] as Map;

      expect(frames.single['fileName'], 'p11.png');
      expect(parsed['baseCaption'], 'node stealth prompt, night street');
      expect((parsed['generationParams'] as Map)['seed'], 13579);
    });

    test('skips nested image sidecars below a prompt-bearing script directory',
        () async {
      final script =
          Directory('${sourceRoot.path}${Platform.pathSeparator}funds');
      final sidecar = Directory('${script.path}${Platform.pathSeparator}PNG');
      await sidecar.create(recursive: true);
      await File('${script.path}${Platform.pathSeparator}p1.json')
          .writeAsString(jsonEncode({'Description': 'artist:parent, garage'}));
      await File('${sidecar.path}${Platform.pathSeparator}p1.json')
          .writeAsString(jsonEncode({'Description': 'artist:sidecar, garage'}));

      final service = WorkspaceService();
      await service.createWorkspace(workspaceRoot.path);

      final report = await importScriptRecastImageSetCaches(
        sourceRoot: sourceRoot.path,
        workspaceRoot: workspaceRoot.path,
        recursive: true,
      );
      final caches = await service.loadRecastScriptCaches();

      expect(report.written, 1);
      expect(report.skipped, 1);
      expect(caches.map((cache) => cache.scriptName), ['funds']);
      expect(
        report.rows.singleWhere((row) => row.scriptName == 'PNG').status,
        'skipped_nested_sidecar',
      );
    });

    test('keeps a sidecar-like child when its parent has no prompt frames',
        () async {
      final parent =
          Directory('${sourceRoot.path}${Platform.pathSeparator}container');
      final child = Directory('${parent.path}${Platform.pathSeparator}PNG');
      await child.create(recursive: true);
      await File('${parent.path}${Platform.pathSeparator}notes.json')
          .writeAsString('{}');
      await File('${child.path}${Platform.pathSeparator}p1.json')
          .writeAsString(jsonEncode({'Description': 'artist:child, bath'}));

      final service = WorkspaceService();
      await service.createWorkspace(workspaceRoot.path);

      final report = await importScriptRecastImageSetCaches(
        sourceRoot: sourceRoot.path,
        workspaceRoot: workspaceRoot.path,
        recursive: true,
      );
      final caches = await service.loadRecastScriptCaches();

      expect(report.written, 1);
      expect(report.skipped, 1);
      expect(caches.map((cache) => cache.scriptName), ['PNG']);
      expect(
        report.rows.singleWhere((row) => row.scriptName == 'container').status,
        'skipped_no_frames',
      );
    });

    test('does not carry stale mapping from related cache after source changes',
        () async {
      final script =
          Directory('${sourceRoot.path}${Platform.pathSeparator}wakamo');
      await script.create();
      final promptFile = File('${script.path}${Platform.pathSeparator}p1.json');
      await promptFile.writeAsString(
        jsonEncode({'Description': 'wakamo_(blue_archive), black kimono'}),
      );

      final service = WorkspaceService();
      await service.createWorkspace(workspaceRoot.path);
      await importScriptRecastImageSetCaches(
        sourceRoot: sourceRoot.path,
        workspaceRoot: workspaceRoot.path,
        recursive: true,
      );

      final seedCache = (await service.loadRecastScriptCaches()).single;
      await service.saveRecastScriptCache(
        RecastScriptCache(
          scriptId: seedCache.scriptId,
          scriptName: seedCache.scriptName,
          sourceRootPath: seedCache.sourceRootPath,
          sourceFingerprint: seedCache.sourceFingerprint,
          updatedAt: DateTime.now().toUtc(),
          scriptBlockWords: 'keep low-risk import state',
          mapping: RecastMapping(
            id: 'mapping-${seedCache.scriptId}',
            scriptId: seedCache.scriptId,
            roleAssemblies: const [
              RoleAssembly(
                sourceRoleId: 'role-wakamo',
                displayLabel: 'Wakamo',
                stages: [
                  RoleAssemblyStage(
                    id: 'stage-old',
                    label: '旧映射',
                    targetCharacterId: 'stale-target-character',
                    manualParts: RecastPromptParts(
                      identity: 'stale replacement identity',
                    ),
                  ),
                ],
              ),
            ],
          ),
          scriptSnapshot: seedCache.scriptSnapshot,
        ),
      );

      await promptFile.writeAsString(
        jsonEncode({'Description': 'wakamo_(blue_archive), white bikini'}),
      );

      final report = await importScriptRecastImageSetCaches(
        sourceRoot: sourceRoot.path,
        workspaceRoot: workspaceRoot.path,
        recursive: true,
      );
      final imported = (await service.loadRecastScriptCaches()).single;

      expect(report.written, 1);
      expect(report.rows.single.preservedAiDraft, isFalse);
      expect(imported.scriptBlockWords, 'keep low-risk import state');
      expect(imported.mapping.roleAssemblies, isEmpty);
    });

    test('Node importer keeps legacy IDs while normalizing fingerprint paths',
        () async {
      final script =
          Directory('${sourceRoot.path}${Platform.pathSeparator}MixedCase');
      await script.create();
      final frame = File('${script.path}${Platform.pathSeparator}p1.json');
      await frame.writeAsString(
        jsonEncode({'Description': 'alice, red jacket'}),
      );
      await Directory(
        '${workspaceRoot.path}${Platform.pathSeparator}script_recast'
        '${Platform.pathSeparator}cache',
      ).create(recursive: true);

      final result = await Process.run(
        'node',
        [
          'tool/import_script_recast_image_set_caches_node_20260620.mjs',
          '--source-root',
          sourceRoot.path,
          '--workspace',
          workspaceRoot.path,
          '--recursive',
          '--apply',
        ],
        workingDirectory: Directory.current.path,
      );
      expect(
        result.exitCode,
        0,
        reason: 'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
      );

      final report = jsonDecode(result.stdout as String) as Map;
      final row = (report['rows'] as List)
          .cast<Map>()
          .singleWhere((entry) => entry['script_name'] == 'MixedCase');
      final scriptId = row['script_id'] as String;
      expect(
        scriptId,
        ScriptRecastParserService.scriptIdForDirectory(script),
      );
      final cacheFile = File(
        '${workspaceRoot.path}${Platform.pathSeparator}script_recast'
        '${Platform.pathSeparator}cache${Platform.pathSeparator}$scriptId.json',
      );
      final cache = jsonDecode(await cacheFile.readAsString()) as Map;
      final fingerprint = (cache['sourceFingerprint'] as String).split('|');
      final expectedRoot = script.path.replaceAll('\\', '/');
      final expectedFrame = frame.path.replaceAll('\\', '/');
      expect(
        fingerprint[1],
        Platform.isWindows ? expectedRoot.toLowerCase() : expectedRoot,
      );
      expect(
        fingerprint[2],
        contains(
            Platform.isWindows ? expectedFrame.toLowerCase() : expectedFrame),
      );
    });
  });
}

Uint8List _pngWithStealthMetadata(String metadata) {
  const width = 96;
  const height = 96;
  final payload = GZipCodec().encode(utf8.encode(metadata));
  final bitLengthBytes = ByteData(4)..setInt32(0, payload.length * 8);
  final embedded = <int>[
    ...utf8.encode('stealth_pngcomp'),
    ...bitLengthBytes.buffer.asUint8List(),
    ...payload,
  ];
  if (embedded.length * 8 > width * height) {
    throw StateError('Stealth test PNG is too small for metadata.');
  }

  final alpha = Uint8List(width * height)..fillRange(0, width * height, 254);
  for (var bitIndex = 0; bitIndex < embedded.length * 8; bitIndex += 1) {
    final byte = embedded[bitIndex ~/ 8];
    final bit = (byte >> (7 - (bitIndex % 8))) & 1;
    final x = bitIndex ~/ height;
    final y = bitIndex % height;
    alpha[y * width + x] = 254 | bit;
  }

  final rawRows = BytesBuilder(copy: false);
  for (var y = 0; y < height; y += 1) {
    rawRows.addByte(0);
    for (var x = 0; x < width; x += 1) {
      rawRows.add([0, 0, 0, alpha[y * width + x]]);
    }
  }

  final bytes = BytesBuilder();
  bytes.add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  bytes.add(_pngChunk(
    'IHDR',
    Uint8List.fromList([
      ..._uint32(width),
      ..._uint32(height),
      8,
      6,
      0,
      0,
      0,
    ]),
  ));
  bytes.add(_pngChunk(
    'IDAT',
    Uint8List.fromList(ZLibCodec().encode(rawRows.toBytes())),
  ));
  bytes.add(_pngChunk('IEND', Uint8List(0)));
  return bytes.toBytes();
}

Uint8List _pngChunk(String type, Uint8List data) {
  final typeBytes = ascii.encode(type);
  final crcInput = Uint8List.fromList([...typeBytes, ...data]);
  return Uint8List.fromList([
    ..._uint32(data.length),
    ...typeBytes,
    ...data,
    ..._uint32(_crc32(crcInput)),
  ]);
}

Uint8List _uint32(int value) {
  final data = ByteData(4)..setUint32(0, value, Endian.big);
  return data.buffer.asUint8List();
}

int _crc32(List<int> bytes) {
  var crc = 0xffffffff;
  for (final byte in bytes) {
    crc ^= byte;
    for (var bit = 0; bit < 8; bit += 1) {
      crc = (crc & 1) == 1 ? (crc >> 1) ^ 0xedb88320 : crc >> 1;
    }
  }
  return (crc ^ 0xffffffff) & 0xffffffff;
}
