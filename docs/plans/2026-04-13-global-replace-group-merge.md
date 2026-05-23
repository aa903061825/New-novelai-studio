# Global Replace Group Merge Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add grouped global-replace behavior so a comma-separated `source` can match multiple prompt tags, keep one replacement at the earliest matched prompt position, and delete the rest with weight-aware matching.

**Architecture:** Keep `PromptReplaceRule` and the current editor model unchanged. Extend `GeneratePayloadUseCase` so single-source rules keep the old regex-based behavior, while comma-separated sources use a new tag-list merge path with weight-shell normalization and conditional weight inheritance. Keep replacement comments readable by applying grouped replacement to the value portion of comment lines instead of naively splitting the whole comment block.

**Tech Stack:** Flutter, Dart, `flutter_test`, `easy_localization`

---

### Task 1: Add failing tests for grouped merge semantics

**Files:**
- Modify: `test/data/use_cases/generate_payload_use_case_global_replace_test.dart`
- Modify later: `lib/data/use_cases/generate_payload_use_case.dart`

**Step 1: Write the failing test**

Add a focused test that proves a comma-separated `source` is no longer treated as one literal phrase.

```dart
test('merges comma-separated source tags at the earliest prompt position', () {
  final payloadConfig = _buildPayloadConfig(
    rules: [
      PromptReplaceRule(
        id: 'group-merge',
        source: 'black panties, white thighhighs, white strapless dress',
        target: 'bunny outfit',
        enabled: true,
      ),
    ],
    basePrompt: '1girl, white thighhighs, smile, black panties',
    characterPrompt: 'black panties, white thighhighs',
  );

  final result = GeneratePayloadUseCase(payloadConfig: payloadConfig)();
  final params = result.payload['parameters'] as Map<String, dynamic>;
  final characters = params['characterPrompts'] as List<dynamic>;

  expect(result.payload['input'], '1girl, bunny outfit, smile');
  expect((characters.first as Map<String, dynamic>)['prompt'], 'bunny outfit');
  expect(result.comment, contains('bunny outfit'));
});
```

Add a second test for empty-target deletion:

```dart
test('deletes every matched tag in a grouped rule when target is empty', () {
  final payloadConfig = _buildPayloadConfig(
    rules: [
      PromptReplaceRule(
        id: 'group-delete',
        source: 'black panties, white thighhighs',
        target: '',
        enabled: true,
      ),
    ],
    basePrompt: '1girl, black panties, smile, white thighhighs',
    characterPrompt: 'white thighhighs, black panties',
  );

  final result = GeneratePayloadUseCase(payloadConfig: payloadConfig)();
  final params = result.payload['parameters'] as Map<String, dynamic>;
  final characters = params['characterPrompts'] as List<dynamic>;

  expect(result.payload['input'], '1girl, smile');
  expect((characters.first as Map<String, dynamic>)['prompt'], '');
});
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/data/use_cases/generate_payload_use_case_global_replace_test.dart`

Expected: FAIL because the current engine treats the whole comma-separated `source` as one phrase and never performs grouped merge/delete behavior.

**Step 3: Write minimal implementation**

In `lib/data/use_cases/generate_payload_use_case.dart`, route rules into two paths:

- single-source rules keep the current regex replacement logic
- comma-separated rules use a grouped tag-list merge path

Implementation sketch:

```dart
String _applyPromptReplaceRules(String input, {bool isComment = false}) {
  var output = input;
  for (final rule in promptReplaceRules) {
    if (!rule.enabled) continue;
    if (_isGroupedReplaceSource(rule.source)) {
      output = isComment
          ? _applyGroupedRuleToComment(output, rule)
          : _applyGroupedRuleToTagList(output, rule);
      continue;
    }
    output = _applySinglePromptReplaceRule(output, rule);
  }
  return output;
}

bool _isGroupedReplaceSource(String source) {
  return source.contains(',') || source.contains('，');
}
```

Add prompt-tag parsing helpers that:

- split the prompt on commas
- trim each tag
- keep original order/index
- find all matching grouped candidates
- replace the earliest matched item with `target`
- remove the remaining matched items
- rebuild the prompt with `', '`

Also update the call sites so comments opt into comment-safe replacement:

```dart
prompt: _applyPromptReplaceRules(basePromptResult.toPrompt()),
comment: _applyPromptReplaceRules(basePromptResult.toComment(), isComment: true),
```

For comments, do not split the entire block blindly. Apply grouped replacement only to the value portion after the first `:` on each line so titles/indentation survive.

