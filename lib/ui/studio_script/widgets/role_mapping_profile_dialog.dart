import 'package:flutter/material.dart';
import 'package:novel_studio/data/studio/models/script_recast.dart';
import 'package:novel_studio/data/studio/models/script_role_mapping_profile.dart';
import 'package:novel_studio/data/studio/tools/prompt_tag_classifier.dart';
import 'package:novel_studio/data/studio/tools/prompt_tag_processor.dart';
import 'package:novel_studio/ui/studio_core/widgets/prompt_tag_chip.dart';
import 'package:novel_studio/ui/studio_core/widgets/prompt_tag_display.dart';
import 'package:novel_studio/ui/studio_core/widgets/prompt_tag_editor.dart';
import 'package:novel_studio/ui/studio_script/view_models/studio_script_viewmodel.dart';

Future<void> showRoleMappingProfileManagerDialog(
  BuildContext context, {
  required StudioScriptViewModel viewModel,
  required String sourceRoleId,
}) async {
  await viewModel.ensureRoleMappingProfilesLoaded();
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (context) => _RoleMappingProfileManagerDialog(
      viewModel: viewModel,
      sourceRoleId: sourceRoleId,
    ),
  );
}

Future<bool> showRoleMappingProfileApplyPreviewDialog(
  BuildContext context, {
  required StudioScriptViewModel viewModel,
  required RoleMappingProfile profile,
  required String sourceRoleId,
}) async {
  final preview = viewModel.previewRoleMappingProfile(
    profileId: profile.id,
    sourceRoleId: sourceRoleId,
  );
  if (!context.mounted) return false;
  return await showDialog<bool>(
        context: context,
        builder: (context) => _RoleMappingProfileApplyDialog(
          viewModel: viewModel,
          profile: profile,
          sourceRoleId: sourceRoleId,
          preview: preview,
        ),
      ) ??
      false;
}

class _RoleMappingProfileManagerDialog extends StatefulWidget {
  final StudioScriptViewModel viewModel;
  final String sourceRoleId;

  const _RoleMappingProfileManagerDialog({
    required this.viewModel,
    required this.sourceRoleId,
  });

  @override
  State<_RoleMappingProfileManagerDialog> createState() =>
      _RoleMappingProfileManagerDialogState();
}

