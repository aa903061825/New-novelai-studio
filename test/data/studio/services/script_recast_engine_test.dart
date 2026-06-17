import 'dart:io';
import 'package:novel_studio/data/studio/tools/prompt_tag_classifier.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/data/studio/models/script_recast.dart';
import 'package:novel_studio/data/studio/services/script_recast_engine.dart';
import 'package:novel_studio/data/studio/services/script_recast_parser_service.dart';
import 'package:novel_studio/data/studio/tools/filter_rule_config.dart';
import 'package:novel_studio/data/workspace/models/workspace_entities.dart';

void main() {
  group('ScriptRecastEngine', () {
    test(
      'role swap replaces character identity while preserving seed and scene',
      () async {
        final script = await _parseFixture();
        final originalSource =
            script.frames.first.parsed.sourcePayload.toString();
        final result = ScriptRecastEngine().resolvePayloads(
          script: script,
          mapping: RecastMapping.defaults(script.id).copyWith(
            roleSwaps: const [
              RoleSwap(sourceRoleId: 'slot-0', targetCharacterId: 'char-x'),
            ],
          ),
          characters: [_newHeroine],
          artistChains: const [],
        );

        final payload = result.frames.first.payload;
        expect(payload['parameters']['seed'], 123456);
        expect(payload.toString(), contains('city lights'));
        expect(payload.toString(), contains('new_heroine'));
        expect(payload.toString(), contains('green eyes'));
        expect(payload.toString(), isNot(contains('fox_tail')));
        expect(
          script.frames.first.parsed.sourcePayload.toString(),
          originalSource,
        );
      },
    );

    test(
      'global prompt prefix is prepended to every frame base caption',
      () async {
        final script = await _parseFixture();
        final result = ScriptRecastEngine().resolvePayloads(
          script: script,
          mapping: RecastMapping.defaults(script.id),
          characters: const [],
          artistChains: const [],
          globalPromptPrefix: 'best quality, detailed lighting',
        );

        expect(result.frames, hasLength(2));
        for (final frame in result.frames) {
          expect(
            _resolvedBaseCaption(
              ScriptRecastResult(
                scriptId: result.scriptId,
                mappingId: result.mappingId,
                frames: [frame],
                configFingerprint: result.configFingerprint,
              ),
            ),
            startsWith('best quality, detailed lighting, '),
          );
        }
      },
    );

    test(
      'artist swap replaces artist and style content from target chain',
      () async {
        final script = await _parseFixture();
        final result = ScriptRecastEngine().resolvePayloads(
          script: script,
          mapping: RecastMapping.defaults(script.id).copyWith(
            artistSwap: const ArtistSwap(targetArtistChainId: 'artist-chain-x'),
          ),
          characters: const [],
          artistChains: const [
            ArtistChain(
              id: 'artist-chain-x',
              name: 'Painter Mix',
              prompt: 'soft watercolor lighting',
              artists: [ArtistEntry(name: 'makoron117117', weight: 0.7)],
              styleHintsWeighted: [
                WorkspaceWeightedTag(tag: 'year 2024', weight: 1.2),
              ],
              globalNegatives: [
                WorkspaceWeightedTag(tag: 'overpainted', weight: -1),
              ],
            ),
          ],
        );

        final payloadText = result.frames.first.payload.toString();
        expect(payloadText, contains('0.7:: artist:makoron117117 ::'));
        expect(payloadText, contains('soft watercolor lighting'));
        expect(payloadText, contains('1.2:: year 2024 ::'));
        expect(payloadText, contains('overpainted'));
        expect(payloadText, isNot(contains('terasu_mc')));
      },
    );

    test(
      'artist swap omits display-only labels from generated prompt',
      () async {
        final script = await _parseFixture();
        final artistLabel = '${_artistChainLabel()} 24';
        final rolePlaceholder = '[${_roleLabel()}A${_upperBodyLabel()}]';
        final result = ScriptRecastEngine().resolvePayloads(
          script: script,
          mapping: RecastMapping.defaults(script.id).copyWith(
            artistSwap: const ArtistSwap(targetArtistChainId: 'artist-chain-x'),
          ),
          characters: const [],
          artistChains: [
            ArtistChain(
              id: 'artist-chain-x',
              name: 'Painter Mix',
              tags: [artistLabel, rolePlaceholder, 'artist:backup_painter'],
              prompt: 'soft watercolor lighting, $artistLabel',
              styleTags: [rolePlaceholder, 'clean lineart'],
              styleHintsWeighted: [
                WorkspaceWeightedTag(tag: artistLabel, weight: 1.2),
                const WorkspaceWeightedTag(tag: 'year 2024', weight: 1.2),
              ],
            ),
          ],
        );

        final payloadText = result.frames.first.payload.toString();
        expect(payloadText, contains('artist:backup_painter'));
        expect(payloadText, contains('soft watercolor lighting'));
        expect(payloadText, contains('clean lineart'));
        expect(payloadText, contains('1.2:: year 2024 ::'));
        expect(payloadText, isNot(contains(artistLabel)));
        expect(payloadText, isNot(contains(rolePlaceholder)));
      },
    );

    test(
      'artist swap removes source artist evidence before adding replacement',
      () {
        final script = _scriptWithBaseCaption(
          '1girl, city_lights, arato_asato, 1.8::ratatatat74::, '
          'artist collaboration, artist:old_painter',
        );
        final result = ScriptRecastEngine().resolvePayloads(
          script: script,
          mapping: RecastMapping.defaults(script.id).copyWith(
            artistSwap: const ArtistSwap(
              targetArtistChainId: 'artist-chain-x',
              sourceArtistPrompt:
                  'arato_asato, ratatatat74, artist collaboration, '
                  'artist:old_painter',
            ),
          ),
          characters: const [],
          artistChains: const [
            ArtistChain(
              id: 'artist-chain-x',
              name: 'Replacement Painter',
              artists: [ArtistEntry(name: 'new_painter', weight: 0.8)],
            ),
          ],
        );

        final baseCaption = _resolvedBaseCaption(result);
        expect(baseCaption, contains('city_lights'));
        expect(baseCaption, contains('0.8:: artist:new_painter ::'));
        expect(baseCaption, isNot(contains('arato_asato')));
        expect(baseCaption, isNot(contains('ratatatat74')));
        expect(baseCaption, isNot(contains('artist collaboration')));
        expect(baseCaption, isNot(contains('old_painter')));
      },
    );

    test(
      'artist swap can delete source artist evidence without replacement',
      () {
        final script = _scriptWithBaseCaption(
          '1girl, city_lights, arato_asato, artist:old_painter',
        );
        final result = ScriptRecastEngine().resolvePayloads(
          script: script,
          mapping: RecastMapping.defaults(script.id).copyWith(
            artistSwap: const ArtistSwap(
              targetArtistChainId: '',
              sourceArtistPrompt: 'arato_asato, artist:old_painter',
              deleteSource: true,
            ),
          ),
          characters: const [],
          artistChains: const [],
        );

        final baseCaption = _resolvedBaseCaption(result);
        expect(baseCaption, contains('1girl'));
        expect(baseCaption, contains('city_lights'));
        expect(baseCaption, isNot(contains('arato_asato')));
        expect(baseCaption, isNot(contains('old_painter')));
      },
    );

    test('prompt block swaps replace style and delete quality terms', () {
      final script = _scriptWithBaseCaption(
        'masterpiece, best quality, official style, city_lights',
      );
      final result = ScriptRecastEngine().resolvePayloads(
        script: script,
        mapping: RecastMapping.defaults(script.id).copyWith(
          promptBlockSwaps: const [
            PromptBlockSwap(
              block: 'style',
              sourcePrompt: 'official style',
              manualPrompt: 'watercolor',
            ),
            PromptBlockSwap(
              block: 'quality',
              sourcePrompt: 'masterpiece, best quality',
              deleteSource: true,
            ),
          ],
        ),
        characters: const [],
        artistChains: const [],
      );

      final baseCaption = _resolvedBaseCaption(result);
      expect(baseCaption, contains('watercolor'));
      expect(baseCaption, contains('city_lights'));
      expect(baseCaption, isNot(contains('official style')));
      expect(baseCaption, isNot(contains('masterpiece')));
      expect(baseCaption, isNot(contains('best quality')));
    });

    test(
      'role prompt replacements mutate only matching character captions',
      () {
        final script = _scriptWithFramePrompts(
          baseCaptions: const ['masterpiece', 'masterpiece'],
          charCaptions: const [
            ['alice, red jacket, black skirt'],
            ['alice, blue coat'],
          ],
        );
        final result = ScriptRecastEngine().resolvePayloads(
          script: script,
          mapping: RecastMapping.defaults(script.id).copyWith(
            rolePromptReplacements: const [
              ScriptRolePromptReplacement(
                sourceRoleId: 'slot-0',
                displayLabel: 'Alice',
                rules: [
                  ScriptPromptReplacementRule(
                    id: 'rule-red-jacket',
                    sourceTerms: [
                      ScriptPromptReplacementTerm(
                        id: 'term-red-jacket',
                        text: 'red jacket',
                        category: PromptTagCategory.clothing,
                        frameIndexes: [1],
                      ),
                    ],
                    targetPrompt: 'white dress',
                  ),
                ],
              ),
            ],
          ),
          characters: const [],
          artistChains: const [],
        );

        final frame1Caption =
            _resolvedCharCaptions(result.frames.first.payload).single;
        final frame2Caption =
            _resolvedCharCaptions(result.frames.last.payload).single;
        expect(frame1Caption, contains('white dress'));
        expect(frame1Caption, isNot(contains('red jacket')));
        expect(frame2Caption, contains('blue coat'));
        expect(frame2Caption, isNot(contains('white dress')));
      },
    );

    test(
      'role prompt replacements follow assembly source appearances',
      () {
        final script = _scriptWithFramePrompts(
          baseCaptions: const ['bedroom', 'bedroom'],
          charCaptions: const [
            ['wakamo_(blue_archive), white tanktop', 'boy, black shirt'],
            ['boy, black shirt', 'wakamo_(blue_archive), white tanktop'],
          ],
        );
        final result = ScriptRecastEngine().resolvePayloads(
          script: script,
          mapping: RecastMapping.defaults(script.id).copyWith(
            roleAssemblies: const [
              RoleAssembly(
                sourceRoleId: 'role-wakamo-blue-archive',
                displayLabel: 'Wakamo',
                sourceAppearances: [
                  RoleAssemblySourceAppearance(
                    sourceId: 'slot-0',
                    sourceKind: 'slot',
                    frameIndexes: [1],
                  ),
                  RoleAssemblySourceAppearance(
                    sourceId: 'slot-1',
                    sourceKind: 'slot',
                    frameIndexes: [2],
                  ),
                ],
                stages: [
                  RoleAssemblyStage(
                    id: 'wakamo-stage',
                    label: 'Default',
                    frameIndexes: [1, 2],
                    sourceParts: RecastPromptParts(
                      identity: 'wakamo_(blue_archive)',
                      upperClothing: 'white tanktop',
                    ),
                  ),
                ],
              ),
            ],
            rolePromptReplacements: const [
              ScriptRolePromptReplacement(
                sourceRoleId: 'role-wakamo-blue-archive',
                displayLabel: 'Wakamo',
                targetIdentityPrompt: 'pepe_(arknights)',
                rules: [
                  ScriptPromptReplacementRule(
                    id: 'rule-wakamo',
                    sourceTerms: [
                      ScriptPromptReplacementTerm(
                        id: 'term-wakamo',
                        text: 'wakamo_(blue_archive)',
                        category: PromptTagCategory.character,
                      ),
                    ],
                  ),
                  ScriptPromptReplacementRule(
                    id: 'rule-tanktop',
                    sourceTerms: [
                      ScriptPromptReplacementTerm(
                        id: 'term-tanktop',
                        text: 'white tanktop',
                        category: PromptTagCategory.clothing,
                      ),
                    ],
                    targetPrompt: 'black jacket',
                  ),
                ],
              ),
            ],
          ),
          characters: const [],
          artistChains: const [],
        );

        final frame1Captions =
            _resolvedCharCaptions(result.frames.first.payload);
        final frame2Captions =
            _resolvedCharCaptions(result.frames.last.payload);
        expect(frame1Captions.first, contains('pepe_(arknights)'));
        expect(frame1Captions.first, contains('black jacket'));
        expect(frame1Captions.first, isNot(contains('wakamo_(blue_archive)')));
        expect(frame1Captions.first, isNot(contains('white tanktop')));
        expect(frame1Captions.last, 'boy, black shirt');
        expect(frame2Captions.first, 'boy, black shirt');
        expect(frame2Captions.last, contains('pepe_(arknights)'));
        expect(frame2Captions.last, contains('black jacket'));
        expect(frame2Captions.last, isNot(contains('wakamo_(blue_archive)')));
        expect(frame2Captions.last, isNot(contains('white tanktop')));
      },
    );

    test('scene prompt replacements mutate base caption separately', () {
      final script = _scriptWithFramePrompts(
        baseCaptions: const [
          'rainy city street, night',
          'warm indoor light',
        ],
      );
      final result = ScriptRecastEngine().resolvePayloads(
        script: script,
        mapping: RecastMapping.defaults(script.id).copyWith(
          scenePromptReplacements: const [
            ScriptScenePromptReplacement(
              id: 'scene-main',
              label: 'Scene',
              rules: [
                ScriptPromptReplacementRule(
                  id: 'rule-night',
                  sourceTerms: [
                    ScriptPromptReplacementTerm(
                      id: 'term-night',
                      text: 'night',
                      category: PromptTagCategory.scene,
                      frameIndexes: [1],
                    ),
                  ],
                  action: ScriptPromptReplacementAction.delete,
                ),
              ],
            ),
          ],
        ),
        characters: const [],
        artistChains: const [],
      );

      expect(
        _resolvedBaseCaption(_resultForFrame(result, result.frames.first)),
        'rainy city street',
      );
      expect(
        _resolvedBaseCaption(_resultForFrame(result, result.frames.last)),
        'warm indoor light',
      );
    });

    test(
      'targetIdentityPrompt applies to role captions without local inference',
      () {
        final script = _scriptWithCharacterCaption(
          'alice, red jacket, 1girl, solo',
        );
        final result = ScriptRecastEngine().resolvePayloads(
          script: script,
          mapping: RecastMapping.defaults(script.id).copyWith(
            rolePromptReplacements: const [
              ScriptRolePromptReplacement(
                sourceRoleId: 'slot-0',
                displayLabel: 'Alice',
                targetIdentityPrompt: 'lily, silver hair',
                rules: [
                  ScriptPromptReplacementRule(
                    id: 'rule-alice',
                    sourceTerms: [
                      ScriptPromptReplacementTerm(
                        id: 'term-alice',
                        text: 'alice',
                        category: PromptTagCategory.character,
                      ),
                    ],
                  ),
                  ScriptPromptReplacementRule(
                    id: 'rule-red-jacket',
                    sourceTerms: [
                      ScriptPromptReplacementTerm(
                        id: 'term-red-jacket',
                        text: 'red jacket',
                        category: PromptTagCategory.clothing,
                      ),
                    ],
                    targetPrompt: 'white dress',
                  ),
                ],
              ),
            ],
          ),
          characters: const [],
          artistChains: const [],
        );

        final charCaption = _resolvedCharCaption(result);
        expect(charCaption, contains('lily'));
        expect(charCaption, contains('silver hair'));
        expect(charCaption, contains('white dress'));
        expect(charCaption, contains('1girl'));
        expect(charCaption, contains('solo'));
        expect(charCaption, isNot(contains('alice')));
        expect(charCaption, isNot(contains('red jacket')));
      },
    );

    test(
      'targetIdentityPrompt is applied after ordinary rules',
      () {
        final script = _scriptWithCharacterCaption('alice, red jacket');
        final result = ScriptRecastEngine().resolvePayloads(
          script: script,
          mapping: RecastMapping.defaults(script.id).copyWith(
            rolePromptReplacements: const [
              ScriptRolePromptReplacement(
                sourceRoleId: 'slot-0',
                displayLabel: 'Alice',
                targetIdentityPrompt: 'lily, red jacket',
                rules: [
                  ScriptPromptReplacementRule(
                    id: 'rule-alice',
                    sourceTerms: [
                      ScriptPromptReplacementTerm(
                        id: 'term-alice',
                        text: 'alice',
                        category: PromptTagCategory.character,
                      ),
                    ],
                  ),
                  ScriptPromptReplacementRule(
                    id: 'rule-red-jacket',
                    sourceTerms: [
                      ScriptPromptReplacementTerm(
                        id: 'term-red-jacket',
                        text: 'red jacket',
                        category: PromptTagCategory.clothing,
                      ),
                    ],
                    targetPrompt: 'white dress',
                  ),
                ],
              ),
            ],
          ),
          characters: const [],
          artistChains: const [],
        );

        final charCaption = _resolvedCharCaption(result);
        expect(charCaption, contains('lily'));
        expect(charCaption, contains('red jacket'));
        expect(charCaption, contains('white dress'));
        expect(charCaption, isNot(contains('alice')));
      },
    );

    test(
      'targetIdentityPrompt appends after all-mode rule removes identity source',
      () {
        final script = _scriptWithCharacterCaption('alice, red jacket');
        final result = ScriptRecastEngine().resolvePayloads(
          script: script,
          mapping: RecastMapping.defaults(script.id).copyWith(
            rolePromptReplacements: const [
              ScriptRolePromptReplacement(
                sourceRoleId: 'slot-0',
                displayLabel: 'Alice',
                targetIdentityPrompt: 'lily',
                rules: [
                  ScriptPromptReplacementRule(
                    id: 'rule-all',
                    sourceTerms: [
                      ScriptPromptReplacementTerm(
                        id: 'term-alice',
                        text: 'alice',
                        category: PromptTagCategory.character,
                      ),
                      ScriptPromptReplacementTerm(
                        id: 'term-red-jacket',
                        text: 'red jacket',
                        category: PromptTagCategory.clothing,
                      ),
                    ],
                    matchMode: ScriptPromptReplacementMatchMode.all,
                    targetPrompt: 'white dress',
                  ),
                ],
              ),
            ],
          ),
          characters: const [],
          artistChains: const [],
        );

        final charCaption = _resolvedCharCaption(result);
        expect(charCaption, contains('lily'));
        expect(charCaption, contains('white dress'));
        expect(charCaption, isNot(contains('alice')));
        expect(charCaption, isNot(contains('red jacket')));
      },
    );

    test('new rolePromptReplacements suppress legacy roleAssemblies path', () {
      final script = _scriptWithCharacterCaption(
        'alice, red jacket, standing',
      );
      final result = ScriptRecastEngine().resolvePayloads(
        script: script,
        mapping: RecastMapping.defaults(script.id).copyWith(
          rolePromptReplacements: const [
            ScriptRolePromptReplacement(
              sourceRoleId: 'slot-0',
              displayLabel: 'Alice',
              rules: [
                ScriptPromptReplacementRule(
                  id: 'rule-red-jacket',
                  sourceTerms: [
                    ScriptPromptReplacementTerm(
                      id: 'term-red-jacket',
                      text: 'red jacket',
                      category: PromptTagCategory.clothing,
                    ),
                  ],
                  targetPrompt: 'white dress',
                ),
              ],
            ),
          ],
          roleAssemblies: const [
            RoleAssembly(
              sourceRoleId: 'slot-0',
              displayLabel: 'Legacy Alice',
              stages: [
                RoleAssemblyStage(
                  id: 'legacy-stage',
                  label: 'Legacy',
                  frameIndexes: [1],
                  sourceParts: RecastPromptParts(
                    identity: 'alice',
                    upperClothing: 'red jacket',
                  ),
                  manualParts: RecastPromptParts(
                    identity: 'legacy_alice',
                    upperClothing: 'legacy outfit',
                  ),
                ),
              ],
            ),
          ],
        ),
        characters: const [],
        artistChains: const [],
      );

      final charCaption = _resolvedCharCaption(result);
      expect(charCaption, contains('alice'));
      expect(charCaption, contains('white dress'));
      expect(charCaption, contains('standing'));
      expect(charCaption, isNot(contains('red jacket')));
      expect(charCaption, isNot(contains('legacy_alice')));
      expect(charCaption, isNot(contains('legacy outfit')));
    });

    test(
      'rolePromptReplacements skip roleAssemblies but preserve other roleSwaps',
      () {
        final script = _scriptWithFramePrompts(
          baseCaptions: const ['masterpiece'],
          charCaptions: const [
            ['alice, red jacket', 'beth, black coat'],
          ],
        );
        final result = ScriptRecastEngine().resolvePayloads(
          script: script,
          mapping: RecastMapping.defaults(script.id).copyWith(
            rolePromptReplacements: const [
              ScriptRolePromptReplacement(
                sourceRoleId: 'slot-0',
                displayLabel: 'Alice',
                rules: [
                  ScriptPromptReplacementRule(
                    id: 'rule-red-jacket',
                    sourceTerms: [
                      ScriptPromptReplacementTerm(
                        id: 'term-red-jacket',
                        text: 'red jacket',
                        category: PromptTagCategory.clothing,
                      ),
                    ],
                    targetPrompt: 'white dress',
                  ),
                ],
              ),
            ],
            roleAssemblies: const [
              RoleAssembly(
                sourceRoleId: 'slot-0',
                displayLabel: 'Legacy Alice',
                stages: [
                  RoleAssemblyStage(
                    id: 'legacy-stage',
                    label: 'Legacy',
                    frameIndexes: [1],
                    sourceParts: RecastPromptParts(
                      identity: 'alice',
                      upperClothing: 'red jacket',
                    ),
                    manualParts: RecastPromptParts(
                      identity: 'legacy_alice',
                      upperClothing: 'legacy outfit',
                    ),
                  ),
                ],
              ),
            ],
            roleSwaps: const [
              RoleSwap(sourceRoleId: 'slot-1', targetCharacterId: 'char-x'),
            ],
          ),
          characters: [_newHeroine],
          artistChains: const [],
        );

        final charCaptions =
            _resolvedCharCaptions(result.frames.single.payload);
        expect(charCaptions.first, contains('alice'));
        expect(charCaptions.first, contains('white dress'));
        expect(charCaptions.first, isNot(contains('legacy_alice')));
        expect(charCaptions.first, isNot(contains('legacy outfit')));
        expect(charCaptions.last, contains('new_heroine'));
        expect(charCaptions.last, contains('green eyes'));
        expect(charCaptions.last, isNot(contains('beth')));
        expect(charCaptions.last, isNot(contains('black coat')));
      },
    );

    test(
      'artist swap keeps bound vibe references as source-only candidates',
      () async {
        final script = await _parseFixture();
        final result = ScriptRecastEngine().resolvePayloads(
          script: script,
          mapping: RecastMapping.defaults(script.id).copyWith(
            artistSwap: const ArtistSwap(targetArtistChainId: 'artist-chain-x'),
          ),
          characters: const [],
          artistChains: const [
            ArtistChain(
              id: 'artist-chain-x',
              name: 'Painter Mix',
              prompt: 'soft watercolor lighting',
              vibeRefs: [
                WorkspaceVibeReference(
                  id: 'qaq-2',
                  name: 'QAQ 2',
                  vibeB64: 'encoded-bound-vibe',
                  referenceStrength: 0.4,
                ),
              ],
            ),
          ],
        );

        final parameters = (result.frames.first.payload['parameters'] as Map)
            .cast<String, dynamic>();
        expect(parameters.containsKey('reference_image_multiple'), isFalse);
        expect(parameters.containsKey('reference_strength_multiple'), isFalse);
        expect(
          parameters.containsKey('reference_information_extracted_multiple'),
          isFalse,
        );
      },
    );

    test('manual mapping vibes are the only activated script vibes', () async {
      final script = await _parseFixture();
      final result = ScriptRecastEngine().resolvePayloads(
        script: script,
        mapping: RecastMapping.defaults(script.id).copyWith(
          artistSwap: const ArtistSwap(targetArtistChainId: 'artist-chain-x'),
          manualVibeRefs: const [
            WorkspaceVibeReference(
              id: 'manual-vibe',
              name: 'Manual Vibe',
              vibeB64: 'encoded-manual-vibe',
              referenceStrength: 0.5,
            ),
          ],
        ),
        characters: const [],
        artistChains: const [
          ArtistChain(
            id: 'artist-chain-x',
            name: 'Painter Mix',
            prompt: 'soft watercolor lighting',
            vibeRefs: [
              WorkspaceVibeReference(
                id: 'bound-vibe',
                name: 'Bound Vibe',
                vibeB64: 'encoded-bound-vibe',
                referenceStrength: 0.4,
              ),
            ],
          ),
        ],
      );

      final parameters = (result.frames.first.payload['parameters'] as Map)
          .cast<String, dynamic>();
      expect(parameters['reference_image_multiple'], ['encoded-manual-vibe']);
      expect(parameters['reference_strength_multiple'], [0.5]);
      expect(parameters['reference_information_extracted_multiple'], [1.0]);
    });

    test(
      'manual vibe strength wins when source candidate shares encoding',
      () async {
        final script = await _parseFixture();
        final result = ScriptRecastEngine().resolvePayloads(
          script: script,
          mapping: RecastMapping.defaults(script.id).copyWith(
            artistSwap: const ArtistSwap(targetArtistChainId: 'artist-chain-x'),
            manualVibeRefs: const [
              WorkspaceVibeReference(
                id: 'manual-vibe',
                name: 'Manual Vibe',
                vibeB64: 'encoded-shared-vibe',
                referenceStrength: 0.8,
              ),
            ],
          ),
          characters: const [],
          artistChains: const [
            ArtistChain(
              id: 'artist-chain-x',
              name: 'Painter Mix',
              prompt: 'soft watercolor lighting',
              vibeRefs: [
                WorkspaceVibeReference(
                  id: 'bound-vibe',
                  name: 'Bound Vibe',
                  vibeB64: 'encoded-shared-vibe',
                  referenceStrength: 0.4,
                ),
              ],
            ),
          ],
        );

        final parameters = (result.frames.first.payload['parameters'] as Map)
            .cast<String, dynamic>();
        expect(parameters['reference_image_multiple'], ['encoded-shared-vibe']);
        expect(parameters['reference_strength_multiple'], [0.8]);
        expect(parameters['reference_information_extracted_multiple'], [1.0]);
      },
    );

    test('role swap can apply selected outfit stage tags', () async {
      final script = await _parseFixture();
      final result = ScriptRecastEngine().resolvePayloads(
        script: script,
        mapping: RecastMapping.defaults(script.id).copyWith(
          roleSwaps: const [
            RoleSwap(
              sourceRoleId: 'slot-0',
              targetCharacterId: 'char-outfit',
              targetOutfitId: 'stage-dress',
            ),
          ],
        ),
        characters: const [_outfitHeroine],
        artistChains: const [],
      );

      final comment = result.frames.first.payload['Comment'] as Map;
      final prompt = comment['v4_prompt'] as Map;
      final caption = prompt['caption'] as Map;
      final charCaptions = caption['char_captions'] as List;
      final firstChar = charCaptions.first as Map;
      final charCaption = firstChar['char_caption'] as String;
      expect(charCaption, contains('stage_heroine'));
      expect(charCaption, contains('black dress'));
      expect(charCaption, contains('lace blouse'));
      expect(charCaption, contains('pleated skirt'));
      expect(charCaption, isNot(contains('fox_tail')));
    });

    test('role swap emits target tags without source heuristic tail', () {
      final script = _scriptWithCharacterCaption(
        'official style, shirogane noel (1st costume), hololive, dress, '
        'belt, armor, skirt, thighhighs, battle pose, nose blush',
      );
      final result = ScriptRecastEngine().resolvePayloads(
        script: script,
        mapping: RecastMapping.defaults(script.id).copyWith(
          roleSwaps: const [
            RoleSwap(
              sourceRoleId: 'slot-0',
              targetCharacterId: 'char-eyja',
              targetOutfitId: 'summer',
            ),
          ],
        ),
        characters: const [_duplicatedEyja],
        artistChains: const [],
      );

      final charCaption = _resolvedCharCaption(result);
      expect(_tagOccurrences(charCaption, 'eyjafjalla_(arknights)'), 1);
      expect(
        _tagOccurrences(charCaption, 'eyjafjalla_(summer_flower)_(arknights)'),
        0,
      );
      expect(_tagOccurrences(charCaption, 'bikini'), 1);
      expect(charCaption, isNot(contains('battle pose')));
      expect(charCaption, isNot(contains('nose blush')));
      expect(charCaption, isNot(contains('shirogane noel')));
      expect(charCaption, isNot(contains('hololive')));
      expect(charCaption, isNot(contains('dress')));
      expect(charCaption, isNot(contains('belt')));
      expect(charCaption, isNot(contains('thighhighs')));
    });

    test(
      'role assembly composes character outfit parts and manual edits per stage',
      () {
        final script = _scriptWithCharacterCaption(
          'source heroine, old dress, standing, nose blush',
        );
        final result = ScriptRecastEngine().resolvePayloads(
          script: script,
          mapping: RecastMapping.defaults(script.id).copyWith(
            roleAssemblies: const [
              RoleAssembly(
                sourceRoleId: 'slot-0',
                displayLabel: '角色 1',
                sourceName: 'source heroine',
                stages: [
                  RoleAssemblyStage(
                    id: 'slot-0-stage-1',
                    label: '服装 1',
                    frameIndexes: [1],
                    targetCharacterId: 'char-assembly',
                    targetUpperOutfitId: 'upper-stage',
                    targetLowerOutfitId: 'lower-stage',
                    sourceParts: RecastPromptParts(
                      identity: 'source heroine',
                      upperClothing: 'old dress',
                    ),
                    manualParts: RecastPromptParts(
                      upperBody: 'manual animal ears',
                      lowerClothing: 'manual boots',
                    ),
                  ),
                ],
              ),
            ],
          ),
          characters: const [_assemblyHeroine],
          artistChains: const [],
        );

        final charCaption = _resolvedCharCaption(result);
        expect(charCaption, contains('assembly_heroine'));
        expect(charCaption, contains('blue eyes'));
        expect(charCaption, contains('manual animal ears'));
        expect(charCaption, contains('white blouse'));
        expect(charCaption, contains('bare legs'));
        expect(charCaption, contains('manual boots'));
        expect(charCaption, contains('standing'));
        expect(charCaption, contains('nose blush'));
        expect(charCaption, isNot(contains('old dress')));
      },
    );

    test('role assembly keeps source tags not listed in source parts', () {
      final script = _scriptWithCharacterCaption(
        'source heroine, old dress, standing',
      );
      final result = ScriptRecastEngine().resolvePayloads(
        script: script,
        mapping: RecastMapping.defaults(script.id).copyWith(
          roleAssemblies: const [
            RoleAssembly(
              sourceRoleId: 'slot-0',
              displayLabel: 'Role 1',
              sourceName: 'source heroine',
              stages: [
                RoleAssemblyStage(
                  id: 'slot-0-stage-1',
                  label: 'Outfit 1',
                  frameIndexes: [1],
                  targetCharacterId: 'char-assembly',
                  targetUpperOutfitId: 'upper-stage',
                  targetLowerOutfitId: 'lower-stage',
                  sourceParts: RecastPromptParts(identity: 'source heroine'),
                ),
              ],
            ),
          ],
        ),
        characters: const [_assemblyHeroine],
        artistChains: const [],
      );

      final charCaption = _resolvedCharCaption(result);
      expect(charCaption, contains('assembly_heroine'));
      expect(charCaption, contains('old dress'));
      expect(charCaption, contains('standing'));
      expect(charCaption, isNot(contains('source heroine')));
    });

    test(
      'role assembly can replace clothing while preserving source identity',
      () {
        final script = _scriptWithCharacterCaption(
          'source heroine, old dress, standing',
        );
        final result = ScriptRecastEngine().resolvePayloads(
          script: script,
          mapping: RecastMapping.defaults(script.id).copyWith(
            roleAssemblies: const [
              RoleAssembly(
                sourceRoleId: 'slot-0',
                displayLabel: 'Role 1',
                sourceName: 'source heroine',
                stages: [
                  RoleAssemblyStage(
                    id: 'slot-0-stage-1',
                    label: 'Outfit 1',
                    frameIndexes: [1],
                    sourceParts: RecastPromptParts(
                      identity: 'source heroine',
                      upperClothing: 'old dress',
                    ),
                    manualParts: RecastPromptParts(upperClothing: 'new dress'),
                  ),
                ],
              ),
            ],
          ),
          characters: const [],
          artistChains: const [],
        );

        final charCaption = _resolvedCharCaption(result);
        expect(charCaption, contains('source heroine'));
        expect(charCaption, contains('new dress'));
        expect(charCaption, contains('standing'));
        expect(charCaption, isNot(contains('old dress')));
      },
    );

    test('empty role assembly target part keeps its source block', () {
      final script = _scriptWithCharacterCaption(
        'source heroine, blue hair, old dress, standing',
      );
      final result = ScriptRecastEngine().resolvePayloads(
        script: script,
        mapping: RecastMapping.defaults(script.id).copyWith(
          roleAssemblies: const [
            RoleAssembly(
              sourceRoleId: 'slot-0',
              displayLabel: 'Role 1',
              sourceName: 'source heroine',
              stages: [
                RoleAssemblyStage(
                  id: 'slot-0-stage-1',
                  label: 'Outfit 1',
                  frameIndexes: [1],
                  targetCharacterId: 'char-assembly',
                  targetUpperOutfitId: 'upper-stage',
                  targetLowerOutfitId: 'lower-stage',
                  sourceParts: RecastPromptParts(
                    identity: 'source heroine',
                    upperBody: 'blue hair',
                    upperClothing: 'old dress',
                  ),
                  preservedParts: {
                    RecastPromptPart.identity,
                    RecastPromptPart.upperBody,
                  },
                  manualParts: RecastPromptParts(upperClothing: 'new dress'),
                ),
              ],
            ),
          ],
        ),
        characters: const [_assemblyHeroine],
        artistChains: const [],
      );

      final charCaption = _resolvedCharCaption(result);
      expect(charCaption, contains('source heroine'));
      expect(charCaption, contains('blue hair'));
      expect(charCaption, contains('new dress'));
      expect(charCaption, contains('standing'));
      expect(charCaption, isNot(contains('assembly_heroine')));
      expect(charCaption, isNot(contains('old dress')));
    });

    test(
      'role assembly does not remove source identity hidden outside source parts',
      () {
        final script = _scriptWithCharacterCaption(
          'girl, himekawa yoshino (date a live), small breasts, white dress, '
          'lying, fingering',
        );
        final result = ScriptRecastEngine().resolvePayloads(
          script: script,
          mapping: RecastMapping.defaults(script.id).copyWith(
            roleAssemblies: const [
              RoleAssembly(
                sourceRoleId: 'slot-0',
                displayLabel: 'Role 1',
                sourceName: 'himekawa yoshino (date a live)',
                stages: [
                  RoleAssemblyStage(
                    id: 'slot-0-stage-1',
                    label: 'Outfit 1',
                    frameIndexes: [1],
                    targetCharacterId: 'char-assembly',
                    sourceParts: RecastPromptParts(
                      upperClothing: 'white dress',
                    ),
                    manualParts: RecastPromptParts(
                      identity: 'pepe_(arknights)',
                      upperBody: 'long_hair',
                    ),
                  ),
                ],
              ),
            ],
          ),
          characters: const [_assemblyHeroine],
          artistChains: const [],
        );

        final charCaption = _resolvedCharCaption(result);
        expect(charCaption, contains('pepe_(arknights)'));
        expect(charCaption, contains('long_hair'));
        expect(charCaption, contains('himekawa yoshino (date a live)'));
        expect(charCaption, contains('lying'));
        expect(charCaption, contains('fingering'));
        expect(charCaption, isNot(contains('white dress')));
      },
    );

    test(
      'role assembly removes source identity when visible source part is replaced',
      () {
        final script = _scriptWithCharacterCaption(
          'girl, himekawa yoshino (date a live), small breasts, white dress, '
          'lying, fingering',
        );
        final result = ScriptRecastEngine().resolvePayloads(
          script: script,
          mapping: RecastMapping.defaults(script.id).copyWith(
            roleAssemblies: const [
              RoleAssembly(
                sourceRoleId: 'slot-0',
                displayLabel: 'Role 1',
                sourceName: 'himekawa yoshino (date a live)',
                stages: [
                  RoleAssemblyStage(
                    id: 'slot-0-stage-1',
                    label: 'Outfit 1',
                    frameIndexes: [1],
                    targetCharacterId: 'char-assembly',
                    sourceParts: RecastPromptParts(
                      identity: 'himekawa yoshino (date a live)',
                      upperClothing: 'white dress',
                    ),
                    manualParts: RecastPromptParts(
                      identity: 'pepe_(arknights)',
                      upperBody: 'long_hair',
                    ),
                  ),
                ],
              ),
            ],
          ),
          characters: const [_assemblyHeroine],
          artistChains: const [],
        );

        final charCaption = _resolvedCharCaption(result);
        expect(charCaption, contains('pepe_(arknights)'));
        expect(charCaption, contains('long_hair'));
        expect(charCaption, contains('lying'));
        expect(charCaption, contains('fingering'));
        expect(charCaption, isNot(contains('himekawa yoshino')));
        expect(charCaption, isNot(contains('date a live')));
        expect(charCaption, isNot(contains('white dress')));
      },
    );

    test(
      'role assembly keeps one target copy when source and target share tag',
      () {
        final script = _scriptWithCharacterCaption(
          'source heroine, white pantyhose, standing',
        );
        final result = ScriptRecastEngine().resolvePayloads(
          script: script,
          mapping: RecastMapping.defaults(script.id).copyWith(
            roleAssemblies: const [
              RoleAssembly(
                sourceRoleId: 'slot-0',
                displayLabel: 'Role 1',
                sourceName: 'source heroine',
                stages: [
                  RoleAssemblyStage(
                    id: 'slot-0-stage-1',
                    label: 'Outfit 1',
                    frameIndexes: [1],
                    targetCharacterId: 'char-assembly',
                    sourceParts: RecastPromptParts(
                      identity: 'source heroine',
                      lowerClothing: 'white pantyhose',
                    ),
                    manualParts: RecastPromptParts(
                      lowerClothing: 'white pantyhose',
                    ),
                  ),
                ],
              ),
            ],
          ),
          characters: const [_assemblyHeroine],
          artistChains: const [],
        );

        final charCaption = _resolvedCharCaption(result);
        expect(_tagOccurrences(charCaption, 'white pantyhose'), 1);
        expect(charCaption, contains('standing'));
        expect(charCaption, isNot(contains('source heroine')));
      },
    );

    test(
      'role assembly omits undetected upper clothing instead of inheriting target outfit',
      () {
        final script = _scriptWithCharacterCaption(
          'source heroine, pleated skirt, standing',
        );
        final result = ScriptRecastEngine().resolvePayloads(
          script: script,
          mapping: RecastMapping.defaults(script.id).copyWith(
            roleAssemblies: const [
              RoleAssembly(
                sourceRoleId: 'slot-0',
                displayLabel: 'Role 1',
                sourceName: 'source heroine',
                stages: [
                  RoleAssemblyStage(
                    id: 'slot-0-stage-1',
                    label: 'Outfit 1',
                    frameIndexes: [1],
                    targetCharacterId: 'char-assembly',
                    targetUpperOutfitId: 'upper-stage',
                    targetLowerOutfitId: 'lower-stage',
                    sourceParts: RecastPromptParts(
                      identity: 'source heroine',
                      lowerClothing: 'pleated skirt',
                    ),
                    omittedParts: {RecastPromptPart.upperClothing},
                    manualParts: RecastPromptParts(
                      lowerClothing: 'manual skirt',
                    ),
                  ),
                ],
              ),
            ],
          ),
          characters: const [_assemblyHeroine],
          artistChains: const [],
        );

        final charCaption = _resolvedCharCaption(result);
        expect(charCaption, contains('assembly_heroine'));
        expect(charCaption, contains('manual skirt'));
        expect(charCaption, contains('standing'));
        expect(charCaption, isNot(contains('white blouse')));
      },
    );

    test(
      'role assembly leaves missing identity blank for split characters without explicit identity tags',
      () {
        final script = _scriptWithCharacterCaption(
          'source heroine, old dress, standing',
        );
        final result = ScriptRecastEngine().resolvePayloads(
          script: script,
          mapping: RecastMapping.defaults(script.id).copyWith(
            roleAssemblies: const [
              RoleAssembly(
                sourceRoleId: 'slot-0',
                displayLabel: 'Role 1',
                sourceName: 'source heroine',
                stages: [
                  RoleAssemblyStage(
                    id: 'slot-0-stage-1',
                    label: 'Outfit 1',
                    frameIndexes: [1],
                    targetCharacterId: 'split-pepe',
                    targetUpperOutfitId: 'variant-1',
                    targetLowerOutfitId: 'variant-1',
                    sourceParts: RecastPromptParts(
                      identity: 'source heroine',
                      upperClothing: 'old dress',
                    ),
                  ),
                ],
              ),
            ],
          ),
          characters: const [_splitPepe],
          artistChains: const [],
        );

        final charCaption = _resolvedCharCaption(result);
        expect(charCaption, isNot(contains('pepe_(arknights)')));
        expect(charCaption, contains('cat ears'));
        expect(charCaption, contains('cat tail'));
        expect(charCaption, contains('ancient egyptian clothes'));
        expect(charCaption, contains('black shorts'));
        expect(charCaption, isNot(contains('source heroine')));
        expect(charCaption, isNot(contains('old dress')));
        expect(charCaption, isNot(contains('animal ear hood')));
        expect(charCaption, isNot(contains('black jacket')));
      },
    );

    test(
      'role assembly applies selected outfit skin identity from frontFull',
      () {
        final script = _scriptWithCharacterCaption(
          'source heroine, old dress, standing',
        );
        final result = ScriptRecastEngine().resolvePayloads(
          script: script,
          mapping: RecastMapping.defaults(script.id).copyWith(
            roleAssemblies: const [
              RoleAssembly(
                sourceRoleId: 'slot-0',
                displayLabel: 'Role 1',
                sourceName: 'source heroine',
                stages: [
                  RoleAssemblyStage(
                    id: 'slot-0-stage-1',
                    label: 'Outfit 1',
                    frameIndexes: [1],
                    targetCharacterId: 'skin-pepe',
                    targetUpperOutfitId: 'nuit',
                    targetLowerOutfitId: 'nuit',
                    sourceParts: RecastPromptParts(
                      identity: 'source heroine',
                      upperClothing: 'old dress',
                    ),
                    manualParts: RecastPromptParts(
                      identity: 'pepe_(arknights)',
                    ),
                  ),
                ],
              ),
            ],
          ),
          characters: const [_skinPepe],
          artistChains: const [],
        );

        final charCaption = _resolvedCharCaption(result);
        expect(charCaption, contains('pepe_(arknights)'));
        expect(
          charCaption,
          contains('pepe_(nuit_of_the_nightsky)_(arknights)'),
        );
        expect(charCaption, contains('cat ears'));
        expect(charCaption, contains('cat tail'));
        expect(charCaption, contains('white dress'));
        expect(charCaption, contains('purple skirt'));
        expect(charCaption, isNot(contains('source heroine')));
        expect(charCaption, isNot(contains('old dress')));
        expect(charCaption, isNot(contains('animal ear hood')));
      },
    );

    test('role assembly filters contaminated character skin anchors', () {
      final script = _scriptWithCharacterCaption(
        'source heroine, old dress, standing',
      );
      final result = ScriptRecastEngine().resolvePayloads(
        script: script,
        mapping: RecastMapping.defaults(script.id).copyWith(
          roleAssemblies: const [
            RoleAssembly(
              sourceRoleId: 'slot-0',
              displayLabel: 'Role 1',
              sourceName: 'source heroine',
              stages: [
                RoleAssemblyStage(
                  id: 'slot-0-stage-1',
                  label: 'Outfit 1',
                  frameIndexes: [1],
                  targetCharacterId: 'contaminated-skin-pepe',
                  targetUpperOutfitId: 'default',
                  targetLowerOutfitId: 'default',
                  sourceParts: RecastPromptParts(
                    identity: 'source heroine',
                    upperClothing: 'old dress',
                  ),
                ),
              ],
            ),
          ],
        ),
        characters: const [_contaminatedSkinPepe],
        artistChains: const [],
      );

      final charCaption = _resolvedCharCaption(result);
      expect(charCaption, contains('pepe_(arknights)'));
      expect(
        charCaption,
        isNot(contains('pepe_(nuit_of_the_nightsky)_(arknights)')),
      );
      expect(charCaption, contains('cat ears'));
      expect(charCaption, contains('cat tail'));
      expect(charCaption, contains('animal ear hood'));
      expect(charCaption, contains('black jacket'));
      expect(charCaption, isNot(contains('source heroine')));
      expect(charCaption, isNot(contains('old dress')));
    });

    test(
      'role assembly does not use outfit frontFull as split clothing fields',
      () {
        final script = _scriptWithCharacterCaption(
          'source heroine, old dress, standing',
        );
        final result = ScriptRecastEngine().resolvePayloads(
          script: script,
          mapping: RecastMapping.defaults(script.id).copyWith(
            roleAssemblies: const [
              RoleAssembly(
                sourceRoleId: 'slot-0',
                displayLabel: 'Role 1',
                sourceName: 'source heroine',
                stages: [
                  RoleAssemblyStage(
                    id: 'slot-0-stage-1',
                    label: 'Outfit 1',
                    frameIndexes: [1],
                    targetCharacterId: 'skin-pepe-frontfull-only',
                    targetUpperOutfitId: 'nuit-frontfull-only',
                    targetLowerOutfitId: 'nuit-frontfull-only',
                    sourceParts: RecastPromptParts(
                      identity: 'source heroine',
                      upperClothing: 'old dress',
                    ),
                    manualParts: RecastPromptParts(
                      identity: 'pepe_(arknights)',
                    ),
                  ),
                ],
              ),
            ],
          ),
          characters: const [_skinPepeFrontFullOnly],
          artistChains: const [],
        );

        final charCaption = _resolvedCharCaption(result);
        expect(charCaption, contains('pepe_(arknights)'));
        expect(
          charCaption,
          contains('pepe_(nuit_of_the_nightsky)_(arknights)'),
        );
        expect(charCaption, isNot(contains('white dress')));
        expect(charCaption, isNot(contains('purple skirt')));
        expect(charCaption, contains('cat ears'));
        expect(charCaption, contains('cat tail'));
        expect(charCaption, contains('standing'));
        expect(charCaption, isNot(contains('source heroine')));
        expect(charCaption, isNot(contains('old dress')));
      },
    );

    test('role assembly keeps identity repeated in outfit full prompt', () {
      final script = _scriptWithCharacterCaption(
        'source heroine, old dress, standing',
      );
      final result = ScriptRecastEngine().resolvePayloads(
        script: script,
        mapping: RecastMapping.defaults(script.id).copyWith(
          roleAssemblies: const [
            RoleAssembly(
              sourceRoleId: 'slot-0',
              displayLabel: 'Role 1',
              sourceName: 'source heroine',
              stages: [
                RoleAssemblyStage(
                  id: 'slot-0-stage-1',
                  label: 'Outfit 1',
                  frameIndexes: [1],
                  targetCharacterId: 'split-papyrus',
                  targetUpperOutfitId: 'pink',
                  targetLowerOutfitId: 'pink',
                  sourceParts: RecastPromptParts(
                    identity: 'source heroine',
                    upperClothing: 'old dress',
                  ),
                ),
              ],
            ),
          ],
        ),
        characters: const [_splitPapyrus],
        artistChains: const [],
      );

      final charCaption = _resolvedCharCaption(result);
      expect(charCaption, contains('papyrus_(arknights)'));
      expect(charCaption, contains('green eyes'));
      expect(charCaption, contains('tail ornament'));
      expect(charCaption, contains('pink pajamas'));
      expect(charCaption, isNot(contains('source heroine')));
      expect(charCaption, isNot(contains('old dress')));
    });

    test(
      'manual value enables an omitted upper clothing row for generation',
      () {
        final script = _scriptWithCharacterCaption(
          'source heroine, pleated skirt, standing',
        );
        final result = ScriptRecastEngine().resolvePayloads(
          script: script,
          mapping: RecastMapping.defaults(script.id).copyWith(
            roleAssemblies: const [
              RoleAssembly(
                sourceRoleId: 'slot-0',
                displayLabel: 'Role 1',
                sourceName: 'source heroine',
                stages: [
                  RoleAssemblyStage(
                    id: 'slot-0-stage-1',
                    label: 'Outfit 1',
                    frameIndexes: [1],
                    targetCharacterId: 'char-assembly',
                    targetUpperOutfitId: 'upper-stage',
                    targetLowerOutfitId: 'lower-stage',
                    sourceParts: RecastPromptParts(
                      identity: 'source heroine',
                      lowerClothing: 'pleated skirt',
                    ),
                    omittedParts: {RecastPromptPart.upperClothing},
                    manualParts: RecastPromptParts(
                      upperClothing: 'manual blouse',
                      lowerClothing: 'manual skirt',
                    ),
                  ),
                ],
              ),
            ],
          ),
          characters: const [_assemblyHeroine],
          artistChains: const [],
        );

        final charCaption = _resolvedCharCaption(result);
        expect(charCaption, contains('manual blouse'));
        expect(charCaption, isNot(contains('white blouse')));
      },
    );

    test(
      'role assembly removes edited source part evidence including generic identity',
      () {
        final script = _scriptWithCharacterCaption(
          'kamisato ayaka, girl, blue hair, white collar, standing, '
          'source birthmark, looking at viewer',
        );
        final result = ScriptRecastEngine().resolvePayloads(
          script: script,
          mapping: RecastMapping.defaults(script.id).copyWith(
            roleAssemblies: const [
              RoleAssembly(
                sourceRoleId: 'slot-0',
                displayLabel: 'Role 1',
                sourceName: 'kamisato ayaka',
                stages: [
                  RoleAssemblyStage(
                    id: 'slot-0-stage-1',
                    label: 'Outfit 1',
                    frameIndexes: [1],
                    targetCharacterId: 'char-assembly',
                    targetUpperOutfitId: 'upper-stage',
                    targetLowerOutfitId: 'lower-stage',
                    sourceParts: RecastPromptParts(
                      identity: 'kamisato ayaka, girl',
                      upperBody: 'blue hair, white collar, source birthmark',
                    ),
                    manualParts: RecastPromptParts(
                      identity: 'pepe_(arknights), animal_ears',
                      upperBody: 'long_hair',
                      lowerBody: 'cat_tail',
                      lowerClothing: 'white pantyhose',
                    ),
                  ),
                ],
              ),
            ],
          ),
          characters: const [_assemblyHeroine],
          artistChains: const [],
        );

        final charCaption = _resolvedCharCaption(result);
        expect(charCaption, contains('pepe_(arknights)'));
        expect(charCaption, contains('animal_ears'));
        expect(charCaption, contains('long_hair'));
        expect(charCaption, contains('cat_tail'));
        expect(charCaption, contains('white pantyhose'));
        expect(charCaption, contains('standing'));
        expect(charCaption, contains('looking at viewer'));
        expect(charCaption, isNot(contains('kamisato ayaka')));
        expect(charCaption, isNot(contains('girl')));
        expect(charCaption, isNot(contains('blue hair')));
        expect(charCaption, isNot(contains('white collar')));
        expect(charCaption, isNot(contains('source birthmark')));
      },
    );

    test('role assembly omitted identity and body fields do not fall back', () {
      final script = _scriptWithCharacterCaption('source heroine, standing');
      final result = ScriptRecastEngine().resolvePayloads(
        script: script,
        mapping: RecastMapping.defaults(script.id).copyWith(
          roleAssemblies: const [
            RoleAssembly(
              sourceRoleId: 'slot-0',
              displayLabel: 'Role 1',
              sourceName: 'source heroine',
              stages: [
                RoleAssemblyStage(
                  id: 'slot-0-stage-1',
                  label: 'Outfit 1',
                  frameIndexes: [1],
                  targetCharacterId: 'char-assembly',
                  targetUpperOutfitId: 'upper-stage',
                  targetLowerOutfitId: 'lower-stage',
                  sourceParts: RecastPromptParts(identity: 'source heroine'),
                  omittedParts: {
                    RecastPromptPart.identity,
                    RecastPromptPart.upperBody,
                    RecastPromptPart.lowerBody,
                    RecastPromptPart.upperClothing,
                  },
                ),
              ],
            ),
          ],
        ),
        characters: const [_assemblyHeroine],
        artistChains: const [],
      );

      final charCaption = _resolvedCharCaption(result);
      expect(charCaption, contains('black boots'));
      expect(charCaption, contains('standing'));
      expect(charCaption, isNot(contains('assembly_heroine')));
      expect(charCaption, isNot(contains('blue eyes')));
      expect(charCaption, isNot(contains('bare legs')));
      expect(charCaption, isNot(contains('white blouse')));
    });

    test(
      'role assembly does not use first explicit stage for unmatched frame',
      () {
        final script = _scriptWithCharacterCaption(
          'source heroine, old dress, standing',
          frameIndex: 2,
        );
        final result = ScriptRecastEngine().resolvePayloads(
          script: script,
          mapping: RecastMapping.defaults(script.id).copyWith(
            roleAssemblies: const [
              RoleAssembly(
                sourceRoleId: 'slot-0',
                displayLabel: 'Role 1',
                sourceName: 'source heroine',
                stages: [
                  RoleAssemblyStage(
                    id: 'slot-0-stage-1',
                    label: 'Outfit 1',
                    frameIndexes: [1],
                    targetCharacterId: 'char-assembly',
                    targetUpperOutfitId: 'upper-stage',
                    targetLowerOutfitId: 'lower-stage',
                  ),
                ],
              ),
            ],
          ),
          characters: const [_assemblyHeroine],
          artistChains: const [],
        );

        expect(
          _resolvedCharCaption(result),
          'source heroine, old dress, standing',
        );
      },
    );

    test('same script and mapping resolve to the same fingerprints', () async {
      final script = await _parseFixture();
      final engine = ScriptRecastEngine();
      final mapping = RecastMapping.defaults(script.id).copyWith(
        roleSwaps: const [
          RoleSwap(sourceRoleId: 'slot-0', targetCharacterId: 'char-x'),
        ],
      );

      final first = engine.resolvePayloads(
        script: script,
        mapping: mapping,
        characters: [_newHeroine],
        artistChains: const [],
      );
      final second = engine.resolvePayloads(
        script: script,
        mapping: mapping,
        characters: [_newHeroine],
        artistChains: const [],
      );

      expect(first.toJson(), second.toJson());
      expect(
        first.frames.map((frame) => frame.payloadFingerprint).toSet(),
        hasLength(2),
      );
    });

    test(
      'role assembly appearances can replace a role across moving slots',
      () {
        final script = _scriptWithMovingSlots();
        final mapping = RecastMapping.defaults(script.id).copyWith(
          roleAssemblies: const [
            RoleAssembly(
              sourceRoleId: 'role-0',
              displayLabel: 'Alice',
              sourceAppearances: [
                RoleAssemblySourceAppearance(
                  sourceId: 'slot-0',
                  sourceKind: 'slot',
                  frameIndexes: [1],
                ),
                RoleAssemblySourceAppearance(
                  sourceId: 'slot-1',
                  sourceKind: 'slot',
                  frameIndexes: [2],
                ),
              ],
              stages: [
                RoleAssemblyStage(
                  id: 'role-0-main',
                  label: 'main',
                  frameIndexes: [1, 2],
                  sourceParts: RecastPromptParts(identity: 'alice_(series)'),
                  manualParts: RecastPromptParts(identity: 'target_alice'),
                ),
              ],
            ),
          ],
        );

        final result = ScriptRecastEngine().resolvePayloads(
          script: script,
          mapping: mapping,
          characters: const [],
          artistChains: const [],
        );

        final frame1Captions = _resolvedCharCaptions(
          result.frames.first.payload,
        );
        final frame2Captions = _resolvedCharCaptions(
          result.frames.last.payload,
        );

        expect(frame1Captions, [
          'target_alice, white shirt',
          'beth_(series), black dress',
        ]);
        expect(frame2Captions, [
          'beth_(series), black dress',
          'target_alice, white shirt',
        ]);
      },
    );

    test(
      'role assembly base appearance replaces base-only character prompt',
      () {
        final script = _scriptWithBaseCaption(
          'alice_(series), white shirt, classroom',
        );
        final mapping = RecastMapping.defaults(script.id).copyWith(
          roleAssemblies: const [
            RoleAssembly(
              sourceRoleId: 'role-alice',
              displayLabel: 'Alice',
              sourceAppearances: [
                RoleAssemblySourceAppearance(
                  sourceId: 'base',
                  sourceKind: 'base',
                  frameIndexes: [1],
                ),
              ],
              stages: [
                RoleAssemblyStage(
                  id: 'role-alice-main',
                  label: 'main',
                  frameIndexes: [1],
                  sourceParts: RecastPromptParts(identity: 'alice_(series)'),
                  manualParts: RecastPromptParts(identity: 'target_alice'),
                ),
              ],
            ),
          ],
        );

        final result = ScriptRecastEngine().resolvePayloads(
          script: script,
          mapping: mapping,
          characters: const [],
          artistChains: const [],
        );

        final baseCaption = _resolvedBaseCaption(result);
        expect(baseCaption, 'target_alice, white shirt, classroom');
        expect(_resolvedCharCaptions(result.frames.single.payload), isEmpty);
      },
    );

    test(
      'global role assembly without appearances falls back to base prompt',
      () {
        final script = _scriptWithBaseCaption(
          'alice_(series), white shirt, classroom',
        );
        final mapping = RecastMapping.defaults(script.id).copyWith(
          roleAssemblies: const [
            RoleAssembly(
              sourceRoleId: 'global-0',
              displayLabel: 'Alice',
              stages: [
                RoleAssemblyStage(
                  id: 'global-0-main',
                  label: 'main',
                  frameIndexes: [1],
                  sourceParts: RecastPromptParts(identity: 'alice_(series)'),
                  manualParts: RecastPromptParts(identity: 'target_alice'),
                ),
              ],
            ),
          ],
        );

        final result = ScriptRecastEngine().resolvePayloads(
          script: script,
          mapping: mapping,
          characters: const [],
          artistChains: const [],
        );

        expect(
          _resolvedBaseCaption(result),
          'target_alice, white shirt, classroom',
        );
      },
    );

    test(
      'global block words apply before payload fingerprints are produced',
      () async {
        final script = await _parseFixture();
        final engine = ScriptRecastEngine();
        final mapping = RecastMapping.defaults(script.id);

        final unfiltered = engine.resolvePayloads(
          script: script,
          mapping: mapping,
          characters: const [],
          artistChains: const [],
        );
        final filtered = engine.resolvePayloads(
          script: script,
          mapping: mapping,
          characters: const [],
          artistChains: const [],
          globalBlockWords: 'bad hands, lowres, artist:terasu_mc, city lights',
        );

        final comment = filtered.frames.first.payload['Comment'] as Map;
        final prompt = comment['v4_prompt'] as Map;
        final caption = prompt['caption'] as Map;
        final negative = comment['v4_negative_prompt'] as Map;
        final negativeCaption = negative['caption'] as Map;
        expect(caption['base_caption'], isNot(contains('city lights')));
        expect(caption['base_caption'], isNot(contains('artist:terasu_mc')));
        expect(
          negativeCaption['char_captions'].toString(),
          isNot(contains('bad hands')),
        );
        expect(
          filtered.frames.first.payloadFingerprint,
          isNot(unfiltered.frames.first.payloadFingerprint),
        );
        expect(filtered.configFingerprint, isNot(unfiltered.configFingerprint));
        expect(
          filtered.frames.first.toJson().keys,
          isNot(contains('filterHits')),
        );
      },
    );

    test('full filter rule config applies to recast payloads', () async {
      final script = await _parseFixture();
      final engine = ScriptRecastEngine();
      final mapping = RecastMapping.defaults(script.id);

      final result = engine.resolvePayloads(
        script: script,
        mapping: mapping,
        characters: const [],
        artistChains: const [],
        filterRuleConfig: const FilterRuleConfig(
          deleteKeywords: 'artist:terasu_mc',
          strongFilterKeywords: 'bad hands',
          replaceRules: 'city lights -> neon alley',
        ),
      );

      final comment = result.frames.first.payload['Comment'] as Map;
      final prompt = comment['v4_prompt'] as Map;
      final caption = prompt['caption'] as Map;
      final negative = comment['v4_negative_prompt'] as Map;
      final negativeCaption = negative['caption'] as Map;

      expect(caption['base_caption'], contains('neon alley'));
      expect(caption['base_caption'], isNot(contains('city lights')));
      expect(caption['base_caption'], isNot(contains('artist:terasu_mc')));
      expect(
        negativeCaption['char_captions'].toString(),
        isNot(contains('bad hands')),
      );
      expect(result.configFingerprint, isNotEmpty);
    });
  });
}

