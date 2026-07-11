import 'dart:convert';
import 'dart:io';

import 'package:novel_studio/data/studio/models/production_task.dart';
import 'package:novel_studio/data/studio/models/script_recast.dart';
import 'package:novel_studio/data/studio/services/script_recast_engine.dart';
import 'package:novel_studio/data/studio/services/script_recast_payload_adapter.dart';

Future<void> main(List<String> args) async {
  final parsed = _Args.parse(args);
  final cacheFile = File(parsed.cachePath);
  final planFile = File(parsed.planPath);
  if (!cacheFile.existsSync()) {
    stderr.writeln('cache file does not exist: ${cacheFile.path}');
    exitCode = 2;
    return;
  }
  if (!planFile.existsSync()) {
    stderr.writeln('plan file does not exist: ${planFile.path}');
    exitCode = 2;
    return;
  }

  final cacheJson =
      jsonDecode(await cacheFile.readAsString()) as Map<String, dynamic>;
  final script = Script.fromJson(
    (cacheJson['scriptSnapshot'] as Map).cast<String, dynamic>(),
  );
  final mapping = RecastMapping.fromJson(
    (cacheJson['mapping'] as Map).cast<String, dynamic>(),
  );
  final result = await const ScriptRecastEngine().resolvePayloadsAsync(
    script: script,
    mapping: mapping,
    characters: const [],
    artistChains: const [],
  );
  final framePayloads = {
    for (final frame in result.frames) frame.frameIndex: frame,
  };

  final planJson =
      jsonDecode(await planFile.readAsString()) as Map<String, dynamic>;
  final plan = ProductionPlan.fromJson(planJson);
  final adapter = const ScriptRecastPayloadAdapter();
  final refreshedTasks = <ProductionTask>[];
  var scanned = 0;
  var eligible = 0;
  var changed = 0;
  final changedFrames = <int>[];

  for (final task in plan.tasks) {
    final frameIndex = task.source.frameIndex;
    final frame = frameIndex == null ? null : framePayloads[frameIndex];
    if (task.taskType != ProductionTaskType.scriptRecastFrame ||
        task.source.scriptId != script.id ||
        frame == null) {
      refreshedTasks.add(task);
      continue;
    }
    scanned += 1;
    if (task.status != ProductionTaskStatus.queued) {
      refreshedTasks.add(task);
      continue;
    }
    eligible += 1;
    final payload = adapter.toNaiRequestPayload(frame.payload);
    final nextSource = ProductionTaskSource(
      scriptId: task.source.scriptId,
      scriptName: task.source.scriptName,
      scriptPath: task.source.scriptPath,
      recastRunId: task.source.recastRunId,
      mappingConfigFingerprint: result.configFingerprint,
      frameIndex: task.source.frameIndex,
      sourceFileName: task.source.sourceFileName,
    );
    final payloadChanged = jsonEncode(_canonicalValue(payload)) !=
            jsonEncode(_canonicalValue(task.payload)) ||
        task.payloadFingerprint != frame.payloadFingerprint ||
        task.source.mappingConfigFingerprint != result.configFingerprint;
    if (!payloadChanged) {
      refreshedTasks.add(task);
      continue;
    }
    changed += 1;
    changedFrames.add(frame.frameIndex);
    refreshedTasks.add(
      task.copyWith(
        source: nextSource,
        payload: payload,
        payloadFingerprint: frame.payloadFingerprint,
        updatedAt: DateTime.now().toUtc(),
      ),
    );
  }

  if (changed > 0) {
    final backupDir = Directory(parsed.backupDir);
    backupDir.createSync(recursive: true);
    final backupFile = File('${backupDir.path}${Platform.pathSeparator}'
        '${planFile.uri.pathSegments.last}');
    if (!backupFile.existsSync()) {
      planFile.copySync(backupFile.path);
    }
    final refreshedPlan = plan.copyWith(
      tasks: refreshedTasks,
      updatedAt: DateTime.now().toUtc(),
    );
    await planFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(refreshedPlan.toJson()),
    );
  }

  stdout.writeln(jsonEncode({
    'plan': plan.id,
    'scriptId': script.id,
    'scannedScriptTasks': scanned,
    'eligibleQueuedTasks': eligible,
    'changedTasks': changed,
    'changedFramesPreview': changedFrames.take(20).toList(growable: false),
    'changedFramesCount': changedFrames.length,
    'configFingerprint': result.configFingerprint,
  }));
}

class _Args {
  final String cachePath;
  final String planPath;
  final String backupDir;

  const _Args({
    required this.cachePath,
    required this.planPath,
    required this.backupDir,
  });

  factory _Args.parse(List<String> args) {
    String? valueFor(String name) {
      final index = args.indexOf(name);
      if (index < 0 || index + 1 >= args.length) return null;
      return args[index + 1];
    }

    final cache = valueFor('--cache');
    final plan = valueFor('--plan');
    final backup = valueFor('--backup-dir');
    if (cache == null || plan == null || backup == null) {
      stderr.writeln(
        'Usage: dart run tool/repair_script_recast_production_plan_payloads_20260627.dart '
        '--cache <cache.json> --plan <plan.json> --backup-dir <dir>',
      );
      exit(64);
    }
    return _Args(cachePath: cache, planPath: plan, backupDir: backup);
  }
}

Object? _canonicalValue(Object? value) {
  if (value is Map) {
    final entries = value.entries.toList()
      ..sort(
        (left, right) => left.key.toString().compareTo(right.key.toString()),
      );
    return {
      for (final entry in entries)
        entry.key.toString(): _canonicalValue(entry.value),
    };
  }
  if (value is Iterable) {
    return value.map(_canonicalValue).toList(growable: false);
  }
  return value;
}
