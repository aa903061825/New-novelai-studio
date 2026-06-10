import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/studio/models/script_ai_role_extraction.dart';
import 'package:nai_casrand/data/studio/services/script_ai_role_extraction_merger.dart';

void main() {
  group('ScriptAiRoleExtractionMerger', () {
    const merger = ScriptAiRoleExtractionMerger();

    test('merges same slot role across chunks', () {
      final result = merger.merge([
        _extraction(
          confidence: 0.8,
          roles: [
            _role(
              sourceRoleId: 'slot-0',
              frameIndexes: [1],
              evidenceTerms: ['alice'],
              stages: [
                _stage(
                  'stage-a',
                  frameIndexes: [1],
                  upperClothing: 'school uniform',
                )
              ],
            ),
          ],
        ),
        _extraction(
          confidence: 0.6,
          roles: [
            _role(
              sourceRoleId: 'slot-0',
              frameIndexes: [2],
              evidenceTerms: ['white shirt'],
              stages: [
                _stage(
                  'stage-b',
                  frameIndexes: [2],
                  upperClothing: 'white nightgown',
                )
              ],
            ),
          ],
        ),
      ]);

      expect(result.status, ScriptAiRoleExtractionStatus.ready);
      expect(result.confidence, closeTo(0.7, 0.001));
      expect(result.roles, hasLength(1));
      expect(result.roles.single.sourceRoleId, 'slot-0');
      expect(result.roles.single.frameIndexes, [1, 2]);
      expect(result.roles.single.evidenceTerms, ['alice', 'white shirt']);
      expect(result.roles.single.stages.map((stage) => stage.stageId), [
        'stage-a',
        'stage-b',
      ]);
    });

    test('keeps different confident global roles separate', () {
      final result = merger.merge([
        _extraction(
          roles: [
            _role(
              sourceRoleId: 'global-0',
              sourceKind: 'global',
              displayName: 'Alice',
              evidenceTerms: ['alice'],
            ),
          ],
        ),
        _extraction(
          roles: [
            _role(
              sourceRoleId: 'global-0',
              sourceKind: 'global',
              displayName: 'Beth',
              evidenceTerms: ['beth'],
            ),
          ],
        ),
      ]);

      expect(result.roles, hasLength(2));
      expect(result.roles.map((role) => role.sourceRoleId), [
        'global-0',
        'global-0-2',
      ]);
      expect(result.roles.map((role) => role.displayName), ['Alice', 'Beth']);
    });

    test('merges exact cross-slot role ids and appearances across chunks', () {
      final result = merger.merge([
        _extraction(
          roles: [
            _role(
              sourceRoleId: 'role-0',
              sourceKind: 'cross_slot',
              displayName: 'Alice',
              frameIndexes: [1],
              appearances: const [
                ScriptAiRoleAppearance(
                  sourceId: 'slot-0',
                  sourceKind: 'slot',
                  frameIndexes: [1],
                ),
              ],
            ),
          ],
        ),
        _extraction(
          roles: [
            _role(
              sourceRoleId: 'role-0',
              sourceKind: 'cross_slot',
              displayName: 'Alice',
              frameIndexes: [2],
              appearances: const [
                ScriptAiRoleAppearance(
                  sourceId: 'slot-1',
                  sourceKind: 'slot',
                  frameIndexes: [2],
                ),
              ],
            ),
          ],
        ),
      ]);

      expect(result.roles, hasLength(1));
      final role = result.roles.single;
      expect(role.sourceRoleId, 'role-0');
      expect(role.sourceKind, 'cross_slot');
      expect(role.frameIndexes, [1, 2]);
      expect(role.appearances, hasLength(2));
      expect(role.appearances.map((item) => item.sourceId), [
        'slot-0',
        'slot-1',
      ]);
    });

    test('avoids global role id suffix collisions', () {
      final result = merger.merge([
        _extraction(
          roles: [
            _role(
              sourceRoleId: 'global-0-2',
              sourceKind: 'global',
              displayName: 'Already suffixed',
            ),
          ],
        ),
        _extraction(
          roles: [
            _role(
              sourceRoleId: 'global-0',
              sourceKind: 'global',
              displayName: 'First global',
            ),
          ],
        ),
        _extraction(
          roles: [
            _role(
              sourceRoleId: 'global-0',
              sourceKind: 'global',
              displayName: 'Second global',
            ),
          ],
        ),
      ]);

      expect(result.roles.map((role) => role.sourceRoleId), [
        'global-0-2',
        'global-0',
        'global-0-3',
      ]);
    });

    test('renames duplicate stage ids inside a merged role', () {
      final result = merger.merge([
        _extraction(
          roles: [
            _role(
              sourceRoleId: 'slot-0',
              stages: [
                _stage(
                  'stage-a',
                  frameIndexes: [1],
                  upperClothing: 'school uniform',
                )
              ],
            ),
          ],
        ),
        _extraction(
          roles: [
            _role(
              sourceRoleId: 'slot-0',
              stages: [
                _stage(
                  'stage-a',
                  frameIndexes: [2],
                  upperClothing: 'white nightgown',
                )
              ],
            ),
          ],
        ),
      ]);

      expect(result.roles.single.stages.map((stage) => stage.stageId), [
        'stage-a',
        'stage-a-2',
      ]);
    });

    test('collapses compatible stages after merging chunks', () {
      final result = merger.merge([
        _extraction(
          roles: [
            _role(
              sourceRoleId: 'slot-0',
              stages: [
                _stage(
                  'complete',
                  frameIndexes: [1],
                  identity: 'alice, girl',
                  upperBody: 'blue eyes, long hair',
                  upperClothing: 'school uniform, red ribbon',
                  lowerClothing: 'black shoes',
                ),
              ],
            ),
          ],
        ),
        _extraction(
          roles: [
            _role(
              sourceRoleId: 'slot-0',
              stages: [
                _stage(
                  'subset',
                  frameIndexes: [2],
                  identity: 'alice',
                  upperBody: 'blue eyes',
                  upperClothing: 'school uniform',
                ),
              ],
            ),
          ],
        ),
      ]);

      final stages = result.roles.single.stages;
      expect(stages, hasLength(1));
      expect(stages.single.stageId, 'complete');
      expect(stages.single.frameIndexes, [1, 2]);
      expect(stages.single.identity, 'alice, girl');
      expect(stages.single.upperBody, 'blue eyes, long hair');
      expect(stages.single.upperClothing, 'school uniform, red ribbon');
      expect(stages.single.lowerClothing, 'black shoes');
    });

    test('avoids stage id suffix collisions', () {
      final result = merger.merge([
        _extraction(
          roles: [
            _role(
              sourceRoleId: 'slot-0',
              stages: [
                _stage(
                  'stage-a-2',
                  frameIndexes: [1],
                  upperClothing: 'school uniform',
                ),
                _stage(
                  'stage-a',
                  frameIndexes: [2],
                  upperClothing: 'white nightgown',
                ),
              ],
            ),
          ],
        ),
        _extraction(
          roles: [
            _role(
              sourceRoleId: 'slot-0',
              stages: [
                _stage(
                  'stage-a',
                  frameIndexes: [3],
                  upperClothing: 'china dress',
                ),
              ],
            ),
          ],
        ),
      ]);

      expect(result.roles.single.stages.map((stage) => stage.stageId), [
        'stage-a-2',
        'stage-a',
        'stage-a-3',
      ]);
    });

    test('deduplicates official art artist terms by normalized key', () {
      final result = merger.merge([
        _extraction(
          artistChains: [
            const ScriptAiArtistChainEvidence(
              label: 'official',
              terms: ['official art'],
              frameIndexes: [1],
              confidence: 0.5,
              evidenceTerms: ['official art'],
            ),
            const ScriptAiArtistChainEvidence(
              label: 'official',
              terms: ['official_art'],
              frameIndexes: [2],
              confidence: 0.8,
              evidenceTerms: ['official_art'],
            ),
          ],
        ),
      ]);

      expect(result.artistChains, hasLength(1));
      expect(result.artistChains.single.terms, ['official art']);
      expect(result.artistChains.single.frameIndexes, [1, 2]);
      expect(result.artistChains.single.confidence, 0.8);
    });

    test('deduplicates artist label fallback against normalized terms', () {
      final result = merger.merge([
        _extraction(
          artistChains: [
            const ScriptAiArtistChainEvidence(
              label: 'official art',
              terms: [],
              frameIndexes: [1],
              confidence: 0.5,
              evidenceTerms: ['official art'],
            ),
            const ScriptAiArtistChainEvidence(
              label: '',
              terms: ['official_art'],
              frameIndexes: [2],
              confidence: 0.7,
              evidenceTerms: ['official_art'],
            ),
          ],
        ),
      ]);

      expect(result.artistChains, hasLength(1));
      expect(result.artistChains.single.label, 'official art');
      expect(result.artistChains.single.terms, ['official_art']);
      expect(result.artistChains.single.frameIndexes, [1, 2]);
      expect(result.artistChains.single.confidence, 0.7);
    });

    test('deduplicates mosaic censoring strong filter terms', () {
      final result = merger.merge([
        _extraction(
          strongFilterKeywords: [
            const ScriptAiStrongFilterKeyword(
              term: 'mosaic censoring',
              frameIndexes: [1],
              reason: 'first',
            ),
            const ScriptAiStrongFilterKeyword(
              term: 'mosaic_censoring',
              frameIndexes: [2],
              reason: 'second',
            ),
          ],
        ),
      ]);

      expect(result.strongFilterKeywords, hasLength(1));
      expect(result.strongFilterKeywords.single.term, 'mosaic censoring');
      expect(result.strongFilterKeywords.single.frameIndexes, [1, 2]);
      expect(result.strongFilterKeywords.single.reason, 'first');
    });

    test('preserves attention and unassigned terms', () {
      final result = merger.merge([
        _extraction(
          attentionItems: [
            const ScriptAiExtractionAttentionItem(
              id: 'attn-1',
              kind: 'low_confidence',
              message: 'check role',
            ),
          ],
          unassignedTerms: [
            const ScriptAiUnassignedTerm(
              term: 'mystery tag',
              frameIndexes: [1],
              reason: 'ambiguous',
            ),
          ],
          roles: [
            _role(
              sourceRoleId: 'slot-0',
              unassignedTerms: [
                const ScriptAiUnassignedTerm(
                  term: 'role mystery',
                  frameIndexes: [2],
                  reason: 'ambiguous role',
                ),
              ],
            ),
          ],
        ),
      ]);

      expect(result.attentionItems.single.id, 'attn-1');
      expect(result.unassignedTerms.single.term, 'mystery tag');
      expect(result.roles.single.unassignedTerms.single.term, 'role mystery');
    });
  });
}

