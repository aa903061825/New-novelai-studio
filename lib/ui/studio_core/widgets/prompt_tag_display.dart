import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:nai_casrand/data/models/payload_config.dart';
import 'package:nai_casrand/data/studio/services/prompt_workshop_bridge.dart';
import 'package:nai_casrand/data/studio/services/prompt_translation_service.dart';
import 'package:nai_casrand/data/studio/tools/online_ai_tools.dart';
import 'package:nai_casrand/data/studio/tools/prompt_tag_classifier.dart';
import 'package:nai_casrand/data/studio/tools/prompt_tag_processor.dart';
import 'package:nai_casrand/data/studio/tools/translation_cache.dart';
import 'package:nai_casrand/ui/core/app_display_settings.dart';
import 'package:nai_casrand/ui/studio_core/services/prompt_tag_auto_translation_queue.dart';
import 'package:nai_casrand/ui/studio_core/services/prompt_tag_filter_rules.dart';
import 'package:nai_casrand/ui/studio_core/services/prompt_tag_list_utils.dart';
import 'package:nai_casrand/ui/studio_core/services/prompt_tag_presentation.dart';
import 'package:nai_casrand/ui/studio_core/theme/prompt_tag_category_style.dart';
import 'package:nai_casrand/ui/studio_core/theme/studio_tokens.dart';
import 'package:nai_casrand/ui/studio_core/widgets/prompt_tag_chip.dart';
import 'package:nai_casrand/ui/studio_core/widgets/prompt_tag_drag.dart';
import 'package:nai_casrand/ui/studio_core/widgets/prompt_tag_selection_toolbar.dart';
import 'package:url_launcher/url_launcher.dart';

export 'package:nai_casrand/ui/studio_core/services/prompt_tag_filter_rules.dart'
    show
        PromptTagFilterRuleAdder,
        PromptTagFilterRuleTarget,
        PromptTagFilterRulesController;

typedef PromptTagAiRetranslate = Future<String?> Function(String tag);
typedef PromptTagDanbooruLauncher = Future<void> Function(Uri uri);
typedef PromptTagTranslationCacheSaver = Future<void> Function(
    TranslationCache cache);
typedef PromptTagClassificationCacheSaver = Future<void> Function(
    PromptTagClassificationCache cache);
typedef PromptTagGroupActionBuilder = Widget? Function(
  BuildContext context,
  PromptTagGroupActionContext group,
);
typedef PromptTagDisplayDiffResolver = PromptTagChipDiffState Function(
  String tag,
);
typedef PromptTagGroupDiffResolver = PromptTagChipDiffState Function(
  String groupId,
  String tag,
);

const defaultPromptTagFilterRuleTargets = [
  PromptTagFilterRuleTarget.deleteKeywords,
  PromptTagFilterRuleTarget.strongFilterKeywords,
  PromptTagFilterRuleTarget.replaceSource,
];

class PromptTagGroupActionContext {
  final PromptTagGroup group;
  final List<PromptTagGroupActionTag> tags;

  const PromptTagGroupActionContext({
    required this.group,
    required this.tags,
  });

  List<String> get displayTags =>
      tags.map((tag) => tag.displayText).toList(growable: false);

  List<String> get promptTags =>
      tags.map((tag) => tag.promptText).toList(growable: false);
}

class PromptTagGroupActionTag {
  final String promptText;
  final String displayText;
  final String? weightLabel;
  final double? weight;
  final PromptTagClassification classification;

  const PromptTagGroupActionTag({
    required this.promptText,
    required this.displayText,
    required this.classification,
    this.weightLabel,
    this.weight,
  });
}

enum PromptTagLayoutMode { sourceOrder, grouped, layered }

class PromptTagDisplayGroup {
  final String id;
  final String label;
  final String text;
  final bool negative;

  const PromptTagDisplayGroup({
    required this.id,
    required this.label,
    required this.text,
    this.negative = false,
  });

  factory PromptTagDisplayGroup.fromTags({
    required String id,
    required String label,
    required Iterable<String> tags,
    bool negative = false,
  }) {
    return PromptTagDisplayGroup(
      id: id,
      label: label,
      text: tags
          .map((tag) => tag.trim())
          .where((tag) => tag.isNotEmpty && tag != '未检测')
          .join(', '),
      negative: negative,
    );
  }

  bool get hasText => text.trim().isNotEmpty && text.trim() != '未检测';
}

class PromptTagGroupDisplay extends StatelessWidget {
  final List<PromptTagDisplayGroup> groups;
  final bool defaultTranslated;
  final bool enableHoverShortcut;
  final bool enableTagActions;
  final bool dense;
  final int? maxTags;
  final String emptyText;
  final TranslationCache? translationCache;
  final PromptTagClassificationCache? classificationCache;
  final PromptTagAiRetranslate? onAiRetranslate;
  final PromptTagDanbooruLauncher? onOpenDanbooru;
  final PromptTagFilterRuleAdder? onAddToFilterRules;
  final List<PromptTagFilterRuleTarget> filterRuleTargets;
  final PromptTagTranslationCacheSaver? saveTranslationCache;
  final PromptTagClassificationCacheSaver? saveClassificationCache;
  final Map<String, PromptTagCategory> classificationOverrides;
  final VoidCallback? onClassificationChanged;
  final PromptTagLayoutMode initialLayoutMode;
  final bool respectInitialLayoutMode;
  final bool showLayoutControls;
  final ValueChanged<String>? onTagTap;
  final ValueChanged<String>? onChanged;
  final PromptTagGroupActionBuilder? groupActionBuilder;
  final PromptTagGroupDiffResolver? diffStateForTag;
  final String groupKeyPrefix;
  final String tagKeyPrefix;

  const PromptTagGroupDisplay({
    super.key,
    required this.groups,
    this.defaultTranslated = false,
    this.enableHoverShortcut = false,
    this.enableTagActions = false,
    this.dense = false,
    this.maxTags,
    this.emptyText = '',
    this.translationCache,
    this.classificationCache,
    this.onAiRetranslate,
    this.onOpenDanbooru,
    this.onAddToFilterRules,
    this.filterRuleTargets = defaultPromptTagFilterRuleTargets,
    this.saveTranslationCache,
    this.saveClassificationCache,
    this.classificationOverrides = const {},
    this.onClassificationChanged,
    this.initialLayoutMode = PromptTagLayoutMode.grouped,
    this.respectInitialLayoutMode = false,
    this.showLayoutControls = false,
    this.onTagTap,
    this.onChanged,
    this.groupActionBuilder,
    this.diffStateForTag,
    this.groupKeyPrefix = 'prompt-tag-display-layer',
    this.tagKeyPrefix = 'prompt-tag-display-layer-tags',
  });

  @override
  Widget build(BuildContext context) {
    final visibleGroups =
        groups.where((group) => group.hasText).toList(growable: false);
    if (visibleGroups.isEmpty) {
      if (emptyText.isEmpty) {
        return const SizedBox.shrink();
      }
      return Text(
        emptyText,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: StudioTokens.textMuted,
            ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, group) in visibleGroups.indexed) ...[
          Container(
            key: ValueKey('$groupKeyPrefix-${group.id}'),
            padding: dense ? const EdgeInsets.all(8) : const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: StudioTokens.surface2,
              borderRadius: StudioTokens.radiusSlot,
              border: StudioTokens.cardBorder,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  group.label,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: StudioTokens.textPrimary,
                        fontWeight: FontWeight.w900,
                      ),
                ),
                SizedBox(height: dense ? 6 : 8),
                PromptTagDisplay(
                  key: ValueKey('$tagKeyPrefix-${group.id}'),
                  text: group.text,
                  defaultTranslated: defaultTranslated,
                  enableHoverShortcut: enableHoverShortcut,
                  enableTagActions: enableTagActions,
                  dense: dense,
                  maxTags: maxTags,
                  emptyText: emptyText,
                  translationCache: translationCache,
                  classificationCache: classificationCache,
                  onAiRetranslate: onAiRetranslate,
                  onOpenDanbooru: onOpenDanbooru,
                  onAddToFilterRules: onAddToFilterRules,
                  filterRuleTargets: filterRuleTargets,
                  saveTranslationCache: saveTranslationCache,
                  saveClassificationCache: saveClassificationCache,
                  classificationOverrides: classificationOverrides,
                  onClassificationChanged: onClassificationChanged,
                  initialLayoutMode: initialLayoutMode,
                  respectInitialLayoutMode: respectInitialLayoutMode,
                  showLayoutControls: showLayoutControls,
                  negative: group.negative,
                  onTagTap: onTagTap,
                  onChanged: onChanged,
                  groupActionBuilder: groupActionBuilder,
                  diffStateForTag: diffStateForTag == null
                      ? null
                      : (tag) => diffStateForTag!(group.id, tag),
                ),
              ],
            ),
          ),
          if (index != visibleGroups.length - 1)
            SizedBox(height: dense ? 8 : 10),
        ],
      ],
    );
  }
}

List<PromptTagDisplayGroup> promptTagGroupsFromV4Prompt(
  Map<String, dynamic> prompt, {
  bool negative = false,
}) {
  final caption = _promptTagDisplayMapValue(prompt['caption']);
  final groups = <PromptTagDisplayGroup>[];
  final charCaptions = caption['char_captions'] ?? prompt['char_captions'];
  if (charCaptions is Iterable) {
    for (final (index, entry) in charCaptions.indexed) {
      final value = entry is Map
          ? _promptTagDisplayFirstStringValue([
              entry['char_caption'],
              entry['caption'],
              entry['base_caption'],
              entry['baseCaption'],
              entry['prompt'],
            ])
          : _promptTagDisplayStringValue(entry);
      if (value == null) continue;
      groups.add(
        PromptTagDisplayGroup(
          id: 'role-${index + 1}',
          label: negative ? '负面角色 ${index + 1}' : '角色 ${index + 1}',
          text: value,
          negative: negative,
        ),
      );
    }
  }

  final base = _promptTagDisplayFirstStringValue([
    caption['base_caption'],
    caption['baseCaption'],
    caption['prompt'],
    caption['caption'],
  ]);
  if (base != null) {
    groups.add(
      PromptTagDisplayGroup(
        id: negative ? 'negative-base' : 'base',
        label: negative ? '负面基础' : '基础提示词',
        text: base,
        negative: negative,
      ),
    );
  }

  return List.unmodifiable(groups);
}

