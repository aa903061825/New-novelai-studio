# NovelAI Official Capability Parity Phase 3 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete the Phase 3 creation loop so saved/generated gallery images can be reused as I2I sources, restored with lineage, enhanced through prompt-aware diffusion, and validated for dedicated upscale.

**Architecture:** Keep gallery records as the durable result index, add typed lineage metadata beside existing `additionalInfo`, and route image operations through small services that reuse the current `PayloadConfig`, `GeneratePayloadUseCase`, `ApiService`, and `StudioGalleryService` boundaries. Enhance is implemented as a prompt-aware image-to-image operation using the existing generate-image request path; Upscale is modeled and validated independently because official docs state it is a non-prompt action and current code has no verified dedicated API adapter yet.

**Tech Stack:** Flutter, Dart, existing `PayloadConfig`/`WorkbenchDocument`/`StudioGalleryRecord`, `image_size_getter`, Beads, `flutter test`, `dart analyze`.

---

## Source Context

Design spec: `docs/superpowers/specs/2026-06-09-novelai-official-capability-parity-design.md`

Parent issue: `NAI_NEW-kfle`

Already completed:

- Phase 0/1: capability contract, I2I persistence, I2I payload emission, workbench I2I controls.
- Phase 2: model-aware `qualityToggle` and `ucPreset`.
- Phase 3 first slice: `StudioGalleryService.useRecordAsI2iSource` plus card/detail/preview UI actions.

Official docs checked on 2026-06-10:

- Enhance is prompt-aware diffusion over an existing image, with Magnitude or individual Strength/Noise controls.
- Dedicated Upscale enlarges the source image four times, has no prompt influence, and official docs state ordinary source images are limited to 1024x1024 pixels.

## File Structure

- Modify `lib/data/studio/models/studio_gallery_record.dart`
  - Add `StudioGalleryLineage`, `StudioGalleryOperation`, JSON parsing, and optional `lineage` field.
  - Keep old records compatible when `lineage` is absent.
- Modify `lib/data/studio/services/studio_gallery_service.dart`
  - Preserve `useRecordAsI2iSource`.
  - Add `saveOperationSnapshot` for operation results with lineage.
- Create `lib/data/studio/services/studio_image_operation_service.dart`
  - Provide `validateUpscaleSource`, `buildEnhancePayload`, and operation-result helpers.
  - Keep request-building pure where possible so service tests can run without a real NovelAI call.
- Modify `lib/ui/studio_shell/widgets/studio_gallery_page.dart`
  - Surface lineage in detail/preview metadata.
  - Add guarded Enhance/Upscale action entry points after the service model exists.
- Modify `lib/ui/generation_page/view_models/generation_page_viewmodel.dart`
  - Add callable methods for one-shot operation execution only after service tests lock request shape.
- Test `test/data/studio/studio_gallery_service_test.dart`
  - Extend gallery persistence tests with lineage round-trip and operation snapshot behavior.
- Create `test/data/studio/services/studio_image_operation_service_test.dart`
  - Cover upscale validation and enhance request construction.
- Extend `test/ui/studio_shell/studio_gallery_page_test.dart`
  - Add widget coverage once current unrelated `PromptTagAutoTranslationQueue` pending timer is fixed or isolated.

## Task 1: Gallery Lineage Model

**Files:**
- Modify: `lib/data/studio/models/studio_gallery_record.dart`
- Test: `test/data/studio/studio_gallery_service_test.dart`

- [ ] **Step 1: Write failing lineage round-trip test**

Add this test to `test/data/studio/studio_gallery_service_test.dart`:

```dart
test('gallery lineage round trips through saved records', () async {
  final service = StudioGalleryService(workspaceService: workspaceService);
  final record = await service.saveSnapshot(
    config: _payload(prompt: 'enhanced prompt', apiKey: 'pst', proxy: ''),
    title: 'enhanced.png',
    imagePath: r'C:\outputs\enhanced.png',
    info: 'enhanced prompt',
    id: 'record-enhanced',
    createdAt: DateTime.parse('2026-06-10T08:00:00Z'),
    lineage: const StudioGalleryLineage(
      operation: StudioGalleryOperation.enhance,
      sourceRecordId: 'record-source',
      sourceImagePath: r'C:\outputs\source.png',
      parameters: {'strength': 0.35, 'noise': 0.12},
    ),
  );

  final reopened = await StudioGalleryService(
    workspaceService: workspaceService,
  ).loadRecords();

  expect(record.lineage?.operation, StudioGalleryOperation.enhance);
  expect(reopened.single.lineage?.sourceRecordId, 'record-source');
  expect(reopened.single.lineage?.parameters['strength'], 0.35);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```powershell
