# Script AI Recognition Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Script Recast AI recognition pipeline: normalized multi-role batches, OpenAI-compatible JSON recognition, application-wide cache, incremental suggestions, and role-level preview/confirmation.

**Architecture:** Add a separate AI suggestion layer beside the existing local `RoleAssembly` model. Local services build normalized recognition batches and cache keys, a cache service supplies reusable global suggestions, an OpenAI-compatible client handles network recognition, and `StudioScriptViewModel` coordinates cache hits, queue state, AI misses, confirmation, rejection, and retry. UI changes surface the suggestion state without letting unconfirmed AI output write to final prompts or long-term knowledge.

**Tech Stack:** Flutter/Dart, existing `http`/`ApiService` networking, `path_provider` + JSON file persistence for the app-global cache, `flutter_test`, existing Script Recast models and ViewModel.

**Project Note:** Beads project memory says stealth mode/no git ops. Do not run `git commit`; use Beads notes and normal test evidence instead.

---

## File Structure

- Modify: `lib/data/models/settings.dart`
  - Add `scriptAiModel` persistence.
- Modify: `lib/ui/settings_page/view_models/settings_page_viewmodel.dart`
  - Add setter for `scriptAiModel`.
- Modify: `lib/ui/settings_page/widgets/settings_page_view.dart`
  - Add model field to the Script AI card only.
- Create: `lib/data/studio/models/script_ai_recognition.dart`
  - Domain models for batches, role inputs, suggestions, cache entries, statuses, JSON parsing.
- Create: `lib/data/studio/services/script_ai_normalizer.dart`
  - Weight-insensitive prompt normalization and cache-key helpers.
- Create: `lib/data/studio/services/script_ai_batch_builder.dart`
  - Build slotted multi-role batches and pure prompt inline batches from `Script`.
- Create: `lib/data/studio/services/script_ai_cache_service.dart`
  - Load/save app-global recognition cache and select best entries.
- Create: `lib/data/studio/services/script_ai_client.dart`
  - `ScriptAiClient` interface and OpenAI-compatible implementation.
- Create: `lib/data/studio/services/script_ai_recognition_service.dart`
  - Orchestrates cache hits, AI misses, JSON parsing, needs-review/failed states.
- Modify: `lib/data/studio/models/script_recast_knowledge.dart`
  - Persist current script AI suggestion state in `RecastScriptCache`.
- Modify: `lib/ui/studio_script/view_models/studio_script_viewmodel.dart`
  - Add AI analysis methods, queue state, confirmation/rejection/retry APIs, and mapping application.
- Modify: `lib/ui/studio_script/widgets/studio_script_page.dart`
  - Add top-level AI actions and suggestion state controls/cards.
- Tests:
  - `test/data/models/settings_batch_interval_jitter_test.dart`
  - `test/ui/settings_page/settings_page_viewmodel_test.dart`
  - `test/ui/settings_page/settings_page_view_widget_test.dart`
  - `test/data/studio/services/script_ai_normalizer_test.dart`
  - `test/data/studio/services/script_ai_batch_builder_test.dart`
  - `test/data/studio/services/script_ai_cache_service_test.dart`
  - `test/data/studio/services/script_ai_client_test.dart`
  - `test/data/studio/services/script_ai_recognition_service_test.dart`
  - `test/data/studio/models/script_recast_knowledge_test.dart`
  - `test/ui/studio_script/studio_script_page_test.dart`

---

### Task 1: Script AI Model Setting

**Files:**
- Modify: `lib/data/models/settings.dart`
- Modify: `lib/ui/settings_page/view_models/settings_page_viewmodel.dart`
- Modify: `lib/ui/settings_page/widgets/settings_page_view.dart`
- Test: `test/data/models/settings_batch_interval_jitter_test.dart`
- Test: `test/ui/settings_page/settings_page_viewmodel_test.dart`
- Test: `test/ui/settings_page/settings_page_view_widget_test.dart`

- [ ] **Step 1: Write the failing settings model test**

Add to `test/data/models/settings_batch_interval_jitter_test.dart`:

```dart
test('settings persists script ai model', () {
  final settings = Settings.fromJson({
    'script_ai_base_url': 'https://script.example/v1',
    'script_ai_token': 'script-token',
    'script_ai_model': 'gpt-4.1-mini',
  });

  final json = settings.toJson();

  expect(settings.scriptAiModel, 'gpt-4.1-mini');
  expect(json['script_ai_model'], 'gpt-4.1-mini');
});
```

- [ ] **Step 2: Run the settings model test to verify it fails**

Run:

```powershell
flutter test test\data\models\settings_batch_interval_jitter_test.dart --plain-name "settings persists script ai model"
```

Expected: FAIL with an error that `scriptAiModel` is not defined or `script_ai_model` is missing.

- [ ] **Step 3: Implement the settings field**

In `lib/data/models/settings.dart`, add the field near the existing Script AI fields:

```dart
String scriptAiModel;
```

Update the constructor:

```dart
this.scriptAiModel = '',
```

Update `fromJson`:

```dart
scriptAiModel: json['script_ai_model'] ?? '',
```

Update `toJson`:

```dart
'script_ai_model': scriptAiModel,
```

- [ ] **Step 4: Verify the model test passes**

Run:

```powershell
flutter test test\data\models\settings_batch_interval_jitter_test.dart --plain-name "settings persists script ai model"
```

Expected: PASS.

- [ ] **Step 5: Write the failing settings ViewModel test**

Extend `test/ui/settings_page/settings_page_viewmodel_test.dart` in the existing script AI settings test:

```dart
viewmodel.setScriptAiModel('gpt-4.1-mini');
expect(viewmodel.settings.scriptAiModel, 'gpt-4.1-mini');
```

- [ ] **Step 6: Run the ViewModel test to verify it fails**

Run:

```powershell
flutter test test\ui\settings_page\settings_page_viewmodel_test.dart --plain-name "sets script and translation ai settings"
```

Expected: FAIL because `setScriptAiModel` is missing.

- [ ] **Step 7: Implement the ViewModel setter**

In `lib/ui/settings_page/view_models/settings_page_viewmodel.dart`, add:

```dart
void setScriptAiModel(String value) {
  payloadConfig.settings.scriptAiModel = value.trim();
  notifyListeners();
}
```

- [ ] **Step 8: Write the failing widget test**

Extend `test/ui/settings_page/settings_page_view_widget_test.dart` in `settings page exposes script and translation ai credentials`:

```dart
expect(find.byKey(const ValueKey('settings-script-ai-model')), findsOneWidget);
```

- [ ] **Step 9: Run the widget test to verify it fails**

Run:

```powershell
flutter test test\ui\settings_page\settings_page_view_widget_test.dart --plain-name "settings page exposes script and translation ai credentials"
```

Expected: FAIL because the model text field is not rendered.

- [ ] **Step 10: Add the Script AI model field to the settings UI**

In `lib/ui/settings_page/widgets/settings_page_view.dart`, update `_buildAiCredentialCard` to accept optional model props:

```dart
Key? modelKey,
String? modelValue,
ValueChanged<String>? onModelChanged,
```

After the base URL field and before the token field, render only when supplied:

```dart
if (modelKey != null && modelValue != null && onModelChanged != null) ...[
  const SizedBox(height: 10),
  TextFormField(
    key: modelKey,
    initialValue: modelValue,
    decoration: const InputDecoration(
      labelText: '模型',
      border: OutlineInputBorder(),
      isDense: true,
    ),
    onChanged: onModelChanged,
  ),
],
```

Pass these only for `剧本 AI`:

```dart
modelKey: const ValueKey('settings-script-ai-model'),
modelValue: viewmodel.settings.scriptAiModel,
onModelChanged: viewmodel.setScriptAiModel,
```

- [ ] **Step 11: Run Task 1 tests**

Run:

```powershell
flutter test test\data\models\settings_batch_interval_jitter_test.dart test\ui\settings_page\settings_page_viewmodel_test.dart test\ui\settings_page\settings_page_view_widget_test.dart
```

Expected: PASS.

---

### Task 2: Recognition Domain Models

**Files:**
- Create: `lib/data/studio/models/script_ai_recognition.dart`
- Test: `test/data/studio/models/script_ai_recognition_test.dart`

- [ ] **Step 1: Write the failing model round-trip test**

