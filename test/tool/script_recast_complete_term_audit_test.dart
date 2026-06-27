import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('audits complete source terms without local repair', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'script-recast-complete-term-audit-test-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final cacheDir = Directory('${tempDir.path}${Platform.pathSeparator}cache')
      ..createSync(recursive: true);
    final sourceRoot = '${tempDir.path}${Platform.pathSeparator}source';
    final reportFile =
        File('${tempDir.path}${Platform.pathSeparator}report.json');
    final cacheFile =
        File('${cacheDir.path}${Platform.pathSeparator}cache.json');
    await cacheFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(
        _cacheJson(
          sourceRootPath: sourceRoot,
          promptTerms: [
            _term('term-double-bun', 'double bun', 'upperBody'),
          ],
          sceneTerms: [
            _term('scene-bedroom', 'bedroom', 'scene'),
          ],
          roleRules: [
            _rule(
              'legacy-double-bun-rule',
              _term('legacy-double-bun', 'double bun', 'upperBody'),
              targetPrompt: 'single braid',
            ),
          ],
          sceneRules: [
            _rule(
              'legacy-bedroom-rule',
              _term('scene-bedroom', 'bedroom', 'scene'),
              targetPrompt: 'sunny courtyard',
            ),
          ],
        ),
      ),
      encoding: utf8,
    );
    final before = await cacheFile.readAsString(encoding: utf8);

    final result = await Process.run(
      'node',
      [
        'tool/script_recast_complete_term_audit.mjs',
        '--cache-dir',
        cacheDir.path,
        '--source-root',
        sourceRoot,
        '--report',
        reportFile.path,
        '--report-unchanged',
      ],
      workingDirectory: Directory.current.path,
      runInShell: Platform.isWindows,
    );

    expect(result.exitCode, 0, reason: result.stderr.toString());
    expect(await cacheFile.readAsString(encoding: utf8), before);

    final report = jsonDecode(await reportFile.readAsString(encoding: utf8))
        as Map<String, dynamic>;
    expect(report['api_used'], isFalse);
    expect(report['eligible_cache_files'], 1);
    expect(report['files_changed'], 0);
    final rows = (report['rows'] as List).cast<Map<String, dynamic>>();
    expect(rows, hasLength(1));
    expect(rows.single['source_term_count'], greaterThanOrEqualTo(5));
    expect(
      (rows.single['target_regression_candidates'] as List)
          .cast<Map<String, dynamic>>()
          .map((row) => row['normalized']),
      containsAll(['gyaru', 'demon girl', 'cristal wings']),
    );
  });

  test('applies explicit schema while preserving confirmed mappings', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'script-recast-complete-term-repair-test-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final cacheDir = Directory('${tempDir.path}${Platform.pathSeparator}cache')
      ..createSync(recursive: true);
    final backupDir =
        Directory('${tempDir.path}${Platform.pathSeparator}backup');
    final sourceRoot = '${tempDir.path}${Platform.pathSeparator}source';
    final cacheFile =
        File('${cacheDir.path}${Platform.pathSeparator}cache.json');
    final schemaFile =
        File('${tempDir.path}${Platform.pathSeparator}schema.json');

    await cacheFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(
        _cacheJson(
          sourceRootPath: sourceRoot,
          promptTerms: [
            _term('legacy-strap-slip-prompt', 'strap slip', 'clothing'),
            _term('refined-strap-slip-prompt', 'strap slip', 'clothingState'),
            _term('legacy-black-collar-prompt', 'black collar', 'clothing'),
            _term('refined-black-collar-prompt', 'black collar', 'accessory'),
          ],
          sceneTerms: const [],
          roleRules: [
            _rule(
              'legacy-double-bun-rule',
              _term('legacy-double-bun', 'double bun', 'upperBody'),
              targetPrompt: 'single braid',
            ),
            _rule(
              'legacy-strap-slip-rule',
              _term('legacy-strap-slip', 'strap slip', 'clothing'),
              targetPrompt: 'dress slipping off shoulder',
            ),
            _rule(
              'legacy-black-collar-rule',
              _term('legacy-black-collar', 'black collar', 'clothing'),
              targetPrompt: 'leather collar',
            ),
          ],
          sceneRules: const [],
        ),
      ),
      encoding: utf8,
    );
    await schemaFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'version': 1,
        'caches': [
          {
            'scriptId': 'script-a',
            'rolePromptTerms': [
              {
                'sourceRoleId': 'role-a',
                'displayLabel': 'Role A',
                'terms': [
                  _term('term-double-bun', 'double bun', 'upperBody'),
                  _term(
                    'term-inverted-nipples',
                    'inverted nipples',
                    'upperBody',
                  ),
                  _term(
                    'term-strap-slip',
                    'strap slip',
                    'clothingState',
                  ),
                  _term(
                    'term-black-collar',
                    'black collar',
                    'accessory',
                  ),
                  _term('term-gyaru', 'gyaru', 'character'),
                ],
              },
            ],
            'sceneTerms': [
              _term('scene-bedroom', 'bedroom', 'scene'),
            ],
            'termCacheSuggestions': [
              {
                'text': 'gyaru',
                'translation': '辣妹',
                'category': 'character',
                'source': 'codex_offline',
              },
            ],
          },
        ],
      }),
      encoding: utf8,
    );

    final result = await Process.run(
      'node',
      [
        'tool/script_recast_complete_term_audit.mjs',
        '--cache-dir',
        cacheDir.path,
        '--source-root',
        sourceRoot,
        '--schema',
        schemaFile.path,
        '--apply',
        '--backup-dir',
        backupDir.path,
      ],
      workingDirectory: Directory.current.path,
      runInShell: Platform.isWindows,
    );

    expect(result.exitCode, 0, reason: result.stderr.toString());
    final updated = jsonDecode(await cacheFile.readAsString(encoding: utf8))
        as Map<String, dynamic>;
    final role = (updated['aiRoleExtraction']['roles'] as List).single
        as Map<String, dynamic>;
    expect(
      (role['prompt_terms'] as List)
          .cast<Map<String, dynamic>>()
          .map((term) => '${term['text']}|${term['category']}'),
      [
        'strap slip|clothingState',
        'black collar|accessory',
        'double bun|upperBody',
        'inverted nipples|upperBody',
        'gyaru|character',
      ],
    );
    final replacement = (updated['mapping']['rolePromptReplacements'] as List)
        .single as Map<String, dynamic>;
    final rules = (replacement['rules'] as List).cast<Map<String, dynamic>>();
    expect(rules, hasLength(5));
    Map<String, dynamic> ruleById(String id) =>
        rules.singleWhere((rule) => rule['id'] == id);
    final doubleBunRule = ruleById('legacy-double-bun-rule');
    final strapSlipRule = ruleById('legacy-strap-slip-rule');
    final blackCollarRule = ruleById('legacy-black-collar-rule');
    final gyaruRule = rules.singleWhere(
      (rule) =>
          ((rule['sourceTerms'] as List).single
              as Map<String, dynamic>)['text'] ==
          'gyaru',
    );
    expect(doubleBunRule['targetPrompt'], 'single braid');
    expect(
      ((doubleBunRule['sourceTerms'] as List).single
          as Map<String, dynamic>)['id'],
      'term-double-bun',
    );
    expect(strapSlipRule['targetPrompt'], 'dress slipping off shoulder');
    expect(
      ((strapSlipRule['sourceTerms'] as List).single as Map<String, dynamic>),
      containsPair('category', 'clothingState'),
    );
    expect(blackCollarRule['targetPrompt'], 'leather collar');
    expect(
      ((blackCollarRule['sourceTerms'] as List).single as Map<String, dynamic>),
      containsPair('category', 'accessory'),
    );
    expect(
      ((gyaruRule['sourceTerms'] as List).single as Map<String, dynamic>),
      containsPair('text', 'gyaru'),
    );
    expect(
      (rules
          .expand(
            (rule) => (rule['sourceTerms'] as List)
                .cast<Map<String, dynamic>>()
                .map((term) => '${term['text']}|${term['category']}'),
          )
          .toList()),
      containsAll([
        'double bun|upperBody',
        'inverted nipples|upperBody',
        'strap slip|clothingState',
        'black collar|accessory',
        'gyaru|character',
      ]),
    );
    expect(updated['aiRoleExtraction']['scene_terms'], hasLength(1));
    expect(updated['mapping']['scenePromptReplacements'], hasLength(1));
    expect(updated['aiRoleExtraction']['term_cache_suggestions'], hasLength(1));
    final backups = backupDir
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.json'))
        .toList();
    expect(backups, hasLength(1));
  });

  test(
    'collapses polluted legacy category duplicates and stays idempotent',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'script-recast-complete-term-polluted-test-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final cacheDir =
          Directory('${tempDir.path}${Platform.pathSeparator}cache')
            ..createSync(recursive: true);
      final backupDir =
          Directory('${tempDir.path}${Platform.pathSeparator}backup');
      final sourceRoot = '${tempDir.path}${Platform.pathSeparator}source';
      final cacheFile =
          File('${cacheDir.path}${Platform.pathSeparator}cache.json');
      final schemaFile =
          File('${tempDir.path}${Platform.pathSeparator}schema.json');

      await cacheFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(
          _cacheJson(
            sourceRootPath: sourceRoot,
            promptTerms: [
              _term('legacy-strap-slip-prompt', 'strap slip', 'clothing'),
              _term('legacy-black-collar-prompt', 'black collar', 'clothing'),
            ],
            sceneTerms: const [],
            roleRules: [
              _rule(
                'refined-strap-slip-rule',
                _term(
                  'refined-strap-slip',
                  'strap slip',
                  'clothingState',
                ),
                targetPrompt: 'dress slipping off shoulder',
              ),
              _rule(
                'refined-black-collar-rule',
                _term('refined-black-collar', 'black collar', 'accessory'),
                targetPrompt: 'leather collar',
              ),
              _rule(
                'legacy-strap-slip-rule',
                _term('legacy-strap-slip', 'strap slip', 'clothing'),
                targetPrompt: 'old legacy strap slip target',
              ),
              _rule(
                'legacy-black-collar-rule',
                _term('legacy-black-collar', 'black collar', 'clothing'),
                targetPrompt: 'old legacy black collar target',
              ),
            ],
            sceneRules: const [],
          ),
        ),
        encoding: utf8,
      );
      await schemaFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'version': 1,
          'caches': [
            {
              'scriptId': 'script-a',
              'rolePromptTerms': [
                {
                  'sourceRoleId': 'role-a',
                  'displayLabel': 'Role A',
                  'terms': [
                    _term(
                      'term-strap-slip',
                      'strap slip',
                      'clothingState',
                    ),
                    _term(
                      'term-black-collar',
                      'black collar',
                      'accessory',
                    ),
                  ],
                },
              ],
            },
          ],
        }),
        encoding: utf8,
      );

      Future<ProcessResult> applySchema() {
        return Process.run(
          'node',
          [
            'tool/script_recast_complete_term_audit.mjs',
            '--cache-dir',
            cacheDir.path,
            '--source-root',
            sourceRoot,
            '--schema',
            schemaFile.path,
            '--apply',
            '--backup-dir',
            backupDir.path,
          ],
          workingDirectory: Directory.current.path,
          runInShell: Platform.isWindows,
        );
      }

      final firstApply = await applySchema();
      expect(firstApply.exitCode, 0, reason: firstApply.stderr.toString());

      final firstUpdated =
          jsonDecode(await cacheFile.readAsString(encoding: utf8))
              as Map<String, dynamic>;
      final firstPromptTerms = (((firstUpdated['aiRoleExtraction']
              as Map<String, dynamic>)['roles'] as List)
          .single as Map<String, dynamic>)['prompt_terms'] as List;
      final firstRules = (((firstUpdated['mapping']
              as Map<String, dynamic>)['rolePromptReplacements'] as List)
          .single as Map<String, dynamic>)['rules'] as List;
      expect(
        firstPromptTerms
            .cast<Map<String, dynamic>>()
            .map((term) => '${term['text']}|${term['category']}')
            .toList(),
        [
          'strap slip|clothingState',
          'black collar|accessory',
        ],
      );
      final firstRuleIds = firstRules
          .cast<Map<String, dynamic>>()
          .map((rule) => rule['id'] as String)
          .toList();
      expect(firstRules, hasLength(2));
      expect(firstRuleIds, isNot(contains('legacy-strap-slip-rule')));
      expect(firstRuleIds, isNot(contains('legacy-black-collar-rule')));
      expect(
        firstRuleIds,
        [
          'refined-strap-slip-rule',
          'refined-black-collar-rule',
        ],
      );
      expect(
        firstRules.cast<Map<String, dynamic>>().expand(
              (rule) => (rule['sourceTerms'] as List)
                  .cast<Map<String, dynamic>>()
                  .map((term) => '${term['text']}|${term['category']}'),
            ),
        [
          'strap slip|clothingState',
          'black collar|accessory',
        ],
      );
      final afterFirstApply = await cacheFile.readAsString(encoding: utf8);

      final secondApply = await applySchema();
      expect(secondApply.exitCode, 0, reason: secondApply.stderr.toString());
      final afterSecondApply = await cacheFile.readAsString(encoding: utf8);
      expect(afterSecondApply, afterFirstApply);
    },
  );

  test(
    'does not merge refined replacement rules through legacy alias',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'script-recast-refined-replacement-alias-test-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final cacheDir =
          Directory('${tempDir.path}${Platform.pathSeparator}cache')
            ..createSync(recursive: true);
      final backupDir =
          Directory('${tempDir.path}${Platform.pathSeparator}backup');
      final sourceRoot = '${tempDir.path}${Platform.pathSeparator}source';
      final cacheFile =
          File('${cacheDir.path}${Platform.pathSeparator}cache.json');
      final schemaFile =
          File('${tempDir.path}${Platform.pathSeparator}schema.json');

      await cacheFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(
          _cacheJson(
            sourceRootPath: sourceRoot,
            promptTerms: [
              _term('existing-accessory-collar-prompt', 'collar', 'accessory'),
            ],
            sceneTerms: const [],
            roleRules: [
              _rule(
                'existing-accessory-collar-rule',
                _term('existing-accessory-collar', 'collar', 'accessory'),
                targetPrompt: 'silver collar',
              ),
            ],
            sceneRules: const [],
          ),
        ),
        encoding: utf8,
      );
      await schemaFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'version': 1,
          'caches': [
            {
              'scriptId': 'script-a',
              'rolePromptTerms': [
                {
                  'sourceRoleId': 'role-a',
                  'displayLabel': 'Role A',
                  'terms': [
                    _term('term-accessory-collar', 'collar', 'accessory'),
                    _term('term-state-collar', 'collar', 'clothingState'),
                  ],
                },
              ],
            },
          ],
        }),
        encoding: utf8,
      );

      Future<ProcessResult> applySchema() {
        return Process.run(
          'node',
          [
            'tool/script_recast_complete_term_audit.mjs',
            '--cache-dir',
            cacheDir.path,
            '--source-root',
            sourceRoot,
            '--schema',
            schemaFile.path,
            '--apply',
            '--backup-dir',
            backupDir.path,
          ],
          workingDirectory: Directory.current.path,
          runInShell: Platform.isWindows,
        );
      }

      final firstApply = await applySchema();
      expect(firstApply.exitCode, 0, reason: firstApply.stderr.toString());

      final updated = jsonDecode(await cacheFile.readAsString(encoding: utf8))
          as Map<String, dynamic>;
      final rules = (((updated['mapping']
              as Map<String, dynamic>)['rolePromptReplacements'] as List)
          .single as Map<String, dynamic>)['rules'] as List;
      expect(rules, hasLength(2));
      expect(
        rules.cast<Map<String, dynamic>>().map((rule) => rule['id'] as String),
        [
          'existing-accessory-collar-rule',
          'role-role-a-clothingstate-collar',
        ],
      );
      expect(
        (rules.first as Map<String, dynamic>)['targetPrompt'],
        'silver collar',
      );
      expect(
        rules.cast<Map<String, dynamic>>().expand(
              (rule) => (rule['sourceTerms'] as List)
                  .cast<Map<String, dynamic>>()
                  .map((term) => '${term['id']}|${term['category']}'),
            ),
        [
          'term-accessory-collar|accessory',
          'term-state-collar|clothingState',
        ],
      );

      final afterFirstApply = await cacheFile.readAsString(encoding: utf8);
      final secondApply = await applySchema();
      expect(secondApply.exitCode, 0, reason: secondApply.stderr.toString());
      final afterSecondApply = await cacheFile.readAsString(encoding: utf8);
      expect(afterSecondApply, afterFirstApply);
    },
  );

  test(
    'generates separate fallback rule ids for same text refined categories',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'script-recast-refined-fallback-id-test-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final cacheDir =
          Directory('${tempDir.path}${Platform.pathSeparator}cache')
            ..createSync(recursive: true);
      final backupDir =
          Directory('${tempDir.path}${Platform.pathSeparator}backup');
      final sourceRoot = '${tempDir.path}${Platform.pathSeparator}source';
      final cacheFile =
          File('${cacheDir.path}${Platform.pathSeparator}cache.json');
      final schemaFile =
          File('${tempDir.path}${Platform.pathSeparator}schema.json');

      await cacheFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(
          _cacheJson(
            sourceRootPath: sourceRoot,
            promptTerms: const [],
            sceneTerms: const [],
            roleRules: const [],
            sceneRules: const [],
          ),
        ),
        encoding: utf8,
      );
      await schemaFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'version': 1,
          'caches': [
            {
              'scriptId': 'script-a',
              'rolePromptTerms': [
                {
                  'sourceRoleId': 'role-a',
                  'displayLabel': 'Role A',
                  'terms': [
                    _term('term-collar', 'collar', 'accessory'),
                    _term('term-collar', 'collar', 'clothingState'),
                  ],
                },
              ],
            },
          ],
        }),
        encoding: utf8,
      );

      final result = await Process.run(
        'node',
        [
          'tool/script_recast_complete_term_audit.mjs',
          '--cache-dir',
          cacheDir.path,
          '--source-root',
          sourceRoot,
          '--schema',
          schemaFile.path,
          '--apply',
          '--backup-dir',
          backupDir.path,
        ],
        workingDirectory: Directory.current.path,
        runInShell: Platform.isWindows,
      );
      expect(result.exitCode, 0, reason: result.stderr.toString());

      final updated = jsonDecode(await cacheFile.readAsString(encoding: utf8))
          as Map<String, dynamic>;
      final rules = (((updated['mapping']
              as Map<String, dynamic>)['rolePromptReplacements'] as List)
          .single as Map<String, dynamic>)['rules'] as List;
      expect(rules, hasLength(2));
      expect(
        rules.cast<Map<String, dynamic>>().map((rule) => rule['id'] as String),
        [
          'role-role-a-accessory-collar',
          'role-role-a-clothingstate-collar',
        ],
      );
      expect(
        rules.cast<Map<String, dynamic>>().expand(
              (rule) => (rule['sourceTerms'] as List)
                  .cast<Map<String, dynamic>>()
                  .map((term) => '${term['id']}|${term['category']}'),
            ),
        [
          'term-collar|accessory',
          'term-collar|clothingState',
        ],
      );
    },
  );
}

