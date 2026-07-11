import 'package:flutter/foundation.dart';
import 'package:novel_studio/data/models/param_config.dart';
import 'package:novel_studio/data/models/payload_config.dart';
import 'package:novel_studio/data/models/vibe_config_v4.dart';
import 'package:novel_studio/data/workspace/models/workspace_entities.dart';
import 'package:novel_studio/data/workspace/workspace_service.dart';

enum StudioWorkbenchAssetKind {
  character,
  outfit,
  outfitPart,
  assetSection,
  artistChain,
  recipe,
  tag,
}

abstract class StudioWorkbenchCharacterDropData {
  String get label;

  String get characterName;

  String get characterPrompt;
}

abstract class StudioWorkbenchPromptDropData {
  String get label;

  void insertAt(int targetIndex);
}

class StudioWorkbenchFragmentDropData implements StudioWorkbenchPromptDropData {
  final StudioWorkbenchAssetService service;
  final String fragmentId;

  @override
  final String label;

  StudioWorkbenchFragmentDropData({
    required this.service,
    required this.fragmentId,
    required this.label,
  });

  @override
  void insertAt(int targetIndex) {
    service.moveFragment(fragmentId, targetIndex);
  }
}

class StudioWorkbenchAssetFragment {
  final String id;
  final StudioWorkbenchAssetKind kind;
  final String sourceId;
  final String? sourceBlock;
  final String? sourceParentId;
  final String typeLabel;
  final String name;
  String originalPositiveText;
  String positiveText;

  StudioWorkbenchAssetFragment({
    required this.id,
    required this.kind,
    required this.sourceId,
    this.sourceBlock,
    this.sourceParentId,
    required this.typeLabel,
    required this.name,
    required this.originalPositiveText,
    required this.positiveText,
  });

  String get prompt => positiveText;

  bool get isDirty => positiveText != originalPositiveText;
}

class StudioWorkbenchAssetService extends ChangeNotifier {
  final PayloadConfig payloadConfig;
  final WorkspaceService? workspaceService;
  final List<StudioWorkbenchAssetFragment> _fragments = [];
  String _manualPositivePrompt;
  int _nextFragmentNumber = 0;

  StudioWorkbenchAssetService({
    required this.payloadConfig,
    this.workspaceService,
  }) : _manualPositivePrompt = payloadConfig.overridePrompt.trim();

  List<StudioWorkbenchAssetFragment> get fragments =>
      List.unmodifiable(_fragments);

  String get manualPositivePrompt => _manualPositivePrompt;

  String get manualNegativePrompt => payloadConfig.paramConfig.negativePrompt;

  void refreshFromPayload() {
    _manualPositivePrompt = payloadConfig.overridePrompt.trim();
    notifyListeners();
  }

  void appendCharacter(CharacterEntry character) {
    _appendPromptFragment(
      kind: StudioWorkbenchAssetKind.character,
      sourceId: character.id,
      typeLabel: '角色',
      name: character.name,
      fragment: character.traits.frontFull,
    );
  }

  void insertCharacter(CharacterEntry character, int targetIndex) {
    _insertPromptFragment(
      kind: StudioWorkbenchAssetKind.character,
      sourceId: character.id,
      typeLabel: '角色',
      name: character.name,
      fragment: character.traits.frontFull,
      targetIndex: targetIndex,
    );
  }

  void appendOutfit(CharacterEntry character, WorkspaceOutfit outfit) {
    _appendPromptFragment(
      kind: StudioWorkbenchAssetKind.outfit,
      sourceId: outfit.id,
      sourceParentId: character.id,
      typeLabel: 'Outfit',
      name: '${character.name} / ${outfit.name}',
      fragment: outfit.tags.frontFull,
    );
  }

  void insertOutfit(
    CharacterEntry character,
    WorkspaceOutfit outfit,
    int targetIndex,
  ) {
    _insertPromptFragment(
      kind: StudioWorkbenchAssetKind.outfit,
      sourceId: outfit.id,
      sourceParentId: character.id,
      typeLabel: 'Outfit',
      name: '${character.name} / ${outfit.name}',
      fragment: outfit.tags.frontFull,
      targetIndex: targetIndex,
    );
  }

