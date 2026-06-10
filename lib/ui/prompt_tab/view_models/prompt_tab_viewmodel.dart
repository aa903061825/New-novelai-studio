import 'package:flutter/foundation.dart';
import 'package:nai_casrand/data/models/character_config.dart';
import 'package:nai_casrand/data/models/prompt_config.dart';
import 'package:nai_casrand/data/models/prompt_replace_rule.dart';

enum PromptDashboardPanel {
  basePrompt,
  characters,
  replaceRules,
  savedConfigs,
}

class PromptTabViewmodel extends ChangeNotifier {
  static const maxCharacterCount = 6;

  PromptConfig promptConfig;
  List<CharacterConfig> characterConfigList;
  List<PromptConfig> savedConfigList;
  List<PromptReplaceRule> promptReplaceRules;
  String batchReplaceRuleInput = '';

  PromptDashboardPanel _activePanel = PromptDashboardPanel.basePrompt;

  PromptTabViewmodel({
    required this.promptConfig,
    required this.characterConfigList,
    required this.savedConfigList,
    required this.promptReplaceRules,
  });

  PromptDashboardPanel get activePanel => _activePanel;

  int get enabledReplaceRuleCount =>
      promptReplaceRules.where((rule) => rule.enabled).length;

  int get validReplaceRuleCount =>
      promptReplaceRules.where((rule) => rule.source.isNotEmpty).length;

  int get skippedReplaceRuleCount =>
      promptReplaceRules.where((rule) => rule.source.isEmpty).length;

  void setActivePanel(PromptDashboardPanel panel) {
    _activePanel = panel;
    notifyListeners();
  }

  void reorderCharacter(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }
    var item = characterConfigList.removeAt(oldIndex);
    characterConfigList.insert(newIndex, item);
    notifyListeners();
  }

  void removeCharacter(int index) {
    characterConfigList.removeAt(index);
    notifyListeners();
  }

  void addCharacter() {
    if (characterConfigList.length >= maxCharacterCount) return;
    characterConfigList.add(
      CharacterConfig.fromEmpty(name: '角色 ${characterConfigList.length + 1}'),
    );
    notifyListeners();
  }

  void addReplaceRule() {
    promptReplaceRules.add(PromptReplaceRule.fromEmpty());
    notifyListeners();
  }

  void updateBatchReplaceRuleInput(String value) {
    batchReplaceRuleInput = value;
    notifyListeners();
  }

  List<String> parseBatchReplaceRuleInput(String rawInput) {
    return rawInput
        .split(RegExp(r'[,，\n\r]+'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  void addReplaceRulesFromBatchInput() {
    final sources = parseBatchReplaceRuleInput(batchReplaceRuleInput);
    if (sources.isEmpty) {
      return;
    }

    promptReplaceRules.addAll(
      sources.map(
        (source) => PromptReplaceRule.fromEmpty().copyWith(source: source),
      ),
    );
    batchReplaceRuleInput = '';
    notifyListeners();
  }

  void removeReplaceRule(int index) {
    if (index < 0 || index >= promptReplaceRules.length) return;
    promptReplaceRules.removeAt(index);
    notifyListeners();
  }

  void duplicateReplaceRule(int index) {
    if (index < 0 || index >= promptReplaceRules.length) return;
    final duplicated = promptReplaceRules[index].copyWith(
      id: PromptReplaceRule.fromEmpty().id,
    );
    promptReplaceRules.insert(index + 1, duplicated);
    notifyListeners();
  }

  void reorderReplaceRule(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= promptReplaceRules.length) return;
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }
    final item = promptReplaceRules.removeAt(oldIndex);
    if (newIndex < 0) {
      promptReplaceRules.insert(0, item);
    } else if (newIndex >= promptReplaceRules.length) {
      promptReplaceRules.add(item);
    } else {
      promptReplaceRules.insert(newIndex, item);
    }
    notifyListeners();
  }

  void updateReplaceRuleSource(int index, String value) {
    if (index < 0 || index >= promptReplaceRules.length) return;
    promptReplaceRules[index].source = value;
    notifyListeners();
  }

  void updateReplaceRuleTarget(int index, String value) {
    if (index < 0 || index >= promptReplaceRules.length) return;
    promptReplaceRules[index].target = value;
    notifyListeners();
  }

  void toggleReplaceRule(int index, bool enabled) {
    if (index < 0 || index >= promptReplaceRules.length) return;
    promptReplaceRules[index].enabled = enabled;
    notifyListeners();
  }
}
