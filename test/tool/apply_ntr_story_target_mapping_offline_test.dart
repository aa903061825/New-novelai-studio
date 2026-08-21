import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('dynamic role mappings do not create global slot swaps', () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'script-recast-target-mapping-test-',
    );
    addTearDown(() async {
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });

    final workspace = Directory('${tempRoot.path}/workspace');
    final cacheDir = Directory(
      '${workspace.path}/script_recast/cache',
    )..createSync(recursive: true);
    final sourceRoot = Directory('${tempRoot.path}/source')..createSync();
    final storyRoot = Directory('${sourceRoot.path}/story')..createSync();
    final cacheFile = File('${cacheDir.path}/script-dynamic-role.json');
    cacheFile.writeAsStringSync(
      jsonEncode(_dynamicRoleCache(storyRoot.path)),
    );

    final result = await Process.run(
      'node',
      [
        'tool/apply_ntr_story_target_mapping_offline.mjs',
        '--workspace',
        workspace.path,
        '--source-root',
        sourceRoot.path,
        '--backup-dir',
        '${tempRoot.path}/backup',
        '--report',
        '${tempRoot.path}/report.json',
        '--apply',
      ],
      workingDirectory: Directory.current.path,
    );

    expect(
      result.exitCode,
      0,
      reason: 'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
    );
    final updated =
        jsonDecode(cacheFile.readAsStringSync()) as Map<String, dynamic>;
    final mapping = updated['mapping'] as Map<String, dynamic>;
    final replacements =
        (mapping['rolePromptReplacements'] as List).cast<Map>();
    final replacement = replacements.single;
    final rules = (replacement['rules'] as List).cast<Map>();

    expect(replacement['targetCharacterId'], 'legacy-character-sheet-r14');
    expect(
        replacement['targetIdentityPrompt'], isNot(contains('black_jacket')));
    expect(
      rules.any(
        (rule) =>
            rule['action'] == 'replace' &&
            (rule['targetPrompt'] as String).contains('pepe_(arknights)') &&
            (rule['targetPrompt'] as String).contains('loli, girl, cat_girl') &&
            (rule['sourceTerms'] as List).cast<Map>().any(
                  (term) =>
                      term['category'] == 'character' && term['text'] == 'girl',
                ),
      ),
      isTrue,
      reason: 'A generic-only role still needs an explicit identity rule.',
    );
    final redJacketRule = rules.singleWhere(
      (rule) => (rule['sourceTerms'] as List).cast<Map>().any(
            (term) => term['text'] == 'red jacket',
          ),
    );
    expect(redJacketRule['action'], isNull);
    expect(redJacketRule['targetPrompt'], isNull);
    final stage =
        ((mapping['roleAssemblies'] as List).single as Map)['stages'] as List;
    final mappedStage = stage.single as Map;
    expect(mappedStage['targetCharacterId'], 'legacy-character-sheet-r14');
    expect(mappedStage['targetUpperOutfitId'], isNull);
    expect(mappedStage['targetLowerOutfitId'], isNull);
    expect(mappedStage['preservedParts'], contains('upperClothing'));
    expect(mapping['roleSwaps'], isEmpty);
    expect(updated['updatedAt'], '2026-07-10T00:00:00.000Z');
  });

  test('requested point mappings preserve clothes and merge compatible traits',
      () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'script-recast-requested-mapping-test-',
    );
    addTearDown(() async {
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });

    final workspace = Directory('${tempRoot.path}/workspace');
    final cacheDir = Directory(
      '${workspace.path}/script_recast/cache',
    )..createSync(recursive: true);
    final sourceRoot = Directory('${tempRoot.path}/source')..createSync();
    final storyRoot = Directory('${sourceRoot.path}/story')..createSync();
    final cacheFile = File('${cacheDir.path}/script-requested-rules.json');
    final fixture = _requestedRuleCache(storyRoot.path);
    final beforeMaleAiRole = jsonEncode(
      ((fixture['aiRoleExtraction'] as Map)['roles'] as List)
          .cast<Map>()
          .singleWhere((role) => role['source_role_id'] == 'role-shota'),
    );
    final beforeMaleReplacement = jsonEncode(
      ((fixture['mapping'] as Map)['rolePromptReplacements'] as List)
          .cast<Map>()
          .singleWhere((role) => role['sourceRoleId'] == 'role-shota'),
    );
    final beforeSharedAssembly = jsonEncode(
      ((fixture['mapping'] as Map)['roleAssemblies'] as List)
          .cast<Map>()
          .singleWhere(
            (assembly) =>
                assembly['sourceRoleId'] ==
                'role-reviewed-evidence-base-shared',
          ),
    );
    cacheFile.writeAsStringSync(jsonEncode(fixture));

    final result = await Process.run(
      'node',
      [
        'tool/apply_ntr_story_target_mapping_offline.mjs',
        '--workspace',
        workspace.path,
        '--source-root',
        sourceRoot.path,
        '--cache-file',
        cacheFile.uri.pathSegments.last,
        '--backup-dir',
        '${tempRoot.path}/backup',
        '--report',
        '${tempRoot.path}/report.json',
        '--apply',
      ],
      workingDirectory: Directory.current.path,
    );

    expect(
      result.exitCode,
      0,
      reason: 'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
    );
    final updated =
        jsonDecode(cacheFile.readAsStringSync()) as Map<String, dynamic>;
    final mapping = updated['mapping'] as Map<String, dynamic>;
    final replacement = (mapping['rolePromptReplacements'] as List)
        .cast<Map>()
        .singleWhere((item) => item['sourceRoleId'] == 'role-ayaka');
    final rules = (replacement['rules'] as List).cast<Map>();

    Map ruleFor(String sourceText) => rules.singleWhere(
          (rule) => (rule['sourceTerms'] as List).cast<Map>().any(
                (term) => term['text'] == sourceText,
              ),
        );

    expect(replacement['targetCharacterId'], 'legacy-character-sheet-r14');
    expect(
      ruleFor('kamisato ayaka')['targetPrompt'],
      'pepe_(arknights), 1.5:: cat_ears ::, -3:: hood ::, '
      '-3:: wearing hood ::, -3:: animal hood ::, '
      '2:: lotus_flower_headdress ::',
    );
    expect(ruleFor('girl')['targetPrompt'], 'loli, girl, cat_girl');
    expect(
      ruleFor('hair ribbon')['targetPrompt'],
      'animal_ear_fluff, animal_ears',
    );
    expect(
      ruleFor('fake animal ears')['targetPrompt'],
      'animal_ear_fluff, animal_ears',
    );
    for (final sourceText in [
      'tress ribbon',
      'no hair ornament',
      'no hat',
      'no ponytail',
    ]) {
      final deleteRule = ruleFor(sourceText);
      expect(deleteRule['action'], 'delete');
      expect(
        (deleteRule['sourceTerms'] as List)
            .cast<Map>()
            .map((term) => term['text'])
            .toList(),
        [sourceText],
      );
    }
    expect(ruleFor('black panties')['targetPrompt'], 'white panties');
    expect(ruleFor('black bikini')['targetPrompt'], 'pink bikini');
    expect(ruleFor('black babydoll')['targetPrompt'], 'white babydoll');
    expect(ruleFor('purple bikini')['targetPrompt'], 'pink bikini');
    expect(ruleFor('red swimsuit')['targetPrompt'], 'pink swimsuit');
    expect(ruleFor('aqua bra')['targetPrompt'], 'white bra');
    expect(ruleFor('red babydoll')['targetPrompt'], 'white babydoll');
    expect(ruleFor('beige lingerie')['targetPrompt'], 'white lingerie');
    expect(
      ruleFor('crotchless panties')['targetPrompt'],
      'crotchless panties, white panties',
    );
    expect(ruleFor('white panties')['action'], isNull);
    expect(ruleFor('bow panties')['action'], isNull);
    expect(ruleFor('pink bikini')['action'], isNull);
    expect(ruleFor('bikini aside')['action'], isNull);
    expect(ruleFor('no panties')['action'], isNull);
    expect(ruleFor('highleg thong leotard')['action'], isNull);
    expect(ruleFor('red jacket')['action'], isNull);
    expect(ruleFor('bunnysuit')['action'], isNull);
    expect(ruleFor('black lace dress')['action'], isNull);
    expect(ruleFor('shoulder armor')['action'], isNull);
    expect(ruleFor('shoulder armor')['targetPrompt'], isNull);
    expect(ruleFor('black gloves')['action'], isNull);
    expect(ruleFor('black gloves')['targetPrompt'], isNull);
    expect(ruleFor('ripped bra')['targetPrompt'], 'ripped bra, white bra');
    expect(ruleFor('torn bra')['targetPrompt'], 'torn bra, white bra');

    final colorHairRule = ruleFor('blue hair');
    expect(colorHairRule['targetPrompt'], 'long_hair');
    expect(
      (colorHairRule['sourceTerms'] as List)
          .cast<Map>()
          .map((term) => term['text'])
          .toSet(),
      {'blue hair'},
    );
    final mergedHairStyleRule = ruleFor('long hair');
    expect(mergedHairStyleRule['targetPrompt'], 'long_hair');
    expect(
      (mergedHairStyleRule['sourceTerms'] as List)
          .cast<Map>()
          .map((term) => term['text'])
          .toSet(),
      {'long hair', 'braids', 'straight hair'},
    );
    expect(ruleFor('one side up')['targetPrompt'], 'long_hair');
    expect(ruleFor('messy hair')['action'], isNull);
    expect(ruleFor('messy hair')['targetPrompt'], isNull);
    final mergedArmpitRule = ruleFor('armpits');
    expect(mergedArmpitRule['action'], isNull);
    expect(
      (mergedArmpitRule['sourceTerms'] as List)
          .cast<Map>()
          .map((term) => term['text'])
          .toSet(),
      {'armpits', 'armpts'},
    );
    final mergedTonguePiercingRule = ruleFor('tongue piercing');
    final mergedTonguePiercingTerm =
        (mergedTonguePiercingRule['sourceTerms'] as List).cast<Map>().single;
    expect(mergedTonguePiercingTerm['frameIndexes'], [1, 2]);
    expect(mergedTonguePiercingTerm['sourceOccurrences'], [
      {'frameIndex': 1, 'sourceLocation': 'slot-0 prompt'},
      {'frameIndex': 2, 'sourceLocation': 'slot-0 prompt'},
    ]);
    expect(ruleFor('curvy')['action'], 'delete');
    final curvyMappingTerm =
        (ruleFor('curvy')['sourceTerms'] as List).cast<Map>().single;
    expect(curvyMappingTerm['frameIndexes'], [1]);
    final aiRole = ((updated['aiRoleExtraction'] as Map)['roles'] as List)
        .cast<Map>()
        .singleWhere((item) => item['source_role_id'] == 'role-ayaka');
    final addedGirlTerm = (aiRole['prompt_terms'] as List)
        .cast<Map>()
        .singleWhere((term) => term['text'] == 'girl');
    expect(addedGirlTerm['source_location'], 'slot-0 prompt');
    expect(addedGirlTerm['frame_indexes'], [1, 2]);
    final curvyAiTerm = (aiRole['prompt_terms'] as List)
        .cast<Map>()
        .singleWhere((term) => term['text'] == 'curvy');
    expect(curvyAiTerm['frame_indexes'], [1]);
    final report = jsonDecode(
      File('${tempRoot.path}/report.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    expect(report['multi_term_delete_rules_split'], 1);
    expect(report['delete_term_rules_written'], 3);
    expect(report['semantic_alias_rules_merged'], 2);
    expect(report['underwear_color_rules_split'], 1);
    expect(
        report['prompt_term_frame_scopes_repaired'], greaterThanOrEqualTo(2));

    final idempotenceResult = await Process.run(
      'node',
      [
        'tool/apply_ntr_story_target_mapping_offline.mjs',
        '--workspace',
        workspace.path,
        '--source-root',
        sourceRoot.path,
        '--cache-file',
        cacheFile.uri.pathSegments.last,
        '--report',
        '${tempRoot.path}/idempotence-report.json',
      ],
      workingDirectory: Directory.current.path,
    );
    expect(
      idempotenceResult.exitCode,
      0,
      reason:
          'stdout:\n${idempotenceResult.stdout}\nstderr:\n${idempotenceResult.stderr}',
    );
    final idempotenceReport = jsonDecode(
      File('${tempRoot.path}/idempotence-report.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    expect(idempotenceReport['files_changed'], 0);

    final maleReplacement = (mapping['rolePromptReplacements'] as List)
        .cast<Map>()
        .singleWhere((item) => item['sourceRoleId'] == 'role-shota');
    final malePantiesRule =
        (maleReplacement['rules'] as List).cast<Map>().singleWhere(
              (rule) => (rule['sourceTerms'] as List)
                  .cast<Map>()
                  .any((term) => term['text'] == 'male black panties'),
            );
    expect(maleReplacement['targetCharacterId'], isNull);
    expect(malePantiesRule['action'], isNull);
    expect(malePantiesRule['targetPrompt'], isNull);
    expect(jsonEncode(maleReplacement), beforeMaleReplacement);
    final maleAiRole = ((updated['aiRoleExtraction'] as Map)['roles'] as List)
        .cast<Map>()
        .singleWhere((role) => role['source_role_id'] == 'role-shota');
    expect(jsonEncode(maleAiRole), beforeMaleAiRole);
    final sharedAssembly = (mapping['roleAssemblies'] as List)
        .cast<Map>()
        .singleWhere(
          (assembly) =>
              assembly['sourceRoleId'] == 'role-reviewed-evidence-base-shared',
        );
    expect(jsonEncode(sharedAssembly), beforeSharedAssembly);

    final animalReplacement = (mapping['rolePromptReplacements'] as List)
        .cast<Map>()
        .singleWhere((item) => item['sourceRoleId'] == 'role-black-dog');
    final animalRule = (animalReplacement['rules'] as List).cast<Map>().single;
    expect(animalReplacement['targetCharacterId'], isNull);
    expect(animalRule['action'], isNull);
    expect(animalRule['targetPrompt'], isNull);

    final auditResult = await Process.run(
      'node',
      [
        'tool/audit_script_recast_target_mapping_20260721.mjs',
        '--cache-dir',
        cacheDir.path,
        '--cache-file',
        cacheFile.uri.pathSegments.last,
        '--report',
        '${tempRoot.path}/audit.json',
      ],
      workingDirectory: Directory.current.path,
    );
    expect(
      auditResult.exitCode,
      0,
      reason: 'stdout:\n${auditResult.stdout}\nstderr:\n${auditResult.stderr}',
    );
    final audit =
        jsonDecode(File('${tempRoot.path}/audit.json').readAsStringSync())
            as Map<String, dynamic>;
    expect(audit['split_semantic_alias_rule_count'], 0);
    expect(audit['violation_count'], 0);
  });

  test('underwear color only mode does not rewrite identity or stages',
      () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'script-recast-underwear-color-only-test-',
    );
    addTearDown(() async {
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });

    final workspace = Directory('${tempRoot.path}/workspace');
    final cacheDir = Directory(
      '${workspace.path}/script_recast/cache',
    )..createSync(recursive: true);
    final sourceRoot = Directory('${tempRoot.path}/source')..createSync();
    final storyRoot = Directory('${sourceRoot.path}/story')..createSync();
    final cacheFile = File('${cacheDir.path}/script-color-only.json');
    final fixture = _requestedRuleCache(storyRoot.path);
    ((fixture['aiRoleExtraction'] as Map)['roles'] as List).add({
      'source_role_id': 'role-commander-nikke',
      'source_kind': 'slot',
      'display_name': 'commander_(nikke) / 指挥官',
      'canonical_name': 'commander',
      'raw_identity_tags': [
        'boy',
        'commander_(nikke)',
        'faceless male',
        'mature male',
      ],
      'frame_indexes': [1, 2],
      'appearances': [
        {
          'source_id': 'slot-2',
          'source_kind': 'slot',
          'frame_indexes': [1, 2],
        },
      ],
      'stages': <Map<String, dynamic>>[],
      'prompt_terms': [
        {
          'id': 'male-black-swimsuit',
          'text': 'male black swimsuit',
          'category': 'clothing',
          'frame_indexes': [1, 2],
        },
      ],
    });
    (((fixture['mapping'] as Map)['rolePromptReplacements']) as List).add({
      'sourceRoleId': 'role-commander-nikke',
      'displayLabel': 'commander_(nikke) / 指挥官',
      'sourcePreview': 'male black swimsuit',
      'rules': [
        {
          'id': 'rule-male-black-swimsuit',
          'sourceTerms': [
            {
              'id': 'male-black-swimsuit',
              'text': 'male black swimsuit',
              'category': 'clothing',
              'frameIndexes': [1, 2],
            },
          ],
        },
      ],
    });
    final ayakaFixtureReplacement =
        ((((fixture['mapping'] as Map)['rolePromptReplacements']) as List)
                .cast<Map>())
            .singleWhere((item) => item['sourceRoleId'] == 'role-ayaka');
    (ayakaFixtureReplacement['rules'] as List).addAll(<Map<String, Object>>[
      {
        'id': 'rule-character-swimsuit-identity',
        'sourceTerms': [
          {
            'id': 'character-swimsuit-identity',
            'text': 'wakamo (swimsuit) (blue_archive)',
            'category': 'character',
            'frameIndexes': [1, 2],
          },
        ],
        'action': 'replace',
        'targetPrompt': 'pepe_(arknights)',
      },
      {
        'id': 'rule-stale-frame-string-bikini',
        'sourceTerms': [
          {
            'id': 'stale-frame-string-bikini',
            'text': 'string bikini',
            'category': 'clothing',
            'frameIndexes': [1, 2, 99],
            'sourceOccurrences': [
              {'frameIndex': 1, 'sourceLocation': 'slot-0 prompt'},
              {'frameIndex': 2, 'sourceLocation': 'slot-0 prompt'},
            ],
          },
        ],
      },
      {
        'id': 'rule-exact-frame-white-bikini',
        'sourceTerms': [
          {
            'id': 'exact-frame-white-bikini',
            'text': 'white bikini',
            'category': 'clothing',
            'frameIndexes': [1, 2],
            'sourceOccurrences': [
              {'frameIndex': 1, 'sourceLocation': 'slot-0 prompt'},
              {'frameIndex': 2, 'sourceLocation': 'slot-0 prompt'},
            ],
          },
        ],
      },
    ]);
    final beforeMapping = jsonEncode(fixture['mapping']);
    final beforeAssemblies = jsonEncode(
      (fixture['mapping'] as Map)['roleAssemblies'],
    );
    cacheFile.writeAsStringSync(jsonEncode(fixture));

    final result = await Process.run(
      'node',
      [
        'tool/apply_ntr_story_target_mapping_offline.mjs',
        '--workspace',
        workspace.path,
        '--source-root',
        sourceRoot.path,
        '--cache-file',
        cacheFile.uri.pathSegments.last,
        '--backup-dir',
        '${tempRoot.path}/backup',
        '--report',
        '${tempRoot.path}/report.json',
        '--underwear-color-only',
        '--apply',
      ],
      workingDirectory: Directory.current.path,
    );
    expect(
      result.exitCode,
      0,
      reason: 'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
    );

    final updated =
        jsonDecode(cacheFile.readAsStringSync()) as Map<String, dynamic>;
    final mapping = updated['mapping'] as Map<String, dynamic>;
    final ayakaReplacement = (mapping['rolePromptReplacements'] as List)
        .cast<Map>()
        .singleWhere((item) => item['sourceRoleId'] == 'role-ayaka');
    final rules = (ayakaReplacement['rules'] as List).cast<Map>();
    Map ruleFor(String text) => rules.singleWhere(
          (rule) => (rule['sourceTerms'] as List)
              .cast<Map>()
              .any((term) => term['text'] == text),
        );
    expect(ruleFor('red swimsuit')['targetPrompt'], 'pink swimsuit');
    expect(ruleFor('white panties')['action'], isNull);
    expect(ruleFor('bikini aside')['action'], isNull);
    expect(ruleFor('red jacket')['action'], isNull);
    expect(ruleFor('curvy')['action'], 'delete');
    expect(
      ruleFor('wakamo (swimsuit) (blue_archive)')['targetPrompt'],
      'pepe_(arknights)',
    );
    expect(ruleFor('string bikini')['action'], isNull);
    expect(ruleFor('string bikini')['targetPrompt'], isNull);
    expect(jsonEncode(mapping['roleAssemblies']), beforeAssemblies);

    final maleReplacement = (mapping['rolePromptReplacements'] as List)
        .cast<Map>()
        .singleWhere((item) => item['sourceRoleId'] == 'role-shota');
    final malePantiesRule =
        (maleReplacement['rules'] as List).cast<Map>().single;
    expect(malePantiesRule['action'], isNull);
    expect(malePantiesRule['targetPrompt'], isNull);

    final commaSeparatedMaleReplacement =
        (mapping['rolePromptReplacements'] as List).cast<Map>().singleWhere(
              (item) => item['sourceRoleId'] == 'role-commander-nikke',
            );
    final maleSwimsuitRule =
        (commaSeparatedMaleReplacement['rules'] as List).cast<Map>().single;
    expect(maleSwimsuitRule['action'], isNull);
    expect(maleSwimsuitRule['targetPrompt'], isNull);

    final before = jsonDecode(beforeMapping) as Map<String, dynamic>;
    final beforeAyaka = (before['rolePromptReplacements'] as List)
        .cast<Map>()
        .singleWhere((item) => item['sourceRoleId'] == 'role-ayaka');
    expect(
      ayakaReplacement['targetCharacterId'],
      beforeAyaka['targetCharacterId'],
    );
    expect(
      ayakaReplacement['targetIdentityPrompt'],
      beforeAyaka['targetIdentityPrompt'],
    );
  });

  test(
      'hair style only mode uses character-card styles and preserves hair states',
      () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'script-recast-hair-style-only-test-',
    );
    addTearDown(() async {
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });

    final workspace = Directory('${tempRoot.path}/workspace');
    final cacheDir = Directory(
      '${workspace.path}/script_recast/cache',
    )..createSync(recursive: true);
    final libraryDir = Directory('${workspace.path}/library')
      ..createSync(recursive: true);
    File('${libraryDir.path}/characters.json').writeAsStringSync(jsonEncode([
      {
        'id': 'legacy-character-sheet-r14',
        'traits': {
          'front_upper': 'brown_hair, long_hair, hair_ornament, animal_ears',
        },
        'defaultOutfitId': 'default-outfit',
        'outfits': [
          {
            'id': 'default-outfit',
            'partTags': {
              'upperBodyTags': ['long_hair', 'brown_hair'],
            },
          },
        ],
      },
      {
        'id': 'legacy-character-sheet-r29',
        'traits': {
          'front_upper': 'fox_ears, twintails, short_hair, hair_between_eyes',
        },
        'defaultOutfitId': 'default-outfit',
        'outfits': [
          {
            'id': 'default-outfit',
            'partTags': {
              'upperBodyTags': [
                'double_bun',
                'hair_bun',
                'hair_between_eyes',
                'medium_hair',
              ],
            },
          },
        ],
      },
    ]));
    final sourceRoot = Directory('${tempRoot.path}/source')..createSync();
    final storyRoot = Directory('${sourceRoot.path}/story')..createSync();
    final cacheFile = File('${cacheDir.path}/script-hair-only.json');
    final fixture = _requestedRuleCache(storyRoot.path);
    final mapping = fixture['mapping'] as Map<String, dynamic>;
    final replacement = (mapping['rolePromptReplacements'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((item) => item['sourceRoleId'] == 'role-ayaka');
    replacement['targetCharacterId'] = 'legacy-character-sheet-r14';
    replacement['targetIdentityPrompt'] = 'existing identity target';
    final mixedTerms = [
      ('alternate-hairstyle', 'alternate hairstyle', 'upperBody'),
      ('twin-drills', 'twin drills', 'upperBody'),
      ('crown-braid', 'crown braid', 'upperBody'),
      ('hair-spread-out', 'hair spread out', 'upperBody'),
      ('wet-hair', 'wet hair', 'upperBody'),
      ('adjusting-hair', 'adjusting hair', 'upperBody'),
      ('cum-on-hair', 'cum on hair', 'upperBody'),
      ('pink-hair', 'pink hair', 'upperBody'),
      ('hair-flower', 'hair flower', 'accessory'),
      ('pubic-hair', 'brown pubic hair', 'lowerBody'),
    ];
    (replacement['rules'] as List).add({
      'id': 'rule-mixed-hair-policy',
      'sourceTerms': [
        for (final term in mixedTerms)
          {
            'id': term.$1,
            'text': term.$2,
            'category': term.$3,
            'frameIndexes': [1, 2],
          },
      ],
      'action': 'replace',
      'targetPrompt': 'preexisting non-hair target',
    });
    final role = ((fixture['aiRoleExtraction'] as Map)['roles'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((item) => item['source_role_id'] == 'role-ayaka');
    role['prompt_terms'] = [
      ...(role['prompt_terms'] as List),
      for (final term in mixedTerms)
        <String, dynamic>{
          'id': term.$1,
          'text': term.$2,
          'category': term.$3,
          'frame_indexes': [1, 2],
        },
    ];
    final roles = ((fixture['aiRoleExtraction'] as Map)['roles'] as List);
    (fixture['aiRoleExtraction'] as Map)['roles'] = [
      ...roles,
      <String, dynamic>{
        'source_role_id': 'role-r29-source',
        'display_name': 'r29 source / 测试女性',
        'canonical_name': 'r29 source',
        'raw_identity_tags': ['girl'],
        'frame_indexes': [1],
        'appearances': <Map<String, dynamic>>[],
        'stages': <Map<String, dynamic>>[],
        'prompt_terms': [
          {
            'id': 'r29-long-hair',
            'text': 'long hair',
            'category': 'upperBody',
            'frame_indexes': [1],
          },
        ],
      },
    ];
    (mapping['rolePromptReplacements'] as List).add({
      'sourceRoleId': 'role-r29-source',
      'displayLabel': 'r29 source / 测试女性',
      'targetCharacterId': 'legacy-character-sheet-r29',
      'targetIdentityPrompt': 'existing r29 identity target',
      'rules': [
        {
          'id': 'rule-r29-long-hair',
          'sourceTerms': [
            {
              'id': 'r29-long-hair',
              'text': 'long hair',
              'category': 'upperBody',
              'frameIndexes': [1],
            },
          ],
        },
      ],
    });
    final frames = ((fixture['scriptSnapshot'] as Map)['frames'] as List)
        .cast<Map<String, dynamic>>();
    for (final frame in frames) {
      final parsed = frame['parsed'] as Map<String, dynamic>;
      final captions = (parsed['charCaptions'] as List).cast<String>();
      captions[0] = '${captions[0]}, single_side_bun';
      parsed['charCaptions'] = captions;
    }
    final beforeAssemblies = jsonEncode(mapping['roleAssemblies']);
    final maleBefore = jsonEncode(
      (mapping['rolePromptReplacements'] as List)
          .cast<Map>()
          .singleWhere((item) => item['sourceRoleId'] == 'role-shota'),
    );
    cacheFile.writeAsStringSync(jsonEncode(fixture));

    final result = await Process.run(
      'node',
      [
        'tool/apply_ntr_story_target_mapping_offline.mjs',
        '--workspace',
        workspace.path,
        '--source-root',
        sourceRoot.path,
        '--cache-file',
        cacheFile.uri.pathSegments.last,
        '--character-library',
        '${libraryDir.path}/characters.json',
        '--report',
        '${tempRoot.path}/report.json',
        '--hair-style-only',
        '--apply',
      ],
      workingDirectory: Directory.current.path,
    );
    expect(
      result.exitCode,
      0,
      reason: 'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
    );

    final updated =
        jsonDecode(cacheFile.readAsStringSync()) as Map<String, dynamic>;
    final updatedMapping = updated['mapping'] as Map<String, dynamic>;
    final updatedReplacement =
        (updatedMapping['rolePromptReplacements'] as List)
            .cast<Map>()
            .singleWhere((item) => item['sourceRoleId'] == 'role-ayaka');
    final rules = (updatedReplacement['rules'] as List).cast<Map>();
    Map ruleFor(String text) => rules.singleWhere(
          (rule) => (rule['sourceTerms'] as List)
              .cast<Map>()
              .any((term) => term['text'] == text),
        );

    for (final style in [
      'alternate hairstyle',
      'twin drills',
      'crown braid',
      'single side bun',
    ]) {
      expect(ruleFor(style)['action'], 'replace');
      expect(ruleFor(style)['targetPrompt'], 'long_hair');
    }
    for (final state in [
      'hair spread out',
      'wet hair',
      'messy hair',
      'adjusting hair',
      'cum on hair',
    ]) {
      expect(ruleFor(state)['action'], isNull);
      expect(ruleFor(state)['targetPrompt'], isNull);
    }
    for (final untouched in ['pink hair', 'hair flower', 'brown pubic hair']) {
      expect(ruleFor(untouched)['action'], 'replace');
      expect(ruleFor(untouched)['targetPrompt'], 'preexisting non-hair target');
    }
    expect(
        updatedReplacement['targetIdentityPrompt'], 'existing identity target');
    final r29Replacement = (updatedMapping['rolePromptReplacements'] as List)
        .cast<Map>()
        .singleWhere((item) => item['sourceRoleId'] == 'role-r29-source');
    final r29Rule = (r29Replacement['rules'] as List).cast<Map>().single;
    expect(
      r29Rule['targetPrompt'],
      'twintails, short_hair, hair_between_eyes',
      reason:
          'Character-level hairstyle must beat an outfit-specific hair bun.',
    );
    expect(jsonEncode(updatedMapping['roleAssemblies']), beforeAssemblies);
    expect(
      jsonEncode((updatedMapping['rolePromptReplacements'] as List)
          .cast<Map>()
          .singleWhere((item) => item['sourceRoleId'] == 'role-shota')),
      maleBefore,
    );
  });

  test('existing character-category girl evidence is reused', () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'script-recast-existing-girl-test-',
    );
    addTearDown(() async {
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });

    final workspace = Directory('${tempRoot.path}/workspace');
    final cacheDir = Directory(
      '${workspace.path}/script_recast/cache',
    )..createSync(recursive: true);
    final sourceRoot = Directory('${tempRoot.path}/source')..createSync();
    final storyRoot = Directory('${sourceRoot.path}/story')..createSync();
    final cacheFile = File('${cacheDir.path}/script-existing-girl.json');
    final fixture = _requestedRuleCache(storyRoot.path);
    final aiRole = ((fixture['aiRoleExtraction'] as Map)['roles'] as List)
        .cast<Map>()
        .singleWhere((item) => item['source_role_id'] == 'role-ayaka');
    (aiRole['prompt_terms'] as List).add({
      'id': 'existing-character-girl',
      'text': 'girl',
      'category': 'character',
      'source_phrase': 'girl',
      'source_location': '',
      'frame_indexes': <int>[],
    });
    final replacement =
        (((fixture['mapping'] as Map)['rolePromptReplacements'] as List)
            .cast<Map>()
            .singleWhere((item) => item['sourceRoleId'] == 'role-ayaka'));
    (replacement['rules'] as List).add({
      'id': 'rule-existing-character-girl',
      'sourceTerms': [
        {
          'id': 'existing-character-girl',
          'text': 'girl',
          'category': 'character',
          'sourcePhrase': 'girl',
          'sourceLocation': '',
          'frameIndexes': <int>[],
        },
      ],
    });
    cacheFile.writeAsStringSync(jsonEncode(fixture));

    final reportFile = File('${tempRoot.path}/report.json');
    final result = await Process.run(
      'node',
      [
        'tool/apply_ntr_story_target_mapping_offline.mjs',
        '--workspace',
        workspace.path,
        '--source-root',
        sourceRoot.path,
        '--cache-file',
        cacheFile.uri.pathSegments.last,
        '--backup-dir',
        '${tempRoot.path}/backup',
        '--report',
        reportFile.path,
        '--apply',
      ],
      workingDirectory: Directory.current.path,
    );
    expect(
      result.exitCode,
      0,
      reason: 'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
    );

    final updated =
        jsonDecode(cacheFile.readAsStringSync()) as Map<String, dynamic>;
    final updatedRole = ((updated['aiRoleExtraction'] as Map)['roles'] as List)
        .cast<Map>()
        .singleWhere((item) => item['source_role_id'] == 'role-ayaka');
    final girlAiTerms = (updatedRole['prompt_terms'] as List)
        .cast<Map>()
        .where((term) => term['text'] == 'girl')
        .toList();
    expect(girlAiTerms, hasLength(1));
    expect(girlAiTerms.single['category'], 'character');
    expect(girlAiTerms.single['source_location'], 'slot-0 prompt');
    expect(girlAiTerms.single['frame_indexes'], [1, 2]);
    expect(girlAiTerms.single['source_occurrences'], [
      {'frame_index': 1, 'source_location': 'slot-0 prompt'},
      {'frame_index': 2, 'source_location': 'slot-0 prompt'},
    ]);
    final updatedReplacement =
        (((updated['mapping'] as Map)['rolePromptReplacements'] as List)
            .cast<Map>()
            .singleWhere((item) => item['sourceRoleId'] == 'role-ayaka'));
    final girlRules = (updatedReplacement['rules'] as List)
        .cast<Map>()
        .where(
          (rule) => (rule['sourceTerms'] as List)
              .cast<Map>()
              .any((term) => term['text'] == 'girl'),
        )
        .toList();
    expect(girlRules, hasLength(1));
    expect(girlRules.single['targetPrompt'], 'loli, girl, cat_girl');
    final girlMappingTerm =
        (girlRules.single['sourceTerms'] as List).cast<Map>().single;
    expect(girlMappingTerm['sourceLocation'], 'slot-0 prompt');
    expect(girlMappingTerm['frameIndexes'], [1, 2]);
    expect(girlMappingTerm['sourceOccurrences'], [
      {'frameIndex': 1, 'sourceLocation': 'slot-0 prompt'},
      {'frameIndex': 2, 'sourceLocation': 'slot-0 prompt'},
    ]);
    final report =
        jsonDecode(reportFile.readAsStringSync()) as Map<String, dynamic>;
    expect(report['generic_girl_ai_terms_added'], 0);
    expect(report['generic_girl_ai_terms_updated'], 1);
    expect(report['generic_girl_mapping_rules_added'], 0);
    expect(report['generic_girl_mapping_terms_updated'], 1);
  });

  test('the longest female role receives Pepe before cameo roles', () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'script-recast-primary-role-mapping-test-',
    );
    addTearDown(() async {
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });

    final workspace = Directory('${tempRoot.path}/workspace');
    final cacheDir = Directory(
      '${workspace.path}/script_recast/cache',
    )..createSync(recursive: true);
    final sourceRoot = Directory('${tempRoot.path}/source')..createSync();
    final storyRoot = Directory('${sourceRoot.path}/story')..createSync();
    final cacheFile = File('${cacheDir.path}/script-primary-role.json');
    cacheFile.writeAsStringSync(
      jsonEncode(_primaryRoleCache(storyRoot.path)),
    );

    final result = await Process.run(
      'node',
      [
        'tool/apply_ntr_story_target_mapping_offline.mjs',
        '--workspace',
        workspace.path,
        '--source-root',
        sourceRoot.path,
        '--cache-file',
        cacheFile.uri.pathSegments.last,
        '--report',
        '${tempRoot.path}/report.json',
        '--apply',
      ],
      workingDirectory: Directory.current.path,
    );

    expect(result.exitCode, 0, reason: result.stderr.toString());
    final updated =
        jsonDecode(cacheFile.readAsStringSync()) as Map<String, dynamic>;
    final replacements =
        ((updated['mapping'] as Map)['rolePromptReplacements'] as List)
            .cast<Map>();
    final targets = {
      for (final replacement in replacements)
        replacement['sourceRoleId']: replacement['targetCharacterId'],
    };
    expect(targets['role-main'], 'legacy-character-sheet-r14');
    expect(targets['role-cameo'], isNot('legacy-character-sheet-r14'));
    const genericProfiles = {
      'legacy-character-sheet-r13': 'loli, girl, fox_girl',
      'legacy-character-sheet-r29': 'loli, girl, fox_girl',
      'legacy-character-sheet-r10': 'loli, girl, cat_girl',
      'legacy-character-sheet-r1': 'loli, girl, sheep_girl',
      'legacy-character-sheet-r3': 'loli, girl',
    };
    final cameoReplacement = replacements.singleWhere(
      (replacement) => replacement['sourceRoleId'] == 'role-cameo',
    );
    final cameoGirlRule =
        (cameoReplacement['rules'] as List).cast<Map>().singleWhere(
              (rule) => (rule['sourceTerms'] as List)
                  .cast<Map>()
                  .any((term) => term['text'] == 'girl'),
            );
    expect(
      cameoGirlRule['targetPrompt'],
      genericProfiles[targets['role-cameo']],
    );
  });

  test('companion target cards vary deterministically across scripts',
      () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'script-recast-diverse-target-test-',
    );
    addTearDown(() async {
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });

    final workspace = Directory('${tempRoot.path}/workspace');
    final cacheDir = Directory('${workspace.path}/script_recast/cache')
      ..createSync(recursive: true);
    final libraryDir = Directory('${workspace.path}/library')
      ..createSync(recursive: true);
    Map<String, dynamic> card(
      String id,
      String name, {
      required String identity,
      required String upper,
      List<String> imageRefs = const ['preview.png'],
    }) =>
        {
          'id': id,
          'name': name,
          'anchorTags': [identity],
          'imageRefs': imageRefs,
          'traits': {
            'front_full': identity,
            'front_upper': upper,
            'front_lower': '',
          },
          'defaultOutfitId': 'default-outfit',
          'outfits': [
            {
              'id': 'default-outfit',
              'partTags': {
                'upperClothingTags': ['white dress'],
                'lowerClothingTags': ['shoes'],
              },
            },
          ],
        };
    File('${libraryDir.path}/characters.json').writeAsStringSync(jsonEncode([
      card('legacy-character-sheet-r14', '佩佩',
          identity: 'pepe_(arknights)', upper: 'cat_ears, long_hair'),
      card('legacy-character-sheet-r13', '铃兰',
          identity: 'suzuran_(arknights)',
          upper: 'fox_ears, long_hair, dress_bow'),
      card('legacy-character-sheet-r29', '巫恋',
          identity: 'shamare_(arknights)', upper: 'fox_ears, short_hair'),
      card('legacy-character-sheet-r10', '莎草',
          identity: 'papyrus_(arknights)', upper: 'cat_ears, long_hair'),
      card('legacy-character-sheet-r24', '果宝',
          identity: 'guobao_(original)', upper: 'short_hair', imageRefs: []),
      card('legacy-character-sheet-r27', '露露卡',
          identity: 'luruka_(last_origin)', upper: 'cat_ears, long_hair'),
      card('legacy-character-sheet-r30', '缇缇',
          identity: 'titi_(original)',
          upper: 'cat_ears, long_hair',
          imageRefs: []),
    ]));
    final sourceRoot = Directory('${tempRoot.path}/source')..createSync();
    final storyRoot = Directory('${sourceRoot.path}/story')..createSync();
    final cacheFiles = <File>[];
    for (var index = 0; index < 8; index += 1) {
      final cache = _primaryRoleCache(storyRoot.path);
      cache['scriptId'] = 'script-diverse-$index';
      cache['scriptName'] = 'Diverse target fixture $index';
      final mapping = cache['mapping'] as Map<String, dynamic>;
      mapping['id'] = 'mapping-script-diverse-$index';
      mapping['scriptId'] = 'script-diverse-$index';
      final file = File('${cacheDir.path}/script-diverse-$index.json')
        ..writeAsStringSync(jsonEncode(cache));
      cacheFiles.add(file);
    }

    final result = await Process.run(
      'node',
      [
        'tool/apply_ntr_story_target_mapping_offline.mjs',
        '--workspace',
        workspace.path,
        '--source-root',
        sourceRoot.path,
        '--report',
        '${tempRoot.path}/report.json',
        '--apply',
      ],
      workingDirectory: Directory.current.path,
    );
    expect(result.exitCode, 0, reason: result.stderr.toString());

    final companionTargets = <String>{};
    for (final file in cacheFiles) {
      final updated =
          jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final replacements =
          ((updated['mapping'] as Map)['rolePromptReplacements'] as List)
              .cast<Map>();
      final main = replacements.singleWhere(
        (replacement) => replacement['sourceRoleId'] == 'role-main',
      );
      final cameo = replacements.singleWhere(
        (replacement) => replacement['sourceRoleId'] == 'role-cameo',
      );
      expect(main['targetCharacterId'], 'legacy-character-sheet-r14');
      expect(cameo['targetCharacterId'], isNot('legacy-character-sheet-r14'));
      companionTargets.add(cameo['targetCharacterId'] as String);
    }
    expect(companionTargets.length, greaterThanOrEqualTo(3));
    expect(
      companionTargets,
      isNot(containsAll(<String>[
        'legacy-character-sheet-r24',
        'legacy-character-sheet-r27',
        'legacy-character-sheet-r30',
      ])),
    );
    expect(
      companionTargets.intersection({
        'legacy-character-sheet-r24',
        'legacy-character-sheet-r27',
        'legacy-character-sheet-r30',
      }),
      isEmpty,
    );
    final report = jsonDecode(
      File('${tempRoot.path}/report.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    expect(
      (report['target_card_pool'] as List)
          .cast<Map>()
          .map((card) => card['id'])
          .toSet(),
      {
        'legacy-character-sheet-r14',
        'legacy-character-sheet-r13',
        'legacy-character-sheet-r29',
        'legacy-character-sheet-r10',
      },
    );
    expect(
      (report['target_card_pool_exclusions'] as List)
          .cast<Map>()
          .map((card) => card['id'])
          .toSet(),
      {
        'legacy-character-sheet-r24',
        'legacy-character-sheet-r27',
        'legacy-character-sheet-r30',
      },
    );
    final auditResult = await Process.run(
      'node',
      [
        'tool/audit_script_recast_target_mapping_20260721.mjs',
        '--cache-dir',
        cacheDir.path,
        '--character-library',
        '${libraryDir.path}/characters.json',
        '--report',
        '${tempRoot.path}/audit.json',
      ],
      workingDirectory: Directory.current.path,
    );
    expect(
      auditResult.exitCode,
      anyOf(0, 1),
      reason: auditResult.stderr.toString(),
    );
    final audit = jsonDecode(
      File('${tempRoot.path}/audit.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    expect(
      (audit['violations'] as List).cast<Map>().where((violation) =>
          violation['message'] == 'target_identity_prompt_contains_clothing'),
      isEmpty,
    );
  });
}