  void appendOutfitPart({
    required CharacterEntry character,
    required String outfitId,
    required String outfitName,
    required String partLabel,
    required String fragment,
  }) {
    _appendPromptFragment(
      kind: StudioWorkbenchAssetKind.outfitPart,
      sourceId: '$outfitId:$partLabel',
      sourceParentId: character.id,
      typeLabel: partLabel,
      name: '${character.name} / $outfitName / $partLabel',
      fragment: fragment,
    );
  }

  void insertOutfitPart({
    required CharacterEntry character,
    required String outfitId,
    required String outfitName,
    required String partLabel,
    required String fragment,
    required int targetIndex,
  }) {
    _insertPromptFragment(
      kind: StudioWorkbenchAssetKind.outfitPart,
      sourceId: '$outfitId:$partLabel',
      sourceParentId: character.id,
      typeLabel: partLabel,
      name: '${character.name} / $outfitName / $partLabel',
      fragment: fragment,
      targetIndex: targetIndex,
    );
  }

  void appendArtistChain(ArtistChain artistChain) {
    final prompt = artistChain.prompt.trim();
    if (prompt.isNotEmpty) {
      _appendPromptFragment(
        kind: StudioWorkbenchAssetKind.artistChain,
        sourceId: artistChain.id,
        typeLabel: '画师串',
        name: artistChain.name,
        fragment: prompt,
      );
      _mergeArtistChainVibes(artistChain.vibeRefs);
      return;
    }
    _appendPromptFragment(
      kind: StudioWorkbenchAssetKind.artistChain,
      sourceId: artistChain.id,
      typeLabel: '画师串',
      name: artistChain.name,
      fragment: [
        ...artistChain.tags,
        ...artistChain.styleTags,
      ].join(', '),
    );
    _mergeArtistChainVibes(artistChain.vibeRefs);
  }

  void insertArtistChain(ArtistChain artistChain, int targetIndex) {
    final prompt = artistChain.prompt.trim();
    _insertPromptFragment(
      kind: StudioWorkbenchAssetKind.artistChain,
      sourceId: artistChain.id,
      typeLabel: '画师串',
      name: artistChain.name,
      fragment: prompt.isNotEmpty
          ? prompt
          : [
              ...artistChain.tags,
              ...artistChain.styleTags,
            ].join(', '),
      targetIndex: targetIndex,
    );
    _mergeArtistChainVibes(artistChain.vibeRefs);
  }

  void appendAssetSection({
    required String sourceId,
    String? sourceBlock,
    required String sectionKey,
    required String typeLabel,
    required String name,
    required String fragment,
  }) {
    _appendPromptFragment(
      kind: StudioWorkbenchAssetKind.assetSection,
      sourceId: '$sourceId:$sectionKey',
      sourceBlock: sourceBlock,
      typeLabel: typeLabel,
      name: '$name / $typeLabel',
      fragment: fragment,
    );
  }

  void insertAssetSection({
    required String sourceId,
    String? sourceBlock,
    required String sectionKey,
    required String typeLabel,
    required String name,
    required String fragment,
    required int targetIndex,
  }) {
    _insertPromptFragment(
      kind: StudioWorkbenchAssetKind.assetSection,
      sourceId: '$sourceId:$sectionKey',
      sourceBlock: sourceBlock,
      typeLabel: typeLabel,
      name: '$name / $typeLabel',
      fragment: fragment,
      targetIndex: targetIndex,
    );
  }

  void appendRecipe(Recipe recipe) {
    final tags = recipe.tags.trim();
    if (tags.isNotEmpty) {
      _appendPromptFragment(
        kind: StudioWorkbenchAssetKind.recipe,
        sourceId: recipe.id,
        sourceBlock: recipe.block,
        typeLabel: '配方',
        name: recipe.name,
        fragment: tags,
      );
      return;
    }
    _appendPromptFragment(
      kind: StudioWorkbenchAssetKind.recipe,
      sourceId: recipe.id,
      sourceBlock: recipe.block,
      typeLabel: '配方',
      name: recipe.name,
      fragment: recipe.variants.values.join(', '),
    );
  }

  void insertRecipe(Recipe recipe, int targetIndex) {
    final tags = recipe.tags.trim();
    _insertPromptFragment(
      kind: StudioWorkbenchAssetKind.recipe,
      sourceId: recipe.id,
      sourceBlock: recipe.block,
      typeLabel: '配方',
      name: recipe.name,
      fragment: tags.isNotEmpty ? tags : recipe.variants.values.join(', '),
      targetIndex: targetIndex,
    );
  }