flutter test test/data/studio/studio_gallery_service_test.dart --plain-name "gallery lineage round trips through saved records" -r expanded
```

Expected: compile failure because `StudioGalleryLineage`, `StudioGalleryOperation`, and `lineage` parameters do not exist yet.

- [ ] **Step 3: Implement lineage types and JSON**

Add to `lib/data/studio/models/studio_gallery_record.dart`:

```dart
enum StudioGalleryOperation {
  generate,
  imageToImage,
  enhance,
  upscale,
  inpaint,
  directorTool,
}

class StudioGalleryLineage {
  final StudioGalleryOperation operation;
  final String? sourceRecordId;
  final String? sourceImagePath;
  final Map<String, dynamic> parameters;

  const StudioGalleryLineage({
    required this.operation,
    this.sourceRecordId,
    this.sourceImagePath,
    this.parameters = const {},
  });

  factory StudioGalleryLineage.fromJson(Map<String, dynamic> json) {
    return StudioGalleryLineage(
      operation: _galleryOperationFromJson(json['operation']),
      sourceRecordId: json['sourceRecordId'] as String?,
      sourceImagePath: json['sourceImagePath'] as String?,
      parameters: _dynamicMap(json['parameters']),
    );
  }

  static StudioGalleryLineage? fromJsonOrNull(Object? value) {
    if (value == null) return null;
    if (value is! Map) {
      throw const FormatException('Gallery lineage must be an object.');
    }
    return StudioGalleryLineage.fromJson(value.cast<String, dynamic>());
  }

  Map<String, dynamic> toJson() => {
        'operation': operation.name,
        if (sourceRecordId != null) 'sourceRecordId': sourceRecordId,
        if (sourceImagePath != null) 'sourceImagePath': sourceImagePath,
        if (parameters.isNotEmpty) 'parameters': parameters,
      };
}
```

Then add `final StudioGalleryLineage? lineage;` to `StudioGalleryRecord`, parse it from `json['lineage'] ?? additionalInfo['lineage']`, emit it from `toJson`, and thread it through `fromPayloadConfig`, `_resolveLegacyImagePath`, and constructors.

- [ ] **Step 4: Run test to verify it passes**

Run:

```powershell
flutter test test/data/studio/studio_gallery_service_test.dart --plain-name "gallery lineage round trips through saved records" -r expanded
```

Expected: PASS.

## Task 2: Operation Snapshot Persistence

**Files:**
- Modify: `lib/data/studio/services/studio_gallery_service.dart`
- Test: `test/data/studio/studio_gallery_service_test.dart`

- [ ] **Step 1: Write failing operation snapshot test**

Add:

```dart
test('saveOperationSnapshot stores result after the source record', () async {
  final service = StudioGalleryService(workspaceService: workspaceService);
  await service.saveSnapshot(
    config: _payload(prompt: 'source prompt', apiKey: 'pst', proxy: ''),
    title: 'source.png',
    imagePath: r'C:\outputs\source.png',
    info: 'source prompt',
    id: 'source-record',
    createdAt: DateTime.parse('2026-06-10T08:00:00Z'),
  );

  await service.saveOperationSnapshot(
    config: _payload(prompt: 'enhanced prompt', apiKey: 'pst', proxy: ''),
    sourceRecordId: 'source-record',
    operation: StudioGalleryOperation.enhance,
    title: 'enhanced.png',
    imagePath: r'C:\outputs\enhanced.png',
    info: 'enhanced prompt',
    parameters: {'strength': 0.35},
    id: 'enhanced-record',
    createdAt: DateTime.parse('2026-06-10T08:01:00Z'),
  );

  final records = await service.loadRecords();
  expect(records.map((record) => record.id), [
    'enhanced-record',
    'source-record',
  ]);
  expect(records.first.lineage?.operation, StudioGalleryOperation.enhance);
  expect(records.first.lineage?.sourceRecordId, 'source-record');
});
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```powershell
flutter test test/data/studio/studio_gallery_service_test.dart --plain-name "saveOperationSnapshot stores result after the source record" -r expanded
```

Expected: compile failure because `saveOperationSnapshot` does not exist.

- [ ] **Step 3: Implement `saveOperationSnapshot`**

Add a method to `StudioGalleryService` that creates a `StudioGalleryLineage`, calls `StudioGalleryRecord.fromPayloadConfig`, prepends the record, and persists with `saveRecords`.

- [ ] **Step 4: Run test to verify it passes**

Run:

```powershell
flutter test test/data/studio/studio_gallery_service_test.dart --plain-name "saveOperationSnapshot stores result after the source record" -r expanded
```

Expected: PASS.

## Task 3: Image Operation Request Service

**Files:**
- Create: `lib/data/studio/services/studio_image_operation_service.dart`
- Test: `test/data/studio/services/studio_image_operation_service_test.dart`

- [ ] **Step 1: Write failing upscale validation tests**

Create `test/data/studio/services/studio_image_operation_service_test.dart` with tests that call:

