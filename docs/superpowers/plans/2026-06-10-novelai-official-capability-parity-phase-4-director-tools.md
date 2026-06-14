# NovelAI Official Capability Parity Phase 4 Director Tools Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a tested Director Tools foundation so gallery images can be sent to NovelAI augment-image operations and saved back with lineage.

**Architecture:** Keep Director Tools separate from normal generate-image settings. Add typed request models and a small API request builder for `ai/augment-image`, then add a one-shot gallery operation method that reads the source image, sends the operation, saves the returned image, and records lineage through `StudioGalleryService.saveOperationSnapshot`.

**Tech Stack:** Flutter, Dart, existing `ApiRequest`/`ApiService`, `ImageService.processResponse`, `StudioGalleryService`, `image_size_getter`, Beads, `flutter test`, `dart analyze`.

---

## Source Context

- Parent design: `docs/superpowers/specs/2026-06-09-novelai-official-capability-parity-design.md`
- Phase 3 plan: `docs/superpowers/plans/2026-06-10-novelai-official-capability-parity-phase-3.md`
- Official docs checked on 2026-06-10: https://docs.novelai.net/en/image/directortools/
- API contract evidence checked on 2026-06-10: NovelAI docs list Remove BG, Line Art, Sketch, Colorize, Emotion, and Declutter; public API references show `POST https://image.novelai.net/ai/augment-image` with payload fields `image`, `width`, `height`, `req_type`, and optional `prompt`/`defry` for Colorize and Emotion.

## File Structure

- Create `lib/data/studio/models/studio_director_tool.dart`
  - Owns `StudioDirectorTool`, request type mapping, options, and JSON-friendly parameter serialization.
- Create `lib/data/studio/services/studio_director_tool_service.dart`
  - Owns validation and `ApiRequest` construction for `ai/augment-image`.
- Modify `lib/ui/generation_page/view_models/generation_page_viewmodel.dart`
  - Adds `runDirectorToolGalleryRecord` for one-shot gallery operation execution.
- Test `test/data/studio/services/studio_director_tool_service_test.dart`
  - Covers req_type mapping, optional Colorize/Emotion fields, endpoint, headers, proxy, and validation.
- Extend `test/ui/generation_page/view_models/generation_page_viewmodel_test.dart`
  - Covers executing a Director Tool from a gallery record and saving lineage.

## Task 1: Director Tool Request Model And API Builder

**Files:**
- Create: `lib/data/studio/models/studio_director_tool.dart`
- Create: `lib/data/studio/services/studio_director_tool_service.dart`
- Test: `test/data/studio/services/studio_director_tool_service_test.dart`

- [ ] **Step 1: Write the failing request-builder test**

Create `test/data/studio/services/studio_director_tool_service_test.dart` with:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/models/settings.dart';
import 'package:nai_casrand/data/studio/models/studio_director_tool.dart';
import 'package:nai_casrand/data/studio/services/studio_director_tool_service.dart';

void main() {
  group('StudioDirectorToolService', () {
    test('builds augment-image requests for basic Director Tools', () {
      final settings = Settings.fromJson(const {})
        ..apiKey = 'pst-token'
        ..proxy = '127.0.0.1:7890';
      final request = const StudioDirectorToolService().buildRequest(
        settings: settings,
        sourceImageB64: 'source-image',
        sourceWidth: 832,
        sourceHeight: 1216,
        options: const StudioDirectorToolOptions(
          tool: StudioDirectorTool.lineArt,
        ),
      );

      expect(request.endpoint, 'https://image.novelai.net/ai/augment-image');
      expect(request.proxy, '127.0.0.1:7890');
      expect(request.headers['authorization'], 'Bearer pst-token');
      expect(request.payload, {
        'image': 'source-image',
        'width': 832,
        'height': 1216,
        'req_type': 'lineart',
      });
    });

    test('builds colorize requests with prompt and defry', () {
      final request = const StudioDirectorToolService().buildRequest(
        settings: Settings.fromJson(const {'apiKey': 'pst-token'}),
        sourceImageB64: 'source-image',
        sourceWidth: 512,
        sourceHeight: 512,
        options: const StudioDirectorToolOptions(
          tool: StudioDirectorTool.colorize,
          prompt: 'red hair, blue eyes',
          defry: 2,
        ),
      );

      expect(request.payload['req_type'], 'colorize');
      expect(request.payload['prompt'], 'red hair, blue eyes');
      expect(request.payload['defry'], 2);
    });
  });
}
```

- [ ] **Step 2: Run the test to verify RED**

Run:

```powershell
flutter test test/data/studio/services/studio_director_tool_service_test.dart -r expanded
```

Expected: compile failure because the model and service do not exist.

- [ ] **Step 3: Implement the model**

Create `lib/data/studio/models/studio_director_tool.dart`:

```dart
enum StudioDirectorTool {
  removeBackground,
  lineArt,
  sketch,
  colorize,
  emotion,
  declutter,
}

