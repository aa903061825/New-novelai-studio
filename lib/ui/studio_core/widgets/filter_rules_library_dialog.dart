import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:nai_casrand/data/studio/services/studio_asset_catalog_service.dart';
import 'package:nai_casrand/data/studio/tools/filter_rule_config.dart';
import 'package:nai_casrand/data/studio/tools/prompt_tag_classifier.dart';
import 'package:nai_casrand/data/studio/tools/prompt_tag_processor.dart';
import 'package:nai_casrand/data/studio/tools/translation_cache.dart';
import 'package:nai_casrand/data/workspace/models/workspace_entities.dart';
import 'package:nai_casrand/data/workspace/workspace_paths.dart';
import 'package:nai_casrand/ui/studio_core/services/filter_rule_document.dart';
import 'package:nai_casrand/ui/studio_core/theme/studio_tokens.dart';

typedef FilterRulesConfigLoader = Future<FilterRuleConfig> Function();
typedef FilterRulesConfigSaver = Future<void> Function(
  FilterRuleConfig config,
);
typedef FilterRulesAvailableTagsLoader = Future<List<TagEntry>> Function();

const _filterRuleBlocks = WorkspacePaths.blocks;

Future<void> showFilterRulesLibraryDialog(
  BuildContext context, {
  required FilterRulesConfigLoader loadConfig,
  required FilterRulesConfigSaver saveConfig,
  FilterRulesAvailableTagsLoader? loadAvailableTags,
}) async {
  final config = await loadConfig();
  if (!context.mounted) {
    return;
  }
  await showDialog<void>(
    context: context,
    builder: (_) => FilterRulesLibraryDialog(
      initialConfig: config,
      onSave: saveConfig,
      loadAvailableTags: loadAvailableTags,
    ),
  );
}

class FilterRulesLibraryDialog extends StatefulWidget {
  final FilterRuleConfig initialConfig;
  final FilterRulesConfigSaver onSave;
  final FilterRulesAvailableTagsLoader? loadAvailableTags;

  const FilterRulesLibraryDialog({
    super.key,
    required this.initialConfig,
    required this.onSave,
    this.loadAvailableTags,
  });

  @override
  State<FilterRulesLibraryDialog> createState() =>
      _FilterRulesLibraryDialogState();
}

class _FilterRulesLibraryDialogState extends State<FilterRulesLibraryDialog> {
  late Map<String, List<String>> _deleteKeywordsByBlock;
  late Map<String, List<String>> _strongFilterKeywordsByBlock;
  late Map<String, List<_EditableReplaceRule>> _replaceRulesByBlock;
  var _deleteLayoutMode = _FilterRuleLayoutMode.sourceOrder;
  var _strongLayoutMode = _FilterRuleLayoutMode.sourceOrder;
  var _replaceLayoutMode = _FilterRuleLayoutMode.sourceOrder;
  var _tagsLoading = false;
  var _rulesTouched = false;
  List<TagEntry> _availableTags = const [];
  Map<String, String> _knownTagBlockByKey = const {};
  TranslationCache? _tagTranslationCache;
  PromptTagClassificationCache? _tagClassificationCache;

  @override
  void initState() {
    super.initState();
    final config = widget.initialConfig;
    _deleteKeywordsByBlock = _groupTagsByBlock(
      _ruleWords(config.deleteKeywords),
    );
    _strongFilterKeywordsByBlock = _groupTagsByBlock(
      _ruleWords(config.strongFilterKeywords),
    );
    _replaceRulesByBlock = _groupReplaceRulesByBlock([
      for (final rule in PromptTagProcessor.parseReplaceRulesText(
        config.replaceRules,
      ))
        _EditableReplaceRule(source: rule.oldValue, target: rule.newValue),
    ]);
    unawaited(_loadAvailableTags());
  }

