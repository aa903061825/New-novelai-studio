import 'dart:math';

import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:get_it/get_it.dart';
import 'package:blinking_text/blinking_text.dart';
import 'package:nai_casrand/data/models/command_status.dart';
import 'package:nai_casrand/data/services/config_service.dart';
import 'package:nai_casrand/ui/core/theme/playful_geometric_theme.dart';
import 'package:nai_casrand/ui/core/widgets/playful_geometric_surface.dart';
import 'package:nai_casrand/ui/navigation/widgets/debug_settings_view.dart';
import 'package:url_launcher/url_launcher.dart';

enum AppState { idle, generating, coolingDown }

class NavigationAppBar extends StatefulWidget implements PreferredSizeWidget {
  final CommandStatus commandStatus = GetIt.instance();

  NavigationAppBar({super.key});

  @override
  NavigationAppBarState createState() => NavigationAppBarState();

  @override
  Size get preferredSize => const Size.fromHeight(60);
}

class NavigationAppBarState extends State<NavigationAppBar>
    with SingleTickerProviderStateMixin {
  late final _iconAnimationController = AnimationController(
    duration: const Duration(seconds: 3), // 控制旋转速度
    vsync: this,
  );
  late final _animation = CurvedAnimation(
    parent: _iconAnimationController,
    curve: Curves.linear,
  );
  AppState _state = AppState.idle;

  @override
  void initState() {
    super.initState();

    // 在生成状态变化时改变样式
    widget.commandStatus.isBatchActive.addListener(refreshDisplay);
    widget.commandStatus.isCoolingDown.addListener(refreshDisplay);
    refreshDisplay(); // 初始化状态
  }

  void refreshDisplay() {
    AppState newState;
    if (widget.commandStatus.isCoolingDown.value) {
      newState = AppState.coolingDown;
    } else if (widget.commandStatus.isBatchActive.value) {
      newState = AppState.generating;
    } else {
      newState = AppState.idle;
    }
    setState(() => _state = newState);
  }

  @override
  Widget build(BuildContext context) {
    Widget title;
    Color statusColor;
    switch (_state) {
      case AppState.idle:
        statusColor = PlayfulGeometricColors.card;
        title = Text(
          context.tr('appbar_idle'),
        );
        _iconAnimationController.stop();
        break;
      case AppState.generating:
        statusColor = PlayfulGeometricColors.secondary;
        title = BlinkText(
          context.tr('appbar_regular'),
          beginColor: Theme.of(context).textTheme.titleMedium?.color,
        );
        _iconAnimationController.repeat();
        break;
      case AppState.coolingDown:
        statusColor = PlayfulGeometricColors.tertiary;
        title = BlinkText(
          context.tr('appbar_cooldown'),
          beginColor: Theme.of(context).textTheme.titleMedium?.color,
        );
        _iconAnimationController.stop();
        break;
    }
    Widget icon = SizedBox.square(
      dimension: 38,
      child: Center(
        child: RotationTransition(
          turns: _animation,
          child: Image.asset(
            'assets/appicon.png',
            filterQuality: FilterQuality.medium,
            height: 30,
            width: 30,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
    final titleBar = Row(
      children: [
        PlayfulGeometricSurface(
          color: statusColor,
          shadowColor: PlayfulGeometricColors.foreground,
          shadowOffset: PlayfulGeometricShadows.pop,
          borderRadius: BorderRadius.circular(PlayfulGeometricRadius.full),
          padding: const EdgeInsets.all(2),
          liftOnHover: false,
          wiggleOnHover: true,
          onTap: () => _iconAnimationController
              .animateTo(Random().nextDouble())
              .whenComplete(refreshDisplay),
          child: icon,
        ),
        const SizedBox(width: 12.0),
        Flexible(
          child: PlayfulGeometricSurface(
            color: PlayfulGeometricColors.card,
            shadowColor: PlayfulGeometricColors.border,
            shadowOffset: PlayfulGeometricShadows.pop,
            borderRadius: BorderRadius.circular(PlayfulGeometricRadius.full),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            liftOnHover: false,
            onTap: () => _showDebugDialog(context),
            child: DefaultTextStyle.merge(
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              child: title,
            ),
          ),
        ),
        const SizedBox(width: 12.0),
      ],
    );
    return AppBar(
      toolbarHeight: widget.preferredSize.height,
      titleSpacing: 8,
      title: titleBar,
      actions: [
        Tooltip(
          message: MaterialLocalizations.of(context)
              .aboutListTileTitle('NAI CasRand'),
          child: PlayfulGeometricSurface(
            color: PlayfulGeometricColors.accent,
            shadowColor: PlayfulGeometricColors.foreground,
            shadowOffset: PlayfulGeometricShadows.pop,
            borderRadius: BorderRadius.circular(PlayfulGeometricRadius.full),
            onTap: () => _showAppInfoDialog(context),
            child: const SizedBox.square(
              dimension: 40,
              child: Icon(
                Icons.help_outline,
                color: PlayfulGeometricColors.accentForeground,
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
      ],
    );
  }

  void _showAppInfoDialog(BuildContext context) {
    final packageInfo = GetIt.instance<ConfigService>().packageInfo;
    const appName = 'NAI CasRand';
    final appVersion = packageInfo.version;
    final iconImage = Image.asset(
      'assets/appicon.png',
      width: 64,
      height: 64,
      filterQuality: FilterQuality.medium,
    );

    showAboutDialog(
        context: context,
        applicationName: appName,
        applicationVersion: appVersion,
        applicationIcon: iconImage,
        children: [
          // Github link
          _buildLinkTile(),
        ]);
  }

  Widget _buildLinkTile() {
    return ListTile(
      title: Text(tr('github_repo')),
      leading: const Icon(Icons.link),
      subtitle: const Text(String.fromEnvironment("GITHUB_REPO_LINK")),
      onTap: () => {
        launchUrl(Uri.parse(const String.fromEnvironment("GITHUB_REPO_LINK")))
      },
    );
  }

  void _showDebugDialog(BuildContext context) {
    showDialog(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('调试设置'),
              content: DebugSettingsView(),
              actions: [
                TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      tr('confirm'),
                    ))
              ],
            ));
  }
}
