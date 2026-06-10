import 'dart:async';
import 'dart:collection';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:nai_casrand/data/models/payload_config.dart';
import 'package:nai_casrand/data/studio/services/prompt_translation_service.dart';
import 'package:nai_casrand/data/studio/services/prompt_workshop_bridge.dart';
import 'package:nai_casrand/data/studio/tools/online_ai_tools.dart';
import 'package:nai_casrand/data/studio/tools/prompt_tag_classifier.dart';
import 'package:nai_casrand/data/studio/tools/prompt_tag_processor.dart';
import 'package:nai_casrand/data/studio/tools/translation_cache.dart';
import 'package:nai_casrand/ui/studio_core/services/prompt_tag_filter_rules.dart';
import 'package:nai_casrand/ui/studio_core/services/prompt_tag_list_utils.dart';
import 'package:nai_casrand/ui/studio_core/services/prompt_tag_presentation.dart';
import 'package:nai_casrand/ui/studio_core/theme/prompt_tag_category_style.dart';
import 'package:nai_casrand/ui/studio_core/theme/studio_tokens.dart';
import 'package:nai_casrand/ui/studio_core/widgets/prompt_tag_drag.dart';
import 'package:nai_casrand/ui/studio_core/widgets/prompt_tag_selection_toolbar.dart';
import 'package:url_launcher/url_launcher.dart';

typedef PromptTagEditorAiRetranslate = Future<String?> Function(String tag);
typedef PromptTagEditorDanbooruLauncher = Future<void> Function(Uri uri);
typedef PromptTagEditorHighlightResolver = PromptTagEditorHighlight? Function(
  String tag,
);

class PromptTagEditorHighlight {
  final String tooltip;

  const PromptTagEditorHighlight({
    required this.tooltip,
  });
}

class _PromptTagAutoTranslationQueue {
  static final _PromptTagAutoTranslationQueue instance =
      _PromptTagAutoTranslationQueue._();

  final Queue<_PromptTagAutoTranslationJob> _queue =
      Queue<_PromptTagAutoTranslationJob>();
  final Map<String, _PromptTagAutoTranslationJob> _jobs =
      <String, _PromptTagAutoTranslationJob>{};
  bool _running = false;

  _PromptTagAutoTranslationQueue._();

  Future<OnlineTranslationResult> request({
    required String tag,
    required String sourceLanguage,
    required String targetLanguage,
    required TranslationCache cache,
    required PromptTranslationService service,
    bool preferCache = true,
  }) {
    final cleanedTag = tag.trim();
    if (cleanedTag.isEmpty) {
      return Future.value(
        const OnlineTranslationResult(
          text: '',
          source: OnlineAiResultSource.emptyFallback,
        ),
      );
    }
    final key = _key(
      cleanedTag,
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
    );
    final existing = _jobs[key];
    if (existing != null) {
      return existing.completer.future;
    }
    final job = _PromptTagAutoTranslationJob(
      key: key,
      tag: cleanedTag,
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
      cache: cache,
      service: service,
      preferCache: preferCache,
    );
    _jobs[key] = job;
    _queue.add(job);
    unawaited(_drain());
    return job.completer.future;
  }

  Future<void> _drain() async {
    if (_running) {
      return;
    }
    _running = true;
    while (_queue.isNotEmpty) {
      final job = _queue.removeFirst();
      try {
        final result = await job.service.translate(
          OnlineTranslationRequest(
            text: job.tag,
            sourceLanguage: job.sourceLanguage,
            targetLanguage: job.targetLanguage,
          ),
          preferCache: job.preferCache,
        );
        final translated = result.text.trim();
        if (translated.isNotEmpty &&
            result.source == OnlineAiResultSource.online) {
          job.cache.setCached(
            job.tag,
            translated,
            source: result.providerName ?? job.service.currentMode.name,
          );
          unawaited(PromptWorkshopBridge.saveTranslationCache(job.cache));
        }
        job.completer.complete(result);
      } catch (error) {
        job.completer.complete(
          OnlineTranslationResult(
            text: '',
            source: OnlineAiResultSource.emptyFallback,
            error: error.toString(),
          ),
        );
      } finally {
        _jobs.remove(job.key);
      }
      await Future<void>.delayed(Duration.zero);
    }
    _running = false;
    if (_queue.isNotEmpty) {
      unawaited(_drain());
    }
  }

  String _key(
    String tag, {
    required String sourceLanguage,
    required String targetLanguage,
  }) {
    return '$sourceLanguage->$targetLanguage::${tag.toLowerCase()}';
  }
}

class _PromptTagAutoTranslationJob {
  final String key;
  final String tag;
  final String sourceLanguage;
  final String targetLanguage;
  final TranslationCache cache;
  final PromptTranslationService service;
  final bool preferCache;
  final Completer<OnlineTranslationResult> completer =
      Completer<OnlineTranslationResult>();

  _PromptTagAutoTranslationJob({
    required this.key,
    required this.tag,
    required this.sourceLanguage,
    required this.targetLanguage,
    required this.cache,
    required this.service,
    required this.preferCache,
  });
}

class PromptTagEditor extends StatefulWidget {
  final String value;
  final ValueChanged<String> onChanged;
  final String? label;
  final bool dense;
  final bool enabled;
  final bool allowAdd;
  final bool enableTagActions;
  final bool showControls;
  final bool inlineLabel;
  final double inlineLabelWidth;
  final String emptyText;
  final bool negative;
  final PromptTagEditorAiRetranslate? onAiRetranslate;
  final PromptTagEditorDanbooruLauncher? onOpenDanbooru;
  final PromptTagFilterRuleAdder? onAddToFilterRules;
  final PromptTagSelectionController? selectionController;
  final String? selectionFieldId;
  final String? selectionGroupId;
  final bool showSelectionToolbar;
  final PromptTagDragRemovalPolicy? removeDroppedTagsFromSource;
  final PromptTagEditorHighlightResolver? highlightForTag;
  final int? autoTranslateTagLimit;
  final bool initialGroupedLayout;

  const PromptTagEditor({
    super.key,
    required this.value,
    required this.onChanged,
    this.label,
    this.dense = false,
    this.enabled = true,
    this.allowAdd = true,
    this.enableTagActions = true,
    this.showControls = true,
    this.inlineLabel = false,
    this.inlineLabelWidth = 72,
    this.negative = false,
    this.emptyText = '暂无标签',
    this.onAiRetranslate,
    this.onOpenDanbooru,
    this.onAddToFilterRules,
    this.selectionController,
    this.selectionFieldId,
    this.selectionGroupId,
    this.showSelectionToolbar = true,
    this.removeDroppedTagsFromSource,
    this.highlightForTag,
    this.autoTranslateTagLimit,
    this.initialGroupedLayout = false,
  });

