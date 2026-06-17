import 'package:novel_studio/data/studio/services/studio_asset_catalog_service.dart';
import 'package:novel_studio/data/studio/tools/filter_rule_config.dart';
import 'package:novel_studio/data/studio/tools/prompt_tag_processor.dart';
import 'package:novel_studio/data/workspace/models/workspace_entities.dart';

class ScriptRecastAssetContextService {
  final StudioAssetCatalogService catalogService;

  const ScriptRecastAssetContextService({
    required this.catalogService,
  });

  Future<ScriptRecastAssetContext> loadContext() async {
    final snapshot = await catalogService.loadSnapshot();
    final filterRules = await catalogService.loadWorkbenchFilterRules();
    final characters = List<CharacterEntry>.unmodifiable(snapshot.characters);
    final outfits = List<StudioOutfitAsset>.unmodifiable(snapshot.outfits);
    final artistChains = List<ArtistChain>.unmodifiable(snapshot.artistChains);
    final characterPreviewPaths = <String, String>{};
    final outfitPreviewPaths = <String, String>{};
    final artistChainPreviewPaths = <String, String>{};

    for (final character in characters) {
      final path = catalogService.resolveImagePath(character.imageRefs);
      if (path != null) {
        characterPreviewPaths[character.id] = path;
      }
    }
    for (final outfit in outfits) {
      final path = catalogService.resolveImagePath(outfit.outfit.imageRefs);
      if (path != null) {
        outfitPreviewPaths[ScriptRecastAssetContext.outfitKey(
          outfit.character.id,
          outfit.outfit.id,
        )] = path;
      }
    }
    for (final chain in artistChains) {
      final path = catalogService.resolveImagePath(chain.imageRefs);
      if (path != null) {
        artistChainPreviewPaths[chain.id] = path;
      }
    }

    return ScriptRecastAssetContext(
      characters: characters,
      outfits: outfits,
      artistChains: artistChains,
      characterPreviewPaths: Map.unmodifiable(characterPreviewPaths),
      outfitPreviewPaths: Map.unmodifiable(outfitPreviewPaths),
      artistChainPreviewPaths: Map.unmodifiable(artistChainPreviewPaths),
      filterRules: FilterRuleConfig.fromMap(filterRules),
      filterMetadata: ScriptRecastFilterMetadata.fromRules(filterRules),
    );
  }
}

class ScriptRecastAssetContext {
  final List<CharacterEntry> characters;
  final List<StudioOutfitAsset> outfits;
  final List<ArtistChain> artistChains;
  final Map<String, String> characterPreviewPaths;
  final Map<String, String> outfitPreviewPaths;
  final Map<String, String> artistChainPreviewPaths;
  final FilterRuleConfig filterRules;
  final ScriptRecastFilterMetadata filterMetadata;
  late final Map<String, CharacterEntry> characterById = Map.unmodifiable(
      {for (final character in characters) character.id: character});
  late final Map<String, ArtistChain> artistChainById =
      Map.unmodifiable({for (final chain in artistChains) chain.id: chain});
  late final Map<String, List<StudioOutfitAsset>> outfitsByCharacterId =
      Map.unmodifiable(_outfitsByCharacter(outfits));

  ScriptRecastAssetContext({
    required this.characters,
    required this.outfits,
    required this.artistChains,
    this.characterPreviewPaths = const {},
    this.outfitPreviewPaths = const {},
    this.artistChainPreviewPaths = const {},
    required this.filterRules,
    required this.filterMetadata,
  });

  StudioOutfitAsset? defaultOutfitFor(String characterId) {
    final character = characterById[characterId];
    final defaultOutfitId = character?.defaultOutfitId;
    if (defaultOutfitId == null || defaultOutfitId.isEmpty) {
      return null;
    }
    for (final outfit in outfitsByCharacterId[characterId] ?? const []) {
      if (outfit.outfit.id == defaultOutfitId) {
        return outfit;
      }
    }
    return null;
  }

  static Map<String, List<StudioOutfitAsset>> _outfitsByCharacter(
    List<StudioOutfitAsset> outfits,
  ) {
    final grouped = <String, List<StudioOutfitAsset>>{};
    for (final outfit in outfits) {
      grouped.putIfAbsent(outfit.character.id, () => []).add(outfit);
    }
    return {
      for (final entry in grouped.entries)
        entry.key: List<StudioOutfitAsset>.unmodifiable(entry.value),
    };
  }

  static String outfitKey(String characterId, String outfitId) =>
      '$characterId::$outfitId';
}

class ScriptRecastFilterMetadata {
  final bool isConfigured;
  final bool isEnabled;
  final int deleteKeywordCount;
  final int strongFilterKeywordCount;
  final int replaceRuleCount;
  final bool deleteArtistTags;

  const ScriptRecastFilterMetadata({
    required this.isConfigured,
    required this.isEnabled,
    required this.deleteKeywordCount,
    required this.strongFilterKeywordCount,
    required this.replaceRuleCount,
    required this.deleteArtistTags,
  });

  factory ScriptRecastFilterMetadata.fromRules(Map<String, dynamic> rules) {
    if (rules.isEmpty) {
      return const ScriptRecastFilterMetadata.empty();
    }
    final config = FilterRuleConfig.fromMap(rules);
    final deleteKeywordCount = _ruleWordCount(config.deleteKeywords);
    final strongFilterKeywordCount =
        _ruleWordCount(config.strongFilterKeywords);
    final replaceRuleCount =
        PromptTagProcessor.parseReplaceRulesText(config.replaceRules).length;
    final enabled = deleteKeywordCount > 0 ||
        strongFilterKeywordCount > 0 ||
        replaceRuleCount > 0 ||
        config.deleteArtistTags;
    return ScriptRecastFilterMetadata(
      isConfigured: true,
      isEnabled: enabled,
      deleteKeywordCount: deleteKeywordCount,
      strongFilterKeywordCount: strongFilterKeywordCount,
      replaceRuleCount: replaceRuleCount,
      deleteArtistTags: config.deleteArtistTags,
    );
  }

  const ScriptRecastFilterMetadata.empty()
      : isConfigured = false,
        isEnabled = false,
        deleteKeywordCount = 0,
        strongFilterKeywordCount = 0,
        replaceRuleCount = 0,
        deleteArtistTags = false;
}

int _ruleWordCount(String text) {
  return text
      .split(RegExp(r'[,，\n]'))
      .map((word) => word.trim())
      .where((word) => word.isNotEmpty)
      .length;
}
