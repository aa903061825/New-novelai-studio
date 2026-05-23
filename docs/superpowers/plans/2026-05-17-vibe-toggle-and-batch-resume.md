# Vibe Toggle And Batch Resume Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a machine-local vibe master switch, explicit batch-resume actions, and version `0.9.5` without changing saved-config JSON semantics.

**Architecture:** Introduce one dedicated runtime-state model that lives alongside `PayloadConfig` but is persisted separately from config export/import. Route vibe enablement and unfinished batch progress through that runtime state, then expose explicit `start fresh` and `continue` entrypoints in the generation-page view model and UI.

**Tech Stack:** Flutter, Dart, GetIt, Hive, flutter_test, easy_localization

> Workspace note: `C:\Users\admin\Downloads\NAI_NEW` is not a git repository in the current environment, so replace commit steps with manual verification checkpoints.

---

### Task 1: Add Local Runtime State And Persistence

**Files:**
- Create: `lib/data/models/generation_runtime_state.dart`
- Create: `test/data/models/generation_runtime_state_test.dart`
- Modify: `lib/data/models/payload_config.dart`
- Modify: `lib/data/services/config_service.dart`
- Modify: `lib/main.dart`

- [ ] **Step 1: Write the failing runtime-state tests**

Create `test/data/models/generation_runtime_state_test.dart` with focused round-trip and helper-behavior coverage:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/models/generation_runtime_state.dart';

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
```

- [ ] **Step 2: Run the new tests and confirm they fail**

Run:

```powershell
flutter test test/data/models/generation_runtime_state_test.dart -r expanded
```

Expected: FAIL with import or undefined-type errors for `GenerationRuntimeState`.

- [ ] **Step 3: Implement the runtime-state model and persistence wiring**

Create `lib/data/models/generation_runtime_state.dart`:

```dart
class GenerationRuntimeState {
  bool vibeEnabled;
  bool hasPendingBatchResume;
  int resumeTargetTotalCount;
  int resumeCompletedCount;
  DateTime? resumeStartedAt;

  GenerationRuntimeState({
    this.vibeEnabled = true,
    this.hasPendingBatchResume = false,
    this.resumeTargetTotalCount = 0,
    this.resumeCompletedCount = 0,
    this.resumeStartedAt,
  });

  factory GenerationRuntimeState.fromJson(Map<String, dynamic> json) {
    return GenerationRuntimeState(
      vibeEnabled: json['vibe_enabled'] ?? true,
      hasPendingBatchResume: json['has_pending_batch_resume'] ?? false,
      resumeTargetTotalCount: json['resume_target_total_count'] ?? 0,
      resumeCompletedCount: json['resume_completed_count'] ?? 0,
      resumeStartedAt: DateTime.tryParse(json['resume_started_at'] ?? ''),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'vibe_enabled': vibeEnabled,
      'has_pending_batch_resume': hasPendingBatchResume,
      'resume_target_total_count': resumeTargetTotalCount,
      'resume_completed_count': resumeCompletedCount,
      'resume_started_at': resumeStartedAt?.toIso8601String(),
    };
  }

  void recordBatchStart(int targetTotalCount) {
    hasPendingBatchResume = targetTotalCount > 0;
    resumeTargetTotalCount = targetTotalCount > 0 ? targetTotalCount : 0;
    resumeCompletedCount = 0;
    resumeStartedAt = hasPendingBatchResume ? DateTime.now() : null;
  }

  void recordBatchSuccess(int completedCount) {
    if (!hasPendingBatchResume) return;
    resumeCompletedCount = completedCount;
  }

  void clearPendingBatchResume() {
    hasPendingBatchResume = false;
    resumeTargetTotalCount = 0;
    resumeCompletedCount = 0;
    resumeStartedAt = null;
  }
}
```

Wire it into `lib/data/models/payload_config.dart`:

```dart
import 'package:nai_casrand/data/models/generation_runtime_state.dart';

class PayloadConfig {
  // ...
  GenerationRuntimeState generationRuntimeState;