Map<String, dynamic> _cacheJson({
  required String sourceRootPath,
  required List<Map<String, dynamic>> promptTerms,
  required List<Map<String, dynamic>> sceneTerms,
  required List<Map<String, dynamic>> roleRules,
  required List<Map<String, dynamic>> sceneRules,
}) {
  return {
    'scriptId': 'script-a',
    'scriptName': 'Script A',
    'sourceRootPath': '$sourceRootPath/story-a',
    'sourceFingerprint': 'fingerprint',
    'updatedAt': '2026-06-27T00:00:00.000Z',
    'scriptSnapshot': {
      'id': 'script-a',
      'name': 'Script A',
      'rootPath': '$sourceRootPath/story-a',
      'frames': [
        {
          'index': 1,
          'path': 'frame-1.png',
          'parsed': {
            'baseCaption': 'bedroom, cinematic lighting',
            'charCaptions': [
              'girl, double bun, gyaru, demon girl, cristal wings',
            ],
            'negativeBase': 'bad anatomy',
            'negativeCharCaptions': ['extra arms'],
          },
        },
      ],
      'detectedSchema': 'v4Slotted',
      'parseWarnings': [],
      'meta': {'frameCount': 1},
    },
    'mapping': {
      'id': 'mapping-script-a',
      'scriptId': 'script-a',
      'roleSwaps': [],
      'artistSwap': null,
      'rolePromptReplacements': [
        {
          'sourceRoleId': 'role-a',
          'displayLabel': 'Role A',
          'sourcePreview': 'double bun',
          'rules': roleRules,
        },
      ],
      if (sceneRules.isNotEmpty)
        'scenePromptReplacements': [
          {
            'id': 'scene-ai',
            'label': 'Scene',
            'rules': sceneRules,
          },
        ],
    },
    'aiRoleExtraction': {
      'schema_version': 1,
      'status': 'ready',
      'confidence': 0.8,
      'roles': [
        {
          'source_role_id': 'role-a',
          'display_name': 'Role A',
          'appearances': [
            {
              'source_id': 'slot-0',
              'source_kind': 'slot',
              'frame_indexes': [1],
            },
          ],
          'stages': [],
          if (promptTerms.isNotEmpty) 'prompt_terms': promptTerms,
        },
      ],
      if (sceneTerms.isNotEmpty) 'scene_terms': sceneTerms,
    },
  };
}

Map<String, dynamic> _term(String id, String text, String category) {
  return {
    'id': id,
    'text': text,
    'category': category,
    'source_phrase': text,
    'source_location': 'slot-0 prompt',
    'frame_indexes': [1],
  };
}

Map<String, dynamic> _rule(
  String id,
  Map<String, dynamic> term, {
  String targetPrompt = '',
}) {
  return {
    'id': id,
    'sourceTerms': [term],
    if (targetPrompt.isNotEmpty) 'targetPrompt': targetPrompt,
  };
}