class _RoleMappingProfileManagerDialogState
    extends State<_RoleMappingProfileManagerDialog> {
  final TextEditingController _searchController = TextEditingController();
  String? _selectedProfileId;

  StudioScriptViewModel get viewModel => widget.viewModel;
  StudioScriptRoleReplacementItem? get sourceRole =>
      viewModel.roleReplacementMappings
          .where((role) => role.sourceRoleId == widget.sourceRoleId)
          .firstOrNull;

  @override
  void initState() {
    super.initState();
    _selectedProfileId = viewModel.roleMappingProfiles.firstOrNull?.id;
    _searchController.addListener(_handleSearchChanged);
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_handleSearchChanged)
      ..dispose();
    super.dispose();
  }

  void _handleSearchChanged() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        width: 1120,
        height: 760,
        child: AnimatedBuilder(
          animation: viewModel,
          builder: (context, _) {
            _repairSelections();
            return LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 780;
                return Column(
                  children: [
                    _buildHeader(context),
                    const Divider(height: 1),
                    Expanded(
                      child: compact
                          ? _buildCompactBody(context)
                          : Row(
                              children: [
                                SizedBox(
                                  width: 330,
                                  child: _buildProfileList(context),
                                ),
                                const VerticalDivider(width: 1),
                                Expanded(child: _buildDetail(context)),
                              ],
                            ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final roleLabel = sourceRole?.sourceLabel ?? '当前角色';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 14),
      child: Row(
        children: [
          const Icon(Icons.bookmarks_outlined),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '全局角色档案',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text(
                  '当前栏位：$roleLabel · 全局共用 '
                  '${viewModel.roleMappingProfiles.length} 个档案',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '关闭',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactBody(BuildContext context) {
    if (_selectedProfileId == null) {
      return _buildProfileList(context);
    }
    return Column(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _selectedProfileId = null),
            icon: const Icon(Icons.arrow_back),
            label: const Text('返回全局角色档案'),
          ),
        ),
        Expanded(child: _buildDetail(context)),
      ],
    );
  }

  Widget _buildProfileList(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final profiles = [
      for (final profile in viewModel.roleMappingProfiles)
        if (query.isEmpty ||
            profile.name.toLowerCase().contains(query) ||
            profile.targetCharacterNameSnapshot.toLowerCase().contains(query))
          profile,
    ];
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: '搜索全局角色档案',
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const ValueKey('role-mapping-profile-create'),
              onPressed:
                  sourceRole == null ? null : () => _createProfile(context),
              icon: const Icon(Icons.add),
              label: const Text('从此角色栏位新建'),
            ),
          ),
          if (viewModel.roleMappingProfileError != null) ...[
            const SizedBox(height: 10),
            _MessageCard(
              color: Theme.of(context).colorScheme.errorContainer,
              text: viewModel.roleMappingProfileStatus,
            ),
          ],
          const SizedBox(height: 10),
          Expanded(
            child: profiles.isEmpty
                ? const Center(child: Text('暂无匹配的全局角色档案'))
                : ListView.separated(
                    itemCount: profiles.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final profile = profiles[index];
                      final selected = profile.id == _selectedProfileId;
                      return ListTile(
                        key: ValueKey('role-mapping-profile-${profile.id}'),
                        selected: selected,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        leading: const CircleAvatar(
                          child: Icon(Icons.person_outline),
                        ),
                        title: Text(profile.name),
                        subtitle: Text(
                          '${profile.blocks.length} 个映射组'
                          '${profile.targetCharacterNameSnapshot.isEmpty ? '' : ' · ${profile.targetCharacterNameSnapshot}'}',
                        ),
                        onTap: () {
                          setState(() {
                            _selectedProfileId = profile.id;
                          });
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetail(BuildContext context) {
    final profile = viewModel.roleMappingProfileById(_selectedProfileId);
    if (profile == null) {
      return const Center(
        child: Text('选择一个全局角色档案查看详情'),
      );
    }
    final linkedCharacterExists = profile.targetCharacterId == null ||
        viewModel.characterOptions
            .any((character) => character.id == profile.targetCharacterId);
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.name,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      profile.targetCharacterId != null &&
                              !linkedCharacterExists
                          ? '关联失效：${profile.targetCharacterNameSnapshot.isEmpty ? profile.targetCharacterId : profile.targetCharacterNameSnapshot}（仍可套用文字）'
                          : profile.targetCharacterNameSnapshot.isEmpty
                              ? '未关联素材角色'
                              : '关联素材：${profile.targetCharacterNameSnapshot}',
                      style: profile.targetCharacterId != null &&
                              !linkedCharacterExists
                          ? TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            )
                          : null,
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                key: const ValueKey('role-mapping-profile-edit'),
                onPressed: () => _editProfile(context, profile),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('编辑详情'),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<String>(
                tooltip: '更多操作',
                onSelected: (value) {
                  if (value == 'duplicate') {
                    _duplicateProfile(context, profile);
                  } else if (value == 'delete') {
                    _deleteProfile(context, profile);
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: 'duplicate',
                    child: Text('复制档案'),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text('删除档案'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          _DetailSurface(
            title: '目标身份',
            child: _profilePromptDisplay(
              viewModel,
              key: const ValueKey('role-mapping-profile-identity-display'),
              text: profile.targetIdentityPrompt,
              emptyText: '未设置',
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: profile.blocks.isEmpty
                ? const Center(child: Text('该全局角色档案还没有有效映射组'))
                : ListView(
                    children: [
                      for (final layer in profile.effectiveLayers)
                        if (layer.blocks.isNotEmpty) ...[
                          _ProfileLayerHeader(layer: layer),
                          const SizedBox(height: 7),
                          for (final block in layer.blocks) ...[
                            _ProfileBlockSummary(
                              viewModel: viewModel,
                              block: block,
                            ),
                            const SizedBox(height: 10),
                          ],
                        ],
                    ],
                  ),
          ),
          const SizedBox(height: 12),
          _buildApplyControls(context, profile),
        ],
      ),
    );
  }

  Widget _buildApplyControls(
    BuildContext context,
    RoleMappingProfile profile,
  ) {
    return Row(
      children: [
        Expanded(
          child: Container(
            key: const ValueKey('role-mapping-profile-fixed-target'),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.my_location_outlined, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '套用到：${sourceRole?.sourceLabel ?? '当前栏位已不存在'}',
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        FilledButton.icon(
          key: const ValueKey('role-mapping-profile-preview'),
          onPressed: sourceRole == null
              ? null
              : () => _showApplyPreview(
                    context,
                    profile: profile,
                    sourceRoleId: widget.sourceRoleId,
                  ),
          icon: const Icon(Icons.preview_outlined),
          label: const Text('预览并套用'),
        ),
      ],
    );
  }

  Future<void> _createProfile(BuildContext context) async {
    if (sourceRole == null) return;
    final name = await _askForName(
      context,
      title: '新建全局角色档案',
      label: '档案名称',
    );
    if (name == null || !context.mounted) return;
    try {
      final profile = await viewModel.createRoleMappingProfile(
        name: name,
        sourceRoleId: widget.sourceRoleId,
      );
      if (!mounted) return;
      setState(() => _selectedProfileId = profile.id);
    } catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }

  Future<void> _editProfile(
    BuildContext context,
    RoleMappingProfile profile,
  ) async {
    final updated = await showDialog<RoleMappingProfile>(
      context: context,
      builder: (context) => _RoleMappingProfileEditDialog(
        profile: profile,
        viewModel: viewModel,
      ),
    );
    if (updated == null || !context.mounted) return;
    try {
      await viewModel.updateRoleMappingProfile(updated);
    } catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }

  Future<void> _duplicateProfile(
    BuildContext context,
    RoleMappingProfile profile,
  ) async {
    try {
      final duplicate = await viewModel.duplicateRoleMappingProfile(profile.id);
      if (!mounted) return;
      setState(() => _selectedProfileId = duplicate.id);
    } catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }

  Future<void> _deleteProfile(
    BuildContext context,
    RoleMappingProfile profile,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除全局角色档案？'),
        content: Text(
          '将永久删除“${profile.name}”。已经写入剧本的可见映射不会被删除。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await viewModel.deleteRoleMappingProfile(profile.id);
      if (!mounted) return;
      setState(() {
        _selectedProfileId = viewModel.roleMappingProfiles.firstOrNull?.id;
      });
    } catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }

  Future<void> _showApplyPreview(
    BuildContext context, {
    required RoleMappingProfile profile,
    required String sourceRoleId,
  }) async {
    try {
      final preview = viewModel.previewRoleMappingProfile(
        profileId: profile.id,
        sourceRoleId: sourceRoleId,
      );
      if (!context.mounted) return;
      final applied = await showDialog<bool>(
        context: context,
        builder: (context) => _RoleMappingProfileApplyDialog(
          viewModel: viewModel,
          profile: profile,
          sourceRoleId: sourceRoleId,
          preview: preview,
        ),
      );
      if (applied == true && context.mounted) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }

  void _repairSelections() {
    if (_selectedProfileId != null &&
        viewModel.roleMappingProfileById(_selectedProfileId) == null) {
      _selectedProfileId = viewModel.roleMappingProfiles.firstOrNull?.id;
    }
  }
}

class _RoleMappingProfileApplyDialog extends StatefulWidget {
  final StudioScriptViewModel viewModel;
  final RoleMappingProfile profile;
  final String sourceRoleId;
  final RoleMappingApplyPreview preview;

  const _RoleMappingProfileApplyDialog({
    required this.viewModel,
    required this.profile,
    required this.sourceRoleId,
    required this.preview,
  });

  @override
  State<_RoleMappingProfileApplyDialog> createState() =>
      _RoleMappingProfileApplyDialogState();
}

class _RoleMappingProfileApplyDialogState
    extends State<_RoleMappingProfileApplyDialog> {
  late final Map<String, bool> _enabledByBlockId;
  late final Map<String, Set<String>> _termIdsByBlockId;
  late final Map<String, String> _targetLayerIdByProfileLayerId;
  final Map<String, String> _anchorTermIdsByBlockId = {};
  late bool _applyIdentity;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _targetLayerIdByProfileLayerId = {
      for (final entry in widget.preview.layerEntries)
        entry.layer.id:
            entry.selectedByDefault ? entry.matchedCurrentLayerId : '',
    };
    _enabledByBlockId = {
      for (final entry in widget.preview.entries)
        entry.block.id: entry.selectedByDefault &&
            (_targetLayerIdByProfileLayerId[entry.profileLayerId]?.isNotEmpty ??
                false),
    };
    _termIdsByBlockId = {
      for (final entry in widget.preview.entries)
        entry.block.id: entry.selectedTermIds.toSet(),
    };
    _applyIdentity = widget.profile.targetIdentityPrompt.trim().isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final terms =
        widget.viewModel.roleMappingProfileAvailableTerms(widget.sourceRoleId);
    final termById = {for (final term in terms) term.id: term};
    final role = widget.viewModel.roleReplacementMappings
        .where((entry) => entry.sourceRoleId == widget.sourceRoleId)
        .firstOrNull;
    final screenSize = MediaQuery.sizeOf(context);
    final dialogWidth = (screenSize.width - 48).clamp(360.0, 920.0).toDouble();
    final dialogHeight =
        (screenSize.height - 160).clamp(460.0, 700.0).toDouble();
    final automaticCount = widget.preview.entries
        .where(
          (entry) =>
              entry.status == RoleMappingApplyPreviewStatus.matched ||
              entry.status == RoleMappingApplyPreviewStatus.conflict,
        )
        .length;
    final reviewCount = widget.preview.entries
        .where(
          (entry) => entry.status == RoleMappingApplyPreviewStatus.ambiguous,
        )
        .length;
    final sameCount = widget.preview.entries
        .where((entry) => entry.status == RoleMappingApplyPreviewStatus.same)
        .length;
    final skippedCount = widget.preview.entries
        .where(
            (entry) => entry.status == RoleMappingApplyPreviewStatus.unmatched)
        .length;
    return AlertDialog(
      insetPadding: const EdgeInsets.all(24),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('套用全局角色档案'),
          const SizedBox(height: 3),
          Text(
            '${widget.profile.name} → ${role?.sourceLabel ?? '当前栏位'}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
      content: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildApplySummary(
              context,
              automaticCount: automaticCount,
              reviewCount: reviewCount,
              sameCount: sameCount,
              skippedCount: skippedCount,
            ),
            const SizedBox(height: 10),
            _buildIdentitySection(context, role),
            const SizedBox(height: 8),
            if (widget.preview.layerEntries.isNotEmpty) ...[
              _buildLayerMappingSection(context, role),
              const SizedBox(height: 8),
            ],
            Expanded(
              child: _buildMappingResults(context, terms, termById),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton.icon(
          key: const ValueKey('role-mapping-profile-apply'),
          onPressed: _saving ? null : _apply,
          icon: _saving
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check),
          label: const Text('复制到当前剧本角色'),
        ),
      ],
    );
  }

  Widget _buildApplySummary(
    BuildContext context, {
    required int automaticCount,
    required int reviewCount,
    required int sameCount,
    required int skippedCount,
  }) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              reviewCount == 0 ? '系统已完成匹配' : '有少量歧义需要确认',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 3),
            Text(
              '全局档案会按标签系统自动识别、归组并复制到当前剧本角色；仅真正歧义需要调整，未命中自动跳过。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 9),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _summaryPill(
                  context,
                  icon: Icons.auto_awesome_outlined,
                  label: '自动套用 $automaticCount',
                  color: colors.primary,
                ),
                if (reviewCount > 0)
                  _summaryPill(
                    context,
                    icon: Icons.warning_amber_rounded,
                    label: '需确认 $reviewCount',
                    color: colors.error,
                  ),
                if (sameCount > 0)
                  _summaryPill(
                    context,
                    icon: Icons.done_all,
                    label: '已一致 $sameCount',
                    color: colors.secondary,
                  ),
                if (skippedCount > 0)
                  _summaryPill(
                    context,
                    icon: Icons.fast_forward_outlined,
                    label: '自动跳过 $skippedCount',
                    color: colors.outline,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryPill(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.38)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 5),
          Text(label, style: Theme.of(context).textTheme.labelMedium),
        ],
      ),
    );
  }

  Widget _buildIdentitySection(
    BuildContext context,
    StudioScriptRoleReplacementItem? role,
  ) {
    final cachedIdentity = widget.profile.targetIdentityPrompt.trim();
    final currentIdentity = role?.targetIdentityPrompt.trim() ?? '';
    final canApply = cachedIdentity.isNotEmpty;
    final same = cachedIdentity == currentIdentity;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: CheckboxListTile(
        key: const ValueKey('role-mapping-profile-apply-identity'),
        contentPadding: const EdgeInsets.fromLTRB(12, 6, 8, 8),
        title: const Text('替换目标身份'),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              !canApply
                  ? '档案没有目标身份，将保留当前内容'
                  : !_applyIdentity
                      ? '已选择保留当前身份'
                      : same
                          ? '档案身份与当前一致'
                          : '将用档案身份覆盖当前内容',
            ),
            if (canApply) ...[
              const SizedBox(height: 8),
              LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 620;
                  final current = _identityPreviewPane(
                    context,
                    label: '当前',
                    value: currentIdentity,
                    key: const ValueKey(
                      'role-mapping-profile-preview-current-identity',
                    ),
                  );
                  final cached = _identityPreviewPane(
                    context,
                    label: '应用后',
                    value: cachedIdentity,
                    key: const ValueKey(
                      'role-mapping-profile-preview-cached-identity',
                    ),
                  );
                  if (compact) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        current,
                        const SizedBox(height: 6),
                        cached,
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: current),
                      const Padding(
                        padding:
                            EdgeInsets.symmetric(horizontal: 8, vertical: 28),
                        child: Icon(Icons.arrow_forward, size: 18),
                      ),
                      Expanded(child: cached),
                    ],
                  );
                },
              ),
            ],
          ],
        ),
        value: canApply && _applyIdentity,
        onChanged: canApply
            ? (value) => setState(() => _applyIdentity = value ?? false)
            : null,
      ),
    );
  }

  Widget _identityPreviewPane(
    BuildContext context, {
    required String label,
    required String value,
    required Key key,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 5),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 104),
              child: SingleChildScrollView(
                child: _profilePromptDisplay(
                  widget.viewModel,
                  key: key,
                  text: value,
                  emptyText: '空白',
                  enableTagActions: false,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLayerMappingSection(
    BuildContext context,
    StudioScriptRoleReplacementItem? role,
  ) {
    final unresolvedCount = widget.preview.layerEntries
        .where(
          (entry) => entry.status != RoleMappingProfileLayerMatchStatus.matched,
        )
        .length;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: const ValueKey('role-mapping-profile-layer-expansion'),
        initiallyExpanded: unresolvedCount > 0,
        leading: Icon(
          unresolvedCount == 0
              ? Icons.layers_outlined
              : Icons.warning_amber_rounded,
        ),
        title: const Text('全局档案分层对应'),
        subtitle: Text(
          unresolvedCount == 0
              ? '已自动对应 ${widget.preview.layerEntries.length} 层，可展开检查'
              : '$unresolvedCount 层无法唯一判断，请选择后再应用',
        ),
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              itemCount: widget.preview.layerEntries.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (context, index) => _buildLayerMappingRow(
                context,
                widget.preview.layerEntries[index],
                role,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLayerMappingRow(
    BuildContext context,
    RoleMappingProfileLayerApplyPreview entry,
    StudioScriptRoleReplacementItem? role,
  ) {
    final selectedLayerId =
        _targetLayerIdByProfileLayerId[entry.layer.id] ?? '';
    final uncertain =
        entry.status != RoleMappingProfileLayerMatchStatus.matched;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: uncertain
            ? Theme.of(context)
                .colorScheme
                .errorContainer
                .withValues(alpha: 0.35)
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Row(
          children: [
            Icon(
              uncertain
                  ? Icons.warning_amber_rounded
                  : Icons.check_circle_outline,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.layer.displayName,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    _profileLayerMatchStatusLabel(entry.status),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: MediaQuery.sizeOf(context).width < 720 ? 160 : 240,
              child: DropdownButtonFormField<String>(
                key: ValueKey(
                  'role-mapping-profile-layer-target-${entry.layer.id}',
                ),
                initialValue: selectedLayerId,
                isDense: true,
                decoration: const InputDecoration(
                  labelText: '套用到',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem(value: '', child: Text('跳过')),
                  if (role != null)
                    for (final layer in role.layers)
                      if (layer.kind !=
                              ScriptRoleReplacementRuleLayerKind.pending ||
                          entry.layer.kind ==
                              RoleMappingProfileLayerKind.pending)
                        DropdownMenuItem(
                          value: layer.id,
                          child: Text(
                            layer.kind ==
                                    ScriptRoleReplacementRuleLayerKind.shared
                                ? '共享层'
                                : layer.kind ==
                                        ScriptRoleReplacementRuleLayerKind
                                            .pending
                                    ? '待确认'
                                    : layer.label,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                ],
                onChanged: (value) {
                  setState(() {
                    final targetLayerId = value ?? '';
                    _targetLayerIdByProfileLayerId[entry.layer.id] =
                        targetLayerId;
                    for (final blockEntry in widget.preview.entries) {
                      if (blockEntry.profileLayerId != entry.layer.id) continue;
                      _enabledByBlockId[blockEntry.block.id] =
                          targetLayerId.isNotEmpty &&
                              blockEntry.selectedByDefault;
                    }
                  });
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMappingResults(
    BuildContext context,
    List<ScriptPromptReplacementTerm> terms,
    Map<String, ScriptPromptReplacementTerm> termById,
  ) {
    if (widget.preview.entries.isEmpty) {
      return const Center(child: Text('该档案没有映射组'));
    }
    final actionable = widget.preview.entries
        .where(
          (entry) =>
              entry.status != RoleMappingApplyPreviewStatus.same &&
              entry.status != RoleMappingApplyPreviewStatus.unmatched,
        )
        .toList(growable: false);
    final same = widget.preview.entries
        .where((entry) => entry.status == RoleMappingApplyPreviewStatus.same)
        .toList(growable: false);
    final skipped = widget.preview.entries
        .where(
            (entry) => entry.status == RoleMappingApplyPreviewStatus.unmatched)
        .toList(growable: false);
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 2, 2, 8),
          child: Text('映射结果', style: Theme.of(context).textTheme.titleSmall),
        ),
        if (actionable.isEmpty && same.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: Text('当前剧本没有命中可套用的映射组')),
          ),
        for (final entry in actionable) ...[
          _buildMappingEntry(context, entry, terms, termById),
          const SizedBox(height: 8),
        ],
        if (same.isNotEmpty)
          _buildPassiveEntryGroup(
            context,
            icon: Icons.done_all,
            title: '已一致 ${same.length} 组',
            subtitle: '当前结果已经与档案相同，无需重复操作',
            entries: same,
          ),
        if (skipped.isNotEmpty)
          _buildPassiveEntryGroup(
            context,
            icon: Icons.fast_forward_outlined,
            title: '未匹配 ${skipped.length} 组',
            subtitle: '这些档案映射组在当前剧本中没有识别词，将自动跳过',
            entries: skipped,
          ),
      ],
    );
  }

  Widget _buildMappingEntry(
    BuildContext context,
    RoleMappingApplyPreviewEntry entry,
    List<ScriptPromptReplacementTerm> terms,
    Map<String, ScriptPromptReplacementTerm> termById,
  ) {
    final enabled = _enabledByBlockId[entry.block.id] ?? false;
    final selectedIds = _termIdsByBlockId[entry.block.id] ?? <String>{};
    final ownerLayer = widget.profile.effectiveLayers
        .where((layer) => layer.id == entry.profileLayerId)
        .firstOrNull;
    final targetLayerReady =
        _targetLayerIdByProfileLayerId[entry.profileLayerId]?.isNotEmpty ??
            false;
    final needsReview = entry.status == RoleMappingApplyPreviewStatus.ambiguous;
    final selectedTerms = [
      for (final termId in selectedIds)
        if (termById[termId] != null) termById[termId]!,
    ];
    return Card(
      margin: EdgeInsets.zero,
      color: needsReview
          ? Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.2)
          : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: enabled,
              title: _profilePromptDisplay(
                widget.viewModel,
                key: ValueKey(
                  'role-mapping-profile-preview-source-${entry.block.id}',
                ),
                text: entry.block.terms.map((term) => term.text).join(', '),
                emptyText: '空映射组',
                enableTagActions: false,
              ),
              subtitle: Text(
                '${ownerLayer?.displayName ?? '未分层'} · '
                '${_previewStatusLabel(entry.status)}'
                '${_previewOperationLabel(entry)}',
              ),
              onChanged: targetLayerReady && selectedIds.isNotEmpty
                  ? (value) {
                      setState(() {
                        _enabledByBlockId[entry.block.id] = value ?? false;
                      });
                    }
                  : null,
            ),
            if (entry.block.targetPrompt.trim().isNotEmpty) ...[
              const SizedBox(height: 2),
              Text('应用后的目标', style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 4),
              _profilePromptDisplay(
                widget.viewModel,
                key: ValueKey(
                  'role-mapping-profile-preview-target-${entry.block.id}',
                ),
                text: entry.block.targetPrompt,
                enableTagActions: false,
              ),
            ],
            const SizedBox(height: 8),
            Text(
              '标签系统已自动归入 ${selectedTerms.length} 个当前源标签',
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: 5),
            _profilePromptDisplay(
              widget.viewModel,
              key: ValueKey(
                'role-mapping-profile-preview-selected-source-${entry.block.id}',
              ),
              text: selectedTerms.map((term) => term.text).join(', '),
              emptyText: '暂无自动归入的标签',
              enableTagActions: false,
              classificationOverrides: {
                for (final term in selectedTerms) term.text: term.category,
              },
            ),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 4),
              initiallyExpanded: needsReview,
              title: const Text('高级调整源标签'),
              subtitle: const Text('系统已经自动勾选；仅在识别有歧义时修改'),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final term in terms)
                        _selectableSourceTermChip(
                          entry: entry,
                          term: term,
                          selectedIds: selectedIds,
                        ),
                    ],
                  ),
                ),
                if (entry.block.matchMode ==
                    ScriptPromptReplacementMatchMode.anchor) ...[
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: selectedIds.contains(
                      _anchorTermIdsByBlockId[entry.block.id],
                    )
                        ? _anchorTermIdsByBlockId[entry.block.id]
                        : null,
                    decoration: const InputDecoration(
                      labelText: '当前锚点',
                      isDense: true,
                    ),
                    items: [
                      for (final termId in selectedIds)
                        if (termById[termId] != null)
                          DropdownMenuItem(
                            value: termId,
                            child: Text(termById[termId]!.text),
                          ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        _anchorTermIdsByBlockId[entry.block.id] = value;
                      });
                    },
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _selectableSourceTermChip({
    required RoleMappingApplyPreviewEntry entry,
    required ScriptPromptReplacementTerm term,
    required Set<String> selectedIds,
  }) {
    final descriptor = PromptTagProcessor.describeWorkshopTag(term.text);
    final displayText = descriptor.displayText.trim().isEmpty
        ? term.text.trim()
        : descriptor.displayText.trim();
    final selected = selectedIds.contains(term.id);
    return PromptTagChip(
      key: ValueKey(
        'role-mapping-profile-source-term-${entry.block.id}-${term.id}',
      ),
      label: displayText,
      translation:
          widget.viewModel.translationCache.translate(displayText).text,
      translationFirst: true,
      weight: descriptor.weight,
      weightLabel: descriptor.weightLabel,
      category: term.category,
      dense: true,
      selected: selected,
      semanticsLabel: '${selected ? '已归入' : '未归入'} $displayText',
      onTap: () {
        setState(() {
          if (selected) {
            selectedIds.remove(term.id);
          } else {
            selectedIds.add(term.id);
          }
          _termIdsByBlockId[entry.block.id] = selectedIds;
          if (selectedIds.isEmpty) {
            _enabledByBlockId[entry.block.id] = false;
          }
        });
      },
    );
  }

  Widget _buildPassiveEntryGroup(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required List<RoleMappingApplyPreviewEntry> entries,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        children: [
          for (final entry in entries)
            ListTile(
              dense: true,
              title:
                  Text(entry.block.terms.map((term) => term.text).join(', ')),
              subtitle: entry.block.targetPrompt.trim().isEmpty
                  ? null
                  : Text('档案目标：${entry.block.targetPrompt}'),
            ),
        ],
      ),
    );
  }

  Future<void> _apply() async {
    final selections = <RoleMappingProfileApplySelection>[];
    for (final entry in widget.preview.entries) {
      if (_enabledByBlockId[entry.block.id] != true) continue;
      final termIds =
          (_termIdsByBlockId[entry.block.id] ?? const <String>{}).toList();
      if (termIds.isEmpty) continue;
      selections.add(
        RoleMappingProfileApplySelection(
          blockId: entry.block.id,
          termIds: termIds,
          anchorTermId: _anchorTermIdsByBlockId[entry.block.id] ?? '',
        ),
      );
    }
    final role = widget.viewModel.roleReplacementMappings
        .where((entry) => entry.sourceRoleId == widget.sourceRoleId)
        .firstOrNull;
    final currentLayerById = {
      for (final layer
          in role?.layers ?? const <StudioScriptRoleReplacementLayerItem>[])
        layer.id: layer,
    };
    final layerSelections = <RoleMappingProfileLayerApplySelection>[
      for (final entry in widget.preview.layerEntries)
        () {
          final targetLayer = currentLayerById[
              _targetLayerIdByProfileLayerId[entry.layer.id] ?? ''];
          return RoleMappingProfileLayerApplySelection(
            profileLayerId: entry.layer.id,
            targetKind: targetLayer?.kind,
            targetStageId: targetLayer?.stageId ?? '',
          );
        }(),
    ];
    setState(() => _saving = true);
    try {
      await widget.viewModel.applyRoleMappingProfile(
        profileId: widget.profile.id,
        sourceRoleId: widget.sourceRoleId,
        selections: selections,
        applyIdentity: _applyIdentity,
        layerSelections: layerSelections,
      );
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(
              '已应用“${widget.profile.name}”，后续调整会自动同步',
            ),
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        _showError(context, error);
      }
    }
  }
}