  PayloadConfig({
    required this.rootPromptConfig,
    required this.characterConfigList,
    required this.savedPromptConfigList,
    required this.paramConfig,
    GlobalGenerationParams? globalGenerationParams,
    GenerationRuntimeState? generationRuntimeState,
    required this.settings,
    required this.overridePrompt,
    required this.useOverridePrompt,
    required this.useCharacterPromptWithOverride,
  })  : globalGenerationParams = globalGenerationParams ??
            GlobalGenerationParams.fromParamConfig(paramConfig),
        generationRuntimeState =
            generationRuntimeState ?? GenerationRuntimeState();
}
```

Add dedicated persistence in `lib/data/services/config_service.dart` and startup loading in `lib/main.dart`:

```dart
static const _generationRuntimeStateKey = 'generationRuntimeState';

GenerationRuntimeState? loadGenerationRuntimeState() {
  final jsonString = saveBox.get(_generationRuntimeStateKey);
  if (jsonString == null) return null;
  return GenerationRuntimeState.fromJson(
    (json.decode(jsonString) as Map).cast<String, dynamic>(),
  );
}

void saveGenerationRuntimeState(GenerationRuntimeState state) {
  saveBox.put(_generationRuntimeStateKey, json.encode(state.toJson()));
}
```

```dart
payloadConfig.generationRuntimeState =
    configService.loadGenerationRuntimeState() ?? GenerationRuntimeState();
```

- [ ] **Step 4: Run the model tests again**

Run:

```powershell
flutter test test/data/models/generation_runtime_state_test.dart -r expanded
```

Expected: PASS with 2 passing tests.

- [ ] **Step 5: Manual checkpoint**

Verify by inspection:
- `PayloadConfig.toJson()` still does not contain `generation_runtime_state`
- `ConfigService` has one dedicated key for runtime-state persistence
- `main.dart` loads runtime state after config JSON is restored

### Task 2: Add The Unified Vibe Master Switch

**Files:**
- Create: `test/data/use_cases/generate_payload_use_case_vibe_toggle_test.dart`
- Create: `test/ui/i2i_tab/i2i_tab_viewmodel_test.dart`
- Modify: `lib/data/use_cases/generate_payload_use_case.dart`
- Modify: `lib/ui/i2i_tab/view_models/i2i_tab_viewmodel.dart`
- Modify: `lib/ui/i2i_tab/widgets/i2i_tab_view.dart`
- Modify: `lib/ui/vibe_config/widgets/vibe_config_list_view.dart`
- Modify: `lib/ui/vibe_config_v4/widgets/vibe_config_v4_list_view.dart`

- [ ] **Step 1: Write failing tests for vibe gating and toggle persistence**

Create `test/data/use_cases/generate_payload_use_case_vibe_toggle_test.dart`:

```dart
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/models/param_config.dart';
import 'package:nai_casrand/data/models/payload_config.dart';
import 'package:nai_casrand/data/models/prompt_config.dart';
import 'package:nai_casrand/data/models/settings.dart';
import 'package:nai_casrand/data/models/vibe_config.dart';
import 'package:nai_casrand/data/models/vibe_config_v4.dart';
import 'package:nai_casrand/data/use_cases/generate_payload_use_case.dart';

PayloadConfig _buildPayloadConfig(String model) {
  final paramConfig = ParamConfig()..model = model;
  return PayloadConfig(
    rootPromptConfig: PromptConfig(strs: const ['prompt'], prompts: const []),
    characterConfigList: const [],
    savedPromptConfigList: const [],
    paramConfig: paramConfig,
    settings: Settings.fromJson({}),
    overridePrompt: '',
    useOverridePrompt: false,
    useCharacterPromptWithOverride: false,
  );
}

