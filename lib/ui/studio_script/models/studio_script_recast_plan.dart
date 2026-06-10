enum StudioScriptPlanIssueKind {
  lowConfidence,
  duplicateRole,
  cacheConflict,
  assetConflict,
  aiBatchFailed,
  highImpact,
}

enum StudioScriptTokenCategory {
  character,
  upperBody,
  lowerBody,
  upperClothing,
  lowerClothing,
  action,
  scene,
  camera,
  artistChain,
  style,
  quality,
  negativeQuality,
  negativeBody,
  negativeArtist,
  negativeContent,
  other,
}

enum StudioScriptTokenEmphasis {
  normal,
  aiRecognized,
  cacheHit,
  userConfirmed,
  replacementAffected,
}

class StudioScriptRecastPlan {
  final List<StudioScriptPlanRole> roles;
  final StudioScriptPlanArtist artist;
  final List<StudioScriptPlanIssue> issues;
  final List<StudioScriptFrameReview> frameReviews;
  final bool hasAiBackedPlan;

  const StudioScriptRecastPlan({
    this.roles = const [],
    this.artist = const StudioScriptPlanArtist(),
    this.issues = const [],
    this.frameReviews = const [],
    this.hasAiBackedPlan = false,
  });
}

class StudioScriptPlanRole {
  final String sourceRoleId;
  final String label;
  final String sourceName;
  final String? selectedCharacterId;
  final String selectedStageLabel;
  final String statusLabel;
  final double confidence;

  const StudioScriptPlanRole({
    required this.sourceRoleId,
    required this.label,
    this.sourceName = '',
    this.selectedCharacterId,
    this.selectedStageLabel = '',
    this.statusLabel = '',
    this.confidence = 0,
  });
}

class StudioScriptPlanArtist {
  final String sourceLabel;
  final String? selectedArtistChainId;
  final String manualPrompt;

  const StudioScriptPlanArtist({
    this.sourceLabel = '',
    this.selectedArtistChainId,
    this.manualPrompt = '',
  });
}

class StudioScriptPlanIssue {
  final String id;
  final String title;
  final StudioScriptPlanIssueKind kind;
  final String detail;
  final List<int> frameIndexes;

  const StudioScriptPlanIssue({
    required this.id,
    required this.title,
    required this.kind,
    this.detail = '',
    this.frameIndexes = const [],
  });
}

class StudioScriptFrameReview {
  final int frameIndex;
  final String title;
  final List<StudioScriptReviewToken> positiveTokens;
  final List<StudioScriptReviewToken> negativeTokens;
  final List<StudioScriptReviewTokenGroup> positiveTokenGroups;
  final List<StudioScriptReviewTokenGroup> negativeTokenGroups;

  const StudioScriptFrameReview({
    required this.frameIndex,
    required this.title,
    this.positiveTokens = const [],
    this.negativeTokens = const [],
    this.positiveTokenGroups = const [],
    this.negativeTokenGroups = const [],
  });

  List<StudioScriptReviewTokenGroup> get effectivePositiveTokenGroups {
    if (positiveTokenGroups.isNotEmpty) return positiveTokenGroups;
    if (positiveTokens.isEmpty) return const [];
    return [
      StudioScriptReviewTokenGroup(
        id: 'positive',
        label: '正向源词',
        tokens: positiveTokens,
      ),
    ];
  }

  List<StudioScriptReviewTokenGroup> get effectiveNegativeTokenGroups {
    if (negativeTokenGroups.isNotEmpty) return negativeTokenGroups;
    if (negativeTokens.isEmpty) return const [];
    return [
      StudioScriptReviewTokenGroup(
        id: 'negative',
        label: '负面源词',
        tokens: negativeTokens,
        negative: true,
      ),
    ];
  }
}

class StudioScriptReviewTokenGroup {
  final String id;
  final String label;
  final List<StudioScriptReviewToken> tokens;
  final bool negative;

  const StudioScriptReviewTokenGroup({
    required this.id,
    required this.label,
    this.tokens = const [],
    this.negative = false,
  });
}

class StudioScriptReviewToken {
  final String source;
  final String translation;
  final StudioScriptTokenCategory category;
  final StudioScriptTokenEmphasis emphasis;

  const StudioScriptReviewToken({
    required this.source,
    this.translation = '',
    this.category = StudioScriptTokenCategory.other,
    this.emphasis = StudioScriptTokenEmphasis.normal,
  });
}
