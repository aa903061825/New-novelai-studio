# Novel Workspace Data Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the visible `novel_workspace/` data foundation, import the three legacy data sources, validate workspace health, and bridge workspace prompt data back into the current generation flow.

**Architecture:** Add a focused `lib/data/workspace/` package containing schema models, path helpers, a single file I/O service, validation, importers, and CasRand adapters. Keep existing CasRand generation models intact and add conversion at the boundary so the current generation page continues to work during migration.

**Tech Stack:** Flutter/Dart, `dart:io`, existing `flutter_test`, existing `PayloadConfig`/`PromptConfig`/`ParamConfig` models, existing `ConfigService` for local Hive state.

---

## File Structure

- Create `lib/data/workspace/models/workspace_manifest.dart`: manifest schema, schema version, migration entries.
- Create `lib/data/workspace/models/workspace_entities.dart`: `Recipe`, `TagEntry`, `CharacterEntry`, `ArtistChain`, `WorkspacePromptConfig`, `GenerationProfile`, `BatchPlan`.
- Create `lib/data/workspace/models/workspace_validation.dart`: validation severity and issue model.
- Create `lib/data/workspace/workspace_paths.dart`: canonical relative paths and directory/file creation lists.
- Create `lib/data/workspace/workspace_service.dart`: create/open workspace, read/write JSON, entity repositories, active workspace path.
- Create `lib/data/workspace/workspace_validator.dart`: full workspace validation rules.
- Create `lib/data/workspace/importers/casrand_importer.dart`: exported/current CasRand JSON to workspace prompt config and profile.
- Create `lib/data/workspace/importers/kamia_importer.dart`: KAMIA `data/` folder to recipes, tags, characters, workflows, batch plans.
- Create `lib/data/workspace/importers/artist_studio_importer.dart`: Artist Chain Studio data folder to artist chains, characters, rules.
- Create `lib/data/workspace/adapters/casrand_workspace_adapter.dart`: workspace prompt config/profile back to existing `PayloadConfig`.
- Create `lib/ui/workspace_health/view_models/workspace_health_viewmodel.dart`: read-only counts and validation state.
- Create `lib/ui/workspace_health/widgets/workspace_health_page.dart`: read-only health page.
- Modify `lib/main.dart`: register `WorkspaceService` and `WorkspaceHealthViewModel`.
- Modify `lib/ui/navigation/widgets/navigation_view.dart`: add workspace health page destination.
- Add tests under `test/data/workspace/` and `test/ui/workspace_health/`.

## Task 1: Workspace Schema Models

**Files:**
- Create: `lib/data/workspace/models/workspace_manifest.dart`
- Create: `lib/data/workspace/models/workspace_entities.dart`
- Test: `test/data/workspace/workspace_models_test.dart`

- [ ] **Step 1: Write failing model round-trip tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/workspace/models/workspace_entities.dart';
import 'package:nai_casrand/data/workspace/models/workspace_manifest.dart';

void main() {
  test('WorkspaceManifest round trips migration metadata', () {
    final manifest = WorkspaceManifest(
      schemaVersion: 1,
      name: 'Novel Studio',
      currentPromptConfigId: 'prompt-1',
      migrations: [
        WorkspaceMigrationEntry(
          sourceType: 'kamia',
          sourcePath: r'C:\src\kamia',
          importedAt: DateTime.parse('2026-05-21T09:00:00Z'),
          importerVersion: 1,
          counts: const {'recipes': 2, 'tags': 3},
        ),
      ],
    );

    final restored = WorkspaceManifest.fromJson(manifest.toJson());

    expect(restored.schemaVersion, 1);
    expect(restored.name, 'Novel Studio');
    expect(restored.currentPromptConfigId, 'prompt-1');
    expect(restored.migrations.single.sourceType, 'kamia');
    expect(restored.migrations.single.counts['recipes'], 2);
  });

  test('CharacterEntry uses front_full as the required baseline variant', () {
    final character = CharacterEntry.fromJson({
      'id': 'char-1',
      'name': 'Heroine',
      'traits': {'front_full': 'blue eyes, silver hair'},
      'outfits': [
        {
          'id': 'outfit-1',
          'name': 'Uniform',
          'tags': {'front_full': 'school uniform'}
        }
      ],
      'imageRefs': ['assets/images/heroine.webp'],
      'source': {'type': 'kamia', 'id': 'old-char-1'},
      'note': 'main character',
    });

    expect(character.traits.frontFull, 'blue eyes, silver hair');
    expect(character.outfits.single.tags.frontFull, 'school uniform');
    expect(character.toJson()['id'], 'char-1');
  });

  test('GenerationProfile does not require secrets in JSON', () {
    final profile = GenerationProfile.fromJson({
      'id': 'profile-1',
      'name': 'Default V4.5',
      'params': {'model': 'nai-diffusion-4-5-full', 'steps': 28},
      'negativePrompt': 'bad anatomy',
      'secretRef': 'default_nai_token',
    });

    expect(profile.params['steps'], 28);
    expect(profile.secretRef, 'default_nai_token');
    expect(profile.toJson()['api_key'], isNull);
  });
}
```

- [ ] **Step 2: Run tests and verify missing imports fail**

Run: `flutter test test/data/workspace/workspace_models_test.dart`

Expected: FAIL with errors for missing `workspace_entities.dart` and `workspace_manifest.dart`.

- [ ] **Step 3: Add manifest models**

Create `lib/data/workspace/models/workspace_manifest.dart`:

```dart
class WorkspaceManifest {
  static const int currentSchemaVersion = 1;

  final int schemaVersion;
  final String name;
  final String? currentPromptConfigId;
  final List<WorkspaceMigrationEntry> migrations;

  const WorkspaceManifest({
    required this.schemaVersion,
    required this.name,
    this.currentPromptConfigId,
    this.migrations = const [],
  });

  factory WorkspaceManifest.empty({String name = 'Novel Studio'}) {
    return WorkspaceManifest(
      schemaVersion: currentSchemaVersion,
      name: name,
    );
  }