void main() {
  test('disabled vibe omits nai3 reference payload fields', () {
    final payloadConfig = _buildPayloadConfig('nai-diffusion-3');
    payloadConfig.vibeConfigList = [
      VibeConfig.fromBytes(
        Uint8List.fromList(const [1, 2, 3]),
        'legacy.png',
        0.8,
        0.4,
      ),
    ];
    payloadConfig.generationRuntimeState.vibeEnabled = false;

    final result = GeneratePayloadUseCase(payloadConfig: payloadConfig)();
    final params = result.payload['parameters'] as Map<String, dynamic>;

    expect(params.containsKey('reference_image_multiple'), isFalse);
    expect(params.containsKey('reference_strength_multiple'), isFalse);
    expect(
      params.containsKey('reference_information_extracted_multiple'),
      isFalse,
    );
  });

  test('enabled vibe keeps nai4 reference payload fields', () {
    final payloadConfig = _buildPayloadConfig('nai-diffusion-4-curated-preview');
    payloadConfig.vibeConfigListV4 = [
      VibeConfigV4(
        fileName: 'v4.vibe',
        vibeB64: 'abc123',
        referenceStrength: 0.65,
      ),
    ];
    payloadConfig.generationRuntimeState.vibeEnabled = true;

    final result = GeneratePayloadUseCase(payloadConfig: payloadConfig)();
    final params = result.payload['parameters'] as Map<String, dynamic>;

    expect(params['reference_image_multiple'], ['abc123']);
    expect(params['reference_strength_multiple'], [0.65]);
    expect(params['reference_information_extracted_multiple'], [1.0]);
  });
}
```

Create `test/ui/i2i_tab/i2i_tab_viewmodel_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:nai_casrand/data/models/generation_runtime_state.dart';
import 'package:nai_casrand/data/models/param_config.dart';
import 'package:nai_casrand/data/models/payload_config.dart';
import 'package:nai_casrand/data/models/prompt_config.dart';
import 'package:nai_casrand/data/models/settings.dart';
import 'package:nai_casrand/data/services/config_service.dart';
import 'package:nai_casrand/ui/i2i_tab/view_models/i2i_tab_viewmodel.dart';

class _FakeConfigService extends ConfigService {
  int saveRuntimeStateCallCount = 0;

  @override
  void saveGenerationRuntimeState(GenerationRuntimeState state) {
    saveRuntimeStateCallCount++;
  }
}

PayloadConfig _buildPayloadConfig() {
  return PayloadConfig(
    rootPromptConfig: PromptConfig(strs: const [], prompts: const []),
    characterConfigList: const [],
    savedPromptConfigList: const [],
    paramConfig: ParamConfig(),
    settings: Settings.fromJson({}),
    overridePrompt: '',
    useOverridePrompt: false,
    useCharacterPromptWithOverride: false,
  );
}

void main() {
  setUp(() async {
    await GetIt.I.reset();
    GetIt.I.registerSingleton<PayloadConfig>(_buildPayloadConfig());
    GetIt.I.registerSingleton<ConfigService>(_FakeConfigService());
  });

  tearDown(() async {
    await GetIt.I.reset();
  });

  test('setVibeEnabled updates runtime state and persists it', () {
    final viewmodel = I2iTabViewmodel();
    final configService = GetIt.I<ConfigService>() as _FakeConfigService;

    viewmodel.setVibeEnabled(false);

    expect(viewmodel.payloadConfig.generationRuntimeState.vibeEnabled, isFalse);
    expect(configService.saveRuntimeStateCallCount, 1);
  });
}
```

- [ ] **Step 2: Run the vibe-focused tests and confirm they fail**

Run:

```powershell
flutter test test/data/use_cases/generate_payload_use_case_vibe_toggle_test.dart test/ui/i2i_tab/i2i_tab_viewmodel_test.dart -r expanded
```

Expected: FAIL because `generationRuntimeState` accessors and `setVibeEnabled` do not exist yet.

- [ ] **Step 3: Implement the master switch, payload gating, and disabled-list UI**

Update `lib/ui/i2i_tab/view_models/i2i_tab_viewmodel.dart`:

```dart
import 'package:nai_casrand/data/services/config_service.dart';