String promptTextFromV4Prompt(Map<String, dynamic> prompt) {
  return promptTagGroupsFromV4Prompt(prompt)
      .map((group) => group.text.trim())
      .where((text) => text.isNotEmpty)
      .join(', ');
}

List<PromptTagDisplayGroup> promptTagGroupsFromV4PromptValue(
  Object? prompt, {
  bool negative = false,
}) {
  return promptTagGroupsFromV4Prompt(
    _promptTagDisplayMapValue(prompt),
    negative: negative,
  );
}

List<PromptTagDisplayGroup> promptTagGroupsFromPromptParameters(
  Object? parameters, {
  bool negative = false,
}) {
  final map = _promptTagDisplayMapValue(parameters);
  return promptTagGroupsFromV4PromptValue(
    map[negative ? 'v4_negative_prompt' : 'v4_prompt'],
    negative: negative,
  );
}

List<PromptTagDisplayGroup> promptTagGroupsFromPayloadConfig(
  PayloadConfig config,
) {
  return promptTagGroupsFromWorkbenchPayload(config.toJson());
}

List<PromptTagDisplayGroup> promptTagGroupsFromWorkbenchPayload(
  Object? payload,
) {
  final map = _promptTagDisplayMapValue(payload);
  for (final source in [
    map,
    _promptTagDisplayMapValue(map['param_config']),
    _promptTagDisplayMapValue(map['parameters']),
  ]) {
    final groups = promptTagGroupsFromPromptParameters(source);
    if (groups.any((group) => group.hasText)) return groups;
  }

  final useOverridePrompt = map['use_override_prompt'] == true;
  final useCharacterPromptWithOverride =
      map['use_character_prompt_with_override'] == true;
  final includeCharacterPrompts =
      !useOverridePrompt || useCharacterPromptWithOverride;
  if (!includeCharacterPrompts) {
    return const <PromptTagDisplayGroup>[];
  }

  final groups = <PromptTagDisplayGroup>[];
  final rawCharacters = map['character_config'];
  if (rawCharacters is Iterable) {
    for (final rawCharacter in rawCharacters) {
      final character = _promptTagDisplayMapValue(rawCharacter);
      if (character['enabled'] == false) continue;
      final text = _promptTagDisplayPromptConfigText(
        character['positivePromptConfig'] ??
            character['positive_prompt_config'] ??
            character['prompt_config'],
      );
      if (text.isEmpty) continue;
      groups.add(
        PromptTagDisplayGroup(
          id: 'role-${groups.length + 1}',
          label: '\u89d2\u8272 ${groups.length + 1}',
          text: text,
        ),
      );
    }
  }

  if (groups.isEmpty) {
    return const <PromptTagDisplayGroup>[];
  }

  final baseText = useOverridePrompt
      ? _promptTagDisplayStringValue(map['override_prompt'])
      : _promptTagDisplayPromptConfigText(map['prompt_config']);
  if (baseText != null && baseText.isNotEmpty) {
    groups.add(
      PromptTagDisplayGroup(
        id: 'base',
        label: '\u57fa\u7840\u63d0\u793a\u8bcd',
        text: baseText,
      ),
    );
  }

  return List.unmodifiable(groups);
}

Map<String, dynamic> _promptTagDisplayMapValue(Object? value) {
  if (value is Map) {
    return value.cast<String, dynamic>();
  }
  return const <String, dynamic>{};
}

String? _promptTagDisplayFirstStringValue(Iterable<Object?> values) {
  for (final value in values) {
    final string = _promptTagDisplayStringValue(value);
    if (string != null) return string;
  }
  return null;
}

String? _promptTagDisplayStringValue(Object? value) {
  if (value is String) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
  return null;
}

String _promptTagDisplayPromptConfigText(Object? value) {
  final map = _promptTagDisplayMapValue(value);
  if (map.isEmpty || map['enabled'] == false) return '';
  final parts = <String>[];
  final strs = map['strs'];
  if (strs is Iterable) {
    for (final row in strs) {
      final text = _promptTagDisplayStringValue(row);
      if (text != null) parts.add(text);
    }
  }
  final prompts = map['prompts'];
  if (prompts is Iterable) {
    for (final child in prompts) {
      final text = _promptTagDisplayPromptConfigText(child);
      if (text.isNotEmpty) parts.add(text);
    }
  }
  return parts.join(', ');
}

class PromptTagDisplay extends StatefulWidget {
  final String text;
  final bool defaultTranslated;
  final bool enableHoverShortcut;
  final bool enableTagActions;
  final bool dense;
  final int? maxTags;
  final String emptyText;
  final TranslationCache? translationCache;
  final PromptTagClassificationCache? classificationCache;
  final PromptTagAiRetranslate? onAiRetranslate;
  final PromptTagDanbooruLauncher? onOpenDanbooru;
  final PromptTagFilterRuleAdder? onAddToFilterRules;
  final List<PromptTagFilterRuleTarget> filterRuleTargets;
  final PromptTagTranslationCacheSaver? saveTranslationCache;
  final PromptTagClassificationCacheSaver? saveClassificationCache;
  final Map<String, PromptTagCategory> classificationOverrides;
  final VoidCallback? onClassificationChanged;
  final PromptTagLayoutMode initialLayoutMode;
  final bool respectInitialLayoutMode;
  final bool showLayoutControls;
  final bool negative;
  final ValueChanged<String>? onTagTap;
  final ValueChanged<String>? onChanged;
  final PromptTagSelectionController? selectionController;
  final String? selectionFieldId;
  final String? selectionGroupId;
  final bool showSelectionToolbar;
  final PromptTagGroupActionBuilder? groupActionBuilder;
  final PromptTagDisplayDiffResolver? diffStateForTag;

  const PromptTagDisplay({
    super.key,
    required this.text,
    this.defaultTranslated = false,
    this.enableHoverShortcut = false,
    this.enableTagActions = false,
    this.dense = false,
    this.maxTags,
    this.emptyText = '',
    this.translationCache,
    this.classificationCache,
    this.onAiRetranslate,
    this.onOpenDanbooru,
    this.onAddToFilterRules,
    this.filterRuleTargets = defaultPromptTagFilterRuleTargets,
    this.saveTranslationCache,
    this.saveClassificationCache,
    this.classificationOverrides = const {},
    this.onClassificationChanged,
    this.initialLayoutMode = PromptTagLayoutMode.grouped,
    this.respectInitialLayoutMode = false,
    this.showLayoutControls = false,
    this.negative = false,
    this.onTagTap,
    this.onChanged,
    this.selectionController,
    this.selectionFieldId,
    this.selectionGroupId,
    this.showSelectionToolbar = true,
    this.groupActionBuilder,
    this.diffStateForTag,
  });

  @override
  State<PromptTagDisplay> createState() => _PromptTagDisplayState();
}

class _PromptTagDisplayState extends State<PromptTagDisplay> {
  static int _nextHoverId = 0;
  static int _nextDragOrigin = 0;

  late final String _hoverId = 'prompt-tag-display-${_nextHoverId++}';
  late final String _dragOriginId = 'prompt-tag-display-${_nextDragOrigin++}';
  bool _shortcutTranslated = false;
  int? _hoveredIndex;
  final Set<String> _autoTranslationPending = <String>{};
  final Set<int> _selectedIndexes = <int>{};
  final Set<int> _selectionPreviewIndexes = <int>{};
  final Map<String, String> _translationOverrides = <String, String>{};
  final GlobalKey _selectionAreaKey = GlobalKey();
  final Map<int, GlobalKey> _chipKeys = <int, GlobalKey>{};
  final FocusNode _selectionFocusNode = FocusNode(
    debugLabel: 'prompt-tag-selection',
  );
  Offset? _selectionStart;
  Offset? _selectionCurrent;
  bool _selectionMoved = false;
  bool _selectionAdditive = false;
  late PromptTagLayoutMode _layoutMode = _normalizedLayoutMode(
    widget.initialLayoutMode,
  );
  PromptTagSelectionController? _registeredSelectionController;
  String? _registeredSelectionFieldId;
  String? _analysisCacheText;
  List<WorkshopTagAnalysis>? _analysisCache;
  List<String>? _tagTextCache;

  @override
  void initState() {
    super.initState();
    AppDisplaySettings.promptTranslationShortcutSerial.addListener(
      _handleShortcutTrigger,
    );
    _syncSelectionController();
  }