  void appendTag(TagEntry tag) {
    _appendPromptFragment(
      kind: StudioWorkbenchAssetKind.tag,
      sourceId: tag.id,
      sourceBlock: tag.block,
      typeLabel: 'Tag',
      name: tag.zh.isEmpty ? tag.tag : tag.zh,
      fragment: tag.tag,
    );
  }

  void insertTag(TagEntry tag, int targetIndex) {
    _insertPromptFragment(
      kind: StudioWorkbenchAssetKind.tag,
      sourceId: tag.id,
      sourceBlock: tag.block,
      typeLabel: 'Tag',
      name: tag.zh.isEmpty ? tag.tag : tag.zh,
      fragment: tag.tag,
      targetIndex: targetIndex,
    );
  }

  void clearFragments() {
    if (_fragments.isEmpty) return;
    _fragments.clear();
    _syncPayload();
  }

  void resetCreativeState() {
    _manualPositivePrompt = '';
    _fragments.clear();
    payloadConfig.overridePrompt = '';
    payloadConfig.useOverridePrompt = false;
    payloadConfig.useCharacterPromptWithOverride = false;
    payloadConfig.characterConfigList = [];
    payloadConfig.paramConfig = ParamConfig();
    payloadConfig.i2iConfig.reset();
    payloadConfig.vibeConfigList = [];
    payloadConfig.vibeConfigListV4 = [];
    payloadConfig.preciseReferenceList = [];
    payloadConfig.usePreciseReference = false;
    notifyListeners();
  }

  void setManualPositivePrompt(String value) {
    _manualPositivePrompt = _normalizeFragment(value);
    _syncPayload();
  }

  void setManualNegativePrompt(String value) {
    payloadConfig.paramConfig.negativePrompt = value.trim();
    notifyListeners();
  }

  void updatePositiveText(String id, String value) {
    final fragment = _fragments.firstWhere((item) => item.id == id);
    fragment.positiveText = _normalizeFragment(value);
    _syncPayload();
  }

  void moveFragment(String id, int targetIndex) {
    final currentIndex = _fragments.indexWhere((item) => item.id == id);
    if (currentIndex < 0) return;

    final clampedIndex = targetIndex.clamp(0, _fragments.length - 1).toInt();
    final fragment = _fragments.removeAt(currentIndex);
    _fragments.insert(clampedIndex, fragment);
    _syncPayload();
  }

  void removeFragment(String id) {
    _fragments.removeWhere((fragment) => fragment.id == id);
    _syncPayload();
  }

  bool canSaveBack(StudioWorkbenchAssetFragment fragment) =>
      workspaceService != null &&
      fragment.isDirty &&
      fragment.kind != StudioWorkbenchAssetKind.outfitPart &&
      fragment.kind != StudioWorkbenchAssetKind.assetSection;

  Future<void> saveBack(String id) async {
    final workspace = workspaceService;
    if (workspace == null) {
      throw StateError('Workbench save-back needs an open workspace.');
    }
    final fragment = _fragments.firstWhere((item) => item.id == id);
    switch (fragment.kind) {
      case StudioWorkbenchAssetKind.character:
        await _saveCharacterPrompt(workspace, fragment);
        break;
      case StudioWorkbenchAssetKind.outfit:
        await _saveOutfitPrompt(workspace, fragment);
        break;
      case StudioWorkbenchAssetKind.outfitPart:
        throw StateError('Outfit part fragments cannot be saved back.');
      case StudioWorkbenchAssetKind.assetSection:
        throw StateError('Asset section fragments cannot be saved back.');
      case StudioWorkbenchAssetKind.artistChain:
        await _saveArtistChainPrompt(workspace, fragment);
        break;
      case StudioWorkbenchAssetKind.recipe:
        await _saveRecipePrompt(workspace, fragment);
        break;
      case StudioWorkbenchAssetKind.tag:
        await _saveTagPrompt(workspace, fragment);
        break;
    }
    fragment.originalPositiveText = fragment.positiveText;
    notifyListeners();
  }

  void _appendPromptFragment({
    required StudioWorkbenchAssetKind kind,
    required String sourceId,
    required String typeLabel,
    required String name,
    required String fragment,
    String? sourceBlock,
    String? sourceParentId,
  }) {
    _insertPromptFragment(
      kind: kind,
      sourceId: sourceId,
      sourceBlock: sourceBlock,
      sourceParentId: sourceParentId,
      typeLabel: typeLabel,
      name: name,
      fragment: fragment,
      targetIndex: _fragments.length,
    );
  }

