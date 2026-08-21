import 'package:novel_studio/data/studio/tools/artist_chain_v5_prompt_policy.dart';

export 'package:novel_studio/data/studio/tools/artist_chain_v5_prompt_policy.dart';

/// Builds the controlled V5 prompt using the same de-duplicating tag split
/// behavior as StudioAssetPreviewGenerationService.
String buildArtistChainV5TestPrompt({
  required Iterable<String> artistTerms,
  required String characterName,
  required String characterFrontFull,
  Iterable<String> characterIdentityTags = const [],
  Iterable<String> characterAnchorTags = const [],
  bool stripRealisticMediumTags = false,
}) {
  final filteredArtistTerms = stripRealisticMediumTags
      ? filterArtistChainV5MediumTags(artistTerms)
      : artistTerms;
  return joinArtistChainV5PromptParts([
    ...filteredArtistTerms,
    artistChainV5QualityTerms,
    characterName,
    characterFrontFull,
    ...characterIdentityTags,
    ...characterAnchorTags,
    if (stripRealisticMediumTags) ...artistChainV5MediumGuardTerms,
    ...artistChainV5CompositionTerms,
  ]);
}
