import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/data/models/character_config.dart';
import 'package:novel_studio/data/models/prompt_config.dart';
import 'package:novel_studio/data/models/prompt_replace_rule.dart';
import 'package:novel_studio/ui/prompt_tab/view_models/prompt_tab_viewmodel.dart';

PromptTabViewmodel _buildViewmodel() {
  return PromptTabViewmodel(
    promptConfig: PromptConfig(strs: const [], prompts: const []),
    characterConfigList: <CharacterConfig>[],
    savedConfigList: <PromptConfig>[],
    promptReplaceRules: <PromptReplaceRule>[],
  );
}

void main() {
  test('can add, edit, toggle, duplicate, delete and reorder replacement rules',
      () {
    final viewmodel = _buildViewmodel();

    viewmodel.addReplaceRule();
    expect(viewmodel.promptReplaceRules.length, 1);

    final firstRule = viewmodel.promptReplaceRules.first;
    expect(firstRule.source, '');
    expect(firstRule.target, '');
    expect(firstRule.enabled, isTrue);

    viewmodel.updateReplaceRuleSource(0, 'cat');
    viewmodel.updateReplaceRuleTarget(0, 'dog');
    expect(viewmodel.promptReplaceRules[0].source, 'cat');
    expect(viewmodel.promptReplaceRules[0].target, 'dog');

    viewmodel.toggleReplaceRule(0, false);
    expect(viewmodel.promptReplaceRules[0].enabled, isFalse);

    viewmodel.duplicateReplaceRule(0);
    expect(viewmodel.promptReplaceRules.length, 2);
    expect(viewmodel.promptReplaceRules[1].source, 'cat');
    expect(viewmodel.promptReplaceRules[1].target, 'dog');
    expect(viewmodel.promptReplaceRules[1].enabled, isFalse);

    viewmodel.updateReplaceRuleSource(1, 'bird');
    viewmodel.reorderReplaceRule(1, 0);
    expect(viewmodel.promptReplaceRules[0].source, 'bird');
    expect(viewmodel.promptReplaceRules[1].source, 'cat');

    viewmodel.removeReplaceRule(0);
    expect(viewmodel.promptReplaceRules.length, 1);
    expect(viewmodel.promptReplaceRules.first.source, 'cat');
  });

  test('switches active dashboard panel', () {
    final viewmodel = _buildViewmodel();

    expect(viewmodel.activePanel, PromptDashboardPanel.basePrompt);

    viewmodel.setActivePanel(PromptDashboardPanel.replaceRules);
    expect(viewmodel.activePanel, PromptDashboardPanel.replaceRules);

    viewmodel.setActivePanel(PromptDashboardPanel.characters);
    expect(viewmodel.activePanel, PromptDashboardPanel.characters);
  });

  test('creates replacement rules from batch input and clears the draft', () {
    final viewmodel = _buildViewmodel();

    viewmodel.updateBatchReplaceRuleInput(
      ' pink dress,white jacket\nshort jacket， black boots ,, ',
    );

    viewmodel.addReplaceRulesFromBatchInput();

    expect(
      viewmodel.promptReplaceRules.map((rule) => rule.source).toList(),
      ['pink dress', 'white jacket', 'short jacket', 'black boots'],
    );
    expect(
      viewmodel.promptReplaceRules.every((rule) => rule.target.isEmpty),
      isTrue,
    );
    expect(
      viewmodel.promptReplaceRules.every((rule) => rule.enabled),
      isTrue,
    );
    expect(viewmodel.batchReplaceRuleInput, '');
  });
}
