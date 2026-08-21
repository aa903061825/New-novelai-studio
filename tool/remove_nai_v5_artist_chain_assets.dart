import 'dart:convert';
import 'dart:io';

const _defaultWorkspace =
    r'C:\Users\admin\AppData\Roaming\org.exception0x0194\nai3_autodraw\novel_studio';
const _defaultTargetIds = <String>{
  'legacy-artist-sheet-r2c1', // tiv
  'legacy-artist-sheet-r2c3', // z3zz4
  'legacy-artist-sheet-r4c1', // dishwasher1910
  'legacy-artist-sheet-r4c5', // 3j_dangan
  'legacy-artist-sheet-r8c3', // stu_dts
  'legacy-artist-sheet-r12c1', // nixeu
  'legacy-artist-sheet-r12c3', // torino_aqua
};
const _keptExceptionId = 'legacy-character-sheet-r1-outfit-7-artist-chain';

Future<void> main(List<String> args) async {
  final options = _Options.parse(args);
  final workspace = Directory(options.workspacePath);
  if (!await workspace.exists()) {
    throw StateError('Workspace does not exist: ${workspace.path}');
  }
  final libraryFile = File(
    '${workspace.path}${Platform.pathSeparator}library${Platform.pathSeparator}artist_chains.json',
  );
  final manifestFile = File(
    '${options.runDirectory}${Platform.pathSeparator}v5-test-manifest.json',
  );
  final queueFile = File(
    '${options.runDirectory}${Platform.pathSeparator}v5-test-queue.json',
  );
  final payloadFile = File(
    '${options.runDirectory}${Platform.pathSeparator}v5-request-payloads.json',
  );
  final proposalFile = File(
    '${options.runDirectory}${Platform.pathSeparator}v5-deletion-proposal.json',
  );

  final libraryDecoded = jsonDecode(await libraryFile.readAsString());
  if (libraryDecoded is! List) {
    throw const FormatException('artist_chains.json must be a JSON array.');
  }
  final library = [
    for (final raw in libraryDecoded)
      if (raw is Map) raw.cast<String, dynamic>(),
  ];
  final targetIds = options.targetIds;
  if (targetIds.contains(_keptExceptionId) && !options.allowKeptException) {
    throw StateError('The explicitly kept exception chain cannot be deleted.');
  }
  final removed = [
    for (final chain in library)
      if (targetIds.contains(chain['id']?.toString())) chain,
  ];
  final missingIds = targetIds
      .where((id) => !removed.any((chain) => chain['id']?.toString() == id))
      .toList(growable: false);
  if (missingIds.isNotEmpty) {
    throw StateError(
        'Target artist-chain id(s) not found: ${missingIds.join(', ')}');
  }
  if (!library.any((chain) => chain['id']?.toString() == _keptExceptionId)) {
    throw StateError(
        'Kept exception chain is missing from artist_chains.json.');
  }

  final remaining = [
    for (final chain in library)
      if (!targetIds.contains(chain['id']?.toString())) chain,
  ];
  final removedRefs = _collectRefs(removed);
  final remainingRefs = _collectRefs(remaining);
  final unsharedRefs = removedRefs.difference(remainingRefs);

  final timestamp = _timestamp();
  final backups = <String>[];
  for (final file in [
    libraryFile,
    manifestFile,
    queueFile,
    payloadFile,
    proposalFile
  ]) {
    if (await file.exists()) {
      final backup = File('${file.path}.bak-before-delete-$timestamp.json');
      await file.copy(backup.path);
      backups.add(backup.path);
    }
  }

  final removedFiles = <String>[];
  final sharedFiles = <String>[];
  for (final relativeRef in unsharedRefs) {
    final file = _resolveWorkspaceFile(workspace, relativeRef);
    if (file == null) {
      sharedFiles.add('outside-workspace: $relativeRef');
      continue;
    }
    if (await file.exists()) {
      if (options.dryRun) {
        removedFiles.add(file.path);
      } else {
        await file.delete();
        removedFiles.add(file.path);
      }
    }
  }

  final manifestDecoded = await _readOptionalJsonMap(manifestFile);
  if (manifestDecoded != null) {
    final entries = [
      for (final raw in (manifestDecoded['entries'] as List? ?? const []))
        if (raw is Map && !targetIds.contains(raw['artistChainId']?.toString()))
          raw.cast<String, dynamic>(),
    ];
    manifestDecoded['entries'] = entries;
    manifestDecoded['deletedArtistChainIds'] = targetIds.toList()..sort();
    manifestDecoded['deletedArtistChainNames'] = [
      for (final chain in removed) chain['name']?.toString() ?? '',
    ];
    manifestDecoded['deletedAt'] = DateTime.now().toIso8601String();
    if (!options.dryRun) await _writeJson(manifestFile, manifestDecoded);
  }

  final queueDecoded = await _readOptionalJsonList(queueFile);
  if (queueDecoded != null && !options.dryRun) {
    await _writeJson(queueFile, [
      for (final raw in queueDecoded)
        if (!targetIds.contains(raw['artistChainId']?.toString())) raw,
    ]);
  }
  final payloadDecoded = await _readOptionalJsonList(payloadFile);
  if (payloadDecoded != null && !options.dryRun) {
    final removedQueueIds = {
      for (final raw in queueDecoded ?? const <Map<String, dynamic>>[])
        if (targetIds.contains(raw['artistChainId']?.toString()))
          raw['id']?.toString(),
    };
    await _writeJson(payloadFile, [
      for (final raw in payloadDecoded)
        if (!removedQueueIds.contains(raw['id']?.toString())) raw,
    ]);
  }

  final reportCrops = Directory(
    '${options.runDirectory}${Platform.pathSeparator}report${Platform.pathSeparator}crops',
  );
  // The target crop names are derived from the deleted source image names;
  // remove them even though crops are not part of the library manifest.
  final targetManifest = await _readOptionalJsonMap(
    File('${manifestFile.path}.bak-before-delete-$timestamp.json'),
  );
  if (targetManifest != null) {
    final targetEntries = [
      for (final raw in (targetManifest['entries'] as List? ?? const []))
        if (raw is Map && targetIds.contains(raw['artistChainId']?.toString()))
          raw.cast<String, dynamic>(),
    ];
    for (final entry in targetEntries) {
      final source = entry['absoluteImagePath']?.toString() ?? '';
      final base = _fileName(source);
      final crop = File(
        '${reportCrops.path}${Platform.pathSeparator}$base-original-crop.png',
      );
      if (await crop.exists()) {
        if (!options.dryRun) await crop.delete();
        removedFiles.add(crop.path);
      }
    }
  }

  final keptException = remaining.any(
    (chain) => chain['id']?.toString() == _keptExceptionId,
  );
  final deletionRecord = <String, dynamic>{
    'schemaVersion': 1,
    'status': options.dryRun ? 'dry-run' : 'executed',
    'generatedAt': DateTime.now().toIso8601String(),
    'keptException': keptException
        ? {
            'artistChainId': _keptExceptionId,
            'reason': '按用户要求保留，待后续另行处理其头像墙触发原因。',
          }
        : null,
    'removedArtistChains': [
      for (final chain in removed)
        {
          'artistChainId': chain['id'],
          'artistChainName': chain['name'],
          'removedV5Refs': [
            for (final ref in _collectModelRefs(chain, 'v5')) ref,
          ],
          'removedV45Refs': [
            for (final ref in _collectModelRefs(chain, 'v4_5')) ref,
          ],
        },
    ],
    'summary': {
      'removedArtistChains': removed.length,
      'removedUnsharedReferences': unsharedRefs.length,
      'removedFiles': removedFiles.length,
      'remainingArtistChains': remaining.length,
      'sharedReferencesNotDeleted': sharedFiles.length,
    },
    'backups': backups,
    'deletedFiles': removedFiles,
    'sharedReferencesNotDeleted': sharedFiles,
  };
  if (!options.dryRun) {
    await _writeJson(proposalFile, deletionRecord);
  }

  if (!options.dryRun) await _writeJson(libraryFile, remaining);
  stdout.writeln(
    '${options.dryRun ? 'Would remove' : 'Removed'} ${removed.length} artist chain(s).',
  );
  stdout.writeln(
    '${options.dryRun ? 'Would remove' : 'Removed'} ${removedFiles.length} file(s).',
  );
  stdout.writeln(
    keptException
        ? 'Kept exception: $_keptExceptionId'
        : 'No exception chain retained.',
  );
  stdout.writeln('Deletion log: ${proposalFile.path}');
}