final _newHeroine = CharacterEntry(
  id: 'char-x',
  name: 'New Heroine',
  traits: const ViewVariantTexts(frontFull: 'green eyes'),
  anchorTags: const ['new_heroine'],
  identityTags: const ['green eyes', 'long hair'],
  conflictTags: const ['fox_tail'],
);

const _outfitHeroine = CharacterEntry(
  id: 'char-outfit',
  name: 'Outfit Heroine',
  traits: ViewVariantTexts(frontFull: 'blue eyes'),
  anchorTags: ['stage_heroine'],
  identityTags: ['blue eyes'],
  conflictTags: ['fox_tail'],
  outfits: [
    WorkspaceOutfit(
      id: 'stage-dress',
      name: 'Stage Dress',
      tags: ViewVariantTexts(
        frontFull: 'black dress',
        frontUpper: 'lace blouse',
        frontLower: 'pleated skirt',
      ),
      partTags: WorkspaceOutfitPartTags(
        upperClothingTags: ['black dress', 'lace blouse'],
        lowerClothingTags: ['pleated skirt'],
      ),
    ),
  ],
);

const _duplicatedEyja = CharacterEntry(
  id: 'char-eyja',
  name: 'Eyjafjalla',
  traits: ViewVariantTexts(frontFull: 'eyjafjalla_(arknights)'),
  anchorTags: ['eyjafjalla_(arknights)'],
  identityTags: ['animal_ears', 'sheep_horns', 'eyjafjalla_(arknights)'],
  outfits: [
    WorkspaceOutfit(
      id: 'summer',
      name: 'Summer',
      tags: ViewVariantTexts(
        frontFull: 'eyjafjalla_(summer_flower)_(arknights)',
        frontUpper: 'eyjafjalla_(summer_flower)_(arknights), bikini, '
            'pink_bikini, plaid_bikini, plaid_clothes, swimsuit, '
            'swimsuit_cover-up',
        frontLower: 'bikini, pink_bikini, plaid_bikini, swimsuit, '
            'swimsuit_cover-up',
      ),
      partTags: WorkspaceOutfitPartTags(
        upperClothingTags: [
          'bikini',
          'pink_bikini',
          'plaid_bikini',
          'plaid_clothes',
          'swimsuit',
          'swimsuit_cover-up',
        ],
        lowerClothingTags: [
          'bikini',
          'pink_bikini',
          'plaid_bikini',
          'swimsuit',
          'swimsuit_cover-up',
        ],
      ),
    ),
  ],
);

