import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/ui/studio_core/services/prompt_tag_list_utils.dart';

void main() {
  group('prompt tag list utils', () {
    test('selects tags by sorted valid indexes', () {
      expect(
        promptTagsForIndexes(['alpha', 'beta', 'gamma'], {2, -1, 0, 9}),
        ['alpha', 'gamma'],
      );
    });

    test('joins trimmed non-empty tags', () {
      expect(
        joinPromptTags([' alpha ', '', ' beta', '   ', 'gamma ']),
        'alpha, beta, gamma',
      );
    });

    test('uses fallback when tag prompt is empty', () {
      expect(
        promptTagsToPrompt([' ', ''], fallback: ' fallback prompt '),
        'fallback prompt',
      );
      expect(
        promptTagsToPrompt(['alpha', ' beta '], fallback: 'fallback'),
        'alpha, beta',
      );
    });

    test('clamps insertion index to tag list bounds', () {
      final tags = ['alpha', 'beta'];

      expect(clampPromptTagInsertIndex(-3, tags), 0);
      expect(clampPromptTagInsertIndex(1, tags), 1);
      expect(clampPromptTagInsertIndex(9, tags), 2);
    });
  });
}
