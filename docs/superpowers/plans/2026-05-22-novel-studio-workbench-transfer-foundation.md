# Novel Studio Workbench Transfer Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Initialize Novel Studio data internally and move user-facing creative-state file exchange to a safe workbench import/export path.

**Architecture:** Keep the existing `WorkspaceService` as an internal file-store primitive, but wrap startup in `StudioDataService` so app code initializes storage without presenting workspace choices to users. Add a whitelisted `WorkbenchDocument` transfer format over `PayloadConfig`, then expose it through a workbench transfer view model and icon actions on the current generation surface while removing Settings-level config import/export actions.

**Tech Stack:** Flutter/Dart, existing `PayloadConfig`, `WorkspaceService`, `FileService`, `FilePicker`, `GetIt`, `easy_localization`, `flutter_test`.

---

## Scope

In scope:

- Auto-create or reopen the internal Novel Studio data root on startup.
- Add a versioned workbench transfer JSON format that excludes API token, proxy, output folder, and other local settings.
- Accept legacy CasRand payload JSON through the same workbench import path.
- Put import/export controls on the current generation/workbench surface.
- Remove Settings header import/export actions so the user-facing exchange path is no longer Settings.

Out of scope:

- Six-destination Novel Studio navigation.
- Library, gallery, batch redesign, Prompt stack composer, or Artist Chain tools.
- Public source-import UI for KAMIA, CasRand, or Artist Chain Studio.

## File Structure

Create:

- `lib/data/studio/studio_data_service.dart`: internal startup wrapper for the existing workspace-backed data root.
- `lib/data/studio/models/workbench_document.dart`: versioned workbench transfer schema and whitelist-based payload snapshot.
- `lib/data/studio/services/workbench_transfer_service.dart`: JSON encode/decode and legacy-config compatibility for transfer documents.
- `lib/ui/studio_workbench/view_models/workbench_transfer_viewmodel.dart`: file picker and save-file orchestration for the current workbench surface.
- `lib/ui/studio_workbench/widgets/workbench_transfer_actions.dart`: icon-only import/export toolbar actions with tooltips.
- `test/data/studio/studio_data_service_test.dart`
- `test/data/studio/workbench_document_test.dart`
- `test/data/studio/workbench_transfer_service_test.dart`
- `test/ui/studio_workbench/workbench_transfer_actions_test.dart`

Modify:

- `lib/main.dart`: initialize and register internal studio data plus transfer services.
- `lib/ui/generation_page/widgets/generation_page_view.dart`: show workbench transfer actions above the existing generation result flow.
- `lib/ui/settings_page/widgets/settings_page_view.dart`: remove Settings-level import/export actions.
- `assets/l10n/en.json`
- `assets/l10n/zh-CN.json`
- `test/ui/settings_page/settings_page_view_widget_test.dart`

## Task 1: Internal Studio Data Startup

**Files:**

- Create: `lib/data/studio/studio_data_service.dart`
- Modify: `lib/main.dart`
- Test: `test/data/studio/studio_data_service_test.dart`

- [ ] **Step 1: Write the failing service tests**

Create `test/data/studio/studio_data_service_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/studio/studio_data_service.dart';
import 'package:nai_casrand/data/workspace/models/workspace_entities.dart';
import 'package:nai_casrand/data/workspace/workspace_service.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('studio-data-test-');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('initializeAt creates the internal studio data root once', () async {
    final workspaceService = WorkspaceService();
    final service = StudioDataService(workspaceService: workspaceService);

    await service.initializeAt(tempDir);

    expect(workspaceService.root!.path, tempDir.path);
    expect(
      File('${tempDir.path}${Platform.pathSeparator}studio_manifest.json')
          .existsSync(),
      isTrue,
    );
  });

  test('initializeAt reopens existing studio data without clearing assets',
      () async {
    final firstWorkspace = WorkspaceService();
    await StudioDataService(workspaceService: firstWorkspace)
        .initializeAt(tempDir);
    await firstWorkspace.saveCharacters([
      CharacterEntry(
        id: 'char-1',
        name: 'Heroine',
        traits: const ViewVariantTexts(frontFull: 'silver hair'),
      ),
    ]);

    final reopenedWorkspace = WorkspaceService();
    await StudioDataService(workspaceService: reopenedWorkspace)
        .initializeAt(tempDir);

    final characters = await reopenedWorkspace.loadCharacters();
    expect(characters.single.name, 'Heroine');
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```powershell
flutter test test/data/studio/studio_data_service_test.dart
```

Expected: FAIL because `data/studio/studio_data_service.dart` does not exist.

- [ ] **Step 3: Add the internal data service**

Create `lib/data/studio/studio_data_service.dart`:

```dart
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:nai_casrand/data/workspace/workspace_paths.dart';
import 'package:nai_casrand/data/workspace/workspace_service.dart';