const _splitPepe = CharacterEntry(
  id: 'split-pepe',
  name: 'Pepe',
  traits: ViewVariantTexts(
    frontFull: 'girl, 2::loli::, pepe_(arknights), cat ears, long hair, '
        'cat tail, animal ear hood, black jacket, black shorts',
    frontUpper: 'cat ears, long hair',
    frontLower: 'cat tail',
  ),
  outfits: [
    WorkspaceOutfit(
      id: 'default',
      name: 'Default',
      tags: ViewVariantTexts(
        frontFull: 'animal ear hood, black jacket, black shorts',
      ),
      partTags: WorkspaceOutfitPartTags(
        upperClothingTags: ['animal ear hood', 'black jacket'],
        lowerClothingTags: ['black shorts'],
      ),
    ),
    WorkspaceOutfit(
      id: 'variant-1',
      name: 'Variant 1',
      tags: ViewVariantTexts(
        frontFull: 'ancient egyptian clothes, sleeveless dress, white dress',
      ),
      partTags: WorkspaceOutfitPartTags(
        upperClothingTags: [
          'ancient egyptian clothes',
          'sleeveless dress',
          'white dress',
        ],
        lowerClothingTags: ['black shoes', 'black shorts'],
      ),
    ),
  ],
  defaultOutfitId: 'default',
);