ScriptAiRoleExtraction _extraction({
  double confidence = 0.8,
  List<ScriptAiExtractedRole> roles = const [],
  List<ScriptAiArtistChainEvidence> artistChains = const [],
  List<ScriptAiStrongFilterKeyword> strongFilterKeywords = const [],
  List<ScriptAiExtractionAttentionItem> attentionItems = const [],
  List<ScriptAiUnassignedTerm> unassignedTerms = const [],
}) {
  return ScriptAiRoleExtraction(
    status: ScriptAiRoleExtractionStatus.ready,
    confidence: confidence,
    roles: roles,
    artistChains: artistChains,
    strongFilterKeywords: strongFilterKeywords,
    attentionItems: attentionItems,
    unassignedTerms: unassignedTerms,
  );
}

ScriptAiExtractedRole _role({
  required String sourceRoleId,
  String sourceKind = 'slot',
  String displayName = 'Hero',
  List<int> frameIndexes = const [],
  List<String> evidenceTerms = const [],
  List<ScriptAiRoleAppearance> appearances = const [],
  List<ScriptAiExtractedStage> stages = const [],
  List<ScriptAiUnassignedTerm> unassignedTerms = const [],
}) {
  return ScriptAiExtractedRole(
    sourceRoleId: sourceRoleId,
    sourceKind: sourceKind,
    displayName: displayName,
    confidence: 0.8,
    frameIndexes: frameIndexes,
    evidenceTerms: evidenceTerms,
    appearances: appearances,
    stages: stages,
    unassignedTerms: unassignedTerms,
  );
}

ScriptAiExtractedStage _stage(
  String stageId, {
  List<int> frameIndexes = const [],
  String identity = 'alice',
  String upperBody = '',
  String lowerBody = '',
  String upperClothing = 'shirt',
  String lowerClothing = '',
}) {
  return ScriptAiExtractedStage(
    stageId: stageId,
    label: stageId,
    confidence: 0.8,
    frameIndexes: frameIndexes,
    identity: identity,
    upperBody: upperBody,
    lowerBody: lowerBody,
    upperClothing: upperClothing,
    lowerClothing: lowerClothing,
    evidenceTerms: [
      identity,
      upperBody,
      lowerBody,
      upperClothing,
      lowerClothing
    ].where((value) => value.trim().isNotEmpty).toList(growable: false),
  );
}
