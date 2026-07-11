import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('offline extraction keeps pure actions out of replacement prompt terms',
      () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'script-recast-offline-test-',
    );
    addTearDown(() async {
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });

    final cacheDir = Directory('${tempRoot.path}/cache')
      ..createSync(recursive: true);
    final outputDir = Directory('${tempRoot.path}/output')
      ..createSync(recursive: true);
    final cacheFile = File('${cacheDir.path}/script-action-purity.json');
    cacheFile.writeAsStringSync(jsonEncode(_minimalRecastCache()));

    final result = await Process.run(
      'node',
      [
        'tool/build_script_recast_ai_extraction_offline.mjs',
        '--cache-dir',
        cacheDir.path,
        '--output-dir',
        outputDir.path,
        '--apply',
      ],
      workingDirectory: Directory.current.path,
    );

    expect(
      result.exitCode,
      0,
      reason: 'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
    );

    final updated = jsonDecode(
      File('${outputDir.path}/script-action-purity.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final roles = (updated['aiRoleExtraction'] as Map)['roles'] as List;
    final promptTerms = [
      for (final role in roles.cast<Map>())
        ...(role['prompt_terms'] as List? ?? const []).cast<Map>(),
    ];
    final termsByText = {
      for (final term in promptTerms) term['text'] as String: term,
    };
    final mapping = updated['mapping'] as Map<String, dynamic>;
    final replacements =
        (mapping['rolePromptReplacements'] as List).cast<Map>();
    final girlReplacement = replacements.singleWhere(
      (replacement) => replacement['sourceRoleId'] == 'role-girl-slot-0',
    );
    final rules = (girlReplacement['rules'] as List).cast<Map>();
    final mappedSourceTexts = {
      for (final rule in rules)
        for (final term in (rule['sourceTerms'] as List).cast<Map>())
          term['text'],
    };
    final blackJacketRule = rules.singleWhere(
      (rule) =>
          ((rule['sourceTerms'] as List).single as Map)['text'] ==
          'black jacket',
    );

    expect(termsByText.keys, isNot(contains('standing')));
    expect(termsByText.keys, isNot(contains('looking at viewer')));
    expect(termsByText.keys, isNot(contains('blush')));
    for (final actionTerm in [
      'presenting panties',
      'pussy juice',
      'spread pussy',
      'cumdrip from penis',
      'hands on penis',
      'hands on own breasts',
      'spread legs',
      'presenting own pussy',
      'adjusting hair',
      'adjusting gloves',
      'whispering in ear',
    ]) {
      expect(termsByText.keys, isNot(contains(actionTerm)));
    }
    expect(termsByText['black jacket']?['category'], 'upperClothing');
    expect(termsByText['black pantyhose']?['category'], 'lowerClothing');
    expect(termsByText['white panties']?['category'], 'lowerClothing');
    expect(termsByText['open shirt']?['category'], 'clothingState');
    expect(termsByText['undressing']?['category'], 'clothingState');
    expect(girlReplacement['targetCharacterId'], 'target-pepe');
    expect(
      girlReplacement['targetIdentityPrompt'],
      'pepe_(arknights), 6:: cat_ears ::, -6:: hood ::',
    );
    expect(blackJacketRule['action'], 'replace');
    expect(blackJacketRule['targetPrompt'], 'target jacket');
    expect(mappedSourceTexts, contains('black pantyhose'));
    expect(
      rules.any(
        (rule) => (rule['sourceTerms'] as List)
            .cast<Map>()
            .any((term) => term['text'] == 'presenting panties'),
      ),
      isFalse,
    );
  });

  test('offline extraction ignores generic POV-hand slots as roles', () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'script-recast-offline-pov-hands-test-',
    );
    addTearDown(() async {
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });

    final cacheDir = Directory('${tempRoot.path}/cache')
      ..createSync(recursive: true);
    final outputDir = Directory('${tempRoot.path}/output')
      ..createSync(recursive: true);
    File('${cacheDir.path}/script-pov-hands.json')
        .writeAsStringSync(jsonEncode(_povHandsOnlyCache()));

    final result = await Process.run(
      'node',
      [
        'tool/build_script_recast_ai_extraction_offline.mjs',
        '--cache-dir',
        cacheDir.path,
        '--output-dir',
        outputDir.path,
        '--apply',
      ],
      workingDirectory: Directory.current.path,
    );

    expect(
      result.exitCode,
      0,
      reason: 'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
    );
    final updated = jsonDecode(
      File('${outputDir.path}/script-pov-hands.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final roles =
        ((updated['aiRoleExtraction'] as Map)['roles'] as List).cast<Map>();
    final roleIds = roles.map((role) => role['source_role_id']).toList();
    final replacements =
        ((updated['mapping'] as Map)['rolePromptReplacements'] as List)
            .cast<Map>();

    expect(roleIds, contains('role-kokkoro-princess-connect'));
    expect(roleIds, isNot(contains('role-girl-slot-0')));
    expect(
      replacements.map((replacement) => replacement['sourceRoleId']),
      isNot(contains('role-girl-slot-0')),
    );
  });

  test('offline extraction ignores generic disembodied-hand slots as roles',
      () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'script-recast-offline-disembodied-hand-test-',
    );
    addTearDown(() async {
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });

    final cacheDir = Directory('${tempRoot.path}/cache')
      ..createSync(recursive: true);
    final outputDir = Directory('${tempRoot.path}/output')
      ..createSync(recursive: true);
    File('${cacheDir.path}/script-disembodied-hand.json')
        .writeAsStringSync(jsonEncode(_disembodiedHandOnlyCache()));

    final result = await Process.run(
      'node',
      [
        'tool/build_script_recast_ai_extraction_offline.mjs',
        '--cache-dir',
        cacheDir.path,
        '--output-dir',
        outputDir.path,
        '--apply',
      ],
      workingDirectory: Directory.current.path,
    );

    expect(
      result.exitCode,
      0,
      reason: 'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
    );
    final updated = jsonDecode(
      File('${outputDir.path}/script-disembodied-hand.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final roles =
        ((updated['aiRoleExtraction'] as Map)['roles'] as List).cast<Map>();
    final roleIds = roles.map((role) => role['source_role_id']).toList();

    expect(roleIds, contains('role-muscular-male'));
    expect(roleIds, isNot(contains('role-anonymous-male')));
  });
}

