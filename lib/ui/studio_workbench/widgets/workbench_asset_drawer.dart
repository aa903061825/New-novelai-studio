import 'package:flutter/material.dart';
import 'package:nai_casrand/data/studio/services/studio_asset_catalog_service.dart';
import 'package:nai_casrand/data/studio/services/studio_workbench_asset_service.dart';
import 'package:nai_casrand/data/workspace/models/workspace_entities.dart';
import 'package:nai_casrand/ui/studio_core/theme/studio_tokens.dart';
import 'package:nai_casrand/ui/studio_core/widgets/studio_button.dart';
import 'package:nai_casrand/ui/studio_core/widgets/studio_panel.dart';

class WorkbenchAssetDrawer extends StatefulWidget {
  final StudioAssetCatalogService catalogService;
  final StudioWorkbenchAssetService workbenchAssetService;

  const WorkbenchAssetDrawer({
    super.key,
    required this.catalogService,
    required this.workbenchAssetService,
  });

  @override
  State<WorkbenchAssetDrawer> createState() => _WorkbenchAssetDrawerState();
}

class _WorkbenchAssetDrawerState extends State<WorkbenchAssetDrawer> {
  late Future<StudioAssetCatalogSnapshot> _snapshotFuture;

  @override
  void initState() {
    super.initState();
    _snapshotFuture = widget.catalogService.loadSnapshot();
  }

  @override
  void didUpdateWidget(covariant WorkbenchAssetDrawer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.catalogService != widget.catalogService) {
      _snapshotFuture = widget.catalogService.loadSnapshot();
    }
  }

  @override
  Widget build(BuildContext context) {
    return StudioPanel(
      color: StudioTokens.surface2,
      padding: const EdgeInsets.all(14),
      child: FutureBuilder<StudioAssetCatalogSnapshot>(
        future: _snapshotFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _DrawerState(
              icon: Icons.error_outline,
              title: '素材抽屉不可用',
              message: snapshot.error.toString(),
              onRetry: _reload,
            );
          }
          if (!snapshot.hasData) {
            return const _DrawerState(
              icon: Icons.hourglass_empty,
              title: '素材抽屉',
              message: '正在整理可用素材',
            );
          }

          final catalog = snapshot.data!;
          if (catalog.summary.isEmpty) {
            return const _DrawerState(
              icon: Icons.inventory_2_outlined,
              title: '素材抽屉',
              message: '还没有可加入工作台的素材',
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.inventory_2_outlined,
                    color: StudioTokens.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '素材抽屉',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  Text(
                    catalog.summary.totalAssetCount.toString(),
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: StudioTokens.primary,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView(
                  children: [
                    _AssetSection(
                      title: '角色',
                      icon: Icons.person_outline,
                      children: [
                        for (final character in catalog.characters)
                          _DrawerAssetRow(
                            actionKey: ValueKey(
                              'workbench-drawer-add-character-${character.id}',
                            ),
                            icon: Icons.person_outline,
                            title: character.name,
                            subtitle: character.traits.frontFull,
                            onAdd: () => widget.workbenchAssetService
                                .appendCharacter(character),
                          ),
                      ],
                    ),
                    _AssetSection(
                      title: 'Outfit',
                      icon: Icons.checkroom_outlined,
                      children: [
                        for (final outfitAsset in catalog.outfits)
                          _DrawerAssetRow(
                            actionKey: ValueKey(
                              'workbench-drawer-add-outfit-${outfitAsset.outfit.id}',
                            ),
                            icon: Icons.checkroom_outlined,
                            title: outfitAsset.outfit.name,
                            subtitle: outfitAsset.character.name,
                            onAdd: () =>
                                widget.workbenchAssetService.appendOutfit(
                              outfitAsset.character,
                              outfitAsset.outfit,
                            ),
                          ),
                      ],
                    ),
                    _AssetSection(
                      title: '画师串',
                      icon: Icons.brush_outlined,
                      children: [
                        for (final artistChain in catalog.artistChains)
                          _DrawerAssetRow(
                            actionKey: ValueKey(
                              'workbench-drawer-add-artist-${artistChain.id}',
                            ),
                            icon: Icons.brush_outlined,
                            title: artistChain.name,
                            subtitle: _artistChainPrompt(artistChain),
                            onAdd: () => widget.workbenchAssetService
                                .appendArtistChain(artistChain),
                          ),
                      ],
                    ),
                    _AssetSection(
                      title: '配方',
                      icon: Icons.auto_awesome_mosaic_outlined,
                      children: [
                        for (final recipe in catalog.recipes)
                          _DrawerAssetRow(
                            actionKey: ValueKey(
                              'workbench-drawer-add-recipe-${recipe.id}',
                            ),
                            icon: Icons.auto_awesome_mosaic_outlined,
                            title: recipe.name,
                            subtitle: recipe.block,
                            onAdd: () => widget.workbenchAssetService
                                .appendRecipe(recipe),
                          ),
                      ],
                    ),
                    _AssetSection(
                      title: 'Tag',
                      icon: Icons.local_offer_outlined,
                      children: [
                        for (final tag in catalog.tags)
                          _DrawerAssetRow(
                            actionKey:
                                ValueKey('workbench-drawer-add-tag-${tag.id}'),
                            icon: Icons.local_offer_outlined,
                            title: tag.zh.isEmpty ? tag.tag : tag.zh,
                            subtitle: tag.tag,
                            onAdd: () =>
                                widget.workbenchAssetService.appendTag(tag),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _reload() {
    setState(() {
      _snapshotFuture = widget.catalogService.loadSnapshot();
    });
  }

  String _artistChainPrompt(ArtistChain artistChain) {
    if (artistChain.prompt.trim().isNotEmpty) {
      return artistChain.prompt.trim();
    }
    return [
      ...artistChain.tags,
      ...artistChain.styleTags,
    ].join(', ');
  }
}

class _AssetSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _AssetSection({
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: StudioTokens.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              Text(
                children.length.toString(),
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}

class _DrawerAssetRow extends StatelessWidget {
  final Key actionKey;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onAdd;

  const _DrawerAssetRow({
    required this.actionKey,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: StudioTokens.surface3,
        borderRadius: StudioTokens.radiusSlot,
        border: StudioTokens.cardBorder,
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: StudioTokens.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                if (subtitle.trim().isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          StudioIconButton(
            key: actionKey,
            tooltip: '加入工作台',
            icon: Icons.add,
            onPressed: onAdd,
          ),
        ],
      ),
    );
  }
}

class _DrawerState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final VoidCallback? onRetry;

  const _DrawerState({
    required this.icon,
    required this.title,
    required this.message,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: StudioTokens.warning),
          const SizedBox(height: 10),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            TextButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ],
      ),
    );
  }
}
