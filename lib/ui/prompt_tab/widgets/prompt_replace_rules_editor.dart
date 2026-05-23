import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:nai_casrand/ui/core/widgets/editable_list_tile.dart';
import 'package:nai_casrand/ui/prompt_tab/view_models/prompt_tab_viewmodel.dart';

class PromptReplaceRulesEditor extends StatefulWidget {
  final PromptTabViewmodel viewmodel;

  const PromptReplaceRulesEditor({
    super.key,
    required this.viewmodel,
  });

  @override
  State<PromptReplaceRulesEditor> createState() =>
      _PromptReplaceRulesEditorState();
}

class _PromptReplaceRulesEditorState extends State<PromptReplaceRulesEditor> {
  late final TextEditingController _batchInputController;

  @override
  void initState() {
    super.initState();
    _batchInputController = TextEditingController(
      text: widget.viewmodel.batchReplaceRuleInput,
    );
  }

  @override
  void didUpdateWidget(covariant PromptReplaceRulesEditor oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (_batchInputController.text == widget.viewmodel.batchReplaceRuleInput) {
      return;
    }

    _batchInputController.value = TextEditingValue(
      text: widget.viewmodel.batchReplaceRuleInput,
      selection: TextSelection.collapsed(
        offset: widget.viewmodel.batchReplaceRuleInput.length,
      ),
    );
  }

  @override
  void dispose() {
    _batchInputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewmodel = widget.viewmodel;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          leading: const Icon(Icons.rule),
          title: Text(tr('prompt_replace_rules_title')),
          subtitle: Text(
            tr(
              'prompt_replace_rules_stats',
              namedArgs: {
                'total': viewmodel.promptReplaceRules.length.toString(),
                'enabled': viewmodel.enabledReplaceRuleCount.toString(),
                'valid': viewmodel.validReplaceRuleCount.toString(),
                'skipped': viewmodel.skippedReplaceRuleCount.toString(),
              },
            ),
          ),
          trailing: FilledButton.icon(
            onPressed: () => viewmodel.addReplaceRule(),
            icon: const Icon(Icons.add),
            label: Text(tr('prompt_replace_add_rule')),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            tr('prompt_replace_rules_hint'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('prompt_replace_batch_input')),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('prompt_replace_batch_input_field'),
                controller: _batchInputController,
                minLines: 2,
                maxLines: 4,
                onChanged: viewmodel.updateBatchReplaceRuleInput,
                decoration: InputDecoration(
                  hintText: tr('prompt_replace_batch_placeholder'),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                tr('prompt_replace_batch_hint'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  key: const ValueKey('prompt_replace_batch_add_button'),
                  onPressed: viewmodel
                          .parseBatchReplaceRuleInput(
                            viewmodel.batchReplaceRuleInput,
                          )
                          .isEmpty
                      ? null
                      : viewmodel.addReplaceRulesFromBatchInput,
                  icon: const Icon(Icons.playlist_add),
                  label: Text(tr('prompt_replace_batch_add')),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (viewmodel.promptReplaceRules.isEmpty)
          ListTile(
            title: Text(tr('prompt_replace_rules_empty')),
          )
        else
          ReorderableListView.builder(
            buildDefaultDragHandles: false,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: viewmodel.promptReplaceRules.length,
            onReorder: (oldIndex, newIndex) =>
                viewmodel.reorderReplaceRule(oldIndex, newIndex),
            itemBuilder: (context, index) {
              final rule = viewmodel.promptReplaceRules[index];
              return Card(
                key: ValueKey(rule.id),
                margin:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 8, right: 8, top: 4),
                      child: Row(
                        children: [
                          ReorderableDragStartListener(
                            index: index,
                            child: const Padding(
                              padding: EdgeInsets.all(8.0),
                              child: Icon(Icons.drag_indicator),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              tr(
                                'prompt_replace_rule_label',
                                namedArgs: {
                                  'num': (index + 1).toString(),
                                },
                              ),
                            ),
                          ),
                          Switch(
                            value: rule.enabled,
                            onChanged: (value) =>
                                viewmodel.toggleReplaceRule(index, value),
                          ),
                        ],
                      ),
                    ),
                    EditableListTile(
                      leading: const Icon(Icons.input),
                      title: tr('prompt_replace_source'),
                      currentValue: rule.source.isEmpty
                          ? tr('prompt_replace_source_placeholder')
                          : rule.source,
                      editValue: rule.source,
                      maxLines: 1,
                      confirmOnSubmit: true,
                      onEditComplete: (value) =>
                          viewmodel.updateReplaceRuleSource(index, value),
                    ),
                    EditableListTile(
                      leading: const Icon(Icons.output),
                      title: tr('prompt_replace_target'),
                      currentValue: rule.target.isEmpty
                          ? tr('prompt_replace_target_placeholder')
                          : rule.target,
                      editValue: rule.target,
                      maxLines: 1,
                      confirmOnSubmit: true,
                      onEditComplete: (value) =>
                          viewmodel.updateReplaceRuleTarget(index, value),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 8, bottom: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton.icon(
                            onPressed: () => viewmodel.duplicateReplaceRule(index),
                            icon: const Icon(Icons.copy),
                            label: Text(tr('prompt_replace_duplicate')),
                          ),
                          TextButton.icon(
                            onPressed: () => viewmodel.removeReplaceRule(index),
                            icon: const Icon(Icons.delete_outline),
                            label: Text(tr('prompt_replace_delete')),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }
}
