# Workbench Single Image Parameters Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the workbench's reused parameter/reference tabs with a dedicated single-image generation console.

**Architecture:** Keep `GenerationPageViewmodel` as the generation owner and add a focused workbench parameter view model that edits the current workbench `PayloadConfig`. The right-side workbench panel renders results, core single-image controls, randomness, prompt controls, reference status, and advanced controls without showing batch, environment, or global override controls.

**Tech Stack:** Flutter/Dart, GetIt, flutter_test widget tests, existing `PayloadConfig`, `ParamConfig`, `GenerationPageViewmodel`, and Studio UI tokens/widgets.

---

### Task 1: Protect The Workbench Boundary With Failing Widget Tests

**Files:**
- Modify: `test/ui/generation_page/generation_page_workbench_layout_test.dart`

- [ ] **Step 1: Replace the old tab expectation test**

Update `generation page hosts drawer composer and generation tabs` to assert the new single-image console contract:

```dart
testWidgets('generation page hosts drawer composer and single image console',
    (tester) async {
  tester.view.physicalSize = const Size(1500, 950);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await _pumpGenerationPage(tester, _WorkbenchLayoutViewmodel());

  expect(find.text('绱犳潗鎶藉眽'), findsOneWidget);
  expect(find.text('Prompt 缂栨帓'), findsOneWidget);
  expect(find.byKey(const ValueKey('workbench-single-image-console')),
      findsOneWidget);
  expect(find.byKey(const ValueKey('workbench-core-output-section')),
      findsOneWidget);
  expect(find.byKey(const ValueKey('workbench-randomness-section')),
      findsOneWidget);
  expect(find.byKey(const ValueKey('workbench-prompt-control-section')),
      findsOneWidget);
  expect(find.byKey(const ValueKey('workbench-reference-input-section')),
      findsOneWidget);
  expect(find.byKey(const ValueKey('workbench-advanced-section')),
      findsOneWidget);
  expect(find.text('鍙傛暟'), findsNothing);
  expect(find.text('鍙傝€?), findsNothing);
});
```

- [ ] **Step 2: Add absence checks for removed workbench controls**

Extend `workbench hides batch execution and resume controls`:

```dart
expect(find.text('Global'), findsNothing);
expect(find.text('鍚敤鍒嗚鲸鐜囨壒閲忕敓鍥?), findsNothing);
expect(find.text('鍒嗚鲸鐜囧垪琛?), findsNothing);
expect(find.text('NAI Token'), findsNothing);
expect(find.text('杈撳嚭鐩綍'), findsNothing);
expect(find.text('浠ｇ悊'), findsNothing);
expect(find.text('鎿﹂櫎 metadata'), findsNothing);
```

- [ ] **Step 3: Run the focused test and confirm RED**

Run:

```powershell
flutter test --no-pub test\ui\generation_page\generation_page_workbench_layout_test.dart -r expanded
```

Expected: FAIL because `workbench-single-image-console` and the new section labels do not exist yet.

### Task 2: Add A Workbench-Specific Parameter View Model

**Files:**
- Create: `lib/ui/studio_workbench/view_models/workbench_single_image_parameters_viewmodel.dart`
- Test: `test/ui/studio_workbench/workbench_single_image_parameters_viewmodel_test.dart`

- [ ] **Step 1: Write the failing view model tests**

Create tests that exercise payload mutation without GetIt globals:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/models/generation_size.dart';
import 'package:nai_casrand/data/models/param_config.dart';
import 'package:nai_casrand/data/models/payload_config.dart';
import 'package:nai_casrand/data/models/prompt_config.dart';
import 'package:nai_casrand/data/models/settings.dart';
import 'package:nai_casrand/ui/studio_workbench/view_models/workbench_single_image_parameters_viewmodel.dart';

PayloadConfig _payload() {
  return PayloadConfig(
    rootPromptConfig: PromptConfig(strs: const [], prompts: const []),
    characterConfigList: const [],
    savedPromptConfigList: const [],
    paramConfig: ParamConfig(),
    settings: Settings(),
    overridePrompt: '',
    useOverridePrompt: false,
    useCharacterPromptWithOverride: false,
  );
}

