import 'dart:convert';
import 'dart:io';

import 'package:hive/hive.dart';
import 'package:novel_studio/data/models/payload_config.dart';
import 'package:novel_studio/data/studio/models/script_ai_role_extraction.dart';
import 'package:novel_studio/data/studio/models/script_recast.dart';
import 'package:novel_studio/data/studio/models/script_recast_knowledge.dart';
import 'package:novel_studio/data/studio/services/script_ai_role_extraction_client.dart';
import 'package:novel_studio/data/studio/services/script_ai_role_extraction_service.dart';
import 'package:novel_studio/data/studio/services/script_recast_parser_service.dart';
import 'package:novel_studio/data/studio/tools/stable_id.dart';
import 'package:novel_studio/data/workspace/workspace_service.dart';

import 'script_recast_ai_cache_mapping_sync.dart';

Future<void> main(List<String> args) => runRegenerateScriptRecastAiCache(args);

Future<void> runRegenerateScriptRecastAiCache(List<String> args) async {
  final options = _Options.parse(args);
  final workspaceRoot = Directory(options.workspaceRoot);
  final hiveDir = Directory(options.hiveDir);
  final outputDir =
      options.outputDir == null ? null : Directory(options.outputDir!);

  final config = await _loadPayloadConfig(hiveDir);
  final settings = config.settings;
  final baseUrl = options.baseUrl ?? settings.scriptAiBaseUrl.trim();
  final token = options.token ?? settings.scriptAiToken.trim();
  final model = options.model ?? settings.scriptAiModel.trim();
  final proxy = options.proxy ?? settings.proxy.trim();
  if (baseUrl.isEmpty || token.isEmpty || model.isEmpty) {
    throw StateError(
      'Missing script AI settings. Need base URL, token, and model.',
    );
  }

  final workspace = WorkspaceService();
  await workspace.openWorkspace(workspaceRoot.path);
  var caches = await workspace.loadRecastScriptCaches();
  final parser = const ScriptRecastParserService();

  final planned = <_CachePlan>[];
  for (final cache in caches) {
    if (!_matchesFilter(cache, options)) {
      continue;
    }
    final rootPath = cache.sourceRootPath.trim();
    if (rootPath.isEmpty) {
      continue;
    }
    final sourceDir = Directory(rootPath);
    if (!await sourceDir.exists()) {
      stderr.writeln('SKIP missing source: ${cache.scriptName} <$rootPath>');
      continue;
    }
    final script = await parser.parseDirectory(sourceDir);
    final uncovered = _uncoveredSlotlessBaseFrames(
      script,
      cache.aiRoleExtraction,
    );
    if (options.onlyUncovered && uncovered.isEmpty) {
      continue;
    }
    planned.add(_CachePlan(cache: cache, script: script, uncovered: uncovered));
  }

  planned.sort((left, right) {
    if (left.cache.scriptId == options.firstScriptId) return -1;
    if (right.cache.scriptId == options.firstScriptId) return 1;
    final uncoveredCompare = right.uncovered.length.compareTo(
      left.uncovered.length,
    );
    if (uncoveredCompare != 0) return uncoveredCompare;
    return left.cache.scriptName.compareTo(right.cache.scriptName);
  });
  final limited = options.limit == null
      ? planned
      : planned.take(options.limit!).toList(growable: false);
  if (!options.dryRun && !options.allowBatch && limited.length > 1) {
    throw StateError(
      'Refusing to regenerate ${limited.length} script caches at once. '
      'Process scripts sequentially with --script-id or --limit 1. '
      'Use --allow-batch only for an explicitly approved batch run.',
    );
  }

  stdout.writeln(
    'Workspace: ${workspaceRoot.path}\n'
    'Hive: ${hiveDir.path}\n'
    'Model: $model\n'
    'Output: ${outputDir?.path ?? "actual cache"}\n'
    'Targets: ${limited.length}/${planned.length}',
  );
  for (final (index, plan) in limited.indexed) {
    stdout.writeln(
      'PLAN ${index + 1}/${limited.length}: ${plan.cache.scriptName} '
      '<${plan.cache.scriptId}> frames=${plan.script.frames.length} '
      'uncovered=${plan.uncovered.length} '
      'sample=${plan.uncovered.take(12).join(",")}',
    );
  }
  if (options.dryRun) {
    return;
  }

  final service = DefaultScriptAiRoleExtractionService(
    client: OpenAiCompatibleScriptAiRoleExtractionClient(),
  );

  for (final (index, plan) in limited.indexed) {
    stdout.writeln(
      'START ${index + 1}/${limited.length}: ${plan.cache.scriptName} '
      '<${plan.cache.scriptId}>',
    );
    final started = DateTime.now();
    final result = await service.extractRoles(
      request: ScriptAiRoleExtractionServiceRequest(
        baseUrl: baseUrl,
        token: token,
        model: model,
        proxy: proxy,
        script: plan.script,
        onRequestStarted: (preview) {
          final kind = preview['request_kind'] ?? 'unknown';
          final chunk = preview['chunk_id'] ?? '';
          stdout.writeln('  request $kind${chunk == '' ? '' : ' $chunk'}');
        },
      ),
    );

    final extraction = result.extraction.collapseEquivalentStages();
    if (extraction.isFailed) {
      stderr.writeln(
        'FAILED ${plan.cache.scriptName}: '
        '${extraction.attentionItems.map((item) => item.message).join(" | ")}',
      );
      continue;
    }

    final updatedCache = RecastScriptCache(
      scriptId: plan.script.id,
      scriptName: plan.script.name,
      sourceRootPath: plan.script.rootPath,
      sourceFingerprint: _sourceFingerprint(plan.script),
      updatedAt: DateTime.now().toUtc(),
      mapping: mappingWithAppliedAiRoleExtraction(
        mapping: plan.cache.mapping,
        extraction: extraction,
      ),
      aiRoleExtraction: extraction,
      aiRoleExtractionChunks: const [],
      aiRoleExtractionDraftCollapsed: false,
      scriptBlockWords: plan.cache.scriptBlockWords,
      scriptSnapshot: plan.script.toJson(),
    );

    if (outputDir == null) {
      caches = [
        for (final cache in caches)
          if (!_cacheBelongsToScript(cache, plan.script)) cache,
        updatedCache,
      ];
      await workspace.saveRecastScriptCaches(caches);
    } else {
      await outputDir.create(recursive: true);
      final outputFile = File(
        [
          outputDir.path,
          '${safeWorkspaceEntityId(prefix: 'script', id: plan.script.id)}.json',
        ].join(Platform.pathSeparator),
      );
      await outputFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(updatedCache.toJson()),
        encoding: utf8,
      );
    }

    final afterUncovered =
        _uncoveredSlotlessBaseFrames(plan.script, extraction);
    final elapsed = DateTime.now().difference(started);
    stdout.writeln(
      'DONE ${plan.cache.scriptName}: status=${extraction.status.name} '
      'roles=${extraction.roles.length} requests=${result.aiRequestCount} '
      'uncovered_after=${afterUncovered.length} '
      'elapsed=${elapsed.inSeconds}s',
    );
  }
}

