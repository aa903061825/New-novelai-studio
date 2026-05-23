import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:get_it/get_it.dart';
import 'package:nai_casrand/data/models/command_status.dart';
import 'package:nai_casrand/data/models/payload_config.dart';
import 'package:nai_casrand/data/services/config_service.dart';
import 'package:nai_casrand/data/studio/services/studio_batch_plan_service.dart';
import 'package:nai_casrand/data/studio/services/studio_workbench_asset_service.dart';
import 'package:nai_casrand/ui/config_page/view_models/config_page_viewmodel.dart';
import 'package:nai_casrand/ui/config_page/widgets/config_page_view.dart';
import 'package:nai_casrand/ui/generation_page/widgets/generation_page_view.dart';
import 'package:nai_casrand/ui/navigation/view_models/navigation_view_model.dart';
import 'package:nai_casrand/ui/navigation/widgets/metadata_drop_area.dart';
import 'package:nai_casrand/ui/settings_page/widgets/settings_page_view.dart';
import 'package:nai_casrand/ui/studio_core/theme/studio_tokens.dart';
import 'package:nai_casrand/ui/studio_core/widgets/studio_chip.dart';
import 'package:nai_casrand/ui/studio_core/widgets/studio_panel.dart';
import 'package:nai_casrand/ui/studio_batch/widgets/studio_batch_page.dart';
import 'package:nai_casrand/ui/studio_workbench/widgets/generation_preview_panel.dart';
import 'package:nai_casrand/ui/studio_shell/models/studio_shell_section.dart';
import 'package:nai_casrand/ui/studio_shell/widgets/asset_library_page.dart';
import 'package:nai_casrand/ui/studio_shell/widgets/studio_gallery_page.dart';
import 'package:nai_casrand/ui/studio_shell/widgets/studio_home_page.dart';
import 'package:url_launcher/url_launcher.dart';

class StudioShellView extends StatefulWidget {
  final NavigationViewModel viewModel;

  const StudioShellView({super.key, required this.viewModel});

  @override
  State<StudioShellView> createState() => _StudioShellViewState();
}

