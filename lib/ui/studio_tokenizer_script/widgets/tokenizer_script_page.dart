import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:nai_casrand/data/studio/models/tokenizer_script.dart';
import 'package:nai_casrand/data/studio/services/tokenizer_script_service.dart';
import 'package:nai_casrand/ui/studio_core/theme/studio_tokens.dart';
import 'package:nai_casrand/ui/studio_core/widgets/studio_button.dart';
import 'package:nai_casrand/ui/studio_core/widgets/studio_metric_card.dart';
import 'package:nai_casrand/ui/studio_core/widgets/studio_panel.dart';

class TokenizerScriptPage extends StatefulWidget {
  final TokenizerScriptService service;

  const TokenizerScriptPage({super.key, required this.service});

  @override
  State<TokenizerScriptPage> createState() => _TokenizerScriptPageState();
}

class _TokenizerScriptPageState extends State<TokenizerScriptPage> {
  late Future<List<TokenizerScript>> _scriptsFuture;
  TokenizerScript? _selectedScript;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _scriptsFuture = widget.service.loadScripts();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<TokenizerScript>>(
      future: _scriptsFuture,
      builder: (context, snapshot) {
        final scripts = snapshot.data ?? const <TokenizerScript>[];
        final selected =
            _selectedScript ?? (scripts.isNotEmpty ? scripts.first : null);
        return LayoutBuilder(
          builder: (context, constraints) {
            final horizontalPadding = constraints.maxWidth >= 1600
                ? 32.0
                : constraints.maxWidth >= 900
                    ? 24.0
                    : 14.0;
            final maxContentWidth =
                constraints.maxWidth >= 1700 ? 1760.0 : 1280.0;
            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                20,
                horizontalPadding,
                32,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxContentWidth),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Header(
                        busy: _busy ||
                            snapshot.connectionState != ConnectionState.done,
                        onNewScript: _createDemoDraft,
                        onImportScript: _showImportDialog,
                        onKnowledge: selected == null
                            ? null
                            : () => _showKnowledgeDialog(selected),
                        onPendingRules: selected == null
                            ? null
                            : () => _showPendingRulesDialog(selected),
                      ),
                      const SizedBox(height: 16),
                      _OverviewStrip(scripts: scripts),
                      const SizedBox(height: 16),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final wide = constraints.maxWidth >= 980;
                          final list = _ScriptList(
                            scripts: scripts,
                            selectedId: selected?.scriptId,
                            onSelected: (script) {
                              setState(() => _selectedScript = script);
                            },
                          );
                          final details = _ScriptDetails(
                            script: selected,
                            busy: _busy,
                            onSave: selected == null
                                ? null
                                : () => _saveScript(selected),
                            onSend: selected == null
                                ? null
                                : () => _sendScript(selected),
                            onConfirmAll: selected == null
                                ? null
                                : () => _saveScript(
                                      widget.service.confirmReviewItems(
                                        selected,
                                        taskIds: [
                                          for (final task
                                              in selected.imageTasks)
                                            if (task.reviewStatus ==
                                                TokenizerTaskReviewStatus
                                                    .needsReview)
                                              task.taskId,
                                        ],
                                        candidateIds: [
                                          for (final candidate
                                              in selected.knowledgeCandidates)
                                            if (!candidate.confirmed)
                                              candidate.candidateId,
                                        ],
                                      ),
                                    ),
                          );
                          if (!wide) {
                            return Column(
                              children: [
                                list,
                                const SizedBox(height: 16),
                                details,
                              ],
                            );
                          }
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(width: 360, child: list),
                              const SizedBox(width: 16),
                              Expanded(child: details),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _createDemoDraft() async {
    setState(() => _busy = true);
    try {
      final script = await widget.service.createDemoDraft();
      await _reload(selected: script);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showImportDialog() async {
    final imported = await showDialog<TokenizerScript>(
      context: context,
      builder: (context) => _ImportScriptDialog(service: widget.service),
    );
    if (imported == null) return;
    setState(() => _busy = true);
    try {
      await widget.service.saveScript(imported);
      await _reload(selected: imported);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showKnowledgeDialog(TokenizerScript script) {
    return showDialog<void>(
      context: context,
      builder: (context) => _TokenizerInfoDialog(
        title: '知识库详情',
        icon: Icons.hub_outlined,
        child: _KnowledgeCandidatePanel(script: script),
      ),
    );
  }

  Future<void> _showPendingRulesDialog(TokenizerScript script) {
    return showDialog<void>(
      context: context,
      builder: (context) => _TokenizerInfoDialog(
        title: '待确认规则详情',
        icon: Icons.rule_folder_outlined,
        child: _ReviewQueuePanel(
          script: script,
          busy: _busy,
          onConfirmAll: null,
        ),
      ),
    );
  }

  Future<void> _saveScript(TokenizerScript script) async {
    setState(() => _busy = true);
    try {
      await widget.service.saveScript(script);
      await _reload(selected: script);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendScript(TokenizerScript script) async {
    setState(() => _busy = true);
    try {
      final updated = await widget.service.sendToProductionQueue(script);
      await _reload(selected: updated);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reload({TokenizerScript? selected}) async {
    final future = widget.service.loadScripts();
    final scripts = await future;
    if (!mounted) return;
    setState(() {
      _scriptsFuture = Future.value(scripts);
      _selectedScript = selected ?? _findSelected(scripts);
    });
  }

  TokenizerScript? _findSelected(List<TokenizerScript> scripts) {
    for (final script in scripts) {
      if (script.scriptId == _selectedScript?.scriptId) return script;
    }
    return scripts.isNotEmpty ? scripts.first : null;
  }
}

class _Header extends StatelessWidget {
  final bool busy;
  final VoidCallback onNewScript;
  final VoidCallback onImportScript;
  final VoidCallback? onKnowledge;
  final VoidCallback? onPendingRules;

  const _Header({
    required this.busy,
    required this.onNewScript,
    required this.onImportScript,
    required this.onKnowledge,
    required this.onPendingRules,
  });

  @override
  Widget build(BuildContext context) {
    return StudioPanel(
      color: StudioTokens.surface2,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 760;
          final title = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '分词剧本',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: StudioTokens.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                '把图片或 JSON 文件夹整理成可校验、可保存、可发送的一图一任务草案。',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          );
          final actions = Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: compact ? WrapAlignment.start : WrapAlignment.end,
            children: [
              StudioButton(
                label: busy ? '生成中...' : '新建剧本',
                icon: Icons.add_rounded,
                onPressed: busy ? null : onNewScript,
              ),
              StudioButton(
                label: '导入剧本',
                icon: Icons.file_open_outlined,
                tone: StudioButtonTone.ghost,
                onPressed: busy ? null : onImportScript,
              ),
              StudioButton(
                label: '知识库',
                icon: Icons.hub_outlined,
                tone: StudioButtonTone.ghost,
                onPressed: onKnowledge,
              ),
              StudioButton(
                label: '待确认规则',
                icon: Icons.rule_folder_outlined,
                tone: StudioButtonTone.ghost,
                onPressed: onPendingRules,
              ),
            ],
          );
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                title,
                const SizedBox(height: 16),
                actions,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: title),
              const SizedBox(width: 20),
              actions,
            ],
          );
        },
      ),
    );
  }
}

class _OverviewStrip extends StatelessWidget {
  final List<TokenizerScript> scripts;

  const _OverviewStrip({required this.scripts});

  @override
  Widget build(BuildContext context) {
    final taskCount = scripts.fold<int>(
      0,
      (sum, script) => sum + script.imageTasks.length,
    );
    final reviewCount = scripts.fold<int>(
      0,
      (sum, script) => sum + script.needsReviewCount,
    );
    final sentCount = scripts.fold<int>(
      0,
      (sum, script) => sum + script.sendRecords.length,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1000
            ? 4
            : constraints.maxWidth >= 620
                ? 2
                : 1;
        return GridView.count(
          crossAxisCount: columns,
          childAspectRatio: columns == 1 ? 5.4 : 3.8,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            StudioMetricCard(
              label: '剧本项目',
              value: scripts.length.toString(),
              icon: Icons.article_outlined,
            ),
            StudioMetricCard(
              label: '图片任务',
              value: taskCount.toString(),
              icon: Icons.image_search_outlined,
              accentColor: StudioTokens.info,
            ),
            StudioMetricCard(
              label: '需要校验',
              value: reviewCount.toString(),
              icon: Icons.fact_check_outlined,
              accentColor: StudioTokens.warning,
            ),
            StudioMetricCard(
              label: '发送记录',
              value: sentCount.toString(),
              icon: Icons.outbox_outlined,
              accentColor: StudioTokens.active,
            ),
          ],
        );
      },
    );
  }
}

class _ScriptList extends StatelessWidget {
  final List<TokenizerScript> scripts;
  final String? selectedId;
  final ValueChanged<TokenizerScript> onSelected;

  const _ScriptList({
    required this.scripts,
    required this.selectedId,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return StudioPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PanelHeader(title: '剧本列表', icon: Icons.article_outlined),
          const SizedBox(height: 12),
          if (scripts.isEmpty)
            const _InlineState(message: '还没有剧本。先用“新建剧本”生成一个模拟草案。')
          else
            for (final script in scripts)
              _ScriptListItem(
                script: script,
                selected: script.scriptId == selectedId,
                onTap: () => onSelected(script),
              ),
        ],
      ),
    );
  }
}

