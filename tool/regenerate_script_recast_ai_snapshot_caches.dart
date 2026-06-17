import 'dart:convert';
import 'dart:io';

import 'package:hive/hive.dart';
import 'package:novel_studio/data/studio/models/script_ai_role_extraction.dart';
import 'package:novel_studio/data/studio/models/script_recast.dart';
import 'package:novel_studio/data/studio/models/script_recast_knowledge.dart';
import 'package:novel_studio/data/studio/services/script_ai_role_extraction_client.dart';
import 'package:novel_studio/data/studio/services/script_ai_role_extraction_service.dart';
import 'package:novel_studio/data/workspace/workspace_service.dart';

import 'script_recast_ai_cache_mapping_sync.dart';

Future<void> main(List<String> args) async {
  final options = _Options.parse(args);
  final hiveSettings = await _loadScriptAiSettingsFromHive(options.hiveDir);
  final settings = hiveSettings.withOverrides(
    baseUrl: options.baseUrl,
    token: options.token,
    model: options.model,
    proxy: options.proxy,
  );
  final report = await regenerateScriptRecastAiSnapshotCaches(
    workspaceRoot: options.workspaceRoot,
    settings: settings,
    dryRun: options.dryRun,
    allowBatch: options.allowBatch,
    includeReady: options.includeReady,
    limit: options.limit,
    scriptIds: options.scriptIds,
    nameContains: options.nameContains,
    roleExtractionService: DefaultScriptAiRoleExtractionService(
      client: OpenAiCompatibleScriptAiRoleExtractionClient(),
    ),
    log: stdout.writeln,
  );
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(report.toJson()));
  if (report.failed > 0 || report.errors > 0) {
    exitCode = 1;
  }
}

Future<ScriptAiBatchReport> regenerateScriptRecastAiSnapshotCaches({
  required String workspaceRoot,
  required ScriptAiBatchSettings settings,
  bool dryRun = false,
  bool allowBatch = false,
  bool includeReady = false,
  int? limit,
  Set<String> scriptIds = const {},
  String? nameContains,
  required ScriptAiRoleExtractionService roleExtractionService,
  void Function(String message)? log,
}) async {
  settings.validate();
  final workspace = WorkspaceService();
  await workspace.openWorkspace(workspaceRoot);
  final allCaches = await workspace.loadRecastScriptCaches();
  final planned = [
    for (final cache in allCaches)
      if (_matches(cache, scriptIds: scriptIds, nameContains: nameContains) &&
          (includeReady ||
              cache.aiRoleExtraction.status ==
                  ScriptAiRoleExtractionStatus.idle))
        cache,
  ]..sort((left, right) => left.scriptName.compareTo(right.scriptName));
  final targets =
      limit == null ? planned : planned.take(limit).toList(growable: false);
  if (!dryRun && !allowBatch && targets.length > 1) {
    throw StateError(
      'Refusing to regenerate ${targets.length} caches at once. '
      'Use --limit 1 or --allow-batch.',
    );
  }

  final rows = <ScriptAiBatchRow>[];
  for (final (index, cache) in targets.indexed) {
    final scriptJson = cache.scriptSnapshot;
    if (scriptJson.isEmpty) {
      rows.add(ScriptAiBatchRow.skipped(cache, 'missing_script_snapshot'));
      continue;
    }
    final script = Script.fromJson(scriptJson);
    if (script.frames.isEmpty) {
      rows.add(ScriptAiBatchRow.skipped(cache, 'empty_script_snapshot'));
      continue;
    }
    if (dryRun) {
      rows.add(ScriptAiBatchRow(
        status: 'would_update',
        scriptId: cache.scriptId,
        scriptName: cache.scriptName,
        frameCount: script.frames.length,
      ));
      continue;
    }

    log?.call(
      'START ${index + 1}/${targets.length}: '
      '${cache.scriptName} <${cache.scriptId}> frames=${script.frames.length}',
    );
    try {
      final result = await roleExtractionService.extractRoles(
        request: ScriptAiRoleExtractionServiceRequest(
          baseUrl: settings.baseUrl,
          token: settings.token,
          model: settings.model,
          proxy: settings.proxy,
          script: script,
          completedChunkExtractions: cache.aiRoleExtractionChunks,
          onRequestStarted: (preview) {
            final kind = preview['request_kind'] ?? 'unknown';
            final chunk = preview['chunk_id'] ?? '';
            log?.call('  request $kind${chunk == '' ? '' : ' $chunk'}');
          },
        ),
      );
      final extraction = result.extraction.collapseEquivalentStages();
      if (!extraction.isReady) {
        rows.add(ScriptAiBatchRow(
          status: 'failed',
          scriptId: cache.scriptId,
          scriptName: cache.scriptName,
          frameCount: script.frames.length,
          aiRequests: result.aiRequestCount,
          message: _attentionSummary(extraction),
        ));
        log?.call(
            'FAILED ${cache.scriptName}: ${_attentionSummary(extraction)}');
        continue;
      }
      final updated = RecastScriptCache(
        scriptId: cache.scriptId,
        scriptName: cache.scriptName,
        sourceRootPath: cache.sourceRootPath,
        sourceFingerprint: cache.sourceFingerprint,
        updatedAt: DateTime.now().toUtc(),
        roleCandidates: cache.roleCandidates,
        mapping: mappingWithAppliedAiRoleExtraction(
          mapping: cache.mapping,
          extraction: extraction,
        ),
        aiRoleExtraction: extraction,
        aiRoleExtractionChunks: const [],
        aiRoleExtractionDraftCollapsed: false,
        scriptBlockWords: cache.scriptBlockWords,
        scriptSnapshot: cache.scriptSnapshot,
      );
      await workspace.saveRecastScriptCache(updated);
      rows.add(ScriptAiBatchRow(
        status: 'updated',
        scriptId: cache.scriptId,
        scriptName: cache.scriptName,
        frameCount: script.frames.length,
        roleCount: extraction.roles.length,
        aiRequests: result.aiRequestCount,
      ));
      log?.call(
        'DONE ${cache.scriptName}: roles=${extraction.roles.length} '
        'requests=${result.aiRequestCount}',
      );
    } catch (error) {
      rows.add(ScriptAiBatchRow(
        status: 'error',
        scriptId: cache.scriptId,
        scriptName: cache.scriptName,
        frameCount: script.frames.length,
        message: error.toString(),
      ));
      log?.call('ERROR ${cache.scriptName}: $error');
    }
  }

  return ScriptAiBatchReport(
    workspaceRoot: workspaceRoot,
    model: settings.model,
    dryRun: dryRun,
    targetCount: targets.length,
    rows: List.unmodifiable(rows),
  );
}

