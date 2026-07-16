import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('builds a deterministic offline promotion acceptance report', () async {
    final fixture = await _Fixture.create('happy');
    addTearDown(fixture.dispose);

    final result = await fixture.run();

    expect(
      result.exitCode,
      0,
      reason: 'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
    );
    final report = fixture.readOutput();
    expect(report['kind'], 'script_recast_promotion_acceptance');
    expect(report['schema_version'], 1);
    expect(report['api_used'], isFalse);
    expect((report['cache_files'] as List), hasLength(3));
    expect((report['removed_cache_files'] as List), hasLength(1));
    expect((report['aggregate_sha256'] as String), hasLength(64));
    expect(
      (report['checks'] as Map).values,
      everyElement(isTrue),
    );
    final roots = (report['evidence'] as Map)['source_roots'] as Map;
    expect(roots['distinct_count'], 2);
    expect(roots['duplicate_count'], 1);
    final authorities = (report['evidence'] as Map)['authorities'] as Map;
    final frameAuthority = authorities['frame_semantics'] as Map;
    expect(frameAuthority['legacy_field_route_authoritative'], isFalse);
    final integrityAuthority = authorities['cache_integrity'] as Map;
    expect(
      integrityAuthority['legacy_non_authoritative_fields'],
      containsAll(
          <String>['classification_issue_count', 'slot_coverage_issue_count']),
    );
  });

  test('rejects peer cache hash drift without writing acceptance', () async {
    final fixture = await _Fixture.create('peer-drift');
    addTearDown(fixture.dispose);
    fixture.peerFile('script-b.json').writeAsStringSync('peer drift');

    final result = await fixture.run();

    expect(result.exitCode, isNot(0));
    expect(fixture.output.existsSync(), isFalse);
  });

  test('rejects a validator report bound to a stale cache directory', () async {
    final fixture = await _Fixture.create('stale-report');
    addTearDown(fixture.dispose);
    fixture.writeJson(fixture.mappingReport, {
      ...fixture.mappingReportJson,
      'cache_dir': fixture.peer.path,
    });

    final result = await fixture.run();

    expect(result.exitCode, isNot(0));
    expect(fixture.output.existsSync(), isFalse);
  });

  test('rejects non-zero term occurrence validator evidence', () async {
    final fixture = await _Fixture.create('validator-nonzero');
    addTearDown(fixture.dispose);
    fixture.writeJson(fixture.mappingReport, {
      ...fixture.mappingReportJson,
      'term_review_source_occurrence_duplicate_ai_count': 1,
    });

    final result = await fixture.run();

    expect(result.exitCode, isNot(0));
    expect(fixture.output.existsSync(), isFalse);
  });

  test('rejects an unrecoverable-without-metadata count mismatch', () async {
    final fixture = await _Fixture.create('coverage-count');
    addTearDown(fixture.dispose);

    final result = await fixture.run(expectedUnrecoverableCount: 3);

    expect(result.exitCode, isNot(0));
    expect(fixture.output.existsSync(), isFalse);
  });

  test('rejects removed cache whose source root still contains an image',
      () async {
    final fixture = await _Fixture.create('remove-image');
    addTearDown(fixture.dispose);
    File('${fixture.staleSource.path}/old.png')
        .writeAsBytesSync(const [1, 2, 3]);

    final result = await fixture.run();

    expect(result.exitCode, isNot(0));
    expect(fixture.output.existsSync(), isFalse);
  });

  test('rejects builder output differences beyond the remove set', () async {
    final fixture = await _Fixture.create('builder-drift');
    addTearDown(fixture.dispose);
    fixture.parentAFile('script-a.json').writeAsStringSync('builder drift');

    final result = await fixture.run();

    expect(result.exitCode, isNot(0));
    expect(fixture.output.existsSync(), isFalse);
  });

  test('rejects symlink and cache-contained output paths', () async {
    final fixture = await _Fixture.create('unsafe-output');
    addTearDown(fixture.dispose);

    final target = File('${fixture.root.path}/outside-target.json')
      ..writeAsStringSync('target');
    final link = Link('${fixture.root.path}/acceptance-link.json');
    var symlinkCreated = false;
    try {
      link.createSync(target.path);
      symlinkCreated = true;
    } on FileSystemException {
      // Windows may disallow symlink creation in a non-elevated test process.
    }

    if (symlinkCreated) {
      final result = await fixture.run(outputPath: link.path);
      expect(result.exitCode, isNot(0));
      expect(link.existsSync(), isTrue);
    } else {
      final result = await fixture.run(
        outputPath: File('${fixture.cache.path}/unsafe-acceptance.json').path,
      );
      expect(result.exitCode, isNot(0));
    }
  });
}