const _skinPepe = CharacterEntry(
  id: 'skin-pepe',
  name: 'Pepe',
  traits: ViewVariantTexts(
    frontFull: 'girl, pepe_(arknights), cat ears, long hair, cat tail, '
        'animal ear hood, black jacket',
    frontUpper: 'cat ears, long hair',
    frontLower: 'cat tail',
  ),
  anchorTags: ['pepe_(arknights)'],
  outfits: [
    WorkspaceOutfit(
      id: 'default',
      name: 'Default',
      tags: ViewVariantTexts(
        frontFull: 'animal ear hood, black jacket, black shorts',
      ),
      partTags: WorkspaceOutfitPartTags(
        upperClothingTags: ['animal ear hood', 'black jacket'],
        lowerClothingTags: ['black shorts'],
      ),
    ),
    WorkspaceOutfit(
      id: 'nuit',
      name: 'Nuit of the Nightsky',
      tags: ViewVariantTexts(
        frontFull: 'pepe_(arknights), '
            'pepe_(nuit_of_the_nightsky)_(arknights), white dress, purple skirt',
      ),
      partTags: WorkspaceOutfitPartTags(
        upperClothingTags: ['white dress'],
        lowerClothingTags: ['purple skirt'],
      ),
    ),
  ],
  defaultOutfitId: 'default',
);