class _ScriptListItem extends StatelessWidget {
  final TokenizerScript script;
  final bool selected;
  final VoidCallback onTap;

  const _ScriptListItem({
    required this.script,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: selected
            ? StudioTokens.primary.withAlpha(26)
            : StudioTokens.surface2,
        borderRadius: StudioTokens.radiusSlot,
        child: InkWell(
          borderRadius: StudioTokens.radiusSlot,
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: StudioTokens.radiusSlot,
              border: Border.all(
                color: selected ? StudioTokens.primary : StudioTokens.border,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  script.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 6),
                Text(
                  '${script.imageTasks.length} 任务 · ${script.needsReviewCount} 待校验 · ${_statusLabel(script.status)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ScriptDetails extends StatelessWidget {
  final TokenizerScript? script;
  final bool busy;
  final VoidCallback? onSave;
  final VoidCallback? onSend;
  final VoidCallback? onConfirmAll;

  const _ScriptDetails({
    required this.script,
    required this.busy,
    required this.onSave,
    required this.onSend,
    required this.onConfirmAll,
  });

  @override
  Widget build(BuildContext context) {
    final script = this.script;
    if (script == null) {
      return const StudioPanel(
        child: _InlineState(message: '选择或新建一个分词剧本后，这里会显示三层任务结构。'),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StudioPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _PanelHeader(title: '剧本卡', icon: Icons.dataset_outlined),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _StatusChip(label: '来源 ${script.sourceFolder}'),
                  _StatusChip(label: '文件 ${script.sourceFiles.length}'),
                  _StatusChip(label: '已解析 ${script.parsedCount}'),
                  _StatusChip(label: '角色 ${script.characterIdentities.length}'),
                  _StatusChip(
                    label: script.hasArtistStack ? '含 [画师串]' : '缺少 [画师串]',
                    warning: !script.hasArtistStack,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  StudioButton(
                    label: busy ? '保存中...' : '保存剧本',
                    icon: Icons.save_outlined,
                    onPressed: busy ? null : onSave,
                  ),
                  StudioButton(
                    label: '发送到生产线',
                    icon: Icons.outbox_outlined,
                    tone: StudioButtonTone.ghost,
                    onPressed: busy ? null : onSend,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _ReviewQueuePanel(
          script: script,
          busy: busy,
          onConfirmAll: onConfirmAll,
        ),
        const SizedBox(height: 16),
        _KnowledgeCandidatePanel(script: script),
        const SizedBox(height: 16),
        _ScriptTaskSummaryPanel(script: script),
      ],
    );
  }
}

class _ImportScriptDialog extends StatefulWidget {
  final TokenizerScriptService service;

  const _ImportScriptDialog({required this.service});

  @override
  State<_ImportScriptDialog> createState() => _ImportScriptDialogState();
}

class _ImportScriptDialogState extends State<_ImportScriptDialog> {
  final _jsonController = TextEditingController();
  final _folderController = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _jsonController.dispose();
    _folderController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('导入分词剧本'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '可以粘贴导出的分词剧本 JSON，也可以选择包含图片/JSON 的文件夹生成新剧本。',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _jsonController,
                minLines: 5,
                maxLines: 8,
                decoration: const InputDecoration(
                  labelText: '剧本 JSON',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _folderController,
                decoration: InputDecoration(
                  labelText: '素材文件夹',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    tooltip: '选择文件夹',
                    onPressed: _busy ? null : _pickDirectory,
                    icon: const Icon(Icons.folder_open_outlined),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: StudioTokens.danger),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: _busy ? null : _importJson,
          child: const Text('导入 JSON'),
        ),
        FilledButton(
          onPressed: _busy ? null : _scanFolder,
          child: Text(_busy ? '导入中...' : '扫描文件夹'),
        ),
      ],
    );
  }

  Future<void> _pickDirectory() async {
    final path = await FilePicker.platform.getDirectoryPath();
    if (path == null) return;
    _folderController.text = path;
  }

  Future<void> _importJson() async {
    final raw = _jsonController.text.trim();
    if (raw.isEmpty) {
      setState(() => _error = '请先粘贴分词剧本 JSON。');
      return;
    }
    await _runImport(() async {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('JSON 根节点必须是对象。');
      }
      return widget.service.importScriptDocument(decoded);
    });
  }

  Future<void> _scanFolder() async {
    final path = _folderController.text.trim();
    if (path.isEmpty) {
      setState(() => _error = '请先选择或填写素材文件夹。');
      return;
    }
    await _runImport(() async {
      final directory = Directory(path);
      final result = await widget.service.scanDirectory(directory);
      final segments =
          directory.uri.pathSegments.where((segment) => segment.isNotEmpty);
      if (result.sources.isEmpty) {
        throw const FormatException('没有找到可导入的图片或 JSON 文件。');
      }
      final folderName = segments.isNotEmpty ? segments.last : '导入分词剧本';
      assert(folderName.isNotEmpty);
      return widget.service.createDraftFromSources(
        name: folderName,
        sourceFolder: path,
        sources: result.sources,
      );
    });
  }

  Future<void> _runImport(Future<TokenizerScript> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final script = await action();
      if (!mounted) return;
      Navigator.of(context).pop(script);
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _TokenizerInfoDialog extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _TokenizerInfoDialog({
    required this.title,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(icon, color: StudioTokens.primary),
          const SizedBox(width: 10),
          Text(title),
        ],
      ),
      content: SizedBox(
        width: 720,
        child: SingleChildScrollView(child: child),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}

class _ReviewQueuePanel extends StatelessWidget {
  final TokenizerScript script;
  final bool busy;
  final VoidCallback? onConfirmAll;

  const _ReviewQueuePanel({
    required this.script,
    required this.busy,
    required this.onConfirmAll,
  });

  @override
  Widget build(BuildContext context) {
    final reviewTasks = script.imageTasks
        .where(
          (task) => task.reviewStatus == TokenizerTaskReviewStatus.needsReview,
        )
        .toList(growable: false);
    final warningCount = reviewTasks.fold<int>(
      0,
      (count, task) => count + task.warnings.length,
    );
    final pendingCandidates = script.knowledgeCandidates
        .where((candidate) => !candidate.confirmed)
        .toList(growable: false);
    return StudioPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.fact_check_outlined,
                  size: 19, color: StudioTokens.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '校验队列',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              StudioButton(
                label: '确认全部',
                icon: Icons.done_all_outlined,
                tone: StudioButtonTone.ghost,
                onPressed: busy || reviewTasks.isEmpty ? null : onConfirmAll,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('手动校验 / AI 辅助', style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 12),
          if (reviewTasks.isEmpty && pendingCandidates.isEmpty)
            const _InlineState(message: '当前没有待校验任务。')
          else ...[
            if (reviewTasks.isNotEmpty)
              _ReviewQueueRow(
                icon: Icons.inventory_2_outlined,
                title: '待校验图片任务 ${reviewTasks.length}',
                detail: warningCount == 0 ? '低置信度任务' : '警告 $warningCount',
              ),
            for (final candidate in pendingCandidates)
              _ReviewQueueRow(
                icon: Icons.rule_folder_outlined,
                title: candidate.label,
                detail: candidate.evidence,
              ),
          ],
        ],
      ),
    );
  }
}

class _KnowledgeCandidatePanel extends StatelessWidget {
  final TokenizerScript script;

  const _KnowledgeCandidatePanel({required this.script});

  @override
  Widget build(BuildContext context) {
    return StudioPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PanelHeader(title: '知识候选', icon: Icons.hub_outlined),
          const SizedBox(height: 8),
          Text(
            '只展示当前剧本内待确认或已确认的规则，不会自动污染长期知识库。',
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: 12),
          if (script.knowledgeCandidates.isEmpty)
            const _InlineState(message: '当前剧本没有知识候选。')
          else
            for (final candidate in script.knowledgeCandidates)
              _ReviewQueueRow(
                icon: candidate.confirmed
                    ? Icons.verified_outlined
                    : Icons.rule_folder_outlined,
                title: candidate.label,
                detail: candidate.evidence,
              ),
        ],
      ),
    );
  }
}

