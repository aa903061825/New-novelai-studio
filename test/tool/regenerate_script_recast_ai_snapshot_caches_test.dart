import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/data/studio/models/script_ai_role_extraction.dart';
import 'package:novel_studio/data/studio/models/script_recast.dart';
import 'package:novel_studio/data/studio/models/script_recast_knowledge.dart';
import 'package:novel_studio/data/studio/services/script_ai_role_extraction_service.dart';
import 'package:novel_studio/data/studio/tools/prompt_tag_classifier.dart';
import 'package:novel_studio/data/workspace/workspace_service.dart';

import '../../tool/regenerate_script_recast_ai_snapshot_caches.dart';

void main() {
  group('regenerateScriptRecastAiSnapshotCaches', () {
    late Directory workspaceRoot;

    setUp(() async {
      workspaceRoot = await Directory.systemTemp.createTemp(
        'script-recast-ai-snapshot-workspace-',
      );
    });

    tearDown(() async {
      if (await workspaceRoot.exists()) {
        await workspaceRoot.delete(recursive: true);
      }
    });

    test('writes ready AI extraction back to matching idle caches', () async {
      final service = WorkspaceService();
      await service.createWorkspace(workspaceRoot.path);
      final script = Script(
        id: 'script-one',
        name: 'script one',
        rootPath: 'source',
        frames: const [
          ScriptFrame(
            index: 1,
            fileName: 'p1.json',
            sourcePath: 'source/p1.json',
            rawJson: '{"Description":"artist:test, girl"}',
            parsed: ParsedFrame(baseCaption: 'artist:test, girl'),
            detectedSchema: ScriptSchema.baseInline,
            parseStatus: ScriptFrameParseStatus.parsed,
          ),
        ],
        detectedSchema: ScriptSchema.baseInline,
      );
      await service.saveRecastScriptCache(
        RecastScriptCache(
          scriptId: script.id,
          scriptName: script.name,
          sourceRootPath: script.rootPath,
          sourceFingerprint: 'fingerprint',
          updatedAt: DateTime.utc(2026, 6, 8),
          mapping: RecastMapping.defaults(script.id),
          scriptSnapshot: script.toJson(),
        ),
      );

      final report = await regenerateScriptRecastAiSnapshotCaches(
        workspaceRoot: workspaceRoot.path,
        settings: const ScriptAiBatchSettings(
          baseUrl: 'https://script.example/v1',
          token: 'token',
          model: 'gpt-test',
        ),
        nameContains: 'script one',
        roleExtractionService: const _ReadyRoleExtractionService(),
      );
      final updated = await service.loadRecastScriptCache(script.id);

      expect(report.updated, 1);
      expect(
          updated!.aiRoleExtraction.status, ScriptAiRoleExtractionStatus.ready);
      expect(updated.aiRoleExtraction.roles.single.displayName, '测试角色');
      expect(updated.mapping.rolePromptReplacements, hasLength(1));
      expect(
        updated.mapping.rolePromptReplacements.single.rules.single.sourceTerms
            .single.text,
        'test girl',
      );
      expect(updated.mapping.scenePromptReplacements, hasLength(1));
      expect(
        updated.mapping.scenePromptReplacements.single.rules.single.sourceTerms
            .single.text,
        'garden',
      );
    });
  });
}

class _ReadyRoleExtractionService implements ScriptAiRoleExtractionService {
  const _ReadyRoleExtractionService();

  @override
  Future<ScriptAiRoleExtractionServiceResult> extractRoles({
    required ScriptAiRoleExtractionServiceRequest request,
  }) async {
    return const ScriptAiRoleExtractionServiceResult(
      extraction: ScriptAiRoleExtraction(
        status: ScriptAiRoleExtractionStatus.ready,
        roles: [
          ScriptAiExtractedRole(
            sourceRoleId: 'global-0',
            sourceKind: 'global',
            displayName: '测试角色',
            frameIndexes: [1],
            appearances: [
              ScriptAiRoleAppearance(
                sourceId: 'base',
                sourceKind: 'base',
                frameIndexes: [1],
              ),
            ],
            stages: [
              ScriptAiExtractedStage(
                stageId: 'stage-1',
                label: '默认',
                frameIndexes: [1],
                identity: 'girl',
              ),
            ],
            promptTerms: [
              ScriptAiExtractedPromptTerm(
                id: 'identity-test-girl',
                text: 'test girl',
                category: PromptTagCategory.character,
                sourcePhrase: 'test girl',
                sourceLocation: 'base prompt',
                frameIndexes: [1],
              ),
            ],
          ),
        ],
        sceneTerms: [
          ScriptAiExtractedPromptTerm(
            id: 'scene-garden',
            text: 'garden',
            category: PromptTagCategory.scene,
            sourcePhrase: 'garden',
            sourceLocation: 'base prompt',
            frameIndexes: [1],
          ),
        ],
      ),
      requestPreview: {},
      aiRequestCount: 1,
    );
  }
}
