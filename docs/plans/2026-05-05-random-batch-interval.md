# Random Batch Interval Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add configurable random cooldown jitter so each batch pause uses `base interval + random jitter between a user-defined min and max`.

**Architecture:** Extend `Settings` with two persisted non-negative jitter fields and expose them in the existing batch settings UI. Keep the current fixed interval as the base value, then update `GenerationPageViewmodel.setCooldown()` to normalize the jitter range and compute one random cooldown duration per cooldown cycle.

**Tech Stack:** Flutter, Dart, `flutter_test`, existing settings/viewmodel architecture, `easy_localization`

---

### Task 1: Add failing tests for jitter settings persistence

**Files:**
- Create: `test/data/models/settings_batch_interval_jitter_test.dart`
- Modify later: `lib/data/models/settings.dart`

**Step 1: Write the failing test**

Create a model-level test proving the new settings fields round-trip through JSON and default to zero when missing.

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/models/settings.dart';

void main() {
  test('settings defaults batch interval jitter values to zero', () {
    final settings = Settings.fromJson({});

    expect(settings.batchIntervalJitterMinSec, 0);
    expect(settings.batchIntervalJitterMaxSec, 0);
  });

  test('settings persists batch interval jitter values in json', () {
    final settings = Settings.fromJson({
      'batch_interval': 30,
      'batch_interval_jitter_min': 10,
      'batch_interval_jitter_max': 40,
    });

    final json = settings.toJson();

    expect(settings.batchIntervalJitterMinSec, 10);
    expect(settings.batchIntervalJitterMaxSec, 40);
    expect(json['batch_interval_jitter_min'], 10);
    expect(json['batch_interval_jitter_max'], 40);
  });
}
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/data/models/settings_batch_interval_jitter_test.dart`

Expected: FAIL because the new settings fields do not exist yet.

**Step 3: Write minimal implementation**

Update `lib/data/models/settings.dart`:

- add `int batchIntervalJitterMinSec;`
- add `int batchIntervalJitterMaxSec;`
- wire them into the constructor
- in `fromJson()` default both to `0`
- in `toJson()` persist both values

Implementation sketch:

```dart
int batchIntervalJitterMinSec;
int batchIntervalJitterMaxSec;
```

```dart
batchIntervalJitterMinSec: json['batch_interval_jitter_min'] ?? 0,
batchIntervalJitterMaxSec: json['batch_interval_jitter_max'] ?? 0,
```

```dart
'batch_interval_jitter_min': batchIntervalJitterMinSec,
'batch_interval_jitter_max': batchIntervalJitterMaxSec,
```

**Step 4: Run test to verify it passes**

Run: `flutter test test/data/models/settings_batch_interval_jitter_test.dart`

Expected: PASS.

**Step 5: Commit**

If this workspace is a git repository:

```bash
git add test/data/models/settings_batch_interval_jitter_test.dart lib/data/models/settings.dart
git commit -m "feat: persist random batch interval settings"
```

If `git status` reports this is not a repository, skip this step.

### Task 2: Add failing tests for settings page jitter editing

**Files:**
- Create: `test/ui/settings_page/settings_page_viewmodel_test.dart`
- Modify later: `lib/ui/settings_page/view_models/settings_page_viewmodel.dart`
- Read for setup: `lib/data/models/payload_config.dart`
- Read for setup: `lib/data/models/settings.dart`

**Step 1: Write the failing test**

Create a focused viewmodel test covering write behavior and negative-value clamping.

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:nai_casrand/data/models/payload_config.dart';
import 'package:nai_casrand/data/models/prompt_config.dart';
import 'package:nai_casrand/data/models/param_config.dart';
import 'package:nai_casrand/data/models/settings.dart';
import 'package:nai_casrand/ui/settings_page/view_models/settings_page_viewmodel.dart';

void main() {
  setUp(() {
    GetIt.I.reset();
    GetIt.I.registerSingleton(
      PayloadConfig(
        rootPromptConfig: PromptConfig(strs: const [], prompts: const []),
        characterConfigList: const [],
        savedPromptConfigList: const [],
        paramConfig: ParamConfig(),
        settings: Settings.fromJson({}),
        overridePrompt: '',
        useOverridePrompt: false,
        useCharacterPromptWithOverride: false,
      ),
    );
  });

  test('sets batch interval jitter values from numeric input', () {
    final viewmodel = SettingsPageViewmodel();

    viewmodel.setBatchIntervalJitterMin('10');
    viewmodel.setBatchIntervalJitterMax('40');

    expect(viewmodel.settings.batchIntervalJitterMinSec, 10);
    expect(viewmodel.settings.batchIntervalJitterMaxSec, 40);
  });

  test('clamps negative jitter values to zero', () {
    final viewmodel = SettingsPageViewmodel();

    viewmodel.setBatchIntervalJitterMin('-3');
    viewmodel.setBatchIntervalJitterMax('-9');

    expect(viewmodel.settings.batchIntervalJitterMinSec, 0);
    expect(viewmodel.settings.batchIntervalJitterMaxSec, 0);
  });
}
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/ui/settings_page/settings_page_viewmodel_test.dart`