class ScriptAiBatchSettings {
  final String baseUrl;
  final String token;
  final String model;
  final String proxy;

  const ScriptAiBatchSettings({
    required this.baseUrl,
    required this.token,
    required this.model,
    this.proxy = '',
  });

  ScriptAiBatchSettings withOverrides({
    String? baseUrl,
    String? token,
    String? model,
    String? proxy,
  }) {
    return ScriptAiBatchSettings(
      baseUrl:
          baseUrl?.trim().isNotEmpty == true ? baseUrl!.trim() : this.baseUrl,
      token: token?.trim().isNotEmpty == true ? token!.trim() : this.token,
      model: model?.trim().isNotEmpty == true ? model!.trim() : this.model,
      proxy: proxy?.trim().isNotEmpty == true ? proxy!.trim() : this.proxy,
    );
  }

  void validate() {
    if (baseUrl.trim().isEmpty ||
        token.trim().isEmpty ||
        model.trim().isEmpty) {
      throw StateError('Missing Script AI base URL, token, or model.');
    }
  }
}

class ScriptAiBatchReport {
  final String workspaceRoot;
  final String model;
  final bool dryRun;
  final int targetCount;
  final List<ScriptAiBatchRow> rows;

  const ScriptAiBatchReport({
    required this.workspaceRoot,
    required this.model,
    required this.dryRun,
    required this.targetCount,
    required this.rows,
  });

  int get updated => rows.where((row) => row.status == 'updated').length;

  int get wouldUpdate =>
      rows.where((row) => row.status == 'would_update').length;

  int get skipped => rows.where((row) => row.status == 'skipped').length;

  int get failed => rows.where((row) => row.status == 'failed').length;

  int get errors => rows.where((row) => row.status == 'error').length;

  Map<String, dynamic> toJson() => {
        'workspace_root': workspaceRoot,
        'model': model,
        'dry_run': dryRun,
        'target_count': targetCount,
        'updated': updated,
        'would_update': wouldUpdate,
        'skipped': skipped,
        'failed': failed,
        'errors': errors,
        'rows': [for (final row in rows) row.toJson()],
      };
}

class ScriptAiBatchRow {
  final String status;
  final String scriptId;
  final String scriptName;
  final int frameCount;
  final int roleCount;
  final int aiRequests;
  final String message;

  const ScriptAiBatchRow({
    required this.status,
    required this.scriptId,
    required this.scriptName,
    required this.frameCount,
    this.roleCount = 0,
    this.aiRequests = 0,
    this.message = '',
  });

  factory ScriptAiBatchRow.skipped(
    RecastScriptCache cache,
    String message,
  ) {
    return ScriptAiBatchRow(
      status: 'skipped',
      scriptId: cache.scriptId,
      scriptName: cache.scriptName,
      frameCount: 0,
      message: message,
    );
  }

  Map<String, dynamic> toJson() => {
        'status': status,
        'script_id': scriptId,
        'script_name': scriptName,
        'frame_count': frameCount,
        if (roleCount > 0) 'role_count': roleCount,
        if (aiRequests > 0) 'ai_requests': aiRequests,
        if (message.isNotEmpty) 'message': message,
      };
}