**Step 4: Run test to verify it passes**

Run: `flutter test test/data/use_cases/generate_payload_use_case_global_replace_test.dart`

Expected: PASS for the new grouped merge/delete tests.

**Step 5: Commit**

If this workspace is a git repository:

```bash
git add test/data/use_cases/generate_payload_use_case_global_replace_test.dart lib/data/use_cases/generate_payload_use_case.dart
git commit -m "feat: add grouped prompt replacement merge"
```

If `git status` reports this is not a repository, skip this step.

### Task 2: Add failing tests for weight-aware matching and inheritance

**Files:**
- Modify: `test/data/use_cases/generate_payload_use_case_global_replace_test.dart`
- Modify later: `lib/data/use_cases/generate_payload_use_case.dart`

**Step 1: Write the failing test**

Add a test that proves weighted tags match grouped plain-text candidates and inherit the earliest matched shell when the target is plain.

```dart
test('matches weighted grouped tags and inherits the anchor shell for a plain target', () {
  final payloadConfig = _buildPayloadConfig(
    rules: [
      PromptReplaceRule(
        id: 'weighted-group',
        source: 'black panties, white thighhighs',
        target: 'bunny outfit',
        enabled: true,
      ),
    ],
    basePrompt: '1girl, {white thighhighs}, 1::black panties::',
    characterPrompt: '0.8::black panties::, smile',
  );

  final result = GeneratePayloadUseCase(payloadConfig: payloadConfig)();
  final params = result.payload['parameters'] as Map<String, dynamic>;
  final characters = params['characterPrompts'] as List<dynamic>;

  expect(result.payload['input'], '1girl, {bunny outfit}');
  expect((characters.first as Map<String, dynamic>)['prompt'], '0.8::bunny outfit::, smile');
});
```

Add a second test to prove a weighted `target` wins over inherited shell:

```dart
test('uses weighted target as-is instead of nesting inherited shell', () {
  final payloadConfig = _buildPayloadConfig(
    rules: [
      PromptReplaceRule(
        id: 'weighted-target',
        source: 'black panties, white thighhighs',
        target: '0.8::bunny outfit::',
        enabled: true,
      ),
    ],
    basePrompt: '1::black panties::, white thighhighs',
    characterPrompt: '{white thighhighs}, black panties',
  );

  final result = GeneratePayloadUseCase(payloadConfig: payloadConfig)();
  final params = result.payload['parameters'] as Map<String, dynamic>;
  final characters = params['characterPrompts'] as List<dynamic>;

  expect(result.payload['input'], '0.8::bunny outfit::');
  expect((characters.first as Map<String, dynamic>)['prompt'], '0.8::bunny outfit::');
});
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/data/use_cases/generate_payload_use_case_global_replace_test.dart`

Expected: FAIL because the grouped merge path does not yet normalize `1::...::` or `{...}` shells, nor does it decide whether to inherit shell based on `target` content.

**Step 3: Write minimal implementation**

Add helper types and functions inside `lib/data/use_cases/generate_payload_use_case.dart`.

Implementation sketch:

```dart
class _WeightShell {
  final String kind;
  final String open;
  final String close;

  const _WeightShell({required this.kind, required this.open, required this.close});
}

class _ParsedTag {
  final String raw;
  final String trimmed;
  final String comparable;
  final _WeightShell? shell;

  const _ParsedTag({
    required this.raw,
    required this.trimmed,
    required this.comparable,
    required this.shell,
  });
}
```

Add shell-aware helpers:

- `_parseTag(String raw)`
- `_stripComparableCore(String value)`
- `_extractNumericShell(String value)` for patterns like `0.8::tag::`
- `_extractBraceShell(String value)` for `{tag}` and `{{tag}}`
- `_hasRecognizedShell(String value)`
- `_applyShell(String target, _WeightShell shell)`

Use these rules:

- compare grouped prompt tags by normalized core text
- if `target` already has a recognized shell, return `target` unchanged
- otherwise, if the anchor tag has a recognized shell, wrap `target` with that shell
- otherwise use plain `target`

Suggested regexes:

```dart
final numericShellPattern = RegExp(r'^([+-]?\d+(?:\.\d+)?)::(.*)::$');
final braceShellPattern = RegExp(r'^(\{+)(.*?)(\}+)$');
```

Keep the shell stripping conservative: only recognize the formats required by the approved design.

**Step 4: Run test to verify it passes**

Run: `flutter test test/data/use_cases/generate_payload_use_case_global_replace_test.dart`