class I2iTabViewmodel extends ChangeNotifier {
  // ...
  bool get vibeEnabled => payloadConfig.generationRuntimeState.vibeEnabled;

  void setVibeEnabled(bool value) {
    payloadConfig.generationRuntimeState.vibeEnabled = value;
    GetIt.I<ConfigService>().saveGenerationRuntimeState(
      payloadConfig.generationRuntimeState,
    );
    notifyListeners();
  }
}
```

Gate vibe assembly in `lib/data/use_cases/generate_payload_use_case.dart`:

```dart
final vibeEnabled = payloadConfig.generationRuntimeState.vibeEnabled;

if (usePreciseReference) {
  // existing precise reference branch
} else if (vibeEnabled && effectiveParamConfig.model.contains('-3')) {
  // existing NAI3 vibe branch
} else if (vibeEnabled && effectiveParamConfig.model.contains('-4-')) {
  // existing NAI4 vibe branch
}
```

Render the switch and disabled state in both vibe list views:

```dart
SwitchListTile(
  title: Text(context.tr('enable_vibe')),
  subtitle: Text(context.tr('enable_vibe_hint')),
  secondary: const Icon(Icons.auto_awesome_outlined),
  value: viewmodel.parentViewmodel.vibeEnabled,
  onChanged: viewmodel.parentViewmodel.setVibeEnabled,
),
IgnorePointer(
  ignoring: !viewmodel.parentViewmodel.vibeEnabled,
  child: AnimatedOpacity(
    duration: const Duration(milliseconds: 150),
    opacity: viewmodel.parentViewmodel.vibeEnabled ? 1.0 : 0.45,
    child: listBody,
  ),
),
```

Pass the parent I2I view model down from `lib/ui/i2i_tab/widgets/i2i_tab_view.dart` so both `VibeConfigListView` and `VibeConfigV4ListView` can read the same toggle.

- [ ] **Step 4: Run the vibe-focused tests again**

Run:

```powershell
flutter test test/data/use_cases/generate_payload_use_case_vibe_toggle_test.dart test/ui/i2i_tab/i2i_tab_viewmodel_test.dart -r expanded
```

Expected: PASS with 3 passing tests.

- [ ] **Step 5: Manual checkpoint**

Verify by inspection:
- turning the switch off does not mutate `vibeConfigList` or `vibeConfigListV4`
- the list stays visible but interaction widgets are wrapped in `IgnorePointer`
- the `GeneratePayloadUseCase` precise-reference branch remains untouched

### Task 3: Add Explicit Batch Resume State And ViewModel Entry Points

**Files:**
- Create: `test/ui/generation_page/view_models/generation_page_resume_test.dart`
- Modify: `lib/ui/generation_page/view_models/generation_page_viewmodel.dart`
- Modify: `lib/data/models/command_status.dart`

- [ ] **Step 1: Write failing resume-behavior tests**

Create `test/ui/generation_page/view_models/generation_page_resume_test.dart` with a narrow test harness built from the existing generation-page test helpers:

```dart
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:nai_casrand/data/models/api_request.dart';
import 'package:nai_casrand/data/models/command_status.dart';
import 'package:nai_casrand/data/models/payload_config.dart';
import 'package:nai_casrand/data/models/param_config.dart';
import 'package:nai_casrand/data/models/prompt_config.dart';
import 'package:nai_casrand/data/models/settings.dart';
import 'package:nai_casrand/ui/generation_page/view_models/generation_page_viewmodel.dart';

PayloadConfig _buildPayloadConfig() {
  return PayloadConfig(
    rootPromptConfig: PromptConfig(strs: const ['unused'], prompts: const []),
    characterConfigList: const [],
    savedPromptConfigList: const [],
    paramConfig: ParamConfig(),
    settings: Settings.fromJson({
      'api_key': 'test-key',
      'batch_count': 999,
      'batch_interval': 1,
      'number_of_requests': 3,
    }),
    overridePrompt: '',
    useOverridePrompt: false,
    useCharacterPromptWithOverride: false,
  );
}