class _Options {
  final String workspaceRoot;
  final String hiveDir;
  final bool dryRun;
  final bool allowBatch;
  final bool includeReady;
  final int? limit;
  final Set<String> scriptIds;
  final String? nameContains;
  final String? baseUrl;
  final String? token;
  final String? model;
  final String? proxy;

  const _Options({
    required this.workspaceRoot,
    required this.hiveDir,
    required this.dryRun,
    required this.allowBatch,
    required this.includeReady,
    required this.limit,
    required this.scriptIds,
    required this.nameContains,
    required this.baseUrl,
    required this.token,
    required this.model,
    required this.proxy,
  });

  factory _Options.parse(List<String> args) {
    final values = <String, String>{};
    final flags = <String>{};
    for (var index = 0; index < args.length; index += 1) {
      final arg = args[index];
      if (!arg.startsWith('--')) continue;
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
    return _Options(
      workspaceRoot: values['workspace'] ?? _defaultWorkspaceRoot(),
      hiveDir: values['hive-dir'] ?? _defaultHiveDir(),
      dryRun: flags.contains('dry-run'),
      allowBatch: flags.contains('allow-batch'),
      includeReady: flags.contains('all'),
      limit: int.tryParse(values['limit'] ?? ''),
      scriptIds: {
        for (final id in (values['script-id'] ?? '').split(','))
          if (id.trim().isNotEmpty) id.trim(),
      },
      nameContains: values['name-contains'],
      baseUrl: values['base-url'],
      token: values['token'],
      model: values['model'],
      proxy: values['proxy'],
    );
  }
}

bool _matches(
  RecastScriptCache cache, {
  required Set<String> scriptIds,
  required String? nameContains,
}) {
  if (scriptIds.isNotEmpty && !scriptIds.contains(cache.scriptId)) {
    return false;
  }
  if (nameContains != null &&
      !cache.scriptName.toLowerCase().contains(nameContains.toLowerCase())) {
    return false;
  }
  return true;
}

Future<ScriptAiBatchSettings> _loadScriptAiSettingsFromHive(
  String hiveDir,
) async {
  Hive.init(hiveDir);
  final box = await Hive.openBox('savedBox');
  try {
    final jsonText = _currentSavedConfigJson(box);
    if (jsonText == null) {
      return const ScriptAiBatchSettings(baseUrl: '', token: '', model: '');
    }
    final decoded = jsonDecode(jsonText);
    if (decoded is! Map) {
      return const ScriptAiBatchSettings(baseUrl: '', token: '', model: '');
    }
    final settings = decoded['settings'];
    if (settings is! Map) {
      return const ScriptAiBatchSettings(baseUrl: '', token: '', model: '');
    }
    return ScriptAiBatchSettings(
      baseUrl: _string(settings['script_ai_base_url']),
      token: _string(settings['script_ai_token']),
      model: _string(settings['script_ai_model']),
      proxy: _string(settings['proxy']),
    );
  } finally {
    await box.close();
  }
}

String? _currentSavedConfigJson(Box<dynamic> box) {
  final savedUuid = box.get('savedUuid');
  if (savedUuid is String && savedUuid.trim().isNotEmpty) {
    final saved = box.get('savedConfig-${savedUuid.trim()}');
    if (saved is String && saved.trim().isNotEmpty) {
      return saved;
    }
  }
  final legacySaved = box.get('savedConfig');
  if (legacySaved is String && legacySaved.trim().isNotEmpty) {
    return legacySaved;
  }
  for (final key in box.keys) {
    final keyString = key.toString();
    if (!keyString.startsWith('savedConfig-')) continue;
    final saved = box.get(key);
    if (saved is String && saved.trim().isNotEmpty) {
      return saved;
    }
  }
  return null;
}

String _attentionSummary(ScriptAiRoleExtraction extraction) {
  final messages = [
    for (final item in extraction.attentionItems)
      if (item.message.trim().isNotEmpty) item.message.trim(),
  ];
  if (messages.isNotEmpty) {
    return messages.take(3).join(' | ');
  }
  return extraction.rawResponse.trim().isEmpty
      ? 'no failure reason recorded'
      : extraction.rawResponse.trim();
}

String _defaultWorkspaceRoot() {
  final appData = Platform.environment['APPDATA'];
  if (appData == null || appData.trim().isEmpty) {
    throw StateError('APPDATA is not set; pass --workspace explicitly.');
  }
  return [
    appData,
    'Novel Studio',
    'Novel Studio',
    'novel_studio',
  ].join(Platform.pathSeparator);
}

String _defaultHiveDir() {
  final userProfile = Platform.environment['USERPROFILE'];
  if (userProfile == null || userProfile.trim().isEmpty) {
    throw StateError('USERPROFILE is not set; pass --hive-dir explicitly.');
  }
  return [userProfile, 'Documents'].join(Platform.pathSeparator);
}

String _string(Object? value) => value is String ? value.trim() : '';