class StudioDataService {
  final WorkspaceService workspaceService;

  StudioDataService({required this.workspaceService});

  Future<void> initializeForApp() async {
    final supportDir = await getApplicationSupportDirectory();
    final studioDir = Directory(
      '${supportDir.path}${Platform.pathSeparator}novel_studio',
    );
    await initializeAt(studioDir);
  }

  Future<void> initializeAt(Directory root) async {
    final manifest = File(
      '${root.path}${Platform.pathSeparator}${WorkspacePaths.manifest}',
    );
    if (await manifest.exists()) {
      await workspaceService.openWorkspace(root.path);
      return;
    }
    await workspaceService.createWorkspace(root.path);
  }
}
```

- [ ] **Step 4: Run the service tests**

Run:

```powershell
flutter test test/data/studio/studio_data_service_test.dart
```

Expected: PASS.

- [ ] **Step 5: Initialize it during app startup**

Update the top-level service setup in `lib/main.dart`:

```dart
import 'package:nai_casrand/data/studio/studio_data_service.dart';
import 'package:nai_casrand/data/workspace/workspace_service.dart';
```

Replace the lazy `WorkspaceService` registration with:

```dart
  final workspaceService = WorkspaceService();
  final studioDataService = StudioDataService(
    workspaceService: workspaceService,
  );
  await studioDataService.initializeForApp();
  GetIt.instance.registerSingleton<WorkspaceService>(workspaceService);
  GetIt.instance.registerSingleton<StudioDataService>(studioDataService);
```

Keep `WorkspaceHealthViewModel` registration internal for now:

```dart
  GetIt.instance.registerFactory(
    () => WorkspaceHealthViewModel(GetIt.I<WorkspaceService>()),
  );
```

- [ ] **Step 6: Run the service test and analyzer**

Run:

```powershell
flutter test test/data/studio/studio_data_service_test.dart
flutter analyze lib/main.dart lib/data/studio/studio_data_service.dart
```

Expected: test PASS and analyzer reports no new errors.

- [ ] **Step 7: Commit when the checkout supports it**

```powershell
git add lib/main.dart lib/data/studio/studio_data_service.dart test/data/studio/studio_data_service_test.dart
git commit -m "feat: initialize internal studio data"
```

If this directory still has no `.git`, record these changed files in the implementation summary instead of committing.

## Task 2: Versioned Workbench Transfer Document

**Files:**

- Create: `lib/data/studio/models/workbench_document.dart`
- Test: `test/data/studio/workbench_document_test.dart`

- [ ] **Step 1: Write failing document tests**

Create `test/data/studio/workbench_document_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/models/param_config.dart';
import 'package:nai_casrand/data/models/payload_config.dart';
import 'package:nai_casrand/data/models/prompt_config.dart';
import 'package:nai_casrand/data/models/settings.dart';
import 'package:nai_casrand/data/studio/models/workbench_document.dart';

