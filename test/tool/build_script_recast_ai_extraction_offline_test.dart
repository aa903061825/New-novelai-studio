import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/data/studio/models/script_recast.dart';
import 'package:novel_studio/data/studio/services/script_recast_cache_restore_service.dart';

void main() {
  test('offline extraction uses complete Codex review as term membership truth',
      () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'script-recast-offline-term-review-test-',
    );
    addTearDown(() async {
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });

    final cacheDir = Directory('${tempRoot.path}/cache')
      ..createSync(recursive: true);
    final outputDir = Directory('${tempRoot.path}/output');
    final reviewFile = File('${tempRoot.path}/term-review.json')
      ..writeAsStringSync(jsonEncode(_completeTermReview()));
    File('${cacheDir.path}/script-term-review.json')
        .writeAsStringSync(jsonEncode(_termReviewRecastCache()));

    final result = await Process.run(
      'node',
      [
        'tool/build_script_recast_ai_extraction_offline.mjs',
        '--cache-dir',
        cacheDir.path,
        '--output-dir',
        outputDir.path,
        '--term-review',
        reviewFile.path,
        '--require-complete-term-review',
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
      File('${outputDir.path}/script-term-review.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final extraction = updated['aiRoleExtraction'] as Map<String, dynamic>;
    final roles = (extraction['roles'] as List).cast<Map>();
    final reisa = roles.singleWhere(
      (role) => role['source_role_id'] == 'role-reisa-blue-archive',
    );
    final terms = (reisa['prompt_terms'] as List).cast<Map>();
    final termsByText = {
      for (final term in terms) term['text'] as String: term,
    };

    expect(
        termsByText.keys,
        containsAll(<String>[
          'reisa (blue archive)',
          'alternate hairstyle',
          'twin drills',
          'high twintails',
          'magical girl',
          'white witch hat',
          'no panties',
          'bridal lingerie',
          'spade tattoo',
          'wet hair',
          'white gloves',
          'elbow gloves',
        ]));
    expect(termsByText['alternate hairstyle']?['category'], 'body');
    expect(termsByText['twin drills']?['category'], 'body');
    expect(termsByText['magical girl']?['category'], 'identity');
    expect(termsByText['white witch hat']?['category'], 'accessory');
    expect(termsByText['no panties']?['category'], 'clothingState');
    expect(termsByText['bridal lingerie']?['category'], 'clothing');
    expect(termsByText['spade tattoo']?['category'], 'body');
    expect(termsByText['wet hair']?['category'], 'body');
    expect(
        termsByText['wet hair']?['source_location'], contains('base prompt'));
    expect(termsByText['white gloves']?['category'], 'accessory');
    expect(termsByText['elbow gloves']?['category'], 'accessory');
    expect(
      termsByText['elbow gloves']?['source_location'],
      contains('slot-0 prompt'),
    );
    expect(termsByText.keys, isNot(contains('{{white witch hat')));
    expect(termsByText.keys, isNot(contains('facial')));
    expect(termsByText.keys, isNot(contains('crotch focus')));
    expect(termsByText.keys, isNot(contains('standing')));
    final stages = (reisa['stages'] as List).cast<Map>();
    expect(stages, isNotEmpty);
    expect(stages.every((stage) => stage['non_role_materialized'] == true),
        isTrue);
    expect(
      stages
          .expand((stage) => [
                stage['identity'],
                stage['upper_body'],
                stage['lower_body'],
                stage['upper_clothing'],
                stage['lower_clothing'],
              ])
          .join(', '),
      isNot(contains('crotch focus')),
    );
    expect(
      stages
          .expand((stage) => [
                stage['identity'],
                stage['upper_body'],
                stage['lower_body'],
                stage['upper_clothing'],
                stage['lower_clothing'],
                stage['non_role'],
              ])
          .join(', '),
      allOf(
        isNot(contains('white witch hat')),
        isNot(contains('no panties')),
        isNot(contains('bridal lingerie')),
        isNot(contains('spade tattoo')),
      ),
    );

    final sceneTerms = (extraction['scene_terms'] as List).cast<Map>();
    expect(sceneTerms.map((term) => term['text']), ['outdoors']);

    final mapping = updated['mapping'] as Map<String, dynamic>;
    final replacement =
        (mapping['rolePromptReplacements'] as List).cast<Map>().singleWhere(
              (item) => item['sourceRoleId'] == 'role-reisa-blue-archive',
            );
    expect(replacement['targetCharacterId'], 'target-reisa');
    final rules = (replacement['rules'] as List).cast<Map>();
    final rulesByText = {
      for (final rule in rules)
        ((rule['sourceTerms'] as List).single as Map)['text'] as String: rule,
    };
    expect(rulesByText.keys, unorderedEquals(termsByText.keys));
    expect(rulesByText.keys, isNot(contains('facial')));
    expect(
      rulesByText['high twintails']?['action'],
      'replace',
      reason: jsonEncode(rules),
    );
    expect(rulesByText['high twintails']?['targetPrompt'], 'long hair');
    expect(rulesByText['reisa (blue archive)']?['action'], 'replace');
    expect(
      rulesByText['reisa (blue archive)']?['targetPrompt'],
      'pepe_(arknights)',
      reason:
          'A generic mapped identity rule must migrate to the new concrete identity.',
    );

    final male = roles.singleWhere(
      (role) => (role['prompt_terms'] as List)
          .cast<Map>()
          .any((term) => term['text'] == 'faceless male'),
    );
    final maleTerms = (male['prompt_terms'] as List).cast<Map>().toList();
    expect(maleTerms.map((term) => term['text']), contains('large penis'));
    expect(
      maleTerms.singleWhere(
          (term) => term['text'] == 'large penis')['source_location'],
      contains('base prompt'),
    );

    final reisaAppearances = (reisa['appearances'] as List).cast<Map>();
    expect(
      reisaAppearances
          .expand(
              (appearance) => (appearance['frame_indexes'] as List).cast<int>())
          .toSet(),
      isNot(contains(3)),
      reason:
          'POV-hand evidence must enrich terms without creating a fake role appearance.',
    );

    final report = jsonDecode(result.stdout as String) as Map<String, dynamic>;
    expect(report['api_used'], isFalse);
    expect(report['term_review_decision_count'], 22);
    expect(report['term_review_missing_term_count'], 0);
    expect(report['term_review_complete'], isTrue);
  });

  test('complete term review fails before writing when a source term is absent',
      () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'script-recast-offline-incomplete-term-review-test-',
    );
    addTearDown(() async {
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });

    final cacheDir = Directory('${tempRoot.path}/cache')
      ..createSync(recursive: true);
    final outputDir = Directory('${tempRoot.path}/output');
    final review = _completeTermReview();
    (review['decisions'] as List).removeWhere(
      (decision) =>
          (decision as Map<String, dynamic>)['term'] == 'alternate hairstyle',
    );
    final reviewFile = File('${tempRoot.path}/term-review.json')
      ..writeAsStringSync(jsonEncode(review));
    File('${cacheDir.path}/script-term-review.json')
        .writeAsStringSync(jsonEncode(_termReviewRecastCache()));

    final result = await Process.run(
      'node',
      [
        'tool/build_script_recast_ai_extraction_offline.mjs',
        '--cache-dir',
        cacheDir.path,
        '--output-dir',
        outputDir.path,
        '--term-review',
        reviewFile.path,
        '--require-complete-term-review',
        '--apply',
      ],
      workingDirectory: Directory.current.path,
    );

    expect(result.exitCode, isNot(0));
    expect('${result.stderr}', contains('alternate hairstyle'));
    expect(outputDir.existsSync(), isFalse);
  });

  test('complete term review fails before writing when cache baseline drifts',
      () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'script-recast-offline-drifted-term-review-test-',
    );
    addTearDown(() async {
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });
    final cacheDir = Directory('${tempRoot.path}/cache')
      ..createSync(recursive: true);
    final outputDir = Directory('${tempRoot.path}/output');
    final review = _completeTermReview()
      ..['cache_files'] = [
        {
          'file_name': 'script-term-review.json',
          'sha256': List.filled(64, '0').join(),
        },
      ];
    final reviewFile = File('${tempRoot.path}/term-review.json')
      ..writeAsStringSync(jsonEncode(review));
    File('${cacheDir.path}/script-term-review.json')
        .writeAsStringSync(jsonEncode(_termReviewRecastCache()));

    final result = await Process.run(
      'node',
      [
        'tool/build_script_recast_ai_extraction_offline.mjs',
        '--cache-dir',
        cacheDir.path,
        '--output-dir',
        outputDir.path,
        '--term-review',
        reviewFile.path,
        '--require-complete-term-review',
        '--apply',
      ],
      workingDirectory: Directory.current.path,
    );

    expect(result.exitCode, isNot(0));
    expect('${result.stderr}', contains('baseline drift'));
    expect('${result.stderr}', contains('script-term-review.json'));
    expect(outputDir.existsSync(), isFalse);
  });

  test(
      'complete term review allows canonical-only raw drift when positive evidence is unchanged',
      () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'script-recast-offline-positive-evidence-drift-test-',
    );
    addTearDown(() async {
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });

    final cacheDir = Directory('${tempRoot.path}/cache')
      ..createSync(recursive: true);
    final outputDir = Directory('${tempRoot.path}/output');
    const fileName = 'script-term-review.json';
    final baselineFile = File('${tempRoot.path}/baseline-$fileName')
      ..writeAsStringSync(jsonEncode(_termReviewRecastCache()));
    final baselineRawSha = await _sha256FileWithNode(baselineFile);
    final baselinePositiveSha = await _manifestPositiveEvidenceSha(
      tempRoot: tempRoot,
      fileName: fileName,
      cache: _termReviewRecastCache(),
      suffix: 'baseline',
    );
    final driftedCache = _termReviewRecastCache();
    ((driftedCache['mapping'] as Map<String, dynamic>)['canonicalOnlyProbe'] =
        'raw-only drift');
    final driftedPositiveSha = await _manifestPositiveEvidenceSha(
      tempRoot: tempRoot,
      fileName: fileName,
      cache: driftedCache,
      suffix: 'drifted',
    );
    expect(driftedPositiveSha, baselinePositiveSha);
    File('${cacheDir.path}/$fileName')
        .writeAsStringSync(jsonEncode(driftedCache));

    final review = _completeTermReview()
      ..['cache_files'] = [
        {
          'file_name': fileName,
          'sha256': baselineRawSha,
          'positive_evidence_sha256': baselinePositiveSha,
        },
      ];
    final reviewFile = File('${tempRoot.path}/term-review.json')
      ..writeAsStringSync(jsonEncode(review));
    final translationCache = File('${tempRoot.path}/translations.json')
      ..writeAsStringSync('{}');
    final result = await Process.run(
      'node',
      [
        'tool/build_script_recast_ai_extraction_offline.mjs',
        '--cache-dir',
        cacheDir.path,
        '--output-dir',
        outputDir.path,
        '--translation-cache',
        translationCache.path,
        '--term-review',
        reviewFile.path,
        '--require-complete-term-review',
        '--apply',
      ],
      workingDirectory: Directory.current.path,
    );

    expect(
      result.exitCode,
      0,
      reason: 'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
    );
    final report = jsonDecode(result.stdout as String) as Map<String, dynamic>;
    expect(report['api_used'], isFalse);
    expect(report['term_review_baseline_mismatch_count'], 0);
    expect(
        report['term_review_positive_evidence_match_after_raw_drift_count'], 1);
    expect(
      report['term_review_positive_evidence_match_after_raw_drift_files'],
      [fileName],
    );
  });

  test('complete term review rejects positive caption evidence drift',
      () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'script-recast-offline-positive-evidence-mismatch-test-',
    );
    addTearDown(() async {
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });

    const fileName = 'script-term-review.json';
    final baselineCache = _termReviewRecastCache();
    final baselineFile = File('${tempRoot.path}/baseline-$fileName')
      ..writeAsStringSync(jsonEncode(baselineCache));
    final baselineRawSha = await _sha256FileWithNode(baselineFile);
    final baselinePositiveSha = await _manifestPositiveEvidenceSha(
      tempRoot: tempRoot,
      fileName: fileName,
      cache: baselineCache,
      suffix: 'baseline',
    );
    final changedCache = _termReviewRecastCache();
    final frames = ((changedCache['scriptSnapshot']
            as Map<String, dynamic>)['frames'] as List)
        .cast<Map<String, dynamic>>();
    final changedFrame = frames.firstWhere((frame) => frame['index'] == 2);
    (changedFrame['parsed'] as Map<String, dynamic>)['baseCaption'] =
        'outdoors, wet hair, alternate hairstyle';
    final cacheDir = Directory('${tempRoot.path}/cache')
      ..createSync(recursive: true);
    File('${cacheDir.path}/$fileName')
        .writeAsStringSync(jsonEncode(changedCache));
    final review = _completeTermReview()
      ..['cache_files'] = [
        {
          'file_name': fileName,
          'sha256': baselineRawSha,
          'positive_evidence_sha256': baselinePositiveSha,
        },
      ];
    final reviewFile = File('${tempRoot.path}/term-review.json')
      ..writeAsStringSync(jsonEncode(review));
    final outputDir = Directory('${tempRoot.path}/output');
    final translationCache = File('${tempRoot.path}/translations.json')
      ..writeAsStringSync('{}');
    final result = await Process.run(
      'node',
      [
        'tool/build_script_recast_ai_extraction_offline.mjs',
        '--cache-dir',
        cacheDir.path,
        '--output-dir',
        outputDir.path,
        '--translation-cache',
        translationCache.path,
        '--term-review',
        reviewFile.path,
        '--require-complete-term-review',
        '--apply',
      ],
      workingDirectory: Directory.current.path,
    );

    expect(result.exitCode, isNot(0));
    expect('${result.stderr}', contains('baseline drift'));
    expect('${result.stderr}', contains(fileName));
    expect(outputDir.existsSync(), isFalse);
  });

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
    final compactedSnapshotContentFingerprint =
        const ScriptRecastCacheRestoreService()
            .sourceContentFingerprintFromSnapshot(
      (updated['scriptSnapshot'] as Map).cast<String, dynamic>(),
    );
    final compactedSnapshotSourceFingerprint =
        const ScriptRecastCacheRestoreService().sourceFingerprint(
      Script.fromJson(
        (updated['scriptSnapshot'] as Map).cast<String, dynamic>(),
      ),
    );
    final expectedStoredSourceFingerprint = Platform.isWindows
        ? 'script-action-purity|c:/fixture/action-purity|'
            '1:nai_1.png:c:/fixture/action-purity/nai_1.png:deadbeef'
        : 'script-action-purity|C:/Fixture/Action-Purity|'
            '1:nai_1.png:C:/Fixture/Action-Purity/nai_1.png:deadbeef';
    expect(compactedSnapshotContentFingerprint, isNotEmpty);
    expect(compactedSnapshotSourceFingerprint, isNotEmpty);
    expect(
      updated['sourceContentFingerprint'],
      'schema:v4Partial|frames:1|1:nai_1.png:deadbeef',
    );
    expect(
      updated['sourceContentFingerprint'],
      isNot(compactedSnapshotContentFingerprint),
      reason: 'Content fingerprints must use the preserved raw-source hash.',
    );
    expect(updated['sourceFingerprint'], expectedStoredSourceFingerprint);
    expect(updated['updatedAt'], '2026-06-01T00:00:00.000Z');
    expect(
      updated['sourceFingerprint'],
      isNot(compactedSnapshotSourceFingerprint),
      reason: 'The stored raw-source hash must survive snapshot compaction.',
    );
    final report = jsonDecode(result.stdout as String) as Map<String, dynamic>;
    expect(report['source_content_fingerprint_missing_count'], 0);
    expect(report['source_content_fingerprint_mismatch_count'], 1);
    expect(report['source_content_fingerprint_repaired_count'], 1);
    expect(report['source_fingerprint_missing_count'], 0);
    expect(report['source_fingerprint_invalid_count'], 0);
    expect(
      report['source_fingerprint_path_normalized_count'],
      Platform.isWindows ? 1 : 0,
    );
    final roles = (updated['aiRoleExtraction'] as Map)['roles'] as List;
    final promptTerms = [
      for (final role in roles.cast<Map>())
        ...(role['prompt_terms'] as List? ?? const []).cast<Map>(),
    ];
    final termsByText = {
      for (final term in promptTerms) term['text'] as String: term,
    };
    final mapping = updated['mapping'] as Map<String, dynamic>;
    expect(mapping['id'], 'mapping-script-action-purity');
    expect(mapping['scriptId'], 'script-action-purity');
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
    expect(termsByText['black jacket']?['category'], 'clothing');
    expect(termsByText['black pantyhose']?['category'], 'clothing');
    expect(termsByText['white panties']?['category'], 'clothing');
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

    final girlRole = roles.cast<Map>().singleWhere(
          (role) => role['source_role_id'] == 'role-girl-slot-0',
        );
    final stageFieldTerms = <String>{
      for (final stage in (girlRole['stages'] as List).cast<Map>())
        for (final field in const [
          'identity',
          'upper_body',
          'lower_body',
          'upper_clothing',
          'lower_clothing',
        ])
          ...(stage[field] as String)
              .split(',')
              .map((term) => term.trim())
              .where((term) => term.isNotEmpty),
    };
    expect(stageFieldTerms, contains('large breasts'));
    for (final transientTerm in [
      'bouncing breasts',
      'breasts squeezed together',
      'stomach bulge',
      'face in crotch',
      'lifting own clothes',
      'wide eyes',
      'dead eyes',
      'deep flushed face',
      'ass visible through thighs',
      'clitoral hood',
      'foot on another\'s face',
      'legs wrapped around waist',
      'tattoo machine (laser)',
      'tear another\'s pantyhose',
      'shorts pull',
      'shirt pull',
      'pants pull',
      'kimono pull',
      'open legs',
      'face down on sofa',
    ]) {
      expect(stageFieldTerms, isNot(contains(transientTerm)));
    }
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
    expect(
      roleIds,
      isNot(contains('role-anonymous-male')),
      reason: jsonEncode(roles),
    );
    final muscular = roles.singleWhere(
      (role) => role['source_role_id'] == 'role-muscular-male',
    );
    expect(muscular['frame_indexes'], isNot(contains(3)));
  });

  test('offline extraction retains stable evidence in a partial POV slot',
      () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'script-recast-offline-partial-stable-test-',
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
    File('${cacheDir.path}/script-partial-stable.json')
        .writeAsStringSync(jsonEncode(_partialStableRoleCache()));

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
      File('${outputDir.path}/script-partial-stable.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final roles =
        ((updated['aiRoleExtraction'] as Map)['roles'] as List).cast<Map>();
    final sensei = roles.singleWhere(
      (role) =>
          role['source_role_id'] == 'role-sensei-blue-archive-the-animation',
    );
    final slotOne = (sensei['appearances'] as List).cast<Map>().singleWhere(
          (appearance) => appearance['source_id'] == 'slot-1',
        );

    expect(slotOne['frame_indexes'], contains(4));
    expect(
      roles.map((role) => role['source_role_id']),
      isNot(contains('role-anonymous-male')),
    );
  });

  test('offline extraction splits simultaneous generic roles by source slot',
      () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'script-recast-offline-generic-slot-collision-test-',
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
    File('${cacheDir.path}/script-generic-slot-collision.json')
        .writeAsStringSync(jsonEncode(_genericSlotCollisionCache()));

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
      File('${outputDir.path}/script-generic-slot-collision.json')
          .readAsStringSync(),
    ) as Map<String, dynamic>;
    final roles =
        ((updated['aiRoleExtraction'] as Map)['roles'] as List).cast<Map>();
    final maleRoles = roles
        .where((role) =>
            (role['source_role_id'] as String).startsWith('role-muscular-male'))
        .toList();

    expect(maleRoles, hasLength(2));
    expect(
      maleRoles
          .map((role) =>
              (role['appearances'] as List).cast<Map>().single['source_id'])
          .toSet(),
      {'slot-0', 'slot-1'},
    );
  });

  test('offline extraction rejects non-character tags classified as characters',
      () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'script-recast-offline-pseudo-character-test-',
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
    File('${cacheDir.path}/script-pseudo-character.json')
        .writeAsStringSync(jsonEncode(_pseudoCharacterCache()));

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
      File('${outputDir.path}/script-pseudo-character.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final roles =
        ((updated['aiRoleExtraction'] as Map)['roles'] as List).cast<Map>();
    final roleIds =
        roles.map((role) => role['source_role_id'] as String).toSet();

    expect(roleIds, contains('role-kokkoro-princess-connect'));
    for (final forbiddenRoleId in [
      'role-foreskin',
      'role-no-humans',
      'role-touching-character-1',
      'role-behind-chiara',
      'role-rebellion-sword',
      'role-ring-of-light-blue-archive',
    ]) {
      expect(roleIds, isNot(contains(forbiddenRoleId)));
    }
  });

  test(
      'offline extraction keeps stable male evidence when the body is off frame',
      () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'script-recast-offline-off-frame-role-test-',
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
    File('${cacheDir.path}/script-off-frame-role.json')
        .writeAsStringSync(jsonEncode(_offFrameMaleCache()));

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
      File('${outputDir.path}/script-off-frame-role.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final roles =
        ((updated['aiRoleExtraction'] as Map)['roles'] as List).cast<Map>();
    final coveredFrames = <int>{
      for (final role in roles)
        for (final frameIndex in (role['frame_indexes'] as List).cast<int>())
          frameIndex,
    };

    expect(coveredFrames, containsAll(<int>[1, 2]));
  });

  test(
      'offline extraction ignores another role clothing actions in stage state',
      () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'script-recast-offline-stage-action-state-test-',
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
    File('${cacheDir.path}/script-stage-action-state.json')
        .writeAsStringSync(jsonEncode(_stageActionStateCache()));

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
      File('${outputDir.path}/script-stage-action-state.json')
          .readAsStringSync(),
    ) as Map<String, dynamic>;
    final roles =
        ((updated['aiRoleExtraction'] as Map)['roles'] as List).cast<Map>();
    final stages = (roles.single['stages'] as List).cast<Map>();

    expect(stages, hasLength(1));
    expect(stages.single['label'], isNot(contains('比基尼')));
    expect(
      stages.single['lower_clothing'],
      isNot(contains('bikini bottom')),
    );
    expect(
      stages.single['evidence_terms'],
      isNot(contains("hand inside 1 girl's bikini bottom")),
    );
  });

  test(
      'offline extraction keeps named costume variants under one canonical role',
      () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'script-recast-offline-named-costume-variant-test-',
    );
    addTearDown(() async {
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });

    final updated = await _runOfflineBuilderFixture(
      tempRoot: tempRoot,
      fileName: 'script-named-costume-variant.json',
      cache: _fixtureCache('script-named-costume-variant', [
        _fixtureFrame(
          1,
          charCaptions: const ['girl, kamisato ayaka, blue hair'],
        ),
        _fixtureFrame(
          2,
          charCaptions: const [
            'girl, kamisato ayaka (springbloom missive), blue hair, blue dress',
          ],
        ),
        _fixtureFrame(
          3,
          charCaptions: const [
            'girl, kamisato ayaka（springbloom missive）, blue hair, blue dress',
          ],
        ),
        _fixtureFrame(
          4,
          charCaptions: const [
            'girl, kamisato ayaka【springbloom missive】, blue hair, blue dress',
          ],
        ),
        _fixtureFrame(
          5,
          charCaptions: const [
            'girl, hamedoori template (meme), kamisato ayaka, blue hair',
          ],
        ),
      ]),
      termReview: _reviewDocument([
        ('girl', 'character'),
        ('kamisato ayaka', 'character'),
        ('kamisato ayaka (springbloom missive)', 'character'),
        ('blue hair', 'upperBody'),
        ('blue dress', 'upperClothing'),
      ]),
      classificationCache: const {},
    );
    final roles =
        ((updated['aiRoleExtraction'] as Map)['roles'] as List).cast<Map>();
    final ayakaRoles = roles
        .where((role) => role['canonical_name'] == 'kamisato ayaka')
        .toList();

    expect(ayakaRoles, hasLength(1));
    expect(ayakaRoles.single['source_role_id'], 'role-kamisato-ayaka');
    expect(ayakaRoles.single['frame_indexes'], [1, 2, 3, 4, 5]);
    expect(ayakaRoles.single['variant_tags'], contains('springbloom missive'));
    final promptTerms = (ayakaRoles.single['prompt_terms'] as List).cast<Map>();
    expect(
      promptTerms.map((term) => term['text']),
      containsAll(<String>[
        'kamisato ayaka',
        'kamisato ayaka (springbloom missive)',
      ]),
    );
    expect(
      roles.map((role) => role['source_role_id']),
      isNot(contains('role-hamedoori-template-meme')),
    );
  });

  test(
      'offline extraction ignores parenthetical pseudo identities on no-human frames',
      () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'script-recast-offline-no-human-pseudo-identity-test-',
    );
    addTearDown(() async {
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });

    final updated = await _runOfflineBuilderFixture(
      tempRoot: tempRoot,
      fileName: 'script-no-human-pseudo-identity.json',
      cache: _fixtureCache('script-no-human-pseudo-identity', [
        _fixtureFrame(
          1,
          baseCaption: 'no human, null (nyanpyoun), indoors',
          charCaptions: const [],
        ),
      ]),
    );
    final roles =
        ((updated['aiRoleExtraction'] as Map)['roles'] as List).cast<Map>();

    expect(roles, isEmpty);
  });

  test(
      'offline extraction keeps normal and aside clothing transitions in separate stages',
      () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'script-recast-offline-stage-transition-test-',
    );
    addTearDown(() async {
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });

    final updated = await _runOfflineBuilderFixture(
      tempRoot: tempRoot,
      fileName: 'script-stage-transition.json',
      cache: _stageTransitionCache(),
      termReview: _stageTransitionReview(),
    );
    final roles =
        ((updated['aiRoleExtraction'] as Map)['roles'] as List).cast<Map>();
    final chiara = roles.singleWhere(
      (role) => (role['raw_identity_tags'] as List)
          .contains('chiara (black survival)'),
    );
    final stages = (chiara['stages'] as List).cast<Map>();

    expect(stages, hasLength(3));
    expect(
      stages.map((stage) => stage['frame_indexes']),
      containsAll(<Object>[
        [1, 2],
        [3, 4],
        [5, 6],
      ]),
      reason:
          'A clothing displacement transition must not be merged by a shared label.',
    );
  });

  test(
      'offline extraction does not let another role swimsuit label a topless male stage',
      () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'script-recast-offline-stage-label-owner-test-',
    );
    addTearDown(() async {
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });

    final updated = await _runOfflineBuilderFixture(
      tempRoot: tempRoot,
      fileName: 'script-stage-label-owner.json',
      cache: _stageLabelOwnerIsolationCache(),
    );
    final roles =
        ((updated['aiRoleExtraction'] as Map)['roles'] as List).cast<Map>();
    final male = roles.singleWhere(
      (role) => (role['raw_identity_tags'] as List)
          .contains('yuuki (princess connect!)'),
    );
    final maleStages = (male['stages'] as List).cast<Map>();

    expect(maleStages, isNotEmpty);
    expect(
      maleStages.map((stage) => stage['label']).join(' / '),
      isNot(contains('泳装')),
      reason:
          'A female slot swimsuit must not become a label term for the male role.',
    );
    expect(
      maleStages
          .expand((stage) => [
                stage['identity'],
                stage['upper_body'],
                stage['lower_body'],
                stage['upper_clothing'],
                stage['lower_clothing'],
              ])
          .join(', '),
      isNot(contains('swimsuit')),
    );
  });

  test(
      'reviewed supplemental anatomy routes per term to a gender-compatible owner',
      () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'script-recast-offline-reviewed-gender-routing-test-',
    );
    addTearDown(() async {
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });

    final updated = await _runOfflineBuilderFixture(
      tempRoot: tempRoot,
      fileName: 'script-reviewed-gender-routing.json',
      cache: _reviewedGenderRoutingCache(),
      termReview: _reviewedGenderRoutingReview(),
    );
    final roles =
        ((updated['aiRoleExtraction'] as Map)['roles'] as List).cast<Map>();
    final chiara = roles.singleWhere(
      (role) => (role['raw_identity_tags'] as List)
          .contains('chiara (black survival)'),
    );
    final male = roles.singleWhere(
      (role) => (role['raw_identity_tags'] as List).contains('faceless male'),
    );
    final chiaraTerms = (chiara['prompt_terms'] as List).cast<Map>();
    final maleTerms = (male['prompt_terms'] as List).cast<Map>();

    expect(
      chiaraTerms.map((term) => term['text']),
      isNot(contains('large penis')),
      reason: 'Male anatomy must not remain in the female owner frameTags.',
    );
    final routed = maleTerms.singleWhere(
      (term) => term['text'] == 'large penis',
    );
    expect(male['frame_indexes'], [1]);
    expect(
      (male['appearances'] as List)
          .cast<Map>()
          .expand(
              (appearance) => (appearance['frame_indexes'] as List).cast<int>())
          .toSet(),
      {1},
    );
    expect(routed['source_location'], contains('slot-0 prompt'));
    expect(routed['source_occurrences'], [
      {
        'frame_index': 2,
        'source_location': 'slot-0 prompt',
      },
    ]);
  });

  test(
      'ambiguous base anatomy stays mappable in shared evidence without a third girl',
      () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'script-recast-offline-shared-anatomy-fallback-test-',
    );
    addTearDown(() async {
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });

    final updated = await _runOfflineBuilderFixture(
      tempRoot: tempRoot,
      fileName: 'script-shared-anatomy-fallback.json',
      cache: _sharedAnatomyFallbackCache(),
      termReview: _sharedAnatomyFallbackReview(),
    );
    final roles =
        ((updated['aiRoleExtraction'] as Map)['roles'] as List).cast<Map>();
    final namedRoles = roles.where((role) {
      final tags = (role['raw_identity_tags'] as List).cast<String>();
      return tags.contains('chiara (black survival)') ||
          tags.contains('xuelin (black survival)');
    }).toList();
    expect(namedRoles, hasLength(2));
    for (final role in namedRoles) {
      expect(
        (role['prompt_terms'] as List).cast<Map>().map((term) => term['text']),
        isNot(contains('large penis')),
      );
    }

    final shared = roles.singleWhere(
      (role) => (role['prompt_terms'] as List)
          .cast<Map>()
          .any((term) => term['text'] == 'large penis'),
    );
    expect(shared['raw_identity_tags'], isEmpty);
    expect(shared['display_name'], contains('shared'));
    expect(shared['display_name'], isNot(contains('girl')));
    expect(shared['frame_indexes'], [1, 2]);
    expect(
      (shared['prompt_terms'] as List).cast<Map>().single['source_occurrences'],
      [
        {'frame_index': 1, 'source_location': 'base prompt'},
        {'frame_index': 2, 'source_location': 'base prompt'},
      ],
    );
  });

  test(
      'prompt term occurrences preserve exact frame and physical source pairs through mapping',
      () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'script-recast-offline-source-occurrences-test-',
    );
    addTearDown(() async {
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });

    final updated = await _runOfflineBuilderFixture(
      tempRoot: tempRoot,
      fileName: 'script-source-occurrences.json',
      cache: _sourceOccurrencesCache(),
    );
    final roles =
        ((updated['aiRoleExtraction'] as Map)['roles'] as List).cast<Map>();
    final chiara = roles.singleWhere(
      (role) => (role['raw_identity_tags'] as List)
          .contains('chiara (black survival)'),
    );
    final term = (chiara['prompt_terms'] as List)
        .cast<Map>()
        .singleWhere((item) => item['text'] == 'black jacket');
    expect(term['frame_indexes'], [1, 2]);
    expect(term['source_location'], 'slot-0 prompt; slot-1 prompt');
    expect(term['source_occurrences'], [
      {'frame_index': 1, 'source_location': 'slot-0 prompt'},
      {'frame_index': 2, 'source_location': 'slot-1 prompt'},
    ]);

    final mapping = updated['mapping'] as Map;
    final replacement = (mapping['rolePromptReplacements'] as List)
        .cast<Map>()
        .singleWhere(
            (item) => item['sourceRoleId'] == chiara['source_role_id']);
    final rule = (replacement['rules'] as List).cast<Map>().singleWhere(
        (item) =>
            ((item['sourceTerms'] as List).single as Map)['text'] ==
            'black jacket');
    expect(((rule['sourceTerms'] as List).single as Map)['sourceOccurrences'], [
      {'frameIndex': 1, 'sourceLocation': 'slot-0 prompt'},
      {'frameIndex': 2, 'sourceLocation': 'slot-1 prompt'},
    ]);
  });

  test(
      'identity evidence remains a legacy summary and never becomes a physical occurrence',
      () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'script-recast-offline-identity-evidence-occurrence-test-',
    );
    addTearDown(() async {
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });

    final updated = await _runOfflineBuilderFixture(
      tempRoot: tempRoot,
      fileName: 'script-identity-evidence-occurrence.json',
      cache: _identityEvidenceOccurrenceCache(),
    );
    final roles =
        ((updated['aiRoleExtraction'] as Map)['roles'] as List).cast<Map>();
    final role = roles.singleWhere(
      (candidate) => candidate['source_role_id'] == 'role-alice-black-survival',
    );
    final term = (role['prompt_terms'] as List)
        .cast<Map>()
        .singleWhere((item) => item['text'] == 'alice (black survival)');
    expect(
      term['frame_indexes'],
      [1, 2],
      reason:
          'A role identity summary must not widen point-mapping frames beyond physical prompt evidence.',
    );
    expect(term['source_location'], contains('role identity evidence'));
    expect(term['source_occurrences'], [
      {'frame_index': 1, 'source_location': 'slot-0 prompt'},
      {'frame_index': 2, 'source_location': 'slot-0 prompt'},
    ]);
    final replacement = (updated['mapping']['rolePromptReplacements'] as List)
        .cast<Map>()
        .singleWhere((item) => item['sourceRoleId'] == role['source_role_id']);
    final rule = (replacement['rules'] as List).cast<Map>().singleWhere(
        (item) =>
            ((item['sourceTerms'] as List).single as Map)['text'] ==
            'alice (black survival)');
    expect(
        ((rule['sourceTerms'] as List).single as Map)['frameIndexes'], [1, 2]);
    expect(((rule['sourceTerms'] as List).single as Map)['sourceOccurrences'], [
      {'frameIndex': 1, 'sourceLocation': 'slot-0 prompt'},
      {'frameIndex': 2, 'sourceLocation': 'slot-0 prompt'},
    ]);
  });

  test(
      'offline extraction keeps a source-evidenced identity typo as a mapped alias',
      () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'script-recast-offline-identity-typo-alias-test-',
    );
    addTearDown(() async {
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });

    final cache = _fixtureCache('script-identity-typo-alias', [
      _fixtureFrame(
        1,
        charCaptions: const [
          'girl, alice (black survival), blue hair',
        ],
      ),
      _fixtureFrame(
        2,
        charCaptions: const [
          'girl, alice (black surviaval), blue hair',
        ],
      ),
      _fixtureFrame(
        3,
        charCaptions: const [
          'girl, alice (black survival), blue hair',
        ],
      ),
    ]);
    cache['mapping'] = {
      'id': 'mapping-script-identity-typo-alias',
      'scriptId': 'script-identity-typo-alias',
      'roleSwaps': [],
      'artistSwap': null,
      'roleAssemblies': [
        {
          'sourceRoleId': 'role-alice-black-survival',
          'displayLabel': 'alice (black survival) / 爱丽丝',
          'sourceName': 'alice (black survival) / 爱丽丝',
          'sourceAppearances': [
            {
              'sourceId': 'slot-0',
              'sourceKind': 'slot',
              'frameIndexes': [1, 2, 3],
            },
          ],
          'stages': [
            {
              'id': 'stage-1',
              'label': '旧阶段',
              'frameIndexes': [1, 2, 3],
              'sourceSummary': 'alice (black survival)',
              'sourceParts': {'identity': 'alice (black survival)'},
              'targetCharacterId': 'target-pepe',
            },
          ],
        },
      ],
      'rolePromptReplacements': [
        {
          'sourceRoleId': 'role-alice-black-survival',
          'displayLabel': 'alice (black survival) / 爱丽丝',
          'targetCharacterId': 'target-pepe',
          'targetIdentityPrompt': 'target-pepe',
          'rules': [
            {
              'id': 'existing-alice-identity',
              'sourceTerms': [
                {
                  'id': 'alice-canonical',
                  'text': 'alice (black survival)',
                  'category': 'character',
                },
              ],
              'action': 'replace',
              'targetPrompt': 'target-pepe',
            },
          ],
        },
      ],
    };

    final updated = await _runOfflineBuilderFixture(
      tempRoot: tempRoot,
      fileName: 'script-identity-typo-alias.json',
      cache: cache,
    );
    final roles =
        ((updated['aiRoleExtraction'] as Map)['roles'] as List).cast<Map>();
    final role = roles.singleWhere(
      (candidate) => candidate['source_role_id'] == 'role-alice-black-survival',
    );
    expect(
      roles.map((candidate) => candidate['source_role_id']),
      isNot(contains('role-alice-black-surviaval')),
    );
    expect(role['frame_indexes'], [1, 2, 3]);

    final promptTerms = (role['prompt_terms'] as List).cast<Map>();
    final canonicalTerm = promptTerms.singleWhere(
      (term) => term['text'] == 'alice (black survival)',
    );
    final typoTerm = promptTerms.singleWhere(
      (term) => term['text'] == 'alice (black surviaval)',
    );
    expect(canonicalTerm['frame_indexes'], [1, 3]);
    expect(typoTerm['frame_indexes'], [2]);
    expect(typoTerm['source_occurrences'], [
      {'frame_index': 2, 'source_location': 'slot-0 prompt'},
    ]);

    final replacement =
        (updated['mapping']['rolePromptReplacements'] as List).cast<Map>().single;
    final typoRule = (replacement['rules'] as List).cast<Map>().singleWhere(
      (rule) =>
          ((rule['sourceTerms'] as List).single as Map)['text'] ==
          'alice (black surviaval)',
    );
    expect(typoRule['action'], 'replace');
    expect(typoRule['targetPrompt'], 'target-pepe');
    expect(
      ((typoRule['sourceTerms'] as List).single as Map)['frameIndexes'],
      [2],
    );
  });

  test(
      'non-human generic identities do not anchor dog, canine, or wolf onto Mash across slot switches',
      () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'script-recast-offline-non-human-anchor-test-',
    );
    addTearDown(() async {
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });

    final updated = await _runOfflineBuilderFixture(
      tempRoot: tempRoot,
      fileName: 'script-non-human-anchor.json',
      cache: _nonHumanAnchorCache(),
      termReview: _nonHumanAnchorReview(),
      classificationCache: _nonHumanClassificationCache(),
    );
    final roles =
        ((updated['aiRoleExtraction'] as Map)['roles'] as List).cast<Map>();
    final mash = roles.singleWhere(
      (role) => (role['raw_identity_tags'] as List)
          .contains('mash_kyrielight_(demi-servant)'),
    );
    final fujimaru = roles.singleWhere(
      (role) => (role['raw_identity_tags'] as List)
          .contains('fujimaru ritsuka (female)'),
    );
    expect(mash['frame_indexes'], [1, 2]);
    expect(fujimaru['frame_indexes'], [3]);
    for (final entry in <String, int>{
      'dog': 4,
      'canine': 5,
      'wolf': 6,
    }.entries) {
      final role = roles.singleWhere(
        (candidate) =>
            (candidate['raw_identity_tags'] as List).contains(entry.key),
      );
      expect(role['source_role_id'], isNot(mash['source_role_id']));
      expect(role['source_role_id'], isNot(fujimaru['source_role_id']));
      expect(role['frame_indexes'], [entry.value]);
    }
  });

  test(
      'role mapping migration accepts exact generic split and rejects ambiguity',
      () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'script-recast-role-migration-test-',
    );
    addTearDown(() async {
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });

    Future<Map<String, dynamic>> rebuild({required bool ambiguous}) async {
      final scenario = ambiguous ? 'ambiguous' : 'unique';
      final cacheDir = Directory('${tempRoot.path}/$scenario-cache')
        ..createSync(recursive: true);
      final outputDir = Directory('${tempRoot.path}/$scenario-output');
      File('${cacheDir.path}/script-role-migration.json').writeAsStringSync(
        jsonEncode(_roleMigrationCache(ambiguous: ambiguous)),
      );
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
      return jsonDecode(
        File('${outputDir.path}/script-role-migration.json').readAsStringSync(),
      ) as Map<String, dynamic>;
    }

    final unique = await rebuild(ambiguous: false);
    final uniqueMapping = unique['mapping'] as Map<String, dynamic>;
    final uniqueReplacements =
        (uniqueMapping['rolePromptReplacements'] as List).cast<Map>();
    final uniqueConcrete = uniqueReplacements.where(
      (replacement) =>
          (replacement['sourceRoleId'] as String).contains('reisa') ||
          (replacement['sourceRoleId'] as String).contains('wakamo'),
    );
    expect(uniqueConcrete, hasLength(2));
    expect(
      uniqueConcrete.map((replacement) => replacement['targetCharacterId']),
      everyElement('target-shared'),
    );
    final uniqueAssemblies =
        (uniqueMapping['roleAssemblies'] as List).cast<Map>().where(
              (assembly) =>
                  (assembly['sourceRoleId'] as String).contains('reisa') ||
                  (assembly['sourceRoleId'] as String).contains('wakamo'),
            );
    expect(uniqueAssemblies, hasLength(2));
    expect(
      uniqueAssemblies.expand(
        (assembly) => (assembly['stages'] as List)
            .cast<Map>()
            .map((stage) => stage['targetCharacterId']),
      ),
      everyElement('stage-target-shared'),
    );

    final ambiguous = await rebuild(ambiguous: true);
    final ambiguousReplacements =
        ((ambiguous['mapping'] as Map)['rolePromptReplacements'] as List)
            .cast<Map>()
            .where(
              (replacement) =>
                  (replacement['sourceRoleId'] as String).contains('reisa') ||
                  (replacement['sourceRoleId'] as String).contains('wakamo'),
            );
    expect(ambiguousReplacements, hasLength(2));
    expect(
      ambiguousReplacements
          .every((replacement) => replacement['targetCharacterId'] == null),
      isTrue,
      reason:
          'Competing old generic roles must be rejected, not chosen by order.',
    );
  });

  test(
      'canonical variant merge preserves both legacy targets with frame-scoped conflicts',
      () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'script-recast-canonical-variant-migration-test-',
    );
    addTearDown(() async {
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });

    final updated = await _runOfflineBuilderFixture(
      tempRoot: tempRoot,
      fileName: 'script-canonical-variant-migration.json',
      cache: _canonicalVariantMigrationCache(),
    );
    expect(updated['aiRoleExtractionDraftCollapsed'], isTrue);
    expect(updated['aiRoleExtractionFinalized'], isTrue);
    final roles =
        ((updated['aiRoleExtraction'] as Map)['roles'] as List).cast<Map>();
    final ayakaRoles = roles
        .where((role) => role['canonical_name'] == 'kamisato ayaka')
        .toList();
    expect(ayakaRoles, hasLength(1));
    final ayaka = ayakaRoles.single;
    expect(
      (ayaka['stages'] as List)
          .cast<Map>()
          .map((stage) => stage['frame_indexes']),
      containsAll(<Object>[
        [1],
        [2],
      ]),
      reason:
          'Conflicting user targets must split the otherwise equivalent source stage.',
    );

    final mapping = updated['mapping'] as Map;
    final assembly = (mapping['roleAssemblies'] as List)
        .cast<Map>()
        .singleWhere((item) => item['sourceRoleId'] == ayaka['source_role_id']);
    final mappedStages = (assembly['stages'] as List).cast<Map>();
    expect(
      mappedStages.map((stage) => stage['targetCharacterId']).toSet(),
      {'target-pepe', 'target-suzuran'},
    );

    final replacement = (mapping['rolePromptReplacements'] as List)
        .cast<Map>()
        .singleWhere((item) => item['sourceRoleId'] == ayaka['source_role_id']);
    final blueHairRules = (replacement['rules'] as List).cast<Map>().where(
          (rule) =>
              (((rule['sourceTerms'] as List).single as Map)['text']) ==
              'blue hair',
        );
    expect(blueHairRules, hasLength(2));
    expect(
      blueHairRules.map((rule) => rule['targetPrompt']).toSet(),
      {'long_hair', 'blonde_hair, long_hair'},
    );
    expect(
      blueHairRules
          .map((rule) => (((rule['sourceTerms'] as List).single
                  as Map)['frameIndexes'] as List)
              .join(','))
          .toSet(),
      {'1', '2'},
    );
    final identityTargets = (replacement['rules'] as List)
        .cast<Map>()
        .where((rule) => rule['targetPrompt'] != null)
        .map((rule) => rule['targetPrompt'])
        .toSet();
    expect(
      identityTargets,
      containsAll({'pepe_(arknights)', 'suzuran_(arknights)'}),
    );
  });
}