```dart
final service = StudioImageOperationService();
expect(service.validateUpscaleSource(width: 1024, height: 1024).isValid, isTrue);
expect(service.validateUpscaleSource(width: 1025, height: 768).isValid, isFalse);
expect(service.validateUpscaleSource(width: 768, height: 1025).isValid, isFalse);
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```powershell
flutter test test/data/studio/services/studio_image_operation_service_test.dart -r expanded
```

Expected: compile failure because the service does not exist.

- [ ] **Step 3: Implement validation model and service shell**

Create `StudioImageOperationValidationResult` and `StudioImageOperationService.validateUpscaleSource` with a `max(width, height) <= 1024` rule.

- [ ] **Step 4: Add failing enhance payload test**

Extend the same test file with a `buildEnhancePayload` test that verifies:

- action is `img2img`
- `parameters.image` is copied from the source image base64
- `parameters.strength` and `parameters.noise` are clamped
- prompt input comes from current workbench payload generation

- [ ] **Step 5: Implement minimal enhance payload builder**

Use a clone or temporary copy of `PayloadConfig`, set `i2iConfig.imageB64`, `strength`, and `noise`, then call `GeneratePayloadUseCase`.

- [ ] **Step 6: Run service tests**

Run:

```powershell
flutter test test/data/studio/services/studio_image_operation_service_test.dart -r expanded
```

Expected: all tests pass.

## Task 4: Gallery UI Lineage Display

**Files:**
- Modify: `lib/ui/studio_shell/widgets/studio_gallery_page.dart`
- Test: `test/ui/studio_shell/studio_gallery_page_test.dart`

- [ ] **Step 1: Add widget test after pending timer blocker is gone**

Add a test record with `lineage.operation == StudioGalleryOperation.enhance` and assert detail drawer shows operation/source metadata.

- [ ] **Step 2: Implement display**

Add small `_DetailBlock` rows for lineage operation, source image path, source record id, and lineage parameters.

- [ ] **Step 3: Run widget test**

Run:

```powershell
flutter test test/ui/studio_shell/studio_gallery_page_test.dart --plain-name "gallery detail shows operation lineage" -r expanded
```

Expected: PASS after the unrelated `PromptTagAutoTranslationQueue` timer issue is fixed or isolated.

## Task 5: Enhance/Upscale Action Execution

**Files:**
- Modify: `lib/ui/generation_page/view_models/generation_page_viewmodel.dart`
- Modify: `lib/ui/studio_shell/widgets/studio_gallery_page.dart`
- Test: `test/ui/generation_page/view_models/generation_page_viewmodel_test.dart`

- [ ] **Step 1: Add failing viewmodel test for Enhance**

Write a test that calls a new `runEnhanceGalleryRecord` method with a fake source record, fake API response, and fake gallery service, then asserts request payload action is `img2img` and gallery save includes enhance lineage.

- [ ] **Step 2: Implement minimal Enhance execution**

Read the source image, build enhance payload via `StudioImageOperationService`, call `fetchData`, `processResponse`, save file, and call `saveOperationSnapshot`.

- [ ] **Step 3: Add failing viewmodel test for Upscale validation**

Write a test that passes a 1025-pixel source size and asserts no API request is sent and an error result is produced.

- [ ] **Step 4: Implement minimal Upscale guard**

Wire `validateUpscaleSource` before any API call. Defer real dedicated upscale API call until an authenticated smoke test confirms the endpoint contract.

- [ ] **Step 5: Run focused tests and analyze**

Run:

```powershell
flutter test test/data/studio/studio_gallery_service_test.dart test/data/studio/services/studio_image_operation_service_test.dart test/ui/generation_page/view_models/generation_page_viewmodel_test.dart -r expanded
dart analyze lib/data/studio/models/studio_gallery_record.dart lib/data/studio/services/studio_gallery_service.dart lib/data/studio/services/studio_image_operation_service.dart lib/ui/generation_page/view_models/generation_page_viewmodel.dart lib/ui/studio_shell/widgets/studio_gallery_page.dart
```

Expected: focused tests pass and analyzer reports no issues.

## Beads Mapping

- `NAI_NEW-kfle.7`: Add gallery lineage model and persistence.
- `NAI_NEW-kfle.8`: Add image operation request service for Enhance/Upscale validation.
- `NAI_NEW-kfle.9`: Add gallery lineage display and operation action UI.
- `NAI_NEW-kfle.10`: Add Enhance execution and guarded Upscale entry point.
- `NAI_NEW-kfle.11`: Phase 3 verification pass and follow-up notes.

## Self-Review

- Spec coverage: This plan covers Phase 3 result reuse, Enhance/Upscale groundwork, and lineage. It intentionally does not cover Director Tools, Canvas/Inpaint, or Prompt Productivity; those remain Phase 4-6 plans.
- Placeholder scan: No step uses TBD/TODO language. The only deferred item is explicitly scoped to authenticated dedicated Upscale API confirmation.
- Type consistency: `StudioGalleryLineage`, `StudioGalleryOperation`, `StudioImageOperationService`, and `saveOperationSnapshot` names are used consistently across tasks.
