import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:novel_studio/data/studio/models/script_ai_role_extraction.dart';
import 'package:novel_studio/data/studio/models/script_recast.dart';
import 'package:novel_studio/data/studio/models/script_recast_knowledge.dart';
import 'package:novel_studio/data/studio/tools/prompt_tag_classifier.dart';
import '../../tool/normalize_script_recast_ai_cache.dart' as normalizer;

void main() {
  test('normalizes AI cache and is idempotent on second dry-run', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'script-recast-ai-cache-test-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final sourceDir = Directory(
      '${tempDir.path}${Platform.pathSeparator}source-script',
    );
    await sourceDir.create();
    await File('test/fixtures/script_recast/v4_slotted/nai_1.json').copy(
      '${sourceDir.path}${Platform.pathSeparator}nai_1.json',
    );
    await File('test/fixtures/script_recast/v4_slotted/nai_2.json').copy(
      '${sourceDir.path}${Platform.pathSeparator}nai_2.json',
    );

    final cacheFile = File('${tempDir.path}${Platform.pathSeparator}one.json');
    final cache = RecastScriptCache(
      scriptId: 'script-one',
      scriptName: 'Script One',
      sourceRootPath: sourceDir.path,
      sourceFingerprint: 'fingerprint',
      updatedAt: DateTime.utc(2026, 1),
      mapping: RecastMapping.defaults('script-one'),
      aiRoleExtraction: const ScriptAiRoleExtraction(
        status: ScriptAiRoleExtractionStatus.ready,
        confidence: 0.9,
        roles: [
          ScriptAiExtractedRole(
            sourceRoleId: 'global-0',
            sourceKind: 'global',
            displayName: 'Alice',
            appearances: [
              ScriptAiRoleAppearance(
                sourceId: 'base',
                sourceKind: 'base',
                frameIndexes: [1],
              ),
            ],
            stages: [
              ScriptAiExtractedStage(
                stageId: 'complete',
                label: 'main',
                frameIndexes: [1],
                identity: 'alice_(series)',
                upperBody: 'blue eyes, smile',
                upperClothing: 'school uniform',
                evidenceTerms: ['blue eyes', 'looking at viewer'],
              ),
              ScriptAiExtractedStage(
                stageId: 'subset',
                label: 'main subset',
                frameIndexes: [2],
                identity: 'alice_(series)',
                upperClothing: 'school uniform',
              ),
            ],
          ),
        ],
      ),
    );
    await cacheFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(cache.toJson()),
      encoding: utf8,
    );

    final auditFile = File(
      '${tempDir.path}${Platform.pathSeparator}audit.json',
    );
    final first = await _runNormalizer([
      '--cache-dir',
      tempDir.path,
      '--audit-report',
      auditFile.path,
    ]);
    expect(first.exitCode, 0, reason: first.stderr.toString());
    expect(first.stdout.toString(), contains('changed_files=1'));
    expect(
      first.stdout.toString(),
      contains('slotless_base_role_appearances=1'),
    );
    expect(first.stdout.toString(), contains('repaired_script_snapshots=1'));

    final normalized = RecastScriptCache.fromJson(
      Map<String, dynamic>.from(
        jsonDecode(await cacheFile.readAsString(encoding: utf8)) as Map,
      ),
    );
    final role = normalized.aiRoleExtraction.roles.single;
    expect(role.stages, hasLength(1));
    expect(role.stages.single.upperBody, 'blue eyes');
    expect(role.stages.single.nonRole, isEmpty);
    expect(role.stages.single.upperBody, isNot(contains('smile')));
    expect(role.stages.single.evidenceTerms, contains('looking at viewer'));

    final assembly = normalized.mapping.roleAssemblies.single;
    expect(assembly.sourceRoleId, 'global-0');
    expect(assembly.sourceAppearances.single.sourceId, 'base');
    expect(assembly.stages.single.sourceParts.upperBody, 'blue eyes');
    expect(
      assembly.stages.single.sourceParts.upperClothing,
      'school uniform',
    );
    expect(normalized.scriptSnapshot['frames'], hasLength(2));

    final audit = Map<String, dynamic>.from(
      jsonDecode(await auditFile.readAsString(encoding: utf8)) as Map,
    );
    expect(audit['cache_count'], 1);
    expect(audit['merged_stage_count'], 1);
    expect(audit['repaired_script_snapshots'], 1);
    expect(audit['residual_issue_count'], 0);

    final second = await _runNormalizer([
      '--dry-run',
      '--cache-dir',
      tempDir.path,
    ]);
    expect(second.exitCode, 0, reason: second.stderr.toString());
    expect(second.stdout.toString(), contains('changed_files=0'));
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('repairs pixiv image-set snapshot skeleton', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'script-recast-pixiv-cache-test-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final sourceDir = Directory(
      '${tempDir.path}${Platform.pathSeparator}pixiv-script',
    );
    await sourceDir.create();
    await File('${sourceDir.path}${Platform.pathSeparator}info.json')
        .writeAsString('not strict json, but enough to mark an image set');
    await File('${sourceDir.path}${Platform.pathSeparator}p00.png')
        .writeAsBytes([1, 2, 3]);
    await File('${sourceDir.path}${Platform.pathSeparator}p01.png')
        .writeAsBytes([4, 5, 6]);

    final cacheFile = File(
      '${tempDir.path}${Platform.pathSeparator}pixiv.json',
    );
    await cacheFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'scriptId': 'script-pixiv',
        'scriptName': 'Pixiv Script',
        'sourceRootPath': sourceDir.path,
        'sourceFingerprint': 'old',
        'updatedAt': DateTime.utc(2026, 1).toIso8601String(),
        'mapping': RecastMapping(
          id: 'mapping-script-pixiv',
          scriptId: 'script-pixiv',
          roleAssemblies: [
            RoleAssembly(
              sourceRoleId: 'role-slot-one',
              displayLabel: 'slot one',
              sourceAppearances: [
                RoleAssemblySourceAppearance(
                  sourceId: 'slot-1',
                  sourceKind: 'slot',
                  frameIndexes: [1, 2],
                ),
              ],
              stages: [
                RoleAssemblyStage(
                  id: 'stage-1',
                  label: 'Stage 1',
                  frameIndexes: [1, 2],
                  sourceParts: RecastPromptParts(identity: 'girl'),
                ),
              ],
            ),
          ],
        ).toJson(),
        'aiRoleExtraction': const ScriptAiRoleExtraction(
          status: ScriptAiRoleExtractionStatus.ready,
          roles: [
            ScriptAiExtractedRole(
              sourceRoleId: 'role-slot-one',
              displayName: 'slot one',
              appearances: [
                ScriptAiRoleAppearance(
                  sourceId: 'slot-1',
                  sourceKind: 'slot',
                  frameIndexes: [1, 2],
                ),
              ],
              stages: [
                ScriptAiExtractedStage(
                  stageId: 'stage-1',
                  frameIndexes: [1, 2],
                  identity: 'girl',
                ),
              ],
            ),
          ],
        ).toJson(),
      }),
      encoding: utf8,
    );

    final first = await _runNormalizer([
      '--cache-dir',
      tempDir.path,
    ]);
    expect(first.exitCode, 0, reason: first.stderr.toString());
    expect(first.stdout.toString(), contains('changed_files=1'));
    expect(first.stdout.toString(), contains('repaired_script_snapshots=1'));
    expect(
      first.stdout.toString(),
      contains('unrepaired_script_snapshots=0'),
    );

    final normalized = RecastScriptCache.fromJson(
      Map<String, dynamic>.from(
        jsonDecode(await cacheFile.readAsString(encoding: utf8)) as Map,
      ),
    );
    final frames = normalized.scriptSnapshot['frames'] as List<dynamic>;
    expect(frames, hasLength(2));
    expect(frames.first, containsPair('fileName', 'p00.png'));
    expect(frames.first, containsPair('sourceImagePath', isNotEmpty));
    final parsed = Map<String, dynamic>.from(
      frames.first['parsed'] as Map,
    );
    expect(parsed['charCaptions'], ['', '']);

    final second = await _runNormalizer([
      '--dry-run',
      '--cache-dir',
      tempDir.path,
    ]);
    expect(second.exitCode, 0, reason: second.stderr.toString());
    expect(second.stdout.toString(), contains('changed_files=0'));
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('upgrades image-set skeleton with PNG prompt metadata', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'script-recast-png-metadata-cache-test-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final sourceDir = Directory(
      '${tempDir.path}${Platform.pathSeparator}png-script',
    );
    await sourceDir.create();
    await File('${sourceDir.path}${Platform.pathSeparator}p00.png')
        .writeAsBytes(
      _pngWithTextChunks({
        'Comment': jsonEncode({
          'width': 832,
          'height': 1216,
          'v4_prompt': {
            'caption': {
              'base_caption': '2girls, candlelit room',
              'char_captions': [
                {
                  'char_caption': 'kokkoro (princess_connect!), white dress',
                  'centers': [
                    {'x': 0.25, 'y': 0.5},
                  ],
                },
              ],
            },
          },
          'v4_negative_prompt': {
            'caption': {
              'base_caption': 'lowres',
              'char_captions': [
                {'char_caption': 'bad hands'},
              ],
            },
          },
        }),
      }),
    );
    await File('${sourceDir.path}${Platform.pathSeparator}p01.png')
        .writeAsBytes(_pngWithTextChunks({}));
    await File('${sourceDir.path}${Platform.pathSeparator}p02.png')
        .writeAsBytes(
      _pngWithTextChunks({
        'Comment': jsonEncode({
          'v4_prompt': {
            'caption': {
              'base_caption': '1girl, moonlit garden',
              'char_captions': [
                {
                  'char_caption':
                      'kokkoro (ceremonial) (princess_connect!), staff',
                },
              ],
            },
          },
        }),
      }),
    );
    await File('${sourceDir.path}${Platform.pathSeparator}p03.png')
        .writeAsBytes(
      _pngWithStealthMetadata(
        jsonEncode({
          'Comment': jsonEncode({
            'v4_prompt': {
              'caption': {
                'base_caption': '1girl, hidden archive',
                'char_captions': [
                  {
                    'char_caption':
                        'kokkoro (stealth) (princess_connect!), cloak',
                  },
                ],
              },
            },
          }),
        }),
      ),
    );

    final cacheFile = File(
      '${tempDir.path}${Platform.pathSeparator}png.json',
    );
    await cacheFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'scriptId': 'script-png',
        'scriptName': 'PNG Script',
        'sourceRootPath': sourceDir.path,
        'sourceFingerprint': 'old',
        'updatedAt': DateTime.utc(2026, 1).toIso8601String(),
        'mapping': RecastMapping.defaults('script-png').toJson(),
        'aiRoleExtraction': const ScriptAiRoleExtraction(
          status: ScriptAiRoleExtractionStatus.ready,
          roles: [
            ScriptAiExtractedRole(
              sourceRoleId: 'role-kokkoro',
              displayName: 'kokkoro',
              appearances: [
                ScriptAiRoleAppearance(
                  sourceId: 'slot-0',
                  sourceKind: 'slot',
                  frameIndexes: [1, 2, 3],
                ),
              ],
              stages: [
                ScriptAiExtractedStage(
                  stageId: 'base',
                  frameIndexes: [1, 2, 3],
                  identity: 'kokkoro (princess_connect!)',
                ),
              ],
            ),
          ],
        ).toJson(),
        'scriptSnapshot': {
          'id': 'script-png',
          'name': 'PNG Script',
          'rootPath': sourceDir.path,
          'frames': [
            {
              'index': 1,
              'fileName': 'p00.png',
              'sourcePath': '${sourceDir.path}${Platform.pathSeparator}p00.png',
              'rawJson': '{}',
              'parsed': {
                'baseCaption': '',
                'charCaptions': [''],
                'negativeBase': '',
                'negativeCharCaptions': [''],
                'coords': [],
                'generationParams': {},
                'sourcePayload': {
                  'source_kind': 'pixiv_image_set_frame',
                },
              },
              'detectedSchema': 'v4Slotted',
              'parseStatus': 'parsed',
              'warnings': [],
            },
          ],
          'detectedSchema': 'v4Slotted',
          'parseWarnings': [],
          'meta': {'frameCount': 1},
        },
      }),
      encoding: utf8,
    );

    final first = await _runNormalizer([
      '--cache-dir',
      tempDir.path,
    ]);
    expect(first.exitCode, 0, reason: first.stderr.toString());
    expect(first.stdout.toString(), contains('changed_files=1'));
    expect(first.stdout.toString(), contains('repaired_script_snapshots=1'));

    final normalized = RecastScriptCache.fromJson(
      Map<String, dynamic>.from(
        jsonDecode(await cacheFile.readAsString(encoding: utf8)) as Map,
      ),
    );
    final frames = normalized.scriptSnapshot['frames'] as List<dynamic>;
    expect(frames, hasLength(3));
    expect(frames[0], containsPair('index', 1));
    expect(frames[0], containsPair('fileName', 'p00.png'));
    expect(frames[1], containsPair('index', 2));
    expect(frames[1], containsPair('fileName', 'p02.png'));
    expect(frames[2], containsPair('index', 3));
    expect(frames[2], containsPair('fileName', 'p03.png'));
    final firstParsed = Map<String, dynamic>.from(
      frames.first['parsed'] as Map,
    );
    expect(firstParsed['baseCaption'], '2girls, candlelit room');
    expect(firstParsed['charCaptions'], [
      'kokkoro (princess_connect!), white dress',
    ]);
    expect(firstParsed['negativeBase'], 'lowres');
    expect(firstParsed['negativeCharCaptions'], ['bad hands']);
    expect(firstParsed['coords'], [
      {'x': 0.25, 'y': 0.5},
    ]);
    final sourcePayload = Map<String, dynamic>.from(
      firstParsed['sourcePayload'] as Map,
    );
    expect(sourcePayload['source_kind'], 'png_metadata_frame');

    final secondParsed = Map<String, dynamic>.from(
      frames[1]['parsed'] as Map,
    );
    expect(secondParsed['baseCaption'], '1girl, moonlit garden');
    expect(secondParsed['charCaptions'], [
      'kokkoro (ceremonial) (princess_connect!), staff',
    ]);
    final thirdParsed = Map<String, dynamic>.from(
      frames[2]['parsed'] as Map,
    );
    expect(thirdParsed['baseCaption'], '1girl, hidden archive');
    expect(thirdParsed['charCaptions'], [
      'kokkoro (stealth) (princess_connect!), cloak',
    ]);
    final snapshot = Map<String, dynamic>.from(normalized.scriptSnapshot);
    final meta = Map<String, dynamic>.from(snapshot['meta'] as Map);
    expect(meta['skippedMetadataFrameCount'], 1);
    expect(meta['skippedMetadataFiles'], ['p01.png']);

    final second = await _runNormalizer([
      '--dry-run',
      '--cache-dir',
      tempDir.path,
    ]);
    expect(second.exitCode, 0, reason: second.stderr.toString());
    expect(second.stdout.toString(), contains('changed_files=0'));
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('prefers PNG metadata when JSON sidecars are present', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'script-recast-png-over-json-cache-test-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final sourceDir = Directory(
      '${tempDir.path}${Platform.pathSeparator}mixed-script',
    );
    await sourceDir.create();
    await File('${sourceDir.path}${Platform.pathSeparator}p00.json')
        .writeAsString(
      jsonEncode({
        'Description': 'json sidecar prompt',
        'Comment': {
          'v4_prompt': {
            'caption': {
              'base_caption': 'json sidecar prompt',
              'char_captions': [
                {'char_caption': 'json sidecar role'},
              ],
            },
          },
        },
      }),
      encoding: utf8,
    );
    await File('${sourceDir.path}${Platform.pathSeparator}p00.png')
        .writeAsBytes(
      _pngWithStealthMetadata(
        jsonEncode({
          'Description': 'png stealth prompt',
          'Comment': jsonEncode({
            'v4_prompt': {
              'caption': {
                'base_caption': 'png stealth prompt',
                'char_captions': [
                  {'char_caption': 'png stealth role'},
                ],
              },
            },
          }),
        }),
      ),
    );

    final cacheFile = File(
      '${tempDir.path}${Platform.pathSeparator}mixed.json',
    );
    await cacheFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'scriptId': 'script-mixed',
        'scriptName': 'Mixed Script',
        'sourceRootPath': sourceDir.path,
        'sourceFingerprint': 'old',
        'updatedAt': DateTime.utc(2026, 1).toIso8601String(),
        'mapping': RecastMapping.defaults('script-mixed').toJson(),
        'aiRoleExtraction': const ScriptAiRoleExtraction(
          status: ScriptAiRoleExtractionStatus.ready,
          roles: [],
        ).toJson(),
        'scriptSnapshot': {'frames': []},
      }),
      encoding: utf8,
    );

    final first = await _runNormalizer([
      '--cache-dir',
      tempDir.path,
    ]);
    expect(first.exitCode, 0, reason: first.stderr.toString());
    expect(first.stdout.toString(), contains('repaired_script_snapshots=1'));

    final normalized = RecastScriptCache.fromJson(
      Map<String, dynamic>.from(
        jsonDecode(await cacheFile.readAsString(encoding: utf8)) as Map,
      ),
    );
    final frames = normalized.scriptSnapshot['frames'] as List<dynamic>;
    expect(frames, hasLength(1));
    expect(frames.single, containsPair('fileName', 'p00.png'));
    final parsed = Map<String, dynamic>.from(frames.single['parsed'] as Map);
    expect(parsed['baseCaption'], 'png stealth prompt');
    expect(parsed['charCaptions'], ['png stealth role']);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('keeps JSON metadata and attaches sibling PNG preview image', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'script-recast-json-with-png-preview-cache-test-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final sourceDir = Directory(
      '${tempDir.path}${Platform.pathSeparator}json-script',
    );
    final pngDir = Directory(
      '${sourceDir.path}${Platform.pathSeparator}PNG',
    );
    await pngDir.create(recursive: true);
    await File('${sourceDir.path}${Platform.pathSeparator}p000.json')
        .writeAsString(
      jsonEncode({
        'Description': 'json prompt',
        'Comment': {
          'v4_prompt': {
            'caption': {
              'base_caption': 'json prompt',
              'char_captions': [
                {'char_caption': 'json role'},
              ],
            },
          },
        },
      }),
      encoding: utf8,
    );
    await File('${pngDir.path}${Platform.pathSeparator}p000.png')
        .writeAsBytes([1, 2, 3]);

    final cacheFile = File(
      '${tempDir.path}${Platform.pathSeparator}json-preview.json',
    );
    await cacheFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'scriptId': 'script-json-preview',
        'scriptName': 'JSON Preview Script',
        'sourceRootPath': sourceDir.path,
        'sourceFingerprint': 'old',
        'updatedAt': DateTime.utc(2026, 1).toIso8601String(),
        'mapping': RecastMapping.defaults('script-json-preview').toJson(),
        'aiRoleExtraction': const ScriptAiRoleExtraction(
          status: ScriptAiRoleExtractionStatus.ready,
          roles: [],
        ).toJson(),
        'scriptSnapshot': {'frames': []},
      }),
      encoding: utf8,
    );

    final first = await _runNormalizer([
      '--cache-dir',
      tempDir.path,
    ]);
    expect(first.exitCode, 0, reason: first.stderr.toString());

    final normalized = RecastScriptCache.fromJson(
      Map<String, dynamic>.from(
        jsonDecode(await cacheFile.readAsString(encoding: utf8)) as Map,
      ),
    );
    final frames = normalized.scriptSnapshot['frames'] as List<dynamic>;
    expect(frames, hasLength(1));
    expect(frames.single, containsPair('fileName', 'p000.json'));
    expect(
      frames.single,
      containsPair(
        'sourceImagePath',
        '${pngDir.path}${Platform.pathSeparator}p000.png',
      ),
    );
    final parsed = Map<String, dynamic>.from(frames.single['parsed'] as Map);
    expect(parsed['baseCaption'], 'json prompt');
    expect(parsed['charCaptions'], ['json role']);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('splits overmerged stages by per-frame source caption evidence',
      () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'script-recast-evidence-split-cache-test-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final cacheFile = File(
      '${tempDir.path}${Platform.pathSeparator}evidence.json',
    );
    await cacheFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'scriptId': 'script-evidence',
        'scriptName': 'Evidence Script',
        'sourceRootPath': 'unused',
        'sourceFingerprint': 'fingerprint',
        'updatedAt': '2026-01-01T00:00:00.000Z',
        'scriptSnapshot': {
          'id': 'script-evidence',
          'name': 'Evidence Script',
          'rootPath': 'unused',
          'frames': [
            _frameSnapshot(
              1,
              'girl, kokkoro (princess_connect!), blue eyes, '
              'white bridal gauntlets, completly nude, empty eyes',
            ),
            _frameSnapshot(
              2,
              'girl, kokkoro (princess_connect!), blue eyes, '
              'white bridal gauntlets, white leotard',
            ),
            _frameSnapshot(
              3,
              'girl, kokkoro (princess_connect!), blue eyes, '
              'white bridal gauntlets, white leotard',
            ),
          ],
          'detectedSchema': 'v4Slotted',
          'parseWarnings': [],
          'meta': {'frameCount': 3},
        },
        'mapping': RecastMapping(
          id: 'mapping-script-evidence',
          scriptId: 'script-evidence',
          roleAssemblies: [
            RoleAssembly(
              sourceRoleId: 'role-kokkoro',
              displayLabel: 'Kokkoro',
              sourceAppearances: [
                RoleAssemblySourceAppearance(
                  sourceId: 'slot-0',
                  sourceKind: 'slot',
                  frameIndexes: [1, 2, 3],
                ),
              ],
              stages: [
                RoleAssemblyStage(
                  id: 'stage-main',
                  label: 'Stage Main',
                  frameIndexes: [1, 2, 3],
                  sourceParts: RecastPromptParts(
                    identity: 'girl, kokkoro (princess_connect!)',
                    upperBody: 'blue eyes, empty eyes',
                    upperClothing: 'white bridal gauntlets, white leotard',
                  ),
                  targetCharacterId: 'target-kokkoro',
                  targetUpperOutfitId: 'target-ceremonial',
                  manualParts: RecastPromptParts(
                    upperClothing: 'replacement ceremonial outfit',
                  ),
                ),
              ],
            ),
          ],
        ).toJson(),
        'aiRoleExtraction': const ScriptAiRoleExtraction(
          status: ScriptAiRoleExtractionStatus.ready,
          roles: [
            ScriptAiExtractedRole(
              sourceRoleId: 'role-kokkoro',
              displayName: 'Kokkoro',
              appearances: [
                ScriptAiRoleAppearance(
                  sourceId: 'slot-0',
                  sourceKind: 'slot',
                  frameIndexes: [1, 2, 3],
                ),
              ],
              stages: [
                ScriptAiExtractedStage(
                  stageId: 'stage-main',
                  label: 'Stage Main',
                  frameIndexes: [1, 2, 3],
                  identity: 'girl, kokkoro (princess_connect!)',
                  upperBody: 'blue eyes, empty eyes',
                  upperClothing: 'white bridal gauntlets, white leotard',
                ),
              ],
            ),
          ],
        ).toJson(),
      }),
      encoding: utf8,
    );

    final first = await _runNormalizer([
      '--cache-dir',
      tempDir.path,
    ]);
    expect(first.exitCode, 0, reason: first.stderr.toString());
    expect(first.stdout.toString(), contains('changed_files=1'));

    final normalized = RecastScriptCache.fromJson(
      Map<String, dynamic>.from(
        jsonDecode(await cacheFile.readAsString(encoding: utf8)) as Map,
      ),
    );
    final aiStages = normalized.aiRoleExtraction.roles.single.stages;
    expect(aiStages, hasLength(2));
    final nudeStage =
        aiStages.singleWhere((stage) => stage.frameIndexes.contains(1));
    final leotardStage =
        aiStages.singleWhere((stage) => stage.frameIndexes.contains(2));
    expect(nudeStage.frameIndexes, [1]);
    expect(nudeStage.upperBody, 'blue eyes');
    expect(nudeStage.upperClothing, 'white bridal gauntlets');
    expect(nudeStage.nonRole, isEmpty);
    expect(nudeStage.upperBody, isNot(contains('empty eyes')));
    expect(leotardStage.frameIndexes, [2, 3]);
    expect(leotardStage.upperBody, 'blue eyes');
    expect(
      leotardStage.upperClothing,
      'white bridal gauntlets, white leotard',
    );

    final mappingStages = normalized.mapping.roleAssemblies.single.stages;
    expect(mappingStages, hasLength(2));
    for (final stage in mappingStages) {
      expect(stage.targetCharacterId, 'target-kokkoro');
      expect(stage.targetUpperOutfitId, 'target-ceremonial');
      expect(
        stage.manualParts.upperClothing,
        'replacement ceremonial outfit',
      );
    }

    final second = await _runNormalizer([
      '--dry-run',
      '--cache-dir',
      tempDir.path,
    ]);
    expect(second.exitCode, 0, reason: second.stderr.toString());
    expect(second.stdout.toString(), contains('changed_files=0'));
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('does not synthesize semantic prompt terms from source captions',
      () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'script-recast-character-prompt-terms-test-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final cacheFile = File(
      '${tempDir.path}${Platform.pathSeparator}character-terms.json',
    );
    await cacheFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'scriptId': 'script-character-terms',
        'scriptName': 'Character Terms Script',
        'sourceRootPath': 'unused',
        'sourceFingerprint': 'fingerprint',
        'updatedAt': '2026-01-01T00:00:00.000Z',
        'scriptSnapshot': {
          'id': 'script-character-terms',
          'name': 'Character Terms Script',
          'rootPath': 'unused',
          'frames': [
            _frameSnapshot(
              1,
              'girl, suzuna (princess connect!), double bun, gyaru, '
              'demon girl, demon horns, demon tail, cristal wings, '
              'white shirt, black skirt',
            ),
            _frameSnapshot(
              2,
              'girl, suzuna (princess connect!), double bun, gyaru, '
              'demon girl, demon horns, demon tail, cristal wings, '
              'white shirt, black skirt',
            ),
          ],
          'detectedSchema': 'v4Slotted',
          'parseWarnings': [],
          'meta': {'frameCount': 2},
        },
        'mapping': RecastMapping(
          id: 'mapping-script-character-terms',
          scriptId: 'script-character-terms',
          roleAssemblies: const [
            RoleAssembly(
              sourceRoleId: 'role-suzuna',
              displayLabel: 'Suzuna',
              sourceAppearances: [
                RoleAssemblySourceAppearance(
                  sourceId: 'slot-0',
                  sourceKind: 'slot',
                  frameIndexes: [1, 2],
                ),
              ],
              stages: [
                RoleAssemblyStage(
                  id: 'stage-main',
                  label: 'Stage Main',
                  frameIndexes: [1, 2],
                  sourceParts: RecastPromptParts(
                    identity: 'suzuna (princess connect!)',
                    upperBody: 'demon horns, cristal wings',
                    lowerBody: 'demon tail',
                    upperClothing: 'white shirt',
                    lowerClothing: 'black skirt',
                  ),
                ),
              ],
            ),
          ],
        ).toJson(),
        'aiRoleExtraction': const ScriptAiRoleExtraction(
          status: ScriptAiRoleExtractionStatus.ready,
          roles: [
            ScriptAiExtractedRole(
              sourceRoleId: 'role-suzuna',
              displayName: 'Suzuna',
              appearances: [
                ScriptAiRoleAppearance(
                  sourceId: 'slot-0',
                  sourceKind: 'slot',
                  frameIndexes: [1, 2],
                ),
              ],
              stages: [
                ScriptAiExtractedStage(
                  stageId: 'stage-main',
                  label: 'Stage Main',
                  frameIndexes: [1, 2],
                  identity: 'suzuna (princess connect!)',
                  upperBody: 'demon horns, cristal wings',
                  lowerBody: 'demon tail',
                  upperClothing: 'white shirt',
                  lowerClothing: 'black skirt',
                ),
              ],
            ),
          ],
        ).toJson(),
      }),
      encoding: utf8,
    );

    final first = await _runNormalizer([
      '--cache-dir',
      tempDir.path,
    ]);
    expect(first.exitCode, 0, reason: first.stderr.toString());

    final normalized = RecastScriptCache.fromJson(
      Map<String, dynamic>.from(
        jsonDecode(await cacheFile.readAsString(encoding: utf8)) as Map,
      ),
    );
    expect(normalized.aiRoleExtraction.roles.single.promptTerms, isEmpty);
    expect(normalized.mapping.rolePromptReplacements, isEmpty);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('preserves existing AI prompt terms and confirmed mappings', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'script-recast-existing-prompt-terms-test-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final cacheFile = File(
      '${tempDir.path}${Platform.pathSeparator}existing-terms.json',
    );
    await cacheFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'scriptId': 'script-existing-terms',
        'scriptName': 'Existing Terms Script',
        'sourceRootPath': 'unused',
        'sourceFingerprint': 'fingerprint',
        'updatedAt': '2026-01-01T00:00:00.000Z',
        'scriptSnapshot': {
          'id': 'script-existing-terms',
          'name': 'Existing Terms Script',
          'rootPath': 'unused',
          'frames': [
            _frameSnapshot(
              1,
              'double bun, gyaru, bedroom',
            ),
          ],
          'detectedSchema': 'v4Slotted',
          'parseWarnings': [],
          'meta': {'frameCount': 1},
        },
        'mapping': RecastMapping(
          id: 'mapping-script-existing-terms',
          scriptId: 'script-existing-terms',
          rolePromptReplacements: const [
            ScriptRolePromptReplacement(
              sourceRoleId: 'role-suzuna',
              displayLabel: 'Suzuna',
              targetCharacterId: 'target-suzuna',
              targetIdentityPrompt: 'target identity',
              rules: [
                ScriptPromptReplacementRule(
                  id: 'legacy-double-bun-rule',
                  sourceTerms: [
                    ScriptPromptReplacementTerm(
                      id: 'legacy-double-bun',
                      text: 'double bun',
                      category: PromptTagCategory.upperBody,
                    ),
                  ],
                  targetPrompt: 'single braid',
                ),
              ],
            ),
          ],
        ).toJson(),
        'aiRoleExtraction': const ScriptAiRoleExtraction(
          status: ScriptAiRoleExtractionStatus.ready,
          roles: [
            ScriptAiExtractedRole(
              sourceRoleId: 'role-suzuna',
              displayName: 'Suzuna',
              appearances: [
                ScriptAiRoleAppearance(
                  sourceId: 'slot-0',
                  sourceKind: 'slot',
                  frameIndexes: [1],
                ),
              ],
              promptTerms: [
                ScriptAiExtractedPromptTerm(
                  id: 'term-double-bun',
                  text: 'double bun',
                  category: PromptTagCategory.upperBody,
                  sourcePhrase: 'double bun',
                  frameIndexes: [1],
                ),
                ScriptAiExtractedPromptTerm(
                  id: 'term-gyaru',
                  text: 'gyaru',
                  category: PromptTagCategory.character,
                  sourcePhrase: 'gyaru',
                  frameIndexes: [1],
                ),
              ],
            ),
          ],
        ).toJson(),
      }),
      encoding: utf8,
    );

    final first = await _runNormalizer([
      '--cache-dir',
      tempDir.path,
    ]);
    expect(first.exitCode, 0, reason: first.stderr.toString());

    final normalized = RecastScriptCache.fromJson(
      Map<String, dynamic>.from(
        jsonDecode(await cacheFile.readAsString(encoding: utf8)) as Map,
      ),
    );
    expect(
      normalized.aiRoleExtraction.roles.single.promptTerms
          .map((term) => term.text),
      ['double bun', 'gyaru'],
    );
    final replacement = normalized.mapping.rolePromptReplacements.single;
    expect(replacement.targetCharacterId, 'target-suzuna');
    expect(replacement.targetIdentityPrompt, 'target identity');
    expect(replacement.rules, hasLength(2));
    expect(replacement.rules.first.id, 'legacy-double-bun-rule');
    expect(replacement.rules.first.targetPrompt, 'single braid');
    expect(replacement.rules.first.sourceTerms.single.id, 'term-double-bun');
    expect(replacement.rules.last.sourceTerms.single.text, 'gyaru');
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('preserves legacy clothing rule across refined AI category', () {
    final replacements = normalizer.rolePromptReplacementsWithAiTermsForTesting(
      existingReplacements: const [
        ScriptRolePromptReplacement(
          sourceRoleId: 'slot-0',
          displayLabel: 'Role',
          rules: [
            ScriptPromptReplacementRule(
              id: 'legacy-strap-slip-rule',
              sourceTerms: [
                ScriptPromptReplacementTerm(
                  id: 'legacy-strap-slip',
                  text: 'strap slip',
                  category: PromptTagCategory.clothing,
                ),
              ],
              targetPrompt: 'secure straps',
            ),
          ],
        ),
      ],
      roles: const [
        ScriptAiExtractedRole(
          sourceRoleId: 'slot-0',
          displayName: 'Role',
          appearances: [
            ScriptAiRoleAppearance(
              sourceId: 'slot-0',
              sourceKind: 'slot',
              frameIndexes: [1],
            ),
          ],
          promptTerms: [
            ScriptAiExtractedPromptTerm(
              id: 'term-strap-slip',
              text: 'strap slip',
              category: PromptTagCategory.clothingState,
              frameIndexes: [1],
            ),
          ],
        ),
      ],
    );

    final rule = replacements.single.rules.single;
    expect(rule.id, 'legacy-strap-slip-rule');
    expect(rule.targetPrompt, 'secure straps');
    expect(rule.sourceTerms.single.id, 'term-strap-slip');
    expect(
      rule.sourceTerms.single.category,
      PromptTagCategory.clothingState,
    );
  });

  test(
    'does not reuse legacy rule when non-migration categories only share text',
    () {
      final replacements =
          normalizer.rolePromptReplacementsWithAiTermsForTesting(
        existingReplacements: const [
          ScriptRolePromptReplacement(
            sourceRoleId: 'slot-0',
            displayLabel: 'Role',
            rules: [
              ScriptPromptReplacementRule(
                id: 'legacy-standing-rule',
                sourceTerms: [
                  ScriptPromptReplacementTerm(
                    id: 'legacy-standing',
                    text: 'standing',
                    category: PromptTagCategory.character,
                  ),
                ],
                targetPrompt: 'hero pose',
              ),
            ],
          ),
        ],
        roles: const [
          ScriptAiExtractedRole(
            sourceRoleId: 'slot-0',
            displayName: 'Role',
            appearances: [
              ScriptAiRoleAppearance(
                sourceId: 'slot-0',
                sourceKind: 'slot',
                frameIndexes: [1],
              ),
            ],
            promptTerms: [
              ScriptAiExtractedPromptTerm(
                id: 'term-standing',
                text: 'standing',
                category: PromptTagCategory.action,
                frameIndexes: [1],
              ),
            ],
          ),
        ],
      );

      final rules = replacements.single.rules;
      expect(rules, hasLength(2));
      expect(rules.first.id, isNot('legacy-standing-rule'));
      expect(rules.first.sourceTerms.single.id, 'term-standing');
      expect(rules.first.sourceTerms.single.category, PromptTagCategory.action);
      expect(rules.first.targetPrompt, isEmpty);
      expect(rules.last.id, 'legacy-standing-rule');
      expect(rules.last.targetPrompt, 'hero pose');
    },
  );
}