Map<String, dynamic> _dynamicRoleCache(String sourceRootPath) {
  return {
    'scriptId': 'script-dynamic-role',
    'scriptName': 'Dynamic role fixture',
    'sourceRootPath': sourceRootPath,
    'updatedAt': DateTime.utc(2026, 7, 10).toIso8601String(),
    'aiRoleExtraction': {
      'status': 'ready',
      'roles': [
        {
          'source_role_id': 'role-heroine',
          'source_kind': 'cross_slot',
          'display_name': 'heroine / girl',
          'raw_identity_tags': ['girl'],
          'appearances': [
            {
              'source_id': 'slot-0',
              'source_kind': 'slot',
              'frame_indexes': [1],
            },
            {
              'source_id': 'slot-1',
              'source_kind': 'slot',
              'frame_indexes': [2],
            },
          ],
          'stages': [
            {
              'stage_id': 'stage-1',
              'label': 'default',
              'frame_indexes': [1, 2],
              'identity': 'girl',
              'upper_body': '',
              'lower_body': '',
              'upper_clothing': 'red jacket',
              'lower_clothing': '',
            },
          ],
          'prompt_terms': [
            {
              'id': 'term-red-jacket',
              'text': 'red jacket',
              'category': 'upperClothing',
              'frame_indexes': [1, 2],
            },
          ],
        },
      ],
    },
    'mapping': {
      'id': 'mapping-script-dynamic-role',
      'scriptId': 'script-dynamic-role',
      'roleSwaps': [],
      'artistSwap': null,
      'rolePromptReplacements': [
        {
          'sourceRoleId': 'role-heroine',
          'displayLabel': 'Heroine',
          'sourcePreview': 'heroine, red jacket',
          'rules': [
            {
              'id': 'rule-heroine',
              'sourceTerms': [
                {
                  'id': 'term-red-jacket',
                  'text': 'red jacket',
                  'category': 'upperClothing',
                },
              ],
            },
          ],
        },
      ],
      'roleAssemblies': [
        {
          'sourceRoleId': 'role-heroine',
          'displayLabel': 'Heroine',
          'sourceAppearances': [
            {
              'sourceId': 'slot-0',
              'sourceKind': 'slot',
              'frameIndexes': [1],
            },
            {
              'sourceId': 'slot-1',
              'sourceKind': 'slot',
              'frameIndexes': [2],
            },
          ],
          'stages': [
            {
              'id': 'stage-1',
              'label': 'default',
              'frameIndexes': [1, 2],
              'sourceParts': {
                'identity': 'heroine',
                'upperClothing': 'red jacket',
              },
            },
          ],
        },
      ],
    },
  };
}