  @override
  Widget build(BuildContext context) {
    String label(String key, String fallback) =>
        _filterRulesLibraryText(context, key, fallback);

    return AlertDialog(
      backgroundColor: StudioTokens.surface2,
      title: Row(
        children: [
          Expanded(
            child: Text(
              label('filter_rules_library_title', 'Filter Rules Library'),
            ),
          ),
          if (_tagsLoading)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
      content: SizedBox(
        width: 760,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _FilterRuleTokenSection(
                sectionId: 'delete',
                title: label('filter_rules_delete_keywords', 'Delete keywords'),
                blocks: _filterRuleBlocks,
                tagsByBlock: _deleteKeywordsByBlock,
                emptyText: label(
                  'filter_rules_empty_block',
                  'No rules in this block',
                ),
                addLabel: label('filter_rules_add_tag', '添加标签'),
                batchAddLabel: label(
                  'filter_rules_batch_add_tags',
                  'Batch add tags',
                ),
                layoutMode: _deleteLayoutMode,
                translationCache: _tagTranslationCache,
                classificationCache: _tagClassificationCache,
                onLayoutChanged: (value) => setState(() {
                  _deleteLayoutMode = value;
                }),
                onAdd: _addDeleteTagAuto,
                onBatchAdd: _batchAddDeleteTagsAuto,
                onBlockAdd: _addDeleteTag,
                onBlockBatchAdd: _batchAddDeleteTags,
                onEdit: (block, index) => _editListTag(
                  _deleteKeywordsByBlock,
                  block,
                  index,
                ),
                onRemove: (block, index) => _removeListTag(
                  _deleteKeywordsByBlock,
                  block,
                  index,
                ),
                onReorder: (fromBlock, fromIndex, toBlock, toIndex) =>
                    _reorderListTag(
                  _deleteKeywordsByBlock,
                  fromBlock,
                  fromIndex,
                  toBlock,
                  toIndex,
                ),
              ),
              const SizedBox(height: 12),
              _FilterRuleTokenSection(
                sectionId: 'strong',
                title: label(
                  'filter_rules_strong_keywords',
                  'Strong filter keywords',
                ),
                blocks: _filterRuleBlocks,
                tagsByBlock: _strongFilterKeywordsByBlock,
                emptyText: label(
                  'filter_rules_empty_block',
                  'No rules in this block',
                ),
                addLabel: label('filter_rules_add_tag', '添加标签'),
                batchAddLabel: label(
                  'filter_rules_batch_add_tags',
                  'Batch add tags',
                ),
                layoutMode: _strongLayoutMode,
                translationCache: _tagTranslationCache,
                classificationCache: _tagClassificationCache,
                onLayoutChanged: (value) => setState(() {
                  _strongLayoutMode = value;
                }),
                onAdd: _addStrongTagAuto,
                onBatchAdd: _batchAddStrongTagsAuto,
                onBlockAdd: _addStrongTag,
                onBlockBatchAdd: _batchAddStrongTags,
                onEdit: (block, index) => _editListTag(
                  _strongFilterKeywordsByBlock,
                  block,
                  index,
                ),
                onRemove: (block, index) => _removeListTag(
                  _strongFilterKeywordsByBlock,
                  block,
                  index,
                ),
                onReorder: (fromBlock, fromIndex, toBlock, toIndex) =>
                    _reorderListTag(
                  _strongFilterKeywordsByBlock,
                  fromBlock,
                  fromIndex,
                  toBlock,
                  toIndex,
                ),
              ),
              const SizedBox(height: 12),
              _FilterReplaceRuleSection(
                blocks: _filterRuleBlocks,
                rulesByBlock: _replaceRulesByBlock,
                title: label('filter_rules_replace_rules', 'Replace rules'),
                emptyText: label(
                  'filter_rules_empty_block',
                  'No rules in this block',
                ),
                addLabel: label(
                  'filter_rules_add_replace_rule',
                  'Add replacement',
                ),
                sourceLabel: label(
                  'filter_rules_replace_source',
                  'Source',
                ),
                targetLabel: label(
                  'filter_rules_replace_target',
                  'Target',
                ),
                layoutMode: _replaceLayoutMode,
                onLayoutChanged: (value) => setState(() {
                  _replaceLayoutMode = value;
                }),
                onAdd: _addReplaceRuleAuto,
                onBlockAdd: _addReplaceRule,
                onEditSource: _editReplaceSource,
                onEditTarget: _editReplaceTarget,
                onRemove: _removeReplaceRule,
                onReorder: _reorderReplaceRule,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          style: _filterRuleDialogTextButtonStyle(),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(label('cancel', 'Cancel')),
        ),
        FilledButton(
          key: const ValueKey('filter-rules-save'),
          style: _filterRuleDialogPrimaryButtonStyle(),
          onPressed: _save,
          child: Text(label('save', 'Save')),
        ),
      ],
    );
  }

  Future<void> _save() async {
    await widget.onSave(
      FilterRuleConfig(
        deleteKeywords: _flattenTagBlocks(_deleteKeywordsByBlock).join(', '),
        strongFilterKeywords:
            _flattenTagBlocks(_strongFilterKeywordsByBlock).join(', '),
        replaceRules: _flattenReplaceBlocks(_replaceRulesByBlock)
            .where((rule) => rule.source.trim().isNotEmpty)
            .map((rule) => '${rule.source.trim()} -> ${rule.target.trim()}')
            .join('\n'),
        removeWeights: widget.initialConfig.removeWeights,
        exactMatch: widget.initialConfig.exactMatch,
        deleteArtistTags: widget.initialConfig.deleteArtistTags,
      ),
    );
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _loadAvailableTags() async {
    setState(() {
      _tagsLoading = true;
    });
    try {
      final loader = widget.loadAvailableTags ?? _loadAvailableTagsFromCatalog;
      final tags = await loader();
      if (!mounted) {
        return;
      }
      setState(() {
        _availableTags = _dedupeTags(tags);
        _tagsLoading = false;
        _rebuildTagSystemCaches();
        if (!_rulesTouched) {
          _regroupRulesByKnownBlocks();
        }
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _availableTags = const [];
        _tagsLoading = false;
        _rebuildTagSystemCaches();
      });
    }
  }

  void _rebuildTagSystemCaches() {
    final translation = _copyTranslationCache();
    final classification = _copyClassificationCache();
    final knownBlocks = buildKnownFilterRuleBlocks(_availableTags);
    for (final tag in _availableTags) {
      final text = tag.tag.trim();
      if (text.isEmpty) {
        continue;
      }
      final zh = tag.zh.trim();
      if (zh.isNotEmpty) {
        translation.setCached(text, zh, source: 'asset-library');
        for (final alias in tag.aliases) {
          translation.setCached(alias, zh, source: 'asset-library');
        }
      }
      final category = filterRuleCategoryFromTagEntry(tag);
      if (category != null) {
        classification.setCategory(text, category, source: 'asset-library');
        for (final alias in tag.aliases) {
          classification.setCategory(
            alias,
            category,
            source: 'asset-library',
          );
        }
      }
    }
    _tagTranslationCache = translation;
    _tagClassificationCache = classification;
    _knownTagBlockByKey = knownBlocks;
  }

  TranslationCache _copyTranslationCache() {
    try {
      if (GetIt.I.isRegistered<TranslationCache>()) {
        return TranslationCache(entries: GetIt.I<TranslationCache>().entries);
      }
    } catch (_) {
      // Tests and storybook-style hosts may not initialize GetIt.
    }
    return TranslationCache();
  }

  PromptTagClassificationCache _copyClassificationCache() {
    try {
      if (GetIt.I.isRegistered<PromptTagClassificationCache>()) {
        return PromptTagClassificationCache(
          entries: GetIt.I<PromptTagClassificationCache>().entries,
        );
      }
    } catch (_) {
      // Tests and storybook-style hosts may not initialize GetIt.
    }
    return PromptTagClassificationCache();
  }

  void _regroupRulesByKnownBlocks() {
    _deleteKeywordsByBlock = _groupTagsByBlock(
      _flattenTagBlocks(_deleteKeywordsByBlock),
    );
    _strongFilterKeywordsByBlock = _groupTagsByBlock(
      _flattenTagBlocks(_strongFilterKeywordsByBlock),
    );
    _replaceRulesByBlock = _groupReplaceRulesByBlock(
      _flattenReplaceBlocks(_replaceRulesByBlock),
    );
  }

  Future<void> _addDeleteTag(String block) async {
    await _addTagToBlock(_deleteKeywordsByBlock, block);
  }

  Future<void> _addStrongTag(String block) async {
    await _addTagToBlock(_strongFilterKeywordsByBlock, block);
  }

  Future<void> _addDeleteTagAuto() async {
    await _addTagToAutoBlock(_deleteKeywordsByBlock);
  }

  Future<void> _addStrongTagAuto() async {
    await _addTagToAutoBlock(_strongFilterKeywordsByBlock);
  }

  Future<void> _batchAddDeleteTags(String block) async {
    await _batchAddTagsToBlock(_deleteKeywordsByBlock, block);
  }

  Future<void> _batchAddStrongTags(String block) async {
    await _batchAddTagsToBlock(_strongFilterKeywordsByBlock, block);
  }

  Future<void> _batchAddDeleteTagsAuto() async {
    await _batchAddTagsToAutoBlocks(_deleteKeywordsByBlock);
  }

  Future<void> _batchAddStrongTagsAuto() async {
    await _batchAddTagsToAutoBlocks(_strongFilterKeywordsByBlock);
  }

  Future<void> _addTagToBlock(
    Map<String, List<String>> tagsByBlock,
    String block,
  ) async {
    final value = await _editTagValue(
      '',
      title: '添加${_blockDisplayName(block)}标签',
    );
    if (value == null) {
      return;
    }
    setState(() {
      _rulesTouched = true;
      _replaceTagBlocks(
        tagsByBlock,
        FilterRuleDocument.fromBlocks(
          tagsByBlock,
          resolveBlock: _blockForTagText,
        ).addToBlock(block, [value]),
      );
    });
  }

  Future<void> _addTagToAutoBlock(
    Map<String, List<String>> tagsByBlock,
  ) async {
    final value = await _editTagValue(
      '',
      title: '添加标签',
    );
    if (value == null) {
      return;
    }
    setState(() {
      _rulesTouched = true;
      _replaceTagBlocks(
        tagsByBlock,
        FilterRuleDocument.fromBlocks(
          tagsByBlock,
          resolveBlock: _blockForTagText,
        ).addAuto([value]),
      );
    });
  }

  Future<void> _batchAddTagsToBlock(
    Map<String, List<String>> tagsByBlock,
    String block,
  ) async {
    final values = await _editBatchTagValues(
      title: '批量添加${_blockDisplayName(block)}标签',
    );
    if (values.isEmpty) {
      return;
    }
    setState(() {
      _rulesTouched = true;
      _replaceTagBlocks(
        tagsByBlock,
        FilterRuleDocument.fromBlocks(
          tagsByBlock,
          resolveBlock: _blockForTagText,
        ).addToBlock(block, values),
      );
    });
  }

  Future<void> _batchAddTagsToAutoBlocks(
    Map<String, List<String>> tagsByBlock,
  ) async {
    final values = await _editBatchTagValues(title: '批量添加标签');
    if (values.isEmpty) {
      return;
    }
    setState(() {
      _rulesTouched = true;
      _replaceTagBlocks(
        tagsByBlock,
        FilterRuleDocument.fromBlocks(
          tagsByBlock,
          resolveBlock: _blockForTagText,
        ).addAuto(values),
      );
    });
  }

  Future<void> _editListTag(
    Map<String, List<String>> tagsByBlock,
    String block,
    int index,
  ) async {
    final list = _listFor(tagsByBlock, block);
    final updated = await _editTagValue(list[index]);
    if (updated == null) {
      return;
    }
    setState(() {
      _rulesTouched = true;
      list[index] = updated;
    });
  }

  void _removeListTag(
    Map<String, List<String>> tagsByBlock,
    String block,
    int index,
  ) {
    setState(() {
      _rulesTouched = true;
      _listFor(tagsByBlock, block).removeAt(index);
    });
  }

  void _reorderListTag(
    Map<String, List<String>> tagsByBlock,
    String fromBlock,
    int fromIndex,
    String toBlock,
    int toIndex,
  ) {
    setState(() {
      _rulesTouched = true;
      final fromList = _listFor(tagsByBlock, fromBlock);
      if (fromIndex < 0 || fromIndex >= fromList.length) {
        return;
      }
      final item = fromList.removeAt(fromIndex);
      final targetList = _listFor(tagsByBlock, toBlock);
      var insertIndex = toIndex.clamp(0, targetList.length);
      if (fromBlock == toBlock && fromIndex < insertIndex) {
        insertIndex -= 1;
      }
      targetList.insert(insertIndex, item);
    });
  }

  Future<void> _addReplaceRule(String block) async {
    final rule = await _editReplaceRuleValue(
      title: '添加${_blockDisplayName(block)}替换规则',
    );
    if (rule == null) {
      return;
    }
    setState(() {
      _rulesTouched = true;
      _listFor(_replaceRulesByBlock, block).add(rule);
    });
  }

  Future<void> _addReplaceRuleAuto() async {
    final rule = await _editReplaceRuleValue(title: '添加替换规则');
    if (rule == null) {
      return;
    }
    setState(() {
      _rulesTouched = true;
      _listFor(_replaceRulesByBlock, _blockForTagText(rule.source)).add(rule);
    });
  }

  Future<void> _editReplaceSource(String block, int index) async {
    final rules = _listFor(_replaceRulesByBlock, block);
    final updated = await _editTagValue(rules[index].source);
    if (updated == null) {
      return;
    }
    setState(() {
      _rulesTouched = true;
      rules[index] = rules[index].copyWith(source: updated);
    });
  }

  Future<void> _editReplaceTarget(String block, int index) async {
    final rules = _listFor(_replaceRulesByBlock, block);
    final updated = await _editTagValue(rules[index].target);
    if (updated == null) {
      return;
    }
    setState(() {
      _rulesTouched = true;
      rules[index] = rules[index].copyWith(target: updated);
    });
  }

  void _removeReplaceRule(String block, int index) {
    setState(() {
      _rulesTouched = true;
      _listFor(_replaceRulesByBlock, block).removeAt(index);
    });
  }

  void _reorderReplaceRule(
    String fromBlock,
    int fromIndex,
    String toBlock,
    int toIndex,
  ) {
    setState(() {
      _rulesTouched = true;
      final fromList = _listFor(_replaceRulesByBlock, fromBlock);
      if (fromIndex < 0 || fromIndex >= fromList.length) {
        return;
      }
      final item = fromList.removeAt(fromIndex);
      final targetList = _listFor(_replaceRulesByBlock, toBlock);
      var insertIndex = toIndex.clamp(0, targetList.length);
      if (fromBlock == toBlock && fromIndex < insertIndex) {
        insertIndex -= 1;
      }
      targetList.insert(insertIndex, item);
    });
  }

  Future<String?> _editTagValue(
    String initialValue, {
    String title = '编辑标签',
  }) async {
    var editedValue = initialValue;
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: StudioTokens.surface2,
        title: Text(title),
        content: TextFormField(
          key: const ValueKey('filter-rule-tag-edit-field'),
          initialValue: initialValue,
          autofocus: true,
          onChanged: (value) {
            editedValue = value;
          },
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            style: _filterRuleDialogTextButtonStyle(),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const ValueKey('filter-rule-tag-edit-save'),
            style: _filterRuleDialogPrimaryButtonStyle(),
            onPressed: () => Navigator.of(context).pop(editedValue),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    final trimmed = result?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

  Future<List<String>> _editBatchTagValues({
    required String title,
  }) async {
    var editedValue = '';
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: StudioTokens.surface2,
        title: Text(title),
        content: SizedBox(
          width: 460,
          child: TextFormField(
            key: const ValueKey('filter-rule-batch-tag-edit-field'),
            autofocus: true,
            minLines: 5,
            maxLines: 10,
            onChanged: (value) {
              editedValue = value;
            },
            decoration: const InputDecoration(
              hintText: '每行一个标签，也可以用逗号分隔',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            style: _filterRuleDialogTextButtonStyle(),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const ValueKey('filter-rule-batch-tag-edit-save'),
            style: _filterRuleDialogPrimaryButtonStyle(),
            onPressed: () => Navigator.of(context).pop(editedValue),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    final trimmed = result?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return const [];
    }
    return _ruleWords(trimmed);
  }

  Future<_EditableReplaceRule?> _editReplaceRuleValue({
    required String title,
    _EditableReplaceRule initialValue =
        const _EditableReplaceRule(source: '', target: ''),
  }) async {
    var source = initialValue.source;
    var target = initialValue.target;
    final result = await showDialog<_EditableReplaceRule>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: StudioTokens.surface2,
        title: Text(title),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                key: const ValueKey('filter-rule-replace-source-edit-field'),
                initialValue: source,
                autofocus: true,
                onChanged: (value) {
                  source = value;
                },
                decoration: const InputDecoration(
                  labelText: '源标签',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                key: const ValueKey('filter-rule-replace-target-edit-field'),
                initialValue: target,
                onChanged: (value) {
                  target = value;
                },
                decoration: const InputDecoration(
                  labelText: '替换为',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            style: _filterRuleDialogTextButtonStyle(),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const ValueKey('filter-rule-replace-edit-save'),
            style: _filterRuleDialogPrimaryButtonStyle(),
            onPressed: () => Navigator.of(context).pop(
              _EditableReplaceRule(source: source, target: target),
            ),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    final sourceText = result?.source.trim();
    if (sourceText == null || sourceText.isEmpty) {
      return null;
    }
    return _EditableReplaceRule(
      source: sourceText,
      target: result?.target.trim() ?? '',
    );
  }

  Map<String, List<String>> _groupTagsByBlock(Iterable<String> tags) {
    return FilterRuleDocument.fromWords(
      tags,
      resolveBlock: _blockForTagText,
    ).tagsByBlock;
  }

  Map<String, List<_EditableReplaceRule>> _groupReplaceRulesByBlock(
    Iterable<_EditableReplaceRule> rules,
  ) {
    final result = _emptyBlockMap<_EditableReplaceRule>();
    for (final rule in rules) {
      final source = rule.source.trim();
      if (source.isEmpty) {
        continue;
      }
      _listFor(result, _blockForTagText(source)).add(
        _EditableReplaceRule(source: source, target: rule.target.trim()),
      );
    }
    return result;
  }

  String _blockForTagText(String text) {
    final key = PromptTagProcessor.normalizeMatchKey(text);
    final knownBlock = _knownTagBlockByKey[key];
    if (knownBlock != null) {
      return knownBlock;
    }
    final classification = PromptTagClassifier.classify(
      text,
      cache: _tagClassificationCache,
    );
    return filterRuleBlockFromCategory(classification.category);
  }
}

class _EditableReplaceRule {
  final String source;
  final String target;

  const _EditableReplaceRule({
    required this.source,
    required this.target,
  });

  _EditableReplaceRule copyWith({String? source, String? target}) {
    return _EditableReplaceRule(
      source: source ?? this.source,
      target: target ?? this.target,
    );
  }
}

enum _FilterRuleLayoutMode { sourceOrder, grouped }

class _TokenRuleRef {
  final String block;
  final int blockIndex;
  final String text;

  const _TokenRuleRef({
    required this.block,
    required this.blockIndex,
    required this.text,
  });
}

class _ReplaceRuleRef {
  final String block;
  final int blockIndex;
  final _EditableReplaceRule rule;

  const _ReplaceRuleRef({
    required this.block,
    required this.blockIndex,
    required this.rule,
  });
}

class _RuleTokenDragData {
  final String sectionId;
  final String block;
  final int index;

  const _RuleTokenDragData({
    required this.sectionId,
    required this.block,
    required this.index,
  });
}

class _ReplaceRuleDragData {
  final String block;
  final int index;

  const _ReplaceRuleDragData({
    required this.block,
    required this.index,
  });
}

class _FilterRuleTokenSection extends StatelessWidget {
  final String sectionId;
  final String title;
  final List<String> blocks;
  final Map<String, List<String>> tagsByBlock;
  final String emptyText;
  final String addLabel;
  final String batchAddLabel;
  final _FilterRuleLayoutMode layoutMode;
  final TranslationCache? translationCache;
  final PromptTagClassificationCache? classificationCache;
  final VoidCallback onAdd;
  final VoidCallback onBatchAdd;
  final ValueChanged<_FilterRuleLayoutMode> onLayoutChanged;
  final ValueChanged<String> onBlockAdd;
  final ValueChanged<String> onBlockBatchAdd;
  final void Function(String block, int index) onEdit;
  final void Function(String block, int index) onRemove;
  final void Function(
    String fromBlock,
    int fromIndex,
    String toBlock,
    int toIndex,
  ) onReorder;

  const _FilterRuleTokenSection({
    required this.sectionId,
    required this.title,
    required this.blocks,
    required this.tagsByBlock,
    required this.emptyText,
    required this.addLabel,
    required this.batchAddLabel,
    required this.layoutMode,
    required this.translationCache,
    required this.classificationCache,
    required this.onAdd,
    required this.onBatchAdd,
    required this.onLayoutChanged,
    required this.onBlockAdd,
    required this.onBlockBatchAdd,
    required this.onEdit,
    required this.onRemove,
    required this.onReorder,
  });

  @override
  Widget build(BuildContext context) {
    final refs = [
      for (final block in _sourceOrderBlocks(tagsByBlock))
        for (final (index, text)
            in (tagsByBlock[block] ?? const <String>[]).indexed)
          _TokenRuleRef(block: block, blockIndex: index, text: text),
    ];
    final visibleBlocks = [
      for (final block in blocks)
        if ((tagsByBlock[block] ?? const <String>[]).isNotEmpty) block,
    ];
    return _FilterRuleSectionShell(
      sectionId: sectionId,
      title: title,
      actions: [
        _SectionIconButton(
          key: ValueKey('filter-rule-section-batch-add-$sectionId'),
          icon: Icons.playlist_add,
          tooltip: batchAddLabel,
          onPressed: onBatchAdd,
        ),
        _SectionIconButton(
          key: ValueKey('filter-rule-section-add-$sectionId'),
          icon: Icons.add,
          tooltip: addLabel,
          onPressed: onAdd,
        ),
        _FilterRuleLayoutButton(
          key: ValueKey('filter-rule-layout-toggle-$sectionId'),
          grouped: layoutMode == _FilterRuleLayoutMode.grouped,
          onPressed: () => onLayoutChanged(
            layoutMode == _FilterRuleLayoutMode.grouped
                ? _FilterRuleLayoutMode.sourceOrder
                : _FilterRuleLayoutMode.grouped,
          ),
        ),
      ],
      child: layoutMode == _FilterRuleLayoutMode.grouped
          ? (visibleBlocks.isEmpty
              ? _FilterRuleEmptyText(text: emptyText)
              : Column(
                  children: [
                    for (final (blockIndex, block) in visibleBlocks.indexed)
                      Padding(
                        padding: EdgeInsets.only(
                          bottom:
                              blockIndex == visibleBlocks.length - 1 ? 0 : 10,
                        ),
                        child: SizedBox(
                          width: double.infinity,
                          child: _FilterRuleBlockCard(
                            key:
                                ValueKey('filter-rule-block-$sectionId-$block'),
                            block: block,
                            sectionId: sectionId,
                            addLabel: addLabel,
                            batchAddLabel: batchAddLabel,
                            onAdd: () => onBlockAdd(block),
                            onBatchAdd: () => onBlockBatchAdd(block),
                            child: _TokenBlockBody(
                              sectionId: sectionId,
                              block: block,
                              tags: tagsByBlock[block] ?? const [],
                              emptyText: emptyText,
                              translationCache: translationCache,
                              classificationCache: classificationCache,
                              onEdit: (index) => onEdit(block, index),
                              onRemove: (index) => onRemove(block, index),
                              onReorder: (from, targetIndex) => onReorder(
                                from.block,
                                from.index,
                                block,
                                targetIndex,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ))
          : (refs.isEmpty
              ? _FilterRuleEmptyText(text: emptyText)
              : Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final (index, ref) in refs.indexed)
                      _EditableRuleToken(
                        sectionId: '$sectionId-all',
                        block: ref.block,
                        index: index,
                        text: ref.text,
                        translationCache: translationCache,
                        classificationCache: classificationCache,
                        onEdit: () => onEdit(ref.block, ref.blockIndex),
                        onRemove: () => onRemove(ref.block, ref.blockIndex),
                        onReorder: (from) => onReorder(
                          from.block,
                          from.index,
                          ref.block,
                          ref.blockIndex,
                        ),
                      ),
                  ],
                )),
    );
  }
}

class _FilterRuleEmptyText extends StatelessWidget {
  final String text;

  const _FilterRuleEmptyText({required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: StudioTokens.textMuted,
          ),
    );
  }
}

class _FilterRuleHoverSurface extends StatefulWidget {
  final Key? surfaceKey;
  final BorderRadius borderRadius;
  final BoxConstraints? constraints;
  final EdgeInsetsGeometry? padding;
  final Color idleColor;
  final Color hoverColor;
  final Color pressedColor;
  final Color idleBorderColor;
  final Color hoverBorderColor;
  final VoidCallback? onTap;
  final Widget child;

  const _FilterRuleHoverSurface({
    this.surfaceKey,
    required this.borderRadius,
    this.constraints,
    this.padding,
    required this.idleColor,
    required this.hoverColor,
    required this.pressedColor,
    required this.idleBorderColor,
    required this.hoverBorderColor,
    this.onTap,
    required this.child,
  });

  @override
  State<_FilterRuleHoverSurface> createState() =>
      _FilterRuleHoverSurfaceState();
}

class _FilterRuleHoverSurfaceState extends State<_FilterRuleHoverSurface> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final surface = AnimatedContainer(
      key: widget.surfaceKey,
      duration: const Duration(milliseconds: 120),
      constraints: widget.constraints,
      padding: widget.padding,
      decoration: BoxDecoration(
        color: _pressed
            ? widget.pressedColor
            : _hovered
                ? widget.hoverColor
                : widget.idleColor,
        borderRadius: widget.borderRadius,
        border: Border.all(
          color: _hovered ? widget.hoverBorderColor : widget.idleBorderColor,
        ),
      ),
      child: widget.child,
    );
    final onTap = widget.onTap;
    if (onTap == null) {
      return MouseRegion(
        onEnter: (_) => setState(() {
          _hovered = true;
        }),
        onExit: (_) => setState(() {
          _hovered = false;
          _pressed = false;
        }),
        child: surface,
      );
    }
    return InkWell(
      borderRadius: widget.borderRadius,
      mouseCursor: SystemMouseCursors.click,
      onHover: (hovered) => setState(() {
        _hovered = hovered;
      }),
      onHighlightChanged: (pressed) => setState(() {
        _pressed = pressed;
      }),
      onTap: onTap,
      child: surface,
    );
  }
}

class _SectionIconButton extends StatelessWidget {
  final IconData icon;
  final String? tooltip;
  final VoidCallback onPressed;

  const _SectionIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      visualDensity: VisualDensity.compact,
      tooltip: tooltip,
      style: _filterRuleIconButtonStyle(),
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
    );
  }
}

class _FilterRuleLayoutButton extends StatelessWidget {
  final bool grouped;
  final VoidCallback onPressed;

  const _FilterRuleLayoutButton({
    super.key,
    required this.grouped,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.hovered)) {
            return StudioTokens.surface4;
          }
          return Colors.transparent;
        }),
        foregroundColor: WidgetStatePropertyAll(
          grouped ? StudioTokens.primary : StudioTokens.textSecondary,
        ),
        overlayColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.pressed)) {
            return StudioTokens.primary.withAlpha(42);
          }
          if (states.contains(WidgetState.hovered)) {
            return StudioTokens.primary.withAlpha(24);
          }
          return null;
        }),
        side: WidgetStatePropertyAll(
          BorderSide(
            color: grouped ? StudioTokens.primary : StudioTokens.border,
          ),
        ),
      ),
      onPressed: onPressed,
      icon: Icon(
        grouped ? Icons.view_agenda_outlined : Icons.dashboard_outlined,
        size: 16,
      ),
      label: Text(grouped ? '原序' : '分块'),
    );
  }
}