class _Fixture {
  _Fixture({
    required this.root,
    required this.cache,
    required this.peer,
    required this.baseline,
    required this.parentA,
    required this.parentB,
    required this.reports,
    required this.output,
    required this.staleSource,
    required this.buildReportA,
    required this.buildReportB,
    required this.mappingReport,
    required this.frameReport,
    required this.integrityReport,
    required this.coverageReport,
    required this.termReview,
    required this.mappingReportJson,
  });

  final Directory root;
  final Directory cache;
  final Directory peer;
  final Directory baseline;
  final Directory parentA;
  final Directory parentB;
  final Directory reports;
  final File output;
  final Directory staleSource;
  final File buildReportA;
  final File buildReportB;
  final File mappingReport;
  final File frameReport;
  final File integrityReport;
  final File coverageReport;
  final File termReview;
  final Map<String, dynamic> mappingReportJson;

  static Future<_Fixture> create(String name) async {
    final root = await Directory.systemTemp.createTemp(
      'script-recast-promotion-acceptance-$name-',
    );
    final cache = Directory('${root.path}/final-a')..createSync();
    final peer = Directory('${root.path}/final-b')..createSync();
    final baseline = Directory('${root.path}/baseline')..createSync();
    final parentA = Directory('${root.path}/rebuilt-a')..createSync();
    final parentB = Directory('${root.path}/rebuilt-b')..createSync();
    final reports = Directory('${root.path}/reports')..createSync();
    final output = File('${root.path}/acceptance.json');
    final staleSource = Directory('${root.path}/stale-source')..createSync();
    final sourceOne = Directory('${root.path}/source-one')..createSync();
    final sourceTwo = Directory('${root.path}/source-two')..createSync();

    final cacheBytes = <String, List<int>>{
      'script-a.json': _cacheBytes('script-a', sourceOne.path),
      'script-b.json': _cacheBytes('script-b', sourceOne.path),
      'script-c.json': _cacheBytes('script-c', sourceTwo.path),
    };
    final removedBytes = _cacheBytes('script-remove', staleSource.path);
    for (final entry in cacheBytes.entries) {
      File('${cache.path}/${entry.key}').writeAsBytesSync(entry.value);
      File('${peer.path}/${entry.key}').writeAsBytesSync(entry.value);
      File('${parentA.path}/${entry.key}').writeAsBytesSync(entry.value);
      File('${parentB.path}/${entry.key}').writeAsBytesSync(entry.value);
      File('${baseline.path}/${entry.key}').writeAsBytesSync(_cacheBytes(
          entry.key.substring(0, entry.key.length - 5),
          '${root.path}/baseline-source'));
    }
    File('${parentA.path}/script-remove.json').writeAsBytesSync(removedBytes);
    File('${parentB.path}/script-remove.json').writeAsBytesSync(removedBytes);
    File('${baseline.path}/script-remove.json').writeAsBytesSync(removedBytes);

    final buildReportA = File('${reports.path}/build-a.json');
    final buildReportB = File('${reports.path}/build-b.json');
    final mappingReport = File('${reports.path}/mapping.json');
    final frameReport = File('${reports.path}/frame.json');
    final integrityReport = File('${reports.path}/integrity.json');
    final coverageReport = File('${reports.path}/coverage.json');
    final termReview = File('${reports.path}/term-review.json');

    final termReviewJson = <String, dynamic>{
      'schema_version': 1,
      'kind': 'script_recast_term_membership_review',
      'api_used': false,
      'decisions': <Object>[],
    };
    _writeJson(termReview, termReviewJson);

    Map<String, dynamic> buildReport(Directory outputDir) => {
          'api_used': false,
          'apply': true,
          'output_dir': outputDir.path,
          'files_scanned': 4,
          'term_review_file': termReview.path,
          'term_review_complete': true,
          'term_review_missing_term_count': 0,
          'term_review_baseline_mismatch_count': 0,
        };
    _writeJson(buildReportA, buildReport(parentA));
    _writeJson(buildReportB, buildReport(parentB));

    final mappingReportJson = <String, dynamic>{
      'api_used': false,
      'cache_dir': cache.path,
      'files_scanned': 3,
      'violation_count': 0,
      'term_review_complete': true,
      'term_review_decision_count': 0,
      for (final field in _mappingCounterFields) field: 0,
    };
    _writeJson(mappingReport, mappingReportJson);
    _writeJson(frameReport, {
      'cache_dir': cache.path,
      'cache_count': 3,
      'mixed_stage_issue_count': 0,
      'label_state_issue_count': 0,
      'field_source_issue_count': 0,
      'ui_label_issue_count': 0,
      'field_route_issue_count': 13,
    });
    _writeJson(integrityReport, {
      'cache_dir': cache.path,
      'cache_count': 3,
      'ready_count': 3,
      'total_frames': 3,
      'parsed_frames': 3,
      'png_metadata_missing_frames': 0,
      'source_frame_mismatch_count': 0,
      'role_identity_issue_count': 0,
      'role_frame_reference_issue_count': 0,
      'classification_issue_count': 11,
      'slot_coverage_issue_count': 7,
    });
    _writeJson(coverageReport, {
      'api_used': false,
      'read_only': true,
      'source_coverage_reviewed': true,
      'cache_dir': cache.path,
      'summary': {
        'uncached_png_without_prompt_metadata_count': 2,
      },
      'uncached_png_without_prompt_metadata_review': {
        'status': 'reviewed_unrecoverable_without_metadata',
        'count': 2,
        'images': <Object>[],
      },
      'checks': {
        'errors': true,
        'missing_cache_directory_count': true,
        'cache_source_issue_count': true,
        'missing_frame_image_count': true,
        'uncached_png_with_prompt_metadata_count': true,
        'uncached_png_metadata_error_count': true,
        'uncached_png_without_prompt_metadata_reviewed': true,
        'source_coverage_reviewed': true,
      },
      'violations': <Object>[],
      'errors': <Object>[],
    });

    return _Fixture(
      root: root,
      cache: cache,
      peer: peer,
      baseline: baseline,
      parentA: parentA,
      parentB: parentB,
      reports: reports,
      output: output,
      staleSource: staleSource,
      buildReportA: buildReportA,
      buildReportB: buildReportB,
      mappingReport: mappingReport,
      frameReport: frameReport,
      integrityReport: integrityReport,
      coverageReport: coverageReport,
      termReview: termReview,
      mappingReportJson: mappingReportJson,
    );
  }