PayloadConfig _payload({
  required String prompt,
  required String apiKey,
  required String proxy,
}) {
  return PayloadConfig(
    rootPromptConfig: PromptConfig(strs: [prompt], prompts: const []),
    characterConfigList: const [],
    savedPromptConfigList: const [],
    paramConfig: ParamConfig(steps: 33),
    settings: Settings.fromJson({
      'api_key': apiKey,
      'proxy': proxy,
      'output_folder': r'C:\private-output',
    }),
    overridePrompt: prompt,
    useOverridePrompt: true,
    useCharacterPromptWithOverride: false,
  );
}

void main() {
  test('workbench export keeps creative state and omits local settings', () {
    final document = WorkbenchDocument.fromPayloadConfig(
      _payload(prompt: 'city rain', apiKey: 'pst-secret', proxy: '127.0.0.1:9'),
    );

    final json = document.toJson();

    expect(json['kind'], WorkbenchDocument.kind);
    expect(json['version'], WorkbenchDocument.currentVersion);
    expect((json['payload'] as Map<String, dynamic>)['settings'], isNull);
    expect(json.toString(), isNot(contains('pst-secret')));
    expect(json.toString(), isNot(contains('private-output')));
    expect(json.toString(), contains('city rain'));
  });

  test('applyTo restores creative state and preserves local settings', () {
    final document = WorkbenchDocument.fromPayloadConfig(
      _payload(prompt: 'imported prompt', apiKey: 'pst-export', proxy: ''),
    );
    final target = _payload(
      prompt: 'current prompt',
      apiKey: 'pst-current',
      proxy: '127.0.0.1:7890',
    );

    document.applyTo(target);

    expect(target.overridePrompt, 'imported prompt');
    expect(target.paramConfig.steps, 33);
    expect(target.settings.apiKey, 'pst-current');
    expect(target.settings.proxy, '127.0.0.1:7890');
  });
}
```

- [ ] **Step 2: Run the document test to verify it fails**

Run:

```powershell
flutter test test/data/studio/workbench_document_test.dart
```

Expected: FAIL because `WorkbenchDocument` does not exist.

- [ ] **Step 3: Add the transfer document model**

Create `lib/data/studio/models/workbench_document.dart`:

```dart
import 'package:nai_casrand/data/models/payload_config.dart';

class WorkbenchDocument {
  static const kind = 'novel-studio-workbench';
  static const currentVersion = 1;

  static const _payloadKeys = <String>{
    'prompt_config',
    'character_config',
    'saved_config',
    'prompt_replace_rules',
    'param_config',
    'vibe_config_list',
    'vibe_config_list_v4',
    'override_prompt',
    'use_override_prompt',
    'use_character_prompt_with_override',
    'use_precise_reference',
    'precise_reference_list',
  };

  final int version;
  final Map<String, dynamic> payload;

  const WorkbenchDocument({
    required this.version,
    required this.payload,
  });

  factory WorkbenchDocument.fromPayloadConfig(PayloadConfig config) {
    return WorkbenchDocument(
      version: currentVersion,
      payload: _extractPayload(config.toJson()),
    );
  }

  factory WorkbenchDocument.fromPayloadJson(Map<String, dynamic> json) {
    return WorkbenchDocument(
      version: currentVersion,
      payload: _extractPayload(json),
    );
  }

  factory WorkbenchDocument.fromJson(Map<String, dynamic> json) {
    if (json['kind'] != kind) {
      throw const FormatException('Unsupported workbench document kind.');
    }
    final version = json['version'];
    if (version is! int || version > currentVersion) {
      throw const FormatException('Unsupported workbench document version.');
    }
    final payload = json['payload'];
    if (payload is! Map) {
      throw const FormatException('Workbench document payload is missing.');
    }
    return WorkbenchDocument(
      version: version,
      payload: _extractPayload(payload.cast<String, dynamic>()),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'kind': kind,
      'version': version,
      'payload': payload,
    };
  }

  void applyTo(PayloadConfig target) {
    target.loadJson(
      {
        ...target.toJson(),
        ...payload,
        'settings': target.settings.toJson(),
      },
      preserveCurrentApiKey: true,
    );
  }