class _FilterReplaceRuleSection extends StatelessWidget {
  final List<String> blocks;
  final Map<String, List<_EditableReplaceRule>> rulesByBlock;
  final String title;
  final String emptyText;
  final String addLabel;
  final String sourceLabel;
  final String targetLabel;
  final _FilterRuleLayoutMode layoutMode;
  final VoidCallback onAdd;
  final ValueChanged<_FilterRuleLayoutMode> onLayoutChanged;
  final ValueChanged<String> onBlockAdd;
  final void Function(String block, int index) onEditSource;
  final void Function(String block, int index) onEditTarget;
  final void Function(String block, int index) onRemove;
  final void Function(
    String fromBlock,
    int fromIndex,
    String toBlock,
    int toIndex,
  ) onReorder;

  const _FilterReplaceRuleSection({
    required this.blocks,
    required this.rulesByBlock,
    required this.title,
    required this.emptyText,
    required this.addLabel,
    required this.sourceLabel,
    required this.targetLabel,
    required this.layoutMode,
    required this.onAdd,
    required this.onLayoutChanged,
    required this.onBlockAdd,
    required this.onEditSource,
    required this.onEditTarget,
    required this.onRemove,
    required this.onReorder,
  });

  @override
  Widget build(BuildContext context) {
    final refs = [
      for (final block in _sourceOrderBlocks(rulesByBlock))
        for (final (index, rule)
            in (rulesByBlock[block] ?? const <_EditableReplaceRule>[]).indexed)
          _ReplaceRuleRef(block: block, blockIndex: index, rule: rule),
    ];
    final visibleBlocks = [
      for (final block in blocks)
        if ((rulesByBlock[block] ?? const <_EditableReplaceRule>[]).isNotEmpty)
          block,
    ];
    return _FilterRuleSectionShell(
      sectionId: 'replace',
      title: title,
      actions: [
        _SectionIconButton(
          key: const ValueKey('filter-rule-section-add-replace'),
          icon: Icons.add,
          tooltip: addLabel,
          onPressed: onAdd,
        ),
        _FilterRuleLayoutButton(
          key: const ValueKey('filter-rule-layout-toggle-replace'),
          grouped: layoutMode == _FilterRuleLayoutMode.grouped,
          onPressed: () => onLayoutChanged(
            layoutMode == _FilterRuleLayoutMode.grouped
                ? _FilterRuleLayoutMode.sourceOrder
                : _FilterRuleLayoutMode.grouped,
          ),
        ),
      ],
      child: layoutMode == _FilterRuleLayoutMode.grouped
          ? (visibleBlocks.isEmpty
              ? _FilterRuleEmptyText(text: emptyText)
              : Column(
                  children: [
                    for (final (blockIndex, block) in visibleBlocks.indexed)
                      Padding(
                        padding: EdgeInsets.only(
                          bottom:
                              blockIndex == visibleBlocks.length - 1 ? 0 : 10,
                        ),
                        child: SizedBox(
                          width: double.infinity,
                          child: _FilterRuleBlockCard(
                            key: ValueKey('filter-rule-block-replace-$block'),
                            block: block,
                            sectionId: 'replace',
                            addLabel: addLabel,
                            onAdd: () => onBlockAdd(block),
                            child: _ReplaceBlockBody(
                              block: block,
                              rules: rulesByBlock[block] ?? const [],
                              emptyText: emptyText,
                              sourceLabel: sourceLabel,
                              targetLabel: targetLabel,
                              onEditSource: (index) =>
                                  onEditSource(block, index),
                              onEditTarget: (index) =>
                                  onEditTarget(block, index),
                              onRemove: (index) => onRemove(block, index),
                              onReorder: (from, targetIndex) => onReorder(
                                from.block,
                                from.index,
                                block,
                                targetIndex,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ))
          : (refs.isEmpty
              ? _FilterRuleEmptyText(text: emptyText)
              : Column(
                  children: [
                    for (final (index, ref) in refs.indexed)
                      _ReplaceRuleRow(
                        block: 'all',
                        index: index,
                        rule: ref.rule,
                        sourceLabel: sourceLabel,
                        targetLabel: targetLabel,
                        onEditSource: () =>
                            onEditSource(ref.block, ref.blockIndex),
                        onEditTarget: () =>
                            onEditTarget(ref.block, ref.blockIndex),
                        onRemove: () => onRemove(ref.block, ref.blockIndex),
                        onReorder: (from) => onReorder(
                          from.block,
                          from.index,
                          ref.block,
                          ref.blockIndex,
                        ),
                      ),
                  ],
                )),
    );
  }
}

class _FilterRuleSectionShell extends StatelessWidget {
  final String sectionId;
  final String title;
  final List<Widget> actions;
  final Widget child;

  const _FilterRuleSectionShell({
    required this.sectionId,
    required this.title,
    required this.actions,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: ValueKey('filter-rule-section-$sectionId'),
      decoration: BoxDecoration(
        color: StudioTokens.surface3,
        borderRadius: StudioTokens.radiusSlot,
        border: Border.all(color: StudioTokens.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: StudioTokens.textPrimary,
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 10),
            if (actions.isNotEmpty)
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: actions,
                ),
              ),
            if (actions.isNotEmpty) const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

class _FilterRuleBlockCard extends StatelessWidget {
  final String block;
  final String sectionId;
  final String addLabel;
  final String? batchAddLabel;
  final VoidCallback onAdd;
  final VoidCallback? onBatchAdd;
  final Widget child;

  const _FilterRuleBlockCard({
    super.key,
    required this.block,
    required this.sectionId,
    required this.addLabel,
    this.batchAddLabel,
    required this.onAdd,
    this.onBatchAdd,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: StudioTokens.surface2,
        borderRadius: StudioTokens.radiusSlot,
        border: Border.all(color: StudioTokens.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  _blockDisplayName(block),
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: StudioTokens.textPrimary,
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const Spacer(),
                if (onBatchAdd != null)
                  IconButton.filledTonal(
                    key: ValueKey(
                      'filter-rule-block-batch-add-$sectionId-$block',
                    ),
                    visualDensity: VisualDensity.compact,
                    tooltip: batchAddLabel,
                    style: _filterRuleIconButtonStyle(),
                    onPressed: onBatchAdd,
                    icon: const Icon(Icons.playlist_add, size: 18),
                  ),
                if (onBatchAdd != null) const SizedBox(width: 6),
                IconButton.filledTonal(
                  key: ValueKey('filter-rule-block-add-$sectionId-$block'),
                  visualDensity: VisualDensity.compact,
                  tooltip: addLabel,
                  style: _filterRuleIconButtonStyle(),
                  onPressed: onAdd,
                  icon: const Icon(Icons.add, size: 18),
                ),
              ],
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}

class _TokenBlockBody extends StatelessWidget {
  final String sectionId;
  final String block;
  final List<String> tags;
  final String emptyText;
  final TranslationCache? translationCache;
  final PromptTagClassificationCache? classificationCache;
  final ValueChanged<int> onEdit;
  final ValueChanged<int> onRemove;
  final void Function(_RuleTokenDragData from, int targetIndex) onReorder;

  const _TokenBlockBody({
    required this.sectionId,
    required this.block,
    required this.tags,
    required this.emptyText,
    required this.translationCache,
    required this.classificationCache,
    required this.onEdit,
    required this.onRemove,
    required this.onReorder,
  });

  @override
  Widget build(BuildContext context) {
    if (tags.isEmpty) {
      return Text(
        emptyText,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: StudioTokens.textMuted,
            ),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (index, tag) in tags.indexed)
          _EditableRuleToken(
            sectionId: '$sectionId-$block',
            block: block,
            index: index,
            text: tag,
            translationCache: translationCache,
            classificationCache: classificationCache,
            onEdit: () => onEdit(index),
            onRemove: () => onRemove(index),
            onReorder: (from) => onReorder(from, index),
          ),
      ],
    );
  }
}

class _ReplaceBlockBody extends StatelessWidget {
  final String block;
  final List<_EditableReplaceRule> rules;
  final String emptyText;
  final String sourceLabel;
  final String targetLabel;
  final ValueChanged<int> onEditSource;
  final ValueChanged<int> onEditTarget;
  final ValueChanged<int> onRemove;
  final void Function(_ReplaceRuleDragData from, int targetIndex) onReorder;

  const _ReplaceBlockBody({
    required this.block,
    required this.rules,
    required this.emptyText,
    required this.sourceLabel,
    required this.targetLabel,
    required this.onEditSource,
    required this.onEditTarget,
    required this.onRemove,
    required this.onReorder,
  });

  @override
  Widget build(BuildContext context) {
    if (rules.isEmpty) {
      return Text(
        emptyText,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: StudioTokens.textMuted,
            ),
      );
    }
    return Column(
      children: [
        for (final (index, rule) in rules.indexed)
          _ReplaceRuleRow(
            block: block,
            index: index,
            rule: rule,
            sourceLabel: sourceLabel,
            targetLabel: targetLabel,
            onEditSource: () => onEditSource(index),
            onEditTarget: () => onEditTarget(index),
            onRemove: () => onRemove(index),
            onReorder: (from) => onReorder(from, index),
          ),
      ],
    );
  }
}

class _ReplaceRuleRow extends StatelessWidget {
  final String block;
  final int index;
  final _EditableReplaceRule rule;
  final String sourceLabel;
  final String targetLabel;
  final VoidCallback onEditSource;
  final VoidCallback onEditTarget;
  final VoidCallback onRemove;
  final ValueChanged<_ReplaceRuleDragData> onReorder;

  const _ReplaceRuleRow({
    required this.block,
    required this.index,
    required this.rule,
    required this.sourceLabel,
    required this.targetLabel,
    required this.onEditSource,
    required this.onEditTarget,
    required this.onRemove,
    required this.onReorder,
  });

  @override
  Widget build(BuildContext context) {
    final data = _ReplaceRuleDragData(block: block, index: index);
    Widget row({Key? surfaceKey}) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _FilterRuleHoverSurface(
            surfaceKey: surfaceKey,
            padding: const EdgeInsets.all(8),
            borderRadius: StudioTokens.radiusSlot,
            idleColor: const Color(0xFF181818),
            hoverColor: StudioTokens.surface4,
            pressedColor: StudioTokens.surface4,
            idleBorderColor: StudioTokens.border,
            hoverBorderColor: StudioTokens.borderStrong,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _EditableReplaceValue(
                        keyPrefix: 'filter-rule-replace-source-$block-$index',
                        label: sourceLabel,
                        value: rule.source,
                        onEdit: onEditSource,
                      ),
                      const SizedBox(height: 4),
                      _EditableReplaceValue(
                        keyPrefix: 'filter-rule-replace-target-$block-$index',
                        label: targetLabel,
                        value: rule.target,
                        onEdit: onEditTarget,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _TinyIconButton(
                  key: ValueKey('filter-rule-replace-row-$block-$index-remove'),
                  icon: Icons.close,
                  onPressed: onRemove,
                ),
              ],
            ),
          ),
        );
    return DragTarget<_ReplaceRuleDragData>(
      key: ValueKey('filter-rule-replace-row-$block-$index'),
      onAcceptWithDetails: (details) => onReorder(details.data),
      builder: (context, candidates, rejected) {
        final highlighted = candidates.isNotEmpty;
        return Draggable<_ReplaceRuleDragData>(
          data: data,
          feedback: Material(
            color: Colors.transparent,
            child: Opacity(opacity: 0.85, child: row()),
          ),
          childWhenDragging: Opacity(opacity: 0.35, child: row()),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: StudioTokens.radiusSlot,
              border: Border.all(
                color: highlighted ? StudioTokens.primary : Colors.transparent,
              ),
            ),
            child: row(
              surfaceKey: ValueKey(
                'filter-rule-replace-row-$block-$index-surface',
              ),
            ),
          ),
        );
      },
    );
  }
}

class _EditableReplaceValue extends StatelessWidget {
  final String keyPrefix;
  final String label;
  final String value;
  final VoidCallback onEdit;

  const _EditableReplaceValue({
    required this.keyPrefix,
    required this.label,
    required this.value,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final text = value.trim().isEmpty ? '<empty>' : value;
    return _FilterRuleHoverSurface(
      surfaceKey: ValueKey('$keyPrefix-surface'),
      borderRadius: StudioTokens.radiusSlot,
      padding: const EdgeInsets.all(8),
      idleColor: Colors.transparent,
      hoverColor: StudioTokens.surface3,
      pressedColor: StudioTokens.surface4,
      idleBorderColor: Colors.transparent,
      hoverBorderColor: StudioTokens.border,
      onTap: onEdit,
      child: Row(
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: StudioTokens.primary,
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: value.trim().isEmpty
                        ? StudioTokens.textMuted
                        : StudioTokens.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          _TinyIconButton(
            key: ValueKey('$keyPrefix-edit'),
            icon: Icons.edit,
            onPressed: onEdit,
          ),
        ],
      ),
    );
  }
}

class _EditableRuleToken extends StatelessWidget {
  final String sectionId;
  final String block;
  final int index;
  final String text;
  final TranslationCache? translationCache;
  final PromptTagClassificationCache? classificationCache;
  final VoidCallback onEdit;
  final VoidCallback onRemove;
  final ValueChanged<_RuleTokenDragData> onReorder;

  const _EditableRuleToken({
    required this.sectionId,
    required this.block,
    required this.index,
    required this.text,
    required this.translationCache,
    required this.classificationCache,
    required this.onEdit,
    required this.onRemove,
    required this.onReorder,
  });

  @override
  Widget build(BuildContext context) {
    final category = PromptTagClassifier.classify(
      text,
      cache: classificationCache,
    ).category;
    final translation = translationCache?.translate(text).text.trim() ?? '';
    final data = _RuleTokenDragData(
      sectionId: sectionId,
      block: block,
      index: index,
    );
    Widget chip({Key? surfaceKey}) => _FilterRuleHoverSurface(
          surfaceKey: surfaceKey,
          constraints: const BoxConstraints(maxWidth: 320),
          borderRadius: StudioTokens.radiusTag,
          idleColor: const Color(0xFF181818),
          hoverColor: StudioTokens.surface4,
          pressedColor: StudioTokens.surface4,
          idleBorderColor: StudioTokens.border,
          hoverBorderColor: StudioTokens.borderStrong,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: _filterRuleCategoryColor(category),
                  borderRadius: StudioTokens.radiusTagStripe,
                ),
                child:
                    SizedBox(width: 3, height: translation.isEmpty ? 34 : 48),
              ),
              Flexible(
                child: InkWell(
                  onTap: onEdit,
                  borderRadius: StudioTokens.radiusTag,
                  child: Padding(
                    padding: const EdgeInsets.only(
                      left: 10,
                      top: 7,
                      bottom: 7,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          text,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.labelMedium?.copyWith(
                                    color: StudioTokens.textPrimary,
                                    fontWeight: FontWeight.w800,
                                  ),
                        ),
                        if (translation.isNotEmpty) ...[
                          const SizedBox(height: 1),
                          Text(
                            translation,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: StudioTokens.textSecondary,
                                    ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Icon(
                  Icons.drag_indicator,
                  size: 16,
                  color: StudioTokens.textSecondary,
                ),
              ),
              _TinyIconButton(
                key: ValueKey('filter-rule-token-$sectionId-$index-edit'),
                icon: Icons.edit,
                onPressed: onEdit,
              ),
              _TinyIconButton(
                key: ValueKey('filter-rule-token-$sectionId-$index-remove'),
                icon: Icons.close,
                onPressed: onRemove,
              ),
            ],
          ),
        );
    return DragTarget<_RuleTokenDragData>(
      key: ValueKey('filter-rule-token-$sectionId-$index'),
      onAcceptWithDetails: (details) => onReorder(details.data),
      builder: (context, candidates, rejected) {
        final highlighted = candidates.isNotEmpty;
        return Draggable<_RuleTokenDragData>(
          data: data,
          feedback: Material(
            color: Colors.transparent,
            child: Opacity(opacity: 0.85, child: chip()),
          ),
          childWhenDragging: Opacity(opacity: 0.35, child: chip()),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: StudioTokens.radiusTag,
              border: Border.all(
                color: highlighted ? StudioTokens.primary : Colors.transparent,
              ),
            ),
            child: chip(
              surfaceKey: ValueKey(
                'filter-rule-token-$sectionId-$index-surface',
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TinyIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;

  const _TinyIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      padding: EdgeInsets.zero,
      iconSize: 16,
      style: _filterRuleTinyIconButtonStyle(),
      color: StudioTokens.textSecondary,
      disabledColor: StudioTokens.textMuted.withAlpha(100),
      onPressed: onPressed,
      icon: Icon(icon),
    );
  }
}

ButtonStyle _filterRuleIconButtonStyle() {
  return IconButton.styleFrom(
    foregroundColor: StudioTokens.textPrimary,
    backgroundColor: StudioTokens.surface4,
    hoverColor: StudioTokens.primary.withAlpha(28),
    highlightColor: StudioTokens.primary.withAlpha(46),
    disabledForegroundColor: StudioTokens.textMuted.withAlpha(100),
  );
}

ButtonStyle _filterRuleTinyIconButtonStyle() {
  return IconButton.styleFrom(
    foregroundColor: StudioTokens.textSecondary,
    hoverColor: StudioTokens.primary.withAlpha(24),
    highlightColor: StudioTokens.primary.withAlpha(42),
    disabledForegroundColor: StudioTokens.textMuted.withAlpha(100),
  );
}

ButtonStyle _filterRuleDialogTextButtonStyle() {
  return TextButton.styleFrom(
    foregroundColor: StudioTokens.textPrimary,
  ).copyWith(
    overlayColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.pressed)) {
        return StudioTokens.primary.withAlpha(44);
      }
      if (states.contains(WidgetState.hovered)) {
        return StudioTokens.primary.withAlpha(24);
      }
      return null;
    }),
  );
}

ButtonStyle _filterRuleDialogPrimaryButtonStyle() {
  return FilledButton.styleFrom(
    foregroundColor: StudioTokens.onPrimary,
    backgroundColor: StudioTokens.primary,
  ).copyWith(
    overlayColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.pressed)) {
        return StudioTokens.onPrimary.withAlpha(52);
      }
      if (states.contains(WidgetState.hovered)) {
        return StudioTokens.onPrimary.withAlpha(36);
      }
      return null;
    }),
  );
}