Set<String> _collectRefs(List<Map<String, dynamic>> chains) {
  final refs = <String>{};
  for (final chain in chains) {
    refs.addAll(_collectModelRefs(chain, 'v5'));
    refs.addAll(_collectModelRefs(chain, 'v4_5'));
    final rawImageRefs = chain['imageRefs'];
    if (rawImageRefs is List) refs.addAll(rawImageRefs.whereType<String>());
  }
  return refs;
}

List<String> _collectModelRefs(Map<String, dynamic> chain, String family) {
  final modelRefs = chain['modelPreviewRefs'];
  if (modelRefs is! Map) return const [];
  final refs = modelRefs[family];
  if (refs is! List) return const [];
  return refs.whereType<String>().toList(growable: false);
}

File? _resolveWorkspaceFile(Directory workspace, String relativeRef) {
  final normalized = relativeRef.replaceAll('/', Platform.pathSeparator);
  final root = workspace.absolute.path.endsWith(Platform.pathSeparator)
      ? workspace.absolute.path
      : '${workspace.absolute.path}${Platform.pathSeparator}';
  final file =
      File('${workspace.path}${Platform.pathSeparator}$normalized').absolute;
  final lowerFile = file.path.toLowerCase();
  if (!lowerFile.startsWith(root.toLowerCase())) return null;
  return file;
}