class _ResumeTestViewmodel extends GenerationPageViewmodel {
  final List<String> savedFileNames = [];

  @override
  Future<ApiResponse> fetchData(ApiRequest request) async {
    return ApiResponse(status: '200', data: Uint8List(0));
  }

  @override
  Uint8List processResponse(Uint8List responseBytes) {
    return Uint8List.fromList([1, 2, 3]);
  }

  @override
  Future<void> savePictureToFile(Uint8List bytes, String fileName, String saveDir) async {
    savedFileNames.add(fileName);
  }

  @override
  String generateTimestampString(DateTime time) => '20260517080000';

  @override
  String generateRandomString() => 'fixed1';
}

Future<void> _drainCurrentCommand(GenerationPageViewmodel viewmodel) async {
  final command = viewmodel.currentCommand;
  expect(command, isNotNull);
  while (command!.isExecutingSync.value || command.isExecuting.value) {
    await Future<void>.delayed(Duration.zero);
  }
  await Future<void>.delayed(Duration.zero);
}

void main() {
  setUp(() async {
    await GetIt.I.reset();
    GetIt.I.registerSingleton<PayloadConfig>(_buildPayloadConfig());
    GetIt.I.registerSingleton<CommandStatus>(CommandStatus());
  });

  tearDown(() async {
    await GetIt.I.reset();
  });

  test('startBatchFromScratch ignores pending resume progress', () {
    final viewmodel = _ResumeTestViewmodel();
    final runtime = viewmodel.payloadConfig.generationRuntimeState
      ..hasPendingBatchResume = true
      ..resumeTargetTotalCount = 100
      ..resumeCompletedCount = 49;

    viewmodel.startBatchFromScratch();

    expect(viewmodel.commandStatus.currentTotalCount, 0);
    expect(runtime.resumeCompletedCount, 0);
    expect(runtime.resumeTargetTotalCount, 3);
  });

  test('stopBatch keeps pending resume after one successful image', () async {
    final viewmodel = _ResumeTestViewmodel();

    viewmodel.startBatchFromScratch();
    await _drainCurrentCommand(viewmodel);
    viewmodel.stopBatch();

    final runtime = viewmodel.payloadConfig.generationRuntimeState;
    expect(runtime.hasPendingBatchResume, isTrue);
    expect(runtime.resumeTargetTotalCount, 3);
    expect(runtime.resumeCompletedCount, 1);
  });

  test('resumeBatchFromNumber uses 1-based numbering semantics', () {
    final viewmodel = _ResumeTestViewmodel();

    viewmodel.resumeBatchFromNumber(2);

    expect(viewmodel.commandStatus.currentTotalCount, 1);
  });
}
```

- [ ] **Step 2: Run the resume tests and confirm they fail**

Run:

```powershell
flutter test test/ui/generation_page/view_models/generation_page_resume_test.dart -r expanded
```

Expected: FAIL because the explicit resume entrypoints do not exist yet.

- [ ] **Step 3: Implement fresh-start and resume entrypoints**

Add focused helpers in `lib/ui/generation_page/view_models/generation_page_viewmodel.dart`:

```dart
import 'package:nai_casrand/data/services/config_service.dart';

void _persistRuntimeState() {
  GetIt.I<ConfigService>().saveGenerationRuntimeState(
    payloadConfig.generationRuntimeState,
  );
}

void _beginBatch({required int initialCompletedCount, required int targetTotalCount}) {
  _payloadResultCache.reset();
  _hasPendingCachedPayloadRetry = false;
  _pendingFastRetry429 = false;
  _cooldownGeneration++;
  commandStatus.isCoolingDown.value = false;
  payloadConfig.paramConfig.resetBatchResolutionCursor();

  commandStatus.currentBatchCount = 0;
  commandStatus.currentTotalCount = initialCompletedCount;
  commandStatus.isBatchActive.value = true;
  commandStatus.batchTimestamp = DateTime.now();

  if (targetTotalCount > 0) {
    payloadConfig.generationRuntimeState.recordBatchStart(targetTotalCount);
    payloadConfig.generationRuntimeState.recordBatchSuccess(
      initialCompletedCount,
    );
  } else {
    payloadConfig.generationRuntimeState.clearPendingBatchResume();
  }
  _persistRuntimeState();
  nextCommand();
}