Map<String, dynamic> _minimalRecastCache() {
  return {
    'scriptId': 'script-action-purity',
    'scriptName': 'Action purity fixture',
    'sourceRootPath': 'C:/fixture/action-purity',
    'scriptSnapshot': {
      'frames': [
        {
          'index': 1,
          'fileName': 'nai_1.png',
          'sourcePath': 'C:/fixture/action-purity/nai_1.png',
          'sourceImagePath': 'C:/fixture/action-purity/nai_1.png',
          'parseStatus': 'parsed',
          'parsed': {
            'baseCaption': 'indoors, detailed eyes',
            'charCaptions': [
              'girl, black jacket, black pantyhose, white panties, standing, looking at viewer, blush, undressing, open shirt, presenting panties, pussy juice, spread pussy, cumdrip from penis, hands on penis, hands on own breasts, spread legs, presenting own pussy, adjusting hair, adjusting gloves, whispering in ear',
            ],
            'negativeBase': '',
            'negativeCharCaptions': [''],
          },
        },
      ],
    },
    'mapping': {
      'id': 'mapping-script-action-purity',
      'scriptId': 'script-action-purity',
      'roleSwaps': [],
      'artistSwap': null,
      'rolePromptReplacements': [
        {
          'sourceRoleId': 'role-girl-slot-0',
          'displayLabel': 'Existing girl',
          'sourcePreview': 'old preview',
          'targetCharacterId': 'target-pepe',
          'targetIdentityPrompt':
              'pepe_(arknights), 6:: cat_ears ::, -6:: hood ::',
          'rules': [
            {
              'id': 'existing-black-jacket',
              'sourceTerms': [
                {
                  'id': 'old-black-jacket',
                  'text': 'black jacket',
                  'category': 'upperClothing',
                },
                {
                  'id': 'old-black-pantyhose',
                  'text': 'black pantyhose',
                  'category': 'lowerClothing',
                },
              ],
              'action': 'replace',
              'targetPrompt': 'target jacket',
            },
            {
              'id': 'existing-presenting-panties',
              'sourceTerms': [
                {
                  'id': 'old-presenting-panties',
                  'text': 'presenting panties',
                  'category': 'lowerClothing',
                },
              ],
              'action': 'replace',
              'targetPrompt': 'target panties',
            },
          ],
        },
      ],
    },
  };
}

Map<String, dynamic> _povHandsOnlyCache() {
  return {
    'scriptId': 'script-pov-hands',
    'scriptName': 'POV hands fixture',
    'sourceRootPath': 'C:/fixture/pov-hands',
    'scriptSnapshot': {
      'frames': [
        {
          'index': 83,
          'fileName': 'nai_83.png',
          'sourcePath': 'C:/fixture/pov-hands/nai_83.png',
          'sourceImagePath': 'C:/fixture/pov-hands/nai_83.png',
          'parseStatus': 'parsed',
          'parsed': {
            'baseCaption': '2girls, prison',
            'charCaptions': [
              'girl, pov hands, white gloves, elbow gloves, hand on another\'s cheek',
              'girl, kokkoro (princess connect!), loli, green dress, short hair',
            ],
            'negativeBase': '',
            'negativeCharCaptions': ['', ''],
          },
        },
      ],
    },
    'mapping': {
      'id': 'mapping-script-pov-hands',
      'scriptId': 'script-pov-hands',
      'roleSwaps': [],
      'artistSwap': null,
    },
  };
}

Map<String, dynamic> _disembodiedHandOnlyCache() {
  return {
    'scriptId': 'script-disembodied-hand',
    'scriptName': 'Disembodied hand fixture',
    'sourceRootPath': 'C:/fixture/disembodied-hand',
    'scriptSnapshot': {
      'frames': [
        {
          'index': 1,
          'fileName': 'nai_1.png',
          'parseStatus': 'parsed',
          'parsed': {
            'baseCaption': '1girl, 1boy, bedroom',
            'charCaptions': [
              'girl, kyoka (summer) (princess connect!), purple hair',
              'boy, dark-skinned male, musclar male, completely nude',
            ],
          },
        },
        {
          'index': 2,
          'fileName': 'nai_2.png',
          'parseStatus': 'parsed',
          'parsed': {
            'baseCaption': '1girl, bedroom',
            'charCaptions': [
              'girl, kyoka (summer) (princess connect!), purple hair',
              'boy, disembodied hand, holding sex toy, hitachi magic wand, wand on stomach',
            ],
          },
        },
      ],
    },
    'mapping': {
      'id': 'mapping-script-disembodied-hand',
      'scriptId': 'script-disembodied-hand',
      'roleSwaps': [],
      'artistSwap': null,
    },
  };
}
