import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/data/studio/services/script_ai_normalizer.dart';

void main() {
  test('normalization ignores weights and wrapper brackets', () {
    const normalizer = ScriptAiNormalizer();

    expect(
      normalizer.normalizePromptKey('2::Torn_Armor::, {black thighhighs}'),
      normalizer.normalizePromptKey('torn armor, black_thighhighs'),
    );
  });

  test('cache keys combine role identity and part keys', () {
    const normalizer = ScriptAiNormalizer();

    expect(
      normalizer.slottedCacheKey(
        roleIdentity: 'Alice_(Series)',
        partText: '2::Torn armor::, black thighhighs',
      ),
      'role:alice series|part:black thighhighs,torn armor',
    );
  });

  test('pure prompt cache key uses normalized full prompt', () {
    const normalizer = ScriptAiNormalizer();

    expect(
      normalizer.inlinePromptCacheKey('{artist:x}, Alice_(Series)'),
      'prompt:alice series,artist x',
    );
  });
}
