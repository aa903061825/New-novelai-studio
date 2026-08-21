import 'package:novel_studio/data/models/generation_capabilities.dart';
import 'package:novel_studio/data/workspace/models/workspace_entities.dart';

enum ArtistChainPreviewFamilyFilter {
  all,
  v45,
  v5,
  unclassified,
}

List<String> artistChainPreviewRefsForFilter(
  ArtistChain chain,
  ArtistChainPreviewFamilyFilter filter,
) {
  return switch (filter) {
    ArtistChainPreviewFamilyFilter.all => chain.allPreviewRefs,
    ArtistChainPreviewFamilyFilter.v45 =>
      chain.previewRefsForFamily(generationPreviewFamilyV45),
    ArtistChainPreviewFamilyFilter.v5 =>
      chain.previewRefsForFamily(generationPreviewFamilyV5),
    ArtistChainPreviewFamilyFilter.unclassified => _unclassifiedRefs(chain),
  };
}

List<String> _unclassifiedRefs(ArtistChain chain) {
  final classified =
      chain.modelPreviewRefs.values.expand((refs) => refs).toSet();
  return List.unmodifiable([
    for (final ref in chain.imageRefs)
      if (ref.trim().isNotEmpty && !classified.contains(ref)) ref,
  ]);
}