  static Map<String, dynamic> _extractPayload(Map<String, dynamic> json) {
    return {
      for (final key in _payloadKeys)
        if (json.containsKey(key)) key: json[key],
    };
  }
}
```

- [ ] **Step 4: Run the document tests**

Run:

```powershell
flutter test test/data/studio/workbench_document_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit when possible**

```powershell
git add lib/data/studio/models/workbench_document.dart test/data/studio/workbench_document_test.dart
git commit -m "feat: add workbench transfer document"
```

If this directory still has no `.git`, record the changed files in the implementation summary instead of committing.

## Task 3: Workbench Transfer Service and Legacy Compatibility

**Files:**

- Create: `lib/data/studio/services/workbench_transfer_service.dart`
- Test: `test/data/studio/workbench_transfer_service_test.dart`

- [ ] **Step 1: Write failing transfer-service tests**

Create `test/data/studio/workbench_transfer_service_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/models/param_config.dart';
import 'package:nai_casrand/data/models/payload_config.dart';
import 'package:nai_casrand/data/models/prompt_config.dart';
import 'package:nai_casrand/data/models/settings.dart';
import 'package:nai_casrand/data/studio/models/workbench_document.dart';
import 'package:nai_casrand/data/studio/services/workbench_transfer_service.dart';

PayloadConfig _payload(String prompt) {
  return PayloadConfig(
    rootPromptConfig: PromptConfig(strs: [prompt], prompts: const []),
    characterConfigList: const [],
    savedPromptConfigList: const [],
    paramConfig: ParamConfig(),
    settings: Settings.fromJson({'api_key': 'pst-current'}),
    overridePrompt: prompt,
    useOverridePrompt: true,
    useCharacterPromptWithOverride: false,
  );
}

void main() {
  test('exportText emits the workbench document envelope', () {
    final text = WorkbenchTransferService().exportText(_payload('soft light'));
    final json = jsonDecode(text) as Map<String, dynamic>;

    expect(json['kind'], WorkbenchDocument.kind);
    expect(json.toString(), contains('soft light'));
  });

  test('decode accepts a workbench document', () {
    final service = WorkbenchTransferService();
    final text = service.exportText(_payload('rainy street'));

    final document = service.decode(text);

    expect(document.payload['override_prompt'], 'rainy street');
  });

  test('decode accepts legacy CasRand payload json', () {
    final service = WorkbenchTransferService();
    final text = jsonEncode(_payload('legacy prompt').toJson());

    final document = service.decode(text);

    expect(document.payload['override_prompt'], 'legacy prompt');
    expect(document.toJson()['kind'], WorkbenchDocument.kind);
  });
}
```

- [ ] **Step 2: Run the transfer-service tests to verify they fail**

Run:

```powershell
flutter test test/data/studio/workbench_transfer_service_test.dart
```

Expected: FAIL because `WorkbenchTransferService` does not exist.

- [ ] **Step 3: Add the transfer service**

Create `lib/data/studio/services/workbench_transfer_service.dart`:

```dart
import 'dart:convert';

import 'package:nai_casrand/data/models/payload_config.dart';
import 'package:nai_casrand/data/studio/models/workbench_document.dart';

class WorkbenchTransferService {
  String exportText(PayloadConfig config) {
    const encoder = JsonEncoder.withIndent('  ');
    return '${encoder.convert(WorkbenchDocument.fromPayloadConfig(config).toJson())}\n';
  }

  WorkbenchDocument decode(String text) {
    final decoded = jsonDecode(text);
    if (decoded is! Map) {
      throw const FormatException('Workbench transfer must be a JSON object.');
    }
    final json = decoded.cast<String, dynamic>();
    if (json['kind'] == WorkbenchDocument.kind) {
      return WorkbenchDocument.fromJson(json);
    }
    if (json.containsKey('prompt_config')) {
      return WorkbenchDocument.fromPayloadJson(json);
    }
    throw const FormatException('Unsupported workbench transfer file.');
  }

  void importText(PayloadConfig target, String text) {
    decode(text).applyTo(target);
  }
}
```

- [ ] **Step 4: Run the document and transfer-service tests**