Create `test/data/studio/models/script_ai_recognition_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/studio/models/script_ai_recognition.dart';
import 'package:nai_casrand/data/studio/models/script_recast.dart';

void main() {
  test('round trips ai recognition batch and suggestion', () {
    const batch = ScriptAiRecognitionBatch(
      id: 'scene-batch-001',
      sourceKind: ScriptAiSourceKind.slotted,
      frameIndexes: [1, 2],
      roles: [
        ScriptAiRecognitionRoleInput(
          sourceRoleId: 'slot-0',
          displayLabel: '角色 1',
          rawCaptions: ['alice_(series), 2::torn armor::'],
          normalizedKey: 'alice series|armor',
          roleIdentityKey: 'alice series',
          partKey: 'armor',
          localSummary: 'alice_(series), torn armor',
          evidenceTags: ['alice_(series)', 'torn armor'],
          cacheKey: 'role:alice series|part:armor',
        ),
      ],
      normalizedBatchKey: 'scene-batch-key',
    );
    const suggestion = ScriptAiSuggestion(
      id: 'sug-1',
      batchId: 'scene-batch-001',
      sourceRoleId: 'slot-0',
      cacheKey: 'role:alice series|part:armor',
      source: ScriptAiSuggestionSource.ai,
      status: ScriptAiSuggestionStatus.suggested,
      confidence: 0.86,
      displayName: 'alice_(series)',
      importance: 'protagonist',
      parts: RecastPromptParts(
        identity: 'alice_(series), blue eyes',
        upperClothing: 'torn armor',
      ),
      stageLabel: 'battle armor',
      targetCharacterHint: 'alice',
      targetUpperOutfitHint: 'armor',
      evidence: ['alice_(series)', 'torn armor'],
      warnings: ['low lower-body evidence'],
    );

    final restoredBatch = ScriptAiRecognitionBatch.fromJson(batch.toJson());
    final restoredSuggestion =
        ScriptAiSuggestion.fromJson(suggestion.toJson());

    expect(restoredBatch.roles.single.sourceRoleId, 'slot-0');
    expect(restoredBatch.sourceKind, ScriptAiSourceKind.slotted);
    expect(restoredSuggestion.parts.identity, contains('alice'));
    expect(restoredSuggestion.source, ScriptAiSuggestionSource.ai);
    expect(restoredSuggestion.status, ScriptAiSuggestionStatus.suggested);
  });

  test('cache entry chooses confirmed state and omits workspace asset ids', () {
    final entry = ScriptAiGlobalCacheEntry(
      cacheKey: 'role:alice series|part:armor',
      schemaVersion: 1,
      promptSchemaVersion: 1,
      model: 'gpt-4.1-mini',
      sourceKind: ScriptAiSourceKind.slotted,
      normalizedRoleIdentity: 'alice series',
      normalizedPartKey: 'armor',
      suggestion: const ScriptAiSuggestion(
        id: 'sug-1',
        batchId: 'batch',
        cacheKey: 'role:alice series|part:armor',
        source: ScriptAiSuggestionSource.cache,
        status: ScriptAiSuggestionStatus.suggested,
        displayName: 'alice_(series)',
        targetCharacterHint: 'alice',
      ),
      status: ScriptAiCacheEntryStatus.confirmed,
      createdAt: DateTime.utc(2026, 5, 30),
      updatedAt: DateTime.utc(2026, 5, 30),
    );

    final json = entry.toJson().toString();

    expect(json, contains('alice'));
    expect(json, isNot(contains('targetCharacterId')));
    expect(ScriptAiGlobalCacheEntry.fromJson(entry.toJson()).status,
        ScriptAiCacheEntryStatus.confirmed);
  });
}
```

- [ ] **Step 2: Run the model tests to verify they fail**

Run:

```powershell
flutter test test\data\studio\models\script_ai_recognition_test.dart
```

Expected: FAIL because `script_ai_recognition.dart` does not exist.

- [ ] **Step 3: Implement the model file**

Create `lib/data/studio/models/script_ai_recognition.dart` with:

```dart
import 'package:nai_casrand/data/studio/models/script_recast.dart';

enum ScriptAiSourceKind { slotted, inlinePrompt }
enum ScriptAiSuggestionSource { local, ai, cache, needsReview, failed }
enum ScriptAiSuggestionStatus { pending, suggested, needsReview, failed, confirmed, rejected }
enum ScriptAiCacheEntryStatus { suggested, confirmed, rejected }

class ScriptAiRecognitionBatch {
  final String id;
  final ScriptAiSourceKind sourceKind;
  final List<int> frameIndexes;
  final List<ScriptAiRecognitionRoleInput> roles;
  final String rawPrompt;
  final String normalizedPrompt;
  final String normalizedBatchKey;

  const ScriptAiRecognitionBatch({
    required this.id,
    required this.sourceKind,
    this.frameIndexes = const [],
    this.roles = const [],
    this.rawPrompt = '',
    this.normalizedPrompt = '',
    required this.normalizedBatchKey,
  });

  factory ScriptAiRecognitionBatch.fromJson(Map<String, dynamic> json) {
    return ScriptAiRecognitionBatch(
      id: json['id'] as String? ?? '',
      sourceKind: _enumByName(
        ScriptAiSourceKind.values,
        json['sourceKind'] as String? ?? ScriptAiSourceKind.slotted.name,
      ),
      frameIndexes: _intList(json['frameIndexes']),
      roles: _mapList(json['roles'])
          .map(ScriptAiRecognitionRoleInput.fromJson)
          .toList(growable: false),
      rawPrompt: json['rawPrompt'] as String? ?? '',
      normalizedPrompt: json['normalizedPrompt'] as String? ?? '',
      normalizedBatchKey: json['normalizedBatchKey'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'sourceKind': sourceKind.name,
        if (frameIndexes.isNotEmpty) 'frameIndexes': frameIndexes,
        if (roles.isNotEmpty)
          'roles': roles.map((role) => role.toJson()).toList(),
        if (rawPrompt.trim().isNotEmpty) 'rawPrompt': rawPrompt,
        if (normalizedPrompt.trim().isNotEmpty)
          'normalizedPrompt': normalizedPrompt,
        'normalizedBatchKey': normalizedBatchKey,
      };
}

class ScriptAiRecognitionRoleInput {
  final String sourceRoleId;
  final String displayLabel;
  final List<String> rawCaptions;
  final String normalizedKey;
  final String roleIdentityKey;
  final String partKey;
  final String localSummary;
  final List<String> evidenceTags;
  final String cacheKey;

  const ScriptAiRecognitionRoleInput({
    required this.sourceRoleId,
    required this.displayLabel,
    this.rawCaptions = const [],
    required this.normalizedKey,
    required this.roleIdentityKey,
    required this.partKey,
    required this.localSummary,
    this.evidenceTags = const [],
    required this.cacheKey,
  });

  factory ScriptAiRecognitionRoleInput.fromJson(Map<String, dynamic> json) {
    return ScriptAiRecognitionRoleInput(
      sourceRoleId: json['sourceRoleId'] as String? ?? '',
      displayLabel: json['displayLabel'] as String? ?? '',
      rawCaptions: _stringList(json['rawCaptions']),
      normalizedKey: json['normalizedKey'] as String? ?? '',
      roleIdentityKey: json['roleIdentityKey'] as String? ?? '',
      partKey: json['partKey'] as String? ?? '',
      localSummary: json['localSummary'] as String? ?? '',
      evidenceTags: _stringList(json['evidenceTags']),
      cacheKey: json['cacheKey'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'sourceRoleId': sourceRoleId,
        'displayLabel': displayLabel,
        if (rawCaptions.isNotEmpty) 'rawCaptions': rawCaptions,
        'normalizedKey': normalizedKey,
        'roleIdentityKey': roleIdentityKey,
        'partKey': partKey,
        'localSummary': localSummary,
        if (evidenceTags.isNotEmpty) 'evidenceTags': evidenceTags,
        'cacheKey': cacheKey,
      };
}

class ScriptAiSuggestion {
  final String id;
  final String batchId;
  final String? sourceRoleId;
  final String cacheKey;
  final ScriptAiSuggestionSource source;
  final ScriptAiSuggestionStatus status;
  final double confidence;
  final String displayName;
  final String importance;
  final RecastPromptParts parts;
  final String stageLabel;
  final String targetCharacterHint;
  final String targetUpperOutfitHint;
  final String targetLowerOutfitHint;
  final String targetArtistChainHint;
  final List<String> evidence;
  final List<String> warnings;
  final String rawResponse;

  const ScriptAiSuggestion({
    required this.id,
    required this.batchId,
    this.sourceRoleId,
    required this.cacheKey,
    this.source = ScriptAiSuggestionSource.local,
    this.status = ScriptAiSuggestionStatus.pending,
    this.confidence = 0,
    this.displayName = '',
    this.importance = '',
    this.parts = const RecastPromptParts(),
    this.stageLabel = '',
    this.targetCharacterHint = '',
    this.targetUpperOutfitHint = '',
    this.targetLowerOutfitHint = '',
    this.targetArtistChainHint = '',
    this.evidence = const [],
    this.warnings = const [],
    this.rawResponse = '',
  });

  factory ScriptAiSuggestion.fromJson(Map<String, dynamic> json) {
    return ScriptAiSuggestion(
      id: json['id'] as String? ?? '',
      batchId: json['batchId'] as String? ?? '',
      sourceRoleId: json['sourceRoleId'] as String?,
      cacheKey: json['cacheKey'] as String? ?? '',
      source: _enumByName(
        ScriptAiSuggestionSource.values,
        json['source'] as String? ?? ScriptAiSuggestionSource.local.name,
      ),
      status: _enumByName(
        ScriptAiSuggestionStatus.values,
        json['status'] as String? ?? ScriptAiSuggestionStatus.pending.name,
      ),
      confidence: ((json['confidence'] ?? 0) as num).toDouble(),
      displayName: json['displayName'] as String? ?? '',
      importance: json['importance'] as String? ?? '',
      parts: json['parts'] == null
          ? const RecastPromptParts()
          : RecastPromptParts.fromJson((json['parts'] as Map).cast()),
      stageLabel: json['stageLabel'] as String? ?? '',
      targetCharacterHint: json['targetCharacterHint'] as String? ?? '',
      targetUpperOutfitHint: json['targetUpperOutfitHint'] as String? ?? '',
      targetLowerOutfitHint: json['targetLowerOutfitHint'] as String? ?? '',
      targetArtistChainHint: json['targetArtistChainHint'] as String? ?? '',
      evidence: _stringList(json['evidence']),
      warnings: _stringList(json['warnings']),
      rawResponse: json['rawResponse'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'batchId': batchId,
        if (sourceRoleId != null) 'sourceRoleId': sourceRoleId,
        'cacheKey': cacheKey,
        'source': source.name,
        'status': status.name,
        if (confidence > 0) 'confidence': confidence,
        if (displayName.trim().isNotEmpty) 'displayName': displayName,
        if (importance.trim().isNotEmpty) 'importance': importance,
        if (!parts.isEmpty) 'parts': parts.toJson(),
        if (stageLabel.trim().isNotEmpty) 'stageLabel': stageLabel,
        if (targetCharacterHint.trim().isNotEmpty)
          'targetCharacterHint': targetCharacterHint,
        if (targetUpperOutfitHint.trim().isNotEmpty)
          'targetUpperOutfitHint': targetUpperOutfitHint,
        if (targetLowerOutfitHint.trim().isNotEmpty)
          'targetLowerOutfitHint': targetLowerOutfitHint,
        if (targetArtistChainHint.trim().isNotEmpty)
          'targetArtistChainHint': targetArtistChainHint,
        if (evidence.isNotEmpty) 'evidence': evidence,
        if (warnings.isNotEmpty) 'warnings': warnings,
        if (rawResponse.trim().isNotEmpty) 'rawResponse': rawResponse,
      };
}

class ScriptAiGlobalCacheEntry {
  final String cacheKey;
  final int schemaVersion;
  final int promptSchemaVersion;
  final String model;
  final ScriptAiSourceKind sourceKind;
  final String normalizedRoleIdentity;
  final String normalizedPartKey;
  final ScriptAiSuggestion suggestion;
  final ScriptAiCacheEntryStatus status;
  final int negativeFeedbackCount;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? confirmedAt;
  final DateTime? rejectedAt;

  const ScriptAiGlobalCacheEntry({
    required this.cacheKey,
    required this.schemaVersion,
    required this.promptSchemaVersion,
    required this.model,
    required this.sourceKind,
    required this.normalizedRoleIdentity,
    required this.normalizedPartKey,
    required this.suggestion,
    required this.status,
    this.negativeFeedbackCount = 0,
    required this.createdAt,
    required this.updatedAt,
    this.confirmedAt,
    this.rejectedAt,
  });

  factory ScriptAiGlobalCacheEntry.fromJson(Map<String, dynamic> json) {
    return ScriptAiGlobalCacheEntry(
      cacheKey: json['cacheKey'] as String? ?? '',
      schemaVersion: json['schemaVersion'] as int? ?? 1,
      promptSchemaVersion: json['promptSchemaVersion'] as int? ?? 1,
      model: json['model'] as String? ?? '',
      sourceKind: _enumByName(
        ScriptAiSourceKind.values,
        json['sourceKind'] as String? ?? ScriptAiSourceKind.slotted.name,
      ),
      normalizedRoleIdentity: json['normalizedRoleIdentity'] as String? ?? '',
      normalizedPartKey: json['normalizedPartKey'] as String? ?? '',
      suggestion: ScriptAiSuggestion.fromJson(
        (json['suggestion'] as Map? ?? const {}).cast<String, dynamic>(),
      ),
      status: _enumByName(
        ScriptAiCacheEntryStatus.values,
        json['status'] as String? ?? ScriptAiCacheEntryStatus.suggested.name,
      ),
      negativeFeedbackCount: json['negativeFeedbackCount'] as int? ?? 0,
      createdAt: DateTime.parse(json['createdAt'] as String).toUtc(),
      updatedAt: DateTime.parse(json['updatedAt'] as String).toUtc(),
      confirmedAt: _dateTimeOrNull(json['confirmedAt']),
      rejectedAt: _dateTimeOrNull(json['rejectedAt']),
    );
  }

  Map<String, dynamic> toJson() => {
        'cacheKey': cacheKey,
        'schemaVersion': schemaVersion,
        'promptSchemaVersion': promptSchemaVersion,
        'model': model,
        'sourceKind': sourceKind.name,
        'normalizedRoleIdentity': normalizedRoleIdentity,
        'normalizedPartKey': normalizedPartKey,
        'suggestion': suggestion.toJson(),
        'status': status.name,
        if (negativeFeedbackCount > 0)
          'negativeFeedbackCount': negativeFeedbackCount,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        if (confirmedAt != null)
          'confirmedAt': confirmedAt!.toUtc().toIso8601String(),
        if (rejectedAt != null)
          'rejectedAt': rejectedAt!.toUtc().toIso8601String(),
      };
}

List<Map<String, dynamic>> _mapList(Object? value) {
  if (value is! List) return const [];
  return value.whereType<Map>().map((item) => item.cast<String, dynamic>()).toList();
}

List<String> _stringList(Object? value) {
  if (value is! List) return const [];
  return value.whereType<String>().toList(growable: false);
}

List<int> _intList(Object? value) {
  if (value is! List) return const [];
  return value.whereType<num>().map((value) => value.toInt()).toList();
}

T _enumByName<T extends Enum>(List<T> values, String name) {
  return values.firstWhere((value) => value.name == name);
}

DateTime? _dateTimeOrNull(Object? value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString())?.toUtc();
}
```