const _contaminatedSkinPepe = CharacterEntry(
  id: 'contaminated-skin-pepe',
  name: 'Pepe',
  traits: ViewVariantTexts(
    frontFull: 'pepe_(arknights), '
        'pepe_(nuit_of_the_nightsky)_(arknights), cat ears, cat tail',
    frontUpper: 'cat ears',
    frontLower: 'cat tail',
  ),
  anchorTags: ['pepe_(arknights)', 'pepe_(nuit_of_the_nightsky)_(arknights)'],
  identityTags: ['pepe_(arknights)', 'pepe_(nuit_of_the_nightsky)_(arknights)'],
  outfits: [
    WorkspaceOutfit(
      id: 'default',
      name: 'Default',
      tags: ViewVariantTexts(
        frontFull: 'animal ear hood, black jacket, black shorts',
      ),
      partTags: WorkspaceOutfitPartTags(
        upperClothingTags: ['animal ear hood', 'black jacket'],
        lowerClothingTags: ['black shorts'],
      ),
    ),
  ],
  defaultOutfitId: 'default',
);

const _skinPepeFrontFullOnly = CharacterEntry(
  id: 'skin-pepe-frontfull-only',
  name: 'Pepe',
  traits: ViewVariantTexts(
    frontFull: 'girl, pepe_(arknights), cat ears, long hair, cat tail',
    frontUpper: 'cat ears, long hair',
    frontLower: 'cat tail',
  ),
  anchorTags: ['pepe_(arknights)'],
  outfits: [
    WorkspaceOutfit(
      id: 'nuit-frontfull-only',
      name: 'Nuit of the Nightsky',
      tags: ViewVariantTexts(
        frontFull: 'pepe_(arknights), '
            'pepe_(nuit_of_the_nightsky)_(arknights), white dress, purple skirt',
      ),
    ),
  ],
);

