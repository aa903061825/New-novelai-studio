import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:novel_studio/data/models/api_request.dart';

import '../../tool/script_recast_acceptance.dart';

void main() {
  group('script recast real smoke wiring', () {
    test('local config token lookup reads saved api key without reporting it',
        () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'script-recast-token-source-test-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final configFile =
          File('${tempDir.path}${Platform.pathSeparator}box.hive');
      await configFile.writeAsString('{"api_key":"pst-secret-for-test"}');

      final token = await resolveScriptRecastSmokeToken(
        environment: const {},
        localConfigDirectories: const [],
        localConfigFiles: [configFile],
      );

      expect(token, 'pst-secret-for-test');
      final reports = await runScriptRecastAcceptance(
        targets: [
          const ScriptAcceptanceTarget(
            label: 'v4 slotted',
            primaryPath: 'test/fixtures/script_recast/v4_slotted',
          ),
        ],
        apiToken: token,
        smokeOptions: const ScriptRecastRealSmokeOptions(enabled: false),
      );

      expect(reports.single.realApiStatus, 'available-not-requested');
      expect(reports.single.toString(), isNot(contains(token!)));
    });

    test('local config token lookup follows the current Hive saved config',
        () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'script-recast-hive-token-source-test-',
      );
      Hive.init(tempDir.path);
      final box = await Hive.openBox('savedBox');
      await box.put('savedUuid', 'current');
      await box.put(
        'savedConfig-current',
        jsonEncode({
          'settings': {
            'api_key': 'pst-current-hive-token',
            'proxy': '127.0.0.1:7890',
            'output_folder': r'C:\nai-out',
          },
        }),
      );
      await box.put(
        'savedConfig-old',
        jsonEncode({
          'settings': {'api_key': 'pst-stale-hive-token'},
        }),
      );
      await box.close();
      addTearDown(() async {
        await Hive.close();
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final token = await resolveScriptRecastSmokeToken(
        environment: const {},
        localConfigDirectories: [tempDir],
        localConfigFiles: const [],
      );

      expect(token, 'pst-current-hive-token');
    });

    test('real smoke uses direct NAI payload and records output path',
        () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'script-recast-real-smoke-test-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      ApiRequest? capturedRequest;

      final reports = await runScriptRecastAcceptance(
        targets: [
          const ScriptAcceptanceTarget(
            label: 'v4 slotted',
            primaryPath: 'test/fixtures/script_recast/v4_slotted',
          ),
        ],
        apiToken: 'pst-secret-for-test',
        smokeOptions: ScriptRecastRealSmokeOptions(
          enabled: true,
          frameLimit: 1,
          outputDirectory: tempDir.path,
          fetchData: (request) async {
            capturedRequest = request;
            return ApiResponse(status: '200', data: Uint8List.fromList([1]));
          },
          processResponse: (bytes) => Uint8List.fromList([137, 80, 78, 71]),
          savePictureToFile: (bytes, fileName, saveDir) async {
            await File('$saveDir${Platform.pathSeparator}$fileName')
                .writeAsBytes(bytes);
          },
        ),
      );

      expect(capturedRequest, isNotNull);
      expect(capturedRequest!.headers['authorization'],
          'Bearer pst-secret-for-test');
      expect(capturedRequest!.payload['input'], contains('city lights'));
      expect(capturedRequest!.payload['model'], 'nai-diffusion-4-5-full');
      expect(capturedRequest!.payload['action'], 'generate');
      expect(capturedRequest!.payload, isNot(contains('Comment')));
      expect(
          capturedRequest!.payload['parameters'], isA<Map<String, dynamic>>());

      final smoke = reports.single.realApiSmokeResults.single;
      expect(reports.single.realApiStatus, 'completed-real-api:1/1');
      expect(smoke.status, ScriptAcceptanceRealApiSmokeStatus.completed);
      expect(smoke.outputImagePath, endsWith('v4-slotted-frame-1.png'));
      expect(await File(smoke.outputImagePath!).exists(), isTrue);
      expect(smoke.payloadFingerprint, isNotEmpty);
    });

    test('acceptance report printer never emits bearer tokens', () async {
      final buffer = StringBuffer();
      printScriptRecastAcceptanceReport(
        [
          ScriptAcceptanceReport(
            label: 'smoke',
            configuredPath: 'path',
            fallbackPath: null,
            actualPath: 'path',
            status: ScriptAcceptanceStatus.passed,
            frameCount: 1,
            detectedSchema: 'v4Slotted',
            parsedCount: 1,
            errorCount: 0,
            warningCount: 0,
            fingerprintStable: true,
            snapshotUnchanged: true,
            productionPlanTaskCount: 1,
            productionPlanFingerprintStable: true,
            realApiStatus: 'completed-real-api:1/1',
            fingerprintSummaries: const [],
            realApiSmokeResults: const [
              ScriptAcceptanceRealApiSmokeResult(
                frameIndex: 1,
                sourceFileName: 'nai_1.json',
                status: ScriptAcceptanceRealApiSmokeStatus.completed,
                payloadFingerprint: 'abc123',
                outputImagePath: r'C:\out\nai_1.png',
              ),
            ],
            fileSnapshotsBefore: const [],
            fileSnapshotsAfter: const [],
            message: 'OK',
          ),
        ],
        output: buffer,
      );

      expect(buffer.toString(), contains('outputImagePath:'));
      expect(buffer.toString(), isNot(contains('pst-secret-for-test')));
      expect(buffer.toString().toLowerCase(), isNot(contains('bearer')));
    });
  });
}