void startBatchFromScratch() {
  final targetTotalCount = payloadConfig.settings.numberOfRequests;
  _beginBatch(initialCompletedCount: 0, targetTotalCount: targetTotalCount);
}

void resumeBatchFromLast() {
  final runtime = payloadConfig.generationRuntimeState;
  if (!runtime.hasPendingBatchResume) return;
  _beginBatch(
    initialCompletedCount: runtime.resumeCompletedCount,
    targetTotalCount: runtime.resumeTargetTotalCount,
  );
}

void resumeBatchFromNumber(int startNumber) {
  final targetTotalCount = payloadConfig.settings.numberOfRequests;
  if (targetTotalCount <= 0) return;
  final clampedStart = startNumber.clamp(1, targetTotalCount);
  _beginBatch(
    initialCompletedCount: clampedStart - 1,
    targetTotalCount: targetTotalCount,
  );
}
```

Update success, finish, and stop paths:

```dart
commandStatus.currentTotalCount++;
payloadConfig.generationRuntimeState.recordBatchSuccess(
  commandStatus.currentTotalCount,
);
_persistRuntimeState();
```

```dart
if (commandStatus.currentTotalCount >= payloadConfig.settings.numberOfRequests &&
    payloadConfig.settings.numberOfRequests != 0) {
  payloadConfig.generationRuntimeState.clearPendingBatchResume();
  _persistRuntimeState();
  stopBatch();
  return;
}
```

```dart
void stopBatch() {
  _cooldownGeneration++;
  commandStatus.isBatchActive.value = false;
  commandStatus.isCoolingDown.value = false;
  _payloadResultCache.reset();
  _hasPendingCachedPayloadRetry = false;
  _pendingFastRetry429 = false;
  _persistRuntimeState();
}
```

Keep `toggleBatch()` as:

```dart
void toggleBatch() {
  if (commandStatus.isBatchActive.value) {
    stopBatch();
  } else {
    startBatchFromScratch();
  }
}
```

Use `CommandStatus` only for ephemeral in-memory counters; do not move persisted fields into it unless an extra notifier is genuinely required.

- [ ] **Step 4: Run the resume tests again**

Run:

```powershell
flutter test test/ui/generation_page/view_models/generation_page_resume_test.dart test/ui/generation_page/view_models/generation_page_viewmodel_test.dart -r expanded
```

Expected: PASS with the new resume tests plus all existing generation-page tests still passing.

- [ ] **Step 5: Manual checkpoint**

Verify by inspection:
- fresh start always flows through `startBatchFromScratch()`
- manual stop does not clear pending resume state
- normal finite completion clears pending resume state
- unlimited mode (`numberOfRequests == 0`) does not produce resumable state

### Task 4: Add Continue Buttons, Dialog Text, And Release Metadata

**Files:**
- Create: `test/ui/generation_page/generation_page_resume_controls_widget_test.dart`
- Modify: `lib/ui/generation_page/widgets/generation_page_view.dart`
- Modify: `assets/l10n/en.json`
- Modify: `assets/l10n/zh-CN.json`
- Modify: `pubspec.yaml`

- [ ] **Step 1: Write a failing widget test for the new controls**

Create `test/ui/generation_page/generation_page_resume_controls_widget_test.dart`:

```dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:nai_casrand/data/models/command_status.dart';
import 'package:nai_casrand/data/models/param_config.dart';
import 'package:nai_casrand/data/models/payload_config.dart';
import 'package:nai_casrand/data/models/prompt_config.dart';
import 'package:nai_casrand/data/models/settings.dart';
import 'package:nai_casrand/ui/generation_page/view_models/generation_page_viewmodel.dart';
import 'package:nai_casrand/ui/generation_page/widgets/generation_page_view.dart';