const _splitPapyrus = CharacterEntry(
  id: 'split-papyrus',
  name: '莎草',
  traits: ViewVariantTexts(
    frontFull: 'girl, papyrus_(arknights), animal ears, cat ears, '
        'green eyes, orange hair, long hair, tail ornament',
    frontUpper: 'animal ears, cat ears, green eyes, orange hair, long hair',
    frontLower: 'tail ornament, fluffy tail',
  ),
  anchorTags: ['papyrus_(arknights)'],
  outfits: [
    WorkspaceOutfit(
      id: 'pink',
      name: '粉色睡衣',
      tags: ViewVariantTexts(
        frontFull:
            'girl, papyrus_(arknights), pink pajamas, dress, brown gloves',
      ),
      partTags: WorkspaceOutfitPartTags(
        upperClothingTags: ['pink pajamas', 'dress'],
        lowerClothingTags: ['brown gloves'],
      ),
    ),
  ],
  defaultOutfitId: 'pink',
);

const _assemblyHeroine = CharacterEntry(
  id: 'char-assembly',
  name: 'Assembly Heroine',
  traits: ViewVariantTexts(frontFull: 'blue eyes'),
  anchorTags: ['assembly_heroine'],
  identityTags: ['blue eyes'],
  outfits: [
    WorkspaceOutfit(
      id: 'upper-stage',
      name: 'Upper Stage',
      tags: ViewVariantTexts(
        frontFull: 'white blouse, red ribbon',
        frontUpper: 'white blouse',
      ),
      partTags: WorkspaceOutfitPartTags(upperClothingTags: ['white blouse']),
    ),
    WorkspaceOutfit(
      id: 'lower-stage',
      name: 'Lower Stage',
      tags: ViewVariantTexts(
        frontFull: 'bare legs, black boots',
        frontLower: 'bare legs, black boots',
      ),
      partTags: WorkspaceOutfitPartTags(
        lowerBodyTags: ['bare legs'],
        lowerClothingTags: ['black boots'],
      ),
    ),
  ],
);