Future<String> _sha256FileWithNode(File file) async {
  final result = await Process.run(
    'node',
    [
      '-e',
      "const fs=require('node:fs');"
          "const crypto=require('node:crypto');"
          "process.stdout.write(crypto.createHash('sha256')"
          ".update(fs.readFileSync(process.argv[1])).digest('hex'));",
      file.path,
    ],
    workingDirectory: Directory.current.path,
  );
  expect(
    result.exitCode,
    0,
    reason: 'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
  );
  return (result.stdout as String).trim();
}

Future<String> _manifestPositiveEvidenceSha({
  required Directory tempRoot,
  required String fileName,
  required Map<String, dynamic> cache,
  required String suffix,
}) async {
  final cacheDir = Directory('${tempRoot.path}/manifest-cache-$suffix')
    ..createSync(recursive: true);
  File('${cacheDir.path}/$fileName').writeAsStringSync(jsonEncode(cache));
  final manifestFile = File('${tempRoot.path}/manifest-$suffix.json');
  final result = await Process.run(
    'node',
    [
      'tool/build_script_recast_term_review_manifest.mjs',
      '--cache-dir',
      cacheDir.path,
      '--output',
      manifestFile.path,
    ],
    workingDirectory: Directory.current.path,
  );
  expect(
    result.exitCode,
    0,
    reason: 'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
  );
  final manifest =
      jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;
  final rows = (manifest['cache_files'] as List).cast<Map>();
  return rows.single['positive_evidence_sha256'] as String;
}

