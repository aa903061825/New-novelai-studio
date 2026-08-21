import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/data/studio/models/script_ai_role_extraction.dart';
import 'package:novel_studio/data/studio/models/script_recast.dart';
import 'package:novel_studio/data/studio/models/script_recast_knowledge.dart';
import 'package:novel_studio/data/studio/services/script_recast_cache_restore_service.dart';
import 'package:novel_studio/data/studio/tools/prompt_tag_classifier.dart';

void main() {
  group('ScriptRecastCacheRestoreService', () {
    const service = ScriptRecastCacheRestoreService();

    test('content fingerprint survives source path moves', () {
      final oldPathScript = _script(
        rootPath: 'E:/old/story',
        sourcePath: 'E:/old/story/nai_1.json',
      );
      final movedScript = _script(
        rootPath: 'E:/new/story',
        sourcePath: 'E:/new/story/nai_1.json',
      );

      expect(
        service.sourceContentFingerprint(oldPathScript),
        service.sourceContentFingerprint(movedScript),
      );
      expect(
        service.sourceFingerprint(oldPathScript),
        isNot(service.sourceFingerprint(movedScript)),
      );
    });

    test('chooses AI-ready cache before newer idle cache', () {
      final script = _script();
      final newerIdle = _cache(
        script,
        updatedAt: DateTime.utc(2026, 6, 2),
      );
      final olderReady = _cache(
        script,
        updatedAt: DateTime.utc(2026, 6, 1),
        aiRoleExtraction: const ScriptAiRoleExtraction(
          status: ScriptAiRoleExtractionStatus.ready,
          roles: [ScriptAiExtractedRole(displayName: 'alice')],
        ),
      );

      expect(
        service.bestExactCache([newerIdle, olderReady]),
        same(olderReady),
      );
    });

    test('chooses cache with user mappings before newer empty mapping cache',
        () {
      final script = _script();
      final newerEmptyMapping = _cache(
        script,
        updatedAt: DateTime.utc(2026, 6, 2),
        aiRoleExtraction: const ScriptAiRoleExtraction(
          status: ScriptAiRoleExtractionStatus.ready,
          roles: [ScriptAiExtractedRole(displayName: 'cached alice')],
        ),
      );
      final olderMapped = _cache(
        script,
        updatedAt: DateTime.utc(2026, 6, 1),
        mapping: RecastMapping(
          id: 'mapping-${script.id}',
          scriptId: script.id,
          rolePromptReplacements: const [
            ScriptRolePromptReplacement(
              sourceRoleId: 'slot-0',
              displayLabel: 'Heroine',
              targetCharacterId: 'target-character',
              rules: [
                ScriptPromptReplacementRule(
                  id: 'rule-blue-eyes',
                  sourceTerms: [
                    ScriptPromptReplacementTerm(
                      id: 'blue-eyes',
                      text: 'blue eyes',
                      category: PromptTagCategory.upperBody,
                    ),
                  ],
                  targetPrompt: 'green eyes',
                ),
              ],
            ),
          ],
        ),
      );

      expect(
        service.bestExactCache([newerEmptyMapping, olderMapped]),
        same(olderMapped),
      );
    });

    test('uses updatedAt when candidate AI draft scores tie', () {
      final script = _script();
      final oldCache = _cache(script, updatedAt: DateTime.utc(2026, 6, 1));
      final newCache = _cache(script, updatedAt: DateTime.utc(2026, 6, 3));

      expect(service.bestExactCache([oldCache, newCache]), same(newCache));
    });

    test('matches content fingerprint from legacy snapshot when field missing',
        () {
      final script = _script();
      final cache = _cache(
        script,
        sourceContentFingerprint: '',
        scriptSnapshot: script.toJson(),
      );

      expect(
        service.cacheHasSourceContentFingerprint(
          cache,
          service.sourceContentFingerprint(script),
        ),
        isTrue,
      );
    });

    test('preserves existing AI draft when saving an idle draft', () {
      final script = _script();
      final draft = _cache(script);
      final existing = _cache(
        script,
        aiRoleExtraction: const ScriptAiRoleExtraction(
          status: ScriptAiRoleExtractionStatus.ready,
          roles: [ScriptAiExtractedRole(displayName: 'cached alice')],
        ),
        aiRoleExtractionDraftCollapsed: true,
        aiRoleExtractionFinalized: true,
      );

      final preserved = service.cachePreservingExistingAiDraft(draft, existing);

      expect(
        preserved.aiRoleExtraction.roles.single.displayName,
        'cached alice',
      );
      expect(preserved.aiRoleExtractionDraftCollapsed, isTrue);
      expect(preserved.aiRoleExtractionFinalized, isTrue);
    });

    test('rejects cache snapshots without frames', () {
      final script = _script();

      expect(service.cacheSnapshotHasFrames({}), isFalse);
      expect(
        service.cacheSnapshotHasFrames(script.toJson()),
        isTrue,
      );
    });
  });
}

Script _script({
  String id = 'script-a',
  String name = 'Story',
  String rootPath = 'E:/source/story',
  String sourcePath = 'E:/source/story/nai_1.json',
  String rawJson = '{"Description":"blue eyes"}',
}) {
  return Script(
    id: id,
    name: name,
    rootPath: rootPath,
    frames: [
      ScriptFrame(
        index: 1,
        fileName: 'nai_1.json',
        sourcePath: sourcePath,
        rawJson: rawJson,
        parsed: const ParsedFrame(baseCaption: 'blue eyes'),
        detectedSchema: ScriptSchema.baseInline,
        parseStatus: ScriptFrameParseStatus.parsed,
      ),
    ],
    detectedSchema: ScriptSchema.baseInline,
  );
}

RecastScriptCache _cache(
  Script script, {
  DateTime? updatedAt,
  String? sourceContentFingerprint,
  RecastMapping? mapping,
  ScriptAiRoleExtraction aiRoleExtraction = const ScriptAiRoleExtraction(),
  bool aiRoleExtractionDraftCollapsed = false,
  bool aiRoleExtractionFinalized = false,
  Map<String, dynamic>? scriptSnapshot,
}) {
  const service = ScriptRecastCacheRestoreService();
  return RecastScriptCache(
    scriptId: script.id,
    scriptName: script.name,
    sourceRootPath: script.rootPath,
    sourceFingerprint: service.sourceFingerprint(script),
    sourceContentFingerprint:
        sourceContentFingerprint ?? service.sourceContentFingerprint(script),
    updatedAt: updatedAt ?? DateTime.utc(2026, 6, 1),
    mapping: mapping ?? RecastMapping.defaults(script.id),
    aiRoleExtraction: aiRoleExtraction,
    aiRoleExtractionDraftCollapsed: aiRoleExtractionDraftCollapsed,
    aiRoleExtractionFinalized: aiRoleExtractionFinalized,
    scriptSnapshot: scriptSnapshot ?? script.toJson(),
  );
}
