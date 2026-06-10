import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:nai_casrand/ui/character_config/widgets/character_config_view.dart';
import 'package:nai_casrand/ui/character_config/view_models/character_config_viewmodel.dart';
import 'package:nai_casrand/ui/prompt_tab/view_models/prompt_tab_viewmodel.dart';
import 'package:nai_casrand/ui/prompt_config/widgets/prompt_config_view.dart';
import 'package:nai_casrand/ui/prompt_config/view_models/prompt_config_viewmodel.dart';
import 'package:nai_casrand/ui/prompt_tab/widgets/prompt_dashboard_card.dart';
import 'package:nai_casrand/ui/prompt_tab/widgets/prompt_replace_rules_editor.dart';
import 'package:nai_casrand/ui/saved_config_list/view_models/saved_config_list_viewmodel.dart';
import 'package:nai_casrand/ui/saved_config_list/widgets/saved_config_list_view.dart';
import 'package:nai_casrand/ui/studio_core/theme/studio_tokens.dart';
import 'package:nai_casrand/ui/studio_core/widgets/studio_panel.dart';
import 'package:provider/provider.dart';

class PromptTabView extends StatelessWidget {
  const PromptTabView({super.key, required this.viewmodel});

  final PromptTabViewmodel viewmodel;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: viewmodel,
      child: Consumer<PromptTabViewmodel>(
        builder: (context, viewmodel, child) {
          final isWideLayout = MediaQuery.of(context).size.width >= 900;
          final cardList = [
            PromptDashboardCard(
              icon: Icons.article_outlined,
              title: tr('prompt_dashboard_base_title'),
              subtitle: viewmodel.promptConfig.comment,
              selected:
                  viewmodel.activePanel == PromptDashboardPanel.basePrompt,
              onTap: () =>
                  viewmodel.setActivePanel(PromptDashboardPanel.basePrompt),
            ),
            PromptDashboardCard(
              icon: Icons.group_outlined,
              title: tr('prompt_dashboard_character_title'),
              subtitle: tr(
                'prompt_dashboard_character_subtitle',
                namedArgs: {
                  'num': viewmodel.characterConfigList.length.toString(),
                },
              ),
              selected:
                  viewmodel.activePanel == PromptDashboardPanel.characters,
              onTap: () =>
                  viewmodel.setActivePanel(PromptDashboardPanel.characters),
            ),
            PromptDashboardCard(
              icon: Icons.rule,
              title: tr('prompt_dashboard_replace_title'),
              subtitle: tr(
                'prompt_dashboard_replace_subtitle',
                namedArgs: {
                  'total': viewmodel.promptReplaceRules.length.toString(),
                  'enabled': viewmodel.enabledReplaceRuleCount.toString(),
                },
              ),
              selected:
                  viewmodel.activePanel == PromptDashboardPanel.replaceRules,
              onTap: () =>
                  viewmodel.setActivePanel(PromptDashboardPanel.replaceRules),
            ),
            PromptDashboardCard(
              icon: Icons.save_outlined,
              title: tr('prompt_dashboard_saved_title'),
              subtitle: tr(
                'prompt_dashboard_saved_subtitle',
                namedArgs: {
                  'num': viewmodel.savedConfigList.length.toString(),
                },
              ),
              selected:
                  viewmodel.activePanel == PromptDashboardPanel.savedConfigs,
              onTap: () =>
                  viewmodel.setActivePanel(PromptDashboardPanel.savedConfigs),
            ),
          ];

          return Scaffold(
            backgroundColor: StudioTokens.surface1,
            body: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1180),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          tr('prompt_dashboard_title'),
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          tr('prompt_dashboard_hint'),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      const SizedBox(height: 12),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: cardList.length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: isWideLayout ? 2 : 1,
                          mainAxisSpacing: 14,
                          crossAxisSpacing: 14,
                          childAspectRatio: isWideLayout ? 5.2 : 4.8,
                        ),
                        itemBuilder: (_, index) => cardList[index],
                      ),
                      const SizedBox(height: 16),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        child: StudioPanel(
                          key: ValueKey(viewmodel.activePanel),
                          color: StudioTokens.surface2,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: _buildPanel(context, viewmodel),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPanel(BuildContext context, PromptTabViewmodel viewmodel) {
    return switch (viewmodel.activePanel) {
      PromptDashboardPanel.basePrompt => _buildBasePromptPanel(viewmodel),
      PromptDashboardPanel.characters =>
        _buildCharacterPanel(context, viewmodel),
      PromptDashboardPanel.replaceRules =>
        PromptReplaceRulesEditor(viewmodel: viewmodel),
      PromptDashboardPanel.savedConfigs => _buildSavedConfigPanel(context),
    };
  }

  Widget _buildBasePromptPanel(PromptTabViewmodel viewmodel) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: PromptConfigView(
        viewModel: PromptConfigViewModel(
          config: viewmodel.promptConfig,
        ),
      ),
    );
  }

  Widget _buildCharacterPanel(
      BuildContext context, PromptTabViewmodel viewmodel) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          leading: const Icon(Icons.group),
          title: Text(tr('characters')),
          subtitle: Text(
            tr(
              'prompt_dashboard_character_subtitle',
              namedArgs: {
                'num': viewmodel.characterConfigList.length.toString(),
              },
            ),
          ),
          trailing: Wrap(
            spacing: 4,
            children: [
              IconButton(
                tooltip: tr('add_character'),
                onPressed: viewmodel.characterConfigList.length >=
                        PromptTabViewmodel.maxCharacterCount
                    ? null
                    : () => viewmodel.addCharacter(),
                icon: const Icon(Icons.person_add_alt),
              ),
              IconButton(
                tooltip: tr('rearrange_characters'),
                onPressed: () => _showCharacterRearrangeDialog(context),
                icon: const Icon(Icons.reorder),
              ),
            ],
          ),
        ),
        if (viewmodel.characterConfigList.isEmpty)
          ListTile(
            title: Text(tr('there_is_no_saved_config')),
          )
        else
          for (final (index, characterConfig)
              in viewmodel.characterConfigList.indexed)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text('Character #$index'),
                  ),
                  const Expanded(child: Divider()),
                ]),
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: CharacterConfigView(
                    viewmodel: CharacterConfigViewmodel(
                      config: characterConfig,
                    ),
                  ),
                )
              ],
            ),
      ],
    );
  }

  Widget _buildSavedConfigPanel(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr('saved_config_list_usage_tip'),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => SavedConfigListView(
                  viewmodel: SavedConfigListViewmodel(
                    configList: viewmodel.savedConfigList,
                  ),
                ),
              ),
            ),
            icon: const Icon(Icons.format_list_bulleted),
            label: Text(tr('manage_saved_configs')),
          ),
        ],
      ),
    );
  }

  void _showCharacterRearrangeDialog(BuildContext context) {
    final addCharacterTile = ChangeNotifierProvider.value(
      value: viewmodel,
      child: Consumer<PromptTabViewmodel>(
          builder: (context, viewmodel, child) => ListTile(
                title: Text(tr('add_character')),
                leading: const Icon(Icons.person_add),
                onTap: () => viewmodel.addCharacter(),
                enabled: viewmodel.characterConfigList.length <
                    PromptTabViewmodel.maxCharacterCount,
              )),
    );
    showDialog(
        context: context,
        builder: (context) => AlertDialog(
              title: Text('${tr('edit')}${tr('colon')}${tr('characters')}'),
              content: SizedBox(
                  width: 400.0,
                  height: 600.0,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Expanded(
                          child: CharacterRearrangeView(viewmodel: viewmodel)),
                      addCharacterTile,
                    ],
                  )),
              actions: [
                TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(tr('confirm')))
              ],
            ));
  }
}

class CharacterRearrangeView extends StatelessWidget {
  final PromptTabViewmodel viewmodel;

  const CharacterRearrangeView({super.key, required this.viewmodel});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
        value: viewmodel,
        child: Consumer<PromptTabViewmodel>(
          builder: (context, viewmodel, child) => ReorderableListView.builder(
            itemBuilder: (context, index) => ListTile(
              key: ValueKey(index),
              title: Text(
                  '#$index ${viewmodel.characterConfigList[index].positivePromptConfig.comment}'),
              leading: const Icon(Icons.person),
              trailing: Padding(
                  padding: const EdgeInsets.only(right: 16.0),
                  child: IconButton(
                    onPressed: () => viewmodel.removeCharacter(index),
                    icon: const Icon(Icons.delete),
                  )),
            ),
            itemCount: viewmodel.characterConfigList.length,
            onReorder: (oldIndex, newIndex) =>
                viewmodel.reorderCharacter(oldIndex, newIndex),
          ),
        ));
  }
}