Map<String, dynamic> _requestedRuleCache(String sourceRootPath) {
  const terms = [
    ('identity-ayaka', 'kamisato ayaka', 'identity'),
    ('identity-girl', 'girl', 'identity'),
    ('body-blue-hair', 'blue hair', 'body'),
    ('body-long-hair', 'long hair', 'body'),
    ('body-braids', 'braids', 'body'),
    ('body-straight-hair', 'straight hair', 'body'),
    ('body-one-side-up', 'one side up', 'upperBody'),
    ('body-messy-hair', 'messy hair', 'body'),
    ('body-no-ponytail', 'no ponytail', 'upperBody'),
    ('body-armpits', 'armpits', 'body'),
    ('body-armpts', 'armpts', 'upperBody'),
    ('body-curvy', 'curvy', 'body'),
    ('body-shoulder-armor', 'shoulder armor', 'upperBody'),
    ('accessory-hair-ribbon', 'hair ribbon', 'accessory'),
    ('accessory-fake-animal-ears', 'fake animal ears', 'accessory'),
    ('accessory-tress-ribbon', 'tress ribbon', 'accessory'),
    ('accessory-no-hair-ornament', 'no hair ornament', 'accessory'),
    ('accessory-no-hat', 'no hat', 'accessory'),
    ('accessory-tongue-piercing', 'tongue piercing', 'accessory'),
    ('accessory-tongue-piercing-underscore', 'tongue_piercing', 'accessory'),
    ('accessory-black-gloves', 'black gloves', 'accessory'),
    ('clothing-red-jacket', 'red jacket', 'clothing'),
    ('clothing-bunnysuit', 'bunnysuit', 'clothing'),
    ('clothing-black-panties', 'black panties', 'clothing'),
    ('clothing-black-bikini', 'black bikini', 'clothing'),
    ('clothing-black-babydoll', 'black babydoll', 'clothing'),
    ('clothing-purple-bikini', 'purple bikini', 'clothing'),
    ('clothing-red-swimsuit', 'red swimsuit', 'clothing'),
    ('clothing-aqua-bra', 'aqua bra', 'clothing'),
    ('clothing-red-babydoll', 'red babydoll', 'clothing'),
    ('clothing-beige-lingerie', 'beige lingerie', 'clothing'),
    ('clothing-white-panties', 'white panties', 'clothing'),
    ('clothing-bow-panties', 'bow panties', 'clothing'),
    ('clothing-crotchless-panties', 'crotchless panties', 'clothing'),
    ('clothing-pink-bikini', 'pink bikini', 'clothing'),
    ('state-bikini-aside', 'bikini aside', 'clothingState'),
    ('state-ripped-bra', 'ripped bra', 'clothingState'),
    ('state-torn-bra', 'torn bra', 'clothingState'),
    ('state-no-panties', 'no panties', 'clothingState'),
    ('clothing-thong-leotard', 'highleg thong leotard', 'clothing'),
    ('clothing-black-lace-dress', 'black lace dress', 'clothing'),
  ];
  final promptTerms = [
    for (final term in terms.where((term) => term.$2 != 'girl'))
      {
        'id': term.$1,
        'text': term.$2,
        'category': term.$3,
        'frame_indexes': const {'ripped bra', 'torn bra'}.contains(term.$2)
            ? [1, 2, 3]
            : const {
                'black panties',
                'white panties',
                'bow panties',
              }.contains(term.$2)
                ? [1]
                : [1, 2],
        if (term.$2 == 'curvy')
          'source_occurrences': [
            {'frame_index': 1, 'source_location': 'slot-0 prompt'},
          ],
        if (term.$2 == 'armpits' || term.$2 == 'armpts')
          'source_occurrences': [
            {
              'frame_index': term.$2 == 'armpits' ? 1 : 2,
              'source_location': 'slot-0 prompt',
            },
          ],
        if (term.$2 == 'tongue piercing' || term.$2 == 'tongue_piercing')
          'source_occurrences': [
            {
              'frame_index': term.$2 == 'tongue piercing' ? 1 : 2,
              'source_location': 'slot-0 prompt',
            },
          ],
      },
  ];
  final mappingTerms = [
    for (final term in terms.where((term) => term.$2 != 'girl'))
      {
        'id': term.$1,
        'text': term.$2,
        'category': term.$3,
        'frameIndexes': const {'ripped bra', 'torn bra'}.contains(term.$2)
            ? [1, 2, 3]
            : const {
                'black panties',
                'white panties',
                'bow panties',
              }.contains(term.$2)
                ? [1]
                : [1, 2],
        if (term.$2 == 'curvy')
          'sourceOccurrences': [
            {'frameIndex': 1, 'sourceLocation': 'slot-0 prompt'},
          ],
        if (term.$2 == 'armpits' || term.$2 == 'armpts')
          'sourceOccurrences': [
            {
              'frameIndex': term.$2 == 'armpits' ? 1 : 2,
              'sourceLocation': 'slot-0 prompt',
            },
          ],
        if (term.$2 == 'tongue piercing' || term.$2 == 'tongue_piercing')
          'sourceOccurrences': [
            {
              'frameIndex': term.$2 == 'tongue piercing' ? 1 : 2,
              'sourceLocation': 'slot-0 prompt',
            },
          ],
      },
  ];
  return {
    'scriptId': 'script-requested-rules',
    'scriptName': 'Requested rule fixture',
    'sourceRootPath': sourceRootPath,
    'scriptSnapshot': {
      'frames': [
        for (final frameIndex in [1, 2])
          {
            'index': frameIndex,
            'parsed': {
              'baseCaption': '1girl, indoors',
              'charCaptions': [
                'girl, kamisato ayaka, blue hair, long hair, braids, '
                    'straight hair, one side up, armpits, armpts, curvy, '
                    'no ponytail, '
                    'shoulder armor, black gloves, '
                    'hair ribbon, fake animal ears, tress ribbon, '
                    'no hair ornament, no hat, tongue piercing, '
                    'tongue_piercing, red jacket, '
                    'bunnysuit, black bikini, black babydoll, purple bikini, '
                    'red swimsuit, aqua bra, red babydoll, beige lingerie, '
                    'crotchless panties, pink bikini, bikini aside, '
                    'ripped bra, torn bra, '
                    'no panties, highleg thong leotard, '
                    '${frameIndex == 1 ? 'black panties, white panties, bow panties, ' : ''}'
                    'black lace dress',
                'boy, muscular male, male black panties',
              ],
            },
          },
      ],
    },
    'aiRoleExtraction': {
      'status': 'ready',
      'roles': [
        {
          'source_role_id': 'role-ayaka',
          'source_kind': 'slot',
          'display_name': 'kamisato ayaka / 神里绫华',
          'canonical_name': 'kamisato ayaka',
          'raw_identity_tags': ['kamisato ayaka', 'girl'],
          'frame_indexes': [1, 2],
          'appearances': [
            {
              'source_id': 'slot-0',
              'source_kind': 'slot',
              'frame_indexes': [1, 2],
            },
          ],
          'stages': [
            {
              'stage_id': 'stage-1',
              'label': '默认服装',
              'frame_indexes': [1, 2],
              'identity': 'kamisato ayaka, girl',
              'upper_body':
                  'blue hair, long hair, braids, straight hair, one side up, '
                      'armpits, armpts, curvy',
              'lower_body': '',
              'upper_clothing': 'red jacket, bunnysuit, black lace dress',
              'lower_clothing': 'black panties, black bikini, black babydoll',
            },
          ],
          'prompt_terms': promptTerms,
        },
        {
          'source_role_id': 'role-shota',
          'source_kind': 'slot',
          'display_name': 'shota / 正太',
          'canonical_name': 'shota',
          'raw_identity_tags': ['shota'],
          'frame_indexes': [1, 2],
          'appearances': [
            {
              'source_id': 'slot-1',
              'source_kind': 'slot',
              'frame_indexes': [1, 2],
            },
          ],
          'stages': <Map<String, dynamic>>[],
          'prompt_terms': [
            {
              'id': 'male-black-panties',
              'text': 'male black panties',
              'category': 'clothing',
              'frame_indexes': [1, 2, 99],
              'source_occurrences': [
                {'frame_index': 1, 'source_location': 'slot-1 prompt'},
                {'frame_index': 2, 'source_location': 'slot-1 prompt'},
              ],
            },
          ],
        },
        {
          'source_role_id': 'role-black-dog',
          'source_kind': 'slot',
          'display_name': 'dog / 狗',
          'canonical_name': '',
          'raw_identity_tags': ['dog', 'black dog'],
          'frame_indexes': [1, 2],
          'appearances': [
            {
              'source_id': 'slot-1',
              'source_kind': 'slot',
              'frame_indexes': [1, 2],
            },
          ],
          'stages': <Map<String, dynamic>>[],
          'prompt_terms': [
            {
              'id': 'animal-black-dog',
              'text': 'black dog',
              'category': 'character',
              'frame_indexes': [1, 2],
            },
          ],
        },
        {
          'source_role_id': 'role-reviewed-evidence-base-shared',
          'source_kind': 'global',
          'display_name': 'shared evidence / pending ownership',
          'canonical_name': '',
          'raw_identity_tags': <String>[],
          'frame_indexes': [1],
          'appearances': <Map<String, dynamic>>[],
          'stages': <Map<String, dynamic>>[],
          'prompt_terms': <Map<String, dynamic>>[],
        },
      ],
    },
    'mapping': {
      'id': 'mapping-script-requested-rules',
      'scriptId': 'script-requested-rules',
      'roleSwaps': [],
      'artistSwap': null,
      'rolePromptReplacements': [
        {
          'sourceRoleId': 'role-ayaka',
          'displayLabel': 'Ayaka',
          'sourcePreview': terms.map((term) => term.$2).join(', '),
          'rules': [
            {
              'id': 'rule-conflicting-accessories',
              'sourceTerms': [
                for (final term in mappingTerms.where(
                  (term) => const {
                    'tress ribbon',
                    'no hair ornament',
                    'no hat',
                  }.contains(term['text']),
                ))
                  term,
              ],
            },
            {
              'id': 'rule-protected-and-style-panties',
              'sourceTerms': [
                for (final term in mappingTerms.where(
                  (term) => const {
                    'white panties',
                    'crotchless panties',
                  }.contains(term['text']),
                ))
                  term,
              ],
            },
            for (final term in mappingTerms.where(
              (term) => !const {
                'tress ribbon',
                'no hair ornament',
                'no hat',
                'white panties',
                'crotchless panties',
              }.contains(term['text']),
            ))
              {
                'id': 'rule-${term['id']}',
                'sourceTerms': [term],
                if (term['text'] == 'curvy') 'action': 'delete',
              },
          ],
        },
        {
          'sourceRoleId': 'role-shota',
          'displayLabel': 'shota / 正太',
          'sourcePreview': 'male black panties',
          'rules': [
            {
              'id': 'rule-male-black-panties',
              'sourceTerms': [
                {
                  'id': 'male-black-panties',
                  'text': 'male black panties',
                  'category': 'clothing',
                  'frameIndexes': [1, 2, 99],
                  'sourceOccurrences': [
                    {'frameIndex': 1, 'sourceLocation': 'slot-1 prompt'},
                    {'frameIndex': 2, 'sourceLocation': 'slot-1 prompt'},
                  ],
                },
              ],
            },
          ],
        },
        {
          'sourceRoleId': 'role-black-dog',
          'displayLabel': 'dog / 狗',
          'sourcePreview': 'black dog',
          'rules': [
            {
              'id': 'rule-animal-black-dog',
              'sourceTerms': [
                {
                  'id': 'animal-black-dog',
                  'text': 'black dog',
                  'category': 'character',
                  'frameIndexes': [1, 2],
                },
              ],
            },
          ],
        },
      ],
      'roleAssemblies': [
        {
          'sourceRoleId': 'role-ayaka',
          'displayLabel': 'Ayaka',
          'sourceAppearances': [
            {
              'sourceId': 'slot-0',
              'sourceKind': 'slot',
              'frameIndexes': [1, 2],
            },
          ],
          'stages': [
            {
              'id': 'stage-1',
              'label': '默认服装',
              'frameIndexes': [1, 2],
              'sourceParts': {
                'identity': 'kamisato ayaka, girl',
                'upperBody': 'blue hair, long hair, braids, straight hair',
                'upperClothing': 'red jacket, bunnysuit, black lace dress',
                'lowerClothing': 'black panties, black bikini',
              },
            },
          ],
        },
        {
          'sourceRoleId': 'role-reviewed-evidence-base-shared',
          'displayLabel': 'shared evidence / pending ownership',
          'sourceName': 'shared evidence / pending ownership',
          'stages': [
            {
              'id': 'stage-1',
              'label': 'shared',
              'frameIndexes': [1],
              'sourceSummary': 'shared evidence / pending ownership',
              'sourceParts': {
                'identity': 'shared evidence / pending ownership',
              },
              'omittedParts': [
                'identity',
                'upperBody',
                'lowerBody',
                'upperClothing',
                'lowerClothing',
              ],
            },
          ],
        },
      ],
    },
  };
}