Future<PayloadConfig> _loadPayloadConfig(Directory hiveDir) async {
  Hive.init(hiveDir.path);
  final box = await Hive.openBox('savedBox');
  try {
    final savedUuid = box.get('savedUuid') as String?;
    final jsonText = savedUuid == null
        ? box.get('savedConfig') as String?
        : box.get('savedConfig-$savedUuid') as String?;
    if (jsonText == null || jsonText.trim().isEmpty) {
      throw StateError('No saved PayloadConfig found in Hive savedBox.');
    }
    return PayloadConfig.fromJson(
      jsonDecode(jsonText) as Map<String, dynamic>,
    );
  } finally {
    await box.close();
  }
}

bool _matchesFilter(RecastScriptCache cache, _Options options) {
  if (options.scriptIds.isNotEmpty &&
      !options.scriptIds.contains(cache.scriptId)) {
    return false;
  }
  if (options.nameContains != null &&
      !cache.scriptName
          .toLowerCase()
          .contains(options.nameContains!.toLowerCase())) {
    return false;
  }
  return true;
}

List<int> _uncoveredSlotlessBaseFrames(
  Script script,
  ScriptAiRoleExtraction extraction,
) {
  final slotless = <int>{};
  for (final frame in script.frames) {
    if (frame.parseStatus != ScriptFrameParseStatus.parsed) {
      continue;
    }
    if (frame.parsed.baseCaption.trim().isEmpty) {
      continue;
    }
    final hasSlot = frame.parsed.charCaptions.any(
      (caption) => caption.trim().isNotEmpty,
    );
    if (!hasSlot) {
      slotless.add(frame.index);
    }
  }
  if (slotless.isEmpty) {
    return const [];
  }

  final covered = <int>{};
  for (final role in extraction.roles) {
    for (final appearance in role.appearances) {
      final sourceId = appearance.sourceId.trim().toLowerCase();
      final sourceKind = appearance.sourceKind.trim().toLowerCase();
      if (!_isBaseSource(sourceId) && !_isBaseSource(sourceKind)) {
        continue;
      }
      covered.addAll(appearance.frameIndexes);
    }
  }

  final uncovered = slotless.difference(covered).toList()..sort();
  return List.unmodifiable(uncovered);
}