class _RoleMappingProfileEditDialog extends StatefulWidget {
  final RoleMappingProfile profile;
  final StudioScriptViewModel viewModel;

  const _RoleMappingProfileEditDialog({
    required this.profile,
    required this.viewModel,
  });

  @override
  State<_RoleMappingProfileEditDialog> createState() =>
      _RoleMappingProfileEditDialogState();
}

class _RoleMappingProfileEditDialogState
    extends State<_RoleMappingProfileEditDialog> {
  late final TextEditingController _nameController;
  late String _identityPrompt;
  late String? _targetCharacterId;
  late List<RoleMappingProfileBlock> _blocks;
  late List<RoleMappingProfileLayer> _layers;
  late Map<String, String> _layerIdByBlockId;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.profile.name);
    _identityPrompt = widget.profile.targetIdentityPrompt;
    _targetCharacterId = widget.profile.targetCharacterId;
    _layers = widget.profile.effectiveLayers.toList();
    _blocks = [
      for (final layer in _layers) ...layer.blocks,
    ];
    _layerIdByBlockId = {
      for (final layer in _layers)
        for (final block in layer.blocks) block.id: layer.id,
    };
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('编辑全局角色档案'),
      content: SizedBox(
        width: 900,
        height: 680,
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(labelText: '档案名称'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: widget.viewModel.characterOptions
                            .any((entry) => entry.id == _targetCharacterId)
                        ? _targetCharacterId!
                        : '',
                    decoration: const InputDecoration(
                      labelText: '关联素材角色（可选）',
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('不关联素材'),
                      ),
                      for (final character in widget.viewModel.characterOptions)
                        DropdownMenuItem(
                          value: character.id,
                          child: Text(character.name),
                        ),
                    ],
                    onChanged: (value) {
                      setState(
                        () => _targetCharacterId =
                            value == null || value.isEmpty ? null : value,
                      );
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            PromptTagEditor(
              key: const ValueKey('role-mapping-profile-identity-editor'),
              value: _identityPrompt,
              label: '目标身份内容',
              dense: true,
              preferTranslatedLabels: true,
              copyDraggedTagsWithAlt: true,
              enableKeyboardPaste: true,
              onChanged: (value) {
                _identityPrompt = value;
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '映射组',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _addBlock,
                  icon: const Icon(Icons.add),
                  label: const Text('新增映射组'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _blocks.isEmpty
                  ? const Center(child: Text('暂无映射组'))
                  : ListView.separated(
                      itemCount: _blocks.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) => _EditableProfileBlock(
                        key: ValueKey(_blocks[index].id),
                        block: _blocks[index],
                        onChanged: (block) {
                          setState(() => _blocks[index] = block);
                        },
                        onDelete: () {
                          setState(() => _blocks.removeAt(index));
                        },
                      ),
                    ),
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
          onPressed: _save,
          child: const Text('保存'),
        ),
      ],
    );
  }

  Future<void> _addBlock() async {
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (context) => const _AddRoleMappingProfileBlockDialog(),
    );
    if (result == null || !mounted) return;
    final terms = _profileTermsFromText(
      result.$1,
      idPrefix: 'manual-${DateTime.now().microsecondsSinceEpoch}',
    );
    if (terms.isEmpty) {
      _showError(context, '至少输入一个源标签。');
      return;
    }
    setState(() {
      final block = RoleMappingProfileBlock(
        id: 'block-${DateTime.now().microsecondsSinceEpoch}',
        terms: terms,
        targetPrompt: result.$2.trim(),
        action: result.$2.trim().isEmpty
            ? ScriptPromptReplacementAction.none
            : ScriptPromptReplacementAction.replace,
      );
      _blocks.add(block);
      final sharedLayer = _layers
          .where((layer) => layer.kind == RoleMappingProfileLayerKind.shared)
          .firstOrNull;
      if (sharedLayer != null) {
        _layerIdByBlockId[block.id] = sharedLayer.id;
      } else {
        const newSharedLayer = RoleMappingProfileLayer(
          id: 'shared',
          kind: RoleMappingProfileLayerKind.shared,
          displayName: '共享',
        );
        _layers.insert(0, newSharedLayer);
        _layerIdByBlockId[block.id] = newSharedLayer.id;
      }
    });
  }

  void _save() {
    final character = widget.viewModel.characterOptions
        .where((entry) => entry.id == _targetCharacterId)
        .firstOrNull;
    final blocksById = {for (final block in _blocks) block.id: block};
    final layers = [
      for (final layer in _layers)
        () {
          final blocks = [
            for (final block in _blocks)
              if (_layerIdByBlockId[block.id] == layer.id)
                blocksById[block.id]!,
          ];
          final signature = <String>{
            for (final block in blocks)
              for (final term in block.terms)
                if (term.autoDetect && term.matchKey.isNotEmpty) term.matchKey,
          }.toList()
            ..sort();
          return layer.copyWith(
            recognitionSignature: List.unmodifiable(signature),
            blocks: List.unmodifiable(blocks),
          );
        }(),
    ];
    Navigator.of(context).pop(
      widget.profile.copyWith(
        name: _nameController.text,
        targetCharacterId: _targetCharacterId,
        targetCharacterNameSnapshot: _targetCharacterId == null
            ? ''
            : character?.name ?? widget.profile.targetCharacterNameSnapshot,
        targetIdentityPrompt: _identityPrompt,
        layers: List.unmodifiable(layers),
      ),
    );
  }
}