  @override
  State<PromptTagEditor> createState() => _PromptTagEditorState();
}

class _PromptTagEditorState extends State<PromptTagEditor> {
  static int _nextDragOrigin = 0;

  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode(debugLabel: 'prompt-tag-editor-input');
  final FocusNode _selectionFocusNode = FocusNode(
    debugLabel: 'prompt-tag-editor-selection',
  );
  late final String _dragOriginId = 'prompt-tag-editor-${_nextDragOrigin++}';
  bool _editing = false;
  late String _value = widget.value;
  final Set<String> _autoTranslationPending = <String>{};
  final Set<String> _autoTranslationMisses = <String>{};
  final Map<String, String> _translationOverrides = <String, String>{};
  final Set<int> _selectedIndexes = <int>{};
  final Set<int> _selectionPreviewIndexes = <int>{};
  final GlobalKey _selectionAreaKey = GlobalKey();
  final Map<int, GlobalKey> _chipKeys = <int, GlobalKey>{};
  TranslationCache? _fallbackTranslationCache;
  Timer? _doubleTapDragSuppressionTimer;
  int? _doubleTapDragSuppressedIndex;
  Offset? _selectionStart;
  Offset? _selectionCurrent;
  bool _selectionMoved = false;
  bool _selectionAdditive = false;
  bool _showTranslations = true;
  late bool _groupedLayout = widget.initialGroupedLayout;
  bool _submittingInput = false;
  PromptTagSelectionController? _registeredSelectionController;
  String? _registeredSelectionFieldId;
  String? _parsedTagItemsValue;
  List<_PromptTagEditorItem>? _parsedTagItems;
  List<String>? _rawTagsCache;
  List<String>? _displayTagsCache;

  @override
  void initState() {
    super.initState();
    _syncSelectionController();
  }