extension StudioDirectorToolRequestType on StudioDirectorTool {
  String get requestType => switch (this) {
        StudioDirectorTool.removeBackground => 'bg-removal',
        StudioDirectorTool.lineArt => 'lineart',
        StudioDirectorTool.sketch => 'sketch',
        StudioDirectorTool.colorize => 'colorize',
        StudioDirectorTool.emotion => 'emotion',
        StudioDirectorTool.declutter => 'declutter',
      };
}

class StudioDirectorToolOptions {
  final StudioDirectorTool tool;
  final String prompt;
  final int defry;

  const StudioDirectorToolOptions({
    required this.tool,
    this.prompt = '',
    this.defry = 0,
  });

  Map<String, dynamic> toLineageParameters({
    required int sourceWidth,
    required int sourceHeight,
  }) {
    return {
      'tool': tool.name,
      'req_type': tool.requestType,
      'source_width': sourceWidth,
      'source_height': sourceHeight,
      if (prompt.trim().isNotEmpty) 'prompt': prompt.trim(),
      if (tool == StudioDirectorTool.colorize ||
          tool == StudioDirectorTool.emotion)
        'defry': defry.clamp(0, 5),
    };
  }
}
```

- [ ] **Step 4: Implement the service**

Create `lib/data/studio/services/studio_director_tool_service.dart`:

```dart
import 'package:nai_casrand/data/models/api_request.dart';
import 'package:nai_casrand/data/models/settings.dart';
import 'package:nai_casrand/data/studio/models/studio_director_tool.dart';

class StudioDirectorToolService {
  static const augmentImageEndpoint =
      'https://image.novelai.net/ai/augment-image';

  const StudioDirectorToolService();

