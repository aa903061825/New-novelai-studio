import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/data/studio/models/script_ai_role_extraction.dart';
import 'package:novel_studio/data/studio/models/studio_asset_capture.dart';
import 'package:novel_studio/data/studio/models/studio_gallery_record.dart';
import 'package:novel_studio/data/studio/models/workbench_document.dart';
import 'package:novel_studio/data/workspace/models/workspace_entities.dart';

void main() {
  group('StudioAssetCaptureDrafts', () {
    test('builds an artist-chain draft from AI evidence', () {
      final draft = StudioAssetCaptureDrafts.artistFromAiEvidence(
        const ScriptAiArtistChainEvidence(
          label: 'soft cel stack',
          terms: ['artist:foo', 'artist:bar', 'soft shading'],
          evidenceTerms: ['artist:foo'],
        ),
        source: const StudioAssetCaptureSource(
          surface: 'script',
          label: 'AI role extraction',
          sourceId: 'chunk-1',
        ),
      );

      expect(draft.kind, StudioAssetCaptureKind.artistChain);
      expect(draft.name, 'soft cel stack');
      expect(
        draft.artistChain!.tags,
        ['artist:foo', 'artist:bar', 'soft shading'],
      );
      expect(
        draft.artistChain!.artists.map((entry) => entry.name),
        ['foo', 'bar'],
      );
      expect(draft.artistChain!.source.type, 'script');
    });

    test('builds an artist-chain draft from structured prompt text', () {
      final draft = StudioAssetCaptureDrafts.artistFromPrompt(
        'artist:alpha, watercolor, artist:beta',
        source: const StudioAssetCaptureSource(
          surface: 'script',
          label: 'Artist mapping target',
          sourceId: 'artist-mapping-target-0',
        ),
      );

      expect(draft.kind, StudioAssetCaptureKind.artistChain);
      expect(draft.name, 'alpha + beta');
      expect(draft.artistChain!.tags, ['artist:alpha', 'artist:beta']);
      expect(draft.artistChain!.styleTags, ['watercolor']);
      expect(
          draft.artistChain!.prompt, 'artist:alpha, artist:beta, watercolor');
      expect(draft.artistChain!.artists.map((entry) => entry.name), [
        'alpha',
        'beta',
      ]);
    });

    test('builds an artist-chain draft from bare artist aliases', () {
      final draft = StudioAssetCaptureDrafts.artistFromPrompt(
        '1girl, arato_asato, ratatatat74, artist collaboration',
        source: const StudioAssetCaptureSource(
          surface: 'script_exhibition',
          label: 'Original script frame',
          sourceId: 'original-1',
        ),
      );

      expect(draft.kind, StudioAssetCaptureKind.artistChain);
      expect(draft.name, 'arato_asato + ratatatat74');
      expect(draft.artistChain!.tags, ['arato_asato', 'ratatatat74']);
      expect(draft.artistChain!.styleTags, ['artist collaboration']);
      expect(
        draft.artistChain!.prompt,
        'arato_asato, ratatatat74, artist collaboration',
      );
    });

    test('builds an artist-chain draft from visible block tags', () {
      final draft = StudioAssetCaptureDrafts.artistFromVisibleTags(
        ['artist:alpha', 'watercolor'],
        source: const StudioAssetCaptureSource(
          surface: 'gallery',
          label: 'Gallery preview block',
          sourceId: 'image-1',
        ),
      );

      expect(draft.kind, StudioAssetCaptureKind.artistChain);
      expect(draft.name, 'alpha');
      expect(draft.artistChain!.tags, ['artist:alpha', 'watercolor']);
      expect(draft.artistChain!.styleTags, isEmpty);
      expect(draft.artistChain!.prompt, 'artist:alpha, watercolor');
      expect(draft.artistChain!.artists.map((entry) => entry.name), ['alpha']);
    });

    test('builds a character draft from visible block tags', () {
      final draft = StudioAssetCaptureDrafts.characterFromVisibleTags(
        ['1girl', 'fox ears'],
        source: const StudioAssetCaptureSource(
          surface: 'script_exhibition',
          label: 'Preview character block',
          sourceId: 'frame-1',
        ),
      );

      final character = draft.character!;
      expect(draft.kind, StudioAssetCaptureKind.character);
      expect(draft.name, 'Preview character block');
      expect(character.traits.frontFull, 'fox ears');
      expect(character.identityTags, ['fox ears']);
    });

    test(
        'builds a character draft from an extracted role using current '
        'character schema', () {
      final draft = StudioAssetCaptureDrafts.characterFromAiRole(
        const ScriptAiExtractedRole(
          sourceRoleId: 'role-a',
          displayName: 'Hero A',
          evidenceTerms: ['blue eyes', 'short hair'],
          stages: [
            ScriptAiExtractedStage(
              stageId: 'base',
              label: 'school',
              identity: 'blue eyes, short hair',
              upperBody: 'white shirt',
              lowerBody: 'pleated skirt',
              upperClothing: 'navy blazer',
              lowerClothing: 'black socks',
            ),
          ],
        ),
        source: const StudioAssetCaptureSource(
          surface: 'script',
          label: 'AI role extraction',
          sourceId: 'role-a',
        ),
      );

      final character = draft.character!;
      expect(draft.kind, StudioAssetCaptureKind.character);
      expect(character.name, 'Hero A');
      expect(character.traits.frontFull, 'blue eyes, short hair');
      expect(character.identityTags, ['blue eyes', 'short hair']);
      expect(character.outfits.single.name, 'school');
      expect(character.outfits.single.partTags.upperBodyTags, ['white shirt']);
      expect(
        character.outfits.single.partTags.lowerClothingTags,
        ['black socks'],
      );
      expect(character.defaultOutfitId, character.outfits.single.id);
    });

    test('copyWith keeps UI-safe kind and clears non-outfit parent id', () {
      final characterDraft = StudioAssetCaptureDrafts.characterFromAiRole(
        const ScriptAiExtractedRole(
          sourceRoleId: 'role-a',
          displayName: 'Hero A',
          stages: [
            ScriptAiExtractedStage(
              stageId: 'base',
              label: 'school',
              identity: 'blue eyes',
            ),
          ],
        ),
        source: const StudioAssetCaptureSource(
          surface: 'script',
          label: 'AI role extraction',
          sourceId: 'role-a',
        ),
      );

      final invalidSwitch = characterDraft.copyWith(
        kind: StudioAssetCaptureKind.outfit,
        parentCharacterId: 'character-a',
      );

      expect(invalidSwitch.kind, StudioAssetCaptureKind.character);
      expect(invalidSwitch.character, isNotNull);
      expect(invalidSwitch.outfit, isNull);
      expect(invalidSwitch.parentCharacterId, isNull);

      final outfitDraft = StudioAssetCaptureDraft.outfit(
        outfit: const WorkspaceOutfit(
          id: 'outfit-a',
          name: 'Outfit A',
          tags: ViewVariantTexts(frontFull: 'white shirt'),
        ),
        parentCharacterId: 'character-a',
        source: const StudioAssetCaptureSource(
          surface: 'script',
          label: 'AI role extraction',
        ),
      );

      expect(outfitDraft.copyWith().parentCharacterId, 'character-a');
      expect(
        outfitDraft.copyWith(kind: StudioAssetCaptureKind.character).kind,
        StudioAssetCaptureKind.outfit,
      );
      expect(
        outfitDraft
            .copyWith(kind: StudioAssetCaptureKind.character)
            .parentCharacterId,
        'character-a',
      );
    });

    test(
        'extracts character and artist drafts from structured workbench '
        'document fields', () {
      final document = WorkbenchDocument.fromPayloadJson({
        'prompt_config': {
          'selectionMethod': 'all',
          'shuffled': false,
          'prob': 0.0,
          'num': 1,
          'randomBracketsUpper': 0,
          'randomBracketsLower': 0,
          'type': 'str',
          'comment': 'root',
          'filter': '',
          'strs': ['artist:alpha, watercolor, market street'],
          'prompts': <Object>[],
          'enabled': true,
        },
        'character_config': [
          {
            'name': 'Gallery Girl',
            'positions': <Object>[],
            'positivePromptConfig': {
              'selectionMethod': 'all',
              'shuffled': false,
              'prob': 0.0,
              'num': 1,
              'randomBracketsUpper': 0,
              'randomBracketsLower': 0,
              'type': 'str',
              'comment': 'character',
              'filter': '',
              'strs': ['green eyes, bob cut'],
              'prompts': <Object>[],
              'enabled': true,
            },
            'negativePrompt': '',
            'enabled': true,
          },
        ],
        'saved_config': [
          {
            'selectionMethod': 'all',
            'shuffled': false,
            'prob': 0.0,
            'num': 1,
            'randomBracketsUpper': 0,
            'randomBracketsLower': 0,
            'type': 'str',
            'comment': 'saved',
            'filter': '',
            'strs': ['artist:beta, oil painting, city square'],
            'prompts': <Object>[],
            'enabled': true,
          },
        ],
        'param_config': <String, Object>{},
      });

      final drafts = StudioAssetCaptureDrafts.fromWorkbenchDocument(
        document,
        source: const StudioAssetCaptureSource(
          surface: 'gallery',
          label: 'Gallery item',
          sourceId: 'record-1',
        ),
      );

      expect(drafts.map((draft) => draft.kind), [
        StudioAssetCaptureKind.character,
        StudioAssetCaptureKind.artistChain,
      ]);
      expect(drafts.first.character!.name, 'Gallery Girl');
      expect(drafts.last.artistChain!.tags, ['artist:alpha', 'artist:beta']);
      expect(drafts.last.artistChain!.styleTags, [
        'watercolor',
        'oil painting',
      ]);
      expect(
        drafts.last.artistChain!.prompt,
        'artist:alpha, artist:beta, watercolor, oil painting',
      );
    });

    test('skips malformed workbench entries and keeps valid drafts', () {
      final document = WorkbenchDocument.fromPayloadJson({
        'prompt_config': <String, Object>{
          'selectionMethod': 'all',
        },
        'character_config': [
          {
            'name': 'Broken',
            'positions': 'not-a-list',
            'positivePromptConfig': <String, Object>{},
          },
          {
            'name': 'Valid Girl',
            'positions': <Object>[],
            'positivePromptConfig': {
              'selectionMethod': 'all',
              'shuffled': false,
              'prob': 0.0,
              'num': 1,
              'randomBracketsUpper': 0,
              'randomBracketsLower': 0,
              'type': 'str',
              'comment': 'character',
              'filter': '',
              'strs': ['green eyes'],
              'prompts': <Object>[],
              'enabled': true,
            },
            'negativePrompt': '',
            'enabled': true,
          },
        ],
        'saved_config': [
          <String, Object>{'selectionMethod': 'all'},
          {
            'selectionMethod': 'all',
            'shuffled': false,
            'prob': 0.0,
            'num': 1,
            'randomBracketsUpper': 0,
            'randomBracketsLower': 0,
            'type': 'str',
            'comment': 'saved',
            'filter': '',
            'strs': ['artist:gamma, ink style'],
            'prompts': <Object>[],
            'enabled': true,
          },
        ],
        'param_config': <String, Object>{},
      });

      final drafts = StudioAssetCaptureDrafts.fromWorkbenchDocument(
        document,
        source: const StudioAssetCaptureSource(
          surface: 'gallery',
          label: 'Gallery item',
          sourceId: 'record-3',
        ),
      );

      expect(drafts.map((draft) => draft.kind), [
        StudioAssetCaptureKind.character,
        StudioAssetCaptureKind.artistChain,
      ]);
      expect(drafts.first.character!.name, 'Valid Girl');
      expect(drafts.last.artistChain!.tags, ['artist:gamma']);
      expect(drafts.last.artistChain!.styleTags, ['ink style']);
    });

    test('extracts artist chains from structured v4 prompt parameters', () {
      final document = WorkbenchDocument.fromPayloadJson({
        'param_config': {
          'v4_prompt': {
            'caption': {
              'base_caption': 'artist:alpha, cel shading, rainy street',
              'char_captions': [
                {'char_caption': 'artist:beta, green eyes'},
              ],
            },
          },
        },
        'override_prompt': 'artist:ignored_from_override_only',
      });

      final drafts = StudioAssetCaptureDrafts.fromWorkbenchDocument(
        document,
        source: const StudioAssetCaptureSource(
          surface: 'script_exhibition',
          label: 'Structured script gallery frame',
          sourceId: 'gallery-1',
        ),
      );

      expect(drafts, hasLength(1));
      expect(drafts.single.kind, StudioAssetCaptureKind.artistChain);
      expect(drafts.single.artistChain!.tags, ['artist:alpha', 'artist:beta']);
      expect(drafts.single.artistChain!.styleTags, ['cel shading']);
    });

    test('keeps recast v4 prompt captions as parseable prompt config', () {
      final record = StudioGalleryRecord.fromRecastPayload(
        payload: const {
          'input': 'artist:raw_input_should_not_be_the_capture_source',
          'parameters': {
            'v4_prompt': {
              'caption': {
                'base_caption': 'artist:gamma, oil painting, market',
              },
            },
          },
        },
        id: 'gallery-structured',
        createdAt: DateTime.parse('2026-06-04T12:00:00Z'),
        title: 'Structured script frame',
        imagePath: r'C:\gallery\frame.png',
        info: 'display prompt',
        provenance: _provenance(),
      );

      final drafts = StudioAssetCaptureDrafts.fromWorkbenchDocument(
        record.document,
        source: const StudioAssetCaptureSource(
          surface: 'script_exhibition',
          label: 'Structured script frame',
          sourceId: 'gallery-structured',
        ),
      );

      expect(drafts, hasLength(1));
      expect(drafts.single.artistChain!.tags, ['artist:gamma']);
      expect(drafts.single.artistChain!.styleTags, ['oil painting']);
    });

    test('keeps direct param config v4 prompt captions as capture source', () {
      final document = StudioGalleryRecord.documentFromNaiPayload(
        const {
          'input': 'artist:raw_input_should_still_be_ignored',
          'param_config': {
            'v4_prompt': {
              'caption': {
                'base_caption': 'artist:delta, pencil sketch, train station',
              },
            },
          },
        },
      );

      final drafts = StudioAssetCaptureDrafts.fromWorkbenchDocument(
        document,
        source: const StudioAssetCaptureSource(
          surface: 'script_exhibition',
          label: 'Direct param config frame',
          sourceId: 'production-1',
        ),
      );

      expect(drafts, hasLength(1));
      expect(drafts.single.artistChain!.tags, ['artist:delta']);
      expect(drafts.single.artistChain!.styleTags, ['pencil sketch']);
    });

    test(
        'builds deterministic stable ids from AI roles and workbench documents',
        () {
      const role = ScriptAiExtractedRole(
        sourceRoleId: 'role-a',
        displayName: 'Hero A',
        evidenceTerms: ['blue eyes'],
        stages: [
          ScriptAiExtractedStage(
            stageId: 'base',
            label: 'school',
            identity: 'blue eyes',
            upperClothing: 'navy blazer',
          ),
        ],
      );
      const source = StudioAssetCaptureSource(
        surface: 'script',
        label: 'AI role extraction',
        sourceId: 'role-a',
      );

      final first =
          StudioAssetCaptureDrafts.characterFromAiRole(role, source: source);
      final second =
          StudioAssetCaptureDrafts.characterFromAiRole(role, source: source);
      final changedSource = StudioAssetCaptureDrafts.characterFromAiRole(
        role,
        source: const StudioAssetCaptureSource(
          surface: 'script',
          label: 'AI role extraction',
          sourceId: 'role-b',
        ),
      );
      final changedInput = StudioAssetCaptureDrafts.characterFromAiRole(
        const ScriptAiExtractedRole(
          sourceRoleId: 'role-a',
          displayName: 'Hero A',
          evidenceTerms: ['green eyes'],
          stages: [
            ScriptAiExtractedStage(
              stageId: 'base',
              label: 'school',
              identity: 'green eyes',
              upperClothing: 'navy blazer',
            ),
          ],
        ),
        source: source,
      );

      expect(first.character!.id, second.character!.id);
      expect(changedSource.character!.id, isNot(first.character!.id));
      expect(changedInput.character!.id, isNot(first.character!.id));

      final document = WorkbenchDocument.fromPayloadJson({
        'prompt_config': {
          'selectionMethod': 'all',
          'shuffled': false,
          'prob': 0.0,
          'num': 1,
          'randomBracketsUpper': 0,
          'randomBracketsLower': 0,
          'type': 'str',
          'comment': 'root',
          'filter': '',
          'strs': ['artist:alpha, watercolor'],
          'prompts': <Object>[],
          'enabled': true,
        },
        'character_config': <Object>[],
        'saved_config': <Object>[],
        'param_config': <String, Object>{},
      });
      final workbenchFirst = StudioAssetCaptureDrafts.fromWorkbenchDocument(
        document,
        source: const StudioAssetCaptureSource(
          surface: 'gallery',
          label: 'Gallery item',
          sourceId: 'record-1',
        ),
      );
      final workbenchSecond = StudioAssetCaptureDrafts.fromWorkbenchDocument(
        document,
        source: const StudioAssetCaptureSource(
          surface: 'gallery',
          label: 'Gallery item',
          sourceId: 'record-1',
        ),
      );

      expect(
        workbenchFirst.single.artistChain!.id,
        workbenchSecond.single.artistChain!.id,
      );
    });

    test(
        'ignores override prompt when structured fields do not contain asset data',
        () {
      final document = WorkbenchDocument.fromPayloadJson({
        'prompt_config': {
          'selectionMethod': 'all',
          'shuffled': false,
          'prob': 0.0,
          'num': 1,
          'randomBracketsUpper': 0,
          'randomBracketsLower': 0,
          'type': 'str',
          'comment': 'root',
          'filter': '',
          'strs': <Object>[],
          'prompts': <Object>[],
          'enabled': true,
        },
        'character_config': <Object>[],
        'saved_config': <Object>[],
        'param_config': <String, Object>{},
        'override_prompt': 'artist:only-in-plain-text, city',
      });

      final drafts = StudioAssetCaptureDrafts.fromWorkbenchDocument(
        document,
        source: const StudioAssetCaptureSource(
          surface: 'gallery',
          label: 'Gallery item',
          sourceId: 'record-2',
        ),
      );

      expect(drafts, isEmpty);
    });
  });
}

StudioRecastProvenance _provenance() {
  return const StudioRecastProvenance(
    scriptId: 'script-1',
    scriptName: 'Script',
    scriptPath: r'C:\stories\script',
    recastRunId: 'run-1',
    productionPlanId: 'plan-1',
    productionPlanFingerprint: 'plan-fingerprint',
    taskId: 'task-1',
    frameIndex: 1,
    sourceFileName: '001.json',
    payloadFingerprint: 'payload-fingerprint',
    mappingConfigFingerprint: 'mapping-fingerprint',
    outputImagePath: r'C:\gallery\frame.png',
  );
}