bool _isBaseSource(String value) {
  return value == 'base' ||
      value == 'global' ||
      value.startsWith('base-') ||
      value.startsWith('global-');
}

bool _cacheBelongsToScript(RecastScriptCache cache, Script script) {
  return cache.scriptId == script.id ||
      _normalizeScriptPath(cache.sourceRootPath) ==
          _normalizeScriptPath(script.rootPath);
}

String _sourceFingerprint(Script script) {
  final parts = [
    script.id,
    script.rootPath,
    for (final frame in script.frames)
      '${frame.index}:${frame.fileName}:${frame.sourcePath}:'
          '${_stableContentHash(frame.rawJson)}',
  ];
  return parts.join('|');
}

String _stableContentHash(String value) {
  var hash = 0x811c9dc5;
  for (final unit in value.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

String _normalizeScriptPath(String path) {
  final normalized = path.trim().replaceAll('\\', '/');
  return Platform.isWindows ? normalized.toLowerCase() : normalized;
}

class _CachePlan {
  final RecastScriptCache cache;
  final Script script;
  final List<int> uncovered;

  const _CachePlan({
    required this.cache,
    required this.script,
    required this.uncovered,
  });
}

class _Options {
  final String workspaceRoot;
  final String hiveDir;
  final bool dryRun;
  final bool onlyUncovered;
  final int? limit;
  final Set<String> scriptIds;
  final String? nameContains;
  final String? firstScriptId;
  final String? baseUrl;
  final String? token;
  final String? model;
  final String? proxy;
  final String? outputDir;
  final bool allowBatch;

  const _Options({
    required this.workspaceRoot,
    required this.hiveDir,
    required this.dryRun,
    required this.onlyUncovered,
    required this.limit,
    required this.scriptIds,
    required this.nameContains,
    required this.firstScriptId,
    required this.baseUrl,
    required this.token,
    required this.model,
    required this.proxy,
    required this.outputDir,
    required this.allowBatch,
  });

  factory _Options.parse(List<String> args) {
    final values = <String, String>{};
    final flags = <String>{};
    for (var index = 0; index < args.length; index += 1) {
      final arg = args[index];
      if (!arg.startsWith('--')) {
        continue;
      }
      final equalIndex = arg.indexOf('=');
      if (equalIndex > 0) {
        values[arg.substring(2, equalIndex)] = arg.substring(equalIndex + 1);
        continue;
      }
      final key = arg.substring(2);
      if (index + 1 < args.length && !args[index + 1].startsWith('--')) {
        values[key] = args[index + 1];
        index += 1;
      } else {
        flags.add(key);
      }
    }
    final appData = Platform.environment['APPDATA'] ?? '';
    final userProfile = Platform.environment['USERPROFILE'] ?? '';
    final workspaceRoot = values['workspace'] ??
        [
          appData,
          'Novel Studio',
          'Novel Studio',
          'novel_studio',
        ].join(Platform.pathSeparator);
    final hiveDir = values['hive-dir'] ??
        [userProfile, 'Documents'].join(Platform.pathSeparator);
    return _Options(
      workspaceRoot: workspaceRoot,
      hiveDir: hiveDir,
      dryRun: flags.contains('dry-run'),
      onlyUncovered: !flags.contains('all'),
      limit: int.tryParse(values['limit'] ?? ''),
      scriptIds: {
        for (final id in (values['script-id'] ?? '').split(','))
          if (id.trim().isNotEmpty) id.trim(),
      },
      nameContains: values['name-contains'],
      firstScriptId: values['first-script-id'],
      baseUrl: values['base-url'],
      token: values['token'],
      model: values['model'],
      proxy: values['proxy'],
      outputDir: values['output-dir'],
      allowBatch: flags.contains('allow-batch'),
    );
  }
}