class _StudioShellViewState extends State<StudioShellView> {
  StudioShellSection _currentSection = StudioShellSection.home;
  DateTime? _lastBackButtonPressTime;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (kIsWeb) return;
      _showWelcomeDialog();
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: _handleBack,
      child: Scaffold(
        backgroundColor: StudioTokens.surface1,
        body: MetadataDropArea(
          childBuilder: (context) => _buildShell(context),
        ),
      ),
    );
  }

  Widget _buildShell(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 900;
        final page = _buildCurrentPage();
        if (compact) {
          return Column(
            children: [
              _StudioTopBar(
                currentSection: _currentSection,
                compact: true,
              ),
              Expanded(child: page),
              _BottomStudioNavigation(
                currentSection: _currentSection,
                onSelected: _changeSection,
              ),
            ],
          );
        }

        return Row(
          children: [
            _SideStudioNavigation(
              currentSection: _currentSection,
              onSelected: _changeSection,
            ),
            Expanded(
              child: Column(
                children: [
                  _StudioTopBar(currentSection: _currentSection),
                  Expanded(child: page),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCurrentPage() {
    return switch (_currentSection) {
      StudioShellSection.home => StudioHomePage(
          catalogService: GetIt.I(),
          galleryService: GetIt.I(),
          workbenchAssetService: GetIt.I<StudioWorkbenchAssetService>(),
          payloadConfig: GetIt.I(),
          onNavigate: _changeSection,
        ),
      StudioShellSection.assets => AssetLibraryPage(
          catalogService: GetIt.I(),
          workbenchAssetService: GetIt.I<StudioWorkbenchAssetService>(),
        ),
      StudioShellSection.workbench => GenerationPageView(viewmodel: GetIt.I()),
      StudioShellSection.batch => StudioBatchPage(
          viewmodel: GetIt.I(),
          batchPlanService: GetIt.I<StudioBatchPlanService>(),
          configEditor: ConfigPageView(viewmodel: ConfigPageViewmodel()),
          resultPanel: GenerationPreviewPanel(viewmodel: GetIt.I()),
        ),
      StudioShellSection.gallery => StudioGalleryPage(
          viewModel: GetIt.I(),
          galleryService: GetIt.I(),
          payloadConfig: GetIt.I(),
        ),
      StudioShellSection.settings => SettingsPageView(),
    };
  }

  void _changeSection(StudioShellSection section) {
    widget.viewModel.changeIndex(_destinations.indexWhere(
      (destination) => destination.section == section,
    ));
    setState(() {
      _currentSection = section;
    });
  }

  void _handleBack(bool didPop, Object? result) {
    if (_currentSection != StudioShellSection.home) {
      _changeSection(StudioShellSection.home);
      return;
    }

    final now = DateTime.now();
    final timeDiff = _lastBackButtonPressTime == null
        ? null
        : now.difference(_lastBackButtonPressTime!);
    if (timeDiff == null || timeDiff > const Duration(seconds: 2)) {
      _lastBackButtonPressTime = now;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('press_again_to_exit'))),
      );
      return;
    }
    SystemNavigator.pop();
  }

  void _showWelcomeDialog() {
    final dontShowAgainVersion =
        GetIt.I<PayloadConfig>().settings.welcomeMessageVersion;
    final packageInfo = GetIt.instance<ConfigService>().packageInfo;
    const appName = 'Novel Studio';
    final appVersion = packageInfo.version;
    if (appVersion == dontShowAgainVersion) return;
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('${tr('welcome_message_title')} - $appName $appVersion'),
          content: MarkdownBody(
            data: tr('welcome_message_markdown'),
            onTapLink: (text, url, title) {
              if (url == null) return;
              if (url == '#jump_to_settings') {
                _changeSection(StudioShellSection.settings);
                Navigator.of(dialogContext).pop();
              } else {
                launchUrl(Uri.parse(url));
              }
            },
          ),
          actions: [
            TextButton(
              onPressed: () {
                GetIt.I<PayloadConfig>().settings.welcomeMessageVersion =
                    appVersion;
                final config = GetIt.instance<PayloadConfig>();
                final service = GetIt.instance<ConfigService>();
                service.saveConfig(config.toJson());
                Navigator.of(dialogContext).pop();
              },
              child: Text(tr('dont_show_again')),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(tr('confirm')),
            ),
          ],
        );
      },
    );
  }
}

class _StudioTopBar extends StatelessWidget {
  final StudioShellSection currentSection;
  final bool compact;