Run:

```powershell
flutter test test/data/studio/workbench_document_test.dart test/data/studio/workbench_transfer_service_test.dart
```

Expected: PASS.

- [ ] **Step 5: Register the transfer service**

Add to `lib/main.dart`:

```dart
import 'package:nai_casrand/data/studio/services/workbench_transfer_service.dart';
```

Register it after `PayloadConfig` is registered:

```dart
  GetIt.instance.registerLazySingleton(() => WorkbenchTransferService());
```

- [ ] **Step 6: Run analyzer on the new service path**

Run:

```powershell
flutter analyze lib/data/studio lib/main.dart
```

Expected: no new analyzer errors.

- [ ] **Step 7: Commit when possible**

```powershell
git add lib/main.dart lib/data/studio/services/workbench_transfer_service.dart test/data/studio/workbench_transfer_service_test.dart
git commit -m "feat: add workbench transfer service"
```

If this directory still has no `.git`, record the changed files in the implementation summary instead of committing.

## Task 4: Workbench Transfer View Model

**Files:**

- Create: `lib/ui/studio_workbench/view_models/workbench_transfer_viewmodel.dart`
- Modify: `lib/main.dart`
- Test: `test/ui/studio_workbench/workbench_transfer_viewmodel_test.dart`

- [ ] **Step 1: Write failing view-model tests**

Create `test/ui/studio_workbench/workbench_transfer_viewmodel_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/models/param_config.dart';
import 'package:nai_casrand/data/models/payload_config.dart';
import 'package:nai_casrand/data/models/prompt_config.dart';
import 'package:nai_casrand/data/models/settings.dart';
import 'package:nai_casrand/data/studio/services/workbench_transfer_service.dart';
import 'package:nai_casrand/ui/studio_workbench/view_models/workbench_transfer_viewmodel.dart';

PayloadConfig _payload(String prompt) {
  return PayloadConfig(
    rootPromptConfig: PromptConfig(strs: [prompt], prompts: const []),
    characterConfigList: const [],
    savedPromptConfigList: const [],
    paramConfig: ParamConfig(),
    settings: Settings.fromJson({'api_key': 'pst-current'}),
    overridePrompt: prompt,
    useOverridePrompt: true,
    useCharacterPromptWithOverride: false,
  );
}

void main() {
  test('importText updates payload and notifies listeners', () {
    final target = _payload('current');
    final text = WorkbenchTransferService().exportText(_payload('imported'));
    final viewModel = WorkbenchTransferViewModel(
      payloadConfig: target,
      transferService: WorkbenchTransferService(),
    );
    var notifications = 0;
    viewModel.addListener(() => notifications++);

    viewModel.importText(text);

    expect(target.overridePrompt, 'imported');
    expect(notifications, 1);
  });

  test('exportText delegates to transfer service', () {
    final viewModel = WorkbenchTransferViewModel(
      payloadConfig: _payload('export me'),
      transferService: WorkbenchTransferService(),
    );

    expect(viewModel.exportText(), contains('export me'));
  });
}
```

- [ ] **Step 2: Run the view-model tests to verify they fail**

Run:

```powershell
flutter test test/ui/studio_workbench/workbench_transfer_viewmodel_test.dart
```

Expected: FAIL because `WorkbenchTransferViewModel` does not exist.

- [ ] **Step 3: Add the transfer view model**

Create `lib/ui/studio_workbench/view_models/workbench_transfer_viewmodel.dart`:

