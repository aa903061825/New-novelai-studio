import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/data/models/prompt_config.dart';
import 'package:novel_studio/ui/prompt_config/view_models/prompt_config_viewmodel.dart';

void main() {
  test('setStrs normalizes CRLF rows without saving blank carriage returns',
      () {
    final config = PromptConfig(strs: const [], prompts: const []);
    final viewModel = PromptConfigViewModel(config: config);

    viewModel.setStrs('scene 1\r\n\r\n,\r\nscene 2\n  \n');

    expect(config.strs, ['scene 1', ',', 'scene 2']);
  });
}