Future<List<TagEntry>> _loadAvailableTagsFromCatalog() async {
  try {
    if (GetIt.I.isRegistered<StudioAssetCatalogService>()) {
      return GetIt.I<StudioAssetCatalogService>().loadWorkbenchTags();
    }
  } catch (_) {
    // Dialog can still edit typed rules when the studio catalog is unavailable.
  }
  return const [];
}

Map<String, List<T>> _emptyBlockMap<T>() {
  return <String, List<T>>{};
}

List<T> _listFor<T>(Map<String, List<T>> blockMap, String block) {
  return blockMap.putIfAbsent(block, () => <T>[]);
}

void _replaceTagBlocks(
  Map<String, List<String>> target,
  FilterRuleDocument document,
) {
  target
    ..clear()
    ..addAll(document.tagsByBlock);
}

Iterable<String> _flattenTagBlocks(
    Map<String, List<String>> tagsByBlock) sync* {
  for (final block in _sourceOrderBlocks(tagsByBlock)) {
    yield* tagsByBlock[block] ?? const <String>[];
  }
}

Iterable<_EditableReplaceRule> _flattenReplaceBlocks(
  Map<String, List<_EditableReplaceRule>> rulesByBlock,
) sync* {
  for (final block in _sourceOrderBlocks(rulesByBlock)) {
    yield* rulesByBlock[block] ?? const <_EditableReplaceRule>[];
  }
}

