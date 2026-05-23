# Success-Only Prompt Progression Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make generation stay on the current prompt payload indefinitely after failures and only advance to the next prompt after a real successful image generation.

**Architecture:** Remove the fixed retry ceiling from the generation payload cache flow. Keep the existing generation pipeline in `GenerationPageViewmodel`, but isolate payload-cache behavior enough to test it without depending on live HTTP calls. Success clears the cache; failure preserves it; starting or stopping a batch resets it.

**Tech Stack:** Flutter, Dart, `flutter_test`, `get_it`, existing app models and use cases

---

### Task 1: Add failing tests for success-only payload reuse

**Files:**
- Create: `test/ui/generation_page/models/generation_payload_cache_test.dart`
- Create later: `lib/ui/generation_page/models/generation_payload_cache.dart`

**Step 1: Write the failing test**

Create a focused unit test for a tiny payload-cache helper so the retry policy is testable without networking.

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/ui/generation_page/models/generation_payload_cache.dart';

void main() {
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

  test('clears the cached payload after success so the next call regenerates', () {
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
}
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/ui/generation_page/models/generation_payload_cache_test.dart`

Expected: FAIL because `GenerationPayloadCache` does not exist yet.

**Step 3: Write minimal implementation**

Create a tiny generic helper in `lib/ui/generation_page/models/generation_payload_cache.dart`.

```dart
class GenerationPayloadCache<T> {
  T? _cached;

  T takeOrGenerate(T Function() generate) {
    return _cached ??= generate();
  }

  void markSuccess() {
    _cached = null;
  }

  void reset() {
    _cached = null;
  }
}
```

**Step 4: Run test to verify it passes**

Run: `flutter test test/ui/generation_page/models/generation_payload_cache_test.dart`

Expected: PASS.

**Step 5: Commit**

If this workspace is a git repository:

```bash
git add test/ui/generation_page/models/generation_payload_cache_test.dart lib/ui/generation_page/models/generation_payload_cache.dart
git commit -m "feat: add success-only payload cache"
```

If `git status` reports this is not a repository, skip this step.

### Task 2: Add a regression test proving prompt progression happens only after success

**Files:**
- Modify: `test/ui/generation_page/models/generation_payload_cache_test.dart`
- Reuse: `lib/ui/generation_page/models/generation_payload_cache.dart`
- Read for setup: `lib/data/models/prompt_config.dart`
- Read for setup: `lib/data/use_cases/generate_payload_use_case.dart`

**Step 1: Write the failing test**

Add a test that uses a real sequential prompt config plus the cache helper to prove repeated failures do not advance the prompt, but success does.

```dart
test('single_sequential prompt advances only after cache success', () {
  final cache = GenerationPayloadCache<String>();
  final config = PromptConfig(
    selectionMethod: 'single_sequential',
    shuffled: false,
    num: 1,
    strs: ['line-1', 'line-2'],
    prompts: const [],
  );

  String generatePrompt() => config.getPrmpts().toPrompt();

  final first = cache.takeOrGenerate(generatePrompt);
  final retryOne = cache.takeOrGenerate(generatePrompt);
  final retryTwo = cache.takeOrGenerate(generatePrompt);

  cache.markSuccess();

  final second = cache.takeOrGenerate(generatePrompt);

  expect(first, 'line-1');
  expect(retryOne, 'line-1');
  expect(retryTwo, 'line-1');
  expect(second, 'line-2');
});
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/ui/generation_page/models/generation_payload_cache_test.dart`

Expected: FAIL until the helper and test imports are wired correctly.

**Step 3: Write minimal implementation**

Keep the helper minimal. Only add code if needed to support the test shape; do not add retry counters or skip logic.

**Step 4: Run test to verify it passes**

Run: `flutter test test/ui/generation_page/models/generation_payload_cache_test.dart`

Expected: PASS, proving failure retries stay on the current sequential item.

**Step 5: Commit**

If this workspace is a git repository:

```bash
git add test/ui/generation_page/models/generation_payload_cache_test.dart lib/ui/generation_page/models/generation_payload_cache.dart
git commit -m "test: cover success-only prompt progression"
```

If `git status` reports this is not a repository, skip this step.

### Task 3: Integrate the cache into the generation viewmodel

**Files:**
- Modify: `lib/ui/generation_page/view_models/generation_page_viewmodel.dart`
- Read: `lib/data/use_cases/generate_payload_use_case.dart`
- Reuse: `lib/ui/generation_page/models/generation_payload_cache.dart`

**Step 1: Write the failing test**

Before editing production code, extend the cache test file with a reset-focused test that matches the batch lifecycle semantics the viewmodel will depend on.

```dart
test('reset drops the cached payload so a new batch starts fresh', () {
  final cache = GenerationPayloadCache<String>();
  var generated = 0;

  cache.takeOrGenerate(() {
    generated++;
    return 'prompt-1';
  });

  cache.reset();

  final next = cache.takeOrGenerate(() {
    generated++;
    return 'prompt-2';
  });

  expect(next, 'prompt-2');
  expect(generated, 2);
});
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/ui/generation_page/models/generation_payload_cache_test.dart`

Expected: FAIL if `reset()` is missing or behavior is wrong.

**Step 3: Write minimal implementation**

Update `lib/ui/generation_page/view_models/generation_page_viewmodel.dart`:

- import `generation_payload_cache.dart`
- replace:

```dart
PayloadGenerationResult? _cachedPayloadResult;
int _cacheRetriesCount = 0;
```

with:

```dart
final _payloadCache = GenerationPayloadCache<PayloadGenerationResult>();
```

- replace the cache selection block with:

```dart
final payloadResult = _payloadCache.takeOrGenerate(
  () => GeneratePayloadUseCase(payloadConfig: payloadConfig)(),
);
```

- on success, replace cache clearing with:

```dart
_payloadCache.markSuccess();
```

- in `startBatch()` and `stopBatch()`, replace cache resets with:

```dart
_payloadCache.reset();
```

- delete `_cacheRetriesCount` logic completely

Do not change `currentTotalCount`, `currentBatchCount`, cooldown, or stop-at-end logic in this task.

**Step 4: Run test to verify it passes**

Run: `flutter test test/ui/generation_page/models/generation_payload_cache_test.dart`

Expected: PASS.

**Step 5: Commit**

If this workspace is a git repository:

```bash
git add lib/ui/generation_page/view_models/generation_page_viewmodel.dart lib/ui/generation_page/models/generation_payload_cache.dart test/ui/generation_page/models/generation_payload_cache_test.dart
git commit -m "feat: advance prompts only after success"
```

If `git status` reports this is not a repository, skip this step.

### Task 4: Run focused and broad verification

**Files:**
- Verify: `test/ui/generation_page/models/generation_payload_cache_test.dart`
- Verify: `test/data/models/param_config_batch_resolution_behavior_test.dart`
- Verify optionally: `test/`

**Step 1: Run focused regression tests**

Run:

```bash
flutter test test/ui/generation_page/models/generation_payload_cache_test.dart
flutter test test/data/models/param_config_batch_resolution_behavior_test.dart
```

Expected: PASS. The new cache semantics should be green, and batch-resolution cursor tests should remain green.

**Step 2: Run the broader test suite**

Run: `flutter test`

Expected: PASS, or only pre-existing unrelated failures.

**Step 3: Manual verification**

Run the app and verify this exact behavior:

- configure a sequential prompt with at least two lines
- force a failure on line 1 (for example with an invalid key or endpoint)
- observe repeated retries stay on line 1
- restore a working request path and confirm the first success is still line 1
- confirm the next generation moves to line 2

**Step 4: Commit**

If this workspace is a git repository and all checks are green:

```bash
git add lib/ui/generation_page/view_models/generation_page_viewmodel.dart lib/ui/generation_page/models/generation_payload_cache.dart test/ui/generation_page/models/generation_payload_cache_test.dart
git commit -m "test: verify success-only prompt progression"
```

If `git status` reports this is not a repository, skip this step.