```dart
import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:nai_casrand/data/models/payload_config.dart';
import 'package:nai_casrand/data/services/file_service.dart';
import 'package:nai_casrand/data/studio/services/workbench_transfer_service.dart';
import 'package:nai_casrand/ui/core/utils/flushbar.dart';

class WorkbenchTransferViewModel extends ChangeNotifier {
  final PayloadConfig payloadConfig;
  final WorkbenchTransferService transferService;

  WorkbenchTransferViewModel({
    required this.payloadConfig,
    required this.transferService,
  });

  String exportText() => transferService.exportText(payloadConfig);

  void importText(String text) {
    transferService.importText(payloadConfig, text);
    notifyListeners();
  }

  Future<void> importFromFile(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null) return;
    try {
      final bytes = result.files.single.bytes;
      if (bytes == null) {
        throw const FormatException('Selected workbench file is empty.');
      }
      importText(utf8.decode(bytes));
      if (!context.mounted) return;
      showInfoBar(context, tr('workbench_import_succeeded'));
    } catch (error) {
      if (!context.mounted) return;
      showErrorBar(context, '${tr('workbench_import_failed')}: $error');
    }
  }

  Future<void> exportToFile() {
    final name =
        'novel-studio-workbench-${FileService().generateRandomString()}.json';
    return FileService().saveStringToFile(exportText(), name);
  }
}
```

- [ ] **Step 4: Register view-model construction**

Add to `lib/main.dart`:

```dart
import 'package:nai_casrand/ui/studio_workbench/view_models/workbench_transfer_viewmodel.dart';
```

Register after `WorkbenchTransferService`:

```dart
  GetIt.instance.registerFactory(
    () => WorkbenchTransferViewModel(
      payloadConfig: GetIt.I<PayloadConfig>(),
      transferService: GetIt.I<WorkbenchTransferService>(),
    ),
  );
```

- [ ] **Step 5: Run view-model tests and analyzer**

Run:

```powershell
flutter test test/ui/studio_workbench/workbench_transfer_viewmodel_test.dart
flutter analyze lib/ui/studio_workbench/view_models/workbench_transfer_viewmodel.dart lib/main.dart
```

Expected: test PASS and analyzer reports no new errors.

- [ ] **Step 6: Commit when possible**

```powershell
git add lib/main.dart lib/ui/studio_workbench/view_models/workbench_transfer_viewmodel.dart test/ui/studio_workbench/workbench_transfer_viewmodel_test.dart
git commit -m "feat: add workbench transfer view model"
```

If this directory still has no `.git`, record the changed files in the implementation summary instead of committing.

## Task 5: Put Transfer Actions on the Workbench Surface

**Files:**

- Create: `lib/ui/studio_workbench/widgets/workbench_transfer_actions.dart`
- Modify: `lib/ui/generation_page/widgets/generation_page_view.dart`
- Modify: `assets/l10n/en.json`
- Modify: `assets/l10n/zh-CN.json`
- Test: `test/ui/studio_workbench/workbench_transfer_actions_test.dart`

- [ ] **Step 1: Write the failing toolbar widget test**

Create `test/ui/studio_workbench/workbench_transfer_actions_test.dart`:

```dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/models/param_config.dart';
import 'package:nai_casrand/data/models/payload_config.dart';
import 'package:nai_casrand/data/models/prompt_config.dart';
import 'package:nai_casrand/data/models/settings.dart';
import 'package:nai_casrand/data/studio/services/workbench_transfer_service.dart';
import 'package:nai_casrand/ui/studio_workbench/view_models/workbench_transfer_viewmodel.dart';
import 'package:nai_casrand/ui/studio_workbench/widgets/workbench_transfer_actions.dart';

const _sharedPreferencesChannel = MethodChannel(
  'plugins.flutter.io/shared_preferences',
);

class _WorkbenchAssetLoader extends AssetLoader {
  const _WorkbenchAssetLoader();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async {
    return {
      'workbench_import': 'Import workbench',
      'workbench_export': 'Export workbench',
    };
  }
}

PayloadConfig _payload() {
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
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_sharedPreferencesChannel, (call) async {
      if (call.method == 'getAll') return <String, Object>{};
      return true;
    });
    await EasyLocalization.ensureInitialized();
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_sharedPreferencesChannel, null);
  });

  testWidgets('workbench transfer actions expose import and export buttons',
      (tester) async {
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en')],
        path: 'assets/l10n',
        assetLoader: const _WorkbenchAssetLoader(),
        fallbackLocale: const Locale('en'),
        startLocale: const Locale('en'),
        saveLocale: false,
        child: MaterialApp(
          home: Scaffold(
            body: WorkbenchTransferActions(
              viewModel: WorkbenchTransferViewModel(
                payloadConfig: _payload(),
                transferService: WorkbenchTransferService(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('workbench-import-action')), findsOneWidget);
    expect(find.byKey(const ValueKey('workbench-export-action')), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run the toolbar test to verify it fails**

Run:

```powershell
flutter test test/ui/studio_workbench/workbench_transfer_actions_test.dart
```

Expected: FAIL because `WorkbenchTransferActions` does not exist.

- [ ] **Step 3: Add localization strings**

Add to `assets/l10n/en.json`:

```json
"workbench_import": "Import workbench",
"workbench_export": "Export workbench",
"workbench_import_succeeded": "Workbench restored",
"workbench_import_failed": "Workbench import failed"
```

Add to `assets/l10n/zh-CN.json`:

```json
"workbench_import": "导入工作台",
"workbench_export": "导出工作台",
"workbench_import_succeeded": "工作台已恢复",
"workbench_import_failed": "工作台导入失败"
```

- [ ] **Step 4: Add icon-only transfer actions**

Create `lib/ui/studio_workbench/widgets/workbench_transfer_actions.dart`:

```dart
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:nai_casrand/ui/studio_workbench/view_models/workbench_transfer_viewmodel.dart';

