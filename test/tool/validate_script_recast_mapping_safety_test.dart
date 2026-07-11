import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('validator fails closed for hidden and unsafe mappings', () async {
    final fixture = await _ValidationFixture.create();
    addTearDown(fixture.dispose);
    fixture.writeCache(_badCache(fixture.sourceRoot.path));

    final result = await fixture.runValidator();

    expect(result.exitCode, isNot(0));
    final report = fixture.readReport();
    expect(report['eligible_cache_files'], 1);
    expect(report['hidden_role_swap_count'], 1);
    expect(report['mapped_male_role_count'], 1);
    expect(report['mapped_role_prompt_term_coverage_gap_count'], 1);
    expect(report['pseudo_partial_role_count'], 1);
    expect(report['appearance_collision_count'], greaterThan(0));
    expect(report['target_stage_mismatch_count'], 1);
    expect(report['regression_male_target_count'], 1);
    expect(report['violation_count'], greaterThanOrEqualTo(6));
  });

  test('validator accepts a visible identity mapping and untouched male slot',
      () async {
    final fixture = await _ValidationFixture.create();
    addTearDown(fixture.dispose);
    fixture.writeCache(_cleanCache(fixture.sourceRoot.path));

    final result = await fixture.runValidator();

    expect(
      result.exitCode,
      0,
      reason: 'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
    );
    final report = fixture.readReport();
    expect(report['eligible_cache_files'], 1);
    expect(report['mapped_role_count'], 1);
    expect(report['violation_count'], 0);
  });
}

class _ValidationFixture {
  final Directory root;
  final Directory cacheDir;
  final Directory sourceRoot;
  final File reportFile;

  const _ValidationFixture({
    required this.root,
    required this.cacheDir,
    required this.sourceRoot,
    required this.reportFile,
  });

  static Future<_ValidationFixture> create() async {
    final root = await Directory.systemTemp.createTemp(
      'script-recast-mapping-validator-test-',
    );
    final cacheDir = Directory('${root.path}/cache')..createSync();
    final sourceRoot = Directory('${root.path}/source')..createSync();
    Directory('${sourceRoot.path}/story').createSync();
    return _ValidationFixture(
      root: root,
      cacheDir: cacheDir,
      sourceRoot: sourceRoot,
      reportFile: File('${root.path}/report.json'),
    );
  }

  void writeCache(Map<String, dynamic> cache) {
    File('${cacheDir.path}/script-safety.json')
        .writeAsStringSync(jsonEncode(cache));
  }

  Future<ProcessResult> runValidator() {
    return Process.run(
      'node',
      [
        'tool/validate_script_recast_mapping_safety.mjs',
        '--cache-dir',
        cacheDir.path,
        '--source-root',
        sourceRoot.path,
        '--report',
        reportFile.path,
        '--regression-script-id',
        'script-safety',
        '--regression-frame-file',
        'story_p32.png',
      ],
      workingDirectory: Directory.current.path,
    );
  }

  Map<String, dynamic> readReport() {
    return jsonDecode(reportFile.readAsStringSync()) as Map<String, dynamic>;
  }

  Future<void> dispose() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  }
}

Map<String, dynamic> _cleanCache(String sourceRoot) {
  return _cacheFixture(
    sourceRoot: sourceRoot,
    roles: [
      _role(
        id: 'role-alice',
        name: 'alice / girl',
        rawIdentityTags: ['alice_(series)', 'girl'],
        sourceId: 'slot-0',
      ),
      _role(
        id: 'role-male',
        name: 'faceless male',
        rawIdentityTags: ['boy', 'faceless male'],
        sourceId: 'slot-1',
      ),
    ],
    roleSwaps: const [],
    replacements: [
      _replacement('role-alice', 'legacy-character-sheet-r14'),
      _replacement('role-male', null),
    ],
    assemblies: [
      _assembly(
        'role-alice',
        'slot-0',
        targetCharacterId: 'legacy-character-sheet-r14',
      ),
      _assembly('role-male', 'slot-1'),
    ],
  );
}

