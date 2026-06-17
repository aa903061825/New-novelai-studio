import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/data/models/generation_runtime_state.dart';

void main() {
  test('GenerationRuntimeState supports json roundtrip', () {
    final state = GenerationRuntimeState(
      vibeEnabled: false,
      hasPendingBatchResume: true,
      resumeTargetTotalCount: 100,
      resumeCompletedCount: 49,
      resumeStartedAt: DateTime.parse('2026-05-17T08:00:00Z'),
    );

    final restored = GenerationRuntimeState.fromJson(state.toJson());

    expect(restored.vibeEnabled, isFalse);
    expect(restored.hasPendingBatchResume, isTrue);
    expect(restored.resumeTargetTotalCount, 100);
    expect(restored.resumeCompletedCount, 49);
    expect(
      restored.resumeStartedAt,
      DateTime.parse('2026-05-17T08:00:00Z'),
    );
  });

  test('clearPendingBatchResume resets only resume fields', () {
    final state = GenerationRuntimeState(
      vibeEnabled: false,
      hasPendingBatchResume: true,
      resumeTargetTotalCount: 100,
      resumeCompletedCount: 49,
      resumeStartedAt: DateTime.parse('2026-05-17T08:00:00Z'),
    );

    state.clearPendingBatchResume();

    expect(state.vibeEnabled, isFalse);
    expect(state.hasPendingBatchResume, isFalse);
    expect(state.resumeTargetTotalCount, 0);
    expect(state.resumeCompletedCount, 0);
    expect(state.resumeStartedAt, isNull);
  });
}