- [ ] **Step 4: Run model tests**

Run:

```powershell
dart format lib\data\studio\models\script_ai_recognition.dart test\data\studio\models\script_ai_recognition_test.dart
flutter test test\data\studio\models\script_ai_recognition_test.dart
```

Expected: PASS.

---

### Task 3: Normalization and Batch Builder

**Files:**
- Create: `lib/data/studio/services/script_ai_normalizer.dart`
- Create: `lib/data/studio/services/script_ai_batch_builder.dart`
- Test: `test/data/studio/services/script_ai_normalizer_test.dart`
- Test: `test/data/studio/services/script_ai_batch_builder_test.dart`

- [ ] **Step 1: Write failing normalizer tests**

Create `test/data/studio/services/script_ai_normalizer_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/studio/services/script_ai_normalizer.dart';

void main() {
  test('normalization ignores weights and wrapper brackets', () {
    const normalizer = ScriptAiNormalizer();

    expect(
      normalizer.normalizePromptKey('2::Torn_Armor::, {black thighhighs}'),
      normalizer.normalizePromptKey('torn armor, black_thighhighs'),
    );
  });

  test('cache keys combine role identity and part keys', () {
    const normalizer = ScriptAiNormalizer();

    expect(
      normalizer.slottedCacheKey(
        roleIdentity: 'Alice_(Series)',
        partText: '2::Torn armor::, black thighhighs',
      ),
      'role:alice series|part:black thighhighs,torn armor',
    );
  });

  test('pure prompt cache key uses normalized full prompt', () {
    const normalizer = ScriptAiNormalizer();

    expect(
      normalizer.inlinePromptCacheKey('{artist:x}, Alice_(Series)'),
      'prompt:alice series,artist x',
    );
  });
}
```

- [ ] **Step 2: Run normalizer tests to verify they fail**

Run:

```powershell
flutter test test\data\studio\services\script_ai_normalizer_test.dart
```

Expected: FAIL because `ScriptAiNormalizer` is missing.

- [ ] **Step 3: Implement the normalizer**

Create `lib/data/studio/services/script_ai_normalizer.dart`:

```dart
import 'package:nai_casrand/data/studio/tools/prompt_tag_processor.dart';

class ScriptAiNormalizer {
  const ScriptAiNormalizer();

  String normalizePromptKey(String text) {
    final parts = PromptTagProcessor.splitWorkshopTags(text)
        .map(PromptTagProcessor.normalizeMatchKey)
        .map((tag) => tag.replaceAll(RegExp(r'[^a-z0-9 ]+'), ' '))
        .map((tag) => tag.replaceAll(RegExp(r'\s+'), ' ').trim())
        .where((tag) => tag.isNotEmpty)
        .toList(growable: false)
      ..sort();
    return parts.join(',');
  }

  String slottedCacheKey({
    required String roleIdentity,
    required String partText,
  }) {
    return 'role:${normalizePromptKey(roleIdentity)}|part:${normalizePromptKey(partText)}';
  }

  String inlinePromptCacheKey(String prompt) {
    return 'prompt:${normalizePromptKey(prompt)}';
  }
}
```

- [ ] **Step 4: Run normalizer tests**

Run:

```powershell
dart format lib\data\studio\services\script_ai_normalizer.dart test\data\studio\services\script_ai_normalizer_test.dart
flutter test test\data\studio\services\script_ai_normalizer_test.dart
```

Expected: PASS.

- [ ] **Step 5: Write failing batch builder tests**

Create `test/data/studio/services/script_ai_batch_builder_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/studio/models/script_ai_recognition.dart';
import 'package:nai_casrand/data/studio/models/script_recast.dart';
import 'package:nai_casrand/data/studio/services/script_ai_batch_builder.dart';

void main() {
  test('builds one multi-role slotted batch for roles in the same frames', () {
    final script = Script(
      id: 'script',
      name: 'script',
      rootPath: '',
      detectedSchema: ScriptSchema.v4Slotted,
      frames: [
        _frame(1, [
          'alice_(series), torn armor, black thighhighs',
          'bob_(series), school uniform, black pants',
        ]),
        _frame(2, [
          'alice_(series), torn armor, black thighhighs',
          'bob_(series), school uniform, black pants',
        ]),
      ],
    );

    final batches = const ScriptAiBatchBuilder().buildBatches(script);

    expect(batches, hasLength(1));
    expect(batches.single.sourceKind, ScriptAiSourceKind.slotted);
    expect(batches.single.roles.map((role) => role.sourceRoleId), [
      'slot-0',
      'slot-1',
    ]);
    expect(batches.single.roles.first.cacheKey,
        'role:alice series|part:black thighhighs,torn armor');
  });

  test('builds pure prompt batch when no role slots exist', () {
    final script = Script(
      id: 'inline',
      name: 'inline',
      rootPath: '',
      detectedSchema: ScriptSchema.baseInline,
      frames: [
        _frame(1, const [], baseCaption: 'artist:x, alice_(series), rooftop'),
      ],
    );

    final batches = const ScriptAiBatchBuilder().buildBatches(script);

    expect(batches, hasLength(1));
    expect(batches.single.sourceKind, ScriptAiSourceKind.inlinePrompt);
    expect(batches.single.rawPrompt, contains('alice'));
    expect(batches.single.roles, isEmpty);
    expect(batches.single.normalizedBatchKey, startsWith('prompt:'));
  });
}

ScriptFrame _frame(
  int index,
  List<String> charCaptions, {
  String baseCaption = 'artist:test',
}) {
  return ScriptFrame(
    index: index,
    fileName: 'nai_$index.json',
    sourcePath: '',
    rawJson: '{}',
    parsed: ParsedFrame(
      baseCaption: baseCaption,
      charCaptions: charCaptions,
    ),
    detectedSchema:
        charCaptions.isEmpty ? ScriptSchema.baseInline : ScriptSchema.v4Slotted,
    parseStatus: ScriptFrameParseStatus.parsed,
  );
}
```

- [ ] **Step 6: Run batch builder tests to verify they fail**

Run:

