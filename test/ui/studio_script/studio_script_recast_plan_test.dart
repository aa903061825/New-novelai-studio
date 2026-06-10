import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/ui/studio_script/models/studio_script_recast_plan.dart';

void main() {
  group('StudioScriptRecastPlan', () {
    test('defaults to an empty non AI-backed plan', () {
      const plan = StudioScriptRecastPlan();

      expect(plan.roles, isEmpty);
      expect(plan.artist.sourceLabel, isEmpty);
      expect(plan.artist.selectedArtistChainId, isNull);
      expect(plan.issues, isEmpty);
      expect(plan.frameReviews, isEmpty);
      expect(plan.hasAiBackedPlan, isFalse);
    });

    test('constructs role and artist projections with defaults', () {
      const role = StudioScriptPlanRole(
        sourceRoleId: 'role-1',
        label: 'Hero',
      );
      const artist = StudioScriptPlanArtist(sourceLabel: 'artist:source');

      expect(role.sourceRoleId, 'role-1');
      expect(role.label, 'Hero');
      expect(role.sourceName, isEmpty);
      expect(role.selectedCharacterId, isNull);
      expect(role.selectedStageLabel, isEmpty);
      expect(role.statusLabel, isEmpty);
      expect(role.confidence, 0);

      expect(artist.sourceLabel, 'artist:source');
      expect(artist.selectedArtistChainId, isNull);
    });

    test('constructs issues with required kind and const frame indexes', () {
      const issue = StudioScriptPlanIssue(
        id: 'issue-1',
        title: 'Duplicate role',
        kind: StudioScriptPlanIssueKind.duplicateRole,
      );

      expect(issue.id, 'issue-1');
      expect(issue.title, 'Duplicate role');
      expect(issue.kind, StudioScriptPlanIssueKind.duplicateRole);
      expect(issue.detail, isEmpty);
      expect(issue.frameIndexes, isEmpty);
    });

    test('constructs frame reviews and tokens with default token metadata', () {
      const token = StudioScriptReviewToken(source: '1girl');
      const review = StudioScriptFrameReview(
        frameIndex: 2,
        title: 'Frame 2',
        positiveTokens: [token],
      );

      expect(token.source, '1girl');
      expect(token.translation, isEmpty);
      expect(token.category, StudioScriptTokenCategory.other);
      expect(token.emphasis, StudioScriptTokenEmphasis.normal);

      expect(review.frameIndex, 2);
      expect(review.title, 'Frame 2');
      expect(review.positiveTokens, [token]);
      expect(review.negativeTokens, isEmpty);
    });

    test('accepts populated plan projections', () {
      const plan = StudioScriptRecastPlan(
        roles: [
          StudioScriptPlanRole(
            sourceRoleId: 'role-1',
            label: 'Hero',
            sourceName: 'source hero',
            selectedCharacterId: 'character-1',
            selectedStageLabel: 'Stage A',
            statusLabel: 'Matched',
            confidence: 0.92,
          ),
        ],
        artist: StudioScriptPlanArtist(
          sourceLabel: 'artist:source',
          selectedArtistChainId: 'artist-chain-1',
        ),
        issues: [
          StudioScriptPlanIssue(
            id: 'issue-1',
            title: 'Low confidence',
            kind: StudioScriptPlanIssueKind.lowConfidence,
            detail: 'Needs review',
            frameIndexes: [0, 2],
          ),
        ],
        frameReviews: [
          StudioScriptFrameReview(
            frameIndex: 0,
            title: 'Opening frame',
            positiveTokens: [
              StudioScriptReviewToken(
                source: 'hero',
                translation: 'Hero',
                category: StudioScriptTokenCategory.character,
                emphasis: StudioScriptTokenEmphasis.aiRecognized,
              ),
            ],
            negativeTokens: [
              StudioScriptReviewToken(
                source: 'bad hands',
                category: StudioScriptTokenCategory.negativeBody,
                emphasis: StudioScriptTokenEmphasis.replacementAffected,
              ),
            ],
          ),
        ],
        hasAiBackedPlan: true,
      );

      expect(plan.roles.single.selectedCharacterId, 'character-1');
      expect(plan.artist.selectedArtistChainId, 'artist-chain-1');
      expect(plan.issues.single.frameIndexes, [0, 2]);
      expect(plan.frameReviews.single.positiveTokens.single.category,
          StudioScriptTokenCategory.character);
      expect(plan.frameReviews.single.negativeTokens.single.emphasis,
          StudioScriptTokenEmphasis.replacementAffected);
      expect(plan.hasAiBackedPlan, isTrue);
    });
  });
}
