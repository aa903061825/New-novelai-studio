import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/data/studio/tools/filter_rule_config.dart';
import 'package:novel_studio/ui/studio_core/services/prompt_tag_filter_rules.dart';

void main() {
  test('adding filter rule tags preserves global prompt prefix', () {
    const config = FilterRuleConfig(
      deleteKeywords: 'lowres',
      strongFilterKeywords: 'mosaic',
      replaceRules: 'old -> new',
      globalPromptPrefix: 'best quality, detailed lighting',
      removeWeights: false,
      exactMatch: false,
      deleteArtistTags: true,
    );

    final deleteUpdated = addTagsToFilterRuleConfig(
      config,
      const ['bad hands'],
      PromptTagFilterRuleTarget.deleteKeywords,
    );
    final strongUpdated = addTagsToFilterRuleConfig(
      config,
      const ['censor bar'],
      PromptTagFilterRuleTarget.strongFilterKeywords,
    );
    final replaceUpdated = addTagsToFilterRuleConfig(
      config,
      const ['blue dress'],
      PromptTagFilterRuleTarget.replaceSource,
    );

    for (final updated in [deleteUpdated, strongUpdated, replaceUpdated]) {
      expect(updated.globalPromptPrefix, config.globalPromptPrefix);
      expect(updated.removeWeights, config.removeWeights);
      expect(updated.exactMatch, config.exactMatch);
      expect(updated.deleteArtistTags, config.deleteArtistTags);
    }
  });
}