class WorkbenchTransferActions extends StatelessWidget {
  final WorkbenchTransferViewModel viewModel;

  const WorkbenchTransferActions({
    super.key,
    required this.viewModel,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          key: const ValueKey('workbench-import-action'),
          tooltip: tr('workbench_import'),
          onPressed: () => viewModel.importFromFile(context),
          icon: const Icon(Icons.file_open_outlined),
        ),
        IconButton(
          key: const ValueKey('workbench-export-action'),
          tooltip: tr('workbench_export'),
          onPressed: viewModel.exportToFile,
          icon: const Icon(Icons.save_alt_outlined),
        ),
      ],
    );
  }
}
```

- [ ] **Step 5: Mount the actions on the current generation/workbench surface**

Add imports to `lib/ui/generation_page/widgets/generation_page_view.dart`:

```dart
import 'package:get_it/get_it.dart';
import 'package:nai_casrand/ui/studio_workbench/view_models/workbench_transfer_viewmodel.dart';
import 'package:nai_casrand/ui/studio_workbench/widgets/workbench_transfer_actions.dart';
```

Wrap the existing `content` body in a top-aligned toolbar:

```dart
    return Scaffold(
      body: PlayfulGeometricBackground(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: WorkbenchTransferActions(
                  viewModel: GetIt.I<WorkbenchTransferViewModel>(),
                ),
              ),
            ),
            Expanded(child: content),
          ],
        ),
      ),
      floatingActionButton: buttons,
    );
```

- [ ] **Step 6: Run the toolbar test and affected generation tests**

Run:

```powershell
flutter test test/ui/studio_workbench/workbench_transfer_actions_test.dart test/ui/generation_page
```

Expected: PASS.

- [ ] **Step 7: Commit when possible**

```powershell
git add assets/l10n/en.json assets/l10n/zh-CN.json lib/ui/generation_page/widgets/generation_page_view.dart lib/ui/studio_workbench/widgets/workbench_transfer_actions.dart test/ui/studio_workbench/workbench_transfer_actions_test.dart
git commit -m "feat: expose workbench transfer actions"
```

If this directory still has no `.git`, record the changed files in the implementation summary instead of committing.

## Task 6: Remove Settings-Level Transfer Actions

**Files:**

- Modify: `lib/ui/settings_page/widgets/settings_page_view.dart`
- Modify: `test/ui/settings_page/settings_page_view_widget_test.dart`

- [ ] **Step 1: Add a failing Settings widget expectation**

Extend the asset loader in `test/ui/settings_page/settings_page_view_widget_test.dart` with:

```dart
'import_settings_from_file': 'Import settings from file',
'export_settings_to_file': 'Export settings to file',
```

Add this test:

```dart
  testWidgets('settings page does not expose workbench file exchange', (
    tester,
  ) async {
    await _pumpLocalizedSettingsPage(tester);

    expect(find.text('Import settings from file'), findsNothing);
    expect(find.text('Export settings to file'), findsNothing);
  });