class _EnglishGenerationAssetLoader extends AssetLoader {
  const _EnglishGenerationAssetLoader();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async {
    return {
      'generation_settings': 'Generation Settings',
      'generate_one_prompt': 'Generate One Prompt',
      'toggle_generation': 'Start or stop generation',
      'continue_from_last_time': 'Continue From Last Time',
      'continue_from_number': 'Continue From Number',
      'continue_from_number_title': 'Continue From Number',
      'continue_from_number_hint': 'Enter the generation number to resume from',
      'confirm': 'Confirm',
    };
  }
}

PayloadConfig _buildPayloadConfig() {
  return PayloadConfig(
    rootPromptConfig: PromptConfig(strs: const [], prompts: const []),
    characterConfigList: const [],
    savedPromptConfigList: const [],
    paramConfig: ParamConfig(),
    settings: Settings.fromJson({'number_of_requests': 3}),
    overridePrompt: '',
    useOverridePrompt: false,
    useCharacterPromptWithOverride: false,
  );
}

class _LocalizedGenerationApp extends StatelessWidget {
  const _LocalizedGenerationApp({required this.viewmodel});

  final GenerationPageViewmodel viewmodel;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      locale: context.locale,
      supportedLocales: context.supportedLocales,
      localizationsDelegates: context.localizationDelegates,
      home: GenerationPageView(viewmodel: viewmodel),
    );
  }
}