  @override
  void didUpdateWidget(covariant PromptTagDisplay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectionController != widget.selectionController ||
        oldWidget.selectionFieldId != widget.selectionFieldId ||
        oldWidget.selectionGroupId != widget.selectionGroupId) {
      _syncSelectionController();
    }
    if (oldWidget.initialLayoutMode != widget.initialLayoutMode) {
      _layoutMode = _normalizedLayoutMode(widget.initialLayoutMode);
    }
    if (oldWidget.text != widget.text) {
      _clearParsedTagCache();
      _chipKeys.clear();
      _shortcutTranslated = false;
      _autoTranslationPending.clear();
      _hoveredIndex = null;
      _selectedIndexes.clear();
      _selectionPreviewIndexes.clear();
      _selectionStart = null;
      _selectionCurrent = null;
      _selectionMoved = false;
      _translationOverrides.clear();
    }
  }

  @override
  void dispose() {
    AppDisplaySettings.clearHoveredPromptTarget(_hoverId);
    AppDisplaySettings.promptTranslationShortcutSerial.removeListener(
      _handleShortcutTrigger,
    );
    _unregisterSelectionController();
    _selectionFocusNode.dispose();
    super.dispose();
  }

  void _syncSelectionController() {
    _unregisterSelectionController();
    final controller = widget.selectionController;
    if (controller == null) {
      return;
    }
    final fieldId = _sharedSelectionFieldId;
    _registeredSelectionController = controller;
    _registeredSelectionFieldId = fieldId;
    controller
      ..addListener(_handleSharedSelectionChanged)
      ..registerField(
        PromptTagSelectionField(
          fieldId: fieldId,
          selectionGroupId: widget.selectionGroupId,
          snapshots: _selectionSnapshots,
          removeIndexes: _removeIndexes,
        ),
      );
  }

  void _unregisterSelectionController() {
    final controller = _registeredSelectionController;
    final fieldId = _registeredSelectionFieldId;
    if (controller != null && fieldId != null) {
      controller
        ..removeListener(_handleSharedSelectionChanged)
        ..unregisterField(fieldId);
    }
    _registeredSelectionController = null;
    _registeredSelectionFieldId = null;
  }

  void _handleSharedSelectionChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final trimmed = widget.text.trim();
    final body = trimmed.isEmpty
        ? _EmptyPromptText(text: widget.emptyText)
        : _buildTags(context, trimmed);

    if (!widget.enableHoverShortcut) {
      return body;
    }

    return MouseRegion(
      cursor: SystemMouseCursors.basic,
      onEnter: (_) => AppDisplaySettings.registerHoveredPromptTarget(_hoverId),
      onExit: (_) => AppDisplaySettings.clearHoveredPromptTarget(_hoverId),
      child: body,
    );
  }

  Widget _buildTags(BuildContext context, String text) {
    final translate = widget.defaultTranslated || _shortcutTranslated;
    final analyses = _analysesFor(text);
    final shown = widget.maxTags == null
        ? analyses
        : analyses.take(widget.maxTags!).toList(growable: false);
    final overflow =
        widget.maxTags == null ? 0 : analyses.length - shown.length;
    final cache = _translationCache();
    final classificationCache = _classificationCache();
    final items = [
      for (final (index, tag) in shown.indexed)
        _PromptTagItem(
          index: index,
          rawText: promptTagRawValueForAnalysis(tag),
          text: tag.displayText,
          weightLabel: tag.weightLabel,
          weight: tag.weight,
          classification: classifyPromptTagForPresentation(
            tag.displayText,
            negative: widget.negative,
            cache: classificationCache,
            overrides: widget.classificationOverrides,
            cacheRuleClassification: true,
          ),
          warning: tag.warning != WorkshopTagWarning.none,
        ),
    ];

    if (translate) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _enqueueAutoTranslations(shown.map((tag) => tag.displayText));
      });
    }

    final canOpenTagMenu =
        widget.enableTagActions || _filterRuleAdder() != null;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.showLayoutControls) ...[
          _PromptTagDisplayLayoutControls(
            dense: widget.dense,
            layoutMode: _effectiveLayoutMode,
            onChanged: (mode) {
              setState(() {
                _layoutMode = _normalizedLayoutMode(mode);
              });
            },
          ),
          const SizedBox(height: 8),
        ],
        _buildTagLayout(
          context,
          items,
          cache,
          translate,
          canOpenTagMenu: canOpenTagMenu,
        ),
        if (overflow > 0)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: PromptTagChip(
              label: '+$overflow',
              translation: '',
              category: PromptTagCategory.other,
              dense: widget.dense,
              selected: false,
              enabled: false,
              bodyKey: ValueKey(
                'prompt-tag-chip-+$overflow-${shown.length}-idle',
              ),
            ),
          ),
      ],
    );

    if (!widget.enableTagActions) {
      return content;
    }

    return _buildSelectionArea(content);
  }

  PromptTagLayoutMode get _effectiveLayoutMode {
    if (widget.showLayoutControls || widget.respectInitialLayoutMode) {
      return _normalizedLayoutMode(
        widget.showLayoutControls ? _layoutMode : widget.initialLayoutMode,
      );
    }
    return PromptTagLayoutMode.grouped;
  }

  PromptTagLayoutMode _normalizedLayoutMode(PromptTagLayoutMode mode) {
    return mode == PromptTagLayoutMode.layered
        ? PromptTagLayoutMode.grouped
        : mode;
  }

  Widget _buildSelectionArea(Widget content) {
    final rect = _selectionRect();
    return Focus(
      key: const ValueKey('prompt-tag-selection-area'),
      focusNode: _selectionFocusNode,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          _clearSelection();
          return KeyEventResult.handled;
        }
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.delete ||
                event.logicalKey == LogicalKeyboardKey.backspace) &&
            widget.onChanged != null &&
            _selectedCount > 0) {
          _deleteSelectedTags();
          return KeyEventResult.handled;
        }
        if (event is KeyDownEvent &&
            (HardwareKeyboard.instance.isControlPressed ||
                HardwareKeyboard.instance.isMetaPressed) &&
            event.logicalKey == LogicalKeyboardKey.keyC &&
            (_selectedCount > 0 || _hoveredTag() != null)) {
          unawaited(_copySelectedFromKeyboard(context));
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Listener(
            key: _selectionAreaKey,
            behavior: HitTestBehavior.translucent,
            onPointerDown: _handleSelectionPointerDown,
            onPointerMove: _handleSelectionPointerMove,
            onPointerUp: _handleSelectionPointerUp,
            onPointerCancel: _handleSelectionPointerCancel,
            child: MouseRegion(
              cursor: _selectionStart == null
                  ? SystemMouseCursors.basic
                  : SystemMouseCursors.precise,
              child: _selectionDropTarget(content),
            ),
          ),
          if (rect != null && _selectionMoved)
            Positioned(
              left: rect.left,
              top: rect.top,
              width: rect.width,
              height: rect.height,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: StudioTokens.primary.withAlpha(28),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(6),
                      topRight: Radius.circular(6),
                      bottomLeft: Radius.circular(6),
                      bottomRight: Radius.circular(2),
                    ),
                    border: Border.all(color: StudioTokens.primary),
                    boxShadow: const [
                      BoxShadow(color: Color(0x33FFE500), blurRadius: 12),
                    ],
                  ),
                ),
              ),
            ),
          if (widget.showSelectionToolbar && _selectedCount > 0)
            Positioned(
              top: 0,
              right: widget.dense ? 6 : 8,
              child: PromptTagSelectionToolbar(
                count: _selectedCount,
                onClear: _clearSelection,
                toolbarKey: const ValueKey('prompt-tag-selection-toolbar'),
                clearButtonKey: const ValueKey('prompt-tag-clear-selection'),
                alignRight: true,
              ),
            ),
        ],
      ),
    );
  }

  Widget _selectionDropTarget(Widget content) {
    return DragTarget<PromptTagDragData>(
      key: const ValueKey('prompt-tag-drop-area'),
      hitTestBehavior: HitTestBehavior.translucent,
      onWillAcceptWithDetails: _canAcceptDraggedTags,
      onAcceptWithDetails: (details) => _acceptDraggedTags(details.data),
      builder: (context, candidates, rejected) {
        final active = candidates.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: double.infinity,
          constraints: BoxConstraints(minHeight: widget.dense ? 40 : 48),
          padding: EdgeInsets.symmetric(vertical: widget.dense ? 3 : 5),
          decoration: BoxDecoration(
            color: active
                ? StudioTokens.primary.withAlpha(12)
                : Colors.transparent,
            borderRadius: StudioTokens.radiusSlot,
          ),
          child: content,
        );
      },
    );
  }

  void _handleSelectionPointerDown(PointerDownEvent event) {
    if (event.buttons != kPrimaryMouseButton) {
      return;
    }
    final local = _selectionLocalPosition(event.position);
    if (local == null) {
      return;
    }
    final pressedIndex = _indexAt(local);
    if (_canDragTags && pressedIndex != null && _isSelected(pressedIndex)) {
      return;
    }
    _selectionFocusNode.requestFocus();
    setState(() {
      _selectionStart = local;
      _selectionCurrent = local;
      _selectionMoved = false;
      _selectionAdditive = HardwareKeyboard.instance.isControlPressed ||
          HardwareKeyboard.instance.isMetaPressed;
      _selectionPreviewIndexes.clear();
    });
  }

  void _handleSelectionPointerMove(PointerMoveEvent event) {
    final start = _selectionStart;
    if (start == null) {
      return;
    }
    final local = _selectionLocalPosition(event.position);
    if (local == null) {
      return;
    }
    final moved = (local - start).distance > 4;
    final preview =
        moved ? _indexesIntersecting(_rectFrom(start, local)) : <int>{};
    setState(() {
      _selectionCurrent = local;
      _selectionMoved = moved;
      _selectionPreviewIndexes
        ..clear()
        ..addAll(preview);
    });
  }

  void _handleSelectionPointerUp(PointerUpEvent event) {
    final start = _selectionStart;
    final current = _selectionCurrent;
    if (start == null || current == null) {
      return;
    }
    final rect = _rectFrom(start, current);
    final tappedIndex = _indexAt(_selectionLocalPosition(event.position));
    setState(() {
      if (_selectionMoved) {
        final hits = _indexesIntersecting(rect);
        final controller = widget.selectionController;
        if (controller != null) {
          controller.setFieldSelection(
            _sharedSelectionFieldId,
            hits,
            additive: _selectionAdditive,
          );
        } else {
          if (!_selectionAdditive) {
            _selectedIndexes.clear();
          }
          _selectedIndexes.addAll(hits);
        }
      } else if (tappedIndex != null) {
        final controller = widget.selectionController;
        if (controller != null) {
          controller.toggle(
            _sharedSelectionFieldId,
            tappedIndex,
            additive: _selectionAdditive,
          );
        } else if (_selectedIndexes.contains(tappedIndex)) {
          if (_selectionAdditive || _selectedIndexes.length == 1) {
            _selectedIndexes.remove(tappedIndex);
          } else {
            _selectedIndexes
              ..clear()
              ..add(tappedIndex);
          }
        } else {
          if (!_selectionAdditive) {
            _selectedIndexes.clear();
          }
          _selectedIndexes.add(tappedIndex);
        }
      }
      _selectionPreviewIndexes.clear();
      _selectionStart = null;
      _selectionCurrent = null;
      _selectionMoved = false;
      _selectionAdditive = false;
    });
  }

  void _handleSelectionPointerCancel(PointerCancelEvent event) {
    setState(() {
      _selectionPreviewIndexes.clear();
      _selectionStart = null;
      _selectionCurrent = null;
      _selectionMoved = false;
      _selectionAdditive = false;
    });
  }

  Offset? _selectionLocalPosition(Offset globalPosition) {
    final box = _selectionAreaKey.currentContext?.findRenderObject();
    if (box is! RenderBox) {
      return null;
    }
    final local = box.globalToLocal(globalPosition);
    return Offset(
      local.dx.clamp(0.0, box.size.width),
      local.dy.clamp(0.0, box.size.height),
    );
  }

  Rect? _selectionRect() {
    final start = _selectionStart;
    final current = _selectionCurrent;
    if (start == null || current == null) {
      return null;
    }
    return _rectFrom(start, current);
  }

  Rect _rectFrom(Offset start, Offset current) {
    return Rect.fromLTRB(
      start.dx < current.dx ? start.dx : current.dx,
      start.dy < current.dy ? start.dy : current.dy,
      start.dx > current.dx ? start.dx : current.dx,
      start.dy > current.dy ? start.dy : current.dy,
    );
  }

  Set<int> _indexesIntersecting(Rect selectionRect) {
    final result = <int>{};
    for (final entry in _chipKeys.entries) {
      final rect = _chipRect(entry.value);
      if (rect != null && selectionRect.overlaps(rect)) {
        result.add(entry.key);
      }
    }
    return result;
  }

  int? _indexAt(Offset? localPosition) {
    if (localPosition == null) {
      return null;
    }
    for (final entry in _chipKeys.entries) {
      final rect = _chipRect(entry.value);
      if (rect != null && rect.contains(localPosition)) {
        return entry.key;
      }
    }
    return null;
  }

  Rect? _chipRect(GlobalKey key) {
    final areaBox = _selectionAreaKey.currentContext?.findRenderObject();
    final chipBox = key.currentContext?.findRenderObject();
    if (areaBox is! RenderBox || chipBox is! RenderBox || !chipBox.hasSize) {
      return null;
    }
    final topLeft = areaBox.globalToLocal(chipBox.localToGlobal(Offset.zero));
    return (topLeft & chipBox.size).inflate(widget.dense ? 2 : 3);
  }

  Rect? _chipGlobalRect(GlobalKey key) {
    final chipBox = key.currentContext?.findRenderObject();
    if (chipBox is! RenderBox || !chipBox.hasSize) {
      return null;
    }
    final topLeft = chipBox.localToGlobal(Offset.zero);
    return (topLeft & chipBox.size).inflate(widget.dense ? 2 : 3);
  }

  List<PromptTagSelectionItem> _selectionSnapshots() {
    final tags = _tags;
    final result = <PromptTagSelectionItem>[];
    for (final entry in _chipKeys.entries) {
      if (entry.key < 0 || entry.key >= tags.length) {
        continue;
      }
      final rect = _chipGlobalRect(entry.value);
      if (rect == null) {
        continue;
      }
      result.add(
        PromptTagSelectionItem(
          fieldId: _sharedSelectionFieldId,
          index: entry.key,
          tag: tags[entry.key],
          globalRect: rect,
        ),
      );
    }
    return result;
  }

  GlobalKey _chipKeyFor(int index) {
    return _chipKeys.putIfAbsent(index, GlobalKey.new);
  }

  void _clearSelection() {
    final controller = widget.selectionController;
    if (controller != null) {
      if (!controller.hasSelection && _selectionPreviewIndexes.isEmpty) {
        return;
      }
      controller.clear();
      setState(_clearSelectionStateOnly);
      return;
    }
    if (_selectedIndexes.isEmpty && _selectionPreviewIndexes.isEmpty) {
      return;
    }
    setState(_clearSelectionStateOnly);
  }

  void _clearSelectionStateOnly() {
    _selectedIndexes.clear();
    _clearSelectionInteractionStateOnly();
  }

  void _clearSelectionInteractionStateOnly() {
    _selectionPreviewIndexes.clear();
    _selectionStart = null;
    _selectionCurrent = null;
    _selectionMoved = false;
    _selectionAdditive = false;
  }

  void _deleteSelectedTags() {
    final controller = widget.selectionController;
    if (controller != null) {
      final selected = controller.selectedIndexesFor(_sharedSelectionFieldId);
      if (selected.isEmpty) {
        return;
      }
      controller.clear();
      _removeIndexes(selected);
      return;
    }
    final nextText = _textWithoutSelectedTags();
    widget.onChanged?.call(nextText);
    if (!mounted) {
      return;
    }
    setState(_clearSelectionStateOnly);
  }

  String _textWithoutSelectedTags() {
    final analyses = _analysesFor(widget.text);
    final selected = _activeSelectedIndexes;
    return [
      for (final (index, tag) in analyses.indexed)
        if (!selected.contains(index)) tag.text.trim(),
    ].where((tag) => tag.isNotEmpty).join(', ');
  }

  List<String> get _tags {
    final cached = _tagTextCache;
    if (cached != null) {
      return cached;
    }
    return _tagTextCache = _analysesFor(widget.text)
        .map((tag) => PromptTagProcessor.cleanTagDisplay(tag.text))
        .where((tag) => tag.trim().isNotEmpty)
        .toList(growable: false);
  }

  List<WorkshopTagAnalysis> _analysesFor(String text) {
    final normalizedText = text.trim();
    final cached = _analysisCache;
    if (_analysisCacheText == normalizedText && cached != null) {
      return cached;
    }
    final analyses = PromptTagProcessor.analyzeWorkshopTags(normalizedText);
    _analysisCacheText = normalizedText;
    _analysisCache = analyses;
    _tagTextCache = null;
    return analyses;
  }

  void _clearParsedTagCache() {
    _analysisCacheText = null;
    _analysisCache = null;
    _tagTextCache = null;
  }

  bool get _canDragTags => widget.enableTagActions;

  String get _sharedSelectionFieldId =>
      widget.selectionFieldId ?? _dragOriginId;

  Set<int> get _activeSelectedIndexes {
    return widget.selectionController?.selectedIndexesFor(
          _sharedSelectionFieldId,
        ) ??
        _selectedIndexes;
  }

  int get _selectedCount {
    return widget.selectionController?.selectedCountFor(
          _sharedSelectionFieldId,
        ) ??
        _selectedIndexes.length;
  }

  bool _isSelected(int index) {
    return widget.selectionController?.isSelected(
          _sharedSelectionFieldId,
          index,
        ) ??
        _selectedIndexes.contains(index);
  }

  bool _isPreviewed(int index) {
    return widget.selectionController?.isPreviewed(
          _sharedSelectionFieldId,
          index,
        ) ??
        false;
  }

  bool _canAcceptDraggedTags(DragTargetDetails<PromptTagDragData> details) {
    return _canAcceptDraggedTagsFor(details);
  }

  bool _canAcceptDraggedTagsFor(
    DragTargetDetails<PromptTagDragData> details, {
    PromptTagCategory? dropCategory,
  }) {
    return widget.enableTagActions &&
        details.data.tags.any((tag) => tag.trim().isNotEmpty) &&
        (widget.onChanged != null || dropCategory != null);
  }

  PromptTagDragData _dragDataForSelection() {
    final indexes = _activeSelectedIndexes.toSet();
    return _dragDataForIndexes(indexes);
  }

  PromptTagDragData _dragDataForIndex(int index) {
    final activeSelected = _activeSelectedIndexes;
    final indexes =
        activeSelected.contains(index) ? activeSelected.toSet() : <int>{index};
    return _dragDataForIndexes(
      indexes,
      includeSharedSelection: activeSelected.contains(index),
    );
  }

  PromptTagDragData _dragDataForIndexes(
    Set<int> indexes, {
    bool includeSharedSelection = true,
  }) {
    final tags = promptTagsForIndexes(_tags, indexes);
    final controller = widget.selectionController;
    if (controller != null && includeSharedSelection) {
      return controller.dragDataFor(
        fieldId: _sharedSelectionFieldId,
        localOriginId: _dragOriginId,
        localIndexes: indexes,
        localTags: tags,
        localRemove: _removeDraggedIndexes,
      );
    }
    return PromptTagDragData(
      originId: _dragOriginId,
      sourceFieldIds: {_sharedSelectionFieldId},
      indexes: indexes,
      tags: tags,
      removeFromSource: _removeDraggedIndexes,
    );
  }

  void _beginDraggingIndexes(Set<int> indexes) {
    final validIndexes =
        indexes.where((index) => index >= 0 && index < _tags.length).toSet();
    if (validIndexes.isEmpty) {
      return;
    }
    _selectionFocusNode.requestFocus();
    final controller = widget.selectionController;
    if (controller != null) {
      controller.setFieldSelection(_sharedSelectionFieldId, validIndexes);
      setState(_clearSelectionInteractionStateOnly);
      return;
    }
    setState(() {
      _selectedIndexes
        ..clear()
        ..addAll(validIndexes);
      _clearSelectionInteractionStateOnly();
    });
  }

  void _acceptDraggedTags(
    PromptTagDragData data, {
    int? insertIndex,
    PromptTagCategory? dropCategory,
  }) {
    if (!widget.enableTagActions ||
        data.tags.every((tag) => tag.trim().isEmpty)) {
      return;
    }
    final categoryChanged = _applyDroppedCategory(data.tags, dropCategory);
    if (data.originId == _dragOriginId) {
      if (dropCategory != null && insertIndex == null) {
        if (categoryChanged && mounted) {
          setState(_clearSelectionStateOnly);
        }
        return;
      }
      if (widget.onChanged == null) {
        if (categoryChanged && mounted) {
          setState(_clearSelectionStateOnly);
        }
        return;
      }
      _moveDraggedIndexes(data.indexes, insertIndex);
      return;
    }
    if (widget.onChanged == null) {
      if (categoryChanged && mounted) {
        setState(_clearSelectionStateOnly);
      }
      return;
    }
    final current = _tags;
    final incoming = data.tags
        .map(PromptTagProcessor.cleanTagDisplay)
        .where((tag) => tag.trim().isNotEmpty)
        .toList(growable: false);
    if (incoming.isEmpty) {
      return;
    }
    final target = clampPromptTagInsertIndex(
      insertIndex ?? current.length,
      current,
    );
    final next = [...current]..insertAll(target, incoming);
    final value = joinPromptTags(next);
    widget.onChanged?.call(value);
    if (!mounted) {
      return;
    }
    setState(_clearSelectionStateOnly);
    data.removeFromSource?.call(data.indexes);
  }

  bool _applyDroppedCategory(
    Iterable<String> tags,
    PromptTagCategory? category,
  ) {
    if (category == null) {
      return false;
    }
    final cache = _classificationCache();
    var changed = false;
    for (final tag in tags) {
      final cleaned = PromptTagProcessor.cleanTagDisplay(tag).trim();
      if (cleaned.isEmpty) {
        continue;
      }
      final current = cache.entryFor(cleaned, negative: widget.negative);
      if (current?.category == category &&
          current?.source.startsWith('manual') == true) {
        continue;
      }
      cache.setCategory(
        cleaned,
        category,
        source: 'manual-drag',
        negative: widget.negative,
      );
      changed = true;
    }
    if (!changed) {
      return false;
    }
    widget.onClassificationChanged?.call();
    unawaited(_saveClassificationCacheBestEffort(cache));
    return true;
  }

  void _moveDraggedIndexes(Set<int> indexes, int? insertIndex) {
    final current = _tags;
    final selected = indexes
        .where((index) => index >= 0 && index < current.length)
        .toList()
      ..sort();
    if (selected.isEmpty) {
      return;
    }
    var target = clampPromptTagInsertIndex(
      insertIndex ?? current.length,
      current,
    );
    final moving = [for (final index in selected) current[index]];
    final remaining = [
      for (final (index, tag) in current.indexed)
        if (!selected.contains(index)) tag,
    ];
    target -= selected.where((index) => index < target).length;
    target = clampPromptTagInsertIndex(target, remaining);
    final next = [...remaining]..insertAll(target, moving);
    widget.onChanged?.call(joinPromptTags(next));
    if (!mounted) {
      return;
    }
    setState(_clearSelectionStateOnly);
  }

  void _removeDraggedIndexes(Set<int> indexes) {
    if (!mounted || indexes.isEmpty) {
      return;
    }
    _removeIndexes(indexes);
  }

  void _removeIndexes(Set<int> indexes) {
    final next = [
      for (final (index, tag) in _tags.indexed)
        if (!indexes.contains(index)) tag,
    ];
    widget.onChanged?.call(joinPromptTags(next));
    if (!mounted) {
      return;
    }
    setState(_clearSelectionStateOnly);
  }

  Widget _buildTagLayout(
    BuildContext context,
    List<_PromptTagItem> items,
    TranslationCache cache,
    bool translate, {
    required bool canOpenTagMenu,
  }) {
    if (_effectiveLayoutMode == PromptTagLayoutMode.sourceOrder) {
      return Wrap(
        spacing: widget.dense ? 4 : 7,
        runSpacing: widget.dense ? 4 : 7,
        children: _chipsForItems(
          context,
          items,
          cache,
          translate,
          canOpenTagMenu: canOpenTagMenu,
        ),
      );
    }

    final visibleGroups = [
      for (final group in PromptTagClassifier.groups)
        if (items.any((item) => item.classification.group.id == group.id))
          group,
    ];
    if (visibleGroups.length <= 1 && widget.groupActionBuilder == null) {
      return Wrap(
        spacing: widget.dense ? 4 : 7,
        runSpacing: widget.dense ? 4 : 7,
        children: _chipsForItems(
          context,
          items,
          cache,
          translate,
          canOpenTagMenu: canOpenTagMenu,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final group in visibleGroups)
          _groupDropTarget(
            key: ValueKey('prompt-tag-group-${group.id}'),
            dropCategory: _dropCategoryForGroup(group),
            builder: (active) {
              final groupItems = items
                  .where((item) => item.classification.group.id == group.id)
                  .toList(growable: false);
              return _PromptTagGroupBlock(
                label: group.label,
                action: widget.groupActionBuilder?.call(
                  context,
                  PromptTagGroupActionContext(
                    group: group,
                    tags: [
                      for (final item in groupItems)
                        PromptTagGroupActionTag(
                          promptText: item.rawText,
                          displayText: item.text,
                          weightLabel: item.weightLabel,
                          weight: item.weight,
                          classification: item.classification,
                        ),
                    ],
                  ),
                ),
                activeDrop: active,
                children: _chipsForItems(
                  context,
                  groupItems,
                  cache,
                  translate,
                  canOpenTagMenu: canOpenTagMenu,
                  dropCategory: _dropCategoryForGroup(group),
                ),
              );
            },
          ),
      ],
    );
  }

  List<Widget> _chipsForItems(
    BuildContext context,
    List<_PromptTagItem> items,
    TranslationCache cache,
    bool translate, {
    required bool canOpenTagMenu,
    PromptTagCategory? dropCategory,
  }) {
    return [
      for (final item in items)
        DragTarget<PromptTagDragData>(
          key: _chipKeyFor(item.index),
          hitTestBehavior: HitTestBehavior.translucent,
          onWillAcceptWithDetails: (details) =>
              _canAcceptDraggedTagsFor(details, dropCategory: dropCategory),
          onAcceptWithDetails: (details) => _acceptDraggedTags(
            details.data,
            insertIndex: item.index,
            dropCategory: dropCategory,
          ),
          builder: (context, candidates, rejected) {
            final selected = _isSelected(item.index);
            final diffState = widget.diffStateForTag?.call(item.text) ??
                PromptTagChipDiffState.unchanged;
            final chip = PromptTagChip(
              label: item.text,
              weightLabel: item.weightLabel,
              weight: item.weight,
              translation: translate
                  ? _translationFor(cache, item.text)
                  : _translationOverrides[item.text] ?? '',
              loading: _autoTranslationPending.contains(item.text),
              warning: item.warning,
              diffState: diffState,
              category: item.classification.category,
              dense: widget.dense,
              hovered: _hoveredIndex == item.index,
              previewed: _selectionPreviewIndexes.contains(item.index) ||
                  _isPreviewed(item.index) ||
                  candidates.isNotEmpty,
              selected: selected,
              bodyKey: ValueKey(
                'prompt-tag-chip-${item.text}-${item.index}-'
                '${selected ? 'selected' : 'idle'}',
              ),
              markerKey: ValueKey(
                'prompt-tag-chip-marker-${item.text}-${item.index}',
              ),
              weightKey: ValueKey(
                'prompt-tag-chip-weight-${item.text}-${item.index}',
              ),
              deleteKey: ValueKey(
                'prompt-tag-chip-delete-${item.text}-${item.index}',
              ),
              checkKey: ValueKey(
                'prompt-tag-chip-check-${item.text}-${item.index}',
              ),
              diffKey: diffState == PromptTagChipDiffState.unchanged
                  ? null
                  : ValueKey(
                      'prompt-tag-chip-diff-${diffState.name}-'
                      '${item.text}-${item.index}',
                    ),
              onDeleted: widget.onChanged == null
                  ? null
                  : () => _removeIndexes({item.index}),
              onHoverChanged: canOpenTagMenu
                  ? (hovered) {
                      if (_hoveredIndex == item.index && !hovered) {
                        setState(() {
                          _hoveredIndex = null;
                        });
                      } else if (hovered && _hoveredIndex != item.index) {
                        setState(() {
                          _hoveredIndex = item.index;
                        });
                      }
                    }
                  : null,
              onSecondaryTapDown: canOpenTagMenu
                  ? (details) => _showTagMenu(
                        context,
                        details.globalPosition,
                        item.index,
                        item.text,
                      )
                  : null,
              onTap: widget.onTagTap == null
                  ? null
                  : () => widget.onTagTap?.call(item.text),
            );
            if (!_canDragTags) {
              return chip;
            }
            final dragData = selected
                ? _dragDataForSelection()
                : _dragDataForIndex(
                    item.index,
                  );
            return Draggable<PromptTagDragData>(
              data: dragData,
              dragAnchorStrategy: pointerDragAnchorStrategy,
              feedback: PromptTagDragFeedback(
                tags: dragData.tags,
                dense: widget.dense,
              ),
              onDragStarted: selected
                  ? null
                  : () => _beginDraggingIndexes(dragData.indexes),
              childWhenDragging: Opacity(opacity: 0.45, child: chip),
              child: chip,
            );
          },
        ),
    ];
  }

  Widget _groupDropTarget({
    required Key key,
    required PromptTagCategory? dropCategory,
    required Widget Function(bool active) builder,
  }) {
    return DragTarget<PromptTagDragData>(
      key: key,
      hitTestBehavior: HitTestBehavior.translucent,
      onWillAcceptWithDetails: (details) =>
          _canAcceptDraggedTagsFor(details, dropCategory: dropCategory),
      onAcceptWithDetails: (details) =>
          _acceptDraggedTags(details.data, dropCategory: dropCategory),
      builder: (context, candidates, rejected) {
        return builder(candidates.isNotEmpty);
      },
    );
  }

  PromptTagCategory? _dropCategoryForGroup(PromptTagGroup group) {
    final allowed = _manualCategoryChoices(
      widget.negative,
    ).where(group.categories.contains).toList(growable: false);
    if (allowed.isEmpty) {
      return null;
    }
    final preferred = widget.negative
        ? const [
            PromptTagCategory.negativeQuality,
            PromptTagCategory.negativeArtist,
            PromptTagCategory.negativeBody,
            PromptTagCategory.negativeContent,
            PromptTagCategory.other,
          ]
        : const [
            PromptTagCategory.quality,
            PromptTagCategory.artist,
            PromptTagCategory.character,
            PromptTagCategory.clothing,
            PromptTagCategory.action,
            PromptTagCategory.scene,
            PromptTagCategory.style,
            PromptTagCategory.other,
            PromptTagCategory.camera,
            PromptTagCategory.upperBody,
            PromptTagCategory.lowerBody,
            PromptTagCategory.upperClothing,
            PromptTagCategory.lowerClothing,
          ];
    for (final category in preferred) {
      if (allowed.contains(category)) {
        return category;
      }
    }
    return allowed.first;
  }

  TranslationCache _translationCache() {
    if (widget.translationCache != null) {
      return widget.translationCache!;
    }
    if (GetIt.I.isRegistered<TranslationCache>()) {
      return GetIt.I<TranslationCache>();
    }
    return TranslationCache();
  }

  PromptTagClassificationCache _classificationCache() {
    if (widget.classificationCache != null) {
      return widget.classificationCache!;
    }
    if (GetIt.I.isRegistered<PromptTagClassificationCache>()) {
      return GetIt.I<PromptTagClassificationCache>();
    }
    return PromptTagClassificationCache();
  }

  PromptTranslationService? _promptTranslationService() {
    if (GetIt.I.isRegistered<PromptTranslationService>()) {
      return GetIt.I<PromptTranslationService>();
    }
    if (GetIt.I.isRegistered<PayloadConfig>()) {
      return DefaultPromptTranslationService(
        translationCache: _translationCache(),
        settingsProvider: () => GetIt.I<PayloadConfig>().settings,
        translationCacheReloader: PromptWorkshopBridge.loadTranslationCache,
      );
    }
    return null;
  }

  void _handleShortcutTrigger() {
    if (!widget.enableHoverShortcut ||
        !AppDisplaySettings.isHoveredPromptTarget(_hoverId)) {
      return;
    }
    setState(() {
      _shortcutTranslated = true;
    });
  }

  String _translationFor(TranslationCache cache, String tag) {
    return promptTagPresentationTranslation(
      tag,
      cache: cache,
      overrides: _translationOverrides,
    );
  }

  void _enqueueAutoTranslations(Iterable<String> tags) {
    final service = _promptTranslationService();
    if (service == null) {
      return;
    }
    final cache = _translationCache();
    var added = false;
    for (final tag in tags) {
      if (tag.trim().isEmpty) {
        continue;
      }
      if (_translationFor(cache, tag).trim().isNotEmpty) {
        continue;
      }
      if (_autoTranslationPending.contains(tag)) {
        continue;
      }
      _autoTranslationPending.add(tag);
      PromptTagAutoTranslationQueue.instance
          .request(
            tag: tag,
            sourceLanguage: 'en',
            targetLanguage: 'zh',
            cache: cache,
            service: service,
            saveTranslationCache: _saveTranslationCache,
          )
          .then((result) => _applyAutoTranslationResult(tag, result));
      added = true;
    }
    if (added && mounted) {
      setState(() {});
    }
  }

  void _applyAutoTranslationResult(
    String tag,
    OnlineTranslationResult result,
  ) {
    _autoTranslationPending.remove(tag);
    if (!mounted) {
      return;
    }
    final translated = result.text.trim();
    if (translated.isNotEmpty) {
      _translationOverrides[tag] = translated;
    }
    setState(() {});
  }

  List<PromptTagFilterRuleTarget> _enabledFilterRuleTargets() {
    final seen = <PromptTagFilterRuleTarget>{};
    return [
      for (final target in widget.filterRuleTargets)
        if (seen.add(target)) target,
    ];
  }

  Future<void> _copySelectedFromKeyboard(BuildContext context) async {
    final tags = _copySourceTags(_hoveredTag() ?? '');
    if (tags.isEmpty || tags.every((tag) => tag.trim().isEmpty)) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: tags.join(', ')));
    if (context.mounted) {
      _showSnack(context, tags.length > 1 ? '已复制选中标签' : '已复制标签');
    }
  }

  String? _hoveredTag() {
    final hoveredIndex = _hoveredIndex;
    if (hoveredIndex == null) return null;
    final analyses = _analysesFor(widget.text);
    if (hoveredIndex < 0 || hoveredIndex >= analyses.length) return null;
    return analyses[hoveredIndex].text;
  }

  Future<void> _showTagMenu(
    BuildContext context,
    Offset position,
    int index,
    String tag,
  ) async {
    if (index < 0 || index >= _tags.length) {
      return;
    }
    _selectionFocusNode.requestFocus();
    if (!_isSelected(index)) {
      final controller = widget.selectionController;
      if (controller != null) {
        controller.setFieldSelection(_sharedSelectionFieldId, {index});
      } else {
        setState(() {
          _selectedIndexes
            ..clear()
            ..add(index);
        });
      }
    }
    final addToFilterRules = _filterRuleAdder();
    final choice = await showMenu<_PromptTagMenuChoice>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        const PopupMenuItem(
          value: _PromptTagMenuChoice(_PromptTagMenuAction.openDanbooru),
          child: Text('打开 Danbooru Wiki'),
        ),
        PopupMenuItem(
          value: const _PromptTagMenuChoice(_PromptTagMenuAction.aiRetranslate),
          child: Text(_retranslateMenuLabel()),
        ),
        const PopupMenuItem(
          value: _PromptTagMenuChoice(_PromptTagMenuAction.manualEdit),
          child: Text('手动编辑'),
        ),
        if (widget.onChanged != null)
          const PopupMenuItem(
            key: ValueKey('prompt-tag-edit-weight'),
            value: _PromptTagMenuChoice(_PromptTagMenuAction.editWeight),
            child: Text('编辑权重'),
          ),
        const PopupMenuItem(
          key: ValueKey('prompt-tag-change-category'),
          value: _PromptTagMenuChoice(_PromptTagMenuAction.changeCategory),
          child: Text('改分类...'),
        ),
        const PopupMenuItem(
          key: ValueKey('prompt-tag-clear-category'),
          value: _PromptTagMenuChoice(_PromptTagMenuAction.clearCategory),
          child: Text('恢复自动分类'),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: _PromptTagMenuChoice(_PromptTagMenuAction.copy),
          child: Text('复制标签'),
        ),
        if (addToFilterRules != null)
          const PopupMenuItem(
            key: ValueKey('prompt-tag-add-to-filter-rules'),
            value: _PromptTagMenuChoice(_PromptTagMenuAction.addToFilterRules),
            child: Text('加入屏蔽库'),
          ),
      ],
    );
    if (!mounted || !context.mounted || choice == null) {
      return;
    }

    switch (choice.action) {
      case _PromptTagMenuAction.openDanbooru:
        await _openDanbooruWiki(context, tag);
      case _PromptTagMenuAction.aiRetranslate:
        await _aiRetranslateTag(context, tag);
      case _PromptTagMenuAction.manualEdit:
        await _editTranslation(context, tag);
      case _PromptTagMenuAction.editWeight:
        await _editWeight(context, index);
      case _PromptTagMenuAction.changeCategory:
        final category = await _pickTagCategory(context);
        if (category == null) {
          return;
        }
        if (!mounted || !context.mounted) {
          return;
        }
        await _setTagCategory(context, tag, category);
      case _PromptTagMenuAction.clearCategory:
        await _clearTagCategory(context, tag);
      case _PromptTagMenuAction.copy:
        await _copyTags(context, fallbackTag: tag);
      case _PromptTagMenuAction.addToFilterRules:
        final adder = addToFilterRules;
        if (adder == null) {
          return;
        }
        await _addTagsToFilterRules(
          context,
          fallbackTag: tag,
          addToFilterRules: adder,
        );
    }
  }

  Future<void> _setTagCategory(
    BuildContext context,
    String tag,
    PromptTagCategory category,
  ) async {
    final cache = _classificationCache();
    cache.setCategory(
      tag,
      category,
      source: 'manual',
      negative: widget.negative,
    );
    widget.onClassificationChanged?.call();
    unawaited(_saveClassificationCacheBestEffort(cache));
    if (!mounted) {
      return;
    }
    setState(() {});
    if (context.mounted) {
      _showSnack(context, '已改分类为：${_categoryLabel(category)}');
    }
  }

  Future<PromptTagCategory?> _pickTagCategory(BuildContext context) {
    return showDialog<PromptTagCategory>(
      context: context,
      builder: (context) {
        return SimpleDialog(
          key: const ValueKey('prompt-tag-category-dialog'),
          backgroundColor: StudioTokens.surface2,
          title: const Text('改分类'),
          children: [
            for (final category in _manualCategoryChoices(widget.negative))
              SimpleDialogOption(
                key: ValueKey('prompt-tag-category-option-${category.name}'),
                onPressed: () => Navigator.of(context).pop(category),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: promptTagCategoryColor(category),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(_categoryLabel(category)),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _clearTagCategory(BuildContext context, String tag) async {
    final cache = _classificationCache();
    cache.clearCategory(tag, negative: widget.negative);
    widget.onClassificationChanged?.call();
    unawaited(_saveClassificationCacheBestEffort(cache));
    if (!mounted) {
      return;
    }
    setState(() {});
    if (context.mounted) {
      _showSnack(context, '已恢复自动分类');
    }
  }

  PromptTagFilterRuleAdder? _filterRuleAdder() {
    if (widget.onAddToFilterRules != null) {
      return widget.onAddToFilterRules;
    }
    if (GetIt.I.isRegistered<PromptTagFilterRulesController>()) {
      return GetIt.I<PromptTagFilterRulesController>().addTags;
    }
    return null;
  }

  String _retranslateMenuLabel() {
    final service = _promptTranslationService();
    if (service == null) {
      return 'AI重译';
    }
    return switch (service.currentMode) {
      OnlineAiMode.google => 'Google重译',
      OnlineAiMode.ai => 'AI重译',
    };
  }

  Future<void> _openDanbooruWiki(BuildContext context, String tag) async {
    final uri = PromptTagClassifier.danbooruWikiUri(tag);
    try {
      final launcher = widget.onOpenDanbooru;
      if (launcher != null) {
        await launcher(uri);
      } else {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (error) {
      if (context.mounted) {
        _showSnack(context, '无法打开 Danbooru Wiki: $error');
      }
    }
  }

  Future<void> _aiRetranslateTag(BuildContext context, String tag) async {
    final translator = widget.onAiRetranslate;
    final usesDefaultTranslator = translator == null;
    final result = translator == null
        ? await _defaultAiRetranslate(tag)
        : OnlineTranslationResult(
            text: (await translator(tag))?.trim() ?? '',
            source: OnlineAiResultSource.online,
            providerName: 'override',
          );
    final translated = result.text.trim();
    if (!mounted || !context.mounted) {
      return;
    }
    if (translated.isEmpty) {
      _showSnack(context, result.error ?? '暂无可用翻译');
      return;
    }

    final cache = _translationCache();
    if (!usesDefaultTranslator &&
        result.source == OnlineAiResultSource.online) {
      cache.setCached(tag, translated, source: result.providerName ?? 'ai');
      unawaited(_saveTranslationCache(cache));
    }
    if (!mounted || !context.mounted) {
      return;
    }
    setState(() {
      _translationOverrides[tag] = translated;
      _shortcutTranslated = true;
    });
    _showSnack(
      context,
      result.source == OnlineAiResultSource.localFallback
          ? '已使用本地缓存翻译'
          : '已重译标签',
    );
  }

  Future<OnlineTranslationResult> _defaultAiRetranslate(String tag) async {
    final service = _promptTranslationService();
    if (service != null) {
      return PromptTagAutoTranslationQueue.instance.request(
        tag: tag,
        sourceLanguage: 'en',
        targetLanguage: 'zh',
        cache: _translationCache(),
        service: service,
        preferCache: false,
        saveTranslationCache: _saveTranslationCache,
      );
    }

    return const OnlineTranslationResult(
      text: '',
      source: OnlineAiResultSource.emptyFallback,
      error: '未配置翻译服务',
    );
  }

  Future<void> _editTranslation(BuildContext context, String tag) async {
    final cache = _translationCache();
    final controller = TextEditingController(text: _translationFor(cache, tag));
    final translated = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          key: const ValueKey('prompt-tag-manual-translation-dialog'),
          backgroundColor: StudioTokens.surface2,
          title: const Text('手动编辑翻译'),
          content: SizedBox(
            width: 420,
            child: TextField(
              key: const ValueKey('prompt-tag-manual-translation-field'),
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(
                labelText: tag,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          actions: [
            TextButton(
              style: _promptTagDialogTextButtonStyle(),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              key: const ValueKey('prompt-tag-manual-save'),
              style: _promptTagDialogPrimaryButtonStyle(),
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
    final trimmed = translated?.trim();
    if (!mounted || !context.mounted || trimmed == null || trimmed.isEmpty) {
      return;
    }
    cache.setManual(tag, trimmed);
    unawaited(_saveTranslationCache(cache));
    if (!mounted || !context.mounted) {
      return;
    }
    setState(() {
      _translationOverrides[tag] = trimmed;
      _shortcutTranslated = true;
    });
    _showSnack(context, '已保存翻译');
  }

  Future<void> _editWeight(BuildContext context, int index) async {
    final analyses = _analysesFor(widget.text);
    if (index < 0 || index >= analyses.length || widget.onChanged == null) {
      return;
    }
    final item = analyses[index];
    final targetIndexes = _weightEditTargetIndexes(index, analyses.length);
    final controller = TextEditingController(
      text: item.weight == null ? '' : formatPromptTagWeightText(item.weight!),
    );
    final nextWeight = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          key: const ValueKey('prompt-tag-edit-weight-dialog'),
          backgroundColor: StudioTokens.surface2,
          title: const Text('编辑权重'),
          content: SizedBox(
            width: 320,
            child: TextField(
              key: const ValueKey('prompt-tag-edit-weight-field'),
              controller: controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              decoration: InputDecoration(
                labelText: item.displayText,
                hintText: '1.2',
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => Navigator.of(context).pop(controller.text),
            ),
          ),
          actions: [
            TextButton(
              style: _promptTagDialogTextButtonStyle(),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              key: const ValueKey('prompt-tag-edit-weight-save'),
              style: _promptTagDialogPrimaryButtonStyle(),
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
    if (!mounted || nextWeight == null) {
      return;
    }
    final trimmed = nextWeight.trim();
    final parsed = trimmed.isEmpty ? 1.0 : double.tryParse(trimmed);
    if (parsed == null || !parsed.isFinite) {
      if (context.mounted) {
        _showSnack(context, '请输入数字权重');
      }
      return;
    }
    String weightedValue(WorkshopTagAnalysis tag) {
      final clean = tag.displayText.trim();
      return parsed == 1.0
          ? clean
          : formatPromptTagWeightedValue(clean, parsed);
    }

    final nextTags = [
      for (final (tagIndex, tag) in analyses.indexed)
        targetIndexes.contains(tagIndex)
            ? weightedValue(tag)
            : promptTagRawValueForAnalysis(tag),
    ];
    widget.onChanged?.call(joinPromptTags(nextTags));
    if (!mounted) {
      return;
    }
    setState(_clearSelectionStateOnly);
  }

  Set<int> _weightEditTargetIndexes(int index, int tagCount) {
    final activeSelected = _activeSelectedIndexes;
    if (!activeSelected.contains(index)) {
      return {index};
    }
    final validIndexes = activeSelected
        .where((targetIndex) => targetIndex >= 0 && targetIndex < tagCount)
        .toSet();
    return validIndexes.isEmpty ? {index} : validIndexes;
  }

  Future<void> _copyTags(
    BuildContext context, {
    required String fallbackTag,
  }) async {
    final tags = _copySourceTags(fallbackTag);
    await Clipboard.setData(ClipboardData(text: tags.join(', ')));
    if (context.mounted) {
      _showSnack(context, tags.length > 1 ? '已复制选中标签' : '已复制标签');
    }
  }

  Future<void> _addTagsToFilterRules(
    BuildContext context, {
    required String fallbackTag,
    required PromptTagFilterRuleAdder? addToFilterRules,
  }) async {
    if (addToFilterRules == null) {
      return;
    }
    final tags = _copySourceTags(fallbackTag)
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toList(growable: false);
    if (tags.isEmpty) {
      return;
    }
    final target = await _pickFilterRuleTarget(context, tags.length);
    if (!mounted || !context.mounted || target == null) {
      return;
    }
    await addToFilterRules.call(tags, target);
    if (context.mounted) {
      _showSnack(context, '已加入${_filterRuleTargetLabel(target)}');
    }
  }

  Future<PromptTagFilterRuleTarget?> _pickFilterRuleTarget(
    BuildContext context,
    int count,
  ) {
    final targets = _enabledFilterRuleTargets();
    if (targets.isEmpty) {
      return Future.value();
    }
    return showDialog<PromptTagFilterRuleTarget>(
      context: context,
      builder: (context) {
        return AlertDialog(
          key: const ValueKey('prompt-tag-filter-target-dialog'),
          backgroundColor: StudioTokens.surface2,
          title: Text(count > 1 ? '加入屏蔽库（$count 个标签）' : '加入屏蔽库'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _FilterRuleTargetOption(
                key: const ValueKey('prompt-tag-filter-target-delete'),
                icon: Icons.block_outlined,
                title: '删除关键词',
                subtitle: '解析时直接移除这些标签',
                onTap: () => Navigator.of(
                  context,
                ).pop(PromptTagFilterRuleTarget.deleteKeywords),
              ),
              const SizedBox(height: 8),
              _FilterRuleTargetOption(
                key: const ValueKey('prompt-tag-filter-target-strong'),
                icon: Icons.shield_outlined,
                title: '强屏蔽关键词',
                subtitle: '更强的过滤规则，适合必须屏蔽的标签',
                onTap: () => Navigator.of(
                  context,
                ).pop(PromptTagFilterRuleTarget.strongFilterKeywords),
              ),
              const SizedBox(height: 8),
              _FilterRuleTargetOption(
                key: const ValueKey('prompt-tag-filter-target-replace'),
                icon: Icons.swap_horiz,
                title: '替换规则源',
                subtitle: '先加入替换源，目标文本之后可在规则库里编辑',
                onTap: () => Navigator.of(
                  context,
                ).pop(PromptTagFilterRuleTarget.replaceSource),
              ),
              if (targets
                  .contains(PromptTagFilterRuleTarget.scriptScopedBlockWords))
                const SizedBox(height: 8),
              if (targets
                  .contains(PromptTagFilterRuleTarget.scriptScopedBlockWords))
                _FilterRuleTargetOption(
                  key: const ValueKey('prompt-tag-filter-target-script'),
                  icon: Icons.article_outlined,
                  title: '\u672c\u5267\u672c\u5c4f\u853d',
                  subtitle:
                      '\u53ea\u5728\u5f53\u524d\u5267\u672c\u5de5\u4f5c\u53f0\u9884\u89c8\u548c\u53d1\u9001\u65f6\u79fb\u9664',
                  onTap: () => Navigator.of(
                    context,
                  ).pop(PromptTagFilterRuleTarget.scriptScopedBlockWords),
                ),
            ],
          ),
          actions: [
            TextButton(
              style: _promptTagDialogTextButtonStyle(),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
          ],
        );
      },
    );
  }

  // ignore: unused_element
  String _filterRuleTargetLabel(PromptTagFilterRuleTarget target) {
    return switch (target) {
      PromptTagFilterRuleTarget.scriptScopedBlockWords =>
        '\u672c\u5267\u672c\u5c4f\u853d',
      PromptTagFilterRuleTarget.deleteKeywords => '删除关键词',
      PromptTagFilterRuleTarget.strongFilterKeywords => '强屏蔽关键词',
      PromptTagFilterRuleTarget.replaceSource => '替换规则',
    };
  }

  List<String> _copySourceTags(String fallbackTag) {
    final selected = _activeSelectedIndexes;
    if (selected.isEmpty) {
      return fallbackTag.trim().isEmpty ? const [] : [fallbackTag];
    }
    final analyses = _analysesFor(widget.text);
    final result = <String>[];
    for (final index in selected.toList()..sort()) {
      if (index >= 0 && index < analyses.length) {
        result.add(analyses[index].text);
      }
    }
    return result.isEmpty ? [fallbackTag] : result;
  }

  void _showSnack(BuildContext context, String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) {
      return;
    }
    try {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    } catch (_) {
      // Some embedded studio surfaces are rendered without a Scaffold.
    }
  }

  Future<void> _saveTranslationCache(TranslationCache cache) async {
    try {
      final saver = widget.saveTranslationCache;
      if (saver != null) {
        await saver(cache);
      } else {
        await PromptWorkshopBridge.saveTranslationCache(cache);
      }
    } catch (_) {
      // The visible translation is still useful even when disk persistence fails.
    }
  }

  Future<void> _saveClassificationCacheBestEffort(
    PromptTagClassificationCache cache,
  ) async {
    try {
      final saver = widget.saveClassificationCache;
      if (saver != null) {
        await saver(cache);
        return;
      }
      if (widget.classificationCache == null &&
          !GetIt.I.isRegistered<PromptTagClassificationCache>()) {
        return;
      }
      await PromptWorkshopBridge.saveTagClassificationCache(cache);
    } catch (_) {
      // Classification caching is an acceleration layer; rendering can proceed.
    }
  }
}

class _PromptTagItem {
  final int index;
  final String rawText;
  final String text;
  final String? weightLabel;
  final double? weight;
  final PromptTagClassification classification;
  final bool warning;

  const _PromptTagItem({
    required this.index,
    required this.rawText,
    required this.text,
    this.weightLabel,
    this.weight,
    required this.classification,
    required this.warning,
  });
}

class _PromptTagDisplayLayoutControls extends StatelessWidget {
  final bool dense;
  final PromptTagLayoutMode layoutMode;
  final ValueChanged<PromptTagLayoutMode> onChanged;

  const _PromptTagDisplayLayoutControls({
    required this.dense,
    required this.layoutMode,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        _PromptTagDisplayControlButton(
          key: const ValueKey('prompt-tag-layout-sourceOrder'),
          icon: Icons.format_align_left_outlined,
          label: '原序',
          tooltip: '按原始顺序显示标签',
          dense: dense,
          selected: layoutMode == PromptTagLayoutMode.sourceOrder,
          onPressed: () => onChanged(PromptTagLayoutMode.sourceOrder),
        ),
        _PromptTagDisplayControlButton(
          key: const ValueKey('prompt-tag-layout-grouped'),
          icon: Icons.account_tree_outlined,
          label: '分块',
          tooltip: '按标签分类分块显示',
          dense: dense,
          selected: layoutMode == PromptTagLayoutMode.grouped,
          onPressed: () => onChanged(PromptTagLayoutMode.grouped),
        ),
      ],
    );
  }
}

class _PromptTagDisplayControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String tooltip;
  final bool dense;
  final bool selected;
  final VoidCallback onPressed;

  const _PromptTagDisplayControlButton({
    super.key,
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.dense,
    required this.selected,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor:
              selected ? StudioTokens.onPrimary : StudioTokens.textSecondary,
          backgroundColor:
              selected ? StudioTokens.primary : StudioTokens.surface3,
          side: BorderSide(
            color: selected ? StudioTokens.primary : StudioTokens.borderStrong,
          ),
          padding: EdgeInsets.symmetric(
            horizontal: dense ? 8 : 10,
            vertical: dense ? 4 : 6,
          ),
          minimumSize: Size(0, dense ? 28 : 32),
          textStyle: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: dense ? 11 : 12,
          ),
        ),
        onPressed: onPressed,
        icon: Icon(icon, size: dense ? 14 : 16),
        label: Text(label),
      ),
    );
  }
}

class _FilterRuleTargetOption extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _FilterRuleTargetOption({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  State<_FilterRuleTargetOption> createState() =>
      _FilterRuleTargetOptionState();
}

class _FilterRuleTargetOptionState extends State<_FilterRuleTargetOption> {
  bool _hovered = false;
  bool _pressed = false;

  Key? get _surfaceKey {
    final key = widget.key;
    return key is ValueKey<String> ? ValueKey('${key.value}-surface') : null;
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: StudioTokens.radiusSlot,
      mouseCursor: SystemMouseCursors.click,
      onHover: (hovered) => setState(() {
        _hovered = hovered;
      }),
      onHighlightChanged: (pressed) => setState(() {
        _pressed = pressed;
      }),
      onTap: widget.onTap,
      child: AnimatedContainer(
        key: _surfaceKey,
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _pressed
              ? StudioTokens.surface4
              : _hovered
                  ? StudioTokens.surface3
                  : StudioTokens.surface1,
          borderRadius: StudioTokens.radiusSlot,
          border: Border.all(
            color: _hovered ? StudioTokens.borderStrong : StudioTokens.border,
          ),
        ),
        child: Row(
          children: [
            Icon(widget.icon, size: 18, color: StudioTokens.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: StudioTokens.textPrimary,
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: StudioTokens.textMuted,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PromptTagGroupBlock extends StatelessWidget {
  final String label;
  final Widget? action;
  final List<Widget> children;
  final bool activeDrop;

  const _PromptTagGroupBlock({
    required this.label,
    this.action,
    required this.children,
    this.activeDrop = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: activeDrop
            ? StudioTokens.primary.withAlpha(14)
            : StudioTokens.surface2,
        borderRadius: StudioTokens.radiusSlot,
        border: Border.all(
          color: activeDrop ? StudioTokens.primary : StudioTokens.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: StudioTokens.textSecondary,
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              if (action != null) ...[const SizedBox(width: 8), action!],
            ],
          ),
          const SizedBox(height: 7),
          Wrap(spacing: 7, runSpacing: 7, children: children),
        ],
      ),
    );
  }
}

enum _PromptTagMenuAction {
  openDanbooru,
  aiRetranslate,
  manualEdit,
  editWeight,
  changeCategory,
  clearCategory,
  copy,
  addToFilterRules,
}

class _PromptTagMenuChoice {
  final _PromptTagMenuAction action;

  const _PromptTagMenuChoice(this.action);
}

List<PromptTagCategory> _manualCategoryChoices(bool negative) {
  if (negative) {
    return const [
      PromptTagCategory.negativeQuality,
      PromptTagCategory.negativeBody,
      PromptTagCategory.negativeArtist,
      PromptTagCategory.negativeContent,
      PromptTagCategory.other,
    ];
  }
  return const [
    PromptTagCategory.quality,
    PromptTagCategory.artist,
    PromptTagCategory.character,
    PromptTagCategory.upperBody,
    PromptTagCategory.lowerBody,
    PromptTagCategory.upperClothing,
    PromptTagCategory.lowerClothing,
    PromptTagCategory.clothing,
    PromptTagCategory.action,
    PromptTagCategory.scene,
    PromptTagCategory.camera,
    PromptTagCategory.style,
    PromptTagCategory.other,
  ];
}

String _categoryLabel(PromptTagCategory category) {
  return switch (category) {
    PromptTagCategory.character => '角色',
    PromptTagCategory.upperBody => '上身',
    PromptTagCategory.lowerBody => '下身',
    PromptTagCategory.upperClothing => '上装',
    PromptTagCategory.lowerClothing => '下装',
    PromptTagCategory.clothing => '服装',
    PromptTagCategory.action => '动作',
    PromptTagCategory.scene => '场景',
    PromptTagCategory.camera => '镜头',
    PromptTagCategory.artist => '画师',
    PromptTagCategory.style => '风格',
    PromptTagCategory.quality => '画质',
    PromptTagCategory.negativeQuality => '负面画质',
    PromptTagCategory.negativeBody => '负面人体',
    PromptTagCategory.negativeArtist => '负面画师',
    PromptTagCategory.negativeContent => '负面内容',
    PromptTagCategory.promptSyntax => '语法',
    PromptTagCategory.other => '其它',
  };
}

ButtonStyle _promptTagDialogTextButtonStyle() {
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

ButtonStyle _promptTagDialogPrimaryButtonStyle() {
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

class _EmptyPromptText extends StatelessWidget {
  final String text;

  const _EmptyPromptText({required this.text});

  @override
  Widget build(BuildContext context) {
    if (text.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    return Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.bodySmall?.copyWith(color: StudioTokens.textMuted),
    );
  }
}