  ApiRequest buildRequest({
    required Settings settings,
    required String sourceImageB64,
    required int sourceWidth,
    required int sourceHeight,
    required StudioDirectorToolOptions options,
  }) {
    if (sourceImageB64.trim().isEmpty) {
      throw StateError('Director Tool source image is missing.');
    }
    if (sourceWidth <= 0 || sourceHeight <= 0) {
      throw StateError('Director Tool source image dimensions are missing.');
    }
    final payload = <String, dynamic>{
      'image': sourceImageB64,
      'width': sourceWidth,
      'height': sourceHeight,
      'req_type': options.tool.requestType,
    };
    if (options.tool == StudioDirectorTool.colorize ||
        options.tool == StudioDirectorTool.emotion) {
      payload['defry'] = options.defry.clamp(0, 5);
      payload['prompt'] = options.prompt.trim();
    }
    return ApiRequest(
      endpoint: augmentImageEndpoint,
      proxy: settings.proxy,
      headers: settings.getHeaders(),
      payload: payload,
      timeout: const Duration(seconds: 60),
      logLabel: 'studio-director-tool',
    );
  }
}
```

- [ ] **Step 5: Run the service tests to verify GREEN**

Run:

```powershell
flutter test test/data/studio/services/studio_director_tool_service_test.dart -r expanded
```

Expected: all tests pass.

## Task 2: Director Tool Gallery Execution

**Files:**
- Modify: `lib/ui/generation_page/view_models/generation_page_viewmodel.dart`
- Test: `test/ui/generation_page/view_models/generation_page_viewmodel_test.dart`

- [ ] **Step 1: Write the failing viewmodel execution test**

Extend `test/ui/generation_page/view_models/generation_page_viewmodel_test.dart`:

```dart
test('runDirectorToolGalleryRecord sends augment request and saves lineage',
    () async {
  final payloadConfig = GetIt.I<PayloadConfig>();
  payloadConfig.settings.outputFolderPath = r'C:\outputs';
  final sourcePath = _writePngFixture('director-source.png', width: 2, height: 3);
  final galleryService = _FakeGalleryService();
  GetIt.I.registerSingleton<StudioGalleryService>(galleryService);
  final viewmodel = _TestGenerationPageViewmodel(
    responses: [
      ApiResponse(status: '200', data: Uint8List.fromList([1, 2, 3])),
    ],
  );

  await viewmodel.runDirectorToolGalleryRecord(
    _galleryRecord(id: 'source-record', imagePath: sourcePath),
    const StudioDirectorToolOptions(
      tool: StudioDirectorTool.colorize,
      prompt: 'red hair',
      defry: 3,
    ),
  );

  expect(viewmodel.requestEndpoints.single,
      'https://image.novelai.net/ai/augment-image');
  expect(viewmodel.requestPayloads.single['req_type'], 'colorize');
  expect(viewmodel.requestPayloads.single['prompt'], 'red hair');
  expect(galleryService.lastOperation, StudioGalleryOperation.directorTool);
  expect(galleryService.lastSourceRecordId, 'source-record');
  expect(galleryService.lastOperationParameters?['tool'], 'colorize');
  expect(galleryService.lastOperationParameters?['source_width'], 2);
  expect(galleryService.lastOperationParameters?['source_height'], 3);
});
```

- [ ] **Step 2: Run the test to verify RED**

Run:

```powershell
flutter test test/ui/generation_page/view_models/generation_page_viewmodel_test.dart --plain-name "runDirectorToolGalleryRecord sends augment request and saves lineage" -r expanded
```

Expected: compile failure because `runDirectorToolGalleryRecord` does not exist.

- [ ] **Step 3: Implement minimal execution**

Add imports for `studio_director_tool.dart` and `studio_director_tool_service.dart`, then add `runDirectorToolGalleryRecord` near existing gallery operation methods. The method should reuse `_readGallerySourceImage`, build the request with `StudioDirectorToolService`, call `fetchData`, verify 2xx status, process the zip/binary response through `processResponse`, save the image, and call `saveOperationSnapshot` with `StudioGalleryOperation.directorTool` plus `options.toLineageParameters(...)`.

- [ ] **Step 4: Run the viewmodel test to verify GREEN**

Run:

```powershell
flutter test test/ui/generation_page/view_models/generation_page_viewmodel_test.dart --plain-name "runDirectorToolGalleryRecord sends augment request and saves lineage" -r expanded
```

Expected: PASS.

## Task 3: Phase 4 Verification

**Files:**
- Analyze the files from Tasks 1 and 2.
- Run focused tests from Tasks 1 and 2 plus existing Phase 3 image operation tests.

- [ ] **Step 1: Format check**

Run:

```powershell
dart format --output=none --set-exit-if-changed lib/data/studio/models/studio_director_tool.dart lib/data/studio/services/studio_director_tool_service.dart lib/ui/generation_page/view_models/generation_page_viewmodel.dart test/data/studio/services/studio_director_tool_service_test.dart test/ui/generation_page/view_models/generation_page_viewmodel_test.dart
```

Expected: exit code 0.

- [ ] **Step 2: Analyze**

Run:

```powershell
dart analyze lib/data/studio/models/studio_director_tool.dart lib/data/studio/services/studio_director_tool_service.dart lib/ui/generation_page/view_models/generation_page_viewmodel.dart test/data/studio/services/studio_director_tool_service_test.dart test/ui/generation_page/view_models/generation_page_viewmodel_test.dart
```

Expected: no issues found.

- [ ] **Step 3: Focused tests**

Run:

```powershell
flutter test test/data/studio/services/studio_director_tool_service_test.dart test/ui/generation_page/view_models/generation_page_viewmodel_test.dart --plain-name "runDirectorToolGalleryRecord sends augment request and saves lineage" -r expanded
```

Expected: service tests and the focused viewmodel test pass.

## Beads Mapping

- `NAI_NEW-kfle.12`: Add Director Tool typed request model and augment-image request builder.
- `NAI_NEW-kfle.13`: Execute Director Tools from gallery records and save lineage.
- `NAI_NEW-kfle.14`: Verify Phase 4 Director Tool foundation.

## Self-Review

- Spec coverage: This plan covers Phase 4's typed request model and gallery result record foundation for all six official Director Tools. A richer UI panel and multi-variant Remove BG selection remain a later Phase 4 slice after the API adapter is stable.
- Placeholder scan: No TBD/TODO placeholders remain. Deferred UI/multi-variant behavior is explicitly scoped out of this foundation slice.
- Type consistency: `StudioDirectorTool`, `StudioDirectorToolOptions`, `StudioDirectorToolService`, and `runDirectorToolGalleryRecord` are named consistently across tasks.