```powershell
flutter test test\data\studio\services\script_ai_batch_builder_test.dart
```

Expected: FAIL because `ScriptAiBatchBuilder` is missing.

- [ ] **Step 7: Implement the batch builder**

Create `lib/data/studio/services/script_ai_batch_builder.dart`:

```dart
import 'package:nai_casrand/data/studio/models/script_ai_recognition.dart';
import 'package:nai_casrand/data/studio/models/script_recast.dart';
import 'package:nai_casrand/data/studio/services/script_ai_normalizer.dart';
import 'package:nai_casrand/data/studio/services/script_recast_role_tag_heuristics.dart';

class ScriptAiBatchBuilder {
  final ScriptAiNormalizer normalizer;

  const ScriptAiBatchBuilder({
    this.normalizer = const ScriptAiNormalizer(),
  });

  List<ScriptAiRecognitionBatch> buildBatches(Script script) {
    final frames = script.frames
        .where((frame) => frame.parseStatus == ScriptFrameParseStatus.parsed)
        .toList(growable: false);
    if (frames.isEmpty) return const [];
    final hasSlots = frames.any((frame) => frame.parsed.charCaptions.isNotEmpty);
    return hasSlots ? [_slottedBatch(frames)] : [_inlineBatch(frames)];
  }

  ScriptAiRecognitionBatch _slottedBatch(List<ScriptFrame> frames) {
    final maxSlots = frames.fold<int>(
      0,
      (count, frame) => frame.parsed.charCaptions.length > count
          ? frame.parsed.charCaptions.length
          : count,
    );
    final roles = <ScriptAiRecognitionRoleInput>[];
    for (var slotIndex = 0; slotIndex < maxSlots && roles.length < 4; slotIndex += 1) {
      final captions = [
        for (final frame in frames)
          if (slotIndex < frame.parsed.charCaptions.length)
            frame.parsed.charCaptions[slotIndex],
      ];
      if (captions.isEmpty) continue;
      final firstTags = ScriptRecastRoleTagHeuristics.splitTags(captions.first);
      final identity = ScriptRecastRoleTagHeuristics.roleNameForTags(
        firstTags,
        slotIndex,
      );
      final evidence = [
        for (final caption in captions)
          ...ScriptRecastRoleTagHeuristics.outfitEvidenceTags(
            ScriptRecastRoleTagHeuristics.splitTags(caption),
          ),
      ];
      final partText = evidence.isEmpty ? captions.join(', ') : evidence.join(', ');
      roles.add(
        ScriptAiRecognitionRoleInput(
          sourceRoleId: 'slot-$slotIndex',
          displayLabel: '角色 ${slotIndex + 1}',
          rawCaptions: captions,
          normalizedKey: normalizer.normalizePromptKey('$identity, $partText'),
          roleIdentityKey: normalizer.normalizePromptKey(identity),
          partKey: normalizer.normalizePromptKey(partText),
          localSummary: captions.first,
          evidenceTags: evidence,
          cacheKey: normalizer.slottedCacheKey(
            roleIdentity: identity,
            partText: partText,
          ),
        ),
      );
    }
    return ScriptAiRecognitionBatch(
      id: 'scene-batch-${frames.first.index}',
      sourceKind: ScriptAiSourceKind.slotted,
      frameIndexes: [for (final frame in frames) frame.index],
      roles: List.unmodifiable(roles),
      normalizedBatchKey: roles.map((role) => role.cacheKey).join('|'),
    );
  }

  ScriptAiRecognitionBatch _inlineBatch(List<ScriptFrame> frames) {
    final rawPrompt = frames
        .map((frame) => frame.parsed.baseCaption)
        .where((caption) => caption.trim().isNotEmpty)
        .join('\n');
    return ScriptAiRecognitionBatch(
      id: 'inline-prompt-${frames.first.index}',
      sourceKind: ScriptAiSourceKind.inlinePrompt,
      frameIndexes: [for (final frame in frames) frame.index],
      rawPrompt: rawPrompt,
      normalizedPrompt: normalizer.normalizePromptKey(rawPrompt),
      normalizedBatchKey: normalizer.inlinePromptCacheKey(rawPrompt),
    );
  }
}
```

- [ ] **Step 8: Run Task 3 tests**

Run:

```powershell
dart format lib\data\studio\services\script_ai_normalizer.dart lib\data\studio\services\script_ai_batch_builder.dart test\data\studio\services\script_ai_normalizer_test.dart test\data\studio\services\script_ai_batch_builder_test.dart
flutter test test\data\studio\services\script_ai_normalizer_test.dart test\data\studio\services\script_ai_batch_builder_test.dart
```

Expected: PASS.

---

### Task 4: Global Cache Service

**Files:**
- Create: `lib/data/studio/services/script_ai_cache_service.dart`
- Test: `test/data/studio/services/script_ai_cache_service_test.dart`

- [ ] **Step 1: Write failing cache service tests**

Create `test/data/studio/services/script_ai_cache_service_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/studio/models/script_ai_recognition.dart';
import 'package:nai_casrand/data/studio/services/script_ai_cache_service.dart';

void main() {
  late Directory tempDir;
  late File cacheFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('script-ai-cache-test-');
    cacheFile = File('${tempDir.path}/script_ai_recognition_cache.json');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('selects confirmed entry before newer suggested entry', () async {
    final service = ScriptAiCacheService(file: cacheFile);
    await service.saveEntries([
      _entry(
        cacheKey: 'key',
        status: ScriptAiCacheEntryStatus.suggested,
        updatedAt: DateTime.utc(2026, 5, 31),
        name: 'new suggestion',
      ),
      _entry(
        cacheKey: 'key',
        status: ScriptAiCacheEntryStatus.confirmed,
        updatedAt: DateTime.utc(2026, 5, 30),
        name: 'confirmed',
      ),
    ]);

    final match = await service.bestEntryFor('key');

    expect(match?.suggestion.displayName, 'confirmed');
  });

  test('rejected entries are not auto-filled', () async {
    final service = ScriptAiCacheService(file: cacheFile);
    await service.saveEntries([
      _entry(
        cacheKey: 'key',
        status: ScriptAiCacheEntryStatus.rejected,
        updatedAt: DateTime.utc(2026, 5, 30),
        name: 'bad',
        negativeFeedbackCount: 1,
      ),
    ]);

    expect(await service.bestEntryFor('key'), isNull);
  });
}

ScriptAiGlobalCacheEntry _entry({
  required String cacheKey,
  required ScriptAiCacheEntryStatus status,
  required DateTime updatedAt,
  required String name,
  int negativeFeedbackCount = 0,
}) {
  return ScriptAiGlobalCacheEntry(
    cacheKey: cacheKey,
    schemaVersion: 1,
    promptSchemaVersion: 1,
    model: 'gpt-4.1-mini',
    sourceKind: ScriptAiSourceKind.slotted,
    normalizedRoleIdentity: 'alice',
    normalizedPartKey: 'armor',
    suggestion: ScriptAiSuggestion(
      id: 'sug-$name',
      batchId: 'batch',
      cacheKey: cacheKey,
      source: ScriptAiSuggestionSource.cache,
      status: ScriptAiSuggestionStatus.suggested,
      displayName: name,
    ),
    status: status,
    negativeFeedbackCount: negativeFeedbackCount,
    createdAt: updatedAt,
    updatedAt: updatedAt,
  );
}
```

- [ ] **Step 2: Run cache tests to verify they fail**

Run:

```powershell
flutter test test\data\studio\services\script_ai_cache_service_test.dart
```

Expected: FAIL because `ScriptAiCacheService` is missing.

- [ ] **Step 3: Implement cache service**

Create `lib/data/studio/services/script_ai_cache_service.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:nai_casrand/data/studio/models/script_ai_recognition.dart';
import 'package:path_provider/path_provider.dart';

class ScriptAiCacheService {
  final File? file;

  const ScriptAiCacheService({this.file});

  Future<File> _cacheFile() async {
    final explicit = file;
    if (explicit != null) return explicit;
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/script_ai_recognition_cache.json');
  }

  Future<List<ScriptAiGlobalCacheEntry>> loadEntries() async {
    final target = await _cacheFile();
    if (!await target.exists()) return const [];
    final decoded = jsonDecode(await target.readAsString());
    if (decoded is! Map) return const [];
    final entries = decoded['entries'];
    if (entries is! List) return const [];
    return entries
        .whereType<Map>()
        .map((entry) => ScriptAiGlobalCacheEntry.fromJson(entry.cast()))
        .toList(growable: false);
  }

  Future<void> saveEntries(List<ScriptAiGlobalCacheEntry> entries) async {
    final target = await _cacheFile();
    if (!await target.parent.exists()) {
      await target.parent.create(recursive: true);
    }
    await target.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'schemaVersion': 1,
        'entries': entries.map((entry) => entry.toJson()).toList(),
      }),
    );
  }

  Future<ScriptAiGlobalCacheEntry?> bestEntryFor(String cacheKey) async {
    final matches = [
      for (final entry in await loadEntries())
        if (entry.cacheKey == cacheKey &&
            entry.status != ScriptAiCacheEntryStatus.rejected &&
            entry.negativeFeedbackCount < 1)
          entry,
    ];
    if (matches.isEmpty) return null;
    matches.sort((left, right) {
      final leftConfirmed = left.status == ScriptAiCacheEntryStatus.confirmed;
      final rightConfirmed = right.status == ScriptAiCacheEntryStatus.confirmed;
      if (leftConfirmed != rightConfirmed) return leftConfirmed ? -1 : 1;
      return right.updatedAt.compareTo(left.updatedAt);
    });
    return matches.first;
  }

  Future<void> upsert(ScriptAiGlobalCacheEntry entry) async {
    final entries = [
      for (final existing in await loadEntries())
        if (existing.cacheKey != entry.cacheKey ||
            existing.suggestion.id != entry.suggestion.id)
          existing,
      entry,
    ];
    await saveEntries(entries);
  }
}
```

- [ ] **Step 4: Run cache tests**

