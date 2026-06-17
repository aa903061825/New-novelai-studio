import 'dart:convert';
import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:novel_studio/data/services/config_service.dart';
import 'package:novel_studio/ui/settings_page/view_models/config_selection_page_viewmodel.dart';
import 'package:novel_studio/ui/studio_core/theme/studio_tokens.dart';
import 'package:novel_studio/ui/studio_core/widgets/studio_button.dart';
import 'package:novel_studio/ui/studio_core/widgets/studio_panel.dart';

enum _ConfigSortMode { recent, name }

class ConfigSelectionPageView extends StatefulWidget {
  final VoidCallback notificationCallback;

  const ConfigSelectionPageView({
    super.key,
    required this.notificationCallback,
  });

  @override
  State<ConfigSelectionPageView> createState() =>
      _ConfigSelectionPageViewState();
}

class _ConfigSelectionPageViewState extends State<ConfigSelectionPageView> {
  final ConfigSelectionPageViewmodel viewmodel = ConfigSelectionPageViewmodel();
  final TextEditingController _searchController = TextEditingController();
  _ConfigSortMode _sortMode = _ConfigSortMode.recent;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: viewmodel,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: Text(tr('saved_config'))),
        backgroundColor: StudioTokens.surface1,
        body: LayoutBuilder(
          builder: (context, constraints) => _buildBody(context, constraints),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, BoxConstraints constraints) {
    final entries = _filteredEntries();
    final columns = constraints.maxWidth >= 1280
        ? 3
        : constraints.maxWidth >= 820
            ? 2
            : 1;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1280),
              child: _ConfigPresetToolbar(
                searchController: _searchController,
                sortMode: _sortMode,
                onSearchChanged: (_) => setState(() {}),
                onSortChanged: (mode) => setState(() => _sortMode = mode),
                onCopyCurrent: () => viewmodel.saveCopyOfCurrentConfig(context),
                onImport: () => viewmodel.importConfigFromFile(context),
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 28),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1280),
                child: entries.isEmpty
                    ? const _ConfigPresetEmptyState()
                    : GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: entries.length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                          mainAxisExtent: 212,
                        ),
                        itemBuilder: (context, index) {
                          final entry = entries[index];
                          return _ConfigPresetCard(
                            uuid: entry.key,
                            info: entry.value,
                            isActive: entry.key ==
                                viewmodel.configService.currentUuid,
                            onUse: () => _loadConfig(context, entry.key),
                            onPreview: entry.value.previewImages.isEmpty
                                ? null
                                : () => _showPreviewDialog(context, entry.key),
                            onRename: () =>
                                _showTitleEditDialog(context, entry.key),
                            onExport: () =>
                                viewmodel.saveConfigAsFile(context, entry.key),
                            onDelete:
                                entry.key == viewmodel.configService.currentUuid
                                    ? null
                                    : () => viewmodel.deleteConfig(
                                          context,
                                          entry.key,
                                        ),
                          );
                        },
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<MapEntry<String, SavedConfigInfo>> _filteredEntries() {
    final query = _searchController.text.trim().toLowerCase();
    final entries = viewmodel.configIndexes.entries.where((entry) {
      if (query.isEmpty) return true;
      return entry.value.title.toLowerCase().contains(query);
    }).toList();

    switch (_sortMode) {
      case _ConfigSortMode.recent:
        entries.sort((a, b) => b.value.lastModified.compareTo(
              a.value.lastModified,
            ));
        break;
      case _ConfigSortMode.name:
        entries.sort((a, b) => a.value.title.toLowerCase().compareTo(
              b.value.title.toLowerCase(),
            ));
        break;
    }
    return entries;
  }

  void _loadConfig(BuildContext context, String uuid) {
    viewmodel.loadSavedConfig(context, uuid);
    widget.notificationCallback();
  }

  void _showTitleEditDialog(BuildContext context, String uuid) {
    final controller = TextEditingController(
      text: viewmodel.configIndexes[uuid]!.title,
    );
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${tr('edit')}${tr('colon')}${tr('title')}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          onSubmitted: (value) {
            viewmodel.setConfigName(uuid, value);
            Navigator.pop(dialogContext);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(tr('cancel')),
          ),
          TextButton(
            onPressed: () {
              viewmodel.setConfigName(uuid, controller.text);
              Navigator.pop(dialogContext);
            },
            child: Text(tr('confirm')),
          ),
        ],
      ),
    );
  }

  void _showPreviewDialog(BuildContext context, String uuid) {
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final info = viewmodel.configIndexes[uuid];
          final previewImages = info?.previewImages ?? const <String>[];

          return AlertDialog(
            title: Text(tr('config_preview_dialog_title')),
            content: previewImages.isEmpty
                ? Text(tr('config_preview_no_preview'))
                : SizedBox(
                    width: 520,
                    child: GridView.builder(
                      shrinkWrap: true,
                      itemCount: previewImages.length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                      ),
                      itemBuilder: (context, index) => _ConfigPreviewOption(
                        uuid: uuid,
                        index: index,
                        imageB64: previewImages[index],
                        isSelected: info?.previewCoverIndex == index,
                        onTap: () {
                          viewmodel.setConfigPreviewCoverIndex(uuid, index);
                          setDialogState(() {});
                        },
                      ),
                    ),
                  ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(tr('confirm')),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ConfigPresetToolbar extends StatelessWidget {
  final TextEditingController searchController;
  final _ConfigSortMode sortMode;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<_ConfigSortMode> onSortChanged;
  final VoidCallback onCopyCurrent;
  final VoidCallback onImport;

  const _ConfigPresetToolbar({
    required this.searchController,
    required this.sortMode,
    required this.onSearchChanged,
    required this.onSortChanged,
    required this.onCopyCurrent,
    required this.onImport,
  });

  @override
  Widget build(BuildContext context) {
    return StudioPanel(
      color: StudioTokens.surface2,
      padding: const EdgeInsets.all(14),
      child: Wrap(
        spacing: 14,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 360,
            child: TextField(
              key: const ValueKey('config-presets-search-field'),
              controller: searchController,
              onChanged: onSearchChanged,
              decoration: InputDecoration(
                hintText: tr('config_presets_search_hint'),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: searchController.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: MaterialLocalizations.of(context)
                            .deleteButtonTooltip,
                        onPressed: () {
                          searchController.clear();
                          onSearchChanged('');
                        },
                        icon: const Icon(Icons.close),
                      ),
              ),
            ),
          ),
          SegmentedButton<_ConfigSortMode>(
            segments: [
              ButtonSegment<_ConfigSortMode>(
                value: _ConfigSortMode.recent,
                icon: const Icon(Icons.schedule),
                label: Text(tr('config_presets_sort_recent')),
              ),
              ButtonSegment<_ConfigSortMode>(
                value: _ConfigSortMode.name,
                icon: const Icon(Icons.sort_by_alpha),
                label: Text(tr('config_presets_sort_name')),
              ),
            ],
            selected: {sortMode},
            onSelectionChanged: (value) => onSortChanged(value.single),
          ),
          _ToolbarActionButton(
            color: StudioTokens.secondary,
            icon: Icons.copy,
            label: tr('copy_current_config'),
            onTap: onCopyCurrent,
          ),
          _ToolbarActionButton(
            color: StudioTokens.primary,
            foregroundColor: StudioTokens.onPrimary,
            icon: Icons.file_open_outlined,
            label: tr('import_from_file'),
            onTap: onImport,
          ),
        ],
      ),
    );
  }
}

