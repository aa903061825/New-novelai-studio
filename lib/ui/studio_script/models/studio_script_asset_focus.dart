enum StudioScriptAssetFocusKind { character, outfit, artistChain }

class StudioScriptAssetFocus {
  final StudioScriptAssetFocusKind kind;
  final String? characterId;
  final String? outfitId;
  final String? artistChainId;
  final int nonce;

  const StudioScriptAssetFocus.character({
    required this.characterId,
    this.nonce = 0,
  })  : kind = StudioScriptAssetFocusKind.character,
        outfitId = null,
        artistChainId = null;

  const StudioScriptAssetFocus.outfit({
    required this.characterId,
    required this.outfitId,
    this.nonce = 0,
  })  : kind = StudioScriptAssetFocusKind.outfit,
        artistChainId = null;

  const StudioScriptAssetFocus.artistChain({
    required this.artistChainId,
    this.nonce = 0,
  })  : kind = StudioScriptAssetFocusKind.artistChain,
        characterId = null,
        outfitId = null;

  String get drawerCardKey {
    return switch (kind) {
      StudioScriptAssetFocusKind.character =>
        'script-asset-character-$characterId',
      StudioScriptAssetFocusKind.outfit =>
        'script-asset-character-$characterId-outfit-$outfitId',
      StudioScriptAssetFocusKind.artistChain =>
        'script-asset-artist-$artistChainId',
    };
  }
}