Expected: FAIL because the setter methods do not exist yet.

**Step 3: Write minimal implementation**

Add two setters in `lib/ui/settings_page/view_models/settings_page_viewmodel.dart`.

Implementation sketch:

```dart
void setBatchIntervalJitterMin(String value) {
  final parsed = int.tryParse(value);
  if (parsed == null) return;
  payloadConfig.settings.batchIntervalJitterMinSec = max(0, parsed);
  notifyListeners();
}

void setBatchIntervalJitterMax(String value) {
  final parsed = int.tryParse(value);
  if (parsed == null) return;
  payloadConfig.settings.batchIntervalJitterMaxSec = max(0, parsed);
  notifyListeners();
}
```

Import `dart:math` if needed for `max`.

**Step 4: Run test to verify it passes**

Run: `flutter test test/ui/settings_page/settings_page_viewmodel_test.dart`

Expected: PASS.

**Step 5: Commit**

If this workspace is a git repository:

```bash
git add test/ui/settings_page/settings_page_viewmodel_test.dart lib/ui/settings_page/view_models/settings_page_viewmodel.dart
git commit -m "feat: add settings jitter editors"
```

If `git status` reports this is not a repository, skip this step.

### Task 3: Add failing tests for cooldown jitter calculation

**Files:**
- Modify: `test/ui/generation_page/view_models/generation_page_viewmodel_test.dart`
- Modify later: `lib/ui/generation_page/view_models/generation_page_viewmodel.dart`
- Read for setup: `lib/data/models/settings.dart`

**Step 1: Write the failing test**

Extend the existing generation viewmodel test file with focused cooldown-duration tests using a test subclass that records the scheduled duration instead of waiting on a real timer.

Add tests like:

```dart
test('setCooldown uses the base interval when jitter range is zero', () {
  final viewmodel = _TestGenerationPageViewmodel();
  viewmodel.payloadConfig.settings.batchIntervalSec = 30;
  viewmodel.payloadConfig.settings.batchIntervalJitterMinSec = 0;
  viewmodel.payloadConfig.settings.batchIntervalJitterMaxSec = 0;

  viewmodel.setCooldown();

  expect(viewmodel.lastScheduledCooldown, const Duration(seconds: 30));
});

test('setCooldown adds jitter within the configured range', () {
  final viewmodel = _TestGenerationPageViewmodel(
    nextRandomInt: (upperBound) => 7,
  );
  viewmodel.payloadConfig.settings.batchIntervalSec = 30;
  viewmodel.payloadConfig.settings.batchIntervalJitterMinSec = 10;
  viewmodel.payloadConfig.settings.batchIntervalJitterMaxSec = 20;

  viewmodel.setCooldown();

  expect(viewmodel.lastScheduledCooldown, const Duration(seconds: 47));
});

test('setCooldown sorts an inverted jitter range before sampling', () {
  final viewmodel = _TestGenerationPageViewmodel(
    nextRandomInt: (upperBound) => 5,
  );
  viewmodel.payloadConfig.settings.batchIntervalSec = 30;
  viewmodel.payloadConfig.settings.batchIntervalJitterMinSec = 20;
  viewmodel.payloadConfig.settings.batchIntervalJitterMaxSec = 10;

  viewmodel.setCooldown();

  expect(viewmodel.lastScheduledCooldown, const Duration(seconds: 45));
});
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/ui/generation_page/view_models/generation_page_viewmodel_test.dart`

Expected: FAIL because cooldown calculation is still fixed and not injectable for deterministic jitter.

**Step 3: Write minimal implementation**

Update `lib/ui/generation_page/view_models/generation_page_viewmodel.dart`:

- add a tiny protected seam for deterministic testing, for example:

```dart
@protected
int randomInt(int upperBound) => Random().nextInt(upperBound);
```

- add a small helper that computes cooldown seconds:

```dart
@visibleForTesting
int computeCooldownSeconds() {
  final base = payloadConfig.settings.batchIntervalSec;
  final rawMin = payloadConfig.settings.batchIntervalJitterMinSec;
  final rawMax = payloadConfig.settings.batchIntervalJitterMaxSec;
  final minJitter = min(rawMin, rawMax);
  final maxJitter = max(rawMin, rawMax);
  final jitter = maxJitter == minJitter
      ? minJitter
      : minJitter + randomInt(maxJitter - minJitter + 1);
  return base + jitter;
}
```

- update `setCooldown()` to use:

```dart
final cooldownSeconds = computeCooldownSeconds();
scheduleCooldown(Duration(seconds: cooldownSeconds), () {
  commandStatus.isCoolingDown.value = false;
  commandStatus.currentBatchCount = 0;
  nextCommand();
});
```

If `scheduleCooldown` currently takes seconds instead of a `Duration`, adapt the seam minimally so tests can capture the exact computed duration.

**Step 4: Run test to verify it passes**

Run: `flutter test test/ui/generation_page/view_models/generation_page_viewmodel_test.dart`

Expected: PASS.

**Step 5: Commit**

If this workspace is a git repository:

```bash
git add test/ui/generation_page/view_models/generation_page_viewmodel_test.dart lib/ui/generation_page/view_models/generation_page_viewmodel.dart
git commit -m "feat: add random batch cooldown jitter"
```

If `git status` reports this is not a repository, skip this step.

### Task 4: Add the settings UI and localization

**Files:**
- Modify: `lib/ui/settings_page/widgets/settings_page_view.dart`
- Modify: `assets/l10n/en.json`
- Modify: `assets/l10n/zh-CN.json`
- Reuse: `lib/ui/settings_page/view_models/settings_page_viewmodel.dart`
- Verify optionally: widget tests if practical

**Step 1: Write the failing test**

If practical, add a focused widget or viewmodel-facing test that proves the two new fields are exposed in the settings UI. If a widget test is too heavy for this repo structure, document that this task will rely on direct manual verification and l10n presence checks instead.

Minimum expectation for a testable path:

```dart
expect(find.text('Minimum random jitter (seconds)'), findsOneWidget);
expect(find.text('Maximum random jitter (seconds)'), findsOneWidget);
```

**Step 2: Run test to verify it fails**

Run the focused widget test if one is added.

Expected: FAIL until the UI fields and strings exist.

**Step 3: Write minimal implementation**

Update `lib/ui/settings_page/widgets/settings_page_view.dart` to add two numeric `EditableListTile`s under the existing batch interval tile.

Implementation sketch:

```dart
Padding(
  padding: const EdgeInsets.only(left: 20),
  child: EditableListTile(
    leading: const Icon(Icons.tune),
    title: tr('batch_interval_jitter_min'),
    currentValue: viewmodel.settings.batchIntervalJitterMinSec.toString(),
    keyboardType: TextInputType.number,
    confirmOnSubmit: true,
    onEditComplete: (value) => viewmodel.setBatchIntervalJitterMin(value),
  ),
),
Padding(
  padding: const EdgeInsets.only(left: 20),
  child: EditableListTile(
    leading: const Icon(Icons.tune),
    title: tr('batch_interval_jitter_max'),
    currentValue: viewmodel.settings.batchIntervalJitterMaxSec.toString(),
    keyboardType: TextInputType.number,
    confirmOnSubmit: true,
    onEditComplete: (value) => viewmodel.setBatchIntervalJitterMax(value),
  ),
),
```

Add localization keys:

```json
"batch_interval_jitter_min": "Minimum random jitter (seconds)",
"batch_interval_jitter_max": "Maximum random jitter (seconds)"
```

```json
"batch_interval_jitter_min": "随机波动最小值（秒）",
"batch_interval_jitter_max": "随机波动最大值（秒）"
```

**Step 4: Run test to verify it passes**

Run the focused widget test if created; otherwise run a relevant existing widget suite plus manual check.

Suggested verification commands:

```bash
flutter test test/ui/settings_page/settings_page_viewmodel_test.dart
flutter test test/ui/generation_page/view_models/generation_page_viewmodel_test.dart
```

Expected: PASS.

**Step 5: Commit**

If this workspace is a git repository:

```bash
git add lib/ui/settings_page/widgets/settings_page_view.dart assets/l10n/en.json assets/l10n/zh-CN.json lib/ui/settings_page/view_models/settings_page_viewmodel.dart
git commit -m "feat: expose random batch cooldown settings"
```

If `git status` reports this is not a repository, skip this step.

### Task 5: Run focused and broad verification

**Files:**
- Verify: `test/data/models/settings_batch_interval_jitter_test.dart`
- Verify: `test/ui/settings_page/settings_page_viewmodel_test.dart`
- Verify: `test/ui/generation_page/view_models/generation_page_viewmodel_test.dart`
- Verify optionally: `test/`

**Step 1: Run focused tests**

Run:

```bash
flutter test test/data/models/settings_batch_interval_jitter_test.dart
flutter test test/ui/settings_page/settings_page_viewmodel_test.dart
flutter test test/ui/generation_page/view_models/generation_page_viewmodel_test.dart
```

Expected: PASS.

**Step 2: Run full suite**

Run: `flutter test`

Expected: PASS, or only pre-existing unrelated warnings.

**Step 3: Manual verification**

Verify in the app:

- open batch settings
- confirm the two new jitter inputs appear under batch interval
- set base = `30`, min = `10`, max = `40`
- start a batch and trigger cooldown
- confirm cooldown still works and repeated cooldowns do not all wait the exact same duration
- set min/max both to `0` and confirm behavior matches fixed interval mode
- set min larger than max and confirm no crash/regression

**Step 4: Commit**

If this workspace is a git repository and all checks are green:

```bash
git add lib/data/models/settings.dart lib/ui/settings_page/view_models/settings_page_viewmodel.dart lib/ui/settings_page/widgets/settings_page_view.dart lib/ui/generation_page/view_models/generation_page_viewmodel.dart assets/l10n/en.json assets/l10n/zh-CN.json test/data/models/settings_batch_interval_jitter_test.dart test/ui/settings_page/settings_page_viewmodel_test.dart test/ui/generation_page/view_models/generation_page_viewmodel_test.dart
git commit -m "test: verify random batch cooldown jitter"
```

If `git status` reports this is not a repository, skip this step.