Map<String, dynamic> _completeTermReview() {
  Map<String, dynamic> role(String term, String category) => {
        'term': term,
        'placement': 'role',
        'category': category,
      };
  Map<String, dynamic> exclude(String term) => {
        'term': term,
        'placement': 'exclude',
      };
  return {
    'schema_version': 1,
    'kind': 'script_recast_term_membership_review',
    'reviewer': 'codex-fixture',
    'api_used': false,
    'decisions': [
      role('reisa (blue archive)', 'character'),
      role('alternate hairstyle', 'upperBody'),
      role('twin drills', 'upperBody'),
      role('high twintails', 'upperBody'),
      role('magical girl', 'character'),
      role('{{white witch hat', 'accessory'),
      role('no panties', 'clothingState'),
      role('bridal lingerie', 'clothing'),
      role('spade tattoo', 'other'),
      role('wet hair', 'upperBody'),
      role('white gloves', 'accessory'),
      role('elbow gloves', 'accessory'),
      role('boy', 'character'),
      role('faceless male', 'character'),
      role('large penis', 'lowerBody'),
      role('girl', 'character'),
      exclude('facial'),
      exclude('crotch focus'),
      exclude('standing'),
      exclude('pov hands'),
      {
        'term': 'outdoors',
        'placement': 'scene',
        'category': 'scene',
      },
      exclude('absurdres'),
    ],
  };
}