void main() {
  test('updates only the supplied workbench payload', () {
    final payload = _payload();
    final viewmodel = WorkbenchSingleImageParametersViewmodel(payload);

    viewmodel.setSteps(17);
    viewmodel.setScale(7.25);
    viewmodel.setCfgRescale(0.35);
    viewmodel.setSampler('k_euler');
    viewmodel.setNegativePrompt('bad anatomy');

    expect(payload.paramConfig.steps, 17);
    expect(payload.paramConfig.scale, 7.25);
    expect(payload.paramConfig.cfgRescale, 0.35);
    expect(payload.paramConfig.sampler, 'k_euler');
    expect(payload.paramConfig.negativePrompt, 'bad anatomy');
  });

  test('normalizes manual size to 64 pixel multiples', () {
    final payload = _payload();
    final viewmodel = WorkbenchSingleImageParametersViewmodel(payload);

    viewmodel.setManualSize(width: '801', height: '1201');

    expect(
      payload.paramConfig.sizes,
      const [GenerationSize(width: 832, height: 1216)],
    );
  });

  test('fixed seed input is retained when random seed is toggled', () {
    final payload = _payload();
    final viewmodel = WorkbenchSingleImageParametersViewmodel(payload);

    viewmodel.setRandomSeedEnabled(false);
    viewmodel.setSeed('12345');
    viewmodel.setRandomSeedEnabled(true);
    viewmodel.setRandomSeedEnabled(false);

    expect(payload.paramConfig.randomSeed, isFalse);
    expect(payload.paramConfig.seed, 12345);
  });
}
```

- [ ] **Step 2: Run the view model test and confirm RED**

Run:

```powershell
flutter test --no-pub test\ui\studio_workbench\workbench_single_image_parameters_viewmodel_test.dart -r expanded
```

Expected: FAIL because `WorkbenchSingleImageParametersViewmodel` does not exist.

- [ ] **Step 3: Implement the minimal view model**

Create `WorkbenchSingleImageParametersViewmodel` as a `ChangeNotifier` with:

```dart
final PayloadConfig payloadConfig;
ParamConfig get config => payloadConfig.paramConfig;
```

Add setters for model, size, steps, scale, cfg rescale, sampler, noise schedule, random seed, seed, negative prompt, legacy UC, auto position, SMEA, SMEA DYN, Variety+, and dynamic thresholding. Each setter mutates `config` and calls `notifyListeners()`.

- [ ] **Step 4: Run the view model test and confirm GREEN**

Run:

```powershell
flutter test --no-pub test\ui\studio_workbench\workbench_single_image_parameters_viewmodel_test.dart -r expanded
```

Expected: PASS.

### Task 3: Replace The Right-Side Tabs With A Single-Image Console

**Files:**
- Modify: `lib/ui/studio_workbench/widgets/generation_preview_panel.dart`
- Create: `lib/ui/studio_workbench/widgets/workbench_single_image_console.dart`
- Test: `test/ui/generation_page/generation_page_workbench_layout_test.dart`

- [ ] **Step 1: Introduce `WorkbenchSingleImageConsole`**

Create a widget with this public constructor:

```dart
class WorkbenchSingleImageConsole extends StatelessWidget {
  final GenerationPageViewmodel generationViewmodel;
  final WorkbenchSingleImageParametersViewmodel parametersViewmodel;

