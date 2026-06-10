import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:nai_casrand/data/models/command_status.dart';
import 'package:nai_casrand/data/models/info_card_content.dart';
import 'package:nai_casrand/data/models/payload_config.dart';
import 'package:nai_casrand/data/models/settings.dart';
import 'package:nai_casrand/ui/core/utils/flushbar.dart';
import 'package:nai_casrand/ui/studio_core/theme/studio_tokens.dart';
import 'package:nai_casrand/ui/studio_core/widgets/studio_panel.dart';
import 'package:nai_casrand/ui/studio_core/widgets/prompt_tag_display.dart';
import 'package:flutter_command/flutter_command.dart';

class InfoCard extends StatelessWidget {
  final Command<void, InfoCardContent> command;

  CommandStatus get commandStatus => GetIt.I();
  Settings get settings => GetIt.I<PayloadConfig>().settings;

  const InfoCard({super.key, required this.command});

  @override
  Widget build(BuildContext context) {
    final cardBody = ListenableBuilder(
      listenable: command.isExecuting,
      builder: (context, child) {
        if (command.isExecuting.value) {
          final current = commandStatus.currentTotalCount.toString();
          final total = settings.numberOfRequests != 0
              ? settings.numberOfRequests.toString()
              : '∞';
          // Loading
          return ListTile(
            leading: const CircularProgressIndicator(),
            title: Text('Requesting $current/$total ...'),
          );
        } else {
          // Result
          return _buildCardContentBody(context, command.value);
        }
      },
    );

    return Padding(
      padding: const EdgeInsets.all(6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: StudioTokens.radiusCard,
          onTap: () => _showDetailedInfoDialog(context),
          child: StudioPanel(
            padding: EdgeInsets.zero,
            child: ClipRect(child: cardBody),
          ),
        ),
      ),
    );
  }

  void _showDetailedInfoDialog(BuildContext context) {
    if (command.isExecuting.value) return;
    final content = command.value;

    // 跳转到新页面
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => InfoDetailPage(content: content),
      ),
    );
  }

  Widget buildInfoTile(String title, String content, BuildContext context) {
    return ListTile(
      titleAlignment: ListTileTitleAlignment.titleHeight,
      title: Text(title),
      subtitle: Text(content),
      trailing: IconButton(
          onPressed: () {
            _copyContent(content, context);
            Navigator.of(context).pop();
          },
          icon: const Icon(Icons.copy)),
    );
  }

  void _copyContent(String content, BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: content));
    if (!context.mounted) return;
    showInfoBar(context, '${tr('info_export_to_clipboard')}${tr('succeed')}');
  }

  Widget _buildCardContentBody(BuildContext context, InfoCardContent content) {
    return content.imageBytes == null
        ? //Without image
        Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: _buildTitle(content),
              ),
              ListTile(
                subtitle: _PromptInfoDisplay(
                  text: content.info,
                  groups: _contentPromptGroups(content),
                  dense: true,
                  maxTags: 12,
                ),
              )
            ],
          )
        : // With image
        Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_outlined),
                title: _buildTitle(content),
              ),
              _buildGeneratedImage(context, content.imageBytes!),
            ],
          );
  }

  Widget _buildGeneratedImage(BuildContext context, Uint8List imageBytes) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth =
            constraints.maxWidth.isFinite ? constraints.maxWidth : 360.0;
        final frameHeight = math.min(360.0, maxWidth);

        return Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          child: SizedBox(
            key: const ValueKey('generated-info-card-image-frame'),
            width: double.infinity,
            height: frameHeight,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: ColoredBox(
                color: Theme.of(context).colorScheme.surface,
                child: Image.memory(
                  imageBytes,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.medium,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTitle(InfoCardContent content) {
    final contentOrderText = content.contentOrderText;
    if (contentOrderText == null || contentOrderText.isEmpty) {
      return Text(
        content.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }
    return Row(
      children: [
        Expanded(
          child: Text(
            content.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          contentOrderText,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class InfoDetailPage extends StatelessWidget {
  final InfoCardContent content;

  const InfoDetailPage({super.key, required this.content});

  @override
  Widget build(BuildContext context) {
    List<Widget> contents = [
      buildInfoTile(tr('title'), content.title, context),
      buildInfoTile(
        tr('info'),
        content.info,
        context,
        asPrompt: true,
        groups: _contentPromptGroups(content),
      ),
    ];
    for (final item in content.additionalInfo.entries) {
      contents.add(
        buildInfoTile(
          item.key,
          item.value.toString(),
          context,
          asPrompt: _isPromptLikeKey(item.key),
          groups: _promptGroupsForInfoEntry(item.key, item.value),
        ),
      );
    }

    final body = Scaffold(
      appBar: AppBar(title: Text(content.title)),
      body: SingleChildScrollView(
        child: Column(
          children: [
            if (content.imageBytes != null)
              Image.memory(content.imageBytes!, fit: BoxFit.contain),
            ...contents,
          ],
        ),
      ),
    );

    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: body,
    );
  }

  Widget buildInfoTile(
    String title,
    String content,
    BuildContext context, {
    bool asPrompt = false,
    List<PromptTagDisplayGroup> groups = const [],
  }) {
    return Column(children: [
      ListTile(
        titleAlignment: ListTileTitleAlignment.top,
        title: Text(title),
        subtitle: asPrompt
            ? _PromptInfoDisplay(text: content, groups: groups)
            : SelectableText(content),
        trailing: IconButton(
            onPressed: () {
              Navigator.of(context).pop();
              _copyContent(content, context);
            },
            tooltip: tr('copy_to_clipboard'),
            icon: const Icon(Icons.copy)),
      ),
      const Divider(),
    ]);
  }

  bool _isPromptLikeKey(String key) {
    final normalized = key.toLowerCase();
    return normalized.contains('prompt') ||
        normalized.contains('tag') ||
        normalized == 'input';
  }

  void _copyContent(String content, BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: content));
    if (!context.mounted) return;
    showInfoBar(context, '${tr('info_export_to_clipboard')}${tr('succeed')}');
  }

  getSelectableTextPage(String title, String text) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('selectable') + tr('colon') + title),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SelectableText(text),
      ),
    );
  }
}

class _PromptInfoDisplay extends StatelessWidget {
  final String text;
  final List<PromptTagDisplayGroup> groups;
  final bool dense;
  final int? maxTags;

  const _PromptInfoDisplay({
    required this.text,
    this.groups = const [],
    this.dense = false,
    this.maxTags,
  });

  @override
  Widget build(BuildContext context) {
    final visibleGroups =
        groups.where((group) => group.hasText).toList(growable: false);
    if (visibleGroups.isNotEmpty) {
      return PromptTagGroupDisplay(
        key: const ValueKey('info-card-prompt-groups'),
        groups: visibleGroups,
        groupKeyPrefix: 'info-card-prompt-group',
        tagKeyPrefix: 'info-card-prompt-group-tags',
        defaultTranslated: true,
        dense: dense,
        maxTags: maxTags,
        enableHoverShortcut: text.trim().isNotEmpty,
        enableTagActions: true,
        initialLayoutMode: PromptTagLayoutMode.grouped,
      );
    }
    return PromptTagDisplay(
      text: text,
      defaultTranslated: true,
      dense: dense,
      maxTags: maxTags,
    );
  }
}

List<PromptTagDisplayGroup> _contentPromptGroups(InfoCardContent content) {
  return _promptGroupsForInfoEntry(
    'v4_prompt',
    content.additionalInfo['v4_prompt'] ??
        _infoMapValue(content.additionalInfo['parameters'])['v4_prompt'] ??
        _infoMapValue(content.additionalInfo['Comment'])['v4_prompt'],
  );
}

List<PromptTagDisplayGroup> _promptGroupsForInfoEntry(
  String key,
  Object? value,
) {
  final normalized = key.toLowerCase();
  if (normalized == 'v4_prompt') {
    return promptTagGroupsFromV4Prompt(_infoMapValue(value));
  }
  if (normalized == 'v4_negative_prompt') {
    return promptTagGroupsFromV4Prompt(
      _infoMapValue(value),
      negative: true,
    );
  }
  final map = _infoMapValue(value);
  if (map.isNotEmpty) {
    final prompt = _infoMapValue(map['v4_prompt']);
    if (prompt.isNotEmpty) {
      return promptTagGroupsFromV4Prompt(prompt);
    }
    final negativePrompt = _infoMapValue(map['v4_negative_prompt']);
    if (negativePrompt.isNotEmpty) {
      return promptTagGroupsFromV4Prompt(negativePrompt, negative: true);
    }
  }
  return const [];
}

Map<String, dynamic> _infoMapValue(Object? value) {
  if (value is Map) {
    return value.cast<String, dynamic>();
  }
  return const <String, dynamic>{};
}