class _ToolbarActionButton extends StatelessWidget {
  final Color color;
  final Color foregroundColor;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ToolbarActionButton({
    required this.color,
    this.foregroundColor = StudioTokens.onPrimary,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return StudioButton(
      label: label,
      icon: icon,
      tone: color == StudioTokens.primary
          ? StudioButtonTone.primary
          : StudioButtonTone.secondary,
      onPressed: onTap,
    );
  }
}

class _ConfigPresetCard extends StatelessWidget {
  final String uuid;
  final SavedConfigInfo info;
  final bool isActive;
  final VoidCallback onUse;
  final VoidCallback? onPreview;
  final VoidCallback onRename;
  final VoidCallback onExport;
  final VoidCallback? onDelete;

  const _ConfigPresetCard({
    required this.uuid,
    required this.info,
    required this.isActive,
    required this.onUse,
    required this.onPreview,
    required this.onRename,
    required this.onExport,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final format = DateFormat('yyyy-MM-dd HH:mm:ss');
    final formattedDate = format.format(info.lastModified);
    final accentColor = isActive ? StudioTokens.active : StudioTokens.border;

    return StudioPanel(
      color: StudioTokens.surface2,
      borderColor: accentColor,
      padding: const EdgeInsets.all(14),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: StudioTokens.radiusCard,
          onTap: onUse,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ConfigPresetCover(
                    uuid: uuid,
                    imageB64: info.coverPreviewImage,
                    isActive: isActive,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          info.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          tr('last_modified',
                              namedArgs: {'time': formattedDate}),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  if (isActive) ...[
                    const SizedBox(width: 8),
                    _ActiveBadge(),
                  ],
                ],
              ),
              const Spacer(),
              Row(
                children: [
                  FilledButton.icon(
                    onPressed: onUse,
                    icon: const Icon(Icons.play_arrow),
                    label: Text(tr('config_presets_use')),
                  ),
                  const Spacer(),
                  IconButton(
                    key: ValueKey('config-preset-preview-$uuid'),
                    tooltip: tr('config_preview_open'),
                    onPressed: onPreview,
                    icon: const Icon(Icons.photo_library_outlined),
                  ),
                  IconButton(
                    tooltip: tr('edit'),
                    onPressed: onRename,
                    icon: const Icon(Icons.edit),
                  ),
                  IconButton(
                    tooltip: tr('info_export_file'),
                    onPressed: onExport,
                    icon: const Icon(Icons.file_download_outlined),
                  ),
                  IconButton(
                    tooltip:
                        MaterialLocalizations.of(context).deleteButtonTooltip,
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConfigPresetCover extends StatelessWidget {
  final String uuid;
  final String? imageB64;
  final bool isActive;

  const _ConfigPresetCover({
    required this.uuid,
    required this.imageB64,
    required this.isActive,
  });

  @override
  Widget build(BuildContext context) {
    final imageBytes = _decodePreviewImage(imageB64);
    final fallbackColor = isActive ? StudioTokens.active : StudioTokens.warning;

    return Container(
      key: ValueKey('config-preset-cover-$uuid'),
      width: 86,
      height: 86,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: imageBytes == null ? fallbackColor : StudioTokens.surface3,
        borderRadius: BorderRadius.circular(StudioTokens.radiusMedium),
        border: Border.all(color: StudioTokens.border),
      ),
      child: imageBytes == null
          ? Icon(
              isActive ? Icons.check : Icons.description_outlined,
              size: 34,
            )
          : Image.memory(
              imageBytes,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => const Icon(
                Icons.broken_image_outlined,
                size: 34,
              ),
            ),
    );
  }
}

class _ConfigPreviewOption extends StatelessWidget {
  final String uuid;
  final int index;
  final String imageB64;
  final bool isSelected;
  final VoidCallback onTap;

  const _ConfigPreviewOption({
    required this.uuid,
    required this.index,
    required this.imageB64,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final imageBytes = _decodePreviewImage(imageB64);

    return Tooltip(
      message: tr('config_preview_set_cover'),
      child: InkWell(
        key: ValueKey('config-preset-preview-option-$uuid-$index'),
        borderRadius: BorderRadius.circular(StudioTokens.radiusLarge),
        onTap: onTap,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: StudioTokens.surface2,
            borderRadius: BorderRadius.circular(StudioTokens.radiusLarge),
            border: Border.all(
              color: isSelected ? StudioTokens.active : StudioTokens.border,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (imageBytes == null)
                const Icon(Icons.broken_image_outlined, size: 36)
              else
                Image.memory(
                  imageBytes,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => const Icon(
                    Icons.broken_image_outlined,
                    size: 36,
                  ),
                ),
              if (isSelected)
                Align(
                  alignment: Alignment.topRight,
                  child: Container(
                    margin: const EdgeInsets.all(8),
                    width: 30,
                    height: 30,
                    decoration: const BoxDecoration(
                      color: StudioTokens.active,
                      borderRadius: StudioTokens.radiusPill,
                    ),
                    child: const Icon(Icons.check, size: 18),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

Uint8List? _decodePreviewImage(String? imageB64) {
  if (imageB64 == null || imageB64.isEmpty) return null;
  try {
    return base64Decode(imageB64);
  } catch (_) {
    return null;
  }
}

class _ActiveBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: StudioTokens.active,
        borderRadius: StudioTokens.radiusPill,
      ),
      child: Text(
        tr('config_presets_active'),
        style: Theme.of(context).textTheme.labelSmall,
      ),
    );
  }
}

class _ConfigPresetEmptyState extends StatelessWidget {
  const _ConfigPresetEmptyState();

  @override
  Widget build(BuildContext context) {
    return StudioPanel(
      color: StudioTokens.surface2,
      padding: const EdgeInsets.all(28),
      child: Column(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: const BoxDecoration(
              color: StudioTokens.secondary,
              borderRadius: StudioTokens.radiusPill,
            ),
            child: const Icon(Icons.search_off, size: 30),
          ),
          const SizedBox(height: 14),
          Text(
            tr('config_presets_empty'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    );
  }
}