  void _insertPromptFragment({
    required StudioWorkbenchAssetKind kind,
    required String sourceId,
    required String typeLabel,
    required String name,
    required String fragment,
    required int targetIndex,
    String? sourceBlock,
    String? sourceParentId,
  }) {
    final normalized = _normalizeFragment(fragment);
    if (normalized.isEmpty) return;

    final newFragment = StudioWorkbenchAssetFragment(
      id: _nextFragmentId(kind, sourceId),
      kind: kind,
      sourceId: sourceId,
      sourceBlock: sourceBlock,
      sourceParentId: sourceParentId,
      typeLabel: typeLabel,
      name: name,
      originalPositiveText: normalized,
      positiveText: normalized,
    );
    _fragments.add(newFragment);
    if (_fragments.length > 1) {
      moveFragment(newFragment.id, targetIndex);
      return;
    }
    _syncPayload();
  }

  String _normalizeFragment(String value) {
    return value
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .join(', ');
  }

  String _nextFragmentId(StudioWorkbenchAssetKind kind, String sourceId) {
    _nextFragmentNumber++;
    return '${kind.name}:$sourceId:$_nextFragmentNumber';
  }

  void _syncPayload() {
    payloadConfig.overridePrompt = [
      if (_manualPositivePrompt.isNotEmpty) _manualPositivePrompt,
      ..._fragments
          .map((fragment) => fragment.positiveText)
          .where((text) => text.isNotEmpty),
    ].join(', ');
    payloadConfig.useOverridePrompt = payloadConfig.overridePrompt.isNotEmpty;
    notifyListeners();
  }

  void _mergeArtistChainVibes(List<WorkspaceVibeReference> vibeRefs) {
    final usableRefs = vibeRefs
        .where((vibe) => vibe.vibeB64.trim().isNotEmpty)
        .toList(growable: false);
    if (usableRefs.isEmpty) {
      return;
    }

    final next = payloadConfig.vibeConfigListV4.toList();
    var changed = false;
    for (final vibe in usableRefs) {
      final encoding = vibe.vibeB64.trim();
      final existingIndex = next.indexWhere(
        (config) => config.vibeB64.trim() == encoding,
      );
      final nextConfig = VibeConfigV4(
        fileName: vibe.name.trim().isEmpty ? vibe.id : vibe.name,
        vibeB64: encoding,
        infoExtracted: vibe.infoExtracted,
        referenceStrength: vibe.referenceStrength,
        imageBytes: existingIndex >= 0 ? next[existingIndex].imageBytes : null,
        sourceImagePath:
            existingIndex >= 0 ? next[existingIndex].sourceImagePath : null,
      );
      if (existingIndex < 0) {
        next.add(nextConfig);
        changed = true;
        continue;
      }
      final existing = next[existingIndex];
      if (existing.fileName != nextConfig.fileName ||
          existing.infoExtracted != nextConfig.infoExtracted ||
          existing.referenceStrength != nextConfig.referenceStrength) {
        next[existingIndex] = nextConfig;
        changed = true;
      }
    }
    if (!changed) {
      if (!payloadConfig.generationRuntimeState.vibeEnabled) {
        payloadConfig.generationRuntimeState.vibeEnabled = true;
        notifyListeners();
      }
      return;
    }
    payloadConfig.setScriptVibeConfigV4List(next);
    payloadConfig.generationRuntimeState.vibeEnabled = true;
    notifyListeners();
  }

  Future<void> _saveCharacterPrompt(
    WorkspaceService workspace,
    StudioWorkbenchAssetFragment fragment,
  ) async {
    final characters = await workspace.loadCharacters();
    final updated = [
      for (final character in characters)
        if (character.id == fragment.sourceId)
          character.copyWith(
            traits: _replaceFrontFull(character.traits, fragment.positiveText),
          )
        else
          character,
    ];
    _ensureUpdated(
      characters,
      updated,
      (character) => character.id == fragment.sourceId,
      'character',
    );
    await workspace.saveCharacters(updated);
  }

