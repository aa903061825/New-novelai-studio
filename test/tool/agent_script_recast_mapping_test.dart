import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/data/studio/models/script_ai_role_extraction.dart';
import 'package:novel_studio/data/studio/models/script_recast.dart';
import 'package:novel_studio/data/studio/models/script_recast_knowledge.dart';
import 'package:novel_studio/data/studio/tools/prompt_tag_classifier.dart';

import '../../tool/agent_script_recast_mapping.dart' as runner;

void main() {
  test('applies visible mapping patch without mutating AI extraction',
      () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'agent-script-recast-mapping-test-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final cacheFile =
        File('${tempDir.path}${Platform.pathSeparator}cache.json');
    final backupDir = Directory(
      '${tempDir.path}${Platform.pathSeparator}backups',
    );
    final patchFile =
        File('${tempDir.path}${Platform.pathSeparator}patch.json');
    await _writeCache(cacheFile, _cache());
    await patchFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(_patchJson()),
      encoding: utf8,
    );
    final before = await _readCache(cacheFile);
    final beforeExtractionJson = jsonEncode(before.aiRoleExtraction.toJson());

    final exitCode = await runner.runAgentScriptRecastMapping([
      'apply',
      '--cache-file',
      cacheFile.path,
      '--patch',
      patchFile.path,
      '--backup-dir',
      backupDir.path,
    ]);

    expect(exitCode, 0);
    final after = await _readCache(cacheFile);
    expect(after.mapping.rolePromptReplacements, hasLength(2));
    expect(after.mapping.scenePromptReplacements, hasLength(1));
    expect(
      after.mapping.rolePromptReplacements
          .firstWhere((group) => group.sourceRoleId == 'slot-0')
          .rules
          .single
          .targetPrompt,
      'short hair, blue eyes',
    );
    expect(
      after.mapping.scenePromptReplacements.single.rules.single.targetPrompt,
      'sunny courtyard',
    );
    expect(jsonEncode(after.aiRoleExtraction.toJson()), beforeExtractionJson);

    final backups = await backupDir
        .list()
        .where((entry) => entry is File && entry.path.endsWith('.json'))
        .toList();
    expect(backups, hasLength(1));
    final backup = await _readCache(File(backups.single.path));
    expect(backup.mapping.rolePromptReplacements, hasLength(1));
    expect(backup.mapping.scenePromptReplacements, isEmpty);
  });

  test('dry-run leaves cache and backups unchanged', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'agent-script-recast-mapping-dry-run-test-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final cacheFile =
        File('${tempDir.path}${Platform.pathSeparator}cache.json');
    final backupDir = Directory(
      '${tempDir.path}${Platform.pathSeparator}backups',
    );
    final patchFile =
        File('${tempDir.path}${Platform.pathSeparator}patch.json');
    await _writeCache(cacheFile, _cache());
    await patchFile.writeAsString(jsonEncode(_patchJson()), encoding: utf8);
    final beforeText = await cacheFile.readAsString(encoding: utf8);

    final exitCode = await runner.runAgentScriptRecastMapping([
      'apply',
      '--cache-file',
      cacheFile.path,
      '--patch',
      patchFile.path,
      '--backup-dir',
      backupDir.path,
      '--dry-run',
    ]);

    expect(exitCode, 0);
    expect(await cacheFile.readAsString(encoding: utf8), beforeText);
    expect(await backupDir.exists(), isFalse);
  });

  test('script id mismatch fails without mutating cache', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'agent-script-recast-mapping-mismatch-test-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final cacheFile =
        File('${tempDir.path}${Platform.pathSeparator}cache.json');
    final patchFile =
        File('${tempDir.path}${Platform.pathSeparator}patch.json');
    await _writeCache(cacheFile, _cache());
    await patchFile.writeAsString(
      jsonEncode({..._patchJson(), 'scriptId': 'other-script'}),
      encoding: utf8,
    );
    final beforeText = await cacheFile.readAsString(encoding: utf8);

    final exitCode = await runner.runAgentScriptRecastMapping([
      'apply',
      '--cache-file',
      cacheFile.path,
      '--patch',
      patchFile.path,
    ]);

    expect(exitCode, 1);
    expect(await cacheFile.readAsString(encoding: utf8), beforeText);
  });
}

RecastScriptCache _cache() {
  return RecastScriptCache(
    scriptId: 'script-a',
    scriptName: 'Story A',
    sourceRootPath: 'E:/scripts/story-a',
    sourceFingerprint: 'fingerprint-a',
    updatedAt: DateTime.utc(2026, 6, 21),
    mapping: RecastMapping(
      id: 'mapping-script-a',
      scriptId: 'script-a',
      rolePromptReplacements: const [
        ScriptRolePromptReplacement(
          sourceRoleId: 'slot-1',
          displayLabel: 'Existing Role',
          rules: [
            ScriptPromptReplacementRule(
              id: 'existing-rule',
              sourceTerms: [
                ScriptPromptReplacementTerm(
                  id: 'existing-term',
                  text: 'red dress',
                  category: PromptTagCategory.clothing,
                ),
              ],
              targetPrompt: 'green dress',
            ),
          ],
        ),
      ],
    ),
    aiRoleExtraction: const ScriptAiRoleExtraction(
      status: ScriptAiRoleExtractionStatus.ready,
      roles: [
        ScriptAiExtractedRole(
          sourceRoleId: 'slot-0',
          displayName: 'Role Zero',
          promptTerms: [
            ScriptAiExtractedPromptTerm(
              id: 'source-long-hair',
              text: 'long hair',
              category: PromptTagCategory.character,
              frameIndexes: [1, 2],
            ),
          ],
        ),
      ],
    ),
  );
}

Map<String, dynamic> _patchJson() {
  return {
    'scriptId': 'script-a',
    'rolePromptReplacements': [
      {
        'sourceRoleId': 'slot-0',
        'displayLabel': 'Role Zero',
        'sourcePreview': 'long hair',
        'rules': [
          {
            'id': 'agent-rule-hair',
            'sourceTerms': [
              {
                'id': 'source-long-hair',
                'text': 'long hair',
                'category': 'body',
                'frameIndexes': [1, 2],
              },
            ],
            'targetPrompt': 'short hair, blue eyes',
          },
        ],
      },
    ],
    'scenePromptReplacements': [
      {
        'id': 'scene-agent',
        'label': 'Scene',
        'rules': [
          {
            'id': 'agent-rule-scene',
            'sourceTerms': [
              {
                'id': 'source-night',
                'text': 'night',
                'category': 'scene',
                'frameIndexes': [1],
              },
            ],
            'targetPrompt': 'sunny courtyard',
          },
        ],
      },
    ],
  };
}

Future<void> _writeCache(File file, RecastScriptCache cache) async {
  await file.writeAsString(
    const JsonEncoder.withIndent('  ').convert(cache.toJson()),
    encoding: utf8,
  );
}

Future<RecastScriptCache> _readCache(File file) async {
  return RecastScriptCache.fromJson(
    Map<String, dynamic>.from(
      jsonDecode(await file.readAsString(encoding: utf8)) as Map,
    ),
  );
}
