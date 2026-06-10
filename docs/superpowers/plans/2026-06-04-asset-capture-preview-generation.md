# Asset Capture Preview Generation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users save structured artist chains, characters, and outfits from any structured surface into the existing asset library, and generate asset-library-only preview images for artist chains and characters.

**Architecture:** Add one data-level capture contract, one capture persistence service, one preview generation service, and one reusable thin confirmation host. Pages only create `StudioAssetCaptureDraft` objects from already structured data; saving and merging stay centralized in services backed by `WorkspaceService`.

**Tech Stack:** Flutter/Dart, GetIt, existing workspace entities (`ArtistChain`, `CharacterEntry`, `WorkspaceOutfit`), `WorkspaceService`, `ProductionNaiAdapterService`, `ParamConfig`, Flutter widget tests.

---

## Source Spec

Read first: `docs/superpowers/specs/2026-06-04-asset-capture-preview-generation-design.md`.

The user-approved behavior is:

- Cross-page save-to-asset applies to already structured artist-chain, character, and outfit data.
- Ordinary prompt text is not a standalone save source. If a gallery or exhibition item only has `override_prompt`, show prompt tags as before and do not expose a save-to-asset action.
- Save uses a thin confirmation bar where the user can edit name, kind, note, merge target, and create-new vs merge.
- Saved characters and outfits must use the current `CharacterEntry` / `WorkspaceOutfit` system.
- Asset-library preview generation exists only in the asset library.
- Artist-chain preview uses a random character from the character library and includes scene/background terms.
- Character preview uses pure white background and no scene.
- Preview model is `nai-diffusion-4-5-full`.
- Preview size is randomly chosen from `832x1216`, `1024x1024`, `1216x832`.

## File Structure

Create:

- `lib/data/studio/models/studio_asset_capture.dart`  
  Data contract for capture source, draft, duplicate candidates, save plan, save result, and deterministic draft builders from script AI and workbench documents.

- `lib/data/studio/services/studio_asset_capture_service.dart`  
  Central save and merge service for `ArtistChain`, `CharacterEntry`, and `WorkspaceOutfit`.

- `lib/data/studio/services/studio_asset_preview_generation_service.dart`  
  Asset-library-only preview generation service using `ProductionNaiAdapterService` callbacks and `ParamConfig.getPayload()`.

- `lib/ui/studio_core/widgets/save_asset_confirm_bar.dart`  
  Thin confirmation bar UI. It edits draft metadata, duplicate target, and create/merge mode.

- `lib/ui/studio_core/widgets/studio_asset_capture_host.dart`  
  Reusable overlay host that pages can call through `StudioAssetCaptureHost.of(context).showDraft(draft)`.

- `test/data/studio/models/studio_asset_capture_test.dart`  
  Unit tests for draft builders and workbench-document extraction.

- `test/data/studio/services/studio_asset_capture_service_test.dart`  
  Unit tests for create and merge persistence.

- `test/data/studio/services/studio_asset_preview_generation_service_test.dart`  
  Unit tests for payload building, size selection, prompt composition, and image-ref persistence.

- `test/ui/studio_core/save_asset_confirm_bar_test.dart`  
  Widget tests for the thin confirmation bar.

Modify:

- `lib/main.dart`  
  Register `StudioAssetCaptureService` and `StudioAssetPreviewGenerationService`.

- `lib/ui/studio_shell/widgets/studio_shell_view.dart`  
  Wrap script, exhibition, gallery, and asset library pages in `StudioAssetCaptureHost`; pass preview service to `AssetLibraryPage`.

- `lib/ui/studio_shell/widgets/asset_library_page.dart`  
  Add preview-generation actions for artist chains and characters only.

- `lib/ui/studio_script/widgets/studio_script_page.dart`  
  Add save buttons beside AI extracted roles and artist-chain evidence.

- `lib/ui/studio_shell/widgets/studio_gallery_page.dart`  
  Add save buttons only for drafts extracted from `StudioGalleryRecord.document`.

- `lib/ui/studio_shell/widgets/script_exhibition_room_page.dart`  
  Add save buttons only for drafts extracted from the backing gallery record document.

---

### Task 1: Capture Contract and Structured Draft Builders

**Files:**

- Create: `lib/data/studio/models/studio_asset_capture.dart`
- Test: `test/data/studio/models/studio_asset_capture_test.dart`

- [ ] **Step 1: Write model tests first**

Create `test/data/studio/models/studio_asset_capture_test.dart` with these tests:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/studio/models/script_ai_role_extraction.dart';
import 'package:nai_casrand/data/studio/models/studio_asset_capture.dart';
import 'package:nai_casrand/data/studio/models/workbench_document.dart';