Expected: PASS for the new weight-aware grouped replacement tests.

**Step 5: Commit**

If this workspace is a git repository:

```bash
git add test/data/use_cases/generate_payload_use_case_global_replace_test.dart lib/data/use_cases/generate_payload_use_case.dart
git commit -m "feat: add weight-aware grouped prompt replacement"
```

If `git status` reports this is not a repository, skip this step.

### Task 3: Update replacement hint copy to explain comma-group semantics

**Files:**
- Modify: `assets/l10n/en.json`
- Modify: `assets/l10n/zh-CN.json`
- Modify: `test/ui/prompt_tab/prompt_tab_dashboard_widget_test.dart`

**Step 1: Write the failing test**

Update the widget test expectations in `test/ui/prompt_tab/prompt_tab_dashboard_widget_test.dart` so the replacement hint describes grouped comma-separated sources.

Suggested English expectation:

```dart
expect(
  find.text(
    'Applied in order before generation. A comma-separated source acts as a grouped tag rule: the earliest matched tag becomes the target and other matched tags are removed.',
  ),
  findsOneWidget,
);
```

The mock localization map at the top of the same test file should use the same new copy.

**Step 2: Run test to verify it fails**

Run: `flutter test test/ui/prompt_tab/prompt_tab_dashboard_widget_test.dart`

Expected: FAIL because the locale JSON files still contain the old hint text.

**Step 3: Write minimal implementation**

Update `prompt_replace_rules_hint` in both locale files.

Suggested English copy:

```json
"prompt_replace_rules_hint": "Applied in order before generation. A comma-separated source acts as a grouped tag rule: the earliest matched tag becomes the target and other matched tags are removed."
```

Suggested Chinese copy:

```json
"prompt_replace_rules_hint": "生成前按顺序执行。source 使用逗号分隔时会作为一组 tag 处理：实际最早命中的项替换成 target，其余命中的项会被删除。"
```

Update the hard-coded English mock strings in the widget test file to match.

**Step 4: Run test to verify it passes**

Run: `flutter test test/ui/prompt_tab/prompt_tab_dashboard_widget_test.dart`

Expected: PASS.

**Step 5: Commit**

If this workspace is a git repository:

```bash
git add assets/l10n/en.json assets/l10n/zh-CN.json test/ui/prompt_tab/prompt_tab_dashboard_widget_test.dart
git commit -m "docs: clarify grouped replacement rule hint"
```

If `git status` reports this is not a repository, skip this step.

### Task 4: Run focused verification and regression checks

**Files:**
- Verify: `test/data/use_cases/generate_payload_use_case_global_replace_test.dart`
- Verify: `test/data/use_cases/generate_payload_use_case_character_placeholder_test.dart`
- Verify: `test/ui/prompt_tab/prompt_tab_dashboard_widget_test.dart`
- Verify: `test/l10n/prompt_replace_l10n_keys_test.dart`

**Step 1: Run the focused suite**

Run:

```bash
flutter test test/data/use_cases/generate_payload_use_case_global_replace_test.dart test/ui/prompt_tab/prompt_tab_dashboard_widget_test.dart test/l10n/prompt_replace_l10n_keys_test.dart
```

Expected: PASS.

**Step 2: Run a neighboring regression test**

Run:

```bash
flutter test test/data/use_cases/generate_payload_use_case_character_placeholder_test.dart
```

Expected: PASS, proving grouped replacement changes did not break nearby prompt-generation behavior.

**Step 3: Optional manual verification**

Run:

```bash
flutter run -d windows
```

Manual checklist:

- open the Prompt tab
- switch to Global Replacements
- add a rule with `source = black panties, white thighhighs, white rabbit tail`
- set `target = bunny outfit`
- generate a prompt containing any subset of those tags
- confirm the earliest matched tag becomes `bunny outfit`
- confirm the other matched tags disappear
- confirm `1::black panties::` and `{white thighhighs}` also participate in matching
- confirm a weighted target such as `0.8::bunny outfit::` is not double-wrapped

**Step 4: Commit**

If this workspace is a git repository:

```bash
git add lib/data/use_cases/generate_payload_use_case.dart test/data/use_cases/generate_payload_use_case_global_replace_test.dart assets/l10n/en.json assets/l10n/zh-CN.json test/ui/prompt_tab/prompt_tab_dashboard_widget_test.dart
git commit -m "feat: add grouped global prompt replacement"
```

If `git status` reports this is not a repository, skip this step.