  factory WorkspaceManifest.fromJson(Map<String, dynamic> json) {
    return WorkspaceManifest(
      schemaVersion: json['schemaVersion'] ?? currentSchemaVersion,
      name: json['name'] ?? 'Novel Studio',
      currentPromptConfigId: json['currentPromptConfigId'] as String?,
      migrations: (json['migrations'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(WorkspaceMigrationEntry.fromJson)
          .toList(growable: false),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'schemaVersion': schemaVersion,
      'name': name,
      if (currentPromptConfigId != null)
        'currentPromptConfigId': currentPromptConfigId,
      'migrations': migrations.map((entry) => entry.toJson()).toList(),
    };
  }

  WorkspaceManifest copyWith({
    String? currentPromptConfigId,
    List<WorkspaceMigrationEntry>? migrations,
  }) {
    return WorkspaceManifest(
      schemaVersion: schemaVersion,
      name: name,
      currentPromptConfigId: currentPromptConfigId ?? this.currentPromptConfigId,
      migrations: migrations ?? this.migrations,
    );
  }
}

class WorkspaceMigrationEntry {
  final String sourceType;
  final String sourcePath;
  final DateTime importedAt;
  final int importerVersion;
  final Map<String, int> counts;

  const WorkspaceMigrationEntry({
    required this.sourceType,
    required this.sourcePath,
    required this.importedAt,
    required this.importerVersion,
    required this.counts,
  });

  factory WorkspaceMigrationEntry.fromJson(Map<String, dynamic> json) {
    return WorkspaceMigrationEntry(
      sourceType: json['sourceType'] ?? 'unknown',
      sourcePath: json['sourcePath'] ?? '',
      importedAt: DateTime.tryParse(json['importedAt'] ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      importerVersion: json['importerVersion'] ?? 1,
      counts: (json['counts'] as Map<String, dynamic>? ?? const {})
          .map((key, value) => MapEntry(key, value is int ? value : 0)),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'sourceType': sourceType,
      'sourcePath': sourcePath,
      'importedAt': importedAt.toUtc().toIso8601String(),
      'importerVersion': importerVersion,
      'counts': counts,
    };
  }
}
```

- [ ] **Step 4: Add entity models**

Create `lib/data/workspace/models/workspace_entities.dart` with the model classes used by the tests:

```dart
class SourceRef {
  final String type;
  final String? id;
  final String? path;

  const SourceRef({required this.type, this.id, this.path});

  factory SourceRef.fromJson(dynamic json) {
    if (json is! Map<String, dynamic>) return const SourceRef(type: 'manual');
    return SourceRef(
      type: json['type'] ?? 'manual',
      id: json['id'] as String?,
      path: json['path'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type,
        if (id != null) 'id': id,
        if (path != null) 'path': path,
      };
}

class ViewVariantTexts {
  final String frontFull;
  final String? frontCowboy;
  final String? frontUpper;
  final String? frontLower;
  final String? backFull;
  final String? backCowboy;
  final String? backUpper;
  final String? backLower;

  const ViewVariantTexts({
    required this.frontFull,
    this.frontCowboy,
    this.frontUpper,
    this.frontLower,
    this.backFull,
    this.backCowboy,
    this.backUpper,
    this.backLower,
  });

  factory ViewVariantTexts.fromJson(Map<String, dynamic> json) {
    return ViewVariantTexts(
      frontFull: json['front_full'] ?? '',
      frontCowboy: json['front_cowboy'] as String?,
      frontUpper: json['front_upper'] as String?,
      frontLower: json['front_lower'] as String?,
      backFull: json['back_full'] as String?,
      backCowboy: json['back_cowboy'] as String?,
      backUpper: json['back_upper'] as String?,
      backLower: json['back_lower'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'front_full': frontFull,
        if (frontCowboy != null) 'front_cowboy': frontCowboy,
        if (frontUpper != null) 'front_upper': frontUpper,
        if (frontLower != null) 'front_lower': frontLower,
        if (backFull != null) 'back_full': backFull,
        if (backCowboy != null) 'back_cowboy': backCowboy,
        if (backUpper != null) 'back_upper': backUpper,
        if (backLower != null) 'back_lower': backLower,
      };
}

class WorkspaceOutfit {
  final String id;
  final String name;
  final ViewVariantTexts tags;
  final List<String> imageRefs;
  final String note;

  const WorkspaceOutfit({
    required this.id,
    required this.name,
    required this.tags,
    this.imageRefs = const [],
    this.note = '',
  });

  factory WorkspaceOutfit.fromJson(Map<String, dynamic> json) {
    return WorkspaceOutfit(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      tags: ViewVariantTexts.fromJson(
        (json['tags'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      imageRefs: (json['imageRefs'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(growable: false),
      note: json['note'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'tags': tags.toJson(),
        if (imageRefs.isNotEmpty) 'imageRefs': imageRefs,
        if (note.isNotEmpty) 'note': note,
      };
}

class CharacterEntry {
  final String id;
  final String name;
  final ViewVariantTexts traits;
  final List<WorkspaceOutfit> outfits;
  final String? defaultOutfitId;
  final List<String> imageRefs;
  final SourceRef source;
  final String note;

  const CharacterEntry({
    required this.id,
    required this.name,
    required this.traits,
    this.outfits = const [],
    this.defaultOutfitId,
    this.imageRefs = const [],
    this.source = const SourceRef(type: 'manual'),
    this.note = '',
  });

  factory CharacterEntry.fromJson(Map<String, dynamic> json) {
    return CharacterEntry(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      traits: ViewVariantTexts.fromJson(
        (json['traits'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      outfits: (json['outfits'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(WorkspaceOutfit.fromJson)
          .toList(growable: false),
      defaultOutfitId: json['defaultOutfitId'] as String?,
      imageRefs: (json['imageRefs'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(growable: false),
      source: SourceRef.fromJson(json['source']),
      note: json['note'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'traits': traits.toJson(),
        'outfits': outfits.map((outfit) => outfit.toJson()).toList(),
        if (defaultOutfitId != null) 'defaultOutfitId': defaultOutfitId,
        if (imageRefs.isNotEmpty) 'imageRefs': imageRefs,
        'source': source.toJson(),
        if (note.isNotEmpty) 'note': note,
      };
}

class Recipe {
  final String id;
  final String name;
  final String block;
  final String category;
  final String group;
  final String tags;
  final Map<String, String> variants;
  final List<String> imageRefs;
  final SourceRef source;
  final String note;

  const Recipe({
    required this.id,
    required this.name,
    required this.block,
    this.category = '',
    this.group = '',
    this.tags = '',
    this.variants = const {},
    this.imageRefs = const [],
    this.source = const SourceRef(type: 'manual'),
    this.note = '',
  });

  factory Recipe.fromJson(Map<String, dynamic> json) => Recipe(
        id: json['id'] ?? '',
        name: json['name'] ?? '',
        block: json['block'] ?? '',
        category: json['category'] ?? '',
        group: json['group'] ?? '',
        tags: json['tags'] ?? '',
        variants: (json['variants'] as Map<String, dynamic>? ?? const {})
            .map((key, value) => MapEntry(key, value.toString())),
        imageRefs: (json['imageRefs'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toList(growable: false),
        source: SourceRef.fromJson(json['source']),
        note: json['note'] ?? '',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'block': block,
        if (category.isNotEmpty) 'category': category,
        if (group.isNotEmpty) 'group': group,
        if (tags.isNotEmpty) 'tags': tags,
        if (variants.isNotEmpty) 'variants': variants,
        if (imageRefs.isNotEmpty) 'imageRefs': imageRefs,
        'source': source.toJson(),
        if (note.isNotEmpty) 'note': note,
      };
}

class TagEntry {
  final String id;
  final String tag;
  final String zh;
  final String block;
  final String category;
  final List<String> aliases;
  final List<String> imageRefs;
  final SourceRef source;
  final String note;

  const TagEntry({
    required this.id,
    required this.tag,
    this.zh = '',
    required this.block,
    this.category = '',
    this.aliases = const [],
    this.imageRefs = const [],
    this.source = const SourceRef(type: 'manual'),
    this.note = '',
  });

  factory TagEntry.fromJson(Map<String, dynamic> json) => TagEntry(
        id: json['id'] ?? json['tag'] ?? '',
        tag: json['tag'] ?? '',
        zh: json['zh'] ?? json['name_zh'] ?? '',
        block: json['block'] ?? '',
        category: json['category'] ?? '',
        aliases: (json['aliases'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toList(growable: false),
        imageRefs: (json['imageRefs'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toList(growable: false),
        source: SourceRef.fromJson(json['source']),
        note: json['note'] ?? '',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'tag': tag,
        if (zh.isNotEmpty) 'zh': zh,
        'block': block,
        if (category.isNotEmpty) 'category': category,
        if (aliases.isNotEmpty) 'aliases': aliases,
        if (imageRefs.isNotEmpty) 'imageRefs': imageRefs,
        'source': source.toJson(),
        if (note.isNotEmpty) 'note': note,
      };
}

class ArtistChain {
  final String id;
  final String name;
  final List<String> tags;
  final String prompt;
  final List<String> styleTags;
  final List<String> imageRefs;
  final Map<String, String> translations;
  final SourceRef source;
  final String note;

  const ArtistChain({
    required this.id,
    required this.name,
    this.tags = const [],
    this.prompt = '',
    this.styleTags = const [],
    this.imageRefs = const [],
    this.translations = const {},
    this.source = const SourceRef(type: 'manual'),
    this.note = '',
  });

  factory ArtistChain.fromJson(Map<String, dynamic> json) => ArtistChain(
        id: json['id'] ?? '',
        name: json['name'] ?? '',
        tags: (json['tags'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toList(growable: false),
        prompt: json['prompt'] ?? '',
        styleTags: (json['styleTags'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toList(growable: false),
        imageRefs: (json['imageRefs'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toList(growable: false),
        translations: (json['translations'] as Map<String, dynamic>? ?? const {})
            .map((key, value) => MapEntry(key, value.toString())),
        source: SourceRef.fromJson(json['source']),
        note: json['note'] ?? '',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (tags.isNotEmpty) 'tags': tags,
        if (prompt.isNotEmpty) 'prompt': prompt,
        if (styleTags.isNotEmpty) 'styleTags': styleTags,
        if (imageRefs.isNotEmpty) 'imageRefs': imageRefs,
        if (translations.isNotEmpty) 'translations': translations,
        'source': source.toJson(),
        if (note.isNotEmpty) 'note': note,
      };
}

class WorkspacePromptConfig {
  final String id;
  final String name;
  final Map<String, dynamic> rootConfig;
  final List<Map<String, dynamic>> savedBlocks;
  final List<String> replaceRuleIds;
  final String? generationProfileId;

  const WorkspacePromptConfig({
    required this.id,
    required this.name,
    required this.rootConfig,
    this.savedBlocks = const [],
    this.replaceRuleIds = const [],
    this.generationProfileId,
  });

  factory WorkspacePromptConfig.fromJson(Map<String, dynamic> json) {
    return WorkspacePromptConfig(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      rootConfig: (json['rootConfig'] as Map?)?.cast<String, dynamic>() ?? {},
      savedBlocks: (json['savedBlocks'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList(growable: false),
      replaceRuleIds: (json['replaceRuleIds'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(growable: false),
      generationProfileId: json['generationProfileId'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'rootConfig': rootConfig,
        'savedBlocks': savedBlocks,
        if (replaceRuleIds.isNotEmpty) 'replaceRuleIds': replaceRuleIds,
        if (generationProfileId != null)
          'generationProfileId': generationProfileId,
      };
}

class GenerationProfile {
  final String id;
  final String name;
  final Map<String, dynamic> params;
  final String negativePrompt;
  final List<String> vibeRefs;
  final List<String> preciseReferenceRefs;
  final Map<String, dynamic> batchDefaults;
  final String? secretRef;

  const GenerationProfile({
    required this.id,
    required this.name,
    this.params = const {},
    this.negativePrompt = '',
    this.vibeRefs = const [],
    this.preciseReferenceRefs = const [],
    this.batchDefaults = const {},
    this.secretRef,
  });

  factory GenerationProfile.fromJson(Map<String, dynamic> json) {
    return GenerationProfile(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      params: (json['params'] as Map?)?.cast<String, dynamic>() ?? {},
      negativePrompt: json['negativePrompt'] ?? '',
      vibeRefs: (json['vibeRefs'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(growable: false),
      preciseReferenceRefs:
          (json['preciseReferenceRefs'] as List<dynamic>? ?? const [])
              .whereType<String>()
              .toList(growable: false),
      batchDefaults:
          (json['batchDefaults'] as Map?)?.cast<String, dynamic>() ?? {},
      secretRef: json['secretRef'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (params.isNotEmpty) 'params': params,
        if (negativePrompt.isNotEmpty) 'negativePrompt': negativePrompt,
        if (vibeRefs.isNotEmpty) 'vibeRefs': vibeRefs,
        if (preciseReferenceRefs.isNotEmpty)
          'preciseReferenceRefs': preciseReferenceRefs,
        if (batchDefaults.isNotEmpty) 'batchDefaults': batchDefaults,
        if (secretRef != null) 'secretRef': secretRef,
      };
}

class BatchPlan {
  final String id;
  final String name;
  final List<Map<String, dynamic>> items;
  final Map<String, dynamic> statusSnapshot;
  final DateTime createdAt;
  final DateTime updatedAt;

  const BatchPlan({
    required this.id,
    required this.name,
    this.items = const [],
    this.statusSnapshot = const {},
    required this.createdAt,
    required this.updatedAt,
  });

  factory BatchPlan.fromJson(Map<String, dynamic> json) => BatchPlan(
        id: json['id'] ?? '',
        name: json['name'] ?? '',
        items: (json['items'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .toList(growable: false),
        statusSnapshot:
            (json['statusSnapshot'] as Map?)?.cast<String, dynamic>() ?? {},
        createdAt: DateTime.tryParse(json['createdAt'] ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        updatedAt: DateTime.tryParse(json['updatedAt'] ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'items': items,
        if (statusSnapshot.isNotEmpty) 'statusSnapshot': statusSnapshot,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
      };
}
```

- [ ] **Step 5: Run model tests**

Run: `flutter test test/data/workspace/workspace_models_test.dart`

Expected: PASS.

## Task 2: Workspace Paths and Service

**Files:**
- Create: `lib/data/workspace/workspace_paths.dart`
- Create: `lib/data/workspace/workspace_service.dart`
- Test: `test/data/workspace/workspace_service_test.dart`

- [ ] **Step 1: Write failing service tests**

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/workspace/models/workspace_entities.dart';
import 'package:nai_casrand/data/workspace/workspace_service.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('novel-workspace-test-');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('createWorkspace creates manifest and expected JSON files', () async {
    final service = WorkspaceService();

    await service.createWorkspace(tempDir.path, name: 'Test Studio');

    expect(File('${tempDir.path}${Platform.pathSeparator}studio_manifest.json').existsSync(), isTrue);
    expect(File('${tempDir.path}${Platform.pathSeparator}library${Platform.pathSeparator}characters.json').existsSync(), isTrue);
    expect(File('${tempDir.path}${Platform.pathSeparator}library${Platform.pathSeparator}artist_chains.json').existsSync(), isTrue);
    expect(Directory('${tempDir.path}${Platform.pathSeparator}configs${Platform.pathSeparator}prompt_configs').existsSync(), isTrue);
    expect(service.currentManifest!.name, 'Test Studio');
  });

  test('writes and reads workspace characters', () async {
    final service = WorkspaceService();
    await service.createWorkspace(tempDir.path, name: 'Test Studio');

    await service.saveCharacters([
      CharacterEntry(
        id: 'char-1',
        name: 'Heroine',
        traits: const ViewVariantTexts(frontFull: 'blue eyes'),
      ),
    ]);

    final characters = await service.loadCharacters();

    expect(characters.single.id, 'char-1');
    expect(characters.single.traits.frontFull, 'blue eyes');
  });
}
```

- [ ] **Step 2: Run tests and verify service is missing**

Run: `flutter test test/data/workspace/workspace_service_test.dart`

Expected: FAIL with missing `WorkspaceService`.

- [ ] **Step 3: Add workspace paths**

Create `lib/data/workspace/workspace_paths.dart`:

```dart
class WorkspacePaths {
  static const manifest = 'studio_manifest.json';
  static const characters = 'library/characters.json';
  static const artistChains = 'library/artist_chains.json';
  static const inspirations = 'library/inspirations.json';
  static const loras = 'library/loras.json';
  static const promptReplaceRules = 'configs/prompt_replace_rules.json';
  static const filterRules = 'configs/filter_rules.json';

  static const blocks = [
    'style',
    'sub_style',
    'character',
    'clothing',
    'action',
    'expression',
    'scene',
    'camera',
  ];

  static const directories = [
    'library/recipes',
    'library/tags',
    'configs/prompt_configs',
    'configs/generation_profiles',
    'production/batch_plans',
    'production/assembly_presets',
    'production/workflows',
    'assets/images',
    'assets/thumbnails',
    'assets/references',
    'imports/kamia',
    'imports/casrand',
    'imports/artist_studio',
    'output/nai',
    'output/comfyui',
  ];

  static List<String> get emptyArrayFiles => [
        characters,
        artistChains,
        inspirations,
        loras,
        promptReplaceRules,
        for (final block in blocks) 'library/recipes/$block.json',
        for (final block in blocks) 'library/tags/$block.json',
      ];

  static List<String> get emptyObjectFiles => [
        filterRules,
      ];
}
```

- [ ] **Step 4: Add WorkspaceService**

Create `lib/data/workspace/workspace_service.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:nai_casrand/data/workspace/models/workspace_entities.dart';
import 'package:nai_casrand/data/workspace/models/workspace_manifest.dart';
import 'package:nai_casrand/data/workspace/workspace_paths.dart';

class WorkspaceService {
  Directory? _root;
  WorkspaceManifest? currentManifest;

  Directory? get root => _root;

  Future<void> createWorkspace(String path, {String name = 'Novel Studio'}) async {
    _root = Directory(path);
    await _root!.create(recursive: true);

    for (final relative in WorkspacePaths.directories) {
      await Directory(_resolve(relative)).create(recursive: true);
    }

    currentManifest = WorkspaceManifest.empty(name: name);
    await _writeJsonObject(WorkspacePaths.manifest, currentManifest!.toJson());

    for (final relative in WorkspacePaths.emptyArrayFiles) {
      await _writeJsonArray(relative, const []);
    }
    for (final relative in WorkspacePaths.emptyObjectFiles) {
      await _writeJsonObject(relative, const {});
    }
  }

  Future<void> openWorkspace(String path) async {
    _root = Directory(path);
    final manifestJson = await _readJsonObject(WorkspacePaths.manifest);
    currentManifest = WorkspaceManifest.fromJson(manifestJson);
  }

  Future<List<CharacterEntry>> loadCharacters() async {
    final data = await _readJsonArray(WorkspacePaths.characters);
    return data
        .whereType<Map<String, dynamic>>()
        .map(CharacterEntry.fromJson)
        .toList(growable: false);
  }

  Future<void> saveCharacters(List<CharacterEntry> characters) async {
    await _writeJsonArray(
      WorkspacePaths.characters,
      characters.map((character) => character.toJson()).toList(),
    );
  }

  Future<List<ArtistChain>> loadArtistChains() async {
    final data = await _readJsonArray(WorkspacePaths.artistChains);
    return data
        .whereType<Map<String, dynamic>>()
        .map(ArtistChain.fromJson)
        .toList(growable: false);
  }

  Future<void> saveArtistChains(List<ArtistChain> chains) async {
    await _writeJsonArray(
      WorkspacePaths.artistChains,
      chains.map((chain) => chain.toJson()).toList(),
    );
  }

  Future<List<Recipe>> loadRecipes(String block) async {
    final data = await _readJsonArray('library/recipes/$block.json');
    return data
        .whereType<Map<String, dynamic>>()
        .map(Recipe.fromJson)
        .toList(growable: false);
  }

  Future<void> saveRecipes(String block, List<Recipe> recipes) async {
    await _writeJsonArray(
      'library/recipes/$block.json',
      recipes.map((recipe) => recipe.toJson()).toList(),
    );
  }

  Future<List<TagEntry>> loadTags(String block) async {
    final data = await _readJsonArray('library/tags/$block.json');
    return data
        .whereType<Map<String, dynamic>>()
        .map(TagEntry.fromJson)
        .toList(growable: false);
  }

  Future<void> saveTags(String block, List<TagEntry> tags) async {
    await _writeJsonArray(
      'library/tags/$block.json',
      tags.map((tag) => tag.toJson()).toList(),
    );
  }

  Future<void> savePromptConfig(WorkspacePromptConfig config) async {
    await _writeJsonObject(
      'configs/prompt_configs/${config.id}.json',
      config.toJson(),
    );
  }

  Future<WorkspacePromptConfig> loadPromptConfig(String id) async {
    return WorkspacePromptConfig.fromJson(
      await _readJsonObject('configs/prompt_configs/$id.json'),
    );
  }

  Future<void> saveGenerationProfile(GenerationProfile profile) async {
    await _writeJsonObject(
      'configs/generation_profiles/${profile.id}.json',
      profile.toJson(),
    );
  }

  Future<GenerationProfile> loadGenerationProfile(String id) async {
    return GenerationProfile.fromJson(
      await _readJsonObject('configs/generation_profiles/$id.json'),
    );
  }

  String _resolve(String relative) {
    final normalized = relative.replaceAll('/', Platform.pathSeparator);
    return '${_requireRoot().path}${Platform.pathSeparator}$normalized';
  }

  Directory _requireRoot() {
    final root = _root;
    if (root == null) {
      throw StateError('Workspace is not open');
    }
    return root;
  }

  Future<Map<String, dynamic>> _readJsonObject(String relative) async {
    final file = File(_resolve(relative));
    final raw = await file.readAsString();
    return (jsonDecode(raw) as Map).cast<String, dynamic>();
  }

  Future<List<dynamic>> _readJsonArray(String relative) async {
    final file = File(_resolve(relative));
    final raw = await file.readAsString();
    return jsonDecode(raw) as List<dynamic>;
  }

  Future<void> _writeJsonObject(String relative, Map<String, dynamic> data) {
    return _writeJson(relative, data);
  }

  Future<void> _writeJsonArray(String relative, List<dynamic> data) {
    return _writeJson(relative, data);
  }

  Future<void> _writeJson(String relative, Object data) async {
    final file = File(_resolve(relative));
    await file.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString('${encoder.convert(data)}\n');
  }
}
```

- [ ] **Step 5: Run service tests**

Run: `flutter test test/data/workspace/workspace_service_test.dart`

Expected: PASS.

## Task 3: Workspace Validator

**Files:**
- Create: `lib/data/workspace/models/workspace_validation.dart`
- Create: `lib/data/workspace/workspace_validator.dart`
- Test: `test/data/workspace/workspace_validator_test.dart`

- [ ] **Step 1: Write failing validator tests**

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/workspace/models/workspace_entities.dart';
import 'package:nai_casrand/data/workspace/models/workspace_validation.dart';
import 'package:nai_casrand/data/workspace/workspace_service.dart';
import 'package:nai_casrand/data/workspace/workspace_validator.dart';

void main() {
  late Directory tempDir;
  late WorkspaceService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('novel-validator-test-');
    service = WorkspaceService();
    await service.createWorkspace(tempDir.path, name: 'Validator Studio');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('reports invalid blocks and duplicate IDs', () async {
    await service.saveRecipes('style', [
      const Recipe(id: 'r1', name: 'Good', block: 'style'),
      const Recipe(id: 'r1', name: 'Duplicate', block: 'bad_block'),
    ]);

    final report = await WorkspaceValidator(service).validate();

    expect(report.hasErrors, isTrue);
    expect(report.issues.any((issue) => issue.code == 'duplicate_id'), isTrue);
    expect(report.issues.any((issue) => issue.code == 'invalid_block'), isTrue);
  });

  test('blocks token-like values in generation profiles', () async {
    await service.saveGenerationProfile(
      const GenerationProfile(
        id: 'profile-1',
        name: 'Unsafe',
        params: {'api_key': 'pst-secret-token'},
      ),
    );

    final report = await WorkspaceValidator(service).validate();

    expect(report.issues.any((issue) {
      return issue.severity == WorkspaceValidationSeverity.error &&
          issue.code == 'secret_in_workspace';
    }), isTrue);
  });
}
```

- [ ] **Step 2: Run tests and verify validator is missing**

Run: `flutter test test/data/workspace/workspace_validator_test.dart`

Expected: FAIL with missing validation classes.

- [ ] **Step 3: Add validation models**

Create `lib/data/workspace/models/workspace_validation.dart`:

```dart
enum WorkspaceValidationSeverity { warning, error }

class WorkspaceValidationIssue {
  final WorkspaceValidationSeverity severity;
  final String code;
  final String path;
  final String message;

  const WorkspaceValidationIssue({
    required this.severity,
    required this.code,
    required this.path,
    required this.message,
  });
}

class WorkspaceValidationReport {
  final List<WorkspaceValidationIssue> issues;

  const WorkspaceValidationReport(this.issues);

  bool get hasErrors => issues.any(
        (issue) => issue.severity == WorkspaceValidationSeverity.error,
      );

  int get warningCount => issues
      .where((issue) => issue.severity == WorkspaceValidationSeverity.warning)
      .length;

  int get errorCount => issues
      .where((issue) => issue.severity == WorkspaceValidationSeverity.error)
      .length;
}
```

- [ ] **Step 4: Add validator**

Create `lib/data/workspace/workspace_validator.dart`:

```dart
import 'dart:io';

import 'package:nai_casrand/data/workspace/models/workspace_entities.dart';
import 'package:nai_casrand/data/workspace/models/workspace_validation.dart';
import 'package:nai_casrand/data/workspace/workspace_paths.dart';
import 'package:nai_casrand/data/workspace/workspace_service.dart';

class WorkspaceValidator {
  final WorkspaceService service;

  WorkspaceValidator(this.service);

  Future<WorkspaceValidationReport> validate() async {
    final issues = <WorkspaceValidationIssue>[];
    _validateManifest(issues);
    await _validateRecipes(issues);
    await _validateCharacters(issues);
    await _validateGenerationProfiles(issues);
    return WorkspaceValidationReport(issues);
  }

  void _validateManifest(List<WorkspaceValidationIssue> issues) {
    final manifest = service.currentManifest;
    if (manifest == null) {
      issues.add(const WorkspaceValidationIssue(
        severity: WorkspaceValidationSeverity.error,
        code: 'missing_manifest',
        path: 'studio_manifest.json',
        message: 'Workspace manifest is not loaded.',
      ));
      return;
    }
    if (manifest.schemaVersion > 1) {
      issues.add(WorkspaceValidationIssue(
        severity: WorkspaceValidationSeverity.error,
        code: 'unsupported_schema_version',
        path: 'studio_manifest.json',
        message:
            'Workspace schema ${manifest.schemaVersion} is newer than this app supports.',
      ));
    }
  }

  Future<void> _validateRecipes(List<WorkspaceValidationIssue> issues) async {
    final seen = <String>{};
    for (final block in WorkspacePaths.blocks) {
      final recipes = await service.loadRecipes(block);
      for (final recipe in recipes) {
        _validateId(issues, seen, recipe.id, 'library/recipes/$block.json');
        if (!WorkspacePaths.blocks.contains(recipe.block)) {
          issues.add(WorkspaceValidationIssue(
            severity: WorkspaceValidationSeverity.error,
            code: 'invalid_block',
            path: 'library/recipes/$block.json',
            message: 'Recipe ${recipe.id} uses invalid block ${recipe.block}.',
          ));
        }
        _validateImageRefs(issues, recipe.imageRefs, 'Recipe ${recipe.id}');
      }
    }
  }

  Future<void> _validateCharacters(List<WorkspaceValidationIssue> issues) async {
    final seen = <String>{};
    final characters = await service.loadCharacters();
    for (final character in characters) {
      _validateId(issues, seen, character.id, 'library/characters.json');
      if (character.traits.frontFull.trim().isEmpty) {
        issues.add(WorkspaceValidationIssue(
          severity: WorkspaceValidationSeverity.error,
          code: 'missing_front_full',
          path: 'library/characters.json',
          message: 'Character ${character.id} has no front_full traits.',
        ));
      }
      for (final outfit in character.outfits) {
        if (outfit.tags.frontFull.trim().isEmpty) {
          issues.add(WorkspaceValidationIssue(
            severity: WorkspaceValidationSeverity.error,
            code: 'missing_front_full',
            path: 'library/characters.json',
            message:
                'Outfit ${outfit.id} on character ${character.id} has no front_full tags.',
          ));
        }
      }
      _validateImageRefs(issues, character.imageRefs, 'Character ${character.id}');
    }
  }

  Future<void> _validateGenerationProfiles(
    List<WorkspaceValidationIssue> issues,
  ) async {
    final root = service.root;
    if (root == null) return;
    final dir = Directory(
      '${root.path}${Platform.pathSeparator}configs${Platform.pathSeparator}generation_profiles',
    );
    if (!await dir.exists()) return;
    await for (final entity in dir.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      final id = entity.uri.pathSegments.last.replaceAll('.json', '');
      final profile = await service.loadGenerationProfile(id);
      final raw = profile.toJson().toString().toLowerCase();
      if (raw.contains('api_key') ||
          raw.contains('pst-') ||
          raw.contains('bearer ')) {
        issues.add(WorkspaceValidationIssue(
          severity: WorkspaceValidationSeverity.error,
          code: 'secret_in_workspace',
          path: entity.path,
          message: 'Generation profile ${profile.id} contains a raw secret.',
        ));
      }
    }
  }

  void _validateId(
    List<WorkspaceValidationIssue> issues,
    Set<String> seen,
    String id,
    String path,
  ) {
    if (id.trim().isEmpty) {
      issues.add(WorkspaceValidationIssue(
        severity: WorkspaceValidationSeverity.error,
        code: 'empty_id',
        path: path,
        message: 'Entity has an empty id.',
      ));
      return;
    }
    if (!seen.add(id)) {
      issues.add(WorkspaceValidationIssue(
        severity: WorkspaceValidationSeverity.error,
        code: 'duplicate_id',
        path: path,
        message: 'Duplicate id $id.',
      ));
    }
  }

  void _validateImageRefs(
    List<WorkspaceValidationIssue> issues,
    List<String> refs,
    String owner,
  ) {
    final root = service.root;
    if (root == null) return;
    for (final ref in refs) {
      final file = File(
        '${root.path}${Platform.pathSeparator}${ref.replaceAll('/', Platform.pathSeparator)}',
      );
      if (!file.existsSync()) {
        issues.add(WorkspaceValidationIssue(
          severity: WorkspaceValidationSeverity.warning,
          code: 'missing_image_ref',
          path: ref,
          message: '$owner references a missing image: $ref.',
        ));
      }
    }
  }
}
```

- [ ] **Step 5: Run validator tests**

Run: `flutter test test/data/workspace/workspace_validator_test.dart`

Expected: PASS.

## Task 4: CasRand Import and Export Bridge

**Files:**
- Create: `lib/data/workspace/importers/casrand_importer.dart`
- Create: `lib/data/workspace/adapters/casrand_workspace_adapter.dart`
- Test: `test/data/workspace/casrand_workspace_adapter_test.dart`

- [ ] **Step 1: Write failing import/export tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/models/payload_config.dart';
import 'package:nai_casrand/data/workspace/adapters/casrand_workspace_adapter.dart';
import 'package:nai_casrand/data/workspace/importers/casrand_importer.dart';

void main() {
  Map<String, dynamic> legacyConfig() => {
        'prompt_config': {
          'selectionMethod': 'all',
          'shuffled': false,
          'prob': 0.0,
          'num': 1,
          'randomBracketsUpper': 0,
          'randomBracketsLower': 0,
          'type': 'str',
          'comment': 'root',
          'filter': '',
          'strs': ['masterpiece'],
          'prompts': [],
          'enabled': true,
        },
        'character_config': const [],
        'saved_config': const [],
        'prompt_replace_rules': [
          {'id': 'replace-1', 'source': 'cat', 'target': 'dog', 'enabled': true}
        ],
        'param_config': {
          'model': 'nai-diffusion-4-5-full',
          'width': 832,
          'height': 1216,
          'steps': 28,
          'scale': 5.0,
          'negative_prompt': 'bad anatomy',
        },
        'settings': {'api_key': 'pst-secret', 'proxy': '127.0.0.1:7890'},
        'override_prompt': '',
        'use_override_prompt': false,
        'use_character_prompt_with_override': false,
      };

  test('CasRandImporter splits prompt config and generation profile', () {
    final result = CasRandImporter().importJson(
      legacyConfig(),
      promptConfigId: 'prompt-1',
      profileId: 'profile-1',
    );

    expect(result.promptConfig.id, 'prompt-1');
    expect(result.promptConfig.rootConfig['comment'], 'root');
    expect(result.generationProfile.params['model'], 'nai-diffusion-4-5-full');
    expect(result.generationProfile.negativePrompt, 'bad anatomy');
    expect(result.generationProfile.toJson().toString(), isNot(contains('pst-secret')));
  });

  test('CasRandWorkspaceAdapter restores PayloadConfig for generation', () {
    final imported = CasRandImporter().importJson(
      legacyConfig(),
      promptConfigId: 'prompt-1',
      profileId: 'profile-1',
    );

    final payload = CasRandWorkspaceAdapter().toPayloadConfig(
      imported.promptConfig,
      imported.generationProfile,
      legacySettings: {'api_key': 'current-key'},
    );

    expect(payload, isA<PayloadConfig>());
    expect(payload.rootPromptConfig.comment, 'root');
    expect(payload.paramConfig.model, 'nai-diffusion-4-5-full');
    expect(payload.settings.apiKey, 'current-key');
  });
}
```

- [ ] **Step 2: Run tests and verify importer is missing**

Run: `flutter test test/data/workspace/casrand_workspace_adapter_test.dart`

Expected: FAIL with missing importer/adapter.

- [ ] **Step 3: Add CasRand importer**

Create `lib/data/workspace/importers/casrand_importer.dart`:

```dart
import 'package:nai_casrand/data/workspace/models/workspace_entities.dart';

class CasRandImportResult {
  final WorkspacePromptConfig promptConfig;
  final GenerationProfile generationProfile;
  final List<Map<String, dynamic>> replaceRules;

  const CasRandImportResult({
    required this.promptConfig,
    required this.generationProfile,
    required this.replaceRules,
  });
}

class CasRandImporter {
  CasRandImportResult importJson(
    Map<String, dynamic> json, {
    required String promptConfigId,
    required String profileId,
  }) {
    final paramConfig = (json['param_config'] as Map?)?.cast<String, dynamic>() ?? {};
    final negativePrompt = paramConfig['negative_prompt']?.toString() ?? '';
    final sanitizedParams = Map<String, dynamic>.from(paramConfig)
      ..remove('negative_prompt')
      ..remove('api_key')
      ..remove('token')
      ..remove('proxy');

    final replaceRules = (json['prompt_replace_rules'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);

    return CasRandImportResult(
      promptConfig: WorkspacePromptConfig(
        id: promptConfigId,
        name: 'Imported CasRand Config',
        rootConfig: (json['prompt_config'] as Map).cast<String, dynamic>(),
        savedBlocks: (json['saved_config'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .toList(growable: false),
        replaceRuleIds:
            replaceRules.map((rule) => rule['id']?.toString() ?? '').where((id) => id.isNotEmpty).toList(),
        generationProfileId: profileId,
      ),
      generationProfile: GenerationProfile(
        id: profileId,
        name: 'Imported CasRand Profile',
        params: sanitizedParams,
        negativePrompt: negativePrompt,
        batchDefaults: {
          'batch_count': (json['settings'] as Map?)?['batch_count'],
          'batch_interval': (json['settings'] as Map?)?['batch_interval'],
        }..removeWhere((key, value) => value == null),
        secretRef: 'default_nai_token',
      ),
      replaceRules: replaceRules,
    );
  }
}
```

- [ ] **Step 4: Add CasRand adapter**

Create `lib/data/workspace/adapters/casrand_workspace_adapter.dart`:

```dart
import 'package:nai_casrand/data/models/param_config.dart';
import 'package:nai_casrand/data/models/payload_config.dart';
import 'package:nai_casrand/data/models/prompt_config.dart';
import 'package:nai_casrand/data/models/settings.dart';
import 'package:nai_casrand/data/workspace/models/workspace_entities.dart';

class CasRandWorkspaceAdapter {
  PayloadConfig toPayloadConfig(
    WorkspacePromptConfig promptConfig,
    GenerationProfile profile, {
    Map<String, dynamic> legacySettings = const {},
  }) {
    final paramJson = Map<String, dynamic>.from(profile.params);
    if (profile.negativePrompt.isNotEmpty) {
      paramJson['negative_prompt'] = profile.negativePrompt;
    }

    return PayloadConfig(
      rootPromptConfig: PromptConfig.fromJson(promptConfig.rootConfig),
      characterConfigList: const [],
      savedPromptConfigList: promptConfig.savedBlocks
          .map(PromptConfig.fromJson)
          .toList(growable: false),
      paramConfig: ParamConfig.fromJson(paramJson),
      settings: Settings.fromJson(legacySettings),
      overridePrompt: '',
      useOverridePrompt: false,
      useCharacterPromptWithOverride: false,
    );
  }
}
```

- [ ] **Step 5: Run CasRand bridge tests**

Run: `flutter test test/data/workspace/casrand_workspace_adapter_test.dart`

Expected: PASS.

## Task 5: KAMIA Importer

**Files:**
- Create: `lib/data/workspace/importers/kamia_importer.dart`
- Test: `test/data/workspace/kamia_importer_test.dart`

- [ ] **Step 1: Write failing KAMIA importer tests**

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/workspace/importers/kamia_importer.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('kamia-importer-test-');
    await Directory('${root.path}/data/recipes').create(recursive: true);
    await Directory('${root.path}/data/tags').create(recursive: true);
    await File('${root.path}/data/recipes/style.json').writeAsString(jsonEncode([
      {
        'id': 'style-1',
        'name': 'Quality',
        'block': 'style',
        'category': 'base',
        'group': 'quality',
        'tags': 'masterpiece',
        'image': null,
        'source': 'manual',
        'note': 'safe base'
      }
    ]));
    await File('${root.path}/data/tags/style.json').writeAsString(jsonEncode([
      {
        'tag': 'masterpiece',
        'name_zh': '杰作',
        'block': 'style',
        'category': 'quality',
        'note': '',
        'image': null
      }
    ]));
    await File('${root.path}/data/characters.json').writeAsString(jsonEncode([
      {
        'id': 'char-1',
        'name': 'Heroine',
        'preview_image': null,
        'traits': {'front_full': 'blue eyes'},
        'outfits': []
      }
    ]));
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  test('imports recipes, tags, and characters from KAMIA data folder', () async {
    final result = await KamiaImporter().importProject(root.path);

    expect(result.recipes['style']!.single.id, 'style-1');
    expect(result.tags['style']!.single.zh, '杰作');
    expect(result.characters.single.name, 'Heroine');
  });
}
```

- [ ] **Step 2: Run tests and verify importer is missing**

Run: `flutter test test/data/workspace/kamia_importer_test.dart`

Expected: FAIL with missing `KamiaImporter`.

- [ ] **Step 3: Add KAMIA importer**

Create `lib/data/workspace/importers/kamia_importer.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:nai_casrand/data/workspace/models/workspace_entities.dart';
import 'package:nai_casrand/data/workspace/workspace_paths.dart';

class KamiaImportResult {
  final Map<String, List<Recipe>> recipes;
  final Map<String, List<TagEntry>> tags;
  final List<CharacterEntry> characters;

  const KamiaImportResult({
    required this.recipes,
    required this.tags,
    required this.characters,
  });
}

class KamiaImporter {
  Future<KamiaImportResult> importProject(String projectPath) async {
    final dataPath = '$projectPath${Platform.pathSeparator}data';
    return KamiaImportResult(
      recipes: await _loadRecipes(dataPath),
      tags: await _loadTags(dataPath),
      characters: await _loadCharacters(dataPath),
    );
  }

  Future<Map<String, List<Recipe>>> _loadRecipes(String dataPath) async {
    final result = <String, List<Recipe>>{};
    for (final block in WorkspacePaths.blocks) {
      final file = File('$dataPath${Platform.pathSeparator}recipes${Platform.pathSeparator}$block.json');
      if (!await file.exists()) {
        result[block] = const [];
        continue;
      }
      final raw = jsonDecode(await file.readAsString()) as List<dynamic>;
      result[block] = raw.whereType<Map<String, dynamic>>().map((json) {
        final variants = <String, String>{};
        for (final entry in json.entries) {
          if (entry.key.startsWith('tags_') && entry.value is String) {
            variants[entry.key.replaceFirst('tags_', '')] = entry.value as String;
          }
        }
        return Recipe(
          id: json['id'] ?? '',
          name: json['name'] ?? '',
          block: json['block'] ?? block,
          category: json['category'] ?? '',
          group: json['group'] ?? '',
          tags: json['tags'] ?? '',
          variants: variants,
          imageRefs: _imageRef(json['image']),
          source: SourceRef(type: 'kamia', id: json['id']?.toString()),
          note: json['note'] ?? '',
        );
      }).toList(growable: false);
    }
    return result;
  }

  Future<Map<String, List<TagEntry>>> _loadTags(String dataPath) async {
    final result = <String, List<TagEntry>>{};
    for (final block in WorkspacePaths.blocks) {
      final file = File('$dataPath${Platform.pathSeparator}tags${Platform.pathSeparator}$block.json');
      if (!await file.exists()) {
        result[block] = const [];
        continue;
      }
      final raw = jsonDecode(await file.readAsString()) as List<dynamic>;
      result[block] = raw.whereType<Map<String, dynamic>>().map((json) {
        return TagEntry(
          id: '${block}_${json['tag'] ?? ''}',
          tag: json['tag'] ?? '',
          zh: json['name_zh'] ?? '',
          block: json['block'] ?? block,
          category: json['category'] ?? '',
          imageRefs: _imageRef(json['image']),
          source: SourceRef(type: 'kamia', id: json['tag']?.toString()),
          note: json['note'] ?? '',
        );
      }).toList(growable: false);
    }
    return result;
  }

  Future<List<CharacterEntry>> _loadCharacters(String dataPath) async {
    final file = File('$dataPath${Platform.pathSeparator}characters.json');
    if (!await file.exists()) return const [];
    final raw = jsonDecode(await file.readAsString()) as List<dynamic>;
    return raw.whereType<Map<String, dynamic>>().map((json) {
      return CharacterEntry(
        id: json['id'] ?? '',
        name: json['name'] ?? '',
        traits: ViewVariantTexts.fromJson(
          (json['traits'] as Map?)?.cast<String, dynamic>() ?? const {},
        ),
        outfits: (json['outfits'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(WorkspaceOutfit.fromJson)
            .toList(growable: false),
        imageRefs: _imageRef(json['preview_image']),
        source: SourceRef(type: 'kamia', id: json['id']?.toString()),
        note: json['note'] ?? '',
      );
    }).toList(growable: false);
  }

  List<String> _imageRef(dynamic value) {
    if (value is String && value.trim().isNotEmpty) return [value];
    return const [];
  }
}
```

- [ ] **Step 4: Run KAMIA importer tests**

Run: `flutter test test/data/workspace/kamia_importer_test.dart`

Expected: PASS.

## Task 6: Artist Chain Studio Importer

**Files:**
- Create: `lib/data/workspace/importers/artist_studio_importer.dart`
- Test: `test/data/workspace/artist_studio_importer_test.dart`

- [ ] **Step 1: Write failing Artist Studio importer tests**

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/workspace/importers/artist_studio_importer.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('artist-studio-importer-test-');
    final dataDir = Directory('${root.path}/画师串数据/data');
    await dataDir.create(recursive: true);
    await File('${dataDir.path}/data.json').writeAsString(jsonEncode({
      'artists': [
        {
          'id': 'artist-1',
          'name': 'Soft Painter',
          'tags': ['soft color', 'pastel'],
          'prompt': 'artist:soft painter',
          'images': ['images/a.png']
        }
      ],
      'characters': [
        {
          'id': 'char-1',
          'name': 'Muse',
          'features': 'green eyes',
          'images': ['images/c.png'],
          'outfit': 'white dress',
          'notes': 'import me'
        }
      ]
    }));
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  test('imports artist chains and characters', () async {
    final result = await ArtistStudioImporter().importDataRoot(root.path);

    expect(result.artistChains.single.name, 'Soft Painter');
    expect(result.artistChains.single.prompt, 'artist:soft painter');
    expect(result.characters.single.traits.frontFull, 'green eyes');
    expect(result.characters.single.outfits.single.tags.frontFull, 'white dress');
  });
}
```

- [ ] **Step 2: Run tests and verify importer is missing**

Run: `flutter test test/data/workspace/artist_studio_importer_test.dart`

Expected: FAIL with missing `ArtistStudioImporter`.

- [ ] **Step 3: Add Artist Studio importer**

Create `lib/data/workspace/importers/artist_studio_importer.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:nai_casrand/data/workspace/models/workspace_entities.dart';

class ArtistStudioImportResult {
  final List<ArtistChain> artistChains;
  final List<CharacterEntry> characters;
  final Map<String, dynamic> filterRules;

  const ArtistStudioImportResult({
    required this.artistChains,
    required this.characters,
    this.filterRules = const {},
  });
}

class ArtistStudioImporter {
  Future<ArtistStudioImportResult> importDataRoot(String rootPath) async {
    final dataJson = File(
      '$rootPath${Platform.pathSeparator}画师串数据${Platform.pathSeparator}data${Platform.pathSeparator}data.json',
    );
    if (!await dataJson.exists()) {
      return const ArtistStudioImportResult(artistChains: [], characters: []);
    }
    final decoded = (jsonDecode(await dataJson.readAsString()) as Map)
        .cast<String, dynamic>();
    return ArtistStudioImportResult(
      artistChains: _mapArtists(decoded['artists']),
      characters: _mapCharacters(decoded['characters']),
      filterRules: await _loadFilterRules(rootPath),
    );
  }

  List<ArtistChain> _mapArtists(dynamic value) {
    return (value as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((json) => ArtistChain(
              id: json['id'] ?? '',
              name: json['name'] ?? '',
              tags: _stringList(json['tags']),
              prompt: json['prompt'] ?? '',
              imageRefs: _stringList(json['images']),
              source: SourceRef(type: 'artist_studio', id: json['id']?.toString()),
            ))
        .toList(growable: false);
  }

  List<CharacterEntry> _mapCharacters(dynamic value) {
    return (value as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((json) {
          final outfitText = json['outfit']?.toString() ?? '';
          return CharacterEntry(
            id: json['id'] ?? '',
            name: json['name'] ?? '',
            traits: ViewVariantTexts(frontFull: json['features'] ?? ''),
            outfits: outfitText.isEmpty
                ? const []
                : [
                    WorkspaceOutfit(
                      id: '${json['id'] ?? 'character'}-outfit',
                      name: 'Imported Outfit',
                      tags: ViewVariantTexts(frontFull: outfitText),
                    ),
                  ],
            imageRefs: _stringList(json['images']),
            source: SourceRef(type: 'artist_studio', id: json['id']?.toString()),
            note: json['notes'] ?? '',
          );
        })
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> _loadFilterRules(String rootPath) async {
    final file = File('$rootPath${Platform.pathSeparator}nai_unified_config.json');
    if (!await file.exists()) return const {};
    return (jsonDecode(await file.readAsString()) as Map).cast<String, dynamic>();
  }

  List<String> _stringList(dynamic value) {
    return (value as List<dynamic>? ?? const [])
        .whereType<String>()
        .toList(growable: false);
  }
}
```

- [ ] **Step 4: Run Artist Studio importer tests**

Run: `flutter test test/data/workspace/artist_studio_importer_test.dart`

Expected: PASS.

## Task 7: Workspace Health ViewModel and Page

**Files:**
- Create: `lib/ui/workspace_health/view_models/workspace_health_viewmodel.dart`
- Create: `lib/ui/workspace_health/widgets/workspace_health_page.dart`
- Modify: `lib/main.dart`
- Modify: `lib/ui/navigation/widgets/navigation_view.dart`
- Test: `test/ui/workspace_health/workspace_health_page_test.dart`

- [ ] **Step 1: Write failing widget test**

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/workspace/models/workspace_entities.dart';
import 'package:nai_casrand/data/workspace/workspace_service.dart';
import 'package:nai_casrand/ui/workspace_health/view_models/workspace_health_viewmodel.dart';
import 'package:nai_casrand/ui/workspace_health/widgets/workspace_health_page.dart';

void main() {
  testWidgets('workspace health page shows counts and validation state',
      (tester) async {
    final tempDir = await Directory.systemTemp.createTemp('workspace-health-widget-');
    final service = WorkspaceService();
    await service.createWorkspace(tempDir.path, name: 'Health Studio');
    await service.saveCharacters([
      CharacterEntry(
        id: 'char-1',
        name: 'Heroine',
        traits: const ViewVariantTexts(frontFull: 'blue eyes'),
      ),
    ]);
    await service.saveArtistChains([
      const ArtistChain(id: 'artist-1', name: 'Painter'),
    ]);

    final viewModel = WorkspaceHealthViewModel(service);
    await viewModel.refresh();

    await tester.pumpWidget(MaterialApp(
      home: WorkspaceHealthPage(viewModel: viewModel),
    ));

    expect(find.text('Workspace Health'), findsOneWidget);
    expect(find.text('Characters'), findsOneWidget);
    expect(find.text('1'), findsWidgets);
    expect(find.text('No validation errors'), findsOneWidget);

    await tempDir.delete(recursive: true);
  });
}
```

- [ ] **Step 2: Run widget test and verify page is missing**

Run: `flutter test test/ui/workspace_health/workspace_health_page_test.dart`

Expected: FAIL with missing workspace health UI files.

- [ ] **Step 3: Add view model**

Create `lib/ui/workspace_health/view_models/workspace_health_viewmodel.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:nai_casrand/data/workspace/models/workspace_validation.dart';
import 'package:nai_casrand/data/workspace/workspace_paths.dart';
import 'package:nai_casrand/data/workspace/workspace_service.dart';
import 'package:nai_casrand/data/workspace/workspace_validator.dart';

class WorkspaceHealthViewModel extends ChangeNotifier {
  final WorkspaceService workspaceService;

  WorkspaceHealthViewModel(this.workspaceService);

  bool loading = false;
  Map<String, int> counts = const {};
  WorkspaceValidationReport report = const WorkspaceValidationReport([]);

  Future<void> refresh() async {
    loading = true;
    notifyListeners();

    final nextCounts = <String, int>{};
    nextCounts['Characters'] = (await workspaceService.loadCharacters()).length;
    nextCounts['Artist Chains'] =
        (await workspaceService.loadArtistChains()).length;
    for (final block in WorkspacePaths.blocks) {
      nextCounts['Recipes: $block'] =
          (await workspaceService.loadRecipes(block)).length;
      nextCounts['Tags: $block'] =
          (await workspaceService.loadTags(block)).length;
    }

    counts = nextCounts;
    report = await WorkspaceValidator(workspaceService).validate();
    loading = false;
    notifyListeners();
  }
}
```

- [ ] **Step 4: Add page**

Create `lib/ui/workspace_health/widgets/workspace_health_page.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:nai_casrand/ui/workspace_health/view_models/workspace_health_viewmodel.dart';

class WorkspaceHealthPage extends StatelessWidget {
  final WorkspaceHealthViewModel viewModel;

  const WorkspaceHealthPage({super.key, required this.viewModel});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListenableBuilder(
        listenable: viewModel,
        builder: (context, _) {
          if (viewModel.loading) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Workspace Health',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              for (final entry in viewModel.counts.entries)
                ListTile(
                  title: Text(entry.key),
                  trailing: Text(entry.value.toString()),
                ),
              const Divider(),
              if (!viewModel.report.hasErrors)
                const ListTile(
                  leading: Icon(Icons.check_circle_outline),
                  title: Text('No validation errors'),
                )
              else
                for (final issue in viewModel.report.issues)
                  ListTile(
                    leading: const Icon(Icons.error_outline),
                    title: Text(issue.message),
                    subtitle: Text('${issue.code} · ${issue.path}'),
                  ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: viewModel.refresh,
        child: const Icon(Icons.refresh),
      ),
    );
  }
}
```

- [ ] **Step 5: Register service and view model**

Modify `lib/main.dart` after `ConfigService` registration:

```dart
GetIt.instance.registerLazySingleton<WorkspaceService>(() => WorkspaceService());
GetIt.instance.registerFactory(
  () => WorkspaceHealthViewModel(GetIt.I<WorkspaceService>()),
);
```

Add imports:

```dart
import 'package:nai_casrand/data/workspace/workspace_service.dart';
import 'package:nai_casrand/ui/workspace_health/view_models/workspace_health_viewmodel.dart';
```

- [ ] **Step 6: Add navigation destination**

Modify `lib/ui/navigation/widgets/navigation_view.dart`:

```dart
import 'package:nai_casrand/ui/workspace_health/view_models/workspace_health_viewmodel.dart';
import 'package:nai_casrand/ui/workspace_health/widgets/workspace_health_page.dart';
```

Add the page to `pages`:

```dart
WorkspaceHealthPage(viewModel: GetIt.I<WorkspaceHealthViewModel>()),
```

Add a side navigation destination:

```dart
_PlayfulNavigationDestination(
  icon: Icons.storage,
  label: 'Workspace',
),
```

Add a bottom navigation item:

```dart
BottomNavigationBarItem(
  icon: const Icon(Icons.storage),
  label: 'Workspace',
),
```

- [ ] **Step 7: Run widget test**

Run: `flutter test test/ui/workspace_health/workspace_health_page_test.dart`

Expected: PASS.

## Task 8: Verification and Implementation Notes

**Files:**
- Modify if needed: `docs/superpowers/plans/2026-05-21-novel-workspace-data-foundation.md`

- [ ] **Step 1: Run targeted workspace tests**

Run:

```powershell
flutter test test/data/workspace test/ui/workspace_health
```

Expected: all workspace and workspace health tests PASS.

- [ ] **Step 2: Run existing affected data tests**

Run:

```powershell
flutter test test/data/models test/data/services test/data/use_cases
```

Expected: existing data model, service, and use-case tests PASS.

- [ ] **Step 3: Run analyzer**

Run:

```powershell
flutter analyze
```

Expected: no new analyzer errors.

- [ ] **Step 4: Commit or record non-git status**

Run:

```powershell
git status --short
```

Expected in a git checkout: changed workspace files are visible and ready to commit.

Expected in `C:\Users\admin\Downloads\NAI_NEW` today: `fatal: not a git repository (or any of the parent directories): .git`. In that case, record the changed files in the final implementation summary instead of committing.

## Self-Review

Spec coverage:

- Visible workspace directory: Task 2.
- Workspace schema models: Task 1.
- Validation rules: Task 3.
- CasRand import/export compatibility: Task 4.
- KAMIA import: Task 5.
- Artist Chain Studio import: Task 6.
- Read-only health UI: Task 7.
- Verification: Task 8.

Marker scan:

- The plan contains no deferred work markers, empty steps, or vague error handling instructions.

Type consistency:

- `WorkspaceService`, `WorkspaceValidator`, importer, adapter, and UI names match across tests and implementation steps.