  @override
  void didUpdateWidget(covariant PromptTagEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectionController != widget.selectionController ||
        oldWidget.selectionFieldId != widget.selectionFieldId ||
        oldWidget.selectionGroupId != widget.selectionGroupId) {
      _syncSelectionController();
    }
    if (oldWidget.value != widget.value && widget.value != _value) {
      _value = widget.value;
      _translationOverrides.clear();
      _autoTranslationPending.clear();
      _autoTranslationMisses.clear();
      _clearSelection();
    }
  }

  @override
  void dispose() {
    _doubleTapDragSuppressionTimer?.cancel();
    _unregisterSelectionController();
    _controller.dispose();
    _focusNode.dispose();
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
          removeIndexes: _deleteIndexes,
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
    final tags = _tagItems;
    final translationCache = _translationCacheOrNull();
    final translationService = _translationServiceOrNull();
    if (_showTranslations &&
        translationCache != null &&
        translationService != null &&
        _shouldAutoTranslate(tags.length)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _enqueueAutoTranslations(
            tags.map((tag) => tag.displayLabel),
            translationCache,
            translationService,
          );
        }
      });
    }
    final theme = Theme.of(context);
    final padding = widget.dense
        ? const EdgeInsets.all(8)
        : const EdgeInsets.symmetric(horizontal: 12, vertical: 10);

    final tagContent = _buildSelectionArea(
      _groupedLayout
          ? _buildGroupedTags(context, tags, translationCache)
          : _buildSourceOrderTags(context, tags, translationCache),
    );

    return Container(
      key: const ValueKey('prompt-tag-editor'),
      padding: padding,
      decoration: BoxDecoration(
        color: StudioTokens.surface2,
        borderRadius: StudioTokens.radiusSlot,
        border: Border.all(
          color:
              widget.enabled ? StudioTokens.borderStrong : StudioTokens.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.inlineLabel)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.label != null) ...[
                  SizedBox(
                    width: widget.inlineLabelWidth,
                    child: Text(
                      widget.label!,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: StudioTokens.primary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(child: tagContent),
                if (widget.showControls) ...[
                  const SizedBox(width: 8),
                  _controls(),
                ],
              ],
            )
          else ...[
            if (widget.label != null || widget.showControls) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.label != null)
                    Expanded(
                      child: Text(
                        widget.label!,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: StudioTokens.primary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    )
                  else
                    const Spacer(),
                  if (widget.showControls) ...[
                    const SizedBox(width: 8),
                    _controls(),
                  ],
                ],
              ),
              const SizedBox(height: 8),
            ],
            tagContent,
          ],
        ],
      ),
    );
  }

  bool _shouldAutoTranslate(int tagCount) {
    final limit = widget.autoTranslateTagLimit;
    return limit == null || tagCount <= limit;
  }

  Widget _controls() {
    return _PromptTagEditorControls(
      dense: widget.dense,
      showTranslations: _showTranslations,
      groupedLayout: _groupedLayout,
      canClearTags: widget.enabled && _tagItems.isNotEmpty,
      onToggleTranslations: () {
        setState(() {
          _showTranslations = !_showTranslations;
        });
      },
      onToggleLayout: () {
        setState(() {
          _groupedLayout = !_groupedLayout;
        });
      },
      onClearTags: _clearAllTags,
    );
  }

  Widget _buildSelectionArea(Widget content) {
    final rect = _selectionRect();
    return Focus(
      key: const ValueKey('prompt-tag-editor-selection-area'),
      focusNode: _selectionFocusNode,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) {
          return KeyEventResult.ignored;
        }
        if (event.logicalKey == LogicalKeyboardKey.escape) {
          _clearSelection();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.delete ||
            event.logicalKey == LogicalKeyboardKey.backspace) {
          if (_selectedCount > 0 && widget.enabled) {
            _deleteSelectedTags();
            return KeyEventResult.handled;
          }
        }
        if ((HardwareKeyboard.instance.isControlPressed ||
                HardwareKeyboard.instance.isMetaPressed) &&
            event.logicalKey == LogicalKeyboardKey.keyC &&
            _selectedCount > 0) {
          _copyTags(_selectedTags());
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
                      BoxShadow(
                        color: Color(0x33FFE500),
                        blurRadius: 12,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (widget.showSelectionToolbar && _selectedCount > 0)
            Positioned(
              top: -12,
              right: widget.dense ? 6 : 8,
              child: PromptTagSelectionToolbar(
                count: _selectedCount,
                onClear: _clearSelection,
                toolbarKey:
                    const ValueKey('prompt-tag-editor-selection-toolbar'),
                clearButtonKey:
                    const ValueKey('prompt-tag-editor-clear-selection'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _selectionDropTarget(Widget content) {
    return DragTarget<PromptTagDragData>(
      key: const ValueKey('prompt-tag-editor-drop-area'),
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

  Widget _buildSourceOrderTags(
    BuildContext context,
    List<_PromptTagEditorItem> tags,
    TranslationCache? translationCache,
  ) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (tags.isEmpty && !_editing) _emptyHint(context),
        for (final item in tags)
          _tagChip(
            item: item,
            translationCache: translationCache,
          ),
        _inputOrAddButton(),
      ],
    );
  }

  Widget _buildGroupedTags(
    BuildContext context,
    List<_PromptTagEditorItem> tags,
    TranslationCache? translationCache,
  ) {
    final cache = _classificationCacheOrNull();
    final items = [
      for (final item in tags)
        item.copyWith(
          group: classifyPromptTagForPresentation(
            item.displayLabel,
            negative: widget.negative,
            cache: cache,
          ).group,
        ),
    ];

    final blocks = [
      for (final group in PromptTagClassifier.groups)
        (
          group: group,
          items: items
              .where((item) => item.group!.id == group.id)
              .toList(growable: false),
        ),
    ].where((block) => block.items.isNotEmpty).toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (blocks.isEmpty && !_editing) _emptyHint(context),
        for (final block in blocks) ...[
          Container(
            key: ValueKey('prompt-tag-editor-group-${block.group.id}'),
            padding: const EdgeInsets.all(8),
            margin: const EdgeInsets.only(bottom: 6),
            decoration: BoxDecoration(
              color: StudioTokens.surfaceBase,
              borderRadius: StudioTokens.radiusSlot,
              border: StudioTokens.cardBorder,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  block.group.label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: StudioTokens.primary,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final item in block.items)
                      _tagChip(
                        item: item,
                        translationCache: translationCache,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: _inputOrAddButton(),
        ),
      ],
    );
  }

  Widget _tagChip({
    required _PromptTagEditorItem item,
    required TranslationCache? translationCache,
  }) {
    final index = item.index;
    return DragTarget<PromptTagDragData>(
      key: _chipKeyFor(index),
      hitTestBehavior: HitTestBehavior.translucent,
      onWillAcceptWithDetails: _canAcceptDraggedTags,
      onAcceptWithDetails: (details) => _acceptDraggedTags(
        details.data,
        insertIndex: index,
      ),
      builder: (context, candidates, rejected) {
        final selected = _isSelected(index);
        final highlight = widget.highlightForTag?.call(item.displayLabel);
        final chip = _EditablePromptTagChip(
          index: index,
          rawLabel: item.displayLabel,
          weightLabel: item.weightLabel,
          weight: item.weight,
          translation: _translationFor(item.displayLabel, translationCache),
          category: classifyPromptTagForPresentation(
            item.displayLabel,
            negative: widget.negative,
            cache: _classificationCacheOrNull(),
          ).category,
          dense: widget.dense,
          enabled: widget.enabled,
          highlight: highlight,
          previewed: _selectionPreviewIndexes.contains(index) ||
              _isPreviewed(index) ||
              candidates.isNotEmpty,
          selected: selected,
          onDeleted: widget.enabled ? () => _deleteTag(index) : null,
          onDoubleTap:
              widget.enabled ? () => unawaited(_editTag(context, index)) : null,
          onSecondaryTapDown: widget.enabled && widget.enableTagActions
              ? (details) => _showTagMenu(
                    context,
                    details.globalPosition,
                    index,
                  )
              : null,
        );
        if (!_canDragTags) {
          return chip;
        }
        final dragData = _dragDataForIndex(index);
        return Draggable<PromptTagDragData>(
          data: dragData,
          dragAnchorStrategy: pointerDragAnchorStrategy,
          feedback: PromptTagDragFeedback(
            tags: dragData.tags,
            dense: widget.dense,
          ),
          maxSimultaneousDrags: _isDragSuppressedForDoubleTap(index) ? 0 : null,
          onDragStarted: () => _beginDraggingIndexes(dragData.indexes),
          childWhenDragging: Opacity(opacity: 0.45, child: chip),
          child: chip,
        );
      },
    );
  }

  Widget _emptyHint(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text(
        widget.emptyText,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: StudioTokens.textMuted,
            ),
      ),
    );
  }

  Widget _inputOrAddButton() {
    if (!widget.allowAdd) {
      return const SizedBox.shrink();
    }
    if (_editing) {
      return SizedBox(
        width: widget.dense ? 180 : 240,
        child: TextField(
          key: const ValueKey('prompt-tag-editor-input'),
          controller: _controller,
          focusNode: _focusNode,
          autofocus: true,
          enabled: widget.enabled,
          minLines: 1,
          maxLines: 3,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            isDense: true,
            hintText: '输入标签，逗号可批量分割',
            suffixIcon: IconButton(
              tooltip: '添加标签',
              icon: _submittingInput
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              onPressed:
                  _submittingInput ? null : () => unawaited(_submitInput()),
            ),
          ),
          onSubmitted: (_) {
            if (!_submittingInput) {
              unawaited(_submitInput());
            }
          },
        ),
      );
    }
    return IconButton.filled(
      key: const ValueKey('prompt-tag-editor-add'),
      tooltip: '添加标签',
      icon: const Icon(Icons.add),
      iconSize: widget.dense ? 16 : 18,
      style: IconButton.styleFrom(
        backgroundColor:
            widget.enabled ? StudioTokens.primary : StudioTokens.surface3,
        foregroundColor:
            widget.enabled ? StudioTokens.onPrimary : StudioTokens.textMuted,
        minimumSize:
            widget.dense ? const Size.square(30) : const Size.square(36),
        padding: EdgeInsets.zero,
      ),
      onPressed: widget.enabled ? _startEditing : null,
    );
  }

  List<String> get _tags {
    final cached = _rawTagsCache;
    if (cached != null) {
      return cached;
    }
    return _rawTagsCache =
        _tagItems.map((tag) => tag.rawTag).toList(growable: false);
  }

  List<String> get _displayTags {
    final cached = _displayTagsCache;
    if (cached != null) {
      return cached;
    }
    return _displayTagsCache =
        _tagItems.map((tag) => tag.displayLabel).toList(growable: false);
  }

  List<_PromptTagEditorItem> get _tagItems {
    final normalizedValue = _value.trim();
    final cached = _parsedTagItems;
    if (_parsedTagItemsValue == normalizedValue && cached != null) {
      return cached;
    }
    final parsed = List<_PromptTagEditorItem>.unmodifiable(
      _tagItemsForValue(normalizedValue),
    );
    _parsedTagItemsValue = normalizedValue;
    _parsedTagItems = parsed;
    _rawTagsCache = null;
    _displayTagsCache = null;
    return parsed;
  }

  List<_PromptTagEditorItem> _tagItemsForValue(String value) {
    return [
      for (final item in promptTagPresentationItems(value))
        _PromptTagEditorItem(
          index: item.index,
          rawTag: item.rawTag,
          displayLabel: item.displayLabel,
          weight: item.weight,
          weightLabel: item.weightLabel,
        ),
    ];
  }

  TranslationCache? _translationCacheOrNull() {
    if (GetIt.I.isRegistered<TranslationCache>()) {
      return GetIt.I<TranslationCache>();
    }
    if (GetIt.I.isRegistered<PayloadConfig>()) {
      return _fallbackTranslationCache ??= TranslationCache();
    }
    return null;
  }

  String _translationFor(String tag, TranslationCache? cache) {
    return promptTagPresentationTranslation(
      tag,
      cache: cache,
      overrides: _translationOverrides,
      enabled: _showTranslations,
    );
  }

  PromptTranslationService? _translationServiceOrNull() {
    if (GetIt.I.isRegistered<PromptTranslationService>()) {
      return GetIt.I<PromptTranslationService>();
    }
    if (GetIt.I.isRegistered<PayloadConfig>()) {
      return DefaultPromptTranslationService(
        translationCache: _translationCacheOrNull() ?? TranslationCache(),
        settingsProvider: () => GetIt.I<PayloadConfig>().settings,
      );
    }
    return null;
  }

  PromptTagClassificationCache? _classificationCacheOrNull() {
    if (GetIt.I.isRegistered<PromptTagClassificationCache>()) {
      return GetIt.I<PromptTagClassificationCache>();
    }
    return null;
  }

  void _enqueueAutoTranslations(
    Iterable<String> tags,
    TranslationCache cache,
    PromptTranslationService service,
  ) {
    var added = false;
    for (final tag in tags) {
      if (tag.trim().isEmpty) {
        continue;
      }
      if (_translationFor(tag, cache).trim().isNotEmpty) {
        continue;
      }
      if (_autoTranslationPending.contains(tag)) {
        continue;
      }
      if (_autoTranslationMisses.contains(tag)) {
        continue;
      }
      _autoTranslationPending.add(tag);
      _PromptTagAutoTranslationQueue.instance
          .request(
            tag: tag,
            sourceLanguage: 'en',
            targetLanguage: 'zh',
            cache: cache,
            service: service,
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
    if (translated.isNotEmpty && _displayTags.contains(tag)) {
      _translationOverrides[tag] = translated;
    } else {
      _autoTranslationMisses.add(tag);
    }
    setState(() {});
  }

  void _startEditing() {
    setState(() {
      _editing = true;
      _controller.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  Future<void> _submitInput() async {
    if (_submittingInput) {
      return;
    }
    final added = _parseInput(_controller.text);
    if (added.isEmpty) {
      setState(() {
        _editing = false;
        _controller.clear();
      });
      return;
    }
    setState(() {
      _submittingInput = true;
    });

    final normalizedAdded = await _normalizeAddedTags(added);
    if (!mounted) {
      return;
    }
    final next = joinPromptTags([..._tags, ...normalizedAdded]);
    setState(() {
      _value = next;
      _editing = false;
      _submittingInput = false;
      _controller.clear();
    });
    widget.onChanged(next);
  }

  Future<List<String>> _normalizeAddedTags(List<String> tags) async {
    final service = _translationServiceOrNull();
    if (service == null) {
      return tags;
    }
    final normalized = <String>[];
    for (final tag in tags) {
      if (!_containsCjk(tag)) {
        normalized.add(tag);
        continue;
      }
      normalized.addAll(await _translateChineseTag(tag, service));
    }
    return normalized;
  }

  Future<List<String>> _translateChineseTag(
    String tag,
    PromptTranslationService service,
  ) async {
    try {
      final result = await service.translate(
        OnlineTranslationRequest(
          text: tag,
          sourceLanguage: 'zh',
          targetLanguage: 'en',
        ),
        preferCache: false,
      );
      final translated = result.text.trim();
      final parsed = _parseInput(translated);
      if (parsed.isNotEmpty) {
        final selectedTag = parsed.first.trim();
        if (selectedTag.isEmpty) {
          return [tag];
        }
        if (result.source == OnlineAiResultSource.online) {
          final cache = _translationCacheOrNull();
          cache?.setCached(
            tag,
            selectedTag,
            mode: 'zh2en',
            source: result.providerName ?? 'ai',
          );
          if (cache != null) {
            unawaited(PromptWorkshopBridge.saveTranslationCache(cache));
          }
        }
        return [selectedTag];
      }
    } catch (_) {
      // Preserve the user's original tag when online translation is unavailable.
    }
    return [tag];
  }

  void _deleteTag(int index) {
    final next = [..._tags]..removeAt(index);
    final value = joinPromptTags(next);
    _clearSharedSelection();
    setState(() {
      _value = value;
      _clearSelectionStateOnly();
    });
    widget.onChanged(value);
  }

  void _deleteSelectedTags() {
    final controller = widget.selectionController;
    if (controller != null) {
      final selected = controller.selectedIndexesFor(_sharedSelectionFieldId);
      if (selected.isEmpty) {
        return;
      }
      _deleteIndexes(selected);
      return;
    }
    if (_selectedIndexes.isEmpty) {
      return;
    }
    _deleteIndexes(_selectedIndexes.toSet());
  }

  void _deleteIndexes(Set<int> indexes) {
    if (indexes.isEmpty) {
      return;
    }
    final next = [
      for (final (index, tag) in _tags.indexed)
        if (!indexes.contains(index)) tag,
    ];
    final value = joinPromptTags(next);
    _clearSharedSelection();
    setState(() {
      _value = value;
      _clearSelectionStateOnly();
    });
    widget.onChanged(value);
  }

  void _clearAllTags() {
    if (_tags.isEmpty) {
      return;
    }
    _clearSharedSelection();
    setState(() {
      _value = '';
      _editing = false;
      _controller.clear();
      _clearSelectionStateOnly();
    });
    widget.onChanged('');
  }

  void _clearSharedSelection() {
    widget.selectionController?.clear();
  }

  List<String> _parseInput(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return const [];
    return _tagItemsForValue(trimmed)
        .map((tag) => tag.rawTag)
        .where((tag) => tag.trim().isNotEmpty)
        .toList(growable: false);
  }

  bool get _canDragTags => widget.enabled && !_editing;

  String get _sharedSelectionFieldId =>
      widget.selectionFieldId ?? _dragOriginId;

  Set<int> get _activeSelectedIndexes {
    return widget.selectionController
            ?.selectedIndexesFor(_sharedSelectionFieldId) ??
        _selectedIndexes;
  }

  int get _selectedCount {
    return widget.selectionController?.selectedCountFor(
          _sharedSelectionFieldId,
        ) ??
        _selectedIndexes.length;
  }

  bool _isSelected(int index) {
    return widget.selectionController
            ?.isSelected(_sharedSelectionFieldId, index) ??
        _selectedIndexes.contains(index);
  }

  bool _isPreviewed(int index) {
    return widget.selectionController
            ?.isPreviewed(_sharedSelectionFieldId, index) ??
        false;
  }

  bool _canAcceptDraggedTags(DragTargetDetails<PromptTagDragData> details) {
    return _canDragTags &&
        details.data.tags.any((tag) => tag.trim().isNotEmpty);
  }

  bool _isDragSuppressedForDoubleTap(int index) {
    return _doubleTapDragSuppressedIndex == index;
  }

  void _markTagTapForDoubleTapDragSuppression(int index) {
    _doubleTapDragSuppressionTimer?.cancel();
    _doubleTapDragSuppressedIndex = index;
    _doubleTapDragSuppressionTimer = Timer(kDoubleTapTimeout, () {
      if (!mounted || _doubleTapDragSuppressedIndex != index) {
        return;
      }
      setState(() {
        _doubleTapDragSuppressedIndex = null;
        _doubleTapDragSuppressionTimer = null;
      });
    });
  }

  PromptTagDragData _dragDataForIndex(int index) {
    final activeSelected = _activeSelectedIndexes;
    final indexes =
        activeSelected.contains(index) ? activeSelected.toSet() : <int>{index};
    return _dragDataForIndexes(indexes);
  }

  PromptTagDragData _dragDataForIndexes(Set<int> indexes) {
    final tags = promptTagsForIndexes(_tags, indexes);
    final controller = widget.selectionController;
    if (controller != null) {
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

  void _acceptDraggedTags(
    PromptTagDragData data, {
    int? insertIndex,
  }) {
    if (!_canDragTags || data.tags.every((tag) => tag.trim().isEmpty)) {
      return;
    }
    if (data.originId == _dragOriginId) {
      _moveDraggedIndexes(data.indexes, insertIndex);
      return;
    }
    final current = _tags;
    final incoming = data.tags
        .expand(_parseInput)
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
    final insertedIndexes = {
      for (var offset = 0; offset < incoming.length; offset++) target + offset,
    };
    setState(() {
      _value = value;
      if (widget.selectionController == null) {
        _selectedIndexes
          ..clear()
          ..addAll(insertedIndexes);
      }
      _clearSelectionInteractionStateOnly();
    });
    widget.onChanged(value);
    if (widget.removeDroppedTagsFromSource?.call(data) ?? true) {
      data.removeFromSource?.call(data.indexes);
    }
    widget.selectionController?.setFieldSelection(
      _sharedSelectionFieldId,
      insertedIndexes,
    );
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
    final value = joinPromptTags(next);
    final movedIndexes = {
      for (var offset = 0; offset < moving.length; offset++) target + offset,
    };
    setState(() {
      _value = value;
      if (widget.selectionController == null) {
        _selectedIndexes
          ..clear()
          ..addAll(movedIndexes);
      }
      _clearSelectionInteractionStateOnly();
    });
    widget.selectionController?.setFieldSelection(
      _sharedSelectionFieldId,
      movedIndexes,
    );
    widget.onChanged(value);
  }

  void _removeDraggedIndexes(Set<int> indexes) {
    if (!mounted || indexes.isEmpty) {
      return;
    }
    _deleteIndexes(indexes);
  }

  bool _containsCjk(String text) {
    return RegExp(r'[\u3400-\u9FFF\uF900-\uFAFF]').hasMatch(text);
  }

  void _handleSelectionPointerDown(PointerDownEvent event) {
    if (event.buttons != kPrimaryMouseButton || !widget.enabled || _editing) {
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
    _selectionStart = local;
    _selectionCurrent = local;
    _selectionMoved = false;
    _selectionAdditive = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    _selectionPreviewIndexes.clear();
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
    if (!moved && !_selectionMoved && _selectionPreviewIndexes.isEmpty) {
      _selectionCurrent = local;
      return;
    }
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
      final tappedIndex = _indexAt(_selectionLocalPosition(event.position));
      if (tappedIndex != null && _isSelected(tappedIndex)) {
        setState(() {
          _markTagTapForDoubleTapDragSuppression(tappedIndex);
        });
      }
      return;
    }
    final rect = _rectFrom(start, current);
    final tappedIndex = _indexAt(_selectionLocalPosition(event.position));
    if (_selectionMoved || tappedIndex != null) {
      _selectionFocusNode.requestFocus();
    }
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
        _markTagTapForDoubleTapDragSuppression(tappedIndex);
      } else {
        _clearSelectionInteractionStateOnly();
      }
      _selectionPreviewIndexes.clear();
      _selectionStart = null;
      _selectionCurrent = null;
      _selectionMoved = false;
      _selectionAdditive = false;
    });
  }

  void _handleSelectionPointerCancel(PointerCancelEvent event) {
    if (_selectionStart == null && _selectionCurrent == null) {
      return;
    }
    setState(_clearSelectionInteractionStateOnly);
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

  List<String> _selectedTags() {
    final tags = _tags;
    return [
      for (final index in _activeSelectedIndexes.toList()..sort())
        if (index >= 0 && index < tags.length) tags[index],
    ];
  }

  Future<void> _copyTags(List<String> tags) async {
    final text =
        tags.map((tag) => tag.trim()).where((tag) => tag.isNotEmpty).join(', ');
    if (text.isEmpty) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
  }

  Future<void> _showTagMenu(
    BuildContext context,
    Offset globalPosition,
    int index,
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
    final selectedCount = _selectedCount;
    final targetIndexes = _activeSelectedIndexes.toSet();
    final selectedRawTags = promptTagsForIndexes(_tags, targetIndexes);
    final selectedDisplayTags = promptTagsForIndexes(
      _displayTags,
      targetIndexes,
    );
    final clickedDisplayTag = _displayTags[index];
    final addToFilterRules = _filterRuleAdder();
    final choice = await showMenu<_PromptTagEditorMenuAction>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPosition.dx,
        globalPosition.dy,
        globalPosition.dx,
        globalPosition.dy,
      ),
      items: [
        PopupMenuItem(
          key: selectedCount > 1
              ? const ValueKey('prompt-tag-editor-delete-selected')
              : const ValueKey('prompt-tag-editor-delete-current'),
          value: _PromptTagEditorMenuAction.delete,
          child: Text(selectedCount > 1 ? '删除选中' : '删除标签'),
        ),
        const PopupMenuItem(
          value: _PromptTagEditorMenuAction.openDanbooru,
          child: Text('打开 Danbooru Wiki'),
        ),
        PopupMenuItem(
          key: const ValueKey('prompt-tag-editor-ai-retranslate'),
          value: _PromptTagEditorMenuAction.aiRetranslate,
          child: Text(_retranslateMenuLabel()),
        ),
        const PopupMenuItem(
          value: _PromptTagEditorMenuAction.editTag,
          child: Text('编辑标签'),
        ),
        PopupMenuItem(
          key: selectedCount > 1
              ? const ValueKey('prompt-tag-editor-copy-selected')
              : const ValueKey('prompt-tag-editor-copy-current'),
          value: _PromptTagEditorMenuAction.copy,
          child: Text(selectedCount > 1 ? '复制选中' : '复制标签'),
        ),
        if (addToFilterRules != null)
          const PopupMenuItem(
            key: ValueKey('prompt-tag-editor-add-to-filter-rules'),
            value: _PromptTagEditorMenuAction.addToFilterRules,
            child: Text('加入屏蔽库'),
          ),
      ],
    );
    if (!mounted || !context.mounted || choice == null) {
      return;
    }
    switch (choice) {
      case _PromptTagEditorMenuAction.openDanbooru:
        await _openDanbooruWiki(context, clickedDisplayTag);
      case _PromptTagEditorMenuAction.aiRetranslate:
        await _aiRetranslateTag(context, clickedDisplayTag);
      case _PromptTagEditorMenuAction.editTag:
        await _editTag(context, index);
      case _PromptTagEditorMenuAction.copy:
        await _copyTags(selectedRawTags);
      case _PromptTagEditorMenuAction.addToFilterRules:
        final added = await _addTagsToFilterRules(
          context,
          tags: selectedDisplayTags,
          addToFilterRules: addToFilterRules,
        );
        if (added && mounted) {
          _deleteIndexes(targetIndexes);
        }
      case _PromptTagEditorMenuAction.delete:
        _deleteIndexes(targetIndexes);
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
    final service = _translationServiceOrNull();
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
        _showSnack(context, '无法打开 Danbooru Wiki：$error');
      }
    }
  }

  Future<void> _aiRetranslateTag(BuildContext context, String tag) async {
    final translator = widget.onAiRetranslate;
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
    final cache = _translationCacheOrNull();
    if (cache != null && result.source == OnlineAiResultSource.online) {
      cache.setCached(
        tag,
        translated,
        source: result.providerName ?? 'ai',
      );
      unawaited(PromptWorkshopBridge.saveTranslationCache(cache));
    }
    setState(() {
      _translationOverrides[tag] = translated;
    });
    _showSnack(
      context,
      result.source == OnlineAiResultSource.localFallback
          ? '已使用本地缓存翻译'
          : '已重译标签',
    );
  }

  Future<OnlineTranslationResult> _defaultAiRetranslate(String tag) async {
    final service = _translationServiceOrNull();
    if (service != null) {
      return _PromptTagAutoTranslationQueue.instance.request(
        tag: tag,
        sourceLanguage: 'en',
        targetLanguage: 'zh',
        cache: _translationCacheOrNull() ?? TranslationCache(),
        service: service,
        preferCache: false,
      );
    }
    final local = _translationCacheOrNull()?.translate(tag).text.trim() ?? '';
    return OnlineTranslationResult(
      text: local,
      source: local.isEmpty
          ? OnlineAiResultSource.emptyFallback
          : OnlineAiResultSource.localFallback,
      providerName: local.isEmpty ? null : 'translation-cache',
    );
  }

  Future<void> _editTag(BuildContext context, int index) async {
    final tags = _tags;
    final items = _tagItems;
    if (index < 0 || index >= tags.length || index >= items.length) {
      return;
    }
    final item = items[index];
    final tagController = TextEditingController(text: item.displayLabel);
    final weightController = TextEditingController(
      text: item.weight == null ? '' : _formatWeightText(item.weight!),
    );
    ({String tag, String weight}) resultFromControllers() {
      return (tag: tagController.text, weight: weightController.text);
    }

    final nextEdit = await showDialog<({String tag, String weight})>(
      context: context,
      builder: (context) {
        return AlertDialog(
          key: const ValueKey('prompt-tag-editor-edit-tag-dialog'),
          backgroundColor: StudioTokens.surface2,
          title: const Text('编辑标签'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  key: const ValueKey('prompt-tag-editor-edit-tag-field'),
                  controller: tagController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: '标签原文',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) =>
                      Navigator.of(context).pop(resultFromControllers()),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('prompt-tag-editor-edit-weight-field'),
                  controller: weightController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: '权重',
                    hintText: '留空或 1 表示普通权重',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) =>
                      Navigator.of(context).pop(resultFromControllers()),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              key: const ValueKey('prompt-tag-editor-edit-tag-save'),
              onPressed: () =>
                  Navigator.of(context).pop(resultFromControllers()),
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
    if (!mounted || nextEdit == null) {
      return;
    }
    final parsed = _parseInput(nextEdit.tag);
    if (!mounted || parsed.isEmpty) {
      return;
    }
    final weightText = nextEdit.weight.trim();
    final weight = weightText.isEmpty ? 1.0 : double.tryParse(weightText);
    if (weight == null || !weight.isFinite) {
      if (context.mounted) {
        _showSnack(context, '请输入数字权重');
      }
      return;
    }
    final normalized = await _normalizeAddedTags(parsed);
    if (!mounted || normalized.isEmpty) {
      return;
    }
    final replacement = weight == 1.0
        ? normalized.first
        : _weightedTagValue(normalized.first, weight);
    final updated = [...tags]..[index] = replacement;
    final value = joinPromptTags(updated);
    setState(() {
      _value = value;
      _clearSelectionStateOnly();
    });
    widget.onChanged(value);
  }

  Future<bool> _addTagsToFilterRules(
    BuildContext context, {
    required List<String> tags,
    required PromptTagFilterRuleAdder? addToFilterRules,
  }) async {
    if (addToFilterRules == null) {
      return false;
    }
    final cleanTags = tags
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toList(growable: false);
    if (cleanTags.isEmpty) {
      return false;
    }
    final target = await _pickFilterRuleTarget(context, cleanTags.length);
    if (!mounted || !context.mounted || target == null) {
      return false;
    }
    await addToFilterRules(cleanTags, target);
    if (context.mounted) {
      _showSnack(context, '已加入${_filterRuleTargetLabel(target)}');
    }
    return true;
  }

  Future<PromptTagFilterRuleTarget?> _pickFilterRuleTarget(
    BuildContext context,
    int count,
  ) {
    return showDialog<PromptTagFilterRuleTarget>(
      context: context,
      builder: (context) {
        return AlertDialog(
          key: const ValueKey('prompt-tag-editor-filter-target-dialog'),
          backgroundColor: StudioTokens.surface2,
          title: Text(count > 1 ? '加入屏蔽库（$count 个标签）' : '加入屏蔽库'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _PromptTagEditorFilterTargetOption(
                key: const ValueKey('prompt-tag-editor-filter-target-delete'),
                icon: Icons.block_outlined,
                title: '删除关键词',
                subtitle: '解析时直接移除这些标签',
                onTap: () => Navigator.of(context).pop(
                  PromptTagFilterRuleTarget.deleteKeywords,
                ),
              ),
              const SizedBox(height: 8),
              _PromptTagEditorFilterTargetOption(
                key: const ValueKey('prompt-tag-editor-filter-target-strong'),
                icon: Icons.shield_outlined,
                title: '强屏蔽关键词',
                subtitle: '更强的过滤规则，适合必须屏蔽的标签',
                onTap: () => Navigator.of(context).pop(
                  PromptTagFilterRuleTarget.strongFilterKeywords,
                ),
              ),
              const SizedBox(height: 8),
              _PromptTagEditorFilterTargetOption(
                key: const ValueKey('prompt-tag-editor-filter-target-replace'),
                icon: Icons.swap_horiz,
                title: '替换规则源',
                subtitle: '先加入替换源，目标文本之后可在规则库里编辑',
                onTap: () => Navigator.of(context).pop(
                  PromptTagFilterRuleTarget.replaceSource,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
          ],
        );
      },
    );
  }

  String _filterRuleTargetLabel(PromptTagFilterRuleTarget target) {
    return switch (target) {
      PromptTagFilterRuleTarget.deleteKeywords => '删除关键词',
      PromptTagFilterRuleTarget.strongFilterKeywords => '强屏蔽关键词',
      PromptTagFilterRuleTarget.replaceSource => '替换规则源',
      PromptTagFilterRuleTarget.scriptScopedBlockWords => '本剧本屏蔽',
    };
  }

  String _weightedTagValue(String tag, double weight) {
    return PromptTagProcessor.formatInlineWeightTag(tag, weight);
  }

  String _formatWeightText(double weight) {
    return weight.toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), '');
  }

  void _showSnack(BuildContext context, String message) {
    if (!context.mounted) {
      return;
    }
    if (Scaffold.maybeOf(context) == null) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

enum _PromptTagEditorMenuAction {
  openDanbooru,
  aiRetranslate,
  editTag,
  copy,
  addToFilterRules,
  delete,
}

class _PromptTagEditorItem {
  final int index;
  final String rawTag;
  final String displayLabel;
  final double? weight;
  final String? weightLabel;
  final PromptTagGroup? group;

  const _PromptTagEditorItem({
    required this.index,
    required this.rawTag,
    required this.displayLabel,
    this.weight,
    this.weightLabel,
    this.group,
  });

  _PromptTagEditorItem copyWith({
    PromptTagGroup? group,
  }) {
    return _PromptTagEditorItem(
      index: index,
      rawTag: rawTag,
      displayLabel: displayLabel,
      weight: weight,
      weightLabel: weightLabel,
      group: group ?? this.group,
    );
  }
}

class _PromptTagEditorFilterTargetOption extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _PromptTagEditorFilterTargetOption({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  State<_PromptTagEditorFilterTargetOption> createState() =>
      _PromptTagEditorFilterTargetOptionState();
}

class _PromptTagEditorFilterTargetOptionState
    extends State<_PromptTagEditorFilterTargetOption> {
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
        width: double.infinity,
        padding: const EdgeInsets.all(10),
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
            Icon(widget.icon, color: StudioTokens.primary, size: 18),
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

class _PromptTagEditorControls extends StatelessWidget {
  final bool dense;
  final bool showTranslations;
  final bool groupedLayout;
  final bool canClearTags;
  final VoidCallback onToggleTranslations;
  final VoidCallback onToggleLayout;
  final VoidCallback onClearTags;

  const _PromptTagEditorControls({
    required this.dense,
    required this.showTranslations,
    required this.groupedLayout,
    required this.canClearTags,
    required this.onToggleTranslations,
    required this.onToggleLayout,
    required this.onClearTags,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      alignment: WrapAlignment.end,
      children: [
        _PromptTagEditorControlButton(
          key: const ValueKey('prompt-tag-editor-translation-toggle'),
          icon:
              showTranslations ? Icons.translate_outlined : Icons.code_outlined,
          label: showTranslations ? '译文' : '原文',
          tooltip: showTranslations ? '显示原文标签' : '显示翻译标签',
          dense: dense,
          selected: showTranslations,
          onPressed: onToggleTranslations,
        ),
        _PromptTagEditorControlButton(
          key: const ValueKey('prompt-tag-editor-layout-toggle'),
          icon: groupedLayout
              ? Icons.account_tree_outlined
              : Icons.format_align_left_outlined,
          label: groupedLayout ? '分块' : '原序',
          tooltip: groupedLayout ? '切换为原始顺序' : '切换为分块显示',
          dense: dense,
          selected: groupedLayout,
          onPressed: onToggleLayout,
        ),
        _PromptTagEditorControlButton(
          key: const ValueKey('prompt-tag-editor-clear-all'),
          icon: Icons.delete_sweep_outlined,
          label: '清空',
          tooltip: '清空全部标签',
          dense: dense,
          selected: false,
          onPressed: canClearTags ? onClearTags : null,
        ),
      ],
    );
  }
}

class _PromptTagEditorControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String tooltip;
  final bool dense;
  final bool selected;
  final VoidCallback? onPressed;

  const _PromptTagEditorControlButton({
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

class _EditablePromptTagChip extends StatelessWidget {
  final int index;
  final String rawLabel;
  final String? weightLabel;
  final double? weight;
  final String translation;
  final PromptTagCategory category;
  final bool dense;
  final bool enabled;
  final PromptTagEditorHighlight? highlight;
  final bool previewed;
  final bool selected;
  final VoidCallback? onDeleted;
  final VoidCallback? onDoubleTap;
  final GestureTapDownCallback? onSecondaryTapDown;

  const _EditablePromptTagChip({
    required this.index,
    required this.rawLabel,
    this.weightLabel,
    this.weight,
    required this.translation,
    required this.category,
    required this.dense,
    required this.enabled,
    this.highlight,
    required this.previewed,
    required this.selected,
    required this.onDeleted,
    this.onDoubleTap,
    this.onSecondaryTapDown,
  });

  @override
  Widget build(BuildContext context) {
    final trimmedTranslation = translation.trim();
    final hasTranslation = trimmedTranslation.isNotEmpty;
    final weightText = weightLabel?.trim();
    final hasWeight = weightText != null && weightText.isNotEmpty;
    final isNegativeWeight = (weight ?? 0) < 0;
    final weightColor =
        isNegativeWeight ? StudioTokens.danger : StudioTokens.primary;
    final weightBackgroundColor = weightColor.withAlpha(
      isNegativeWeight ? 30 : 28,
    );
    final weightBorderColor = weightColor.withAlpha(
      isNegativeWeight ? 150 : 120,
    );
    final categoryColor = promptTagCategoryColor(category);
    final primaryStyle = Theme.of(context).textTheme.labelMedium?.copyWith(
          color: enabled ? StudioTokens.textPrimary : StudioTokens.textMuted,
          fontWeight: FontWeight.w700,
        );
    final secondaryStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: StudioTokens.textSecondary,
        );
    final highlighted = highlight != null;
    final borderColor = selected
        ? StudioTokens.primary
        : highlighted
            ? StudioTokens.info
            : previewed
                ? StudioTokens.info
                : StudioTokens.borderStrong;
    final backgroundColor = selected
        ? const Color(0xFF22200B)
        : highlighted
            ? const Color(0xFF1F2430)
            : previewed
                ? const Color(0xFF1F2430)
                : StudioTokens.surface3;
    final chipBody = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      key: ValueKey('prompt-tag-editor-chip-$index'),
      constraints: const BoxConstraints(maxWidth: 280),
      clipBehavior: Clip.antiAlias,
      padding: EdgeInsets.zero,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: StudioTokens.radiusTag,
        border: Border.all(color: borderColor),
        boxShadow: selected
            ? const [
                BoxShadow(
                  color: Color(0xCCFFE500),
                  blurRadius: 0,
                  spreadRadius: 1,
                ),
                BoxShadow(
                  color: Color(0x40000000),
                  blurRadius: 20,
                  offset: Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: DecoratedBox(
              key: ValueKey('prompt-tag-editor-chip-marker-$index'),
              decoration: BoxDecoration(
                color: categoryColor,
                borderRadius: StudioTokens.radiusTagStripe,
              ),
              child: const SizedBox(width: 3),
            ),
          ),
          Padding(
            padding: EdgeInsets.only(
              left: dense ? 12 : 14,
              right: 2,
              top: dense ? 3 : 5,
              bottom: dense ? 3 : 5,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              rawLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: primaryStyle,
                            ),
                          ),
                          if (hasWeight) ...[
                            const SizedBox(width: 6),
                            DecoratedBox(
                              key: ValueKey(
                                'prompt-tag-editor-chip-weight-$index',
                              ),
                              decoration: BoxDecoration(
                                color: weightBackgroundColor,
                                borderRadius: StudioTokens.radiusBadge,
                                border: Border.all(
                                  color: weightBorderColor,
                                ),
                              ),
                              child: Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: dense ? 4 : 5,
                                  vertical: dense ? 1 : 2,
                                ),
                                child: Text(
                                  weightText,
                                  maxLines: 1,
                                  overflow: TextOverflow.fade,
                                  softWrap: false,
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelSmall
                                      ?.copyWith(
                                        color: weightColor,
                                        fontWeight: FontWeight.w900,
                                      ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (hasTranslation) ...[
                        SizedBox(height: dense ? 1 : 2),
                        Text(
                          trimmedTranslation,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: secondaryStyle,
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  key: ValueKey('prompt-tag-editor-delete-$index'),
                  tooltip: '删除标签',
                  icon: const Icon(Icons.close),
                  iconSize: dense ? 15 : 16,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints.tightFor(
                    width: dense ? 32 : 36,
                    height: dense ? 32 : 36,
                  ),
                  color: StudioTokens.textMuted,
                  onPressed: onDeleted,
                ),
              ],
            ),
          ),
        ],
      ),
    );
    final chip = Stack(
      clipBehavior: Clip.none,
      children: [
        chipBody,
        if (selected)
          Positioned(
            top: -7,
            right: -6,
            child: DecoratedBox(
              key: ValueKey('prompt-tag-editor-chip-check-$index'),
              decoration: const BoxDecoration(
                color: StudioTokens.primary,
                shape: BoxShape.circle,
              ),
              child: const SizedBox(
                width: 18,
                height: 18,
                child: Center(
                  child: Icon(
                    Icons.check,
                    size: 12,
                    color: StudioTokens.onPrimary,
                  ),
                ),
              ),
            ),
          ),
        if (highlighted)
          Positioned(
            top: -7,
            left: -6,
            child: Tooltip(
              message: highlight!.tooltip,
              child: DecoratedBox(
                key: ValueKey('prompt-tag-editor-cache-hit-$rawLabel'),
                decoration: const BoxDecoration(
                  color: StudioTokens.info,
                  shape: BoxShape.circle,
                ),
                child: const SizedBox(
                  width: 18,
                  height: 18,
                  child: Center(
                    child: Icon(
                      Icons.cached_outlined,
                      size: 11,
                      color: StudioTokens.textPrimary,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTap: onDoubleTap,
        onSecondaryTapDown: onSecondaryTapDown,
        child: chip,
      ),
    );
  }
}
