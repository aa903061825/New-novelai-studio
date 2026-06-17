import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/data/studio/tools/prompt_tag_classifier.dart';
import 'package:novel_studio/data/studio/models/script_ai_role_extraction.dart';

void main() {
  group('ScriptAiRoleExtraction', () {
    test('parses role prompt terms and scene terms separately', () {
      final extraction = ScriptAiRoleExtraction.fromJson({
        'status': 'ready',
        'roles': [
          {
            'source_role_id': 'slot-0',
            'display_name': 'alice',
            'prompt_terms': [
              {
                'id': 'slot-0-identity-alice',
                'text': 'alice (wonder story)',
                'category': 'identity',
                'source_phrase': 'alice (wonder story), brown hair',
                'frame_indexes': [1, 2, 3],
              },
              {
                'id': 'slot-0-clothing-jacket',
                'text': 'red jacket',
                'category': 'clothing',
                'source_phrase': 'wearing a red jacket and black skirt',
                'frame_indexes': [1, 2, 3],
              },
            ],
          },
        ],
        'scene_terms': [
          {
            'id': 'scene-rainy-street',
            'text': 'rainy city street',
            'category': 'scene',
            'source_phrase': 'in a rainy city street at night',
            'source_location': 'base prompt',
            'frame_indexes': [1, 2],
          },
        ],
      });

      final role = extraction.roles.single;
      expect(role.promptTerms.map((term) => term.text), [
        'alice (wonder story)',
        'red jacket',
      ]);
      expect(role.promptTerms.first.category, PromptTagCategory.character);
      expect(role.promptTerms.last.category, PromptTagCategory.clothing);
      expect(extraction.sceneTerms.single.text, 'rainy city street');
      expect(extraction.sceneTerms.single.category, PromptTagCategory.scene);

      final allTerms = [
        for (final role in extraction.roles) ...role.promptTerms,
        ...extraction.sceneTerms,
      ].map((term) => term.text).toList();
      expect(allTerms, isNot(contains('1girl')));
      expect(allTerms, isNot(contains('solo')));
    });

    test('round trips prompt terms and scene terms', () {
      const extraction = ScriptAiRoleExtraction(
        status: ScriptAiRoleExtractionStatus.ready,
        roles: [
          ScriptAiExtractedRole(
            sourceRoleId: 'slot-0',
            promptTerms: [
              ScriptAiExtractedPromptTerm(
                id: 'slot-0-accessory-halo',
                text: 'halo',
                category: PromptTagCategory.clothing,
                sourcePhrase: 'halo, blue eyes',
                sourceLocation: 'slot-0 prompt',
                frameIndexes: [1],
              ),
            ],
          ),
        ],
        sceneTerms: [
          ScriptAiExtractedPromptTerm(
            id: 'scene-night',
            text: 'night',
            category: PromptTagCategory.scene,
            sourcePhrase: 'city street at night',
            sourceLocation: 'base prompt',
            frameIndexes: [1, 2],
          ),
        ],
      );

      final json = extraction.toJson();
      expect(
        ((json['roles'] as List).single
            as Map<String, dynamic>)['prompt_terms'],
        isA<List>(),
      );
      expect(json['scene_terms'], isA<List>());

      final restored = ScriptAiRoleExtraction.fromJson(json);
      expect(restored.toJson(), json);
    });

    test('prompt term category parsing accepts clothing state aliases', () {
      final snake = ScriptAiExtractedPromptTerm.fromJson({
        'text': 'open jacket',
        'category': 'clothing_state',
      });
      final camel = ScriptAiExtractedPromptTerm.fromJson({
        'text': 'wet shirt',
        'category': 'clothingState',
      });

      expect(snake.category, PromptTagCategory.clothing);
      expect(camel.category, PromptTagCategory.clothing);
    });

    test('collapseEquivalentStages preserves scene terms and role prompt terms',
        () {
      const extraction = ScriptAiRoleExtraction(
        status: ScriptAiRoleExtractionStatus.ready,
        roles: [
          ScriptAiExtractedRole(
            sourceRoleId: 'slot-0',
            displayName: 'alice',
            promptTerms: [
              ScriptAiExtractedPromptTerm(
                id: 'slot-0-identity-alice',
                text: 'alice (wonder story)',
                category: PromptTagCategory.character,
                sourcePhrase: 'alice (wonder story), brown hair',
                frameIndexes: [1, 2],
              ),
            ],
            stages: [
              ScriptAiExtractedStage(
                stageId: 'stage-1',
                frameIndexes: [1],
                identity: 'alice (wonder story)',
                upperClothing: 'red jacket',
              ),
              ScriptAiExtractedStage(
                stageId: 'stage-2',
                frameIndexes: [2],
                identity: 'alice (wonder story)',
                upperClothing: 'red jacket',
              ),
            ],
          ),
        ],
        sceneTerms: [
          ScriptAiExtractedPromptTerm(
            id: 'scene-rainy-street',
            text: 'rainy city street',
            category: PromptTagCategory.scene,
            sourcePhrase: 'in a rainy city street at night',
            sourceLocation: 'base prompt',
            frameIndexes: [1, 2],
          ),
        ],
      );

      final collapsed = extraction.collapseEquivalentStages();

      expect(collapsed.roles.single.stages, hasLength(1));
      expect(collapsed.roles.single.promptTerms.single.text,
          'alice (wonder story)');
      expect(collapsed.sceneTerms.single.text, 'rainy city street');
    });

    test('split generic multi-source roles scopes prompt terms by appearance',
        () {
      const extraction = ScriptAiRoleExtraction(
        status: ScriptAiRoleExtractionStatus.ready,
        roles: [
          ScriptAiExtractedRole(
            sourceRoleId: 'role-generic-girl',
            displayName: 'girl',
            appearances: [
              ScriptAiRoleAppearance(
                sourceId: 'slot-0',
                sourceKind: 'slot',
                frameIndexes: [1],
              ),
              ScriptAiRoleAppearance(
                sourceId: 'base',
                sourceKind: 'base',
                frameIndexes: [2],
              ),
            ],
            stages: [
              ScriptAiExtractedStage(
                stageId: 'slot-stage',
                frameIndexes: [1],
                identity: 'girl',
                upperClothing: 'red jacket',
              ),
              ScriptAiExtractedStage(
                stageId: 'base-stage',
                frameIndexes: [2],
                identity: 'girl',
                upperBody: 'blue eyes',
              ),
            ],
            promptTerms: [
              ScriptAiExtractedPromptTerm(
                id: 'slot-red-jacket',
                text: 'red jacket',
                category: PromptTagCategory.clothing,
                sourceLocation: 'slot-0 prompt',
                frameIndexes: [1],
              ),
              ScriptAiExtractedPromptTerm(
                id: 'base-blue-eyes',
                text: 'blue eyes',
                category: PromptTagCategory.upperBody,
                sourceLocation: 'base prompt',
                frameIndexes: [2],
              ),
            ],
          ),
        ],
      );

      final roles = extraction.collapseEquivalentStages().roles;
      final slotRole = roles.singleWhere(
        (role) => role.sourceRoleId == 'role-generic-girl-slot-0',
      );
      final baseRole = roles.singleWhere(
        (role) => role.sourceRoleId == 'role-generic-girl-base',
      );

      expect(slotRole.promptTerms.map((term) => term.text), ['red jacket']);
      expect(slotRole.promptTerms.single.frameIndexes, [1]);
      expect(baseRole.promptTerms.map((term) => term.text), ['blue eyes']);
      expect(baseRole.promptTerms.single.frameIndexes, [2]);
    });

    test('split generic roles scope frameless terms by source references', () {
      const extraction = ScriptAiRoleExtraction(
        status: ScriptAiRoleExtractionStatus.ready,
        roles: [
          ScriptAiExtractedRole(
            sourceRoleId: 'role-generic-girl',
            displayName: 'girl',
            appearances: [
              ScriptAiRoleAppearance(
                sourceId: 'slot-1',
                sourceKind: 'slot',
              ),
              ScriptAiRoleAppearance(
                sourceId: 'slot-10',
                sourceKind: 'slot',
              ),
            ],
            promptTerms: [
              ScriptAiExtractedPromptTerm(
                id: 'slot-1-red-jacket',
                text: 'red jacket',
                category: PromptTagCategory.clothing,
                sourceLocation: 'slot-1 prompt',
              ),
              ScriptAiExtractedPromptTerm(
                id: 'slot-10-blue-dress',
                text: 'blue dress',
                category: PromptTagCategory.clothing,
                sourceLocation: 'slot-10 prompt',
              ),
            ],
          ),
        ],
      );

      final roles = extraction.collapseEquivalentStages().roles;
      final slotOneRole = roles.singleWhere(
        (role) => role.sourceRoleId == 'role-generic-girl-slot-1',
      );
      final slotTenRole = roles.singleWhere(
        (role) => role.sourceRoleId == 'role-generic-girl-slot-10',
      );

      expect(slotOneRole.promptTerms.map((term) => term.text), ['red jacket']);
      expect(slotTenRole.promptTerms.map((term) => term.text), ['blue dress']);
    });

    test('merged prompt terms union frame evidence for matching ids', () {
      const extraction = ScriptAiRoleExtraction(
        status: ScriptAiRoleExtractionStatus.ready,
        roles: [
          ScriptAiExtractedRole(
            sourceRoleId: 'slot-0',
            displayName: 'alice',
            rawIdentityTags: ['alice (wonder story)'],
            promptTerms: [
              ScriptAiExtractedPromptTerm(
                id: 'alice-identity',
                text: 'alice (wonder story)',
                category: PromptTagCategory.character,
                sourcePhrase: 'alice (wonder story), red jacket',
                sourceLocation: 'slot-0 prompt',
                frameIndexes: [1],
              ),
            ],
          ),
          ScriptAiExtractedRole(
            sourceRoleId: 'slot-1',
            displayName: 'alice',
            rawIdentityTags: ['alice (wonder story)'],
            promptTerms: [
              ScriptAiExtractedPromptTerm(
                id: 'alice-identity',
                text: 'alice (wonder story)',
                category: PromptTagCategory.character,
                sourcePhrase: 'alice (wonder story), blue dress',
                sourceLocation: 'slot-1 prompt',
                frameIndexes: [2],
              ),
            ],
          ),
        ],
      );

      final role = extraction.collapseEquivalentStages().roles.single;

      expect(role.promptTerms, hasLength(1));
      expect(role.promptTerms.single.id, 'alice-identity');
      expect(role.promptTerms.single.frameIndexes, [1, 2]);
      expect(role.promptTerms.single.sourcePhrase,
          'alice (wonder story), red jacket');
    });

    test('ready extraction parses global-0', () {
      final extraction = ScriptAiRoleExtraction.fromJson({
        'schema_version': 1,
        'status': 'ready',
        'chunk_id': 'chunk-1',
        'confidence': 0.87,
        'roles': [
          {
            'source_role_id': 'global-0',
            'source_kind': 'global',
            'display_name': 'Heroine',
            'confidence': 0.91,
            'frame_indexes': [0, '1', 'bad'],
            'evidence_terms': ['blue hair', 7, 'school uniform'],
            'warnings': ['review hair accessory'],
            'stages': [
              {
                'stage_id': 'global-0-stage-0',
                'label': 'default',
                'confidence': '0.82',
                'frame_indexes': [0],
                'identity': 'blue-haired heroine',
                'upper_body': 'slim build',
                'lower_body': 'long legs',
                'upper_clothing': 'white shirt',
                'lower_clothing': 'pleated skirt',
                'evidence_terms': ['white shirt'],
                'missing_fields': ['missing_upper_clothing'],
                'warnings': ['low lower clothing evidence'],
              },
            ],
          },
        ],
      });

      expect(extraction.status, ScriptAiRoleExtractionStatus.ready);
      expect(extraction.roles.single.sourceRoleId, 'global-0');
      expect(extraction.toJson()['roles'], isA<List>());
    });

    test('stage preserves empty upper_clothing', () {
      final extraction = ScriptAiRoleExtraction.fromJson({
        'status': 'ready',
        'roles': [
          {
            'source_role_id': 'global-0',
            'stages': [
              {
                'stage_id': 'global-0-stage-0',
                'upper_clothing': '',
                'missing_fields': ['missing_upper_clothing'],
              },
            ],
          },
        ],
      });

      expect(extraction.roles.single.stages.single.upperClothing, '');
      expect(
        extraction.roles.single.stages.single.toJson(),
        containsPair('upper_clothing', ''),
      );
    });

    test('round trips stage non-role draft state', () {
      const extraction = ScriptAiRoleExtraction(
        status: ScriptAiRoleExtractionStatus.ready,
        roles: [
          ScriptAiExtractedRole(
            sourceRoleId: 'slot-0',
            stages: [
              ScriptAiExtractedStage(
                stageId: 'main-outfit',
                frameIndexes: [1, 2],
                identity: 'hero',
                upperBody: 'fox ears',
                upperClothing: 'blue jacket',
                nonRole: 'city street, smile',
                nonRoleMaterialized: true,
                confidence: 0.9,
              ),
            ],
          ),
        ],
      );

      final json = extraction.toJson();
      final restored = ScriptAiRoleExtraction.fromJson(json);
      final restoredStage = restored.roles.single.stages.single;

      expect(restoredStage.nonRole, 'city street, smile');
      expect(restoredStage.nonRoleMaterialized, isTrue);

      final roleJson = (json['roles'] as List).single as Map<String, dynamic>;
      final stageJson =
          (roleJson['stages'] as List).single as Map<String, dynamic>;
      expect(stageJson['non_role'], 'city street, smile');
      expect(stageJson['non_role_materialized'], isTrue);
    });

    test('collapses equivalent outfit stages while dropping action evidence',
        () {
      const extraction = ScriptAiRoleExtraction(
        status: ScriptAiRoleExtractionStatus.ready,
        roles: [
          ScriptAiExtractedRole(
            sourceRoleId: 'role-hero',
            displayName: 'hero',
            stages: [
              ScriptAiExtractedStage(
                stageId: 'stage-1',
                label: 'Stage 1',
                confidence: 0.6,
                frameIndexes: [1],
                identity: 'girl, hero',
                upperBody: 'brown hair',
                lowerBody: 'tail',
                upperClothing: 'school uniform',
                lowerClothing: 'white socks',
                nonRole: 'standing',
                nonRoleMaterialized: true,
              ),
              ScriptAiExtractedStage(
                stageId: 'stage-2',
                label: 'Stage 2',
                confidence: 0.8,
                frameIndexes: [3, 2],
                identity: 'hero, girl',
                upperBody: 'brown hair',
                lowerBody: 'tail',
                upperClothing: 'starting to take off her top, school uniform',
                lowerClothing: 'white socks',
                nonRole: 'bent over, standing',
                nonRoleMaterialized: true,
              ),
            ],
          ),
        ],
      );

      final collapsed = extraction.collapseEquivalentStages();
      final stage = collapsed.roles.single.stages.single;

      expect(stage.stageId, 'stage-1');
      expect(stage.confidence, 0.8);
      expect(stage.frameIndexes, [1, 2, 3]);
      expect(stage.identity, 'girl, hero');
      expect(stage.upperClothing, 'school uniform');
      expect(stage.nonRole, isEmpty);
      expect(stage.nonRoleMaterialized, isFalse);
    });

    test('demotes action terms from a single outfit stage', () {
      const extraction = ScriptAiRoleExtraction(
        status: ScriptAiRoleExtractionStatus.ready,
        roles: [
          ScriptAiExtractedRole(
            sourceRoleId: 'role-soyo',
            displayName: 'nagasaki soyo',
            stages: [
              ScriptAiExtractedStage(
                stageId: 'stage-5',
                label: 'Stage 5',
                confidence: 0.66,
                frameIndexes: [22],
                identity: 'girl, nagasaki soyo',
                upperClothing:
                    'starting to take off her top, navy blue school uniform',
                nonRole: 'side view',
                nonRoleMaterialized: true,
              ),
            ],
          ),
        ],
      );

      final collapsed = extraction.collapseEquivalentStages();
      final stage = collapsed.roles.single.stages.single;

      expect(stage.upperClothing, 'navy blue school uniform');
      expect(stage.nonRole, isEmpty);
      expect(stage.nonRoleMaterialized, isFalse);
      expect(stage.frameIndexes, [22]);
    });

    test('demotes pose expression and temporary terms from stable fields', () {
      const extraction = ScriptAiRoleExtraction(
        status: ScriptAiRoleExtractionStatus.ready,
        roles: [
          ScriptAiExtractedRole(
            sourceRoleId: 'slot-0',
            displayName: 'hero',
            stages: [
              ScriptAiExtractedStage(
                stageId: 'main',
                label: 'main',
                frameIndexes: [1],
                identity: 'hero, girl',
                upperBody: 'blue eyes, smile, closed eyes',
                lowerBody: 'fox tail, kneeling',
                upperClothing: 'school uniform, wet, lifted shirt',
                lowerClothing: 'pleated skirt, spread legs',
                confidence: 0.9,
              ),
            ],
          ),
        ],
      );

      final stage =
          extraction.collapseEquivalentStages().roles.single.stages.single;

      expect(stage.upperBody, 'blue eyes');
      expect(stage.lowerBody, 'fox tail');
      expect(stage.upperClothing, 'school uniform');
      expect(stage.lowerClothing, 'pleated skirt');
      expect(stage.nonRole, isEmpty);
      expect(stage.nonRoleMaterialized, isFalse);
    });

    test('drops transient evidence terms from pending role fields', () {
      const extraction = ScriptAiRoleExtraction(
        status: ScriptAiRoleExtractionStatus.ready,
        roles: [
          ScriptAiExtractedRole(
            sourceRoleId: 'slot-0',
            stages: [
              ScriptAiExtractedStage(
                stageId: 'main',
                identity: 'hero',
                upperBody: 'blue eyes',
                upperClothing: 'school uniform',
                evidenceTerms: ['blue eyes', 'looking at viewer', 'smile'],
              ),
            ],
          ),
        ],
      );

      final stage =
          extraction.collapseEquivalentStages().roles.single.stages.single;

      expect(stage.upperBody, 'blue eyes');
      expect(stage.upperClothing, 'school uniform');
      expect(stage.nonRole, isEmpty);
      expect(stage.nonRoleMaterialized, isFalse);
    });

    test('demotes underscore action terms from stable fields', () {
      const extraction = ScriptAiRoleExtraction(
        status: ScriptAiRoleExtractionStatus.ready,
        roles: [
          ScriptAiExtractedRole(
            sourceRoleId: 'slot-0',
            stages: [
              ScriptAiExtractedStage(
                stageId: 'main',
                identity: 'hero',
                upperBody: 'blue eyes',
                upperClothing:
                    'school uniform, fingering_through_clothes, undressing_another_clothes',
                lowerClothing: 'black shoes, spread_legs',
              ),
            ],
          ),
        ],
      );

      final stage =
          extraction.collapseEquivalentStages().roles.single.stages.single;

      expect(stage.upperClothing, 'school uniform');
      expect(stage.lowerClothing, 'black shoes');
      expect(stage.nonRole, isEmpty);
      expect(stage.nonRoleMaterialized, isFalse);
    });

    test('demotes pipe action terms and moves lower garments out of upper', () {
      const extraction = ScriptAiRoleExtraction(
        status: ScriptAiRoleExtractionStatus.ready,
        roles: [
          ScriptAiExtractedRole(
            sourceRoleId: 'slot-0',
            stages: [
              ScriptAiExtractedStage(
                stageId: 'main',
                identity: 'hero',
                upperBody:
                    'blue eyes, ||hand_between_breasts|covering_nipples||',
                lowerBody: 'tail, panties_aside',
                upperClothing:
                    'adjusting_clothes, lace-trimmed_panties, white_panties, dress_tug',
                lowerClothing: 'skirt_flip',
              ),
            ],
          ),
        ],
      );

      final stage =
          extraction.collapseEquivalentStages().roles.single.stages.single;

      expect(stage.upperBody, 'blue eyes');
      expect(stage.lowerBody, 'tail');
      expect(stage.upperClothing, '');
      expect(stage.lowerClothing, 'lace-trimmed_panties, white_panties');
      expect(stage.nonRole, isEmpty);
      expect(stage.nonRoleMaterialized, isFalse);
    });

    test('demotes observed temporary state terms from stable fields', () {
      const extraction = ScriptAiRoleExtraction(
        status: ScriptAiRoleExtractionStatus.ready,
        roles: [
          ScriptAiExtractedRole(
            sourceRoleId: 'slot-0',
            stages: [
              ScriptAiExtractedStage(
                stageId: 'main',
                identity: 'hero',
                upperBody:
                    'blue eyes, empty eyes, facial, penis on face, breasts out, bare shoulders, wavy mouth, mouth drool, arm around shoulder',
                lowerBody: 'tail, kissing penis',
                upperClothing: 'white leotard, male topless',
              ),
            ],
          ),
        ],
      );

      final stage =
          extraction.collapseEquivalentStages().roles.single.stages.single;

      expect(stage.upperBody, 'blue eyes');
      expect(stage.lowerBody, 'tail');
      expect(stage.upperClothing, 'white leotard');
      expect(stage.lowerClothing, '');
      expect(stage.nonRole, isEmpty);
      expect(stage.nonRoleMaterialized, isFalse);
    });

    test('collapses outfit stages when one stage only misses field evidence',
        () {
      const extraction = ScriptAiRoleExtraction(
        status: ScriptAiRoleExtractionStatus.ready,
        roles: [
          ScriptAiExtractedRole(
            sourceRoleId: 'role-soyo',
            displayName: 'nagasaki soyo',
            stages: [
              ScriptAiExtractedStage(
                stageId: 'stage-1',
                label: 'Stage 1',
                confidence: 0.66,
                frameIndexes: [2, 3],
                identity: 'girl, nagasaki soyo',
                lowerBody: 'barefoot',
                upperClothing: 'wearing navy blue school uniform',
                nonRole: 'sitting in taxi backseat',
                nonRoleMaterialized: true,
              ),
              ScriptAiExtractedStage(
                stageId: 'stage-5',
                label: 'Stage 5',
                confidence: 0.66,
                frameIndexes: [22],
                identity: 'girl, nagasaki soyo',
                upperClothing: 'wearing navy blue school uniform',
                nonRole: 'side view',
                nonRoleMaterialized: true,
                evidenceTerms: ['starting to take off her top'],
              ),
            ],
          ),
        ],
      );

      final collapsed = extraction.collapseEquivalentStages();
      final stage = collapsed.roles.single.stages.single;

      expect(stage.stageId, 'stage-1');
      expect(stage.frameIndexes, [2, 3, 22]);
      expect(stage.lowerBody, 'barefoot');
      expect(stage.upperClothing, 'wearing navy blue school uniform');
      expect(stage.nonRole, isEmpty);
      expect(stage.nonRoleMaterialized, isFalse);
    });

    test('collapses stages when one stable field set is a subset', () {
      const extraction = ScriptAiRoleExtraction(
        status: ScriptAiRoleExtractionStatus.ready,
        roles: [
          ScriptAiExtractedRole(
            sourceRoleId: 'slot-0',
            displayName: 'hero',
            stages: [
              ScriptAiExtractedStage(
                stageId: 'complete',
                frameIndexes: [1],
                identity: 'hero, girl',
                upperBody: 'blue eyes, long hair',
                upperClothing: 'school uniform, red ribbon',
                lowerClothing: 'black shoes',
              ),
              ScriptAiExtractedStage(
                stageId: 'subset',
                frameIndexes: [2],
                identity: 'hero',
                upperBody: 'blue eyes',
                upperClothing: 'school uniform',
                lowerClothing: '',
              ),
            ],
          ),
        ],
      );

      final stage =
          extraction.collapseEquivalentStages().roles.single.stages.single;

      expect(stage.stageId, 'complete');
      expect(stage.frameIndexes, [1, 2]);
      expect(stage.identity, 'hero, girl');
      expect(stage.upperBody, 'blue eyes, long hair');
      expect(stage.upperClothing, 'school uniform, red ribbon');
      expect(stage.lowerClothing, 'black shoes');
    });

    test('keeps clothing and nude replacement states as separate stages', () {
      const extraction = ScriptAiRoleExtraction(
        status: ScriptAiRoleExtractionStatus.ready,
        roles: [
          ScriptAiExtractedRole(
            sourceRoleId: 'role-aoi',
            displayName: 'aoi (mechanic) (princess connect!)',
            stages: [
              ScriptAiExtractedStage(
                stageId: 'tank-skirt',
                label: 'black tank top / back strap skirt',
                confidence: 0.72,
                frameIndexes: [
                  1,
                  4,
                  5,
                  6,
                  7,
                  8,
                  9,
                  10,
                  11,
                  12,
                  13,
                  14,
                  52,
                  53,
                  54,
                  55,
                  56,
                  57,
                  58,
                  59,
                  60,
                  61,
                  62,
                  63,
                  64,
                  65,
                  66,
                ],
                identity: 'aoi (mechanic) (princess connect!), girl',
                upperBody: 'green hair',
                upperClothing: 'black tank top',
                lowerClothing: 'overall skirt, white panties',
              ),
              ScriptAiExtractedStage(
                stageId: 'workwear',
                label: 'workshop overalls',
                confidence: 0.7,
                frameIndexes: [2, 3],
                identity: 'aoi (mechanic) (princess connect!), girl',
                upperBody: 'green hair',
                upperClothing: 'black tank top, blue overalls',
              ),
              ScriptAiExtractedStage(
                stageId: 'topless-panties',
                label: 'bedroom topless / white panties',
                confidence: 0.7,
                frameIndexes: [15],
                identity: 'aoi (mechanic) (princess connect!), girl',
                upperBody: 'green hair',
                lowerClothing: 'white panties',
                evidenceTerms: ['topless'],
              ),
              ScriptAiExtractedStage(
                stageId: 'nude',
                label: 'nude',
                confidence: 0.7,
                frameIndexes: [
                  16,
                  17,
                  18,
                  19,
                  20,
                  21,
                  22,
                  23,
                  24,
                  25,
                  26,
                  27,
                  28,
                  39,
                  40,
                  41,
                  42,
                  43,
                  44,
                  45,
                  46,
                  47,
                  48,
                  49,
                  50,
                  51,
                ],
                identity: 'aoi (mechanic) (princess connect!), girl',
                upperBody: 'green hair',
                evidenceTerms: ['completely nude'],
              ),
              ScriptAiExtractedStage(
                stageId: 'towel',
                label: 'bedroom bath towel',
                confidence: 0.7,
                frameIndexes: [29, 30, 31, 32, 33, 34, 35, 36, 37, 38],
                identity: 'aoi (mechanic) (princess connect!), girl',
                upperBody: 'green hair',
                upperClothing: 'white towel',
              ),
            ],
          ),
        ],
      );

      final stages = extraction.collapseEquivalentStages().roles.single.stages;

      expect(stages.map((stage) => stage.stageId), [
        'tank-skirt',
        'workwear',
        'topless-panties',
        'nude',
        'towel',
      ]);
      expect(
        stages.singleWhere((stage) => stage.stageId == 'nude').frameIndexes,
        contains(48),
      );
      expect(
        stages
            .singleWhere((stage) => stage.stageId == 'tank-skirt')
            .frameIndexes,
        isNot(contains(48)),
      );
    });

    test('makes duplicate stage ids unique before mapping materialization', () {
      const extraction = ScriptAiRoleExtraction(
        status: ScriptAiRoleExtractionStatus.ready,
        roles: [
          ScriptAiExtractedRole(
            sourceRoleId: 'role-saren',
            displayName: 'saren',
            stages: [
              ScriptAiExtractedStage(
                stageId: 'stage-1',
                frameIndexes: [1],
                identity: 'saren',
                upperClothing: 'white dress',
              ),
              ScriptAiExtractedStage(
                stageId: 'stage-1',
                frameIndexes: [2],
                identity: 'saren',
                upperClothing: 'aqua bikini',
              ),
              ScriptAiExtractedStage(
                stageId: 'stage-1',
                frameIndexes: [3],
                identity: 'saren',
                upperClothing: 'orange bikini',
              ),
            ],
          ),
        ],
      );

      final stages = extraction.collapseEquivalentStages().roles.single.stages;

      expect(stages.map((stage) => stage.stageId), [
        'stage-1',
        'stage-1-2',
        'stage-1-3',
      ]);
    });

    test('keeps genuinely different stable outfits as separate stages', () {
      const extraction = ScriptAiRoleExtraction(
        status: ScriptAiRoleExtractionStatus.ready,
        roles: [
          ScriptAiExtractedRole(
            sourceRoleId: 'slot-0',
            displayName: 'hero',
            stages: [
              ScriptAiExtractedStage(
                stageId: 'uniform',
                frameIndexes: [1],
                identity: 'hero, girl',
                upperBody: 'blue eyes',
                upperClothing: 'school uniform',
                lowerClothing: 'black shoes',
              ),
              ScriptAiExtractedStage(
                stageId: 'nightgown',
                frameIndexes: [2],
                identity: 'hero, girl',
                upperBody: 'blue eyes',
                upperClothing: 'white nightgown',
                lowerClothing: 'barefoot',
              ),
            ],
          ),
        ],
      );

      final stages = extraction.collapseEquivalentStages().roles.single.stages;

      expect(stages.map((stage) => stage.stageId), ['uniform', 'nightgown']);
    });

    test('merges official identity variants into one canonical role', () {
      const extraction = ScriptAiRoleExtraction(
        status: ScriptAiRoleExtractionStatus.ready,
        roles: [
          ScriptAiExtractedRole(
            sourceRoleId: 'slot-0',
            sourceKind: 'slot',
            displayName: 'Kokkoro',
            canonicalName: 'kokkoro',
            franchise: 'princess_connect!',
            rawIdentityTags: ['kokkoro (princess_connect!)'],
            stages: [
              ScriptAiExtractedStage(
                stageId: 'normal',
                frameIndexes: [1],
                identity: 'kokkoro (princess_connect!)',
              ),
            ],
          ),
          ScriptAiExtractedRole(
            sourceRoleId: 'slot-1',
            sourceKind: 'slot',
            displayName: 'Kokkoro ceremonial',
            canonicalName: 'kokkoro',
            franchise: 'princess_connect!',
            rawIdentityTags: [
              'kokkoro (ceremonial) (princess_connect!)',
            ],
            variantTags: ['ceremonial'],
            mergeWithRoleId: 'slot-0',
            stages: [
              ScriptAiExtractedStage(
                stageId: 'ceremonial-name-only',
                frameIndexes: [2],
                identity: 'kokkoro (ceremonial) (princess_connect!)',
              ),
            ],
          ),
        ],
      );

      final roles = extraction.collapseEquivalentStages().roles;

      expect(roles, hasLength(1));
      expect(roles.single.sourceRoleId, 'slot-0');
      expect(roles.single.canonicalName, 'kokkoro');
      expect(roles.single.franchise, 'princess_connect!');
      expect(roles.single.rawIdentityTags, [
        'kokkoro (princess_connect!)',
        'kokkoro (ceremonial) (princess_connect!)',
      ]);
      expect(roles.single.variantTags, ['ceremonial']);
      expect(roles.single.stages, hasLength(1));
      expect(roles.single.stages.single.identity, contains('kokkoro'));
      expect(roles.single.stages.single.upperClothing, isEmpty);
    });

    test('keeps official clothing variant as same role with outfit stage', () {
      const extraction = ScriptAiRoleExtraction(
        status: ScriptAiRoleExtractionStatus.ready,
        roles: [
          ScriptAiExtractedRole(
            sourceRoleId: 'slot-0',
            canonicalName: 'kokkoro',
            franchise: 'princess_connect!',
            rawIdentityTags: ['kokkoro (princess_connect!)'],
            stages: [
              ScriptAiExtractedStage(
                stageId: 'normal',
                frameIndexes: [1],
                identity: 'kokkoro (princess_connect!)',
                upperClothing: 'green cloak',
              ),
            ],
          ),
          ScriptAiExtractedRole(
            sourceRoleId: 'slot-1',
            canonicalName: 'kokkoro',
            franchise: 'princess_connect!',
            rawIdentityTags: [
              'kokkoro (ceremonial) (princess_connect!)',
            ],
            variantTags: ['ceremonial'],
            stages: [
              ScriptAiExtractedStage(
                stageId: 'ceremonial',
                frameIndexes: [2],
                identity: 'kokkoro (ceremonial) (princess_connect!)',
                upperClothing: 'ceremonial robe',
              ),
            ],
          ),
        ],
      );

      final roles = extraction.collapseEquivalentStages().roles;

      expect(roles, hasLength(1));
      expect(roles.single.stages.map((stage) => stage.stageId), [
        'normal',
        'ceremonial',
      ]);
      expect(roles.single.stages.last.upperClothing, 'ceremonial robe');
    });

    test('derives canonical identity from display name when AI omitted fields',
        () {
      const extraction = ScriptAiRoleExtraction(
        status: ScriptAiRoleExtractionStatus.ready,
        roles: [
          ScriptAiExtractedRole(
            sourceRoleId: 'role-karyl',
            displayName: 'karyl (princess connect!)',
            stages: [
              ScriptAiExtractedStage(
                stageId: 'stage-1',
                frameIndexes: [1],
                identity: 'girl',
              ),
            ],
          ),
        ],
      );

      final role = extraction.collapseEquivalentStages().roles.single;

      expect(role.canonicalName, 'karyl');
      expect(role.franchise, 'princess connect!');
      expect(role.rawIdentityTags, ['karyl (princess connect!)']);
    });

    test('does not merge same canonical name across different franchises', () {
      const extraction = ScriptAiRoleExtraction(
        status: ScriptAiRoleExtractionStatus.ready,
        roles: [
          ScriptAiExtractedRole(
            sourceRoleId: 'slot-0',
            canonicalName: 'kokkoro',
            franchise: 'princess_connect!',
            rawIdentityTags: ['kokkoro (princess_connect!)'],
            stages: [
              ScriptAiExtractedStage(
                stageId: 'pc',
                identity: 'kokkoro (princess_connect!)',
              ),
            ],
          ),
          ScriptAiExtractedRole(
            sourceRoleId: 'slot-1',
            canonicalName: 'kokkoro',
            franchise: 'other_series',
            rawIdentityTags: ['kokkoro (other_series)'],
            stages: [
              ScriptAiExtractedStage(
                stageId: 'other',
                identity: 'kokkoro (other_series)',
              ),
            ],
          ),
        ],
      );

      expect(extraction.collapseEquivalentStages().roles, hasLength(2));
    });

    test('splits generic multi-slot roles instead of cross-slot merging', () {
      const extraction = ScriptAiRoleExtraction(
        status: ScriptAiRoleExtractionStatus.ready,
        roles: [
          ScriptAiExtractedRole(
            sourceRoleId: 'role-generic-boy',
            sourceKind: 'cross_slot',
            displayName: 'boy',
            appearances: [
              ScriptAiRoleAppearance(
                sourceId: 'slot-1',
                sourceKind: 'slot',
                frameIndexes: [1, 2, 3],
              ),
              ScriptAiRoleAppearance(
                sourceId: 'slot-2',
                sourceKind: 'slot',
                frameIndexes: [2, 3, 4],
              ),
            ],
            stages: [
              ScriptAiExtractedStage(
                stageId: 'stage-1',
                frameIndexes: [1],
                identity: 'boy',
                upperClothing: 'shirt',
              ),
            ],
          ),
        ],
      );

      final roles = extraction.collapseEquivalentStages().roles;

      expect(roles.map((role) => role.sourceRoleId), [
        'role-generic-boy-slot-1',
        'role-generic-boy-slot-2',
      ]);
      expect(roles.first.appearances.single.sourceId, 'slot-1');
      expect(roles.last.appearances.single.sourceId, 'slot-2');
      expect(roles.first.stages.single.frameIndexes, [1, 2, 3]);
      expect(roles.last.stages.single.frameIndexes, [2, 3, 4]);
    });

    test('splits generic multi-source roles even with descriptor identity', () {
      const extraction = ScriptAiRoleExtraction(
        status: ScriptAiRoleExtractionStatus.ready,
        roles: [
          ScriptAiExtractedRole(
            sourceRoleId: 'role-generic-boy',
            displayName: 'boy',
            appearances: [
              ScriptAiRoleAppearance(
                sourceId: 'base',
                sourceKind: 'base',
                frameIndexes: [1],
              ),
              ScriptAiRoleAppearance(
                sourceId: 'slot-0',
                sourceKind: 'slot',
                frameIndexes: [2],
              ),
            ],
            stages: [
              ScriptAiExtractedStage(
                stageId: 'stage-1',
                frameIndexes: [1, 2],
                identity: 'boy, bandit',
                upperClothing: 'bandana',
              ),
            ],
          ),
        ],
      );

      final roles = extraction.collapseEquivalentStages().roles;

      expect(roles.map((role) => role.sourceRoleId), [
        'role-generic-boy-base',
        'role-generic-boy-slot-0',
      ]);
      expect(roles.first.stages.single.identity, 'boy, bandit');
      expect(roles.first.stages.single.frameIndexes, [1]);
      expect(roles.last.stages.single.frameIndexes, [2]);
    });

    test('demotes cross-frame qualifiers out of stable role fields', () {
      const extraction = ScriptAiRoleExtraction(
        status: ScriptAiRoleExtractionStatus.ready,
        roles: [
          ScriptAiExtractedRole(
            sourceRoleId: 'slot-1',
            displayName: 'Sparkle',
            stages: [
              ScriptAiExtractedStage(
                stageId: 'sparkle-stage',
                frameIndexes: [1, 2],
                identity: 'sparkle (honkai: star rail)',
                upperBody: 'fox mask often present, flower tattoo',
                upperClothing: 'red dress, black gloves in some early frames',
                lowerClothing:
                    'red skirt, white panties only in some compromised frames',
              ),
            ],
          ),
        ],
      );

      final stage =
          extraction.collapseEquivalentStages().roles.single.stages.single;

      expect(stage.upperBody, 'flower tattoo');
      expect(stage.upperClothing, 'red dress');
      expect(stage.lowerClothing, 'red skirt');
      expect(stage.nonRole, isEmpty);
      expect(stage.nonRoleMaterialized, isFalse);
    });

    test('round trips AI stage grouping and field reasons', () {
      final extraction = ScriptAiRoleExtraction.fromJson({
        'status': 'ready',
        'roles': [
          {
            'source_role_id': 'global-0',
            'source_kind': 'global',
            'display_name': 'Alice',
            'role_reason': 'base prompt names Alice directly',
            'canonical_name': 'alice',
            'franchise': 'series',
            'raw_identity_tags': ['alice_(series)'],
            'variant_tags': ['school uniform'],
            'merge_with_role_id': 'global-main',
            'stages': [
              {
                'stage_id': 'alice-main',
                'appearance_group_id': 'alice-school-uniform',
                'merge_with_stage_ids': ['alice-main-subset'],
                'field_reasons': {
                  'identity': 'alice_(series) is a character tag',
                  'upper_clothing': 'school uniform is stable clothing',
                  'non_role': 'smile is an expression',
                },
                'identity': 'alice_(series)',
                'upper_clothing': 'school uniform',
              },
            ],
          },
        ],
      });

      final role = extraction.roles.single;
      final stage = role.stages.single;
      expect(role.roleReason, 'base prompt names Alice directly');
      expect(role.canonicalName, 'alice');
      expect(role.franchise, 'series');
      expect(role.rawIdentityTags, ['alice_(series)']);
      expect(role.variantTags, ['school uniform']);
      expect(role.mergeWithRoleId, 'global-main');
      expect(stage.appearanceGroupId, 'alice-school-uniform');
      expect(stage.mergeWithStageIds, ['alice-main-subset']);
      expect(
          stage.fieldReasons['identity'], 'alice_(series) is a character tag');

      final json = extraction.toJson();
      final restored = ScriptAiRoleExtraction.fromJson(json);
      expect(restored.toJson(), json);
    });

    test('old stage json without non-role remains readable', () {
      final extraction = ScriptAiRoleExtraction.fromJson({
        'status': 'ready',
        'roles': [
          {
            'source_role_id': 'slot-0',
            'stages': [
              {
                'stage_id': 'main-outfit',
                'frame_indexes': [1],
                'identity': 'hero',
                'upper_body': 'fox ears',
                'lower_body': '',
                'upper_clothing': 'blue jacket',
                'lower_clothing': '',
                'confidence': 0.9,
              },
            ],
          },
        ],
      });

      final stage = extraction.roles.single.stages.single;
      expect(stage.nonRole, '');
      expect(stage.nonRoleMaterialized, isFalse);
    });

    test('round trips cross-slot role appearances', () {
      final extraction = ScriptAiRoleExtraction.fromJson({
        'status': 'ready',
        'roles': [
          {
            'source_role_id': 'role-0',
            'source_kind': 'cross_slot',
            'display_name': 'Alice',
            'frame_indexes': [1, 2, 3],
            'appearances': [
              {
                'source_id': 'slot-0',
                'source_kind': 'slot',
                'frame_indexes': [1, 3],
              },
              {
                'source_id': 'slot-1',
                'source_kind': 'slot',
                'frame_indexes': [2],
              },
            ],
          },
        ],
      });

      final role = extraction.roles.single;
      expect(role.sourceRoleId, 'role-0');
      expect(role.sourceKind, 'cross_slot');
      expect(role.appearances, hasLength(2));
      expect(role.appearances.first.sourceId, 'slot-0');
      expect(role.appearances.first.frameIndexes, [1, 3]);

      final json = extraction.toJson();
      final restored = ScriptAiRoleExtraction.fromJson(json);
      expect(restored.toJson(), json);
      expect(
        ((json['roles'] as List).single as Map<String, dynamic>)['appearances'],
        isA<List>(),
      );
    });

    test('missing fields parse', () {
      final extraction = ScriptAiRoleExtraction.fromJson({
        'status': 'ready',
        'roles': [
          {
            'source_role_id': 'global-0',
            'stages': [
              {
                'stage_id': 'global-0-stage-0',
                'missing_fields': ['missing_upper_clothing'],
              },
            ],
          },
        ],
      });

      expect(
        extraction.roles.single.stages.single.missingFields,
        contains('missing_upper_clothing'),
      );
    });

    test('artist-chain official art parses', () {
      final extraction = ScriptAiRoleExtraction.fromJson({
        'status': 'ready',
        'artist_chains': [
          {
            'label': 'official baseline',
            'terms': ['official art', 'key visual'],
            'frame_indexes': [0, '1'],
            'confidence': '0.76',
            'evidence_terms': ['official art'],
          },
        ],
      });

      expect(extraction.artistChains.single.terms, contains('official art'));
    });

    test('mosaic strong filter keyword parses', () {
      final extraction = ScriptAiRoleExtraction.fromJson({
        'status': 'ready',
        'strong_filter_keywords': [
          {
            'term': 'mosaic censoring',
            'frame_indexes': [2],
            'reason': 'Strong negative filter term found in source prompt.',
          },
        ],
      });

      expect(extraction.strongFilterKeywords.single.term, 'mosaic censoring');
    });

    test('failure object stores raw response', () {
      final failure = ScriptAiRoleExtraction.failure(
        message: 'Missing JSON object',
        rawResponse: '[]',
      );

      expect(failure.status, ScriptAiRoleExtractionStatus.failed);
      expect(failure.rawResponse, '[]');
      expect(failure.attentionItems.single.message, 'Missing JSON object');
      expect(failure.attentionItems.single.blocking, isTrue);
    });

    test('parses needs_more_evidence response with evidence requests', () {
      final extraction = ScriptAiRoleExtraction.fromJson({
        'schema_version': 2,
        'status': 'needs_more_evidence',
        'chunk_id': 'chunk-1',
        'evidence_requests': [
          {
            'id': 'slot-0-stage-ambiguity',
            'source_id': 'slot-0',
            'frame_indexes': [8, '9', 10],
            'wanted_fields': [
              'base_caption',
              'char_caption',
              'negative_caption',
            ],
            'reason': 'Need exact nearby captions.',
          },
        ],
      });

      expect(extraction.schemaVersion, 2);
      expect(
        extraction.status,
        ScriptAiRoleExtractionStatus.needsMoreEvidence,
      );
      expect(extraction.isNeedsMoreEvidence, isTrue);
      expect(extraction.evidenceRequests, hasLength(1));
      expect(extraction.evidenceRequests.single.id, 'slot-0-stage-ambiguity');
      expect(extraction.evidenceRequests.single.sourceId, 'slot-0');
      expect(extraction.evidenceRequests.single.frameIndexes, [8, 9, 10]);
      expect(
        extraction.evidenceRequests.single.wantedFields,
        contains('char_caption'),
      );
    });

    test('serializes evidence requests with snake case status', () {
      const extraction = ScriptAiRoleExtraction(
        schemaVersion: 2,
        status: ScriptAiRoleExtractionStatus.needsMoreEvidence,
        chunkId: 'chunk-1',
        evidenceRequests: [
          ScriptAiEvidenceRequest(
            id: 'slot-0-stage-ambiguity',
            sourceId: 'slot-0',
            frameIndexes: [8, 9],
            wantedFields: ['base_caption', 'char_caption'],
            reason: 'Need exact nearby captions.',
          ),
        ],
      );

      final json = extraction.toJson();

      expect(json['schema_version'], 2);
      expect(json['status'], 'needs_more_evidence');
      expect(json['evidence_requests'], isA<List>());
      expect(
        (json['evidence_requests'] as List).single,
        containsPair('source_id', 'slot-0'),
      );
    });

    test('old ready cache json remains readable', () {
      final extraction = ScriptAiRoleExtraction.fromJson({
        'schema_version': 1,
        'status': 'ready',
        'confidence': 0.8,
        'roles': [],
      });

      expect(extraction.status, ScriptAiRoleExtractionStatus.ready);
      expect(extraction.evidenceRequests, isEmpty);
    });

    test('toJson emits full snake_case schema arrays for empty objects', () {
      final extractionJson = const ScriptAiRoleExtraction().toJson();

      expect(extractionJson, containsPair('roles', isEmpty));
      expect(extractionJson, containsPair('artist_chains', isEmpty));
      expect(extractionJson, containsPair('strong_filter_keywords', isEmpty));
      expect(extractionJson, containsPair('attention_items', isEmpty));
      expect(extractionJson, containsPair('unassigned_terms', isEmpty));
      expect(extractionJson, isNot(contains('chunk_id')));
      expect(extractionJson, isNot(contains('raw_response')));

      final roleJson = const ScriptAiExtractedRole().toJson();
      expect(roleJson, containsPair('source_role_id', ''));
      expect(roleJson, containsPair('source_kind', ''));
      expect(roleJson, containsPair('display_name', ''));
      expect(roleJson, containsPair('canonical_name', ''));
      expect(roleJson, containsPair('franchise', ''));
      expect(roleJson, containsPair('raw_identity_tags', isEmpty));
      expect(roleJson, containsPair('variant_tags', isEmpty));
      expect(roleJson, containsPair('merge_with_role_id', ''));
      expect(roleJson, containsPair('frame_indexes', isEmpty));
      expect(roleJson, containsPair('evidence_terms', isEmpty));
      expect(roleJson, containsPair('warnings', isEmpty));
      expect(roleJson, containsPair('stages', isEmpty));
      expect(roleJson, containsPair('unassigned_terms', isEmpty));

      final stageJson = const ScriptAiExtractedStage().toJson();
      expect(stageJson, containsPair('stage_id', ''));
      expect(stageJson, containsPair('label', ''));
      expect(stageJson, containsPair('frame_indexes', isEmpty));
      expect(stageJson, containsPair('identity', ''));
      expect(stageJson, containsPair('upper_body', ''));
      expect(stageJson, containsPair('lower_body', ''));
      expect(stageJson, containsPair('upper_clothing', ''));
      expect(stageJson, containsPair('lower_clothing', ''));
      expect(stageJson, containsPair('evidence_terms', isEmpty));
      expect(stageJson, containsPair('missing_fields', isEmpty));
      expect(stageJson, containsPair('warnings', isEmpty));

      expect(
        const ScriptAiArtistChainEvidence().toJson(),
        containsPair('evidence_terms', isEmpty),
      );
      expect(
        const ScriptAiStrongFilterKeyword().toJson(),
        containsPair('frame_indexes', isEmpty),
      );
      expect(
        const ScriptAiExtractionAttentionItem().toJson(),
        containsPair('frame_indexes', isEmpty),
      );
      expect(
        const ScriptAiExtractionAttentionItem().toJson(),
        isNot(contains('source_role_id')),
      );
      expect(
        const ScriptAiUnassignedTerm().toJson(),
        containsPair('frame_indexes', isEmpty),
      );
    });

    test('round trips all model classes with full snake_case output', () {
      const extraction = ScriptAiRoleExtraction(
        schemaVersion: 2,
        status: ScriptAiRoleExtractionStatus.ready,
        chunkId: 'chunk-9',
        confidence: 0.93,
        roles: [
          ScriptAiExtractedRole(
            sourceRoleId: 'global-0',
            sourceKind: 'global',
            displayName: 'Heroine',
            confidence: 0.91,
            frameIndexes: [0, 1],
            evidenceTerms: ['blue hair'],
            warnings: ['review accessory'],
            stages: [
              ScriptAiExtractedStage(
                stageId: 'global-0-stage-0',
                label: 'default',
                confidence: 0.82,
                frameIndexes: [0],
                identity: 'blue-haired heroine',
                upperBody: 'slim build',
                lowerBody: 'long legs',
                upperClothing: '',
                lowerClothing: 'pleated skirt',
                evidenceTerms: ['pleated skirt'],
                missingFields: ['missing_upper_clothing'],
                warnings: ['empty upper clothing evidence'],
              ),
            ],
            unassignedTerms: [
              ScriptAiUnassignedTerm(
                term: 'loose ribbon',
                frameIndexes: [1],
                reason: 'Could not assign to a stage field.',
              ),
            ],
          ),
        ],
        artistChains: [
          ScriptAiArtistChainEvidence(
            label: 'official baseline',
            terms: ['official art'],
            frameIndexes: [0, 1],
            confidence: 0.76,
            evidenceTerms: ['key visual'],
          ),
        ],
        strongFilterKeywords: [
          ScriptAiStrongFilterKeyword(
            term: 'mosaic censoring',
            frameIndexes: [2],
            reason: 'Strong filter keyword.',
          ),
        ],
        attentionItems: [
          ScriptAiExtractionAttentionItem(
            id: 'review-global-0',
            kind: 'review',
            message: 'Review empty upper clothing.',
            sourceRoleId: 'global-0',
            frameIndexes: [0],
            blocking: false,
          ),
        ],
        unassignedTerms: [
          ScriptAiUnassignedTerm(
            term: 'floating prop',
            frameIndexes: [3],
            reason: 'No matching role.',
          ),
        ],
        rawResponse: '{"status":"ready"}',
      );

      final json = extraction.toJson();
      final restored = ScriptAiRoleExtraction.fromJson(json);

      expect(restored.toJson(), json);
      expect(
          json.keys,
          containsAll([
            'schema_version',
            'status',
            'chunk_id',
            'confidence',
            'roles',
            'artist_chains',
            'strong_filter_keywords',
            'attention_items',
            'unassigned_terms',
            'raw_response',
          ]));

      final roleJson = (json['roles'] as List).single as Map<String, dynamic>;
      expect(
          roleJson.keys,
          containsAll([
            'source_role_id',
            'source_kind',
            'display_name',
            'confidence',
            'frame_indexes',
            'evidence_terms',
            'warnings',
            'stages',
            'unassigned_terms',
          ]));

      final stageJson =
          (roleJson['stages'] as List).single as Map<String, dynamic>;
      expect(
          stageJson.keys,
          containsAll([
            'stage_id',
            'label',
            'confidence',
            'frame_indexes',
            'identity',
            'upper_body',
            'lower_body',
            'upper_clothing',
            'lower_clothing',
            'evidence_terms',
            'missing_fields',
            'warnings',
          ]));
      expect(stageJson['upper_clothing'], '');

      final artistJson =
          (json['artist_chains'] as List).single as Map<String, dynamic>;
      expect(
          artistJson.keys,
          containsAll([
            'label',
            'terms',
            'frame_indexes',
            'confidence',
            'evidence_terms',
          ]));

      final keywordJson = (json['strong_filter_keywords'] as List).single
          as Map<String, dynamic>;
      expect(
          keywordJson.keys,
          containsAll([
            'term',
            'frame_indexes',
            'reason',
          ]));

      final attentionJson =
          (json['attention_items'] as List).single as Map<String, dynamic>;
      expect(
          attentionJson.keys,
          containsAll([
            'id',
            'kind',
            'message',
            'source_role_id',
            'frame_indexes',
            'blocking',
          ]));

      final unassignedJson =
          (json['unassigned_terms'] as List).single as Map<String, dynamic>;
      expect(
          unassignedJson.keys,
          containsAll([
            'term',
            'frame_indexes',
            'reason',
          ]));
    });

    test('failure serializes and round trips raw response', () {
      final failure = ScriptAiRoleExtraction.failure(
        message: 'Missing JSON object',
        rawResponse: '[]',
      );

      final json = failure.toJson();
      final restored = ScriptAiRoleExtraction.fromJson(json);

      expect(restored.status, ScriptAiRoleExtractionStatus.failed);
      expect(restored.rawResponse, '[]');
      expect(json['roles'], isEmpty);
      expect(json['artist_chains'], isEmpty);
      expect(json['strong_filter_keywords'], isEmpty);
      expect(json['unassigned_terms'], isEmpty);
      expect((json['attention_items'] as List).single, {
        'id': 'ai-role-extraction-parse-failure',
        'kind': 'parse_failure',
        'message': 'Missing JSON object',
        'frame_indexes': <int>[],
        'blocking': true,
      });
    });
  });
}