Map<String, dynamic> _badCache(String sourceRoot) {
  return _cacheFixture(
    sourceRoot: sourceRoot,
    roles: [
      {
        ..._role(
          id: 'role-girl-slot-0',
          name: 'girl',
          rawIdentityTags: ['girl'],
          sourceId: 'slot-0',
          caption: 'girl, pov hands, white gloves',
        ),
        'prompt_terms': [
          {
            'id': 'term-role-girl-slot-0',
            'text': 'girl',
            'category': 'character',
            'frame_indexes': [32],
          },
          {
            'id': 'term-uncovered-pink-hair',
            'text': 'pink hair',
            'category': 'upperBody',
            'frame_indexes': [32],
          },
        ],
      },
      _role(
        id: 'role-male',
        name: 'faceless male',
        rawIdentityTags: ['boy', 'faceless male'],
        sourceId: 'slot-1',
      ),
      _role(
        id: 'role-overlap',
        name: 'another girl',
        rawIdentityTags: ['girl'],
        sourceId: 'slot-1',
      ),
    ],
    roleSwaps: const [
      {
        'sourceRoleId': 'slot-1',
        'targetCharacterId': 'legacy-character-sheet-r13',
      },
    ],
    replacements: [
      _replacement('role-girl-slot-0', 'legacy-character-sheet-r14'),
      _replacement('role-male', 'legacy-character-sheet-r13'),
      _replacement('role-overlap', null),
    ],
    assemblies: [
      _assembly(
        'role-girl-slot-0',
        'slot-0',
        targetCharacterId: 'legacy-character-sheet-r13',
      ),
      _assembly(
        'role-male',
        'slot-1',
        targetCharacterId: 'legacy-character-sheet-r13',
      ),
      _assembly('role-overlap', 'slot-1'),
    ],
  );
}

Map<String, dynamic> _cacheFixture({
  required String sourceRoot,
  required List<Map<String, dynamic>> roles,
  required List<Map<String, dynamic>> roleSwaps,
  required List<Map<String, dynamic>> replacements,
  required List<Map<String, dynamic>> assemblies,
}) {
  return {
    'scriptId': 'script-safety',
    'scriptName': 'Safety fixture',
    'sourceRootPath': '$sourceRoot/story',
    'updatedAt': DateTime.utc(2026, 7, 11).toIso8601String(),
    'scriptSnapshot': {
      'frames': [
        {
          'index': 32,
          'fileName': 'story_p32.png',
          'parseStatus': 'parsed',
          'parsed': {
            'baseCaption': '1girl, 1boy, indoors',
            'charCaptions': [
              'alice_(series), girl, red jacket',
              'boy, pov hands, holding chain',
            ],
          },
        },
      ],
    },
    'aiRoleExtraction': {
      'status': 'ready',
      'roles': roles,
    },
    'mapping': {
      'id': 'mapping-script-safety',
      'scriptId': 'script-safety',
      'roleSwaps': roleSwaps,
      'rolePromptReplacements': replacements,
      'roleAssemblies': assemblies,
    },
  };
}

Map<String, dynamic> _role({
  required String id,
  required String name,
  required List<String> rawIdentityTags,
  required String sourceId,
  String? caption,
}) {
  return {
    'source_role_id': id,
    'source_kind': 'slot',
    'display_name': name,
    'canonical_name': rawIdentityTags.first.contains('_(')
        ? rawIdentityTags.first.split('_(').first
        : '',
    'raw_identity_tags': rawIdentityTags,
    'frame_indexes': [32],
    'appearances': [
      {
        'source_id': sourceId,
        'source_kind': 'slot',
        'frame_indexes': [32],
      },
    ],
    'stages': [
      {
        'stage_id': 'stage-1',
        'label': 'default',
        'frame_indexes': [32],
        'identity': caption ?? name,
      },
    ],
    'prompt_terms': [
      {
        'id': 'term-$id',
        'text': rawIdentityTags.first,
        'category': 'character',
        'frame_indexes': [32],
      },
    ],
  };
}

Map<String, dynamic> _replacement(String roleId, String? targetId) {
  return {
    'sourceRoleId': roleId,
    'displayLabel': roleId,
    if (targetId != null) ...{
      'targetCharacterId': targetId,
      'targetIdentityPrompt': 'target_identity',
    },
    'rules': [
      {
        'id': 'rule-$roleId',
        'sourceTerms': [
          {
            'id': 'term-$roleId',
            'text': roleId,
            'category': 'character',
            'frameIndexes': [32],
          },
        ],
        if (targetId != null) ...{
          'action': 'replace',
          'targetPrompt': 'target_identity',
        },
      },
    ],
  };
}

Map<String, dynamic> _assembly(
  String roleId,
  String sourceId, {
  String? targetCharacterId,
}) {
  return {
    'sourceRoleId': roleId,
    'displayLabel': roleId,
    'sourceAppearances': [
      {
        'sourceId': sourceId,
        'sourceKind': 'slot',
        'frameIndexes': [32],
      },
    ],
    'stages': [
      {
        'id': 'stage-1',
        'label': 'default',
        'frameIndexes': [32],
        if (targetCharacterId != null) 'targetCharacterId': targetCharacterId,
      },
    ],
  };
}