Future<Script> _parseFixture() {
  return ScriptRecastParserService().parseDirectory(
    Directory('test/fixtures/script_recast/v4_slotted'),
  );
}

Script _scriptWithMovingSlots() {
  Map<String, dynamic> sourcePayload(List<String> captions) => {
        'Comment': {
          'v4_prompt': {
            'caption': {
              'base_caption': 'masterpiece',
              'char_captions': [
                for (final caption in captions) {'char_caption': caption},
              ],
            },
          },
        },
      };

  ScriptFrame frame(int index, List<String> captions) {
    return ScriptFrame(
      index: index,
      fileName: 'nai_$index.json',
      sourcePath: r'C:\scripts\moving-slots\nai_$index.json',
      rawJson: '{}',
      parsed: ParsedFrame(
        baseCaption: 'masterpiece',
        charCaptions: captions,
        sourcePayload: sourcePayload(captions),
      ),
      detectedSchema: ScriptSchema.v4Slotted,
      parseStatus: ScriptFrameParseStatus.parsed,
    );
  }

  return Script(
    id: 'script-moving-slots',
    name: 'Moving Slots',
    rootPath: r'C:\scripts\moving-slots',
    frames: [
      frame(1, const [
        'alice_(series), white shirt',
        'beth_(series), black dress',
      ]),
      frame(2, const [
        'beth_(series), black dress',
        'alice_(series), white shirt',
      ]),
    ],
    detectedSchema: ScriptSchema.v4Slotted,
    parseWarnings: const [],
    meta: const {},
  );
}