Future<ProcessResult> _runNormalizer(List<String> args) {
  return Process.run(
    Platform.resolvedExecutable,
    [
      '--packages=.dart_tool/package_config.json',
      'tool/normalize_script_recast_ai_cache.dart',
      ...args,
    ],
    workingDirectory: Directory.current.path,
  );
}

Map<String, dynamic> _frameSnapshot(int index, String charCaption) {
  return {
    'index': index,
    'fileName': 'p${index.toString().padLeft(2, '0')}.png',
    'sourcePath': 'p${index.toString().padLeft(2, '0')}.png',
    'sourceImagePath': 'p${index.toString().padLeft(2, '0')}.png',
    'rawJson': '{}',
    'parsed': {
      'baseCaption': '',
      'charCaptions': [charCaption],
      'negativeBase': '',
      'negativeCharCaptions': [''],
      'coords': [],
      'generationParams': {},
      'sourcePayload': {},
    },
    'detectedSchema': 'v4Slotted',
    'parseStatus': 'parsed',
    'warnings': [],
  };
}

Uint8List _pngWithTextChunks(Map<String, String> chunks) {
  return Uint8List.fromList([
    137,
    80,
    78,
    71,
    13,
    10,
    26,
    10,
    ..._pngChunk('IHDR', List.filled(13, 0)),
    for (final entry in chunks.entries)
      ..._pngChunk('tEXt', [
        ...utf8.encode(entry.key),
        0,
        ...utf8.encode(entry.value),
      ]),
    ..._pngChunk('IEND', const []),
  ]);
}

