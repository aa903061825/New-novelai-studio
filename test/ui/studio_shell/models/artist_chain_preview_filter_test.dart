import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/data/workspace/models/workspace_entities.dart';
import 'package:novel_studio/ui/studio_shell/models/artist_chain_preview_filter.dart';

void main() {
  const chain = ArtistChain(
    id: 'artist-1',
    name: 'Painter',
    imageRefs: [
      'assets/references/legacy-v45.png',
      'assets/references/unclassified.png',
    ],
    modelPreviewRefs: {
      'v4_5': ['assets/references/legacy-v45.png'],
      'v5': ['assets/references/new-v5.png'],
    },
  );

  test('returns only the selected model family', () {
    expect(
      artistChainPreviewRefsForFilter(
        chain,
        ArtistChainPreviewFamilyFilter.v45,
      ),
      ['assets/references/legacy-v45.png'],
    );
    expect(
      artistChainPreviewRefsForFilter(
        chain,
        ArtistChainPreviewFamilyFilter.v5,
      ),
      ['assets/references/new-v5.png'],
    );
  });

  test(
      'keeps legacy refs visible as unclassified until migration classifies them',
      () {
    expect(
      artistChainPreviewRefsForFilter(
        chain,
        ArtistChainPreviewFamilyFilter.unclassified,
      ),
      ['assets/references/unclassified.png'],
    );
  });
}