class _AddRoleMappingProfileBlockDialog extends StatefulWidget {
  const _AddRoleMappingProfileBlockDialog();

  @override
  State<_AddRoleMappingProfileBlockDialog> createState() =>
      _AddRoleMappingProfileBlockDialogState();
}

class _AddRoleMappingProfileBlockDialogState
    extends State<_AddRoleMappingProfileBlockDialog> {
  String _sourcePrompt = '';
  String _targetPrompt = '';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('新增映射组'),
      content: SizedBox(
        width: 680,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PromptTagEditor(
              key: const ValueKey(
                'role-mapping-profile-new-block-source-editor',
              ),
              value: _sourcePrompt,
              label: '源标签',
              dense: true,
              preferTranslatedLabels: true,
              copyDraggedTagsWithAlt: true,
              enableKeyboardPaste: true,
              onChanged: (value) => _sourcePrompt = value,
            ),
            const SizedBox(height: 12),
            PromptTagEditor(
              key: const ValueKey(
                'role-mapping-profile-new-block-target-editor',
              ),
              value: _targetPrompt,
              label: '目标内容',
              dense: true,
              preferTranslatedLabels: true,
              copyDraggedTagsWithAlt: true,
              enableKeyboardPaste: true,
              onChanged: (value) => _targetPrompt = value,
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
          onPressed: () => Navigator.of(context).pop(
            (_sourcePrompt, _targetPrompt),
          ),
          child: const Text('添加'),
        ),
      ],
    );
  }
}