Uint8List _pngWithStealthMetadata(String metadataString) {
  final image = img.Image(width: 128, height: 128, numChannels: 4);
  final data = [
    ...utf8.encode('stealth_pngcomp'),
    ..._uint32Bytes(GZipCodec().encode(utf8.encode(metadataString)).length * 8),
    ...GZipCodec().encode(utf8.encode(metadataString)),
  ];
  if (data.length * 8 > image.width * image.height) {
    throw StateError('Stealth test metadata does not fit in the image.');
  }

  var bitIndex = 0;
  for (var x = 0; x < image.width; x += 1) {
    for (var y = 0; y < image.height; y += 1) {
      final byteIndex = bitIndex ~/ 8;
      if (byteIndex >= data.length) {
        return Uint8List.fromList(img.encodePng(image));
      }
      final bit = (data[byteIndex] >> (7 - bitIndex % 8)) & 1;
      final pixel = image.getPixel(x, y);
      pixel.a = 254 | bit;
      image.setPixel(x, y, pixel);
      bitIndex += 1;
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

List<int> _pngChunk(String type, List<int> data) {
  return [
    ..._uint32Bytes(data.length),
    ...ascii.encode(type),
    ...data,
    0,
    0,
    0,
    0,
  ];
}

List<int> _uint32Bytes(int value) {
  return [
    value >> 24 & 0xff,
    value >> 16 & 0xff,
    value >> 8 & 0xff,
    value & 0xff,
  ];
}