Run:

```powershell
dart format lib\data\studio\services\script_ai_cache_service.dart test\data\studio\services\script_ai_cache_service_test.dart
flutter test test\data\studio\services\script_ai_cache_service_test.dart
```

Expected: PASS.

---

### Task 5: OpenAI-Compatible Script AI Client

**Files:**
- Create: `lib/data/studio/services/script_ai_client.dart`
- Test: `test/data/studio/services/script_ai_client_test.dart`

- [ ] **Step 1: Write failing client tests**

Create `test/data/studio/services/script_ai_client_test.dart`:

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/models/api_request.dart';
import 'package:nai_casrand/data/studio/models/script_ai_recognition.dart';
import 'package:nai_casrand/data/studio/services/script_ai_client.dart';

void main() {
  test('openai-compatible client posts chat completions and extracts content',
      () async {
    ApiRequest? captured;
    final client = OpenAiCompatibleScriptAiClient(
      fetchData: (request) async {
        captured = request;
        return ApiResponse(
          status: '200',
          data: Uint8List.fromList(utf8.encode(jsonEncode({
            'choices': [
              {
                'message': {
                  'content': '{"schema_version":1,"items":[]}',
                },
              },
            ],
          }))),
        );
      },
    );

    final result = await client.recognize(
      ScriptAiClientRequest(
        baseUrl: 'https://script.example/v1',
        token: 'secret',
        model: 'gpt-4.1-mini',
        batches: const [
          ScriptAiRecognitionBatch(
            id: 'batch',
            sourceKind: ScriptAiSourceKind.slotted,
            normalizedBatchKey: 'batch-key',
          ),
        ],
      ),
    );

    expect(result.rawJson, '{"schema_version":1,"items":[]}');
    expect(captured?.endpoint, 'https://script.example/v1/chat/completions');
    expect(captured?.headers['Authorization'], 'Bearer secret');
    expect(captured?.payload['model'], 'gpt-4.1-mini');
  });

  test('client throws configuration error for missing model', () async {
    final client = OpenAiCompatibleScriptAiClient(
      fetchData: (_) async => throw StateError('should not call network'),
    );

    expect(
      () => client.recognize(
        const ScriptAiClientRequest(
          baseUrl: 'https://script.example/v1',
          token: 'secret',
          model: '',
          batches: [],
        ),
      ),
      throwsA(isA<ScriptAiClientException>()),
    );
  });
}
```

- [ ] **Step 2: Run client tests to verify they fail**

Run:

```powershell
flutter test test\data\studio\services\script_ai_client_test.dart
```

Expected: FAIL because `ScriptAiClient` is missing.

- [ ] **Step 3: Implement the client**

Create `lib/data/studio/services/script_ai_client.dart`:

```dart
import 'dart:convert';

import 'package:nai_casrand/data/models/api_request.dart';
import 'package:nai_casrand/data/services/api_service.dart';
import 'package:nai_casrand/data/studio/models/script_ai_recognition.dart';

typedef ScriptAiFetchData = Future<ApiResponse> Function(ApiRequest request);

abstract interface class ScriptAiClient {
  Future<ScriptAiClientResult> recognize(ScriptAiClientRequest request);
}

class ScriptAiClientRequest {
  final String baseUrl;
  final String token;
  final String model;
  final List<ScriptAiRecognitionBatch> batches;
  final String proxy;

  const ScriptAiClientRequest({
    required this.baseUrl,
    required this.token,
    required this.model,
    required this.batches,
    this.proxy = '',
  });
}

class ScriptAiClientResult {
  final String rawJson;

  const ScriptAiClientResult({required this.rawJson});
}

class ScriptAiClientException implements Exception {
  final String message;

  const ScriptAiClientException(this.message);

  @override
  String toString() => message;
}

class OpenAiCompatibleScriptAiClient implements ScriptAiClient {
  final ScriptAiFetchData fetchData;

  OpenAiCompatibleScriptAiClient({
    ScriptAiFetchData? fetchData,
    ApiService? apiService,
  }) : fetchData = fetchData ?? (apiService ?? ApiService()).fetchData;

  @override
  Future<ScriptAiClientResult> recognize(ScriptAiClientRequest request) async {
    _validate(request);
    final endpoint = _joinEndpoint(request.baseUrl);
    final response = await fetchData(
      ApiRequest(
        endpoint: endpoint,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${request.token}',
        },
        payload: {
          'model': request.model,
          'messages': [
            {
              'role': 'system',
              'content': _systemPrompt,
            },
            {
              'role': 'user',
              'content': jsonEncode({
                'schema_version': 1,
                'batches': request.batches.map((batch) => batch.toJson()).toList(),
              }),
            },
          ],
          'temperature': 0,
        },
        proxy: request.proxy,
      ),
    );
    final status = int.tryParse(response.status) ?? 0;
    if (status < 200 || status >= 300) {
      throw ScriptAiClientException('Script AI request failed: HTTP $status');
    }
    final decoded = jsonDecode(utf8.decode(response.data));
    final content = (((decoded as Map)['choices'] as List).first
        as Map)['message'] as Map;
    return ScriptAiClientResult(rawJson: content['content'] as String);
  }

  void _validate(ScriptAiClientRequest request) {
    if (request.baseUrl.trim().isEmpty) {
      throw const ScriptAiClientException('Script AI base URL is empty.');
    }
    if (request.token.trim().isEmpty) {
      throw const ScriptAiClientException('Script AI token is empty.');
    }
    if (request.model.trim().isEmpty) {
      throw const ScriptAiClientException('Script AI model is empty.');
    }
  }

  String _joinEndpoint(String baseUrl) {
    final trimmed = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    if (trimmed.endsWith('/v1')) return '$trimmed/chat/completions';
    return '$trimmed/v1/chat/completions';
  }

  static const _systemPrompt =
      'Return strict JSON only. Analyze Script Recast batches into roles. '
      'For slotted batches, return every source_role_id exactly once. '
      'Do not rewrite final prompts; only fill identity, body, clothing, hints, evidence, confidence.';
}
```

- [ ] **Step 4: Run client tests**

Run:

```powershell
dart format lib\data\studio\services\script_ai_client.dart test\data\studio\services\script_ai_client_test.dart
flutter test test\data\studio\services\script_ai_client_test.dart
```

Expected: PASS.

---

### Task 6: Recognition Service and JSON Alignment

**Files:**
- Create: `lib/data/studio/services/script_ai_recognition_service.dart`
- Test: `test/data/studio/services/script_ai_recognition_service_test.dart`

- [ ] **Step 1: Write failing recognition service tests**

Create `test/data/studio/services/script_ai_recognition_service_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/studio/models/script_ai_recognition.dart';
import 'package:nai_casrand/data/studio/services/script_ai_cache_service.dart';
import 'package:nai_casrand/data/studio/services/script_ai_client.dart';
import 'package:nai_casrand/data/studio/services/script_ai_recognition_service.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('script-ai-recognition-');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('uses cache hit without calling ai client', () async {
    final cache = ScriptAiCacheService(
      file: File('${tempDir.path}/cache.json'),
    );
    await cache.saveEntries([
      _cacheEntry('role:alice|part:armor', 'alice cached'),
    ]);
    final service = DefaultScriptAiRecognitionService(
      cacheService: cache,
      client: _FakeClient((_) => throw StateError('network should not run')),
    );

    final result = await service.recognize(
      request: const ScriptAiRecognitionRequest(
        baseUrl: 'https://script.example/v1',
        token: 'token',
        model: 'model',
        batches: [
          ScriptAiRecognitionBatch(
            id: 'batch',
            sourceKind: ScriptAiSourceKind.slotted,
            normalizedBatchKey: 'batch',
            roles: [
              ScriptAiRecognitionRoleInput(
                sourceRoleId: 'slot-0',
                displayLabel: '角色 1',
                normalizedKey: 'alice armor',
                roleIdentityKey: 'alice',
                partKey: 'armor',
                localSummary: 'alice armor',
                cacheKey: 'role:alice|part:armor',
              ),
            ],
          ),
        ],
      ),
    );

    expect(result.suggestions.single.source, ScriptAiSuggestionSource.cache);
    expect(result.suggestions.single.displayName, 'alice cached');
    expect(result.aiRequestCount, 0);
  });

  test('marks slotted source id mismatch as needsReview', () async {
    final cache = ScriptAiCacheService(
      file: File('${tempDir.path}/cache.json'),
    );
    final service = DefaultScriptAiRecognitionService(
      cacheService: cache,
      client: _FakeClient(
        (_) async => const ScriptAiClientResult(
          rawJson:
              '{"schema_version":1,"items":[{"candidate_id":"batch","roles":[{"source_role_id":"slot-x","display_name":"wrong"}]}]}',
        ),
      ),
    );

    final result = await service.recognize(
      request: const ScriptAiRecognitionRequest(
        baseUrl: 'https://script.example/v1',
        token: 'token',
        model: 'model',
        batches: [
          ScriptAiRecognitionBatch(
            id: 'batch',
            sourceKind: ScriptAiSourceKind.slotted,
            normalizedBatchKey: 'batch',
            roles: [
              ScriptAiRecognitionRoleInput(
                sourceRoleId: 'slot-0',
                displayLabel: '角色 1',
                normalizedKey: 'alice armor',
                roleIdentityKey: 'alice',
                partKey: 'armor',
                localSummary: 'alice armor',
                cacheKey: 'role:alice|part:armor',
              ),
            ],
          ),
        ],
      ),
    );

    expect(result.suggestions.single.status, ScriptAiSuggestionStatus.needsReview);
    expect(result.suggestions.single.rawResponse, contains('slot-x'));
  });
}

