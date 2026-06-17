import 'package:flutter/material.dart';
import 'package:novel_studio/data/studio/models/studio_asset_capture.dart';
import 'package:novel_studio/ui/studio_core/theme/studio_tokens.dart';
import 'package:novel_studio/ui/studio_core/widgets/studio_button.dart';
import 'package:novel_studio/ui/studio_core/widgets/studio_chip.dart';

const _createNewTargetValue = '__save_asset_create_new__';

class SaveAssetConfirmBar extends StatelessWidget {
  final StudioAssetCaptureDraft draft;
  final StudioAssetCapturePlan plan;
  final String name;
  final String note;
  final String? selectedTargetId;
  final bool forceNew;
  final bool isSaving;
  final ValueChanged<String> onNameChanged;
  final ValueChanged<String> onNoteChanged;
  final ValueChanged<StudioAssetCaptureKind> onKindChanged;
  final ValueChanged<String?> onTargetChanged;
  final ValueChanged<bool> onForceNewChanged;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  const SaveAssetConfirmBar({
    super.key,
    required this.draft,
    required this.plan,
    required this.name,
    required this.note,
    this.selectedTargetId,
    this.forceNew = false,
    this.isSaving = false,
    required this.onNameChanged,
    required this.onNoteChanged,
    required this.onKindChanged,
    required this.onTargetChanged,
    required this.onForceNewChanged,
    required this.onCancel,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    final kinds = draft.availableKinds.isEmpty
        ? <StudioAssetCaptureKind>[draft.kind]
        : draft.availableKinds;
    final candidates = plan.candidates;

    return Material(
      color: Colors.transparent,
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 620;
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const StudioChip(
                        label: '素材',
                        icon: Icons.bookmark_add_outlined,
                        selected: true,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '保存素材',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(
                                    color: StudioTokens.textPrimary,
                                    fontWeight: FontWeight.w900,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '确认素材类型、名称和备注后写入素材库。',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: StudioTokens.textSecondary,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  if (compact)
                    Column(
                      children: [
                        _KindField(
                          kinds: kinds,
                          draft: draft,
                          isSaving: isSaving,
                          onKindChanged: onKindChanged,
                        ),
                        const SizedBox(height: 12),
                        _NameField(
                          name: name,
                          isSaving: isSaving,
                          onNameChanged: onNameChanged,
                        ),
                      ],
                    )
                  else
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: _KindField(
                            kinds: kinds,
                            draft: draft,
                            isSaving: isSaving,
                            onKindChanged: onKindChanged,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 5,
                          child: _NameField(
                            name: name,
                            isSaving: isSaving,
                            onNameChanged: onNameChanged,
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('save-asset-note-field'),
                    initialValue: note,
                    enabled: !isSaving,
                    minLines: 2,
                    maxLines: 4,
                    decoration: _inputDecoration('备注'),
                    onChanged: onNoteChanged,
                  ),
                  if (candidates.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      key: const Key('save-asset-target-field'),
                      initialValue: forceNew
                          ? _createNewTargetValue
                          : selectedTargetId ?? _createNewTargetValue,
                      isExpanded: true,
                      decoration: _inputDecoration('合并目标'),
                      items: [
                        const DropdownMenuItem<String>(
                          value: _createNewTargetValue,
                          child: Text('新建素材'),
                        ),
                        for (final candidate in candidates)
                          DropdownMenuItem<String>(
                            value: candidate.id,
                            child: Text(
                              candidate.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: isSaving
                          ? null
                          : (value) {
                              final forceNew = value == _createNewTargetValue;
                              onTargetChanged(forceNew ? null : value);
                              onForceNewChanged(forceNew);
                            },
                    ),
                  ],
                  const SizedBox(height: 18),
                  DecoratedBox(
                    decoration: const BoxDecoration(
                      border: Border(
                        top: BorderSide(color: StudioTokens.cardOutline),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: Wrap(
                        alignment: WrapAlignment.end,
                        spacing: 10,
                        runSpacing: 8,
                        children: [
                          StudioButton(
                            key: const Key('save-asset-cancel'),
                            label: '取消',
                            icon: Icons.close,
                            tone: StudioButtonTone.ghost,
                            onPressed: isSaving ? null : onCancel,
                          ),
                          StudioButton(
                            key: const Key('save-asset-confirm'),
                            label: isSaving ? '保存中' : '保存',
                            icon: isSaving ? Icons.hourglass_top : Icons.check,
                            onPressed: isSaving ? null : onConfirm,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _KindField extends StatelessWidget {
  final List<StudioAssetCaptureKind> kinds;
  final StudioAssetCaptureDraft draft;
  final bool isSaving;
  final ValueChanged<StudioAssetCaptureKind> onKindChanged;

  const _KindField({
    required this.kinds,
    required this.draft,
    required this.isSaving,
    required this.onKindChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<StudioAssetCaptureKind>(
      key: const Key('save-asset-kind-field'),
      initialValue: draft.kind,
      isExpanded: true,
      decoration: _inputDecoration('类型'),
      items: [
        for (final kind in kinds)
          DropdownMenuItem(
            value: kind,
            child: Text(_assetKindLabel(kind)),
          ),
      ],
      onChanged: isSaving
          ? null
          : (value) {
              if (value == null) return;
              onKindChanged(value);
            },
    );
  }
}

class _NameField extends StatelessWidget {
  final String name;
  final bool isSaving;
  final ValueChanged<String> onNameChanged;

  const _NameField({
    required this.name,
    required this.isSaving,
    required this.onNameChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      key: const Key('save-asset-name-field'),
      initialValue: name,
      enabled: !isSaving,
      decoration: _inputDecoration('名称'),
      onChanged: onNameChanged,
    );
  }
}

String _assetKindLabel(StudioAssetCaptureKind kind) {
  return switch (kind) {
    StudioAssetCaptureKind.artistChain => '画师串',
    StudioAssetCaptureKind.character => '角色',
    StudioAssetCaptureKind.outfit => '服装',
  };
}

InputDecoration _inputDecoration(String label) {
  return InputDecoration(
    labelText: label,
    isDense: true,
    filled: true,
    fillColor: StudioTokens.surface1,
    border: OutlineInputBorder(
      borderRadius: StudioTokens.radiusSlot,
      borderSide: const BorderSide(color: StudioTokens.border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: StudioTokens.radiusSlot,
      borderSide: const BorderSide(color: StudioTokens.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: StudioTokens.radiusSlot,
      borderSide: const BorderSide(color: StudioTokens.primary),
    ),
  );
}