  const _StudioTopBar({
    required this.currentSection,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final destination = _destinations.firstWhere(
      (item) => item.section == currentSection,
    );
    final packageInfo = GetIt.I<ConfigService>().packageInfo;
    final commandStatus = GetIt.I<CommandStatus>();

    return Container(
      height: compact ? 58 : 64,
      padding: EdgeInsets.symmetric(horizontal: compact ? 14 : 22),
      decoration: const BoxDecoration(
        color: StudioTokens.surface1,
        border: Border(
          bottom: BorderSide(color: StudioTokens.border),
        ),
      ),
      child: Row(
        children: [
          Image.asset(
            'assets/appicon.png',
            width: 30,
            height: 30,
            filterQuality: FilterQuality.medium,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  destination.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (!compact)
                  Text(
                    'Novel Studio ${packageInfo.version}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
              ],
            ),
          ),
          ListenableBuilder(
            listenable: Listenable.merge([
              commandStatus.isBatchActive,
              commandStatus.isCoolingDown,
            ]),
            builder: (context, _) {
              final label = commandStatus.isCoolingDown.value
                  ? '冷却中'
                  : commandStatus.isBatchActive.value
                      ? '生成中'
                      : '待机';
              final color = commandStatus.isCoolingDown.value
                  ? StudioTokens.warning
                  : commandStatus.isBatchActive.value
                      ? StudioTokens.active
                      : StudioTokens.textMuted;
              return StudioChip(
                label: label,
                icon: Icons.circle,
                selected: commandStatus.isBatchActive.value ||
                    commandStatus.isCoolingDown.value,
                accentColor: color,
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SideStudioNavigation extends StatelessWidget {
  final StudioShellSection currentSection;
  final ValueChanged<StudioShellSection> onSelected;

  const _SideStudioNavigation({
    required this.currentSection,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: StudioTokens.sidebarWidth,
      decoration: const BoxDecoration(
        color: StudioTokens.surfaceBase,
        border: Border(
          right: BorderSide(color: StudioTokens.border),
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _StudioBrandBlock(),
              const SizedBox(height: 18),
              for (final destination in _destinations)
                _SideStudioNavigationItem(
                  destination: destination,
                  selected: destination.section == currentSection,
                  onTap: () => onSelected(destination.section),
                ),
              const Spacer(),
              const _LocalOnlyNote(),
            ],
          ),
        ),
      ),
    );
  }
}

class _StudioBrandBlock extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StudioPanel(
      color: StudioTokens.surface2,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              color: StudioTokens.primary,
              borderRadius: StudioTokens.radiusPill,
            ),
            child: const Icon(
              Icons.auto_awesome,
              color: StudioTokens.onPrimary,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Novel Studio',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _SideStudioNavigationItem extends StatelessWidget {
  final _StudioDestination destination;
  final bool selected;
  final VoidCallback onTap;

  const _SideStudioNavigationItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final foreground =
        selected ? StudioTokens.onPrimary : StudioTokens.textSecondary;
    final background = selected ? StudioTokens.primary : Colors.transparent;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Tooltip(
        message: destination.label,
        child: Material(
          color: background,
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Icon(destination.icon, color: foreground, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      destination.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: foreground,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomStudioNavigation extends StatelessWidget {
  final StudioShellSection currentSection;
  final ValueChanged<StudioShellSection> onSelected;

  const _BottomStudioNavigation({
    required this.currentSection,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 78,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: const BoxDecoration(
        color: StudioTokens.surfaceBase,
        border: Border(
          top: BorderSide(color: StudioTokens.border),
        ),
      ),
      child: Row(
        children: [
          for (final destination in _destinations)
            Expanded(
              child: _BottomStudioNavigationItem(
                destination: destination,
                selected: destination.section == currentSection,
                onTap: () => onSelected(destination.section),
              ),
            ),
        ],
      ),
    );
  }
}

class _BottomStudioNavigationItem extends StatelessWidget {
  final _StudioDestination destination;
  final bool selected;
  final VoidCallback onTap;

  const _BottomStudioNavigationItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final foreground =
        selected ? StudioTokens.onPrimary : StudioTokens.textSecondary;
    final background = selected ? StudioTokens.primary : Colors.transparent;
    return Tooltip(
      message: destination.label,
      child: Material(
        color: background,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(destination.icon, color: foreground, size: 20),
                const SizedBox(height: 4),
                Text(
                  destination.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: foreground,
                        fontSize: 10,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LocalOnlyNote extends StatelessWidget {
  const _LocalOnlyNote();

  @override
  Widget build(BuildContext context) {
    return Text(
      '个人本地创作工具',
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.labelSmall,
    );
  }
}

class _StudioDestination {
  final StudioShellSection section;
  final IconData icon;
  final String label;

  const _StudioDestination({
    required this.section,
    required this.icon,
    required this.label,
  });
}

const _destinations = [
  _StudioDestination(
    section: StudioShellSection.home,
    icon: Icons.home_outlined,
    label: '主页',
  ),
  _StudioDestination(
    section: StudioShellSection.assets,
    icon: Icons.inventory_2_outlined,
    label: '素材库',
  ),
  _StudioDestination(
    section: StudioShellSection.workbench,
    icon: Icons.dashboard_customize_outlined,
    label: '工作台',
  ),
  _StudioDestination(
    section: StudioShellSection.batch,
    icon: Icons.account_tree_outlined,
    label: '批量产线',
  ),
  _StudioDestination(
    section: StudioShellSection.gallery,
    icon: Icons.photo_library_outlined,
    label: '画廊',
  ),
  _StudioDestination(
    section: StudioShellSection.settings,
    icon: Icons.tune,
    label: '设置',
  ),
];