class _EditableProfileBlock extends StatefulWidget {
  final RoleMappingProfileBlock block;
  final ValueChanged<RoleMappingProfileBlock> onChanged;
  final VoidCallback onDelete;

  const _EditableProfileBlock({
    super.key,
    required this.block,
    required this.onChanged,
    required this.onDelete,
  });

  @override
  State<_EditableProfileBlock> createState() => _EditableProfileBlockState();
}

class _EditableProfileBlockState extends State<_EditableProfileBlock> {
  late final TextEditingController _weightController;

  @override
  void initState() {
    super.initState();
    _weightController = TextEditingController(
      text: widget.block.targetWeightMultiplier?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _weightController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final block = widget.block;
    return Card(
      child: ExpansionTile(
        initiallyExpanded: true,
        title: Text(
          block.terms.isEmpty
              ? '空映射组'
              : block.terms.map((term) => term.text).join(' + '),
        ),
        subtitle: Text(_blockActionLabel(block)),
        trailing: IconButton(
          tooltip: '删除映射组',
          onPressed: widget.onDelete,
          icon: const Icon(Icons.delete_outline),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PromptTagEditor(
                  key: ValueKey(
                    'role-mapping-profile-block-source-editor-${block.id}',
                  ),
                  value: block.terms.map((term) => term.text).join(', '),
                  label: '源标签',
                  dense: true,
                  preferTranslatedLabels: true,
                  copyDraggedTagsWithAlt: true,
                  enableKeyboardPaste: true,
                  onChanged: _updateTerms,
                ),
                const SizedBox(height: 8),
                const Text('参与自动识别：'),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final term in block.terms)
                      FilterChip(
                        label: Text(term.text),
                        selected: term.autoDetect,
                        onSelected: (selected) {
                          _emit(
                            block.copyWith(
                              terms: [
                                for (final entry in block.terms)
                                  if (entry.id == term.id)
                                    entry.copyWith(autoDetect: selected)
                                  else
                                    entry,
                              ],
                            ),
                          );
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<
                          ScriptPromptReplacementMatchMode>(
                        initialValue: block.matchMode,
                        decoration: const InputDecoration(
                          labelText: '匹配模式',
                          isDense: true,
                        ),
                        items: [
                          for (final mode
                              in ScriptPromptReplacementMatchMode.values)
                            DropdownMenuItem(
                              value: mode,
                              child: Text(_matchModeLabel(mode)),
                            ),
                        ],
                        onChanged: (mode) {
                          if (mode == null) return;
                          var anchor = block.anchorTermKey;
                          if (mode == ScriptPromptReplacementMatchMode.anchor &&
                              !block.normalizedTermKeys.contains(anchor)) {
                            anchor = block.terms.firstOrNull?.matchKey ?? '';
                          }
                          _emit(
                            block.copyWith(
                              matchMode: mode,
                              anchorTermKey: anchor,
                            ),
                          );
                        },
                      ),
                    ),
                    if (block.matchMode ==
                        ScriptPromptReplacementMatchMode.anchor) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: block.normalizedTermKeys
                                  .contains(block.anchorTermKey)
                              ? block.anchorTermKey
                              : null,
                          decoration: const InputDecoration(
                            labelText: '锚点',
                            isDense: true,
                          ),
                          items: [
                            for (final term in block.terms)
                              DropdownMenuItem(
                                value: term.matchKey,
                                child: Text(term.text),
                              ),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            _emit(block.copyWith(anchorTermKey: value));
                          },
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<
                          ScriptPromptReplacementAction>(
                        initialValue: block.effectiveAction,
                        decoration: const InputDecoration(
                          labelText: '目标动作',
                          isDense: true,
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: ScriptPromptReplacementAction.none,
                            child: Text('无映射'),
                          ),
                          DropdownMenuItem(
                            value: ScriptPromptReplacementAction.replace,
                            child: Text('替换'),
                          ),
                          DropdownMenuItem(
                            value: ScriptPromptReplacementAction.delete,
                            child: Text('删除'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          _emit(block.copyWith(action: value));
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _weightController,
                        decoration: const InputDecoration(
                          labelText: '目标权重倍率（可选）',
                          isDense: true,
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        onChanged: (value) {
                          _emit(
                            block.copyWith(
                              targetWeightMultiplier:
                                  double.tryParse(value.trim()),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                PromptTagEditor(
                  key: ValueKey(
                    'role-mapping-profile-block-target-editor-${block.id}',
                  ),
                  value: block.targetPrompt,
                  label: '目标内容',
                  dense: true,
                  preferTranslatedLabels: true,
                  copyDraggedTagsWithAlt: true,
                  enableKeyboardPaste: true,
                  onChanged: (value) {
                    _emit(block.copyWith(targetPrompt: value));
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _updateTerms(String value) {
    _emit(
      widget.block.copyWith(
        terms: _profileTermsFromText(
          value,
          idPrefix: widget.block.id,
          existingTerms: widget.block.terms,
        ),
      ),
    );
  }

  void _emit(RoleMappingProfileBlock block) {
    widget.onChanged(block);
  }
}

class _ProfileBlockSummary extends StatelessWidget {
  final StudioScriptViewModel viewModel;
  final RoleMappingProfileBlock block;

  const _ProfileBlockSummary({
    required this.viewModel,
    required this.block,
  });

  @override
  Widget build(BuildContext context) {
    return _DetailSurface(
      title: _blockActionLabel(block),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('源标签'),
          const SizedBox(height: 4),
          _profilePromptDisplay(
            viewModel,
            key: ValueKey(
              'role-mapping-profile-block-source-display-${block.id}',
            ),
            text: block.terms.map((term) => term.text).join(', '),
            emptyText: '无源标签',
          ),
          if (block.targetPrompt.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text('目标内容'),
            const SizedBox(height: 4),
            _profilePromptDisplay(
              viewModel,
              key: ValueKey(
                'role-mapping-profile-block-target-display-${block.id}',
              ),
              text: block.targetPrompt,
            ),
          ],
          const SizedBox(height: 6),
          Text(
            '匹配：${_matchModeLabel(block.matchMode)}'
            '${block.matchMode == ScriptPromptReplacementMatchMode.anchor ? ' · 锚点 ${block.anchorTermKey}' : ''}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _ProfileLayerHeader extends StatelessWidget {
  final RoleMappingProfileLayer layer;

  const _ProfileLayerHeader({required this.layer});

  @override
  Widget build(BuildContext context) {
    final signature = layer.recognitionSignature.join(', ');
    return Row(
      children: [
        Icon(
          layer.kind == RoleMappingProfileLayerKind.shared
              ? Icons.layers_outlined
              : layer.kind == RoleMappingProfileLayerKind.pending
                  ? Icons.help_outline
                  : Icons.checkroom_outlined,
          size: 18,
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                layer.displayName,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              if (signature.isNotEmpty)
                Text(
                  '识别词：$signature',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
        ),
        Text('${layer.blocks.length} 组'),
      ],
    );
  }
}

class _DetailSurface extends StatelessWidget {
  final String title;
  final Widget child;

  const _DetailSurface({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            child,
          ],
        ),
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  final Color color;
  final String text;

  const _MessageCard({required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(text),
    );
  }
}

PromptTagDisplay _profilePromptDisplay(
  StudioScriptViewModel viewModel, {
  Key? key,
  required String text,
  String emptyText = '暂无标签',
  bool enableTagActions = true,
  Map<String, PromptTagCategory> classificationOverrides = const {},
}) {
  return PromptTagDisplay(
    key: key,
    text: text,
    emptyText: emptyText,
    dense: true,
    defaultTranslated: false,
    enableTagActions: enableTagActions,
    initialLayoutMode: PromptTagLayoutMode.sourceOrder,
    respectInitialLayoutMode: true,
    showSelectionToolbar: false,
    translationCache: viewModel.translationCache,
    classificationCache: viewModel.classificationCache,
    saveTranslationCache: viewModel.saveTranslationCache,
    saveClassificationCache: viewModel.saveClassificationCache,
    classificationOverrides: classificationOverrides,
    suppressedTagWarningKeys: viewModel.suppressedPromptTagWarningKeys,
    onSuppressTagWarningForScope:
        viewModel.suppressPromptTagWarningForCurrentScript,
  );
}

List<RoleMappingProfileTerm> _profileTermsFromText(
  String value, {
  required String idPrefix,
  Map<String, bool> detectionByKey = const {},
  Iterable<RoleMappingProfileTerm> existingTerms = const [],
}) {
  final terms = <RoleMappingProfileTerm>[];
  final seen = <String>{};
  final existingByKey = {
    for (final term in existingTerms) term.matchKey: term,
  };
  final reservedIds = {
    for (final term in existingTerms) term.id,
  };
  var nextId = 0;
  String allocateId() {
    while (reservedIds.contains('$idPrefix-term-$nextId')) {
      nextId += 1;
    }
    final id = '$idPrefix-term-$nextId';
    reservedIds.add(id);
    nextId += 1;
    return id;
  }

  for (final raw in PromptTagProcessor.splitWorkshopTags(value)) {
    final text = raw.trim();
    final key = normalizeRoleMappingProfileTerm(text);
    if (text.isEmpty || key.isEmpty || !seen.add(key)) continue;
    final existing = existingByKey[key];
    terms.add(
      existing?.copyWith(text: text) ??
          RoleMappingProfileTerm(
            id: allocateId(),
            text: text,
            normalizedKey: key,
            autoDetect: detectionByKey[key] ?? true,
          ),
    );
  }
  return List.unmodifiable(terms);
}

String _blockActionLabel(RoleMappingProfileBlock block) {
  if (block.effectiveAction == ScriptPromptReplacementAction.delete) {
    return '删除源标签';
  }
  final prompt = block.targetPrompt.trim();
  final weight = block.targetWeightMultiplier;
  if (prompt.isEmpty && weight == null) return '无映射';
  return [
    if (prompt.isNotEmpty) '替换目标',
    if (weight != null) '×${weight.toStringAsFixed(2)}',
  ].join(' ');
}

String _matchModeLabel(ScriptPromptReplacementMatchMode mode) {
  return switch (mode) {
    ScriptPromptReplacementMatchMode.any => '任一',
    ScriptPromptReplacementMatchMode.all => '全部',
    ScriptPromptReplacementMatchMode.anchor => '锚点',
  };
}

String _previewStatusLabel(RoleMappingApplyPreviewStatus status) {
  return switch (status) {
    RoleMappingApplyPreviewStatus.matched => '已自动匹配',
    RoleMappingApplyPreviewStatus.same => '当前结果相同',
    RoleMappingApplyPreviewStatus.conflict => '将覆盖当前结果',
    RoleMappingApplyPreviewStatus.ambiguous => '识别有歧义，需要确认',
    RoleMappingApplyPreviewStatus.unmatched => '未命中，将自动跳过',
  };
}

String _profileLayerMatchStatusLabel(
  RoleMappingProfileLayerMatchStatus status,
) {
  return switch (status) {
    RoleMappingProfileLayerMatchStatus.matched => '已唯一匹配当前分层',
    RoleMappingProfileLayerMatchStatus.ambiguous => '多个当前阶段并列，请手动选择',
    RoleMappingProfileLayerMatchStatus.unmatched => '没有识别词命中，请手动选择或跳过',
    RoleMappingProfileLayerMatchStatus.conflict => '多个档案阶段争用同一当前阶段',
  };
}

String _previewOperationLabel(RoleMappingApplyPreviewEntry entry) {
  final operations = [
    if (entry.pendingSplitRuleIds.isNotEmpty)
      '拆分 ${entry.pendingSplitRuleIds.length} 条',
    if (entry.pendingMergeRuleIds.isNotEmpty)
      '合并 ${entry.pendingMergeRuleIds.length} 条',
  ];
  return operations.isEmpty ? '' : '\n将自动整理：${operations.join('，')}';
}

Future<String?> _askForName(
  BuildContext context, {
  required String title,
  required String label,
}) async {
  final controller = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(labelText: label),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(controller.text),
          child: const Text('确定'),
        ),
      ],
    ),
  );
  controller.dispose();
  return result?.trim();
}

void _showError(BuildContext context, Object error) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(error.toString())),
  );
}
