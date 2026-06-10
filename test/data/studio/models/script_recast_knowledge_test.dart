import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/studio/models/script_ai_role_extraction.dart';
import 'package:nai_casrand/data/studio/models/script_recast.dart';
import 'package:nai_casrand/data/studio/models/script_recast_knowledge.dart';

void main() {
  group('RecastRoleCandidate', () {
    test('confirms, rejects, and renames without mutating the suggestion', () {
      const candidate = RecastRoleCandidate(
        id: 'role-alice',
        displayName: 'alice',
        importance: RecastRoleImportance.protagonist,
        aliases: ['alice_old'],
        evidenceTags: ['alice', 'hero'],
        frameIndexes: [1, 3],
        confidence: 0.8,
      );

      final confirmed = candidate.confirm(mappedCharacterId: 'char-alice');
      final rejected = candidate.reject();
      final renamed = candidate.rename('Alice');

      expect(candidate.status, RecastRoleCandidateStatus.suggested);
      expect(candidate.mappedCharacterId, isNull);
      expect(confirmed.status, RecastRoleCandidateStatus.confirmed);
      expect(confirmed.confirmed, isTrue);
      expect(confirmed.mappedCharacterId, 'char-alice');
      expect(rejected.status, RecastRoleCandidateStatus.rejected);
      expect(rejected.confirmed, isFalse);
      expect(renamed.displayName, 'Alice');
      expect(renamed.aliases, contains('alice'));
    });

    test('merges suggestions into a single candidate with combined evidence',
        () {
      const alice = RecastRoleCandidate(
        id: 'role-alice',
        displayName: 'Alice',
        importance: RecastRoleImportance.supporting,
        aliases: ['Alicia'],
        evidenceTags: ['Alice', 'blue hair'],
        frameIndexes: [1, 3],
        confidence: 0.7,
      );
      const alias = RecastRoleCandidate(
        id: 'role-alicia',
        displayName: 'Alicia',
        importance: RecastRoleImportance.protagonist,
        evidenceTags: ['Alicia', 'hero'],
        frameIndexes: [2, 3],
        confidence: 0.9,
      );

      final merged = alice.mergeWith(alias, displayName: 'Alice');

      expect(merged.id, 'role-alice');
      expect(merged.displayName, 'Alice');
      expect(merged.importance, RecastRoleImportance.protagonist);
      expect(merged.aliases, containsAll(['Alicia']));
      expect(merged.evidenceTags, ['Alice', 'blue hair', 'Alicia', 'hero']);
      expect(merged.frameIndexes, [1, 2, 3]);
      expect(merged.confidence, 0.9);
      expect(merged.status, RecastRoleCandidateStatus.suggested);
    });
  });

  group('RecastScriptCache', () {
    test('persists script scoped block words in cache json', () {
      final cache = RecastScriptCache(
        scriptId: 'script-1',
        scriptName: 'Script One',
        sourceRootPath: '/scripts/one',
        sourceFingerprint: 'fingerprint-1',
        updatedAt: DateTime.utc(2026, 6, 7),
        mapping: RecastMapping.defaults('script-1'),
        scriptBlockWords: 'city lights, lowres',
      );

      final restored = RecastScriptCache.fromJson(cache.toJson());

      expect(restored.scriptBlockWords, 'city lights, lowres');
    });

    test('persists parsed script snapshot in cache json', () {
      final cache = RecastScriptCache(
        scriptId: 'script-1',
        scriptName: 'Script One',
        sourceRootPath: '/scripts/one',
        sourceFingerprint: 'fingerprint-1',
        updatedAt: DateTime.utc(2026, 5, 26),
        mapping: RecastMapping.defaults('script-1'),
        scriptSnapshot: const {
          'id': 'script-1',
          'frames': [
            {'index': 1, 'fileName': 'nai_1.json'},
          ],
        },
      );

      final restored = RecastScriptCache.fromJson(cache.toJson());

      expect(restored.scriptSnapshot['id'], 'script-1');
      expect(restored.scriptSnapshot['frames'], hasLength(1));
    });

    test('script cache ignores legacy AI suggestion and plan keys', () {
      final restored = RecastScriptCache.fromJson({
        'scriptId': 'script',
        'scriptName': 'Script',
        'sourceRootPath': '',
        'sourceFingerprint': 'fingerprint',
        'updatedAt': DateTime.utc(2026, 6, 1).toIso8601String(),
        'mapping': RecastMapping.defaults('script').toJson(),
        'aiSuggestions': const [
          {'id': 'legacy-suggestion', 'displayName': 'alice'},
        ],
        'aiFailedBatches': const [
          {'id': 'legacy-batch'},
        ],
        'aiReviewBatches': const [
          {'id': 'legacy-review'},
        ],
        'aiRecastPlan': const {
          'status': 'ready',
          'roles': [
            {'source_role_id': 'slot-0', 'display_name': 'alice'},
          ],
        },
      });

      final json = restored.toJson();

      expect(json, isNot(contains('aiSuggestions')));
      expect(json, isNot(contains('aiFailedBatches')));
      expect(json, isNot(contains('aiReviewBatches')));
      expect(json, isNot(contains('aiRecastPlan')));
    });

    test('script cache reads legacy role candidates but no longer writes them',
        () {
      final restored = RecastScriptCache.fromJson({
        'scriptId': 'script',
        'scriptName': 'Script',
        'sourceRootPath': '',
        'sourceFingerprint': 'fingerprint',
        'updatedAt': DateTime.utc(2026, 6, 1).toIso8601String(),
        'mapping': RecastMapping.defaults('script').toJson(),
        'roleCandidates': const [
          {
            'id': 'role-alice',
            'displayName': 'alice',
            'importance': 'protagonist',
            'status': 'confirmed',
          },
        ],
        'knowledgeSnapshot': const {
          'roles': [
            {'displayName': 'alice'},
          ],
        },
      });

      final json = restored.toJson();

      expect(restored.roleCandidates.single.displayName, 'alice');
      expect(json, isNot(contains('roleCandidates')));
      expect(json, isNot(contains('knowledgeSnapshot')));
    });

    test('script cache persists AI role extraction draft', () {
      final cache = RecastScriptCache(
        scriptId: 'script',
        scriptName: 'Script',
        sourceRootPath: '',
        sourceFingerprint: 'fingerprint',
        updatedAt: DateTime.utc(2026, 6, 2),
        mapping: RecastMapping.defaults('script'),
        aiRoleExtraction: const ScriptAiRoleExtraction(
          status: ScriptAiRoleExtractionStatus.ready,
          confidence: 0.9,
          roles: [
            ScriptAiExtractedRole(
              sourceRoleId: 'slot-0',
              displayName: 'alice',
              confidence: 0.9,
              stages: [
                ScriptAiExtractedStage(
                  stageId: 'main',
                  identity: 'alice',
                  upperBody: 'green eyes',
                  lowerBody: 'black boots',
                  upperClothing: 'blue jacket',
                  lowerClothing: 'white skirt',
                  confidence: 0.88,
                ),
              ],
            ),
          ],
        ),
      );

      final json = cache.toJson();
      final restored = RecastScriptCache.fromJson(json);

      expect(json, contains('aiRoleExtraction'));
      expect(
          restored.aiRoleExtraction.status, ScriptAiRoleExtractionStatus.ready);
      expect(restored.aiRoleExtraction.roles.single.displayName, 'alice');
      expect(restored.aiRoleExtraction.roles.single.stages.single.identity,
          'alice');
    });

    test('script cache persists collapsed AI role extraction draft state', () {
      final cache = RecastScriptCache(
        scriptId: 'script',
        scriptName: 'Script',
        sourceRootPath: '',
        sourceFingerprint: 'fingerprint',
        updatedAt: DateTime.utc(2026, 6, 3),
        mapping: RecastMapping.defaults('script'),
        aiRoleExtractionDraftCollapsed: true,
        aiRoleExtraction: const ScriptAiRoleExtraction(
          status: ScriptAiRoleExtractionStatus.ready,
          confidence: 0.9,
        ),
      );

      final json = cache.toJson();
      final restored = RecastScriptCache.fromJson(json);

      expect(json['aiRoleExtractionDraftCollapsed'], isTrue);
      expect(restored.aiRoleExtractionDraftCollapsed, isTrue);
    });

    test('script cache persists AI role extraction chunk checkpoints', () {
      final cache = RecastScriptCache(
        scriptId: 'script',
        scriptName: 'Script',
        sourceRootPath: '',
        sourceFingerprint: 'fingerprint',
        updatedAt: DateTime.utc(2026, 6, 3),
        mapping: RecastMapping.defaults('script'),
        aiRoleExtractionChunks: const [
          ScriptAiRoleExtraction(
            status: ScriptAiRoleExtractionStatus.ready,
            chunkId: 'chunk-1',
            confidence: 0.8,
            roles: [
              ScriptAiExtractedRole(
                sourceRoleId: 'slot-0',
                displayName: 'alice',
                confidence: 0.8,
              ),
            ],
          ),
        ],
      );

      final json = cache.toJson();
      final restored = RecastScriptCache.fromJson(json);

      expect(json, contains('aiRoleExtractionChunks'));
      expect(restored.aiRoleExtractionChunks, hasLength(1));
      expect(restored.aiRoleExtractionChunks.single.chunkId, 'chunk-1');
      expect(
        restored.aiRoleExtractionChunks.single.roles.single.displayName,
        'alice',
      );
    });
  });
}