  static const _mappingCounterFields = <String>[
    'term_review_ai_mapping_category_mismatch_count',
    'term_review_ai_mapping_term_set_mismatch_count',
    'term_review_excluded_ai_leak_count',
    'term_review_excluded_mapping_leak_count',
    'term_review_excluded_stage_leak_count',
    'term_review_missing_term_count',
    'term_review_required_role_category_mismatch_count',
    'term_review_required_role_missing_ai_count',
    'term_review_required_role_missing_mapping_count',
    'term_review_required_scene_category_mismatch_count',
    'term_review_required_scene_missing_ai_count',
    'term_review_required_scene_missing_mapping_count',
    'term_review_source_occurrence_ai_mapping_mismatch_count',
    'term_review_source_occurrence_duplicate_ai_count',
    'term_review_source_occurrence_duplicate_mapping_count',
    'term_review_source_occurrence_invalid_ai_count',
    'term_review_source_occurrence_invalid_mapping_count',
    'term_review_source_occurrence_missing_ai_count',
    'term_review_source_occurrence_missing_mapping_count',
    'term_review_source_occurrence_unbacked_ai_count',
    'term_review_source_occurrence_unbacked_mapping_count',
    'term_review_stage_category_mismatch_count',
    'term_review_stage_materialization_marker_missing_count',
    'term_review_stage_non_role_residue_count',
    'term_review_unresolved_term_count',
    'term_review_wrong_placement_ai_count',
    'term_review_wrong_placement_mapping_count',
    'term_review_wrong_placement_stage_count',
  ];

  File peerFile(String name) => File('${peer.path}/$name');

  File parentAFile(String name) => File('${parentA.path}/$name');

  void writeJson(File file, Map<String, dynamic> value) =>
      _writeJson(file, value);

  Future<ProcessResult> run({
    int expectedUnrecoverableCount = 2,
    String? outputPath,
  }) {
    return Process.run(
      'node',
      [
        'tool/build_script_recast_promotion_acceptance.mjs',
        '--cache-dir',
        cache.path,
        '--peer-cache-dir',
        peer.path,
        '--baseline-dir',
        baseline.path,
        '--build-report-a',
        buildReportA.path,
        '--build-report-b',
        buildReportB.path,
        '--mapping-report',
        mappingReport.path,
        '--frame-report',
        frameReport.path,
        '--integrity-report',
        integrityReport.path,
        '--coverage-report',
        coverageReport.path,
        '--term-review',
        termReview.path,
        '--remove-file',
        'script-remove.json',
        '--expected-count',
        '3',
        '--expected-source-root-count',
        '2',
        '--expected-duplicate-root-count',
        '1',
        '--expected-unrecoverable-without-metadata-count',
        '$expectedUnrecoverableCount',
        '--output',
        outputPath ?? output.path,
      ],
      workingDirectory: Directory.current.path,
    );
  }

  Map<String, dynamic> readOutput() =>
      jsonDecode(output.readAsStringSync()) as Map<String, dynamic>;

  Future<void> dispose() async {
    if (root.existsSync()) await root.delete(recursive: true);
  }
}

List<int> _cacheBytes(String scriptId, String sourceRootPath) => utf8.encode(
      '${jsonEncode({
            'scriptId': scriptId,
            'sourceRootPath': sourceRootPath,
            'scriptSnapshot': {'frames': <Object>[]},
          })}\n',
    );

void _writeJson(File file, Map<String, dynamic> value) {
  file.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(value)}\n',
  );
}