class _ReviewQueueRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String detail;

  const _ReviewQueueRow({
    required this.icon,
    required this.title,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: StudioTokens.surface2,
        borderRadius: StudioTokens.radiusSlot,
        border: StudioTokens.cardBorder,
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: StudioTokens.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 3),
                Text(
                  detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScriptTaskSummaryPanel extends StatelessWidget {
  final TokenizerScript script;

  const _ScriptTaskSummaryPanel({required this.script});

  @override
  Widget build(BuildContext context) {
    final warningCount = script.imageTasks.fold<int>(
      0,
      (count, task) => count + task.warnings.length,
    );
    return StudioPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PanelHeader(title: '任务摘要', icon: Icons.inventory_2_outlined),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _StatusChip(label: '任务 ${script.imageTasks.length}'),
              _StatusChip(label: '源文件 ${script.sourceFiles.length}'),
              _StatusChip(label: '已解析 ${script.parsedCount}'),
              _StatusChip(
                label: '待校验 ${script.needsReviewCount}',
                warning: script.needsReviewCount > 0,
              ),
              _StatusChip(
                label: '警告 $warningCount',
                warning: warningCount > 0,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PanelHeader extends StatelessWidget {
  final String title;
  final IconData icon;

  const _PanelHeader({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 19, color: StudioTokens.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final bool warning;

  const _StatusChip({required this.label, this.warning = false});

  @override
  Widget build(BuildContext context) {
    final color = warning ? StudioTokens.warning : StudioTokens.active;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withAlpha(24),
        borderRadius: StudioTokens.radiusTag,
        border: Border.all(color: color.withAlpha(120)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
        ),
      ),
    );
  }
}

class _InlineState extends StatelessWidget {
  final String message;

  const _InlineState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: StudioTokens.surface2,
        borderRadius: StudioTokens.radiusSlot,
        border: StudioTokens.cardBorder,
      ),
      child: Text(message, style: Theme.of(context).textTheme.bodyMedium),
    );
  }
}

String _statusLabel(TokenizerScriptStatus status) {
  return switch (status) {
    TokenizerScriptStatus.scanning => '扫描中',
    TokenizerScriptStatus.parsed => '已解析',
    TokenizerScriptStatus.needsReview => '待校验',
    TokenizerScriptStatus.ready => '可发送',
    TokenizerScriptStatus.sent => '已发送',
    TokenizerScriptStatus.archived => '已归档',
  };
}