Future<void> _pumpGenerationPage(WidgetTester tester, GenerationPageViewmodel viewmodel) async {
  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('en')],
      path: 'assets/l10n',
      assetLoader: const _EnglishGenerationAssetLoader(),
      fallbackLocale: const Locale('en'),
      startLocale: const Locale('en'),
      saveLocale: false,
      child: _LocalizedGenerationApp(viewmodel: viewmodel),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await EasyLocalization.ensureInitialized();
  });

  setUp(() async {
    await GetIt.I.reset();
    GetIt.I.registerSingleton<PayloadConfig>(_buildPayloadConfig());
    GetIt.I.registerSingleton<CommandStatus>(CommandStatus());
  });

  tearDown(() async {
    await GetIt.I.reset();
  });

  testWidgets('shows continue-from-last button only when resume state exists', (tester) async {
    final viewmodel = GenerationPageViewmodel();
    viewmodel.payloadConfig.generationRuntimeState
      ..hasPendingBatchResume = true
      ..resumeTargetTotalCount = 3
      ..resumeCompletedCount = 1;

    await _pumpGenerationPage(tester, viewmodel);

    expect(find.byTooltip('Continue From Last Time'), findsOneWidget);
    expect(find.byTooltip('Continue From Number'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run the widget test and confirm it fails**

Run:

```powershell
flutter test test/ui/generation_page/generation_page_resume_controls_widget_test.dart -r expanded
```

Expected: FAIL because the continue controls and localization keys do not exist yet.

- [ ] **Step 3: Implement the new controls, dialog, localization, and version bump**

Extend the floating action buttons in `lib/ui/generation_page/widgets/generation_page_view.dart`:

```dart
if (viewmodel.payloadConfig.generationRuntimeState.hasPendingBatchResume) ...[
  FloatingActionButton(
    heroTag: 'gpfab-resume-last',
    onPressed: viewmodel.commandStatus.isBatchActive.value
        ? null
        : viewmodel.resumeBatchFromLast,
    tooltip: tr('continue_from_last_time'),
    child: const Icon(Icons.history),
  ),
  const SizedBox(height: 20.0),
],
FloatingActionButton(
  heroTag: 'gpfab-resume-number',
  onPressed: viewmodel.commandStatus.isBatchActive.value ||
          viewmodel.payloadConfig.settings.numberOfRequests <= 0
      ? null
      : () => _showResumeFromNumberDialog(context),
  tooltip: tr('continue_from_number'),
  child: const Icon(Icons.format_list_numbered),
),
```

Add the dialog helper in the same file:

```dart
Future<void> _showResumeFromNumberDialog(BuildContext context) async {
  final controller = TextEditingController();
  final result = await showDialog<int>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(tr('continue_from_number_title')),
      content: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          hintText: tr('continue_from_number_hint'),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tr('cancel')),
        ),
        TextButton(
          onPressed: () {
            final value = int.tryParse(controller.text.trim());
            Navigator.of(context).pop(value);
          },
          child: Text(tr('confirm')),
        ),
      ],
    ),
  );

  if (result != null) {
    viewmodel.resumeBatchFromNumber(result);
  }
}
```

Add the localization keys in both `assets/l10n/en.json` and `assets/l10n/zh-CN.json`:

```json
{
  "enable_vibe": "Enable Vibe",
  "enable_vibe_hint": "Disable this to keep the list but ignore vibe transfer during generation.",
  "continue_from_last_time": "Continue From Last Time",
  "continue_from_number": "Continue From Number",
  "continue_from_number_title": "Continue From Number",
  "continue_from_number_hint": "Enter the generation number to resume from"
}
```

```json
{
  "enable_vibe": "启用 Vibe",
  "enable_vibe_hint": "关闭后保留列表内容，但生成时忽略 Vibe。",
  "continue_from_last_time": "从上次继续",
  "continue_from_number": "从指定数值继续",
  "continue_from_number_title": "从指定数值继续",
  "continue_from_number_hint": "输入要从第几次开始生成"
}
```

Update `pubspec.yaml`:

```yaml
version: 0.9.5
```

- [ ] **Step 4: Run the widget test and the targeted regression suite**

Run:

```powershell
flutter test test/ui/generation_page/generation_page_resume_controls_widget_test.dart test/data/models/generation_runtime_state_test.dart test/data/use_cases/generate_payload_use_case_vibe_toggle_test.dart test/ui/i2i_tab/i2i_tab_viewmodel_test.dart test/ui/generation_page/view_models/generation_page_resume_test.dart test/ui/generation_page/view_models/generation_page_viewmodel_test.dart -r expanded
```

Expected: PASS across the new targeted tests and existing generation-page regression coverage.

- [ ] **Step 5: Run analyzer and final manual verification**

Run:

```powershell
dart analyze lib/data/models/generation_runtime_state.dart lib/data/services/config_service.dart lib/data/use_cases/generate_payload_use_case.dart lib/ui/i2i_tab/view_models/i2i_tab_viewmodel.dart lib/ui/i2i_tab/widgets/i2i_tab_view.dart lib/ui/vibe_config/widgets/vibe_config_list_view.dart lib/ui/vibe_config_v4/widgets/vibe_config_v4_list_view.dart lib/ui/generation_page/view_models/generation_page_viewmodel.dart lib/ui/generation_page/widgets/generation_page_view.dart
```

Expected: PASS with no errors.

Manual UI checklist:
- the vibe switch sits at the top of the vibe-editing area
- turning the switch off visibly dims the vibe list and prevents interaction
- the default play button starts from scratch after a previous manual stop
- `from last time` appears only when there is unfinished finite progress
- `from specified number` opens a dialog and honors 1-based numbering

## Self-Review

Spec coverage checklist:
- Runtime-state model and persistence: Task 1
- Unified vibe switch and disabled list behavior: Task 2
- Vibe payload omission while disabled: Task 2
- Explicit fresh-start versus resume semantics: Task 3
- Manual-stop and app-restart resume persistence: Tasks 1 and 3
- Continue buttons and specified-number dialog: Task 4
- Version bump to `0.9.5`: Task 4

Placeholder scan:
- No `TBD`, `TODO`, or “implement later” placeholders remain.
- Each test step includes concrete file paths, code, and commands.

Type consistency:
- Runtime-state name is consistently `GenerationRuntimeState`.
- Resume entrypoints are consistently `startBatchFromScratch()`, `resumeBatchFromLast()`, and `resumeBatchFromNumber(int startNumber)`.
- Persistence API is consistently `saveGenerationRuntimeState(...)`.