Map<String, dynamic> _primaryRoleCache(String sourceRootPath) {
  Map<String, dynamic> role(
    String id,
    String identity,
    List<int> frames,
  ) =>
      {
        'source_role_id': id,
        'source_kind': 'slot',
        'display_name': '$identity / 测试角色',
        'canonical_name': identity,
        'raw_identity_tags': [identity, 'girl'],
        'frame_indexes': frames,
        'appearances': [
          {
            'source_id': id == 'role-cameo' ? 'slot-0' : 'slot-1',
            'source_kind': 'slot',
            'frame_indexes': frames,
          },
        ],
        'stages': [
          {
            'stage_id': 'stage-1',
            'label': '默认服装',
            'frame_indexes': frames,
            'identity': '$identity, girl',
            'upper_body': '',
            'lower_body': '',
            'upper_clothing': '',
            'lower_clothing': '',
          },
        ],
        'prompt_terms': [
          {
            'id': 'term-$id',
            'text': identity,
            'category': 'identity',
            'frame_indexes': frames,
          },
          {
            'id': 'term-$id-girl',
            'text': 'girl',
            'category': 'identity',
            'frame_indexes': frames,
          },
        ],
      };

  Map<String, dynamic> replacement(String id, String identity) => {
        'sourceRoleId': id,
        'displayLabel': identity,
        'sourcePreview': identity,
        'rules': [
          {
            'id': 'rule-$id',
            'sourceTerms': [
              {
                'id': 'term-$id',
                'text': identity,
                'category': 'identity',
              },
            ],
          },
          {
            'id': 'rule-$id-girl',
            'sourceTerms': [
              {
                'id': 'term-$id-girl',
                'text': 'girl',
                'category': 'identity',
              },
            ],
          },
        ],
      };

  Map<String, dynamic> assembly(
    String id,
    String identity,
    List<int> frames,
  ) =>
      {
        'sourceRoleId': id,
        'displayLabel': identity,
        'sourceAppearances': [
          {
            'sourceId': id == 'role-cameo' ? 'slot-0' : 'slot-1',
            'sourceKind': 'slot',
            'frameIndexes': frames,
          },
        ],
        'stages': [
          {
            'id': 'stage-1',
            'label': '默认服装',
            'frameIndexes': frames,
            'sourceParts': {'identity': identity},
          },
        ],
      };

  return {
    'scriptId': 'script-primary-role',
    'scriptName': 'Primary role fixture',
    'sourceRootPath': sourceRootPath,
    'aiRoleExtraction': {
      'status': 'ready',
      'roles': [
        role('role-cameo', 'cameo heroine', [1]),
        role('role-main', 'main heroine', [1, 2, 3]),
      ],
    },
    'mapping': {
      'id': 'mapping-script-primary-role',
      'scriptId': 'script-primary-role',
      'roleSwaps': [],
      'artistSwap': null,
      'rolePromptReplacements': [
        replacement('role-cameo', 'cameo heroine'),
        replacement('role-main', 'main heroine'),
      ],
      'roleAssemblies': [
        assembly('role-cameo', 'cameo heroine', [1]),
        assembly('role-main', 'main heroine', [1, 2, 3]),
      ],
    },
  };
}