ScriptAiGlobalCacheEntry _cacheEntry(String cacheKey, String name) {
  return ScriptAiGlobalCacheEntry(
    cacheKey: cacheKey,
    schemaVersion: 1,
    promptSchemaVersion: 1,
    model: 'model',
    sourceKind: ScriptAiSourceKind.slotted,
    normalizedRoleIdentity: 'alice',
    normalizedPartKey: 'armor',
    suggestion: ScriptAiSuggestion(
      id: 'cache-sug',
      batchId: 'batch',
      sourceRoleId: 'slot-0',
      cacheKey: cacheKey,
      source: ScriptAiSuggestionSource.cache,
      status: ScriptAiSuggestionStatus.suggested,
      displayName: name,
    ),
    status: ScriptAiCacheEntryStatus.confirmed,
    createdAt: DateTime.utc(2026, 5, 30),
    updatedAt: DateTime.utc(2026, 5, 30),
  );
}

class _FakeClient implements ScriptAiClient {
  final Future<ScriptAiClientResult> Function(ScriptAiClientRequest request)
      handler;

  const _FakeClient(this.handler);

  @override
  Future<ScriptAiClientResult> recognize(ScriptAiClientRequest request) {
    return handler(request);
  }
}
```

- [ ] **Step 2: Run recognition service tests to verify they fail**

Run:

```powershell
flutter test test\data\studio\services\script_ai_recognition_service_test.dart
```

Expected: FAIL because `ScriptAiRecognitionService` is missing.

- [ ] **Step 3: Implement recognition request/result and service**

Create `lib/data/studio/services/script_ai_recognition_service.dart`:

```dart
import 'dart:convert';

import 'package:nai_casrand/data/studio/models/script_ai_recognition.dart';
import 'package:nai_casrand/data/studio/models/script_recast.dart';
import 'package:nai_casrand/data/studio/services/script_ai_cache_service.dart';
import 'package:nai_casrand/data/studio/services/script_ai_client.dart';

class ScriptAiRecognitionRequest {
  final String baseUrl;
  final String token;
  final String model;
  final String proxy;
  final List<ScriptAiRecognitionBatch> batches;

  const ScriptAiRecognitionRequest({
    required this.baseUrl,
    required this.token,
    required this.model,
    this.proxy = '',
    required this.batches,
  });
}

class ScriptAiRecognitionResult {
  final List<ScriptAiSuggestion> suggestions;
  final int aiRequestCount;

  const ScriptAiRecognitionResult({
    required this.suggestions,
    required this.aiRequestCount,
  });
}

abstract interface class ScriptAiRecognitionService {
  Future<ScriptAiRecognitionResult> recognize({
    required ScriptAiRecognitionRequest request,
  });
}

class DefaultScriptAiRecognitionService implements ScriptAiRecognitionService {
  final ScriptAiCacheService cacheService;
  final ScriptAiClient client;

  const DefaultScriptAiRecognitionService({
    this.cacheService = const ScriptAiCacheService(),
    required this.client,
  });

  @override
  Future<ScriptAiRecognitionResult> recognize({
    required ScriptAiRecognitionRequest request,
  }) async {
    final suggestions = <ScriptAiSuggestion>[];
    final misses = <ScriptAiRecognitionBatch>[];

    for (final batch in request.batches) {
      if (batch.sourceKind == ScriptAiSourceKind.inlinePrompt) {
        final hit = await cacheService.bestEntryFor(batch.normalizedBatchKey);
        if (hit == null) {
          misses.add(batch);
        } else {
          suggestions.add(_fromCache(hit, batch.id, null));
        }
        continue;
      }
      final missingRoles = <ScriptAiRecognitionRoleInput>[];
      for (final role in batch.roles) {
        final hit = await cacheService.bestEntryFor(role.cacheKey);
        if (hit == null) {
          missingRoles.add(role);
        } else {
          suggestions.add(_fromCache(hit, batch.id, role.sourceRoleId));
        }
      }
      if (missingRoles.isNotEmpty) {
        misses.add(
          ScriptAiRecognitionBatch(
            id: batch.id,
            sourceKind: batch.sourceKind,
            frameIndexes: batch.frameIndexes,
            roles: missingRoles,
            rawPrompt: batch.rawPrompt,
            normalizedPrompt: batch.normalizedPrompt,
            normalizedBatchKey: batch.normalizedBatchKey,
          ),
        );
      }
    }

    if (misses.isEmpty) {
      return ScriptAiRecognitionResult(suggestions: suggestions, aiRequestCount: 0);
    }

    try {
      final ai = await client.recognize(
        ScriptAiClientRequest(
          baseUrl: request.baseUrl,
          token: request.token,
          model: request.model,
          proxy: request.proxy,
          batches: misses,
        ),
      );
      suggestions.addAll(_parseAiSuggestions(misses, ai.rawJson));
      return ScriptAiRecognitionResult(suggestions: suggestions, aiRequestCount: 1);
    } catch (error) {
      suggestions.addAll([
        for (final batch in misses)
          ScriptAiSuggestion(
            id: '${batch.id}-failed',
            batchId: batch.id,
            cacheKey: batch.normalizedBatchKey,
            source: ScriptAiSuggestionSource.failed,
            status: ScriptAiSuggestionStatus.failed,
            warnings: [error.toString()],
          ),
      ]);
      return ScriptAiRecognitionResult(suggestions: suggestions, aiRequestCount: 1);
    }
  }

  ScriptAiSuggestion _fromCache(
    ScriptAiGlobalCacheEntry entry,
    String batchId,
    String? sourceRoleId,
  ) {
    final suggestion = entry.suggestion;
    return ScriptAiSuggestion(
      id: suggestion.id,
      batchId: batchId,
      sourceRoleId: sourceRoleId ?? suggestion.sourceRoleId,
      cacheKey: entry.cacheKey,
      source: ScriptAiSuggestionSource.cache,
      status: ScriptAiSuggestionStatus.suggested,
      confidence: suggestion.confidence,
      displayName: suggestion.displayName,
      importance: suggestion.importance,
      parts: suggestion.parts,
      stageLabel: suggestion.stageLabel,
      targetCharacterHint: suggestion.targetCharacterHint,
      targetUpperOutfitHint: suggestion.targetUpperOutfitHint,
      targetLowerOutfitHint: suggestion.targetLowerOutfitHint,
      targetArtistChainHint: suggestion.targetArtistChainHint,
      evidence: suggestion.evidence,
      warnings: suggestion.warnings,
    );
  }

  List<ScriptAiSuggestion> _parseAiSuggestions(
    List<ScriptAiRecognitionBatch> batches,
    String rawJson,
  ) {
    final decoded = jsonDecode(rawJson) as Map<String, dynamic>;
    final items = decoded['items'];
    if (items is! List) {
      return [
        for (final batch in batches) _review(batch, rawJson, 'Missing items list'),
      ];
    }
    final byBatch = {for (final batch in batches) batch.id: batch};
    final result = <ScriptAiSuggestion>[];
    for (final item in items.whereType<Map>()) {
      final map = item.cast<String, dynamic>();
      final batch = byBatch[map['candidate_id']];
      if (batch == null) continue;
      final roles = map['roles'];
      if (roles is! List) {
        result.add(_review(batch, rawJson, 'Missing roles list'));
        continue;
      }
      if (batch.sourceKind == ScriptAiSourceKind.slotted &&
          !_slottedRolesAlign(batch, roles)) {
        result.add(_review(batch, rawJson, 'AI role count or source_role_id mismatch'));
        continue;
      }
      for (final (index, role) in roles.whereType<Map>().indexed) {
        final roleMap = role.cast<String, dynamic>();
        result.add(_suggestionFromRole(batch, roleMap, rawJson, index));
      }
    }
    return result;
  }

  bool _slottedRolesAlign(ScriptAiRecognitionBatch batch, List<dynamic> roles) {
    final expected = batch.roles.map((role) => role.sourceRoleId).toSet();
    final actual = roles
        .whereType<Map>()
        .map((role) => role['source_role_id'])
        .whereType<String>()
        .toSet();
    return expected.length == actual.length && expected.containsAll(actual);
  }

  ScriptAiSuggestion _suggestionFromRole(
    ScriptAiRecognitionBatch batch,
    Map<String, dynamic> role,
    String rawJson,
    int index,
  ) {
    final sourceRoleId = role['source_role_id'] as String?;
    final sourceInput = batch.roles
        .where((input) => input.sourceRoleId == sourceRoleId)
        .firstOrNull;
    final cacheKey = sourceInput?.cacheKey ?? batch.normalizedBatchKey;
    return ScriptAiSuggestion(
      id: '${batch.id}-${sourceRoleId ?? 'inline-$index'}',
      batchId: batch.id,
      sourceRoleId: sourceRoleId ?? 'inline-${batch.id}-$index',
      cacheKey: cacheKey,
      source: ScriptAiSuggestionSource.ai,
      status: ScriptAiSuggestionStatus.suggested,
      confidence: ((role['confidence'] ?? 0) as num).toDouble(),
      displayName: role['display_name'] as String? ?? '',
      importance: role['importance'] as String? ?? '',
      parts: RecastPromptParts(
        identity: role['identity'] as String? ?? '',
        upperBody: role['upper_body'] as String? ?? '',
        lowerBody: role['lower_body'] as String? ?? '',
        upperClothing: role['upper_clothing'] as String? ?? '',
        lowerClothing: role['lower_clothing'] as String? ?? '',
      ),
      stageLabel: role['stage_label'] as String? ?? '',
      targetCharacterHint: role['target_character_hint'] as String? ?? '',
      targetUpperOutfitHint: role['target_upper_outfit_hint'] as String? ?? '',
      targetLowerOutfitHint: role['target_lower_outfit_hint'] as String? ?? '',
      targetArtistChainHint: role['target_artist_chain_hint'] as String? ?? '',
      evidence: _stringList(role['evidence']),
      warnings: _stringList(role['warnings']),
      rawResponse: rawJson,
    );
  }

  ScriptAiSuggestion _review(
    ScriptAiRecognitionBatch batch,
    String rawJson,
    String warning,
  ) {
    return ScriptAiSuggestion(
      id: '${batch.id}-review',
      batchId: batch.id,
      cacheKey: batch.normalizedBatchKey,
      source: ScriptAiSuggestionSource.needsReview,
      status: ScriptAiSuggestionStatus.needsReview,
      warnings: [warning],
      rawResponse: rawJson,
    );
  }
}