```

- [ ] **Step 2: Run the Settings widget test to verify it fails**

Run:

```powershell
flutter test test/ui/settings_page/settings_page_view_widget_test.dart
```

Expected: FAIL because Settings still renders import/export action buttons.

- [ ] **Step 3: Remove Settings header transfer actions**

In `_buildSettingsHeader` within `lib/ui/settings_page/widgets/settings_page_view.dart`, replace the `Wrap` that contains `_buildSettingsActionButton` calls with the title row only:

```dart
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: PlayfulGeometricDecorations.sticker(
              color: PlayfulGeometricColors.accent,
              borderRadius:
                  BorderRadius.circular(PlayfulGeometricRadius.full),
              shadowOffset: Offset.zero,
            ),
            child: const Icon(
              Icons.settings,
              color: PlayfulGeometricColors.accentForeground,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            context.tr('settings'),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
        ],
      ),
```

Delete `_buildSettingsActionButton` because no Settings action uses it after this change.

- [ ] **Step 4: Run Settings tests**

Run:

```powershell
flutter test test/ui/settings_page/settings_page_view_widget_test.dart test/ui/settings_page/settings_page_viewmodel_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit when possible**

```powershell
git add lib/ui/settings_page/widgets/settings_page_view.dart test/ui/settings_page/settings_page_view_widget_test.dart
git commit -m "refactor: move file exchange out of settings"
```

If this directory still has no `.git`, record the changed files in the implementation summary instead of committing.

## Task 7: Verification and Review Gate

**Files:**

- Review if needed: `docs/novel-studio-integrated-prd.md`
- Review if needed: `docs/superpowers/plans/2026-05-22-novel-studio-integration-roadmap.md`

- [ ] **Step 1: Run the targeted studio and affected UI tests**

```powershell
flutter test test/data/studio test/ui/studio_workbench test/ui/generation_page test/ui/settings_page
```

Expected: all tests PASS.

- [ ] **Step 2: Run existing workspace foundation tests**

```powershell
flutter test test/data/workspace test/ui/workspace_health
```

Expected: all tests PASS. These tests protect the internal data primitive used by `StudioDataService`.

- [ ] **Step 3: Run analyzer**

```powershell
flutter analyze
```

Expected: no new analyzer errors.

- [ ] **Step 4: Inspect the public UI terms**

```powershell
rg -n "Workspace|工作区|Health|三源导入" lib/ui assets/l10n
```

Expected: no new user-facing workbench-transfer strings expose internal data storage or source migration. Existing internal diagnostic references should be reviewed before keeping them in any visible route.

- [ ] **Step 5: Record the result**

Run:

```powershell
git status --short
```

Expected in a git checkout: only files from this plan are staged or changed.

Expected in `C:\Users\admin\Downloads\NAI_NEW` if it still has no `.git`: Git reports that the directory is not a repository; list changed files in the implementation summary instead.

## Self-Review

Spec coverage:

- Internal data concepts stay hidden: Task 1 plus Task 7 term scan.
- User-facing exchange moves to the workbench: Tasks 2-6.
- Local secrets are excluded from exports: Task 2 tests.
- Legacy CasRand config JSON remains restorable through the new path: Task 3 tests.
- Existing generation and Settings flows stay regression-covered: Tasks 5-7.

Placeholder scan:

- Placeholder and vague-step scan completed with no plan blockers found.

Type consistency:

- `StudioDataService`, `WorkbenchDocument`, `WorkbenchTransferService`, and `WorkbenchTransferViewModel` names match across file paths, tests, registration, and widgets.
- `WorkbenchDocument` is the only transfer envelope type; the service is the only JSON compatibility boundary.
