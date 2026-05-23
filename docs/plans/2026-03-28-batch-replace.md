# Batch Replace Rules Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a batch input flow to the global prompt replacement panel so pasted comma-separated prompt fragments can be turned into multiple editable replacement rules in one action.

**Architecture:** Keep the existing `PromptReplaceRule` model and replacement engine unchanged. Add transient batch-input state plus parsing/append logic to `PromptTabViewmodel`, then expose that behavior in `PromptReplaceRulesEditor` with new localized copy and targeted tests.

**Tech Stack:** Flutter, Dart, `flutter_test`, `easy_localization`, Provider/ChangeNotifier

---

### Task 1: Add ViewModel batch parsing behavior

**Files:**
- Modify: `lib/ui/prompt_tab/view_models/prompt_tab_viewmodel.dart`
- Test: `test/ui/prompt_tab/prompt_tab_viewmodel_test.dart`

**Step 1: Write the failing test**

Add a new test to `test/ui/prompt_tab/prompt_tab_viewmodel_test.dart` that exercises batch creation from mixed separators.

```dart
test('creates replacement rules from batch input and clears the draft', () {
  final viewmodel = _buildViewmodel();

  viewmodel.updateBatchReplaceRuleInput(
    ' pink dress,white jacket\nshort jacket， black boots ,, ',
  );

  viewmodel.addReplaceRulesFromBatchInput();

  expect(
    viewmodel.promptReplaceRules.map((rule) => rule.source).toList(),
    ['pink dress', 'white jacket', 'short jacket', 'black boots'],
  );
  expect(
    viewmodel.promptReplaceRules.every((rule) => rule.target.isEmpty),
    isTrue,
  );
  expect(
    viewmodel.promptReplaceRules.every((rule) => rule.enabled),
    isTrue,
  );
  expect(viewmodel.batchReplaceRuleInput, '');
});
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/ui/prompt_tab/prompt_tab_viewmodel_test.dart`

Expected: FAIL because `updateBatchReplaceRuleInput`, `addReplaceRulesFromBatchInput`, or `batchReplaceRuleInput` do not exist yet.

**Step 3: Write minimal implementation**

In `lib/ui/prompt_tab/view_models/prompt_tab_viewmodel.dart`, add:

- a `String batchReplaceRuleInput = '';`
- `void updateBatchReplaceRuleInput(String value)`
- `List<String> parseBatchReplaceRuleInput(String rawInput)`
- `void addReplaceRulesFromBatchInput()`

Implementation sketch:

```dart
String batchReplaceRuleInput = '';

void updateBatchReplaceRuleInput(String value) {
  batchReplaceRuleInput = value;
  notifyListeners();
}

List<String> parseBatchReplaceRuleInput(String rawInput) {
  return rawInput
      .split(RegExp(r'[,，\n\r]+'))
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList();
}

void addReplaceRulesFromBatchInput() {
  final sources = parseBatchReplaceRuleInput(batchReplaceRuleInput);
  if (sources.isEmpty) {
    return;
  }

  promptReplaceRules.addAll(
    sources.map(
      (source) => PromptReplaceRule.fromEmpty().copyWith(source: source),
    ),
  );
  batchReplaceRuleInput = '';
  notifyListeners();
}
```

Keep the parser intentionally simple: preserve order, trim whitespace, ignore blanks, no dedupe.

**Step 4: Run test to verify it passes**

Run: `flutter test test/ui/prompt_tab/prompt_tab_viewmodel_test.dart`

Expected: PASS.

**Step 5: Commit**

If this workspace is a git repository:

```bash
git add test/ui/prompt_tab/prompt_tab_viewmodel_test.dart lib/ui/prompt_tab/view_models/prompt_tab_viewmodel.dart
git commit -m "feat: add batch replacement rule parsing"
```

If `git status` reports this is not a repository, skip this step.

### Task 2: Add batch input UI to the replacement editor

**Files:**
- Modify: `lib/ui/prompt_tab/widgets/prompt_replace_rules_editor.dart`
- Test: `test/ui/prompt_tab/prompt_tab_dashboard_widget_test.dart`

**Step 1: Write the failing test**

Extend `test/ui/prompt_tab/prompt_tab_dashboard_widget_test.dart` with a widget test that:

- opens the replacement panel
- finds the batch input label/button
- enters a mixed-separator string
- taps the batch-create button
- verifies the created rule texts appear in the widget tree

Suggested test shape:

```dart
testWidgets('batch input creates multiple replacement rules', (tester) async {
  final viewmodel = _buildViewmodel();
  viewmodel.setActivePanel(PromptDashboardPanel.replaceRules);

  await tester.pumpWidget(
    MaterialApp(home: PromptTabView(viewmodel: viewmodel)),
  );

  expect(find.text('prompt_replace_batch_input'), findsOneWidget);

  await tester.enterText(
    find.byType(TextField).first,
    'pink dress, white jacket\nblack boots',
  );
  await tester.tap(find.text('prompt_replace_batch_add'));
  await tester.pumpAndSettle();

  expect(find.text('pink dress'), findsOneWidget);
  expect(find.text('white jacket'), findsOneWidget);
  expect(find.text('black boots'), findsOneWidget);
});
```

Adjust the finder if the panel already contains another `TextField`; use a key if necessary.

**Step 2: Run test to verify it fails**

Run: `flutter test test/ui/prompt_tab/prompt_tab_dashboard_widget_test.dart`

Expected: FAIL because the batch input UI and localization keys do not exist yet.

**Step 3: Write minimal implementation**

Update `lib/ui/prompt_tab/widgets/prompt_replace_rules_editor.dart` to add a batch input block between the hint text and the rule list. Use a `TextField` wired to `viewmodel.batchReplaceRuleInput`, and a button that calls `viewmodel.addReplaceRulesFromBatchInput()`.

