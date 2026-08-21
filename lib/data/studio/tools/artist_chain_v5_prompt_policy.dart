import 'package:novel_studio/data/studio/tools/prompt_tag_processor.dart';

/// Shared prompt policy for V5 artist-chain previews and their test harness.
const artistChainV5QualityTerms =
    'masterpiece, best quality, amazing quality, very aesthetic, absurdres';

const artistChainV5MediumGuardTerms = [
  '2d',
  'anime illustration',
  'illustration',
];

const artistChainV5MediumNegativeTerms = [
  '3d',
  'cgi',
  'photorealistic',
  'realistic',
  'photograph',
  'photography',
  'photo',
  'live action',
  'real person',
];

const artistChainV5CompositionTerms = [
  '1girl',
  'solo',
  'upper body',
  'looking at viewer',
  'simple plain background',
  'character focus',
  'clean readable pose',
  'no text',
  'no watermark',
];

/// Suppresses the learned artist-collaboration / multi-avatar tendency in
/// artist-chain previews. The spaces are the canonical inline-weight format.
const artistChainV5CollaborationNegativeTerm = '-6:: 画师合作 ::';

const artistChainV5NegativeTerms = [
  artistChainV5CollaborationNegativeTerm,
];

Iterable<String> filterArtistChainV5MediumTags(Iterable<String> tags) sync* {
  for (final tag in tags) {
    for (final part in PromptTagProcessor.splitWorkshopTags(tag)) {
      if (_isArtistChainV5RealisticMediumTag(part)) continue;
      yield part;
    }
  }
}

bool artistChainV5HasRealisticMediumTags(Iterable<String> tags) {
  for (final tag in tags) {
    for (final part in PromptTagProcessor.splitWorkshopTags(tag)) {
      if (_isArtistChainV5RealisticMediumTag(part)) return true;
    }
  }
  return false;
}

/// Keeps non-artist style fragments from a legacy raw prompt while avoiding a
/// second copy of the structured `artists` list.
Iterable<String> artistChainV5NonArtistPromptTerms(String prompt) sync* {
  for (final part in PromptTagProcessor.splitWorkshopTags(prompt)) {
    final display = PromptTagProcessor.describeWorkshopTag(part).displayText;
    final normalized = PromptTagProcessor.normalizeMatchKey(display);
    if (normalized.startsWith('artist:') || normalized.startsWith('artist ')) {
      continue;
    }
    yield part;
  }
}

bool _isArtistChainV5RealisticMediumTag(String tag) {
  final display = PromptTagProcessor.describeWorkshopTag(tag).displayText;
  final normalized = PromptTagProcessor.normalizeMatchKey(display);
  return artistChainV5MediumNegativeTerms.contains(normalized);
}

String joinArtistChainV5PromptParts(Iterable<String> parts) {
  final seen = <String>{};
  final result = <String>[];
  for (final part in parts) {
    for (final tag in PromptTagProcessor.splitWorkshopTags(part)
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)) {
      final normalized = tag.toLowerCase();
      if (!seen.add(normalized)) continue;
      result.add(tag);
    }
  }
  return result.join(', ');
}