void main() {
  group('StudioAssetCaptureDrafts', () {
    test('builds an artist-chain draft from AI evidence', () {
      final draft = StudioAssetCaptureDrafts.artistFromAiEvidence(
        const ScriptAiArtistChainEvidence(
          label: 'soft cel stack',
          terms: ['artist:foo', 'artist:bar', 'soft shading'],
          evidenceTerms: ['artist:foo'],
        ),
        source: const StudioAssetCaptureSource(
          surface: 'script',
          label: 'AI role extraction',
          sourceId: 'chunk-1',
        ),
      );

      expect(draft.kind, StudioAssetCaptureKind.artistChain);
      expect(draft.name, 'soft cel stack');
      expect(draft.artistChain!.tags, ['artist:foo', 'artist:bar', 'soft shading']);
      expect(draft.artistChain!.artists.map((entry) => entry.name), ['foo', 'bar']);
      expect(draft.artistChain!.source.type, 'script');
    });

    test('builds a character draft from an extracted role using current character schema', () {
      final draft = StudioAssetCaptureDrafts.characterFromAiRole(
        const ScriptAiExtractedRole(
          sourceRoleId: 'role-a',
          displayName: 'Hero A',
          evidenceTerms: ['blue eyes', 'short hair'],
          stages: [
            ScriptAiExtractedStage(
              stageId: 'base',
              label: 'school',
              identity: 'blue eyes, short hair',
              upperBody: 'white shirt',
              lowerBody: 'pleated skirt',
              upperClothing: 'navy blazer',
              lowerClothing: 'black socks',
            ),
          ],
        ),
        source: const StudioAssetCaptureSource(
          surface: 'script',
          label: 'AI role extraction',
          sourceId: 'role-a',
        ),
      );

      final character = draft.character!;
      expect(draft.kind, StudioAssetCaptureKind.character);
      expect(character.name, 'Hero A');
      expect(character.traits.frontFull, 'blue eyes, short hair');
      expect(character.identityTags, ['blue eyes', 'short hair']);
      expect(character.outfits.single.name, 'school');
      expect(character.outfits.single.partTags.upperBodyTags, ['white shirt']);
      expect(character.outfits.single.partTags.lowerClothingTags, ['black socks']);
      expect(character.defaultOutfitId, character.outfits.single.id);
    });

    test('extracts character and artist drafts from structured workbench document fields', () {
      final document = WorkbenchDocument.fromPayloadJson({
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
          'strs': ['artist:alpha, watercolor, market street'],
          'prompts': <Object>[],
          'enabled': true,
        },
        'character_config': [
          {
            'name': 'Gallery Girl',
            'positions': <Object>[],
            'positivePromptConfig': {
              'selectionMethod': 'all',
              'shuffled': false,
              'prob': 0.0,
              'num': 1,
              'randomBracketsUpper': 0,
              'randomBracketsLower': 0,
              'type': 'str',
              'comment': 'character',
              'filter': '',
              'strs': ['green eyes, bob cut'],
              'prompts': <Object>[],
              'enabled': true,
            },
            'negativePrompt': '',
            'enabled': true,
          },
        ],
        'saved_config': <Object>[],
        'param_config': <String, Object>{},
      });

      final drafts = StudioAssetCaptureDrafts.fromWorkbenchDocument(
        document,
        source: const StudioAssetCaptureSource(
          surface: 'gallery',
          label: 'Gallery item',
          sourceId: 'record-1',
        ),
      );

      expect(drafts.map((draft) => draft.kind), [
        StudioAssetCaptureKind.character,
        StudioAssetCaptureKind.artistChain,
      ]);
      expect(drafts.first.character!.name, 'Gallery Girl');
      expect(drafts.last.artistChain!.tags, ['artist:alpha']);
      expect(drafts.last.artistChain!.styleTags, ['watercolor']);
      expect(drafts.last.artistChain!.prompt, 'artist:alpha, watercolor');
    });

    test('ignores override prompt when structured fields do not contain asset data', () {
      final document = WorkbenchDocument.fromPayloadJson({
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
          'strs': <Object>[],
          'prompts': <Object>[],
          'enabled': true,
        },
        'character_config': <Object>[],
        'saved_config': <Object>[],
        'param_config': <String, Object>{},
        'override_prompt': 'artist:only-in-plain-text, city',
      });

      final drafts = StudioAssetCaptureDrafts.fromWorkbenchDocument(
        document,
        source: const StudioAssetCaptureSource(
          surface: 'gallery',
          label: 'Gallery item',
          sourceId: 'record-2',
        ),
      );

      expect(drafts, isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run tests and confirm missing file failure**

Run:

```powershell
flutter test --no-pub test/data/studio/models/studio_asset_capture_test.dart -r expanded
```

Expected: fails because `package:nai_casrand/data/studio/models/studio_asset_capture.dart` does not exist.

- [ ] **Step 3: Create the capture model and builders**

Create `lib/data/studio/models/studio_asset_capture.dart`:

```dart
import 'package:nai_casrand/data/models/character_config.dart';
import 'package:nai_casrand/data/models/prompt_config.dart';
import 'package:nai_casrand/data/studio/models/script_ai_role_extraction.dart';
import 'package:nai_casrand/data/studio/models/workbench_document.dart';
import 'package:nai_casrand/data/studio/tools/stable_id.dart';
import 'package:nai_casrand/data/workspace/models/workspace_entities.dart';

enum StudioAssetCaptureKind {
  artistChain,
  character,
  outfit,
}

extension StudioAssetCaptureKindLabel on StudioAssetCaptureKind {
  String get storageKey => switch (this) {
        StudioAssetCaptureKind.artistChain => 'artist-chain',
        StudioAssetCaptureKind.character => 'character',
        StudioAssetCaptureKind.outfit => 'outfit',
      };

  String get label => switch (this) {
        StudioAssetCaptureKind.artistChain => 'artist chain',
        StudioAssetCaptureKind.character => 'character',
        StudioAssetCaptureKind.outfit => 'outfit',
      };
}

class StudioAssetCaptureSource {
  final String surface;
  final String label;
  final String? sourceId;
  final String? path;

  const StudioAssetCaptureSource({
    required this.surface,
    required this.label,
    this.sourceId,
    this.path,
  });

  SourceRef toSourceRef() {
    return SourceRef(
      type: surface.trim().isEmpty ? 'structured_capture' : surface.trim(),
      id: _blankToNull(sourceId),
      path: _blankToNull(path),
    );
  }
}

class StudioAssetDuplicateCandidate {
  final StudioAssetCaptureKind kind;
  final String id;
  final String name;
  final String summary;

  const StudioAssetDuplicateCandidate({
    required this.kind,
    required this.id,
    required this.name,
    required this.summary,
  });
}

class StudioAssetCapturePlan {
  final StudioAssetCaptureDraft draft;
  final List<StudioAssetDuplicateCandidate> candidates;

  const StudioAssetCapturePlan({
    required this.draft,
    this.candidates = const [],
  });

  bool get hasCandidates => candidates.isNotEmpty;
}

class StudioAssetCaptureResult {
  final StudioAssetCaptureKind kind;
  final String savedId;
  final String name;
  final bool merged;

  const StudioAssetCaptureResult({
    required this.kind,
    required this.savedId,
    required this.name,
    required this.merged,
  });
}

class StudioAssetCaptureDraft {
  final StudioAssetCaptureKind kind;
  final String name;
  final String note;
  final StudioAssetCaptureSource source;
  final ArtistChain? artistChain;
  final CharacterEntry? character;
  final WorkspaceOutfit? outfit;
  final String? parentCharacterId;

  const StudioAssetCaptureDraft._({
    required this.kind,
    required this.name,
    required this.note,
    required this.source,
    this.artistChain,
    this.character,
    this.outfit,
    this.parentCharacterId,
  });

  factory StudioAssetCaptureDraft.artistChain({
    required ArtistChain artistChain,
    required StudioAssetCaptureSource source,
    String? name,
    String note = '',
  }) {
    return StudioAssetCaptureDraft._(
      kind: StudioAssetCaptureKind.artistChain,
      name: _firstText([name, artistChain.name, 'Artist chain']),
      note: note,
      source: source,
      artistChain: artistChain,
    );
  }

  factory StudioAssetCaptureDraft.character({
    required CharacterEntry character,
    required StudioAssetCaptureSource source,
    String? name,
    String note = '',
  }) {
    return StudioAssetCaptureDraft._(
      kind: StudioAssetCaptureKind.character,
      name: _firstText([name, character.name, 'Character']),
      note: note,
      source: source,
      character: character,
    );
  }

  factory StudioAssetCaptureDraft.outfit({
    required WorkspaceOutfit outfit,
    required String parentCharacterId,
    required StudioAssetCaptureSource source,
    String? name,
    String note = '',
  }) {
    return StudioAssetCaptureDraft._(
      kind: StudioAssetCaptureKind.outfit,
      name: _firstText([name, outfit.name, 'Outfit']),
      note: note,
      source: source,
      outfit: outfit,
      parentCharacterId: parentCharacterId,
    );
  }

  StudioAssetCaptureDraft copyWith({
    String? name,
    String? note,
    StudioAssetCaptureKind? kind,
    String? parentCharacterId,
  }) {
    final nextKind = kind ?? this.kind;
    return StudioAssetCaptureDraft._(
      kind: nextKind,
      name: name ?? this.name,
      note: note ?? this.note,
      source: source,
      artistChain: nextKind == StudioAssetCaptureKind.artistChain ? artistChain : null,
      character: nextKind == StudioAssetCaptureKind.character ? character : null,
      outfit: nextKind == StudioAssetCaptureKind.outfit ? outfit : null,
      parentCharacterId: parentCharacterId ?? this.parentCharacterId,
    );
  }

  List<StudioAssetCaptureKind> get availableKinds {
    return [
      if (artistChain != null) StudioAssetCaptureKind.artistChain,
      if (character != null) StudioAssetCaptureKind.character,
      if (outfit != null) StudioAssetCaptureKind.outfit,
    ];
  }
}

class StudioAssetCaptureDrafts {
  const StudioAssetCaptureDrafts._();

  static StudioAssetCaptureDraft artistFromAiEvidence(
    ScriptAiArtistChainEvidence evidence, {
    required StudioAssetCaptureSource source,
  }) {
    final tags = _dedupeTags(evidence.terms);
    final artistNames = tags
        .where(_isArtistTag)
        .map(_stripArtistPrefix)
        .where((name) => name.isNotEmpty)
        .toList(growable: false);
    final name = _firstText([
      evidence.label,
      artistNames.join(' + '),
      'Artist chain',
    ]);
    final chain = ArtistChain(
      id: stableIdFromText(
        prefix: 'artist-chain',
        label: name,
        text: 'ai-artist:${source.surface}:${source.sourceId}:$tags',
      ),
      name: name,
      tags: tags,
      prompt: _joinTags(tags),
      styleTags: _dedupeTags(tags.where((tag) => !_isArtistTag(tag))),
      artists: [
        for (final artist in artistNames) ArtistEntry(name: artist),
      ],
      source: source.toSourceRef(),
      note: _joinTags(evidence.evidenceTerms),
    );
    return StudioAssetCaptureDraft.artistChain(
      artistChain: chain,
      source: source,
      name: name,
    );
  }

  static StudioAssetCaptureDraft characterFromAiRole(
    ScriptAiExtractedRole role, {
    required StudioAssetCaptureSource source,
  }) {
    final name = _firstText([role.displayName, role.sourceRoleId, 'Character']);
    final firstStage = role.stages.isEmpty ? null : role.stages.first;
    final identityTags = _dedupeTags([
      if (firstStage != null) ..._splitTags(firstStage.identity),
      ...role.evidenceTerms,
    ]);
    final traits = ViewVariantTexts(
      frontFull: _joinTags(identityTags),
      frontUpper: firstStage == null ? null : _emptyToNull(firstStage.upperBody),
      frontLower: firstStage == null ? null : _emptyToNull(firstStage.lowerBody),
    );
    final outfits = [
      for (final (index, stage) in role.stages.indexed)
        if (_stageHasOutfitTerms(stage))
          WorkspaceOutfit(
            id: stableIdFromText(
              prefix: 'outfit',
              label: _firstText([stage.label, 'outfit-${index + 1}']),
              text: 'ai-role-outfit:${role.sourceRoleId}:${stage.stageId}:${stage.toJson()}',
            ),
            name: _firstText([stage.label, 'Outfit ${index + 1}']),
            tags: ViewVariantTexts(
              frontFull: _joinTags([
                ..._splitTags(stage.upperBody),
                ..._splitTags(stage.lowerBody),
                ..._splitTags(stage.upperClothing),
                ..._splitTags(stage.lowerClothing),
              ]),
              frontUpper: _emptyToNull(_joinTags([
                ..._splitTags(stage.upperBody),
                ..._splitTags(stage.upperClothing),
              ])),
              frontLower: _emptyToNull(_joinTags([
                ..._splitTags(stage.lowerBody),
                ..._splitTags(stage.lowerClothing),
              ])),
            ),
            partTags: WorkspaceOutfitPartTags(
              upperBodyTags: _splitTags(stage.upperBody),
              upperClothingTags: _splitTags(stage.upperClothing),
              lowerBodyTags: _splitTags(stage.lowerBody),
              lowerClothingTags: _splitTags(stage.lowerClothing),
            ),
            note: _joinTags(stage.evidenceTerms),
          ),
    ];
    final character = CharacterEntry(
      id: stableIdFromText(
        prefix: 'character',
        label: name,
        text: 'ai-role:${role.sourceRoleId}:${role.toJson()}',
      ),
      name: name,
      traits: traits,
      outfits: List.unmodifiable(outfits),
      defaultOutfitId: outfits.isEmpty ? null : outfits.first.id,
      source: source.toSourceRef(),
      note: _joinTags(role.warnings),
      identityTags: identityTags,
      aliases: _dedupeTags([role.sourceRoleId]),
      recastNotes: _joinTags(role.unassignedTerms.map((term) => term.term)),
    );
    return StudioAssetCaptureDraft.character(
      character: character,
      source: source,
      name: name,
    );
  }

  static List<StudioAssetCaptureDraft> fromWorkbenchDocument(
    WorkbenchDocument document, {
    required StudioAssetCaptureSource source,
  }) {
    final drafts = <StudioAssetCaptureDraft>[];
    final characterJson = document.payload['character_config'];
    if (characterJson is List) {
      for (final (index, item) in characterJson.indexed) {
        if (item is! Map) continue;
        final config = CharacterConfig.fromJson(item.cast<String, dynamic>());
        final rows = _flattenPromptConfig(config.positivePromptConfig);
        if (rows.isEmpty) continue;
        final tags = _dedupeTags(rows.expand(_splitTags));
        final name = _firstText([config.name, 'Document character ${index + 1}']);
        final character = CharacterEntry(
          id: stableIdFromText(
            prefix: 'character',
            label: name,
            text: 'workbench-character:${source.sourceId}:$index:${config.toJson()}',
          ),
          name: name,
          traits: ViewVariantTexts(frontFull: _joinTags(tags)),
          identityTags: tags,
          source: source.toSourceRef(),
          note: config.negativePrompt.trim().isEmpty
              ? ''
              : 'negative: ${config.negativePrompt.trim()}',
        );
        drafts.add(
          StudioAssetCaptureDraft.character(
            character: character,
            source: source,
            name: name,
          ),
        );
      }
    }

    final promptRows = <String>[];
    final rootPromptJson = document.payload['prompt_config'];
    if (rootPromptJson is Map) {
      promptRows.addAll(
        _flattenPromptConfig(
          PromptConfig.fromJson(rootPromptJson.cast<String, dynamic>()),
        ),
      );
    }
    final savedPromptJson = document.payload['saved_config'];
    if (savedPromptJson is List) {
      for (final item in savedPromptJson) {
        if (item is! Map) continue;
        promptRows.addAll(
          _flattenPromptConfig(PromptConfig.fromJson(item.cast<String, dynamic>())),
        );
      }
    }
    final promptTags = _dedupeTags(promptRows.expand(_splitTags));
    final artistTags = _dedupeTags(promptTags.where(_isArtistTag));
    if (artistTags.isNotEmpty) {
      final styleTags = _dedupeTags(promptTags.where((tag) => !_isArtistTag(tag)));
      final artistNames = artistTags.map(_stripArtistPrefix).toList(growable: false);
      final name = _firstText([
        artistNames.join(' + '),
        '${source.label} artist chain',
      ]);
      drafts.add(
        StudioAssetCaptureDraft.artistChain(
          source: source,
          name: name,
          artistChain: ArtistChain(
            id: stableIdFromText(
              prefix: 'artist-chain',
              label: name,
              text: 'workbench-artist:${source.sourceId}:$artistTags:$styleTags',
            ),
            name: name,
            tags: artistTags,
            styleTags: styleTags,
            prompt: _joinTags([...artistTags, ...styleTags]),
            artists: [
              for (final artist in artistNames) ArtistEntry(name: artist),
            ],
            source: source.toSourceRef(),
          ),
        ),
      );
    }

    return List.unmodifiable(drafts);
  }
}

List<String> _flattenPromptConfig(PromptConfig config) {
  if (!config.enabled) return const [];
  final rows = <String>[
    ...PromptConfig.normalizeStrRows(config.strs),
    for (final child in config.prompts) ..._flattenPromptConfig(child),
  ];
  return _dedupeTags(rows);
}

List<String> _splitTags(String value) {
  return value
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split(RegExp(r'[,\n]'))
      .map((tag) => tag.trim())
      .where((tag) => tag.isNotEmpty)
      .toList(growable: false);
}

List<String> _dedupeTags(Iterable<String> values) {
  final seen = <String>{};
  final result = <String>[];
  for (final value in values) {
    final cleaned = value.trim();
    if (cleaned.isEmpty) continue;
    final key = cleaned.toLowerCase();
    if (!seen.add(key)) continue;
    result.add(cleaned);
  }
  return List.unmodifiable(result);
}

bool _isArtistTag(String value) {
  return value.trim().toLowerCase().startsWith('artist:');
}

String _stripArtistPrefix(String value) {
  final trimmed = value.trim();
  final index = trimmed.indexOf(':');
  return index < 0 ? trimmed : trimmed.substring(index + 1).trim();
}

String _joinTags(Iterable<String> values) {
  return values.map((value) => value.trim()).where((value) => value.isNotEmpty).join(', ');
}

String _firstText(Iterable<String?> values) {
  for (final value in values) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isNotEmpty) return trimmed;
  }
  return 'Untitled';
}

String? _emptyToNull(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

String? _blankToNull(String? value) {
  final trimmed = value?.trim() ?? '';
  return trimmed.isEmpty ? null : trimmed;
}

bool _stageHasOutfitTerms(ScriptAiExtractedStage stage) {
  return [
    stage.upperBody,
    stage.lowerBody,
    stage.upperClothing,
    stage.lowerClothing,
  ].any((value) => value.trim().isNotEmpty);
}
```

- [ ] **Step 4: Run model tests**

Run:

```powershell
flutter test --no-pub test/data/studio/models/studio_asset_capture_test.dart -r expanded
```

Expected: all tests pass.

- [ ] **Step 5: Git-enabled checkpoint**

Skip this step while Beads stealth/no-git mode is active. If the user enables git operations, run:

```powershell
git add lib/data/studio/models/studio_asset_capture.dart test/data/studio/models/studio_asset_capture_test.dart
git commit -m "feat: add structured asset capture drafts"
```

Expected: commit succeeds.

---

### Task 2: Capture Persistence Service

**Files:**

- Create: `lib/data/studio/services/studio_asset_capture_service.dart`
- Test: `test/data/studio/services/studio_asset_capture_service_test.dart`

- [ ] **Step 1: Write service tests first**

Create `test/data/studio/services/studio_asset_capture_service_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/studio/models/studio_asset_capture.dart';
import 'package:nai_casrand/data/studio/services/studio_asset_capture_service.dart';
import 'package:nai_casrand/data/workspace/models/workspace_entities.dart';
import 'package:nai_casrand/data/workspace/workspace_service.dart';

void main() {
  late Directory tempDir;
  late WorkspaceService workspace;
  late StudioAssetCaptureService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('asset-capture-service-');
    workspace = WorkspaceService();
    await workspace.createWorkspace(tempDir.path, name: 'Test Workspace');
    service = StudioAssetCaptureService(workspaceService: workspace);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('creates a new artist chain when no duplicate exists', () async {
    final draft = StudioAssetCaptureDraft.artistChain(
      source: const StudioAssetCaptureSource(surface: 'script', label: 'Script'),
      artistChain: const ArtistChain(
        id: 'artist-chain-new',
        name: 'Foo Stack',
        tags: ['artist:foo'],
        prompt: 'artist:foo',
      ),
    );

    final plan = await service.previewSave(draft);
    expect(plan.hasCandidates, isFalse);

    final result = await service.save(draft);
    expect(result.savedId, 'artist-chain-new');
    expect(result.merged, isFalse);

    final chains = await workspace.loadArtistChains();
    expect(chains.single.name, 'Foo Stack');
    expect(chains.single.tags, ['artist:foo']);
  });

  test('offers and merges duplicate artist chains by normalized tags', () async {
    await workspace.saveArtistChains([
      const ArtistChain(
        id: 'existing',
        name: 'Foo',
        tags: ['artist:foo'],
        prompt: 'artist:foo',
        styleTags: ['soft shading'],
      ),
    ]);

    final draft = StudioAssetCaptureDraft.artistChain(
      source: const StudioAssetCaptureSource(surface: 'gallery', label: 'Gallery'),
      artistChain: const ArtistChain(
        id: 'incoming',
        name: 'Foo incoming',
        tags: ['artist:foo'],
        prompt: 'artist:foo, watercolor',
        styleTags: ['watercolor'],
      ),
      note: 'from gallery',
    );

    final plan = await service.previewSave(draft);
    expect(plan.candidates.single.id, 'existing');

    final result = await service.save(draft, targetId: 'existing');
    expect(result.savedId, 'existing');
    expect(result.merged, isTrue);

    final chains = await workspace.loadArtistChains();
    expect(chains.single.styleTags, ['soft shading', 'watercolor']);
    expect(chains.single.note, contains('from gallery'));
  });

  test('creates a character using CharacterEntry fields', () async {
    final draft = StudioAssetCaptureDraft.character(
      source: const StudioAssetCaptureSource(surface: 'script', label: 'Script'),
      character: const CharacterEntry(
        id: 'character-hero',
        name: 'Hero',
        traits: ViewVariantTexts(frontFull: 'blue eyes, short hair'),
        identityTags: ['blue eyes', 'short hair'],
      ),
    );

    await service.save(draft);

    final characters = await workspace.loadCharacters();
    expect(characters.single.id, 'character-hero');
    expect(characters.single.identityTags, ['blue eyes', 'short hair']);
  });

  test('merges a character by target id and preserves existing outfits', () async {
    await workspace.saveCharacters([
      const CharacterEntry(
        id: 'char-a',
        name: 'Hero',
        traits: ViewVariantTexts(frontFull: 'blue eyes'),
        identityTags: ['blue eyes'],
        outfits: [
          WorkspaceOutfit(
            id: 'outfit-old',
            name: 'Old',
            tags: ViewVariantTexts(frontFull: 'old coat'),
          ),
        ],
      ),
    ]);

    final draft = StudioAssetCaptureDraft.character(
      source: const StudioAssetCaptureSource(surface: 'gallery', label: 'Gallery'),
      character: const CharacterEntry(
        id: 'char-incoming',
        name: 'Hero',
        traits: ViewVariantTexts(frontFull: 'short hair'),
        identityTags: ['short hair'],
        outfits: [
          WorkspaceOutfit(
            id: 'outfit-new',
            name: 'New',
            tags: ViewVariantTexts(frontFull: 'new jacket'),
          ),
        ],
      ),
      note: 'gallery note',
    );

    final result = await service.save(draft, targetId: 'char-a');
    expect(result.merged, isTrue);

    final character = (await workspace.loadCharacters()).single;
    expect(character.identityTags, ['blue eyes', 'short hair']);
    expect(character.outfits.map((outfit) => outfit.id), ['outfit-old', 'outfit-new']);
    expect(character.note, contains('gallery note'));
  });

  test('adds an outfit to its parent character', () async {
    await workspace.saveCharacters([
      const CharacterEntry(
        id: 'char-a',
        name: 'Hero',
        traits: ViewVariantTexts(frontFull: 'blue eyes'),
      ),
    ]);

    final draft = StudioAssetCaptureDraft.outfit(
      parentCharacterId: 'char-a',
      source: const StudioAssetCaptureSource(surface: 'script', label: 'Script'),
      outfit: const WorkspaceOutfit(
        id: 'outfit-school',
        name: 'School',
        tags: ViewVariantTexts(frontFull: 'school uniform'),
      ),
    );

    final result = await service.save(draft);
    expect(result.savedId, 'outfit-school');

    final character = (await workspace.loadCharacters()).single;
    expect(character.outfits.single.name, 'School');
    expect(character.defaultOutfitId, 'outfit-school');
  });
}
```

- [ ] **Step 2: Run tests and confirm missing service failure**

Run:

```powershell
flutter test --no-pub test/data/studio/services/studio_asset_capture_service_test.dart -r expanded
```

Expected: fails because `StudioAssetCaptureService` does not exist.

- [ ] **Step 3: Implement capture service**

Create `lib/data/studio/services/studio_asset_capture_service.dart`:

```dart
import 'package:nai_casrand/data/studio/models/studio_asset_capture.dart';
import 'package:nai_casrand/data/workspace/models/workspace_entities.dart';
import 'package:nai_casrand/data/workspace/workspace_service.dart';

class StudioAssetCaptureService {
  final WorkspaceService workspaceService;

  const StudioAssetCaptureService({required this.workspaceService});

  Future<StudioAssetCapturePlan> previewSave(StudioAssetCaptureDraft draft) async {
    final candidates = switch (draft.kind) {
      StudioAssetCaptureKind.artistChain => await _artistCandidates(draft.artistChain!),
      StudioAssetCaptureKind.character => await _characterCandidates(draft.character!),
      StudioAssetCaptureKind.outfit => await _outfitCandidates(draft),
    };
    return StudioAssetCapturePlan(draft: draft, candidates: candidates);
  }

  Future<StudioAssetCaptureResult> save(
    StudioAssetCaptureDraft draft, {
    String? targetId,
    bool forceNew = false,
    String? nameOverride,
    String? noteOverride,
  }) async {
    final namedDraft = _renameDraft(
      draft,
      name: nameOverride,
      note: noteOverride,
    );
    return switch (namedDraft.kind) {
      StudioAssetCaptureKind.artistChain => _saveArtistChain(
          namedDraft,
          targetId: forceNew ? null : targetId,
        ),
      StudioAssetCaptureKind.character => _saveCharacter(
          namedDraft,
          targetId: forceNew ? null : targetId,
        ),
      StudioAssetCaptureKind.outfit => _saveOutfit(
          namedDraft,
          targetId: forceNew ? null : targetId,
        ),
    };
  }

  StudioAssetCaptureDraft _renameDraft(
    StudioAssetCaptureDraft draft, {
    String? name,
    String? note,
  }) {
    final cleanName = name?.trim();
    final cleanNote = note?.trim();
    if ((cleanName == null || cleanName.isEmpty) &&
        (cleanNote == null || cleanNote.isEmpty)) {
      return draft;
    }
    return draft.copyWith(
      name: cleanName == null || cleanName.isEmpty ? draft.name : cleanName,
      note: cleanNote == null ? draft.note : cleanNote,
    );
  }

  Future<List<StudioAssetDuplicateCandidate>> _artistCandidates(
    ArtistChain incoming,
  ) async {
    final incomingKey = _tagKey([...incoming.tags, ...incoming.styleTags]);
    final incomingPrompt = _normalizeText(incoming.prompt);
    final chains = await workspaceService.loadArtistChains();
    return [
      for (final chain in chains)
        if (_tagKey([...chain.tags, ...chain.styleTags]) == incomingKey ||
            (incomingPrompt.isNotEmpty && _normalizeText(chain.prompt) == incomingPrompt))
          StudioAssetDuplicateCandidate(
            kind: StudioAssetCaptureKind.artistChain,
            id: chain.id,
            name: chain.name,
            summary: _joinDisplay([...chain.tags, ...chain.styleTags]),
          ),
    ];
  }

  Future<List<StudioAssetDuplicateCandidate>> _characterCandidates(
    CharacterEntry incoming,
  ) async {
    final nameKey = _normalizeText(incoming.name);
    final identityKey = _tagKey(incoming.identityTags);
    final characters = await workspaceService.loadCharacters();
    return [
      for (final character in characters)
        if (_normalizeText(character.name) == nameKey ||
            (identityKey.isNotEmpty && _tagKey(character.identityTags) == identityKey))
          StudioAssetDuplicateCandidate(
            kind: StudioAssetCaptureKind.character,
            id: character.id,
            name: character.name,
            summary: _joinDisplay(character.identityTags),
          ),
    ];
  }

  Future<List<StudioAssetDuplicateCandidate>> _outfitCandidates(
    StudioAssetCaptureDraft draft,
  ) async {
    final parentId = draft.parentCharacterId;
    if (parentId == null || parentId.trim().isEmpty) return const [];
    final incoming = draft.outfit!;
    final nameKey = _normalizeText(incoming.name);
    final tagKey = _normalizeText(incoming.tags.frontFull);
    final characters = await workspaceService.loadCharacters();
    final parent = characters.where((character) => character.id == parentId).firstOrNull;
    if (parent == null) return const [];
    return [
      for (final outfit in parent.outfits)
        if (_normalizeText(outfit.name) == nameKey ||
            (tagKey.isNotEmpty && _normalizeText(outfit.tags.frontFull) == tagKey))
          StudioAssetDuplicateCandidate(
            kind: StudioAssetCaptureKind.outfit,
            id: outfit.id,
            name: outfit.name,
            summary: outfit.tags.frontFull,
          ),
    ];
  }

  Future<StudioAssetCaptureResult> _saveArtistChain(
    StudioAssetCaptureDraft draft, {
    String? targetId,
  }) async {
    final incoming = _namedArtistChain(draft.artistChain!, draft);
    final chains = [...await workspaceService.loadArtistChains()];
    final targetIndex = targetId == null ? -1 : chains.indexWhere((chain) => chain.id == targetId);
    if (targetIndex < 0) {
      chains.add(incoming);
      await workspaceService.saveArtistChains(chains);
      return StudioAssetCaptureResult(
        kind: StudioAssetCaptureKind.artistChain,
        savedId: incoming.id,
        name: incoming.name,
        merged: false,
      );
    }
    final merged = _mergeArtistChain(chains[targetIndex], incoming);
    chains[targetIndex] = merged;
    await workspaceService.saveArtistChains(chains);
    return StudioAssetCaptureResult(
      kind: StudioAssetCaptureKind.artistChain,
      savedId: merged.id,
      name: merged.name,
      merged: true,
    );
  }

  Future<StudioAssetCaptureResult> _saveCharacter(
    StudioAssetCaptureDraft draft, {
    String? targetId,
  }) async {
    final incoming = _namedCharacter(draft.character!, draft);
    final characters = [...await workspaceService.loadCharacters()];
    final targetIndex =
        targetId == null ? -1 : characters.indexWhere((character) => character.id == targetId);
    if (targetIndex < 0) {
      characters.add(incoming);
      await workspaceService.saveCharacters(characters);
      return StudioAssetCaptureResult(
        kind: StudioAssetCaptureKind.character,
        savedId: incoming.id,
        name: incoming.name,
        merged: false,
      );
    }
    final merged = _mergeCharacter(characters[targetIndex], incoming);
    characters[targetIndex] = merged;
    await workspaceService.saveCharacters(characters);
    return StudioAssetCaptureResult(
      kind: StudioAssetCaptureKind.character,
      savedId: merged.id,
      name: merged.name,
      merged: true,
    );
  }

  Future<StudioAssetCaptureResult> _saveOutfit(
    StudioAssetCaptureDraft draft, {
    String? targetId,
  }) async {
    final parentId = draft.parentCharacterId?.trim() ?? '';
    if (parentId.isEmpty) {
      throw const StudioAssetCaptureException('Outfit capture requires a parent character.');
    }
    final incoming = _namedOutfit(draft.outfit!, draft);
    final characters = [...await workspaceService.loadCharacters()];
    final parentIndex = characters.indexWhere((character) => character.id == parentId);
    if (parentIndex < 0) {
      throw StudioAssetCaptureException('Parent character "$parentId" was not found.');
    }
    final parent = characters[parentIndex];
    final outfits = [...parent.outfits];
    final targetIndex = targetId == null ? -1 : outfits.indexWhere((outfit) => outfit.id == targetId);
    final WorkspaceOutfit saved;
    final bool merged;
    if (targetIndex < 0) {
      outfits.add(incoming);
      saved = incoming;
      merged = false;
    } else {
      saved = _mergeOutfit(outfits[targetIndex], incoming);
      outfits[targetIndex] = saved;
      merged = true;
    }
    characters[parentIndex] = parent.copyWith(
      outfits: List.unmodifiable(outfits),
      defaultOutfitId: parent.defaultOutfitId ?? saved.id,
    );
    await workspaceService.saveCharacters(characters);
    return StudioAssetCaptureResult(
      kind: StudioAssetCaptureKind.outfit,
      savedId: saved.id,
      name: saved.name,
      merged: merged,
    );
  }

  ArtistChain _namedArtistChain(ArtistChain chain, StudioAssetCaptureDraft draft) {
    return chain.copyWith(
      name: draft.name.trim().isEmpty ? chain.name : draft.name.trim(),
      note: _mergeText(chain.note, draft.note),
      source: draft.source.toSourceRef(),
    );
  }

  CharacterEntry _namedCharacter(CharacterEntry character, StudioAssetCaptureDraft draft) {
    return character.copyWith(
      name: draft.name.trim().isEmpty ? character.name : draft.name.trim(),
      note: _mergeText(character.note, draft.note),
      source: draft.source.toSourceRef(),
    );
  }

  WorkspaceOutfit _namedOutfit(WorkspaceOutfit outfit, StudioAssetCaptureDraft draft) {
    return WorkspaceOutfit(
      id: outfit.id,
      name: draft.name.trim().isEmpty ? outfit.name : draft.name.trim(),
      tags: outfit.tags,
      partTags: outfit.partTags,
      imageRefs: outfit.imageRefs,
      note: _mergeText(outfit.note, draft.note),
    );
  }

  ArtistChain _mergeArtistChain(ArtistChain existing, ArtistChain incoming) {
    return existing.copyWith(
      tags: _mergeList(existing.tags, incoming.tags),
      prompt: existing.prompt.trim().isEmpty ? incoming.prompt : existing.prompt,
      styleTags: _mergeList(existing.styleTags, incoming.styleTags),
      imageRefs: _mergeList(existing.imageRefs, incoming.imageRefs),
      note: _mergeText(existing.note, incoming.note),
      artists: _mergeArtists(existing.artists, incoming.artists),
      globalNegatives: _mergeWeighted(existing.globalNegatives, incoming.globalNegatives),
      styleHintsWeighted: _mergeWeighted(existing.styleHintsWeighted, incoming.styleHintsWeighted),
      vibeRefs: _mergeVibes(existing.vibeRefs, incoming.vibeRefs),
    );
  }

  CharacterEntry _mergeCharacter(CharacterEntry existing, CharacterEntry incoming) {
    return existing.copyWith(
      traits: ViewVariantTexts(
        frontFull: _mergePrompt(existing.traits.frontFull, incoming.traits.frontFull),
        frontCowboy: existing.traits.frontCowboy ?? incoming.traits.frontCowboy,
        frontUpper: existing.traits.frontUpper ?? incoming.traits.frontUpper,
        frontLower: existing.traits.frontLower ?? incoming.traits.frontLower,
        backFull: existing.traits.backFull ?? incoming.traits.backFull,
        backCowboy: existing.traits.backCowboy ?? incoming.traits.backCowboy,
        backUpper: existing.traits.backUpper ?? incoming.traits.backUpper,
        backLower: existing.traits.backLower ?? incoming.traits.backLower,
      ),
      outfits: _mergeOutfitLists(existing.outfits, incoming.outfits),
      defaultOutfitId: existing.defaultOutfitId ?? incoming.defaultOutfitId,
      imageRefs: _mergeList(existing.imageRefs, incoming.imageRefs),
      note: _mergeText(existing.note, incoming.note),
      anchorTags: _mergeList(existing.anchorTags, incoming.anchorTags),
      identityTags: _mergeList(existing.identityTags, incoming.identityTags),
      conflictTags: _mergeList(existing.conflictTags, incoming.conflictTags),
      defaultCenters: existing.defaultCenters.isEmpty ? incoming.defaultCenters : existing.defaultCenters,
      aliases: _mergeList(existing.aliases, incoming.aliases),
      recastNotes: _mergeText(existing.recastNotes, incoming.recastNotes),
    );
  }

  List<WorkspaceOutfit> _mergeOutfitLists(
    List<WorkspaceOutfit> existing,
    List<WorkspaceOutfit> incoming,
  ) {
    final result = [...existing];
    for (final outfit in incoming) {
      final index = result.indexWhere(
        (item) =>
            item.id == outfit.id ||
            _normalizeText(item.name) == _normalizeText(outfit.name) ||
            _normalizeText(item.tags.frontFull) == _normalizeText(outfit.tags.frontFull),
      );
      if (index < 0) {
        result.add(outfit);
      } else {
        result[index] = _mergeOutfit(result[index], outfit);
      }
    }
    return List.unmodifiable(result);
  }

  WorkspaceOutfit _mergeOutfit(WorkspaceOutfit existing, WorkspaceOutfit incoming) {
    return WorkspaceOutfit(
      id: existing.id,
      name: existing.name,
      tags: ViewVariantTexts(
        frontFull: _mergePrompt(existing.tags.frontFull, incoming.tags.frontFull),
        frontCowboy: existing.tags.frontCowboy ?? incoming.tags.frontCowboy,
        frontUpper: existing.tags.frontUpper ?? incoming.tags.frontUpper,
        frontLower: existing.tags.frontLower ?? incoming.tags.frontLower,
        backFull: existing.tags.backFull ?? incoming.tags.backFull,
        backCowboy: existing.tags.backCowboy ?? incoming.tags.backCowboy,
        backUpper: existing.tags.backUpper ?? incoming.tags.backUpper,
        backLower: existing.tags.backLower ?? incoming.tags.backLower,
      ),
      partTags: WorkspaceOutfitPartTags(
        upperBodyTags: _mergeList(existing.partTags.upperBodyTags, incoming.partTags.upperBodyTags),
        upperClothingTags:
            _mergeList(existing.partTags.upperClothingTags, incoming.partTags.upperClothingTags),
        lowerBodyTags: _mergeList(existing.partTags.lowerBodyTags, incoming.partTags.lowerBodyTags),
        lowerClothingTags:
            _mergeList(existing.partTags.lowerClothingTags, incoming.partTags.lowerClothingTags),
        weaponTags: _mergeList(existing.partTags.weaponTags, incoming.partTags.weaponTags),
      ),
      imageRefs: _mergeList(existing.imageRefs, incoming.imageRefs),
      note: _mergeText(existing.note, incoming.note),
    );
  }
}

class StudioAssetCaptureException implements Exception {
  final String message;

  const StudioAssetCaptureException(this.message);

  @override
  String toString() => message;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

List<String> _mergeList(List<String> first, List<String> second) {
  final seen = <String>{};
  final result = <String>[];
  for (final value in [...first, ...second]) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) continue;
    final key = trimmed.toLowerCase();
    if (!seen.add(key)) continue;
    result.add(trimmed);
  }
  return List.unmodifiable(result);
}

String _mergeText(String first, String second) {
  final a = first.trim();
  final b = second.trim();
  if (a.isEmpty) return b;
  if (b.isEmpty) return a;
  if (a.toLowerCase().contains(b.toLowerCase())) return a;
  return '$a\n$b';
}

String _mergePrompt(String first, String second) {
  return _joinDisplay(_mergeList(_splitTags(first), _splitTags(second)));
}

List<String> _splitTags(String value) {
  return value
      .split(RegExp(r'[,\n]'))
      .map((tag) => tag.trim())
      .where((tag) => tag.isNotEmpty)
      .toList(growable: false);
}

String _joinDisplay(Iterable<String> values) {
  return values.map((value) => value.trim()).where((value) => value.isNotEmpty).join(', ');
}

String _normalizeText(String value) {
  return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}

String _tagKey(Iterable<String> tags) {
  final normalized = tags.map(_normalizeText).where((tag) => tag.isNotEmpty).toSet().toList()..sort();
  return normalized.join('|');
}

List<ArtistEntry> _mergeArtists(List<ArtistEntry> first, List<ArtistEntry> second) {
  final byName = <String, ArtistEntry>{};
  for (final artist in [...first, ...second]) {
    final key = _normalizeText('${artist.prefix}${artist.name}');
    byName.putIfAbsent(key, () => artist);
  }
  return List.unmodifiable(byName.values);
}

List<WorkspaceWeightedTag> _mergeWeighted(
  List<WorkspaceWeightedTag> first,
  List<WorkspaceWeightedTag> second,
) {
  final byTag = <String, WorkspaceWeightedTag>{};
  for (final tag in [...first, ...second]) {
    byTag[_normalizeText(tag.tag)] = tag;
  }
  return List.unmodifiable(byTag.values);
}

List<WorkspaceVibeReference> _mergeVibes(
  List<WorkspaceVibeReference> first,
  List<WorkspaceVibeReference> second,
) {
  final byId = <String, WorkspaceVibeReference>{};
  for (final vibe in [...first, ...second]) {
    byId[vibe.id] = vibe;
  }
  return List.unmodifiable(byId.values);
}
```

- [ ] **Step 4: Run service tests**

Run:

```powershell
flutter test --no-pub test/data/studio/services/studio_asset_capture_service_test.dart -r expanded
```

Expected: all tests pass.

- [ ] **Step 5: Run model and service tests together**

Run:

```powershell
flutter test --no-pub test/data/studio/models/studio_asset_capture_test.dart test/data/studio/services/studio_asset_capture_service_test.dart -r expanded
```

Expected: both suites pass.

- [ ] **Step 6: Git-enabled checkpoint**

Skip this step while Beads stealth/no-git mode is active. If the user enables git operations, run:

```powershell
git add lib/data/studio/services/studio_asset_capture_service.dart test/data/studio/services/studio_asset_capture_service_test.dart
git commit -m "feat: save structured captures into assets"
```

Expected: commit succeeds.

---

### Task 3: Asset-Library Preview Generation Service

**Files:**

- Create: `lib/data/studio/services/studio_asset_preview_generation_service.dart`
- Test: `test/data/studio/services/studio_asset_preview_generation_service_test.dart`

- [ ] **Step 1: Write preview service tests first**

Create `test/data/studio/services/studio_asset_preview_generation_service_test.dart`:

```dart
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/studio/services/studio_asset_preview_generation_service.dart';
import 'package:nai_casrand/data/workspace/models/workspace_entities.dart';

void main() {
  test('generates an artist-chain preview with random character and scene terms', () async {
    final requests = <Map<String, dynamic>>[];
    var chains = [
      const ArtistChain(
        id: 'chain-a',
        name: 'Foo',
        tags: ['artist:foo'],
        prompt: 'artist:foo',
      ),
    ];
    final service = StudioAssetPreviewGenerationService(
      loadArtistChains: () async => chains,
      saveArtistChains: (next) async => chains = next,
      loadCharacters: () async => const [
        CharacterEntry(
          id: 'char-a',
          name: 'Hero',
          traits: ViewVariantTexts(frontFull: 'blue eyes, short hair'),
        ),
      ],
      saveCharacters: (_) async {},
      requestImage: (payload) async {
        requests.add(payload);
        return Uint8List.fromList([1, 2, 3]);
      },
      saveImage: (_, fileName) async => 'out/$fileName',
      randomInt: (max) => 0,
      now: () => DateTime.utc(2026, 6, 4, 1, 2, 3),
    );

    final result = await service.generateArtistChainPreview('chain-a');

    expect(result.imagePath, 'out/asset-preview-artist-chain-chain-a-20260604-010203.png');
    expect(chains.single.imageRefs, [result.imagePath]);
    expect(requests.single['model'], 'nai-diffusion-4-5-full');
    expect(requests.single['input'], contains('artist:foo'));
    expect(requests.single['input'], contains('blue eyes, short hair'));
    expect(requests.single['input'], contains('detailed background'));
    expect(requests.single['parameters']['width'], 832);
    expect(requests.single['parameters']['height'], 1216);
  });

  test('generates a character preview on pure white background', () async {
    final requests = <Map<String, dynamic>>[];
    var characters = [
      const CharacterEntry(
        id: 'char-a',
        name: 'Hero',
        traits: ViewVariantTexts(frontFull: 'blue eyes, short hair'),
      ),
    ];
    final service = StudioAssetPreviewGenerationService(
      loadArtistChains: () async => const [],
      saveArtistChains: (_) async {},
      loadCharacters: () async => characters,
      saveCharacters: (next) async => characters = next,
      requestImage: (payload) async {
        requests.add(payload);
        return Uint8List.fromList([4, 5, 6]);
      },
      saveImage: (_, fileName) async => 'out/$fileName',
      randomInt: (max) => max - 1,
      now: () => DateTime.utc(2026, 6, 4, 1, 2, 3),
    );

    await service.generateCharacterPreview('char-a');

    expect(characters.single.imageRefs.single, 'out/asset-preview-character-char-a-20260604-010203.png');
    expect(requests.single['input'], contains('plain white background'));
    expect(requests.single['input'], isNot(contains('detailed background')));
    expect(requests.single['parameters']['width'], 1216);
    expect(requests.single['parameters']['height'], 832);
  });
}
```

- [ ] **Step 2: Run tests and confirm missing service failure**

Run:

```powershell
flutter test --no-pub test/data/studio/services/studio_asset_preview_generation_service_test.dart -r expanded
```

Expected: fails because `StudioAssetPreviewGenerationService` does not exist.

- [ ] **Step 3: Implement preview generation service**

Create `lib/data/studio/services/studio_asset_preview_generation_service.dart`:

```dart
import 'dart:math';
import 'dart:typed_data';

import 'package:nai_casrand/core/constants/defaults.dart';
import 'package:nai_casrand/data/models/generation_size.dart';
import 'package:nai_casrand/data/models/param_config.dart';
import 'package:nai_casrand/data/workspace/models/workspace_entities.dart';

typedef StudioPreviewPayloadRequester = Future<Uint8List> Function(
  Map<String, dynamic> payload,
);
typedef StudioPreviewImageSaver = Future<String> Function(
  Uint8List bytes,
  String fileName,
);
typedef StudioPreviewArtistChainsLoader = Future<List<ArtistChain>> Function();
typedef StudioPreviewArtistChainsSaver = Future<void> Function(List<ArtistChain> chains);
typedef StudioPreviewCharactersLoader = Future<List<CharacterEntry>> Function();
typedef StudioPreviewCharactersSaver = Future<void> Function(List<CharacterEntry> characters);
typedef StudioPreviewRandomInt = int Function(int max);

class StudioAssetPreviewGenerationResult {
  final String assetId;
  final String imagePath;
  final Map<String, dynamic> payload;

  const StudioAssetPreviewGenerationResult({
    required this.assetId,
    required this.imagePath,
    required this.payload,
  });
}

class StudioAssetPreviewGenerationService {
  static const model = 'nai-diffusion-4-5-full';
  static const qualityPrompt = 'masterpiece, best quality, very aesthetic, absurdres';
  static const artistScenePrompt =
      'detailed background, environmental storytelling, atmospheric lighting, cinematic composition';
  static const characterWhitePrompt =
      'full body, standing, character reference, plain white background, no scenery';
  static const previewSizes = [
    GenerationSize(width: 832, height: 1216),
    GenerationSize(width: 1024, height: 1024),
    GenerationSize(width: 1216, height: 832),
  ];

  final StudioPreviewArtistChainsLoader loadArtistChains;
  final StudioPreviewArtistChainsSaver saveArtistChains;
  final StudioPreviewCharactersLoader loadCharacters;
  final StudioPreviewCharactersSaver saveCharacters;
  final StudioPreviewPayloadRequester requestImage;
  final StudioPreviewImageSaver saveImage;
  final StudioPreviewRandomInt randomInt;
  final DateTime Function() now;

  StudioAssetPreviewGenerationService({
    required this.loadArtistChains,
    required this.saveArtistChains,
    required this.loadCharacters,
    required this.saveCharacters,
    required this.requestImage,
    required this.saveImage,
    StudioPreviewRandomInt? randomInt,
    DateTime Function()? now,
  })  : randomInt = randomInt ?? Random().nextInt,
        now = now ?? DateTime.now;

  Future<StudioAssetPreviewGenerationResult> generateArtistChainPreview(
    String artistChainId,
  ) async {
    final chains = [...await loadArtistChains()];
    final chainIndex = chains.indexWhere((chain) => chain.id == artistChainId);
    if (chainIndex < 0) {
      throw StudioAssetPreviewGenerationException('Artist chain "$artistChainId" was not found.');
    }
    final characters = await loadCharacters();
    final character = characters.isEmpty ? null : characters[randomInt(characters.length)];
    final chain = chains[chainIndex];
    final prompt = _joinPrompt([
      qualityPrompt,
      chain.prompt,
      ...chain.tags,
      ...chain.styleTags,
      if (character != null) character.traits.frontFull,
      artistScenePrompt,
    ]);
    final payload = _payload(prompt, _randomSize());
    final bytes = await requestImage(payload);
    final imagePath = await saveImage(bytes, _fileName('artist-chain', chain.id));
    chains[chainIndex] = chain.copyWith(
      imageRefs: _appendRef(chain.imageRefs, imagePath),
    );
    await saveArtistChains(List.unmodifiable(chains));
    return StudioAssetPreviewGenerationResult(
      assetId: chain.id,
      imagePath: imagePath,
      payload: payload,
    );
  }

  Future<StudioAssetPreviewGenerationResult> generateCharacterPreview(
    String characterId,
  ) async {
    final characters = [...await loadCharacters()];
    final characterIndex = characters.indexWhere((character) => character.id == characterId);
    if (characterIndex < 0) {
      throw StudioAssetPreviewGenerationException('Character "$characterId" was not found.');
    }
    final character = characters[characterIndex];
    final prompt = _joinPrompt([
      qualityPrompt,
      character.traits.frontFull,
      ...character.identityTags,
      characterWhitePrompt,
    ]);
    final payload = _payload(prompt, _randomSize());
    final bytes = await requestImage(payload);
    final imagePath = await saveImage(bytes, _fileName('character', character.id));
    characters[characterIndex] = character.copyWith(
      imageRefs: _appendRef(character.imageRefs, imagePath),
    );
    await saveCharacters(List.unmodifiable(characters));
    return StudioAssetPreviewGenerationResult(
      assetId: character.id,
      imagePath: imagePath,
      payload: payload,
    );
  }

  GenerationSize _randomSize() {
    return previewSizes[randomInt(previewSizes.length)];
  }

  Map<String, dynamic> _payload(String prompt, GenerationSize size) {
    final params = ParamConfig(
      model: model,
      sizes: [size],
      negativePrompt: defaultUC,
    ).getPayload();
    params['v4_prompt'] = {
      'caption': {
        'base_caption': prompt,
        'char_captions': <Object>[],
      },
      'use_coords': false,
      'use_order': true,
    };
    params['v4_negative_prompt'] = {
      'caption': {
        'base_caption': defaultUC,
        'char_captions': <Object>[],
      },
      'legacy_uc': false,
    };
    params['use_coords'] = false;
    return {
      'input': prompt,
      'model': model,
      'action': 'generate',
      'parameters': params,
    };
  }

  String _fileName(String kind, String id) {
    final utc = now().toUtc();
    String two(int value) => value.toString().padLeft(2, '0');
    final stamp =
        '${utc.year}${two(utc.month)}${two(utc.day)}-${two(utc.hour)}${two(utc.minute)}${two(utc.second)}';
    return 'asset-preview-$kind-$id-$stamp.png';
  }
}

class StudioAssetPreviewGenerationException implements Exception {
  final String message;

  const StudioAssetPreviewGenerationException(this.message);

  @override
  String toString() => message;
}

String _joinPrompt(Iterable<String> parts) {
  return parts
      .expand((part) => part.split(RegExp(r'[,\n]')))
      .map((tag) => tag.trim())
      .where((tag) => tag.isNotEmpty)
      .join(', ');
}

List<String> _appendRef(List<String> refs, String imagePath) {
  final result = <String>[...refs];
  if (!result.contains(imagePath)) {
    result.add(imagePath);
  }
  return List.unmodifiable(result);
}
```

- [ ] **Step 4: Run preview service tests**

Run:

```powershell
flutter test --no-pub test/data/studio/services/studio_asset_preview_generation_service_test.dart -r expanded
```

Expected: all tests pass.

- [ ] **Step 5: Git-enabled checkpoint**

Skip this step while Beads stealth/no-git mode is active. If the user enables git operations, run:

```powershell
git add lib/data/studio/services/studio_asset_preview_generation_service.dart test/data/studio/services/studio_asset_preview_generation_service_test.dart
git commit -m "feat: generate previews for saved assets"
```

Expected: commit succeeds.

---

### Task 4: Thin Save Confirmation Bar and Overlay Host

**Files:**

- Create: `lib/ui/studio_core/widgets/save_asset_confirm_bar.dart`
- Create: `lib/ui/studio_core/widgets/studio_asset_capture_host.dart`
- Test: `test/ui/studio_core/save_asset_confirm_bar_test.dart`

- [ ] **Step 1: Write widget tests first**

Create `test/ui/studio_core/save_asset_confirm_bar_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/studio/models/studio_asset_capture.dart';
import 'package:nai_casrand/data/workspace/models/workspace_entities.dart';
import 'package:nai_casrand/ui/studio_core/widgets/save_asset_confirm_bar.dart';

void main() {
  testWidgets('edits name and note before confirming', (tester) async {
    final draft = StudioAssetCaptureDraft.artistChain(
      source: const StudioAssetCaptureSource(surface: 'script', label: 'Script'),
      artistChain: const ArtistChain(
        id: 'chain-a',
        name: 'Old',
        tags: ['artist:foo'],
      ),
    );
    String? name;
    String? note;
    bool confirmed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SaveAssetConfirmBar(
            draft: draft,
            plan: StudioAssetCapturePlan(draft: draft),
            saving: false,
            onNameChanged: (value) => name = value,
            onNoteChanged: (value) => note = value,
            onKindChanged: (_) {},
            onTargetChanged: (_) {},
            onForceNewChanged: (_) {},
            onConfirm: () => confirmed = true,
            onCancel: () {},
          ),
        ),
      ),
    );

    await tester.enterText(find.byKey(const ValueKey('save-asset-name-field')), 'New name');
    await tester.enterText(find.byKey(const ValueKey('save-asset-note-field')), 'Useful note');
    await tester.tap(find.byKey(const ValueKey('save-asset-confirm')));
    await tester.pump();

    expect(name, 'New name');
    expect(note, 'Useful note');
    expect(confirmed, isTrue);
  });
}
```

- [ ] **Step 2: Run test and confirm missing widgets failure**

Run:

```powershell
flutter test --no-pub test/ui/studio_core/save_asset_confirm_bar_test.dart -r expanded
```

Expected: fails because the widgets do not exist.

- [ ] **Step 3: Implement confirmation bar**

Create `lib/ui/studio_core/widgets/save_asset_confirm_bar.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:nai_casrand/data/studio/models/studio_asset_capture.dart';
import 'package:nai_casrand/ui/studio_core/theme/studio_tokens.dart';
import 'package:nai_casrand/ui/studio_core/widgets/studio_button.dart';
import 'package:nai_casrand/ui/studio_core/widgets/studio_chip.dart';
import 'package:nai_casrand/ui/studio_core/widgets/studio_panel.dart';

class SaveAssetConfirmBar extends StatelessWidget {
  final StudioAssetCaptureDraft draft;
  final StudioAssetCapturePlan plan;
  final bool saving;
  final ValueChanged<String> onNameChanged;
  final ValueChanged<String> onNoteChanged;
  final ValueChanged<StudioAssetCaptureKind> onKindChanged;
  final ValueChanged<String?> onTargetChanged;
  final ValueChanged<bool> onForceNewChanged;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;
  final String? selectedTargetId;
  final bool forceNew;

  const SaveAssetConfirmBar({
    super.key,
    required this.draft,
    required this.plan,
    required this.saving,
    required this.onNameChanged,
    required this.onNoteChanged,
    required this.onKindChanged,
    required this.onTargetChanged,
    required this.onForceNewChanged,
    required this.onConfirm,
    required this.onCancel,
    this.selectedTargetId,
    this.forceNew = false,
  });

  @override
  Widget build(BuildContext context) {
    final candidates = plan.candidates;
    final kinds = draft.availableKinds.isEmpty ? [draft.kind] : draft.availableKinds;
    return StudioPanel(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          StudioChip(
            label: draft.kind.label,
            icon: Icons.inventory_2_outlined,
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 150,
            child: DropdownButtonFormField<StudioAssetCaptureKind>(
              key: const ValueKey('save-asset-kind-field'),
              value: draft.kind,
              isExpanded: true,
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Type',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final kind in kinds)
                  DropdownMenuItem(
                    value: kind,
                    child: Text(kind.label),
                  ),
              ],
              onChanged: saving ? null : (value) {
                if (value != null) onKindChanged(value);
              },
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: TextFormField(
              key: const ValueKey('save-asset-name-field'),
              initialValue: draft.name,
              onChanged: onNameChanged,
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Name',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: TextFormField(
              key: const ValueKey('save-asset-note-field'),
              initialValue: draft.note,
              onChanged: onNoteChanged,
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Note',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          if (candidates.isNotEmpty) ...[
            const SizedBox(width: 8),
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<String?>(
                key: const ValueKey('save-asset-target-field'),
                value: forceNew ? null : selectedTargetId,
                isExpanded: true,
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'Merge target',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Create new'),
                  ),
                  for (final candidate in candidates)
                    DropdownMenuItem<String?>(
                      value: candidate.id,
                      child: Text(
                        candidate.name,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: saving
                    ? null
                    : (value) {
                        onTargetChanged(value);
                        onForceNewChanged(value == null);
                      },
              ),
            ),
          ],
          const SizedBox(width: 8),
          StudioButton(
            key: const ValueKey('save-asset-cancel'),
            label: 'Cancel',
            icon: Icons.close,
            onPressed: saving ? null : onCancel,
            tone: StudioButtonTone.neutral,
          ),
          const SizedBox(width: 8),
          StudioButton(
            key: const ValueKey('save-asset-confirm'),
            label: saving ? 'Saving' : 'Save',
            icon: saving ? Icons.hourglass_empty : Icons.check,
            onPressed: saving ? null : onConfirm,
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Implement overlay host**

Create `lib/ui/studio_core/widgets/studio_asset_capture_host.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nai_casrand/data/studio/models/studio_asset_capture.dart';
import 'package:nai_casrand/data/studio/services/studio_asset_capture_service.dart';
import 'package:nai_casrand/ui/studio_core/theme/studio_tokens.dart';
import 'package:nai_casrand/ui/studio_core/widgets/save_asset_confirm_bar.dart';

class StudioAssetCaptureHost extends StatefulWidget {
  final Widget child;
  final StudioAssetCaptureService service;
  final ValueChanged<StudioAssetCaptureResult>? onSaved;

  const StudioAssetCaptureHost({
    super.key,
    required this.child,
    required this.service,
    this.onSaved,
  });

  static StudioAssetCaptureHostState? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<_StudioAssetCaptureScope>()?.state;
  }

  static StudioAssetCaptureHostState of(BuildContext context) {
    final state = maybeOf(context);
    if (state == null) {
      throw StateError('StudioAssetCaptureHost was not found above this context.');
    }
    return state;
  }

  @override
  State<StudioAssetCaptureHost> createState() => StudioAssetCaptureHostState();
}

class StudioAssetCaptureHostState extends State<StudioAssetCaptureHost> {
  StudioAssetCaptureDraft? _draft;
  StudioAssetCapturePlan? _plan;
  String? _name;
  String _note = '';
  String? _targetId;
  bool _forceNew = false;
  bool _saving = false;

  Future<void> showDraft(StudioAssetCaptureDraft draft) async {
    final plan = await widget.service.previewSave(draft);
    if (!mounted) return;
    setState(() {
      _draft = draft;
      _plan = plan;
      _name = draft.name;
      _note = draft.note;
      _targetId = plan.candidates.isEmpty ? null : plan.candidates.first.id;
      _forceNew = plan.candidates.isEmpty;
      _saving = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final draft = _draft;
    final plan = _plan;
    return _StudioAssetCaptureScope(
      state: this,
      child: Stack(
        children: [
          widget.child,
          if (draft != null && plan != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: Material(
                color: Colors.transparent,
                elevation: 16,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: StudioTokens.surface1,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: const [
                      BoxShadow(
                        blurRadius: 24,
                        color: Color(0x33000000),
                      ),
                    ],
                  ),
                  child: SaveAssetConfirmBar(
                    draft: draft.copyWith(
                      name: _name,
                      note: _note,
                    ),
                    plan: plan,
                    saving: _saving,
                    selectedTargetId: _targetId,
                    forceNew: _forceNew,
                    onNameChanged: (value) => setState(() => _name = value),
                    onNoteChanged: (value) => setState(() => _note = value),
                    onKindChanged: (value) {
                      setState(() {
                        _draft = draft.copyWith(kind: value);
                      });
                    },
                    onTargetChanged: (value) => setState(() => _targetId = value),
                    onForceNewChanged: (value) => setState(() => _forceNew = value),
                    onCancel: _clear,
                    onConfirm: () => unawaited(_confirm()),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _confirm() async {
    final draft = _draft;
    if (draft == null) return;
    setState(() => _saving = true);
    try {
      final result = await widget.service.save(
        draft,
        targetId: _targetId,
        forceNew: _forceNew,
        nameOverride: _name,
        noteOverride: _note,
      );
      widget.onSaved?.call(result);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved ${result.name}')),
        );
      }
      _clear();
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  void _clear() {
    if (!mounted) return;
    setState(() {
      _draft = null;
      _plan = null;
      _name = null;
      _note = '';
      _targetId = null;
      _forceNew = false;
      _saving = false;
    });
  }
}

class _StudioAssetCaptureScope extends InheritedWidget {
  final StudioAssetCaptureHostState state;

  const _StudioAssetCaptureScope({
    required this.state,
    required super.child,
  });

  @override
  bool updateShouldNotify(_StudioAssetCaptureScope oldWidget) {
    return oldWidget.state != state;
  }
}
```

- [ ] **Step 5: Run widget test**

Run:

```powershell
flutter test --no-pub test/ui/studio_core/save_asset_confirm_bar_test.dart -r expanded
```

Expected: all tests pass.

- [ ] **Step 6: Git-enabled checkpoint**

Skip this step while Beads stealth/no-git mode is active. If the user enables git operations, run:

```powershell
git add lib/ui/studio_core/widgets/save_asset_confirm_bar.dart lib/ui/studio_core/widgets/studio_asset_capture_host.dart test/ui/studio_core/save_asset_confirm_bar_test.dart
git commit -m "feat: add structured asset save confirmation"
```

Expected: commit succeeds.

---

### Task 5: Register Services and Wrap Pages

**Files:**

- Modify: `lib/main.dart`
- Modify: `lib/ui/studio_shell/widgets/studio_shell_view.dart`

- [ ] **Step 1: Register services in GetIt**

In `lib/main.dart`, add imports:

```dart
import 'package:nai_casrand/data/studio/services/studio_asset_capture_service.dart';
import 'package:nai_casrand/data/studio/services/studio_asset_preview_generation_service.dart';
```

After `StudioWorkbenchAssetService` registration, add:

```dart
  GetIt.instance.registerLazySingleton(
    () => StudioAssetCaptureService(
      workspaceService: workspaceService,
    ),
  );
```

After `ProductionNaiAdapterService` registration, add:

```dart
  GetIt.instance.registerLazySingleton(
    () {
      final adapter = GetIt.I<ProductionNaiAdapterService>();
      return StudioAssetPreviewGenerationService(
        loadArtistChains: workspaceService.loadArtistChains,
        saveArtistChains: workspaceService.saveArtistChains,
        loadCharacters: workspaceService.loadCharacters,
        saveCharacters: workspaceService.saveCharacters,
        requestImage: adapter.requestImage,
        saveImage: adapter.saveImage,
      );
    },
  );
```

- [ ] **Step 2: Wrap structured pages in the capture host**

In `lib/ui/studio_shell/widgets/studio_shell_view.dart`, add imports:

```dart
import 'package:nai_casrand/data/studio/services/studio_asset_capture_service.dart';
import 'package:nai_casrand/data/studio/services/studio_asset_preview_generation_service.dart';
import 'package:nai_casrand/ui/studio_core/widgets/studio_asset_capture_host.dart';
```

Add this helper method inside `_StudioShellViewState`:

```dart
  Widget _withAssetCapture(Widget child) {
    return StudioAssetCaptureHost(
      service: GetIt.I<StudioAssetCaptureService>(),
      child: child,
    );
  }
```

Wrap page cases that can produce structured drafts:

```dart
      StudioShellSection.assets => _withAssetCapture(
          AssetLibraryPage(
            catalogService: GetIt.I(),
            workbenchAssetService: GetIt.I<StudioWorkbenchAssetService>(),
            previewGenerationService:
                GetIt.I<StudioAssetPreviewGenerationService>(),
            onSendToScript: _openScriptAsset,
          ),
        ),
      StudioShellSection.script => _withAssetCapture(
          StudioScriptPage(
            viewModel: _scriptViewModel,
            assetFocus: _scriptAssetFocus,
            onSentToProduction: () {
              _productionQueueViewModel.load();
              _changeSection(StudioShellSection.batch);
            },
          ),
        ),
      StudioShellSection.scriptExhibition => _withAssetCapture(
          ScriptExhibitionRoomPage(
            viewModel: _scriptExhibitionRoomViewModel,
            onSendToScriptWorkbench: (focus) {
              unawaited(_openScriptExhibitionFocus(focus));
            },
            onSendToWorkbench: (focus) {
              unawaited(_openScriptExhibitionImageInWorkbench(focus));
            },
          ),
        ),
      StudioShellSection.gallery => _withAssetCapture(
          StudioGalleryPage(
            viewModel: GetIt.I(),
            galleryService: GetIt.I(),
            payloadConfig: GetIt.I(),
          ),
        ),
```

- [ ] **Step 3: Analyze modified files**

Run:

```powershell
flutter analyze lib/main.dart lib/ui/studio_shell/widgets/studio_shell_view.dart
```

Expected: no new analyzer errors in those files.

- [ ] **Step 4: Git-enabled checkpoint**

Skip this step while Beads stealth/no-git mode is active. If the user enables git operations, run:

```powershell
git add lib/main.dart lib/ui/studio_shell/widgets/studio_shell_view.dart
git commit -m "feat: wire asset capture services"
```

Expected: commit succeeds.

---

### Task 6: Asset Library Preview Actions

**Files:**

- Modify: `lib/ui/studio_shell/widgets/asset_library_page.dart`
- Test: `test/ui/studio_shell/asset_library_page_test.dart`

- [ ] **Step 1: Add preview service constructor field**

In `lib/ui/studio_shell/widgets/asset_library_page.dart`, add import:

```dart
import 'package:nai_casrand/data/studio/services/studio_asset_preview_generation_service.dart';
```

Add field to `AssetLibraryPage`:

```dart
  final StudioAssetPreviewGenerationService? previewGenerationService;
```

Add constructor parameter:

```dart
    this.previewGenerationService,
```

Add state field:

```dart
  final Set<String> _previewGenerationInFlight = <String>{};
```

- [ ] **Step 2: Add generation handler in `_AssetLibraryPageState`**

Add this method:

```dart
  Future<void> _generatePreview(_AssetDisplayItem item) async {
    final service = widget.previewGenerationService;
    if (service == null) return;
    if (item.kind != _AssetKind.artistChain && item.kind != _AssetKind.character) {
      return;
    }
    final key = item.key;
    setState(() => _previewGenerationInFlight.add(key));
    try {
      if (item.kind == _AssetKind.artistChain) {
        await service.generateArtistChainPreview(item.id);
      } else {
        await service.generateCharacterPreview(item.id);
      }
      if (!mounted) return;
      _clearDisplayCaches(clearImagePathCache: true);
      setState(() {
        _snapshotFuture = _loadSnapshot(includeCodex: _filter == _AssetFilter.codex);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Preview generated for ${item.title}')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      if (mounted) {
        setState(() => _previewGenerationInFlight.remove(key));
      }
    }
  }
```

- [ ] **Step 3: Thread preview callbacks into cards and drawer**

Find `_AssetCard` construction and pass:

```dart
onGeneratePreview: widget.previewGenerationService == null
    ? null
    : () => _generatePreview(item),
generatingPreview: _previewGenerationInFlight.contains(item.key),
```

Find `_AssetDetailDrawer` construction and pass the same callback and state for `_selectedAsset`.

Update `_AssetCard` and `_AssetDetailDrawer` constructors with:

```dart
  final VoidCallback? onGeneratePreview;
  final bool generatingPreview;
```

For artist-chain and character items only, render an icon button:

```dart
if ((item.kind == _AssetKind.artistChain || item.kind == _AssetKind.character) &&
    onGeneratePreview != null)
  _AssetCardActionButton(
    key: ValueKey('asset-generate-preview-${item.kind.name}-${item.id}'),
    icon: generatingPreview ? Icons.hourglass_empty : Icons.auto_awesome,
    tooltip: generatingPreview ? 'Generating preview' : 'Generate preview',
    onPressed: generatingPreview ? null : onGeneratePreview,
  ),
```

Use the same key shape in the detail drawer:

```dart
ValueKey('asset-detail-generate-preview-${item.kind.name}-${item.id}')
```

- [ ] **Step 4: Add asset-library widget tests**

In `test/ui/studio_shell/asset_library_page_test.dart`, add a fake preview service that records calls:

```dart
class _FakePreviewGenerationService extends StudioAssetPreviewGenerationService {
  final List<String> artistRequests = [];
  final List<String> characterRequests = [];

  _FakePreviewGenerationService()
      : super(
          loadArtistChains: () async => const [],
          saveArtistChains: (_) async {},
          loadCharacters: () async => const [],
          saveCharacters: (_) async {},
          requestImage: (_) async => Uint8List(0),
          saveImage: (_, __) async => '',
        );

  @override
  Future<StudioAssetPreviewGenerationResult> generateArtistChainPreview(String artistChainId) async {
    artistRequests.add(artistChainId);
    return StudioAssetPreviewGenerationResult(
      assetId: artistChainId,
      imagePath: 'artist.png',
      payload: const {},
    );
  }

  @override
  Future<StudioAssetPreviewGenerationResult> generateCharacterPreview(String characterId) async {
    characterRequests.add(characterId);
    return StudioAssetPreviewGenerationResult(
      assetId: characterId,
      imagePath: 'character.png',
      payload: const {},
    );
  }
}
```

Add imports if absent:

```dart
import 'dart:typed_data';
import 'package:nai_casrand/data/studio/services/studio_asset_preview_generation_service.dart';
```

Extend the existing `page` helper signature with:

```dart
    StudioAssetPreviewGenerationService? previewGenerationService,
```

and pass it into `AssetLibraryPage`:

```dart
        previewGenerationService: previewGenerationService,
```

Add test:

```dart
testWidgets('generate preview button is available for artist chains and characters', (tester) async {
  final config = payload();
  final previewService = _FakePreviewGenerationService();
  await tester.pumpWidget(
    page(config: config, previewGenerationService: previewService),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.byKey(const ValueKey('asset-generate-preview-character-char-1')));
  await tester.pumpAndSettle();
  expect(previewService.characterRequests, ['char-1']);

  await tester.tap(find.byKey(const ValueKey('asset-generate-preview-artistChain-artist-1')));
  await tester.pumpAndSettle();
  expect(previewService.artistRequests, ['artist-1']);
});
```

- [ ] **Step 5: Run asset-library tests**

Run:

```powershell
flutter test --no-pub test/ui/studio_shell/asset_library_page_test.dart -r expanded
```

Expected: all tests in the file pass.

- [ ] **Step 6: Git-enabled checkpoint**

Skip this step while Beads stealth/no-git mode is active. If the user enables git operations, run:

```powershell
git add lib/ui/studio_shell/widgets/asset_library_page.dart test/ui/studio_shell/asset_library_page_test.dart
git commit -m "feat: generate asset previews from library"
```

Expected: commit succeeds.

---

### Task 7: Script Page Save Entrypoints

**Files:**

- Modify: `lib/ui/studio_script/widgets/studio_script_page.dart`

- [ ] **Step 1: Add imports**

Add:

```dart
import 'package:nai_casrand/data/studio/models/studio_asset_capture.dart';
import 'package:nai_casrand/ui/studio_core/widgets/studio_asset_capture_host.dart';
```

- [ ] **Step 2: Add save button for AI extracted roles**

In `_AiRoleExtractionRoleRowState.build`, near the role title/action row, add:

```dart
StudioIconButton(
  key: ValueKey('script-ai-role-save-${role.sourceRoleId}'),
  icon: Icons.save_alt_outlined,
  tooltip: 'Save character as asset',
  onPressed: () {
    final host = StudioAssetCaptureHost.maybeOf(context);
    if (host == null) return;
    host.showDraft(
      StudioAssetCaptureDrafts.characterFromAiRole(
        role,
        source: StudioAssetCaptureSource(
          surface: 'script',
          label: 'AI role extraction',
          sourceId: role.sourceRoleId,
        ),
      ),
    );
  },
),
```

Keep the button in the same row as collapse/expand controls so it is visible without opening a dialog.

- [ ] **Step 3: Add save buttons for AI artist-chain evidence**

In `_AiRoleExtractionHiddenEvidence`, where `extraction.artistChains` are rendered, add one save icon per chain:

```dart
for (final (index, chain) in extraction.artistChains.indexed)
  Row(
    children: [
      Expanded(
        child: _AiRoleExtractionTermWrap(terms: chain.terms),
      ),
      StudioIconButton(
        key: ValueKey('script-ai-artist-chain-save-$index'),
        icon: Icons.save_alt_outlined,
        tooltip: 'Save artist chain as asset',
        onPressed: () {
          final host = StudioAssetCaptureHost.maybeOf(context);
          if (host == null) return;
          host.showDraft(
            StudioAssetCaptureDrafts.artistFromAiEvidence(
              chain,
              source: StudioAssetCaptureSource(
                surface: 'script',
                label: 'AI artist chain evidence',
                sourceId: 'artist-chain-$index',
              ),
            ),
          );
        },
      ),
    ],
  ),
```

If the existing widget already builds rows for each chain, add the `StudioIconButton` to that row instead of creating a second listing.

- [ ] **Step 4: Add save button for manual artist mappings**

In the artist mapping card builder around the `viewModel.artistMappings` loop, add a save icon when the mapping has a selected chain or source terms. Use:

```dart
StudioIconButton(
  key: ValueKey('script-artist-mapping-save-${chain.slotKey}'),
  icon: Icons.save_alt_outlined,
  tooltip: 'Save artist chain as asset',
  onPressed: () {
    final host = StudioAssetCaptureHost.maybeOf(context);
    if (host == null) return;
    final selected = _artistChainById(viewModel.artistChainOptions, chain.selectedArtistChainId);
    if (selected != null) {
      host.showDraft(
        StudioAssetCaptureDraft.artistChain(
          source: StudioAssetCaptureSource(
            surface: 'script',
            label: 'Artist mapping',
            sourceId: chain.slotKey,
          ),
          artistChain: selected,
          name: selected.name,
        ),
      );
    }
  },
),
```

If `slotKey` is not available on `StudioScriptArtistMappingItem`, use `index` from the existing indexed loop and key `script-artist-mapping-save-$index`.

- [ ] **Step 5: Run script page tests or analyzer**

Run:

```powershell
flutter analyze lib/ui/studio_script/widgets/studio_script_page.dart
```

Expected: no new analyzer errors in the file.

- [ ] **Step 6: Git-enabled checkpoint**

Skip this step while Beads stealth/no-git mode is active. If the user enables git operations, run:

```powershell
git add lib/ui/studio_script/widgets/studio_script_page.dart
git commit -m "feat: save script structured assets"
```

Expected: commit succeeds.

---

### Task 8: Gallery and Exhibition Save Entrypoints

**Files:**

- Modify: `lib/ui/studio_shell/widgets/studio_gallery_page.dart`
- Modify: `lib/ui/studio_shell/widgets/script_exhibition_room_page.dart`

- [ ] **Step 1: Add imports to both files**

Add:

```dart
import 'package:nai_casrand/data/studio/models/studio_asset_capture.dart';
import 'package:nai_casrand/ui/studio_core/widgets/studio_asset_capture_host.dart';
```

- [ ] **Step 2: Add structured draft extraction helper to gallery page**

In `studio_gallery_page.dart`, add a private helper near other record helpers:

```dart
List<StudioAssetCaptureDraft> _captureDraftsForGalleryRecord(
  StudioGalleryRecord record,
) {
  return StudioAssetCaptureDrafts.fromWorkbenchDocument(
    record.document,
    source: StudioAssetCaptureSource(
      surface: 'gallery',
      label: record.title.trim().isEmpty ? 'Gallery item' : record.title.trim(),
      sourceId: record.id,
      path: record.imagePath,
    ),
  );
}
```

- [ ] **Step 3: Render gallery save buttons only when drafts exist**

In `_GalleryDetailDrawer.build`, compute:

```dart
final captureDrafts = _captureDraftsForGalleryRecord(record);
```

In the detail action row, add:

```dart
for (final (index, draft) in captureDrafts.indexed)
  StudioButton(
    key: ValueKey('gallery-save-structured-asset-$index'),
    label: draft.kind.label,
    icon: Icons.save_alt_outlined,
    onPressed: () {
      final host = StudioAssetCaptureHost.maybeOf(context);
      if (host == null) return;
      host.showDraft(draft);
    },
    tone: StudioButtonTone.neutral,
  ),
```

Do not create a button from `record.info` or `record.document.payload['override_prompt']`.

- [ ] **Step 4: Add structured draft extraction helper to exhibition page**

In `script_exhibition_room_page.dart`, add:

```dart
List<StudioAssetCaptureDraft> _captureDraftsForExhibitionItem(
  ScriptExhibitionItem item,
) {
  final record = item.galleryRecord;
  if (record == null) return const [];
  return StudioAssetCaptureDrafts.fromWorkbenchDocument(
    record.document,
    source: StudioAssetCaptureSource(
      surface: 'script_exhibition',
      label: item.title.trim().isEmpty ? 'Exhibition item' : item.title.trim(),
      sourceId: item.id,
      path: item.imagePath,
    ),
  );
}
```

In `lib/ui/studio_shell/view_models/script_exhibition_room_viewmodel.dart`, expose the backing record directly on `ScriptExhibitionItem`:

```dart
  final StudioGalleryRecord? galleryRecord;
```

Add the constructor parameter:

```dart
    this.galleryRecord,
```

When constructing `ScriptExhibitionItem` from a gallery record, pass:

```dart
      galleryRecord: record,
```

For script-only items that do not come from a gallery record, leave `galleryRecord` unset.

- [ ] **Step 5: Render exhibition save buttons only when drafts exist**

In the exhibition detail and preview action rows, compute:

```dart
final captureDrafts = _captureDraftsForExhibitionItem(item);
```

Render:

```dart
for (final (index, draft) in captureDrafts.indexed)
  StudioButton(
    key: ValueKey('script-exhibition-save-structured-asset-$index'),
    label: draft.kind.label,
    icon: Icons.save_alt_outlined,
    onPressed: () {
      final host = StudioAssetCaptureHost.maybeOf(context);
      if (host == null) return;
      host.showDraft(draft);
    },
    tone: StudioButtonTone.neutral,
  ),
```

Keep existing send-to-workbench and send-to-script actions unchanged.

- [ ] **Step 6: Analyze changed pages**

Run:

```powershell
flutter analyze lib/ui/studio_shell/widgets/studio_gallery_page.dart lib/ui/studio_shell/widgets/script_exhibition_room_page.dart lib/ui/studio_shell/view_models/script_exhibition_room_viewmodel.dart
```

Expected: no new analyzer errors in these files.

- [ ] **Step 7: Git-enabled checkpoint**

Skip this step while Beads stealth/no-git mode is active. If the user enables git operations, run:

```powershell
git add lib/ui/studio_shell/widgets/studio_gallery_page.dart lib/ui/studio_shell/widgets/script_exhibition_room_page.dart lib/ui/studio_shell/view_models/script_exhibition_room_viewmodel.dart
git commit -m "feat: save gallery structured assets"
```

Expected: commit succeeds.

---

### Task 9: Verification Pass

**Files:**

- All files changed above

- [ ] **Step 1: Run targeted tests**

Run:

```powershell
flutter test --no-pub test/data/studio/models/studio_asset_capture_test.dart test/data/studio/services/studio_asset_capture_service_test.dart test/data/studio/services/studio_asset_preview_generation_service_test.dart test/ui/studio_core/save_asset_confirm_bar_test.dart test/ui/studio_shell/asset_library_page_test.dart -r expanded
```

Expected: all targeted tests pass.

- [ ] **Step 2: Run analyzer for touched production files**

Run:

```powershell
flutter analyze lib/data/studio/models/studio_asset_capture.dart lib/data/studio/services/studio_asset_capture_service.dart lib/data/studio/services/studio_asset_preview_generation_service.dart lib/ui/studio_core/widgets/save_asset_confirm_bar.dart lib/ui/studio_core/widgets/studio_asset_capture_host.dart lib/main.dart lib/ui/studio_shell/widgets/studio_shell_view.dart lib/ui/studio_shell/widgets/asset_library_page.dart lib/ui/studio_script/widgets/studio_script_page.dart lib/ui/studio_shell/widgets/studio_gallery_page.dart lib/ui/studio_shell/widgets/script_exhibition_room_page.dart
```

Expected: no new analyzer errors in touched files.

- [ ] **Step 3: Manual smoke test in the app**

Run the app with the existing project command:

```powershell
flutter run -d windows
```

Expected:

- Asset library shows preview generation button on character cards and artist-chain cards.
- Clicking character preview sends one NAI request with `model` equal to `nai-diffusion-4-5-full` and a prompt containing `plain white background`.
- Clicking artist-chain preview sends one NAI request with `model` equal to `nai-diffusion-4-5-full`, a random character prompt, and `detailed background`.
- Script AI role rows show save buttons that open the thin confirmation bar.
- Gallery and exhibition only show save buttons when `WorkbenchDocument` has `character_config` or structured artist tags in `prompt_config` / `saved_config`.
- Saving a duplicate offers a merge target; saving with create-new appends a new item.

- [ ] **Step 4: Update Beads issue**

Run:

```powershell
bd update NAI_NEW-231z --notes "Implemented structured asset capture and asset-library preview generation. Targeted tests and analyzer pass."
```

Expected: issue notes are updated.

- [ ] **Step 5: Git-enabled final checkpoint**

Skip this step while Beads stealth/no-git mode is active. If the user enables git operations, run:

```powershell
git status --short
git add lib/data/studio/models/studio_asset_capture.dart lib/data/studio/services/studio_asset_capture_service.dart lib/data/studio/services/studio_asset_preview_generation_service.dart lib/ui/studio_core/widgets/save_asset_confirm_bar.dart lib/ui/studio_core/widgets/studio_asset_capture_host.dart lib/main.dart lib/ui/studio_shell/widgets/studio_shell_view.dart lib/ui/studio_shell/widgets/asset_library_page.dart lib/ui/studio_script/widgets/studio_script_page.dart lib/ui/studio_shell/widgets/studio_gallery_page.dart lib/ui/studio_shell/widgets/script_exhibition_room_page.dart test/data/studio/models/studio_asset_capture_test.dart test/data/studio/services/studio_asset_capture_service_test.dart test/data/studio/services/studio_asset_preview_generation_service_test.dart test/ui/studio_core/save_asset_confirm_bar_test.dart test/ui/studio_shell/asset_library_page_test.dart
git commit -m "feat: capture structured assets and generate previews"
```

Expected: commit succeeds and unrelated dirty worktree files remain unstaged.

## Self-Review Notes

- Spec coverage: cross-page structured capture is handled by Tasks 4, 5, 7, and 8; ordinary prompt exclusion is enforced in Task 1 and Task 8; preview generation is asset-library-only in Task 6; preview payload requirements are handled in Task 3.
- Type consistency: `StudioAssetCaptureDraft`, `StudioAssetCapturePlan`, `StudioAssetCaptureResult`, and `StudioAssetPreviewGenerationResult` are introduced before all UI tasks that use them.
- Project constraint: Beads issue `NAI_NEW-231z` is already created and claimed. Git commands are written only as git-enabled checkpoints because current Beads context says stealth/no-git.