Implementation sketch:

```dart
Padding(
  padding: const EdgeInsets.all(16),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(tr('prompt_replace_batch_input')),
      const SizedBox(height: 8),
      TextField(
        controller: TextEditingController(
          text: viewmodel.batchReplaceRuleInput,
        ),
        minLines: 2,
        maxLines: 4,
        onChanged: viewmodel.updateBatchReplaceRuleInput,
        decoration: InputDecoration(
          hintText: tr('prompt_replace_batch_placeholder'),
          border: const OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerRight,
        child: FilledButton.icon(
          onPressed: viewmodel.parseBatchReplaceRuleInput(
                    viewmodel.batchReplaceRuleInput,
                  ).isEmpty
              ? null
              : viewmodel.addReplaceRulesFromBatchInput,
          icon: const Icon(Icons.playlist_add),
          label: Text(tr('prompt_replace_batch_add')),
        ),
      ),
    ],
  ),
)
```

Important details:

- keep the existing per-rule editor unchanged
- append new rules after existing ones
- use a stable `TextEditingController` strategy; if a local controller causes cursor resets on rebuild, convert the editor to `StatefulWidget` and synchronize controller text in `didUpdateWidget`
- if needed for tests, give the batch `TextField` a key such as `ValueKey('prompt_replace_batch_input')`

**Step 4: Run test to verify it passes**

Run: `flutter test test/ui/prompt_tab/prompt_tab_dashboard_widget_test.dart`

Expected: PASS.

**Step 5: Commit**

If this workspace is a git repository:

```bash
git add test/ui/prompt_tab/prompt_tab_dashboard_widget_test.dart lib/ui/prompt_tab/widgets/prompt_replace_rules_editor.dart
git commit -m "feat: add batch replacement rule editor"
```

If `git status` reports this is not a repository, skip this step.

### Task 3: Add localization for the batch input flow

**Files:**
- Modify: `assets/l10n/zh-CN.json`
- Modify: `assets/l10n/en.json`
- Test: `test/l10n/prompt_replace_l10n_keys_test.dart`

**Step 1: Write the failing test**

Add the new required keys to `test/l10n/prompt_replace_l10n_keys_test.dart`:

```dart
'prompt_replace_batch_input',
'prompt_replace_batch_placeholder',
'prompt_replace_batch_hint',
'prompt_replace_batch_add',
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/l10n/prompt_replace_l10n_keys_test.dart`

Expected: FAIL because one or both locale files are missing the new keys.

**Step 3: Write minimal implementation**

Add concise copy to both locale files.

Suggested Chinese copy:

```json
"prompt_replace_batch_input": "批量规则输入",
"prompt_replace_batch_placeholder": "pink dress, white jacket, short jacket",
"prompt_replace_batch_hint": "支持使用 ,、，或换行分隔。创建后可继续编辑每条规则。",
"prompt_replace_batch_add": "批量创建规则"
```

Suggested English copy:

```json
"prompt_replace_batch_input": "Batch rule input",
"prompt_replace_batch_placeholder": "pink dress, white jacket, short jacket",
"prompt_replace_batch_hint": "Use commas or line breaks as separators. Each created rule remains editable.",
"prompt_replace_batch_add": "Create rules in batch"
```

If the widget does not yet render the hint, add it while implementing Task 2.

**Step 4: Run test to verify it passes**

Run: `flutter test test/l10n/prompt_replace_l10n_keys_test.dart`

Expected: PASS.

**Step 5: Commit**

If this workspace is a git repository:

```bash
git add test/l10n/prompt_replace_l10n_keys_test.dart assets/l10n/zh-CN.json assets/l10n/en.json
git commit -m "feat: add batch replacement rule copy"
```

If `git status` reports this is not a repository, skip this step.

### Task 4: Run focused verification and inspect behavior

**Files:**
- Verify: `test/ui/prompt_tab/prompt_tab_viewmodel_test.dart`
- Verify: `test/ui/prompt_tab/prompt_tab_dashboard_widget_test.dart`
- Verify: `test/l10n/prompt_replace_l10n_keys_test.dart`

**Step 1: Run the focused test suite**

Run:

```bash
flutter test test/ui/prompt_tab/prompt_tab_viewmodel_test.dart test/ui/prompt_tab/prompt_tab_dashboard_widget_test.dart test/l10n/prompt_replace_l10n_keys_test.dart
```

Expected: all tests PASS.

**Step 2: Run a broader regression test for prompt replacement behavior**

Run:

```bash
flutter test test/data/use_cases/generate_payload_use_case_global_replace_test.dart
```

Expected: PASS, proving the new batch creation flow did not change replacement semantics.

**Step 3: Optional manual verification**

Run the app and verify the UI flow manually:

```bash
flutter run -d windows
```

Manual checklist:

- open the Prompt tab
- switch to Global Replacements
- paste `pink dress, white jacket, short jacket`
- click the batch-create button
- confirm three enabled rules appear
- edit one target value and confirm the card remains editable

**Step 4: Commit**

If this workspace is a git repository:

```bash
git add lib/ui/prompt_tab/view_models/prompt_tab_viewmodel.dart lib/ui/prompt_tab/widgets/prompt_replace_rules_editor.dart test/ui/prompt_tab/prompt_tab_viewmodel_test.dart test/ui/prompt_tab/prompt_tab_dashboard_widget_test.dart test/l10n/prompt_replace_l10n_keys_test.dart assets/l10n/zh-CN.json assets/l10n/en.json
git commit -m "feat: add batch creation for prompt replacement rules"
```

If `git status` reports this is not a repository, skip this step.