Map<String, dynamic> _termReviewRecastCache() {
  return {
    'scriptId': 'script-term-review',
    'scriptName': 'Term review fixture',
    'sourceRootPath': 'C:/fixture/term-review',
    'scriptSnapshot': {
      'id': 'script-term-review',
      'name': 'Term review fixture',
      'rootPath': 'C:/fixture/term-review',
      'detectedSchema': 'v4Partial',
      'frames': [
        {
          'index': 1,
          'fileName': 'nai_1.png',
          'rawJson': '{"prompt":"term review"}',
          'sourcePath': 'C:/fixture/term-review/nai_1.png',
          'sourceImagePath': 'C:/fixture/term-review/nai_1.png',
          'parseStatus': 'parsed',
          'parsed': {
            // Pure punctuation is prompt syntax, not a reviewable positive term.
            'baseCaption': 'outdoors, absurdres, large penis, !',
            'charCaptions': [
              'girl, reisa (blue archive), alternate hairstyle, twin drills, '
                  'high twintails, magical girl, {{white witch hat, no panties, '
                  'bridal lingerie, spade tattoo, facial, crotch focus, standing',
              'boy, faceless male',
            ],
            'negativeBase': '',
            'negativeCharCaptions': ['', ''],
          },
        },
        {
          'index': 2,
          'fileName': 'nai_2.png',
          'rawJson': '{"prompt":"term review 2"}',
          'sourcePath': 'C:/fixture/term-review/nai_2.png',
          'sourceImagePath': 'C:/fixture/term-review/nai_2.png',
          'parseStatus': 'parsed',
          'parsed': {
            'baseCaption': 'outdoors, wet hair',
            'charCaptions': [
              'girl, reisa (blue archive)',
            ],
            'negativeBase': '',
            'negativeCharCaptions': [''],
          },
        },
        {
          'index': 3,
          'fileName': 'nai_3.png',
          'rawJson': '{"prompt":"term review 3"}',
          'sourcePath': 'C:/fixture/term-review/nai_3.png',
          'sourceImagePath': 'C:/fixture/term-review/nai_3.png',
          'parseStatus': 'parsed',
          'parsed': {
            'baseCaption': 'outdoors',
            'charCaptions': [
              'girl, pov hands, white gloves, elbow gloves',
            ],
            'negativeBase': '',
            'negativeCharCaptions': [''],
          },
        },
      ],
    },
    'mapping': {
      'id': 'mapping-script-term-review',
      'scriptId': 'script-term-review',
      'roleSwaps': [],
      'artistSwap': null,
      'roleAssemblies': [
        {
          'sourceRoleId': 'role-girl-slot-0',
          'displayLabel': 'girl / 女孩',
          'sourceName': 'girl / 女孩',
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
              'label': '旧角色阶段',
              'frameIndexes': [1, 2],
              'sourceSummary': 'girl',
              'sourceParts': {'identity': 'girl'},
              'targetCharacterId': 'target-reisa',
            },
          ],
        },
      ],
      'rolePromptReplacements': [
        {
          'sourceRoleId': 'role-girl-slot-0',
          'displayLabel': 'girl / 女孩',
          'targetCharacterId': 'target-reisa',
          'rules': [
            {
              'id': 'existing-girl-identity',
              'sourceTerms': [
                {
                  'id': 'old-girl',
                  'text': 'girl',
                  'category': 'character',
                },
              ],
              'action': 'replace',
              'targetPrompt': 'pepe_(arknights)',
            },
            {
              'id': 'existing-high-twintails',
              'sourceTerms': [
                {
                  'id': 'old-high-twintails',
                  'text': 'high twintails',
                  'category': 'upperBody',
                },
              ],
              'action': 'replace',
              'targetPrompt': 'long hair',
            },
            {
              'id': 'existing-facial',
              'sourceTerms': [
                {
                  'id': 'old-facial',
                  'text': 'facial',
                  'category': 'upperBody',
                },
              ],
              'action': 'replace',
              'targetPrompt': 'should be removed',
            },
          ],
        },
      ],
    },
  };
}