  Future<void> _saveOutfitPrompt(
    WorkspaceService workspace,
    StudioWorkbenchAssetFragment fragment,
  ) async {
    final parentId = fragment.sourceParentId;
    if (parentId == null) {
      throw StateError('Outfit save-back needs a parent character id.');
    }
    final characters = await workspace.loadCharacters();
    var updatedOutfit = false;
    final updated = [
      for (final character in characters)
        if (character.id == parentId)
          character.copyWith(
            outfits: [
              for (final outfit in character.outfits)
                if (outfit.id == fragment.sourceId)
                  _updatedOutfit(outfit, fragment.positiveText,
                      markUpdated: () => updatedOutfit = true)
                else
                  outfit,
            ],
          )
        else
          character,
    ];
    if (!updatedOutfit) {
      throw StateError('Source outfit was not found.');
    }
    await workspace.saveCharacters(updated);
  }

  Future<void> _saveArtistChainPrompt(
    WorkspaceService workspace,
    StudioWorkbenchAssetFragment fragment,
  ) async {
    final artistChains = await workspace.loadArtistChains();
    final updated = [
      for (final artistChain in artistChains)
        if (artistChain.id == fragment.sourceId)
          artistChain.copyWith(prompt: fragment.positiveText)
        else
          artistChain,
    ];
    _ensureUpdated(
      artistChains,
      updated,
      (artistChain) => artistChain.id == fragment.sourceId,
      'artist chain',
    );
    await workspace.saveArtistChains(updated);
  }

  Future<void> _saveRecipePrompt(
    WorkspaceService workspace,
    StudioWorkbenchAssetFragment fragment,
  ) async {
    final block = fragment.sourceBlock;
    if (block == null) {
      throw StateError('Recipe save-back needs a source block.');
    }
    final recipes = await workspace.loadRecipes(block);
    final updated = [
      for (final recipe in recipes)
        if (recipe.id == fragment.sourceId)
          Recipe(
            id: recipe.id,
            name: recipe.name,
            block: recipe.block,
            category: recipe.category,
            group: recipe.group,
            tags: fragment.positiveText,
            variants: recipe.variants,
            imageRefs: recipe.imageRefs,
            source: recipe.source,
            note: recipe.note,
          )
        else
          recipe,
    ];
    _ensureUpdated(
      recipes,
      updated,
      (recipe) => recipe.id == fragment.sourceId,
      'recipe',
    );
    await workspace.saveRecipes(block, updated);
  }

  Future<void> _saveTagPrompt(
    WorkspaceService workspace,
    StudioWorkbenchAssetFragment fragment,
  ) async {
    final block = fragment.sourceBlock;
    if (block == null) {
      throw StateError('Tag save-back needs a source block.');
    }
    final tags = await workspace.loadTags(block);
    final updated = [
      for (final tag in tags)
        if (tag.id == fragment.sourceId)
          TagEntry(
            id: tag.id,
            tag: fragment.positiveText,
            zh: tag.zh,
            block: tag.block,
            category: tag.category,
            sections: tag.sections,
            aliases: tag.aliases,
            imageRefs: tag.imageRefs,
            source: tag.source,
            note: tag.note,
          )
        else
          tag,
    ];
    _ensureUpdated(tags, updated, (tag) => tag.id == fragment.sourceId, 'tag');
    await workspace.saveTags(block, updated);
  }

  WorkspaceOutfit _updatedOutfit(
    WorkspaceOutfit outfit,
    String positiveText, {
    required VoidCallback markUpdated,
  }) {
    markUpdated();
    return WorkspaceOutfit(
      id: outfit.id,
      name: outfit.name,
      tags: _replaceFrontFull(outfit.tags, positiveText),
      imageRefs: outfit.imageRefs,
      note: outfit.note,
    );
  }

  ViewVariantTexts _replaceFrontFull(ViewVariantTexts source, String value) {
    return ViewVariantTexts(
      frontFull: value,
      frontCowboy: source.frontCowboy,
      frontUpper: source.frontUpper,
      frontLower: source.frontLower,
      backFull: source.backFull,
      backCowboy: source.backCowboy,
      backUpper: source.backUpper,
      backLower: source.backLower,
    );
  }

  void _ensureUpdated<T>(
    List<T> before,
    List<T> after,
    bool Function(T item) matches,
    String label,
  ) {
    if (before.length != after.length || !before.any(matches)) {
      throw StateError('Source $label was not found.');
    }
  }
}
