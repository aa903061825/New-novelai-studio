import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/script_recast_acceptance.dart';

void main() {
  group('script recast acceptance tool', () {
    test('covers fixture schemas, broken frames, skipped paths, and API skip',
        () async {
      final reports = await runScriptRecastAcceptance(
        targets: [
          const ScriptAcceptanceTarget(
            label: 'v4 slotted',
            primaryPath: 'test/fixtures/script_recast/v4_slotted',
          ),
          const ScriptAcceptanceTarget(
            label: 'base inline',
            primaryPath: 'test/fixtures/script_recast/base_inline',
          ),
          const ScriptAcceptanceTarget(
            label: 'mixed',
            primaryPath: 'test/fixtures/script_recast/mixed',
          ),
          const ScriptAcceptanceTarget(
            label: 'broken',
            primaryPath: 'test/fixtures/script_recast/broken',
          ),
          const ScriptAcceptanceTarget(
            label: 'missing',
            primaryPath: 'test/fixtures/script_recast/does_not_exist',
          ),
        ],
        apiToken: null,
      );

      expect(reports, hasLength(5));
      expect(reports[0].status, ScriptAcceptanceStatus.passed);
      expect(reports[0].detectedSchema, 'v4Slotted');
      expect(reports[1].detectedSchema, 'baseInline');
      expect(reports[2].detectedSchema, 'v4Partial');
      expect(reports[3].status, ScriptAcceptanceStatus.failed);
      expect(reports[3].errorCount, 1);
      expect(reports[3].warningCount, 1);
      expect(reports[4].status, ScriptAcceptanceStatus.skipped);
      expect(reports[4].message, contains('SKIPPED'));

      for (final report
          in reports.where((r) => r.status != ScriptAcceptanceStatus.skipped)) {
        expect(report.realApiStatus, 'skipped-real-api');
        expect(report.frameCount, greaterThan(0));
        expect(report.snapshotUnchanged, isTrue);
        expect(report.fingerprintStable, isTrue);
        expect(report.productionPlanTaskCount, greaterThan(0));
        expect(report.productionPlanTaskCount, lessThanOrEqualTo(10));
        expect(report.productionPlanFingerprintStable, isTrue);
        expect(report.fingerprintSummaries.length, lessThanOrEqualTo(10));
      }
    });

    test('fingerprints are deterministic and omit policy metadata', () async {
      final first = await runScriptRecastAcceptance(
        targets: [
          const ScriptAcceptanceTarget(
            label: 'v4 slotted',
            primaryPath: 'test/fixtures/script_recast/v4_slotted',
          ),
        ],
        apiToken: '',
      );
      final second = await runScriptRecastAcceptance(
        targets: [
          const ScriptAcceptanceTarget(
            label: 'v4 slotted',
            primaryPath: 'test/fixtures/script_recast/v4_slotted',
          ),
        ],
        apiToken: '',
      );

      expect(
        first.single.fingerprintSummaries
            .map((summary) => summary.payloadFingerprint),
        second.single.fingerprintSummaries
            .map((summary) => summary.payloadFingerprint),
      );
      expect(
        first.single.fingerprintSummaries
            .expand((summary) => summary.policyMetadataKeys),
        isEmpty,
      );
    });

    test('does not mutate fixture nai json files', () async {
      final directory = Directory('test/fixtures/script_recast/v4_slotted');
      final before = await snapshotNaiJsonFiles(directory);

      final reports = await runScriptRecastAcceptance(
        targets: [
          ScriptAcceptanceTarget(
            label: 'v4 slotted',
            primaryPath: directory.path,
          ),
        ],
        apiToken: null,
      );

      final after = await snapshotNaiJsonFiles(directory);
      expect(reports.single.snapshotUnchanged, isTrue);
      expect(after.map((entry) => entry.toJson()),
          before.map((entry) => entry.toJson()));
    });
  });
}