Map<String, dynamic> _minimalRecastCache() {
  return {
    'scriptId': 'script-action-purity',
    'scriptName': 'Action purity fixture',
    'sourceRootPath': 'C:/fixture/action-purity',
    'sourceFingerprint': 'script-action-purity|C:/Fixture/Action-Purity|'
        '1:nai_1.png:C:/Fixture/Action-Purity/nai_1.png:deadbeef',
    'sourceContentFingerprint': 'original-source-content-fingerprint',
    'updatedAt': '2026-06-01T00:00:00.000Z',
    'scriptSnapshot': {
      'id': 'script-action-purity',
      'name': 'Action purity fixture',
      'rootPath': 'C:/fixture/action-purity',
      'detectedSchema': 'v4Partial',
      'frames': [
        {
          'index': 1,
          'fileName': 'nai_1.png',
          'rawJson': '{"prompt":"测试 prompt"}',
          'sourcePath': 'C:/fixture/action-purity/nai_1.png',
          'sourceImagePath': 'C:/fixture/action-purity/nai_1.png',
          'parseStatus': 'parsed',
          'parsed': {
            'baseCaption': 'indoors, detailed eyes',
            'charCaptions': [
              'girl, large breasts, bouncing breasts, breasts squeezed together, stomach bulge, face in crotch, wide eyes, dead eyes, deep flushed face, ass visible through thighs, clitoral hood, foot on another\'s face, legs wrapped around waist, tattoo machine (laser), tear another\'s pantyhose, shorts pull, shirt pull, pants pull, kimono pull, open legs, face down on sofa, black jacket, black pantyhose, white panties, standing, looking at viewer, blush, undressing, open shirt, lifting own clothes, presenting panties, pussy juice, spread pussy, cumdrip from penis, hands on penis, hands on own breasts, spread legs, presenting own pussy, adjusting hair, adjusting gloves, whispering in ear',
            ],
            'negativeBase': '',
            'negativeCharCaptions': [''],
          },
        },
      ],
    },
    'mapping': {
      'id': 'mapping-stale-script-id',
      'scriptId': 'stale-script-id',
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
        {
          'index': 3,
          'fileName': 'nai_3.png',
          'parseStatus': 'parsed',
          'parsed': {
            'baseCaption': '1girl, bedroom',
            'charCaptions': [
              'girl, kyoka (summer) (princess connect!), purple hair',
              'boy, disembodied hands, spreading another\'s legs, hands on thighs',
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

Map<String, dynamic> _partialStableRoleCache() {
  return {
    'scriptId': 'script-partial-stable',
    'scriptName': 'Partial stable role fixture',
    'sourceRootPath': 'C:/fixture/partial-stable',
    'scriptSnapshot': {
      'frames': [
        for (var index = 1; index <= 4; index += 1)
          {
            'index': index,
            'fileName': 'nai_$index.png',
            'parseStatus': 'parsed',
            'parsed': {
              'baseCaption': '1girl, indoors',
              'charCaptions': [
                'girl, ako (dress) (blue archive), black dress',
                if (index < 4)
                  'boy, sensei (blue archive the animation), very dark skin'
                else
                  'boy, pov hands, very dark skin, grabbing another\'s arms',
              ],
            },
          },
      ],
    },
    'mapping': {
      'id': 'mapping-script-partial-stable',
      'scriptId': 'script-partial-stable',
      'roleSwaps': [],
      'artistSwap': null,
    },
  };
}

Map<String, dynamic> _genericSlotCollisionCache() {
  return {
    'scriptId': 'script-generic-slot-collision',
    'scriptName': 'Generic slot collision fixture',
    'sourceRootPath': 'C:/fixture/generic-slot-collision',
    'scriptSnapshot': {
      'frames': [
        {
          'index': 1,
          'fileName': 'nai_1.png',
          'parseStatus': 'parsed',
          'parsed': {
            'baseCaption': '2boys, indoors',
            'charCaptions': [
              'boy, muscular male, black shirt',
              'boy, muscular male, white shirt',
            ],
          },
        },
      ],
    },
    'mapping': {
      'id': 'mapping-script-generic-slot-collision',
      'scriptId': 'script-generic-slot-collision',
      'roleSwaps': [],
      'artistSwap': null,
    },
  };
}

Map<String, dynamic> _pseudoCharacterCache() {
  return {
    'scriptId': 'script-pseudo-character',
    'scriptName': 'Pseudo character fixture',
    'sourceRootPath': 'C:/fixture/pseudo-character',
    'scriptSnapshot': {
      'frames': [
        for (final entry in <(int, String)>[
          (1, 'boy, foreskin, muscular male'),
          (2, 'no humans'),
          (3, 'boy, touching (character 1), dark-skinned male'),
          (4, 'boy, behind (chiara), muscular male'),
          (5, 'girl, kokkoro (princess connect!), green dress'),
          (6, 'boy, goblin slayer, grey armor, rebellion (sword)'),
          (7, 'girl, iroha (blue archive), ring of light (blue archive)'),
        ])
          {
            'index': entry.$1,
            'fileName': 'nai_${entry.$1}.png',
            'parseStatus': 'parsed',
            'parsed': {
              'baseCaption': 'indoors',
              'charCaptions': [entry.$2],
            },
          },
      ],
    },
    'mapping': {
      'id': 'mapping-script-pseudo-character',
      'scriptId': 'script-pseudo-character',
      'roleSwaps': [],
      'artistSwap': null,
    },
  };
}

Map<String, dynamic> _offFrameMaleCache() {
  return {
    'scriptId': 'script-off-frame-role',
    'scriptName': 'Off-frame role fixture',
    'sourceRootPath': 'C:/fixture/off-frame-role',
    'scriptSnapshot': {
      'frames': [
        {
          'index': 1,
          'fileName': 'nai_1.png',
          'parseStatus': 'parsed',
          'parsed': {
            'baseCaption': 'indoors',
            'charCaptions': [
              'boy, very dark-skinned male, muscular, out of frame',
            ],
          },
        },
        {
          'index': 2,
          'fileName': 'nai_2.png',
          'parseStatus': 'parsed',
          'parsed': {
            'baseCaption': 'indoors',
            'charCaptions': [
              'boy, silhouette, see-through silhouette, muscular, shadow',
            ],
          },
        },
      ],
    },
    'mapping': {
      'id': 'mapping-script-off-frame-role',
      'scriptId': 'script-off-frame-role',
      'roleSwaps': [],
      'artistSwap': null,
    },
  };
}

Map<String, dynamic> _stageActionStateCache() {
  return {
    'scriptId': 'script-stage-action-state',
    'scriptName': 'Stage action state fixture',
    'sourceRootPath': 'C:/fixture/stage-action-state',
    'scriptSnapshot': {
      'detectedSchema': 'v4Partial',
      'frames': [
        {
          'index': 1,
          'fileName': 'nai_1.png',
          'rawJson': '{}',
          'parseStatus': 'parsed',
          'parsed': {
            'baseCaption': 'indoors',
            'charCaptions': [
              "boy, nude, bikini top pull, hands on bikini top, hand inside 1 girl's bikini bottom",
            ],
          },
        },
        {
          'index': 2,
          'fileName': 'nai_2.png',
          'rawJson': '{}',
          'parseStatus': 'parsed',
          'parsed': {
            'baseCaption': 'indoors',
            'charCaptions': ['boy, nude'],
          },
        },
      ],
    },
    'mapping': {
      'id': 'mapping-script-stage-action-state',
      'scriptId': 'script-stage-action-state',
      'roleSwaps': [],
      'artistSwap': null,
    },
  };
}

Map<String, dynamic> _stageTransitionCache() {
  return _fixtureCache('script-stage-transition', [
    _fixtureFrame(
      1,
      charCaptions: const [
        'girl, chiara (black survival), topless, black underwear',
      ],
    ),
    _fixtureFrame(
      2,
      charCaptions: const [
        'girl, chiara (black survival), topless, black underwear',
      ],
    ),
    _fixtureFrame(
      3,
      charCaptions: const [
        'girl, chiara (black survival), topless, black underwear, underwear aside. sex',
      ],
    ),
    _fixtureFrame(
      4,
      charCaptions: const [
        'girl, chiara (black survival), topless, black underwear, panties pull sideways. sex',
      ],
    ),
    _fixtureFrame(
      5,
      charCaptions: const [
        'girl, chiara (black survival), topless',
      ],
    ),
    _fixtureFrame(
      6,
      charCaptions: const [
        'girl, chiara (black survival), topless',
      ],
    ),
  ]);
}

Map<String, dynamic> _stageTransitionReview() {
  return _reviewDocument([
    ('girl', 'character'),
    ('chiara (black survival)', 'character'),
    ('topless', 'clothingState'),
    ('black underwear', 'lowerClothing'),
    ('underwear aside. sex', 'clothingState'),
    ('panties pull sideways. sex', 'clothingState'),
  ]);
}

Map<String, dynamic> _stageLabelOwnerIsolationCache() {
  return _fixtureCache('script-stage-label-owner', [
    _fixtureFrame(
      1,
      charCaptions: const [
        'boy, yuuki (princess connect!), male topless, no lower clothing',
      ],
    ),
    _fixtureFrame(
      2,
      charCaptions: const [
        'boy, yuuki (princess connect!), male topless, no lower clothing',
      ],
    ),
    _fixtureFrame(
      3,
      charCaptions: const [
        'boy, yuuki (princess connect!), male topless, no lower clothing',
      ],
    ),
    _fixtureFrame(
      4,
      charCaptions: const [
        'blue swimsuit',
      ],
    ),
    _fixtureFrame(
      5,
      charCaptions: const [
        'boy, yuuki (princess connect!), male topless, no lower clothing',
      ],
    ),
    _fixtureFrame(
      6,
      charCaptions: const [
        'boy, yuuki (princess connect!), male topless, no lower clothing',
      ],
    ),
    _fixtureFrame(
      7,
      charCaptions: const [
        'boy, yuuki (princess connect!), male topless, no lower clothing',
      ],
    ),
  ]);
}

Map<String, dynamic> _roleMigrationCache({required bool ambiguous}) {
  Map<String, dynamic> previousAssembly(String suffix, String target) => {
        'sourceRoleId': 'role-girl-slot-0-$suffix',
        'displayLabel': 'girl / 女孩 $suffix',
        'sourceName': 'girl / 女孩 $suffix',
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
            'label': 'old generic stage',
            'frameIndexes': [1, 2],
            'sourceSummary': 'girl',
            'sourceParts': {'identity': 'girl'},
            'targetCharacterId': target,
          },
        ],
      };
  Map<String, dynamic> previousReplacement(String suffix, String target) => {
        'sourceRoleId': 'role-girl-slot-0-$suffix',
        'displayLabel': 'girl / 女孩 $suffix',
        'targetCharacterId': target,
        'targetIdentityPrompt': 'target prompt $suffix',
        'rules': [
          {
            'id': 'identity-$suffix',
            'sourceTerms': [
              {
                'id': 'girl-$suffix',
                'text': 'girl',
                'category': 'character',
              },
            ],
            'action': 'replace',
            'targetPrompt': 'target prompt $suffix',
          },
        ],
      };

  final assemblies = [
    previousAssembly('a', 'stage-target-shared'),
    if (ambiguous) previousAssembly('b', 'stage-target-conflict'),
  ];
  final replacements = [
    previousReplacement('a', 'target-shared'),
    if (ambiguous) previousReplacement('b', 'target-conflict'),
  ];
  return {
    'scriptId': 'script-role-migration',
    'scriptName': 'Role migration fixture',
    'sourceRootPath': 'C:/fixture/role-migration',
    'scriptSnapshot': {
      'detectedSchema': 'v4Partial',
      'frames': [
        {
          'index': 1,
          'fileName': 'nai_1.png',
          'rawJson': '{}',
          'parseStatus': 'parsed',
          'parsed': {
            'baseCaption': 'indoors',
            'charCaptions': [
              'girl, reisa (blue archive), long hair, school uniform',
            ],
          },
        },
        {
          'index': 2,
          'fileName': 'nai_2.png',
          'rawJson': '{}',
          'parseStatus': 'parsed',
          'parsed': {
            'baseCaption': 'indoors',
            'charCaptions': [
              'girl, wakamo (blue archive), long hair, school uniform',
            ],
          },
        },
      ],
    },
    'mapping': {
      'id': 'mapping-script-role-migration',
      'scriptId': 'script-role-migration',
      'roleSwaps': [],
      'artistSwap': null,
      'roleAssemblies': assemblies,
      'rolePromptReplacements': replacements,
    },
  };
}

Map<String, dynamic> _canonicalVariantMigrationCache() {
  Map<String, dynamic> assembly({
    required String roleId,
    required String sourceName,
    required int frameIndex,
    required String targetCharacterId,
  }) =>
      {
        'sourceRoleId': roleId,
        'displayLabel': sourceName,
        'sourceName': sourceName,
        'sourceAppearances': [
          {
            'sourceId': 'slot-0',
            'sourceKind': 'slot',
            'frameIndexes': [frameIndex],
          },
        ],
        'stages': [
          {
            'id': '$roleId-stage-1',
            'label': 'old nude stage',
            'frameIndexes': [frameIndex],
            'sourceSummary': 'completely nude',
            'sourceParts': {
              'identity': 'girl',
              'upperClothing': 'completely nude'
            },
            'targetCharacterId': targetCharacterId,
          },
        ],
      };
  Map<String, dynamic> replacement({
    required String roleId,
    required String identity,
    required String identityTarget,
    required String hairTarget,
  }) =>
      {
        'sourceRoleId': roleId,
        'displayLabel': identity,
        'rules': [
          {
            'id': '$roleId-identity',
            'sourceTerms': [
              {
                'id': '$roleId-identity-term',
                'text': identity,
                'category': 'character',
              },
            ],
            'action': 'replace',
            'targetPrompt': identityTarget,
          },
          {
            'id': '$roleId-blue-hair',
            'sourceTerms': [
              {
                'id': '$roleId-blue-hair-term',
                'text': 'blue hair',
                'category': 'upperBody',
              },
            ],
            'action': 'replace',
            'targetPrompt': hairTarget,
          },
        ],
      };

  const baseRoleId = 'role-kamisato-ayaka';
  const variantRoleId = 'role-kamisato-ayaka-springbloom-missive';
  return {
    'scriptId': 'script-canonical-variant-migration',
    'scriptName': 'Canonical variant migration fixture',
    'sourceRootPath': 'C:/fixture/canonical-variant-migration',
    'scriptSnapshot': {
      'detectedSchema': 'v4Partial',
      'frames': [
        {
          'index': 1,
          'fileName': 'nai_1.png',
          'rawJson': '{}',
          'parseStatus': 'parsed',
          'parsed': {
            'baseCaption': 'indoors',
            'charCaptions': [
              'girl, kamisato ayaka, blue hair, completely nude',
            ],
          },
        },
        {
          'index': 2,
          'fileName': 'nai_2.png',
          'rawJson': '{}',
          'parseStatus': 'parsed',
          'parsed': {
            'baseCaption': 'indoors',
            'charCaptions': [
              'girl, kamisato ayaka (springbloom missive), blue hair, completely nude',
            ],
          },
        },
      ],
    },
    'mapping': {
      'id': 'mapping-script-canonical-variant-migration',
      'scriptId': 'script-canonical-variant-migration',
      'roleSwaps': [],
      'artistSwap': null,
      'roleAssemblies': [
        assembly(
          roleId: baseRoleId,
          sourceName: 'kamisato ayaka / \u795e\u91cc\u7eeb\u534e',
          frameIndex: 1,
          targetCharacterId: 'target-pepe',
        ),
        assembly(
          roleId: variantRoleId,
          sourceName:
              'kamisato ayaka (springbloom missive) / \u795e\u91cc\u7eeb\u534e\uff08\u6625\u7efd\u6765\u4fe1\uff09',
          frameIndex: 2,
          targetCharacterId: 'target-suzuran',
        ),
      ],
      'rolePromptReplacements': [
        replacement(
          roleId: baseRoleId,
          identity: 'kamisato ayaka',
          identityTarget: 'pepe_(arknights)',
          hairTarget: 'long_hair',
        ),
        replacement(
          roleId: variantRoleId,
          identity: 'kamisato ayaka (springbloom missive)',
          identityTarget: 'suzuran_(arknights)',
          hairTarget: 'blonde_hair, long_hair',
        ),
      ],
    },
  };
}

Future<Map<String, dynamic>> _runOfflineBuilderFixture({
  required Directory tempRoot,
  required String fileName,
  required Map<String, dynamic> cache,
  Map<String, dynamic>? termReview,
  Map<String, dynamic>? classificationCache,
}) async {
  final cacheDir = Directory('${tempRoot.path}/cache')
    ..createSync(recursive: true);
  final outputDir = Directory('${tempRoot.path}/output')
    ..createSync(recursive: true);
  File('${cacheDir.path}/$fileName').writeAsStringSync(jsonEncode(cache));
  final translationCacheFile = File('${tempRoot.path}/translations.json')
    ..writeAsStringSync('{}');
  final args = [
    'tool/build_script_recast_ai_extraction_offline.mjs',
    '--cache-dir',
    cacheDir.path,
    '--output-dir',
    outputDir.path,
    '--translation-cache',
    translationCacheFile.path,
  ];
  if (termReview != null) {
    final reviewFile = File('${tempRoot.path}/term-review.json')
      ..writeAsStringSync(jsonEncode(termReview));
    args.addAll(['--term-review', reviewFile.path]);
  }
  if (classificationCache != null) {
    final classificationFile = File('${tempRoot.path}/classification.json')
      ..writeAsStringSync(jsonEncode(classificationCache));
    args.addAll(['--classification-cache', classificationFile.path]);
  }
  args.add('--apply');

  final result = await Process.run(
    'node',
    args,
    workingDirectory: Directory.current.path,
  );
  expect(
    result.exitCode,
    0,
    reason: 'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
  );
  return jsonDecode(
    File('${outputDir.path}/$fileName').readAsStringSync(),
  ) as Map<String, dynamic>;
}

Map<String, dynamic> _fixtureFrame(
  int index, {
  String baseCaption = '',
  required List<String> charCaptions,
}) {
  return {
    'index': index,
    'fileName': 'nai_$index.png',
    'parseStatus': 'parsed',
    'parsed': {
      'baseCaption': baseCaption,
      'charCaptions': charCaptions,
      'negativeBase': '',
      'negativeCharCaptions': [for (final _ in charCaptions) ''],
    },
  };
}

Map<String, dynamic> _fixtureCache(
  String scriptId,
  List<Map<String, dynamic>> frames,
) {
  return {
    'scriptId': scriptId,
    'scriptName': scriptId,
    'scriptSnapshot': {'frames': frames},
    'mapping': {
      'id': 'mapping-$scriptId',
      'scriptId': scriptId,
      'roleSwaps': [],
      'artistSwap': null,
    },
  };
}

Map<String, dynamic> _reviewDocument(
  List<(String, String)> roles,
) {
  return {
    'schema_version': 1,
    'kind': 'script_recast_term_membership_review',
    'reviewer': 'codex-fixture',
    'api_used': false,
    'decisions': [
      for (final role in roles)
        {
          'term': role.$1,
          'placement': 'role',
          'category': role.$2,
        },
    ],
  };
}

Map<String, dynamic> _reviewedGenderRoutingCache() {
  return _fixtureCache('script-reviewed-gender-routing', [
    _fixtureFrame(
      1,
      charCaptions: const [
        'girl, chiara (black survival), large breasts',
        'boy, faceless male, muscular',
      ],
    ),
    _fixtureFrame(
      2,
      charCaptions: const [
        'girl, chiara (black survival), large breasts, large penis',
      ],
    ),
  ]);
}

Map<String, dynamic> _reviewedGenderRoutingReview() {
  return _reviewDocument([
    ('girl', 'character'),
    ('chiara (black survival)', 'character'),
    ('large breasts', 'upperBody'),
    ('large penis', 'lowerBody'),
    ('boy', 'character'),
    ('faceless male', 'character'),
  ]);
}

Map<String, dynamic> _sharedAnatomyFallbackCache() {
  return _fixtureCache('script-shared-anatomy-fallback', [
    _fixtureFrame(
      1,
      baseCaption: '2girls, large penis',
      charCaptions: const [
        'girl, chiara (black survival), large breasts',
        'girl, xuelin (black survival), large breasts',
      ],
    ),
    _fixtureFrame(
      2,
      baseCaption: '2girls, large penis',
      charCaptions: const [
        'girl, chiara (black survival), large breasts',
        'girl, xuelin (black survival), large breasts',
      ],
    ),
  ]);
}

Map<String, dynamic> _sharedAnatomyFallbackReview() {
  return _reviewDocument([
    ('large penis', 'lowerBody'),
    ('girl', 'character'),
    ('chiara (black survival)', 'character'),
    ('xuelin (black survival)', 'character'),
    ('large breasts', 'upperBody'),
  ]);
}

Map<String, dynamic> _sourceOccurrencesCache() {
  return _fixtureCache('script-source-occurrences', [
    _fixtureFrame(
      1,
      charCaptions: const [
        'girl, chiara (black survival), black jacket',
      ],
    ),
    _fixtureFrame(
      2,
      charCaptions: const [
        '',
        'girl, chiara (black survival), black jacket',
      ],
    ),
  ]);
}

Map<String, dynamic> _identityEvidenceOccurrenceCache() {
  return _fixtureCache('script-identity-evidence-occurrence', [
    _fixtureFrame(
      1,
      charCaptions: const [
        'girl, alice (black survival), large breasts',
      ],
    ),
    _fixtureFrame(
      2,
      charCaptions: const [
        'girl, alice (black survival), large breasts',
      ],
    ),
    _fixtureFrame(
      3,
      charCaptions: const [
        'girl, large breasts',
      ],
    ),
  ]);
}

Map<String, dynamic> _nonHumanAnchorCache() {
  return _fixtureCache('script-non-human-anchor', [
    _fixtureFrame(
      1,
      charCaptions: const [
        'girl, mash_kyrielight_(demi-servant), large breasts',
      ],
    ),
    _fixtureFrame(
      2,
      charCaptions: const [
        'girl, mash_kyrielight_(demi-servant), large breasts',
      ],
    ),
    _fixtureFrame(
      3,
      charCaptions: const [
        'girl, fujimaru ritsuka (female), large breasts',
      ],
    ),
    _fixtureFrame(
      4,
      charCaptions: const [
        'dog, large body',
      ],
    ),
    _fixtureFrame(
      5,
      charCaptions: const [
        'canine, large body',
      ],
    ),
    _fixtureFrame(
      6,
      charCaptions: const [
        'wolf, large body',
      ],
    ),
  ]);
}

Map<String, dynamic> _nonHumanAnchorReview() {
  return _reviewDocument([
    ('girl', 'character'),
    ('mash_kyrielight_(demi-servant)', 'character'),
    ('fujimaru ritsuka (female)', 'character'),
    ('large breasts', 'upperBody'),
    ('dog', 'character'),
    ('canine', 'character'),
    ('wolf', 'character'),
  ]);
}

Map<String, dynamic> _nonHumanClassificationCache() {
  return {
    'positive:dog': {'category': 'other'},
    'positive:canine': {'category': 'other'},
    'positive:wolf': {'category': 'other'},
  };
}