List<String> _stringList(Object? value) {
  if (value is! List) return const [];
  return value.whereType<String>().toList(growable: false);
}
```

- [ ] **Step 4: Run recognition service tests**

Run:

```powershell
dart format lib\data\studio\services\script_ai_recognition_service.dart test\data\studio\services\script_ai_recognition_service_test.dart
flutter test test\data\studio\services\script_ai_recognition_service_test.dart
```

Expected: PASS.

---

### Task 7: Persist AI Suggestion State in Script Cache

**Files:**
- Modify: `lib/data/studio/models/script_recast_knowledge.dart`
- Test: `test/data/studio/models/script_recast_knowledge_test.dart`

- [ ] **Step 1: Write failing cache persistence test**

Add to `test/data/studio/models/script_recast_knowledge_test.dart`:

```dart
test('script cache round trips ai recognition suggestions', () {
  final cache = RecastScriptCache(
    scriptId: 'script',
    scriptName: 'Script',
    sourceRootPath: '/script',
    sourceFingerprint: 'fingerprint',
    updatedAt: DateTime.utc(2026, 5, 30),
    roleCandidates: const [],
    mapping: RecastMapping.defaults('script'),
    aiSuggestions: const [
      ScriptAiSuggestion(
        id: 'sug-1',
        batchId: 'batch',
        sourceRoleId: 'slot-0',
        cacheKey: 'role:alice|part:armor',
        source: ScriptAiSuggestionSource.cache,
        status: ScriptAiSuggestionStatus.suggested,
        displayName: 'alice',
      ),
    ],
  );

  final restored = RecastScriptCache.fromJson(cache.toJson());

  expect(restored.aiSuggestions.single.displayName, 'alice');
});
```

Also add:

```dart
import 'package:nai_casrand/data/studio/models/script_ai_recognition.dart';
```

- [ ] **Step 2: Run cache persistence test to verify it fails**

Run:

```powershell
flutter test test\data\studio\models\script_recast_knowledge_test.dart --plain-name "script cache round trips ai recognition suggestions"
```

Expected: FAIL because `aiSuggestions` is missing.

- [ ] **Step 3: Add AI suggestion fields to `RecastScriptCache`**

In `lib/data/studio/models/script_recast_knowledge.dart`, import:

```dart
import 'package:nai_casrand/data/studio/models/script_ai_recognition.dart';
```

Add fields:

```dart
final List<ScriptAiSuggestion> aiSuggestions;
final List<ScriptAiRecognitionBatch> aiFailedBatches;
final List<ScriptAiRecognitionBatch> aiReviewBatches;
```

Constructor defaults:

```dart
this.aiSuggestions = const [],
this.aiFailedBatches = const [],
this.aiReviewBatches = const [],
```

In `fromJson`:

```dart
aiSuggestions: [
  for (final value in json['aiSuggestions'] as List? ?? const [])
    ScriptAiSuggestion.fromJson(Map<String, dynamic>.from(value as Map)),
],
aiFailedBatches: [
  for (final value in json['aiFailedBatches'] as List? ?? const [])
    ScriptAiRecognitionBatch.fromJson(Map<String, dynamic>.from(value as Map)),
],
aiReviewBatches: [
  for (final value in json['aiReviewBatches'] as List? ?? const [])
    ScriptAiRecognitionBatch.fromJson(Map<String, dynamic>.from(value as Map)),
],
```

In `toJson`:

```dart
if (aiSuggestions.isNotEmpty)
  'aiSuggestions': aiSuggestions.map((entry) => entry.toJson()).toList(),
if (aiFailedBatches.isNotEmpty)
  'aiFailedBatches': aiFailedBatches.map((entry) => entry.toJson()).toList(),
if (aiReviewBatches.isNotEmpty)
  'aiReviewBatches': aiReviewBatches.map((entry) => entry.toJson()).toList(),
```

- [ ] **Step 4: Run cache persistence tests**

Run:

```powershell
dart format lib\data\studio\models\script_recast_knowledge.dart test\data\studio\models\script_recast_knowledge_test.dart
flutter test test\data\studio\models\script_recast_knowledge_test.dart
```

Expected: PASS.

---

### Task 8: ViewModel AI Recognition Integration

**Files:**
- Modify: `lib/ui/studio_script/view_models/studio_script_viewmodel.dart`
- Test: `test/ui/studio_script/studio_script_page_test.dart`

- [ ] **Step 1: Write failing ViewModel tests for cache fill and confirmation**

Add to `test/ui/studio_script/studio_script_page_test.dart` inside the `StudioScriptViewModel` group:

```dart
test('ai analysis fills cache suggestions pending confirmation', () async {
  final viewModel = StudioScriptViewModel(
    scriptAiRecognitionService: _FakeRecognitionService(
      const ScriptAiRecognitionResult(
        aiRequestCount: 0,
        suggestions: [
          ScriptAiSuggestion(
            id: 'sug-1',
            batchId: 'batch',
            sourceRoleId: 'slot-0',
            cacheKey: 'role:vulpisfoglia arknights|part:fox tail',
            source: ScriptAiSuggestionSource.cache,
            status: ScriptAiSuggestionStatus.suggested,
            displayName: 'vulpisfoglia_(arknights)',
            parts: RecastPromptParts(identity: 'vulpisfoglia_(arknights)'),
          ),
        ],
      ),
    ),
    scriptAiBaseUrlProvider: () => 'https://script.example/v1',
    scriptAiTokenProvider: () => 'token',
    scriptAiModelProvider: () => 'gpt-4.1-mini',
  );

  await viewModel.importScriptPath(_fixturePath);
  await viewModel.analyzeScriptWithAi();

  expect(viewModel.aiSuggestions.single.source, ScriptAiSuggestionSource.cache);
  expect(viewModel.aiSuggestions.single.status, ScriptAiSuggestionStatus.suggested);
  expect(viewModel.aiStatus, contains('缓存建议'));
});

test('confirming ai suggestion writes manual parts into role mapping', () async {
  final viewModel = StudioScriptViewModel(
    scriptAiRecognitionService: _FakeRecognitionService(
      const ScriptAiRecognitionResult(
        aiRequestCount: 1,
        suggestions: [
          ScriptAiSuggestion(
            id: 'sug-1',
            batchId: 'batch',
            sourceRoleId: 'slot-0',
            cacheKey: 'role:vulpisfoglia arknights|part:armor',
            source: ScriptAiSuggestionSource.ai,
            status: ScriptAiSuggestionStatus.suggested,
            displayName: 'vulpisfoglia_(arknights)',
            parts: RecastPromptParts(
              identity: 'vulpisfoglia_(arknights)',
              upperClothing: 'ai armor',
            ),
          ),
        ],
      ),
    ),
    scriptAiBaseUrlProvider: () => 'https://script.example/v1',
    scriptAiTokenProvider: () => 'token',
    scriptAiModelProvider: () => 'gpt-4.1-mini',
  );

  await viewModel.importScriptPath(_fixturePath);
  await viewModel.analyzeScriptWithAi();
  viewModel.confirmAiSuggestion('sug-1');

  expect(
    viewModel.roleMappings.first.stageItems.first.parts.upperClothing,
    'ai armor',
  );
});
```

At the bottom of the test file, add:

```dart
class _FakeRecognitionService implements ScriptAiRecognitionService {
  final ScriptAiRecognitionResult result;

  const _FakeRecognitionService(this.result);

  @override
  Future<ScriptAiRecognitionResult> recognize({
    required ScriptAiRecognitionRequest request,
  }) async {
    return result;
  }
}
```

- [ ] **Step 2: Run ViewModel tests to verify they fail**

Run:

```powershell
flutter test test\ui\studio_script\studio_script_page_test.dart --plain-name "ai analysis fills cache suggestions pending confirmation"
flutter test test\ui\studio_script\studio_script_page_test.dart --plain-name "confirming ai suggestion writes manual parts into role mapping"
```

Expected: FAIL because constructor injection and AI methods are missing.

- [ ] **Step 3: Add ViewModel dependencies and public state**

In `lib/ui/studio_script/view_models/studio_script_viewmodel.dart`, import AI models/services and add typedefs:

```dart
typedef StudioScriptAiSettingProvider = String Function();
```

Add constructor fields:

```dart
final ScriptAiRecognitionService? scriptAiRecognitionService;
final StudioScriptAiSettingProvider? scriptAiBaseUrlProvider;
final StudioScriptAiSettingProvider? scriptAiTokenProvider;
final StudioScriptAiSettingProvider? scriptAiModelProvider;
```

Add public state:

```dart
String aiStatus = '尚未进行 AI 分析';
List<ScriptAiSuggestion> aiSuggestions = const [];
```

- [ ] **Step 4: Implement `analyzeScriptWithAi`**

Add:

```dart
Future<void> analyzeScriptWithAi() async {
  final script = _script;
  if (script == null) {
    aiStatus = '请先导入剧本';
    notifyListeners();
    return;
  }
  final baseUrl = scriptAiBaseUrlProvider?.call().trim() ?? '';
  final token = scriptAiTokenProvider?.call().trim() ?? '';
  final model = scriptAiModelProvider?.call().trim() ?? '';
  if (baseUrl.isEmpty || token.isEmpty || model.isEmpty) {
    aiStatus = '请先配置剧本 AI 地址、Token 和模型';
    notifyListeners();
    return;
  }
  final service = scriptAiRecognitionService;
  if (service == null) {
    aiStatus = '剧本 AI 服务未配置';
    notifyListeners();
    return;
  }
  final batches = const ScriptAiBatchBuilder().buildBatches(script);
  final result = await service.recognize(
    request: ScriptAiRecognitionRequest(
      baseUrl: baseUrl,
      token: token,
      model: model,
      batches: batches,
    ),
  );
  aiSuggestions = List.unmodifiable(result.suggestions);
  final cacheCount = result.suggestions
      .where((item) => item.source == ScriptAiSuggestionSource.cache)
      .length;
  aiStatus = cacheCount == result.suggestions.length
      ? '已填入 ${result.suggestions.length} 条缓存建议'
      : '已填入 ${result.suggestions.length} 条 AI 建议';
  await _saveCurrentCache();
  notifyListeners();
}
```

- [ ] **Step 5: Implement `confirmAiSuggestion` and `rejectAiSuggestion`**

Add:

```dart
void confirmAiSuggestion(String suggestionId) {
  final suggestion =
      aiSuggestions.where((item) => item.id == suggestionId).firstOrNull;
  if (suggestion == null || suggestion.sourceRoleId == null) return;
  _updateRoleStage(
    sourceRoleId: suggestion.sourceRoleId!,
    stageId: roleMappings
            .where((item) => item.sourceRoleId == suggestion.sourceRoleId)
            .firstOrNull
            ?.selectedStage
            ?.id ??
        '${suggestion.sourceRoleId}-stage-1',
    update: (stage, character) => stage.copyWith(
      manualParts: suggestion.parts,
    ),
  );
  aiSuggestions = [
    for (final item in aiSuggestions)
      if (item.id == suggestionId)
        ScriptAiSuggestion(
          id: item.id,
          batchId: item.batchId,
          sourceRoleId: item.sourceRoleId,
          cacheKey: item.cacheKey,
          source: item.source,
          status: ScriptAiSuggestionStatus.confirmed,
          confidence: item.confidence,
          displayName: item.displayName,
          importance: item.importance,
          parts: item.parts,
          stageLabel: item.stageLabel,
          targetCharacterHint: item.targetCharacterHint,
          targetUpperOutfitHint: item.targetUpperOutfitHint,
          targetLowerOutfitHint: item.targetLowerOutfitHint,
          targetArtistChainHint: item.targetArtistChainHint,
          evidence: item.evidence,
          warnings: item.warnings,
          rawResponse: item.rawResponse,
        )
      else
        item,
  ];
  notifyListeners();
}

