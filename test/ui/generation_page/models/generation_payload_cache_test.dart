import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/data/models/prompt_config.dart';
import 'package:novel_studio/ui/generation_page/models/generation_payload_cache.dart';

PromptConfig _buildSequentialPromptConfig() {
  return PromptConfig(
    selectionMethod: 'single_sequential',
    shuffled: false,
    num: 1,
    type: 'str',
    comment: 'sequential',
    strs: const ['prompt-1', 'prompt-2', 'prompt-3'],
    prompts: const [],
  );
}

({String Function() generate, int Function() generatedCount})
    _buildSequentialGenerator() {
  final promptConfig = _buildSequentialPromptConfig();
  var generated = 0;

  String generate() {
    generated++;
    return promptConfig.getPrmpts().toPrompt();
  }

  int generatedCount() => generated;

  return (
    generate: generate,
    generatedCount: generatedCount,
  );
}

void main() {
  test('reuses a cached null payload until success clears it', () {
    final cache = GenerationPayloadCache<String?>();
    var generated = 0;

    final first = cache.takeOrGenerate(() {
      generated++;
      return null;
    });

    final second = cache.takeOrGenerate(() {
      generated++;
      return 'prompt-2';
    });

    cache.markSuccess();

    final third = cache.takeOrGenerate(() {
      generated++;
      return 'prompt-3';
    });

    expect(first, isNull);
    expect(second, isNull);
    expect(third, 'prompt-3');
    expect(generated, 2);
  });

  test('reuses the same payload across unlimited failures until success', () {
    final cache = GenerationPayloadCache<String>();
    var generated = 0;

    final first = cache.takeOrGenerate(() {
      generated++;
      return 'prompt-1';
    });

    final second = cache.takeOrGenerate(() {
      generated++;
      return 'prompt-2';
    });

    final third = cache.takeOrGenerate(() {
      generated++;
      return 'prompt-3';
    });

    expect(first, 'prompt-1');
    expect(second, 'prompt-1');
    expect(third, 'prompt-1');
    expect(generated, 1);
  });

  test('clears the cached payload after success so the next call regenerates',
      () {
    final cache = GenerationPayloadCache<String>();
    var generated = 0;

    final first = cache.takeOrGenerate(() {
      generated++;
      return 'prompt-1';
    });

    cache.markSuccess();

    final second = cache.takeOrGenerate(() {
      generated++;
      return 'prompt-2';
    });

    expect(first, 'prompt-1');
    expect(second, 'prompt-2');
    expect(generated, 2);
  });

  test('reset drops the cached payload so a new batch starts fresh', () {
    final cache = GenerationPayloadCache<String>();
    var generated = 0;

    final first = cache.takeOrGenerate(() {
      generated++;
      return 'prompt-1';
    });

    cache.reset();

    final second = cache.takeOrGenerate(() {
      generated++;
      return 'prompt-2';
    });

    expect(first, 'prompt-1');
    expect(second, 'prompt-2');
    expect(generated, 2);
  });

  test('repeated failures do not advance a single sequential prompt', () {
    final cache = GenerationPayloadCache<String>();
    final generator = _buildSequentialGenerator();

    final prompts = [
      cache.takeOrGenerate(generator.generate),
      cache.takeOrGenerate(generator.generate),
      cache.takeOrGenerate(generator.generate),
    ];

    expect(prompts, ['prompt-1', 'prompt-1', 'prompt-1']);
    expect(generator.generatedCount(), 1);
  });

  test('success advances a single sequential prompt on the next generation',
      () {
    final cache = GenerationPayloadCache<String>();
    final generator = _buildSequentialGenerator();

    final first = cache.takeOrGenerate(generator.generate);

    cache.markSuccess();

    final promptsAfterSuccess = [
      cache.takeOrGenerate(generator.generate),
      cache.takeOrGenerate(generator.generate),
    ];

    expect(first, 'prompt-1');
    expect(promptsAfterSuccess, ['prompt-2', 'prompt-2']);
    expect(generator.generatedCount(), 2);
  });
}