Iterable<String> _sourceOrderBlocks<T>(
        Map<String, List<T>> rulesByBlock) =>
    filterRuleSourceOrderBlocks(rulesByBlock);

List<String> _ruleWords(String text) => parseFilterRuleWords(text);

List<TagEntry> _dedupeTags(List<TagEntry> tags) {
  final seen = <String>{};
  final result = <TagEntry>[];
  for (final tag in tags) {
    final key = filterRuleMatchKey(tag.tag);
    if (key.isEmpty || !seen.add(key)) {
      continue;
    }
    result.add(tag);
  }
  result.sort((a, b) {
    final block = a.block.compareTo(b.block);
    if (block != 0) {
      return block;
    }
    return a.tag.compareTo(b.tag);
  });
  return List.unmodifiable(result);
}

String _blockDisplayName(String block) {
  return switch (block) {
    'style' => '风格',
    'sub_style' => '子风格',
    'character' => '角色',
    'clothing' => '服装',
    'action' => '动作',
    'expression' => '表情',
    'scene' => '场景',
    'camera' => '镜头',
    _ => block,
  };
}

Color _filterRuleCategoryColor(PromptTagCategory category) {
  return switch (category) {
    PromptTagCategory.character => const Color(0xFF5B8DEF),
    PromptTagCategory.upperBody => const Color(0xFF00B894),
    PromptTagCategory.lowerBody => const Color(0xFF36CFC9),
    PromptTagCategory.upperClothing => const Color(0xFF00A676),
    PromptTagCategory.lowerClothing => const Color(0xFF2E9F9F),
    PromptTagCategory.clothing => const Color(0xFF13C2C2),
    PromptTagCategory.action => const Color(0xFFF59E0B),
    PromptTagCategory.scene => const Color(0xFF8B9DC3),
    PromptTagCategory.camera => const Color(0xFF60A5FA),
    PromptTagCategory.artist => const Color(0xFFD946EF),
    PromptTagCategory.style => const Color(0xFFA78BFA),
    PromptTagCategory.quality => const Color(0xFFEAB308),
    PromptTagCategory.negativeQuality => const Color(0xFFEF4444),
    PromptTagCategory.negativeBody => const Color(0xFFDB2777),
    PromptTagCategory.negativeArtist => const Color(0xFFA855F7),
    PromptTagCategory.negativeContent => const Color(0xFFA16207),
    PromptTagCategory.promptSyntax => const Color(0xFF94A3B8),
    PromptTagCategory.other => StudioTokens.borderStrong,
  };
}

String _filterRulesLibraryText(
  BuildContext context,
  String key,
  String fallback,
) {
  try {
    final text = context.tr(key);
    return text == key ? fallback : text;
  } on Object {
    return fallback;
  }
}
