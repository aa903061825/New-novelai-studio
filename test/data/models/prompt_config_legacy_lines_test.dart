import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/data/models/prompt_config.dart';

Map<String, dynamic> _promptJson(List<String> strs) {
  return {
    'selectionMethod': 'single_sequential',
    'shuffled': false,
    'prob': 0.0,
    'num': 1,
    'randomBracketsUpper': 0,
    'randomBracketsLower': 0,
    'type': 'str',
    'comment': 'legacy lines',
    'filter': '',
    'strs': strs,
    'prompts': const [],
    'enabled': true,
  };
}

void main() {
  test('normalizes legacy CRLF prompt rows and keeps comma placeholders', () {
    final config = PromptConfig.fromJson(_promptJson([
      'scene 1\r\nscene 2',
      '\r',
      '   ',
      ',\r',
      'scene 3\n\nscene 4',
    ]));

    expect(config.strs, [
      'scene 1',
      'scene 2',
      ',',
      'scene 3',
      'scene 4',
    ]);
  });
}