  const WorkbenchSingleImageConsole({
    super.key,
    required this.generationViewmodel,
    required this.parametersViewmodel,
  });
}
```

It renders:

```dart
StudioPanel(
  key: const ValueKey('workbench-single-image-console'),
  color: StudioTokens.surface2,
  child: ...
)
```

Sections must include stable keys:

```dart
const ValueKey('workbench-core-output-section')
const ValueKey('workbench-randomness-section')
const ValueKey('workbench-prompt-control-section')
const ValueKey('workbench-reference-input-section')
const ValueKey('workbench-advanced-section')
```

- [ ] **Step 2: Move the result list into the console**

Keep the existing waterfall result behavior by moving `_GenerationResultList` into the new console file or exporting it from the old panel. Preserve:

```dart
WaterfallFlow.builder(
  gridDelegate: SliverWaterfallFlowDelegateWithFixedCrossAxisCount(
    crossAxisCount: generationViewmodel.colNum,
  ),
  ...
)
```

- [ ] **Step 3: Wire `GenerationPreviewPanel` to the new console**

Replace the `DefaultTabController`, `TabBar`, `ParametersConfigView`, and `I2iTabView` composition with:

```dart
WorkbenchSingleImageConsole(
  generationViewmodel: viewmodel,
  parametersViewmodel:
      WorkbenchSingleImageParametersViewmodel(viewmodel.payloadConfig),
)
```

- [ ] **Step 4: Run the focused workbench layout test and confirm GREEN**

Run:

```powershell
flutter test --no-pub test\ui\generation_page\generation_page_workbench_layout_test.dart -r expanded
```

Expected: PASS for the new console contract.

### Task 4: Fill The Console Controls

**Files:**
- Modify: `lib/ui/studio_workbench/widgets/workbench_single_image_console.dart`
- Modify: `test/ui/generation_page/generation_page_workbench_layout_test.dart`

- [ ] **Step 1: Add widget test coverage for visible controls**

Add expectations for visible single-image controls:

```dart
expect(find.text('鐢熸垚妯″瀷'), findsOneWidget);
expect(find.text('鍥惧儚灏哄'), findsOneWidget);
expect(find.textContaining('Steps'), findsOneWidget);
expect(find.textContaining('Prompt Guidance'), findsOneWidget);
expect(find.textContaining('Prompt Guidance Rescale'), findsOneWidget);
expect(find.text('Sampler'), findsOneWidget);
expect(find.text('Noise Schedule'), findsOneWidget);
expect(find.byKey(const ValueKey('workbench-negative-prompt-field')),
    findsOneWidget);
expect(find.textContaining('Vibe'), findsOneWidget);
```

- [ ] **Step 2: Run the test and confirm RED**

Run:

```powershell
flutter test --no-pub test\ui\generation_page\generation_page_workbench_layout_test.dart -r expanded
```

Expected: FAIL for missing concrete control labels.

- [ ] **Step 3: Implement core output controls**

Use existing constants from `core/constants/parameters.dart` for model/sampler/noise options. Render compact list rows, sliders, switches, and text fields that call the view model setters.

- [ ] **Step 4: Implement randomness and prompt controls**

Render random seed switch, fixed seed input when disabled, Variety+, negative prompt field, legacy UC, and auto position when the selected model supports it.

- [ ] **Step 5: Implement reference summary**

Render collapsed-friendly summary rows for:

```dart
payloadConfig.generationRuntimeState.vibeEnabled
payloadConfig.vibeConfigList.length + payloadConfig.vibeConfigListV4.length
payloadConfig.i2iConfig.imageBase64.isNotEmpty
payloadConfig.preciseReferenceList.length
```

- [ ] **Step 6: Run the focused layout test and confirm GREEN**

Run:

```powershell
flutter test --no-pub test\ui\generation_page\generation_page_workbench_layout_test.dart -r expanded
```

Expected: PASS.

### Task 5: Verify Workbench And Batch Remain Separated

**Files:**
- Test: `test/ui/generation_page/generation_page_workbench_layout_test.dart`
- Test: `test/ui/studio_batch/studio_batch_page_test.dart`

- [ ] **Step 1: Run workbench regression tests**

Run:

```powershell
flutter test --no-pub test\ui\generation_page\generation_page_workbench_layout_test.dart test\ui\generation_page\generation_page_resume_controls_widget_test.dart -r expanded
```

Expected: PASS.

- [ ] **Step 2: Run batch regression test**

Run:

```powershell
flutter test --no-pub test\ui\studio_batch\studio_batch_page_test.dart -r expanded
```

Expected: PASS, with batch execution/environment settings still present in the batch page.

- [ ] **Step 3: Run static analysis**

Run:

```powershell
flutter analyze --no-pub
```

Expected: `No issues found!`

- [ ] **Step 4: Run the full test suite**

Run:

```powershell
flutter test --no-pub -r expanded
```

Expected: all tests pass.

## Self-Review

- Spec coverage: Tasks cover the dedicated workbench console, removed batch/environment/global controls, core output controls, random seed, prompt control, reference summary, payload boundary, and regressions for batch/settings separation.
- Completeness scan: This plan lists concrete files, commands, expected outcomes, and implementation steps.
- Type consistency: `WorkbenchSingleImageParametersViewmodel`, `WorkbenchSingleImageConsole`, `GenerationPageViewmodel`, and `PayloadConfig` names match existing project conventions.