Script _scriptWithFramePrompts({
  required List<String> baseCaptions,
  List<List<String>> charCaptions = const [],
}) {
  ScriptFrame frame(int index, String baseCaption, List<String> captions) {
    final sourcePayload = {
      'Comment': {
        'v4_prompt': {
          'caption': {
            'base_caption': baseCaption,
            'char_captions': [
              for (final caption in captions) {'char_caption': caption},
            ],
          },
        },
      },
    };
    return ScriptFrame(
      index: index,
      fileName: 'nai_$index.json',
      sourcePath: 'C:\\scripts\\replacement-rules\\nai_$index.json',
      rawJson: '{}',
      parsed: ParsedFrame(
        baseCaption: baseCaption,
        charCaptions: captions,
        generationParams: const {'seed': 123},
        sourcePayload: sourcePayload,
      ),
      detectedSchema: ScriptSchema.v4Slotted,
      parseStatus: ScriptFrameParseStatus.parsed,
    );
  }

  return Script(
    id: 'script-replacement-rules',
    name: 'Replacement Rules',
    rootPath: 'C:\\scripts\\replacement-rules',
    frames: [
      for (var index = 0; index < baseCaptions.length; index += 1)
        frame(
          index + 1,
          baseCaptions[index],
          index < charCaptions.length ? charCaptions[index] : const [],
        ),
    ],
    detectedSchema: ScriptSchema.v4Slotted,
    parseWarnings: const [],
    meta: const {},
  );
}

Script _scriptWithBaseCaption(String baseCaption) {
  return Script(
    id: 'script-base-caption',
    name: 'Base Caption',
    rootPath: r'C:\scripts\base-caption',
    frames: [
      ScriptFrame(
        index: 1,
        fileName: 'nai_1.json',
        sourcePath: r'C:\scripts\base-caption\nai_1.json',
        rawJson: '{}',
        parsed: ParsedFrame(
          baseCaption: baseCaption,
          generationParams: const {'seed': 123},
          sourcePayload: {
            'Comment': {
              'v4_prompt': {
                'caption': {
                  'base_caption': baseCaption,
                  'char_captions': const [],
                },
              },
            },
          },
        ),
        detectedSchema: ScriptSchema.baseInline,
        parseStatus: ScriptFrameParseStatus.parsed,
      ),
    ],
    detectedSchema: ScriptSchema.baseInline,
    parseWarnings: const [],
    meta: const {},
  );
}

Script _scriptWithCharacterCaption(String charCaption, {int frameIndex = 1}) {
  return Script(
    id: 'script-duplicate-role-tags',
    name: 'Duplicate Role Tags',
    rootPath: r'C:\scripts\duplicate-role-tags',
    frames: [
      ScriptFrame(
        index: frameIndex,
        fileName: 'nai_$frameIndex.json',
        sourcePath: r'C:\scripts\duplicate-role-tags\nai_$frameIndex.json',
        rawJson: '{}',
        parsed: ParsedFrame(
          baseCaption: 'masterpiece, castle background',
          charCaptions: [charCaption],
          generationParams: const {'seed': 123},
          sourcePayload: const {
            'Comment': {
              'v4_prompt': {
                'caption': {
                  'base_caption': 'masterpiece, castle background',
                  'char_captions': [
                    {'char_caption': ''},
                  ],
                },
              },
            },
          },
        ),
        detectedSchema: ScriptSchema.v4Slotted,
        parseStatus: ScriptFrameParseStatus.parsed,
      ),
    ],
    detectedSchema: ScriptSchema.v4Slotted,
    parseWarnings: const [],
    meta: const {},
  );
}

String _resolvedCharCaption(ScriptRecastResult result) {
  final comment = result.frames.single.payload['Comment'] as Map;
  final prompt = comment['v4_prompt'] as Map;
  final caption = prompt['caption'] as Map;
  final charCaptions = caption['char_captions'] as List;
  final firstChar = charCaptions.single as Map;
  return firstChar['char_caption'] as String;
}

List<String> _resolvedCharCaptions(Map<String, dynamic> payload) {
  final comment = payload['Comment'] as Map;
  final prompt = comment['v4_prompt'] as Map;
  final caption = prompt['caption'] as Map;
  final charCaptions = caption['char_captions'] as List;
  return [
    for (final item in charCaptions.cast<Map>()) item['char_caption'] as String,
  ];
}

String _resolvedBaseCaption(ScriptRecastResult result) {
  final comment = result.frames.single.payload['Comment'] as Map;
  final prompt = comment['v4_prompt'] as Map;
  final caption = prompt['caption'] as Map;
  return caption['base_caption'] as String;
}

ScriptRecastResult _resultForFrame(
  ScriptRecastResult result,
  ScriptRecastFramePayload frame,
) {
  return ScriptRecastResult(
    scriptId: result.scriptId,
    mappingId: result.mappingId,
    frames: [frame],
    configFingerprint: result.configFingerprint,
  );
}

int _tagOccurrences(String caption, String tag) {
  return caption
      .split(',')
      .map((part) => part.trim().toLowerCase())
      .where((part) => part == tag.toLowerCase())
      .length;
}

String _artistChainLabel() {
  return String.fromCharCodes([0x753b, 0x5e08, 0x4e32]);
}

String _roleLabel() {
  return String.fromCharCodes([0x89d2, 0x8272]);
}

String _upperBodyLabel() {
  return String.fromCharCodes([0x4e0a, 0x8eab]);
}