void rejectAiSuggestion(String suggestionId) {
  aiSuggestions = [
    for (final item in aiSuggestions)
      if (item.id == suggestionId)
        ScriptAiSuggestion(
          id: item.id,
          batchId: item.batchId,
          sourceRoleId: item.sourceRoleId,
          cacheKey: item.cacheKey,
          source: item.source,
          status: ScriptAiSuggestionStatus.rejected,
          confidence: item.confidence,
          displayName: item.displayName,
          importance: item.importance,
          parts: item.parts,
          stageLabel: item.stageLabel,
          targetCharacterHint: item.targetCharacterHint,
          targetUpperOutfitHint: item.targetUpperOutfitHint,
          targetLowerOutfitHint: item.targetLowerOutfitHint,
          targetArtistChainHint: item.targetArtistChainHint,
          evidence: item.evidence,
          warnings: item.warnings,
          rawResponse: item.rawResponse,
        )
      else
        item,
  ];
  notifyListeners();
}
```

If this duplication becomes unwieldy, add `copyWith` to `ScriptAiSuggestion` in Task 2 before implementing this step.

- [ ] **Step 6: Persist AI suggestions in cache save/restore**

When creating `RecastScriptCache` in `_saveCache`, include:

```dart
aiSuggestions: aiSuggestions,
```

When applying cache in `_applyCache`, restore:

```dart
aiSuggestions = cache.aiSuggestions;
aiStatus = aiSuggestions.isEmpty
    ? aiStatus
    : '已从缓存恢复 ${aiSuggestions.length} 条 AI 建议';
```

- [ ] **Step 7: Run ViewModel tests**

Run:

```powershell
dart format lib\ui\studio_script\view_models\studio_script_viewmodel.dart test\ui\studio_script\studio_script_page_test.dart
flutter test test\ui\studio_script\studio_script_page_test.dart --plain-name "ai analysis fills cache suggestions pending confirmation"
flutter test test\ui\studio_script\studio_script_page_test.dart --plain-name "confirming ai suggestion writes manual parts into role mapping"
```

Expected: PASS.

---

### Task 9: Script Page AI Controls

**Files:**
- Modify: `lib/ui/studio_script/widgets/studio_script_page.dart`
- Test: `test/ui/studio_script/studio_script_page_test.dart`

- [ ] **Step 1: Write failing widget test for AI controls**

Add to `test/ui/studio_script/studio_script_page_test.dart`:

```dart
testWidgets('script page exposes ai analysis controls and suggestion state',
    (tester) async {
  final viewModel = StudioScriptViewModel();
  await tester.runAsync(() async {
    await viewModel.importScriptPath(_fixturePath);
  });

  await tester.pumpWidget(buildScriptPage(viewModel: viewModel));
  await tester.pumpAndSettle();

  expect(find.text('AI 分析剧本'), findsOneWidget);
  expect(find.text('只使用缓存建议'), findsOneWidget);
  expect(find.text('重试失败项'), findsOneWidget);
});
```

- [ ] **Step 2: Run widget test to verify it fails**

Run:

```powershell
flutter test test\ui\studio_script\studio_script_page_test.dart --plain-name "script page exposes ai analysis controls and suggestion state"
```

Expected: FAIL because controls are missing.

- [ ] **Step 3: Add AI action buttons near existing script actions**

In `lib/ui/studio_script/widgets/studio_script_page.dart`, find the script action toolbar. Add buttons using existing button style patterns:

```dart
FilledButton.icon(
  onPressed: () => viewModel.analyzeScriptWithAi(),
  icon: const Icon(Icons.smart_toy_outlined),
  label: const Text('AI 分析剧本'),
),
OutlinedButton.icon(
  onPressed: () => viewModel.analyzeScriptWithAi(),
  icon: const Icon(Icons.cached_outlined),
  label: const Text('只使用缓存建议'),
),
OutlinedButton.icon(
  onPressed: () => viewModel.analyzeScriptWithAi(),
  icon: const Icon(Icons.refresh_outlined),
  label: const Text('重试失败项'),
),
```

For this implementation slice, `只使用缓存建议` and `重试失败项` call the same ViewModel method as `AI 分析剧本`; the labels reserve the UI affordance while the base pipeline is verified.

- [ ] **Step 4: Render AI suggestions in role cards**

In the role mapping card widget, add a compact status block when a matching suggestion exists:

```dart
final suggestion = viewModel.aiSuggestions
    .where((item) => item.sourceRoleId == role.sourceRoleId)
    .firstOrNull;
if (suggestion != null) ...[
  const SizedBox(height: 8),
  _AiSuggestionBanner(
    suggestion: suggestion,
    onConfirm: () => viewModel.confirmAiSuggestion(suggestion.id),
    onReject: () => viewModel.rejectAiSuggestion(suggestion.id),
    onRetry: () => viewModel.analyzeScriptWithAi(),
  ),
],
```

Create a private widget:

```dart
class _AiSuggestionBanner extends StatelessWidget {
  final ScriptAiSuggestion suggestion;
  final VoidCallback onConfirm;
  final VoidCallback onReject;
  final VoidCallback onRetry;

  const _AiSuggestionBanner({
    required this.suggestion,
    required this.onConfirm,
    required this.onReject,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final label = switch (suggestion.source) {
      ScriptAiSuggestionSource.cache => '缓存建议',
      ScriptAiSuggestionSource.ai => 'AI 建议',
      ScriptAiSuggestionSource.needsReview => '需人工审查',
      ScriptAiSuggestionSource.failed => 'AI 失败',
      ScriptAiSuggestionSource.local => '本地规则',
    };
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: StudioTokens.surface2,
        borderRadius: StudioTokens.radiusSlot,
        border: StudioTokens.cardBorder,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('$label · ${suggestion.displayName}'),
          if (suggestion.parts.identity.trim().isNotEmpty)
            Text('角色身份：${suggestion.parts.identity}'),
          if (suggestion.parts.upperClothing.trim().isNotEmpty)
            Text('上装：${suggestion.parts.upperClothing}'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              TextButton(onPressed: onConfirm, child: const Text('确认此角色')),
              TextButton(onPressed: onReject, child: const Text('拒绝建议')),
              TextButton(onPressed: onRetry, child: const Text('重试 AI')),
            ],
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 5: Run widget tests**

Run:

```powershell
dart format lib\ui\studio_script\widgets\studio_script_page.dart test\ui\studio_script\studio_script_page_test.dart
flutter test test\ui\studio_script\studio_script_page_test.dart --plain-name "script page exposes ai analysis controls and suggestion state"
flutter test test\ui\studio_script\studio_script_page_test.dart
```

Expected: PASS.

---

### Task 10: End-to-End Verification

**Files:**
- Modify only files touched by earlier tasks if failures reveal integration issues.

- [ ] **Step 1: Run focused data tests**

Run:

```powershell
flutter test test\data\models\settings_batch_interval_jitter_test.dart test\data\studio\models\script_ai_recognition_test.dart test\data\studio\models\script_recast_knowledge_test.dart test\data\studio\services\script_ai_normalizer_test.dart test\data\studio\services\script_ai_batch_builder_test.dart test\data\studio\services\script_ai_cache_service_test.dart test\data\studio\services\script_ai_client_test.dart test\data\studio\services\script_ai_recognition_service_test.dart
```

Expected: PASS.

- [ ] **Step 2: Run focused UI tests**

Run:

```powershell
flutter test test\ui\settings_page\settings_page_viewmodel_test.dart test\ui\settings_page\settings_page_view_widget_test.dart test\ui\studio_script\studio_script_page_test.dart
```

Expected: PASS.

- [ ] **Step 3: Run analyzer**

Run:

```powershell
flutter analyze
```

Expected: No new errors. Existing repository warnings must be inspected; only claim clean if output has no issues.

- [ ] **Step 4: Update Beads**

Run:

```powershell
bd update NAI_NEW-7ej --notes "Implementation completed and focused tests recorded: <paste test commands and pass/fail status>"
```

Expected: Beads issue notes updated. Do not close until all requested implementation and verification are actually complete.