Future<Map<String, dynamic>?> _readOptionalJsonMap(File file) async {
  if (!await file.exists()) return null;
  final decoded = jsonDecode(await file.readAsString());
  if (decoded is! Map) {
    throw FormatException('Expected JSON object: ${file.path}');
  }
  return decoded.cast<String, dynamic>();
}

Future<List<Map<String, dynamic>>?> _readOptionalJsonList(File file) async {
  if (!await file.exists()) return null;
  final decoded = jsonDecode(await file.readAsString());
  if (decoded is! List) {
    throw FormatException('Expected JSON array: ${file.path}');
  }
  return [
    for (final raw in decoded)
      if (raw is Map) raw.cast<String, dynamic>(),
  ];
}

Future<void> _writeJson(File file, Object value) async {
  await file.writeAsString(const JsonEncoder.withIndent('  ').convert(value));
}

String _fileName(String path) {
  final normalized = path.replaceAll('\\', '/');
  final index = normalized.lastIndexOf('/');
  return index < 0 ? normalized : normalized.substring(index + 1);
}

String _timestamp() {
  final now = DateTime.now();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${now.year}${two(now.month)}${two(now.day)}'
      '${two(now.hour)}${two(now.minute)}${two(now.second)}';
}

class _Options {
  final String workspacePath;
  final String runDirectory;
  final Set<String> targetIds;
  final bool dryRun;
  final bool allowKeptException;

  const _Options({
    required this.workspacePath,
    required this.runDirectory,
    required this.targetIds,
    required this.dryRun,
    required this.allowKeptException,
  });

  factory _Options.parse(List<String> args) {
    var workspacePath = _defaultWorkspace;
    String? runDirectory;
    var targetIds = <String>{..._defaultTargetIds};
    var dryRun = false;
    var allowKeptException = false;
    for (final arg in args) {
      if (arg.startsWith('--workspace=')) {
        workspacePath = arg.substring('--workspace='.length);
      } else if (arg.startsWith('--run-directory=')) {
        runDirectory = arg.substring('--run-directory='.length);
      } else if (arg.startsWith('--target-ids=')) {
        targetIds = {
          for (final id in arg.substring('--target-ids='.length).split(','))
            if (id.trim().isNotEmpty) id.trim(),
        };
      } else if (arg == '--dry-run') {
        dryRun = true;
      } else if (arg == '--allow-kept-exception') {
        allowKeptException = true;
      }
    }
    final effectiveRunDirectory = runDirectory ??
        '$workspacePath${Platform.pathSeparator}assets${Platform.pathSeparator}references'
            '${Platform.pathSeparator}artist-chain-v5-previews${Platform.pathSeparator}'
            'r3c-strong-quality-conditional';
    return _Options(
      workspacePath: workspacePath,
      runDirectory: effectiveRunDirectory,
      targetIds: targetIds,
      dryRun: dryRun,
      allowKeptException: allowKeptException,
    );
  }
}
