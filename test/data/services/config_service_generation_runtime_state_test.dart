import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:nai_casrand/data/models/generation_runtime_state.dart';
import 'package:nai_casrand/data/services/config_service.dart';

void main() {
  late Directory tempDir;
  late ConfigService configService;
  late Box<dynamic> testBox;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'nai-casrand-config-service-test-',
    );
    Hive.init(tempDir.path);
    testBox = await Hive.openBox('savedBox-test-runtime-state');
    configService = ConfigService()..saveBox = testBox;
  });

  tearDown(() async {
    await testBox.deleteFromDisk();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('ConfigService persists and restores generation runtime state', () {
    final state = GenerationRuntimeState(
      vibeEnabled: false,
      hasPendingBatchResume: true,
      resumeTargetTotalCount: 100,
      resumeCompletedCount: 49,
      resumeStartedAt: DateTime.parse('2026-05-17T08:00:00Z'),
    );

    configService.saveGenerationRuntimeState(state);
    final restored = configService.loadGenerationRuntimeState();

    expect(restored, isNotNull);
    expect(restored!.vibeEnabled, isFalse);
    expect(restored.hasPendingBatchResume, isTrue);
    expect(restored.resumeTargetTotalCount, 100);
    expect(restored.resumeCompletedCount, 49);
    expect(
      restored.resumeStartedAt,
      DateTime.parse('2026-05-17T08:00:00Z'),
    );
  });

  test('ConfigService async helper persists generation runtime state',
      () async {
    final state = GenerationRuntimeState(
      vibeEnabled: true,
      hasPendingBatchResume: true,
      resumeTargetTotalCount: 8,
      resumeCompletedCount: 2,
      resumeStartedAt: DateTime.parse('2026-05-17T08:00:00Z'),
    );

    await configService.saveGenerationRuntimeStateAsync(state);
    final restored = configService.loadGenerationRuntimeState();

    expect(restored, isNotNull);
    expect(restored!.vibeEnabled, isTrue);
    expect(restored.hasPendingBatchResume, isTrue);
    expect(restored.resumeTargetTotalCount, 8);
    expect(restored.resumeCompletedCount, 2);
    expect(
      restored.resumeStartedAt,
      DateTime.parse('2026-05-17T08:00:00Z'),
    );
  });

  test('ConfigService ignores invalid generation runtime state cache', () {
    testBox.put('generationRuntimeState', '{not-valid-json');

    final restored = configService.loadGenerationRuntimeState();

    expect(restored, isNull);
  });
}
