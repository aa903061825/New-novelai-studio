import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:novel_studio/core/constants/settings.dart';
import 'package:novel_studio/data/models/settings.dart';
import 'package:novel_studio/ui/core/app_display_settings.dart';
import 'package:novel_studio/ui/settings_page/view_models/settings_page_viewmodel.dart';
import 'package:novel_studio/ui/core/widgets/editable_list_tile.dart';
import 'package:novel_studio/ui/settings_page/widgets/config_selection_page_view.dart';
import 'package:novel_studio/ui/studio_core/theme/studio_tokens.dart';
import 'package:novel_studio/ui/studio_core/widgets/studio_panel.dart';
import 'package:provider/provider.dart';

class SettingsPageView extends StatefulWidget {
  final Widget? knowledgeAndRulesSection;
  final WidgetBuilder? knowledgeAndRulesBuilder;

  const SettingsPageView({
    super.key,
    this.knowledgeAndRulesSection,
    this.knowledgeAndRulesBuilder,
  });

  @override
  State<SettingsPageView> createState() => _SettingsPageViewState();
}

class _SettingsPageViewState extends State<SettingsPageView> {
  final SettingsPageViewmodel viewmodel = SettingsPageViewmodel();
  final ScrollController _scrollController = ScrollController();
  bool _buildKnowledgeAndRulesSection = false;

  bool get _hasKnowledgeAndRulesSection =>
      widget.knowledgeAndRulesSection != null ||
      widget.knowledgeAndRulesBuilder != null;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleSettingsScroll);
  }

  @override
  void didUpdateWidget(covariant SettingsPageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_hasKnowledgeAndRulesSection && _buildKnowledgeAndRulesSection) {
      _buildKnowledgeAndRulesSection = false;
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleSettingsScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _handleSettingsScroll() {
    if (_buildKnowledgeAndRulesSection || !_hasKnowledgeAndRulesSection) {
      return;
    }
    if (!_scrollController.hasClients) {
      return;
    }
    final position = _scrollController.position;
    if (position.pixels < 280 && position.extentAfter > 720) {
      return;
    }
    setState(() {
      _buildKnowledgeAndRulesSection = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: viewmodel,
      child: Consumer<SettingsPageViewmodel>(
        builder: (context, viewmodel, child) => Scaffold(
          backgroundColor: StudioTokens.surface1,
          body: LayoutBuilder(
            builder: (context, constraints) =>
                _buildSettingsContent(context, constraints),
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsContent(
    BuildContext context,
    BoxConstraints constraints,
  ) {
    final horizontalPadding = constraints.maxWidth >= 900 ? 24.0 : 14.0;

    final profileSection = _buildSettingsSection(
      context,
      title: tr('saved_config'),
      icon: Icons.widgets_outlined,
      accentColor: StudioTokens.active,
      children: [
        _buildSavedConfigTile(context),
        _buildDisplayScaleTile(context),
        _buildPromptTranslationShortcutTile(context),
        _buildThemeModeTile(context),
        _buildLanguageTile(context),
      ],
    );
    final knowledgeSection =
        !_buildKnowledgeAndRulesSection || !_hasKnowledgeAndRulesSection
            ? null
            : KeyedSubtree(
                key: const ValueKey('settings-knowledge-and-rules-section'),
                child: widget.knowledgeAndRulesBuilder?.call(context) ??
                    widget.knowledgeAndRulesSection!,
              );
    final sections = <Widget>[
      profileSection,
      _buildCachePackageSection(context),
      _buildNaiApiSettingsSection(context),
      _buildAiSettingsSection(context),
      if (knowledgeSection != null) knowledgeSection,
    ];

    return SingleChildScrollView(
      controller: _scrollController,
      padding:
          EdgeInsets.fromLTRB(horizontalPadding, 16, horizontalPadding, 28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildSettingsHeader(context),
              const SizedBox(height: 18),
              _buildSectionColumn(sections),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsHeader(BuildContext context) {
    return StudioPanel(
      color: StudioTokens.surface2,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: const BoxDecoration(
              color: StudioTokens.primary,
              borderRadius: StudioTokens.radiusPill,
            ),
            child: const Icon(
              Icons.settings,
              color: StudioTokens.onPrimary,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            context.tr('settings'),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
        ],
      ),
    );
  }

  Widget _buildSectionColumn(List<Widget> sections) {
    return Column(
      children: [
        for (final section in sections) ...[
          section,
          const SizedBox(height: 18),
        ],
      ],
    );
  }

  Widget _buildSettingsSection(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Color accentColor,
    required List<Widget> children,
  }) {
    return StudioPanel(
      color: StudioTokens.surface2,
      padding: const EdgeInsets.only(top: 14, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: accentColor,
                    borderRadius: StudioTokens.radiusPill,
                  ),
                  child: Icon(
                    icon,
                    color: accentColor == StudioTokens.primary
                        ? StudioTokens.onPrimary
                        : StudioTokens.surfaceBase,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 18),
          ...children,
        ],
      ),
    );
  }

  Widget _buildNaiApiSettingsSection(BuildContext context) {
    return _buildSettingsSection(
      context,
      title: tr('nai_api_settings'),
      icon: Icons.cloud_sync_outlined,
      accentColor: StudioTokens.primary,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final twoColumns = constraints.maxWidth >= 760;
              final tokenField = TextFormField(
                key: const ValueKey('settings-nai-api-token'),
                initialValue: viewmodel.settings.apiKey,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: tr('NAI_API_key'),
                  helperText: tr('NAI_API_key_hint'),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: viewmodel.setApiKey,
              );
              final proxyField = TextFormField(
                key: const ValueKey('settings-nai-http-proxy'),
                initialValue: viewmodel.settings.proxy,
                decoration: InputDecoration(
                  labelText: tr('proxy_settings'),
                  helperText: tr('proxy_settings_notice'),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: viewmodel.setProxy,
              );

              if (!twoColumns) {
                return Column(
                  children: [
                    tokenField,
                    const SizedBox(height: 12),
                    proxyField,
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: tokenField),
                  const SizedBox(width: 12),
                  Expanded(child: proxyField),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAiSettingsSection(BuildContext context) {
    return _buildSettingsSection(
      context,
      title: 'AI 设置',
      icon: Icons.smart_toy_outlined,
      accentColor: StudioTokens.info,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final twoColumns = constraints.maxWidth >= 760;
              final cards = [
                _buildAiCredentialCard(
                  context,
                  title: '剧本 AI',
                  description: '用于后续自动识别剧本角色、服装阶段和映射建议。',
                  baseUrlKey: const ValueKey('settings-script-ai-base-url'),
                  tokenKey: const ValueKey('settings-script-ai-token'),
                  modelKey: const ValueKey('settings-script-ai-model'),
                  reasoningEffortKey:
                      const ValueKey('settings-script-ai-reasoning-effort'),
                  baseUrlValue: viewmodel.settings.scriptAiBaseUrl,
                  tokenValue: viewmodel.settings.scriptAiToken,
                  modelValue: viewmodel.settings.scriptAiModel,
                  reasoningEffortValue:
                      viewmodel.settings.scriptAiReasoningEffort,
                  onBaseUrlChanged: viewmodel.setScriptAiBaseUrl,
                  onTokenChanged: viewmodel.setScriptAiToken,
                  onModelChanged: viewmodel.setScriptAiModel,
                  onReasoningEffortChanged:
                      viewmodel.setScriptAiReasoningEffort,
                  testConnectionKey:
                      const ValueKey('settings-script-ai-test-connection'),
                  testStatusKey:
                      const ValueKey('settings-script-ai-test-status'),
                  testStatus: viewmodel.scriptAiTestStatus,
                  isTestingConnection: viewmodel.isTestingScriptAiConnection,
                  onTestConnection: viewmodel.testScriptAiConnection,
                ),
                _buildAiCredentialCard(
                  context,
                  title: '翻译 AI',
                  description: '用于提示词翻译、标签解释和翻译缓存补全。',
                  baseUrlKey:
                      const ValueKey('settings-translation-ai-base-url'),
                  tokenKey: const ValueKey('settings-translation-ai-token'),
                  modelKey: const ValueKey('settings-translation-ai-model'),
                  headerExtras: [
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: SegmentedButton<TranslationProviderMode>(
                        key: const ValueKey('settings-translation-provider'),
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(
                            value: TranslationProviderMode.ai,
                            label: Text('AI'),
                          ),
                          ButtonSegment(
                            value: TranslationProviderMode.google,
                            label: Text('Google'),
                          ),
                        ],
                        selected: {
                          viewmodel.settings.translationProviderMode,
                        },
                        onSelectionChanged: (selection) {
                          final mode = selection.firstOrNull;
                          if (mode == null) {
                            return;
                          }
                          viewmodel.setTranslationProvider(mode.name);
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '默认翻译先查本地缓存；在线翻译按这里的提供方选择。',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: StudioTokens.textMuted,
                          ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        FilledButton.icon(
                          key: const ValueKey(
                            'settings-translation-cache-ai-refresh',
                          ),
                          onPressed:
                              viewmodel.isRefreshingTranslationCacheWithAi
                                  ? null
                                  : viewmodel.refreshTranslationCacheWithAi,
                          icon: viewmodel.isRefreshingTranslationCacheWithAi
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.auto_fix_high_outlined),
                          label: const Text('AI 更新缓存'),
                        ),
                        Text(
                          viewmodel.translationCacheRefreshStatus,
                          key: const ValueKey(
                            'settings-translation-cache-refresh-status',
                          ),
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: StudioTokens.textMuted,
                                  ),
                        ),
                      ],
                    ),
                  ],
                  baseUrlValue: viewmodel.settings.translationAiBaseUrl,
                  tokenValue: viewmodel.settings.translationAiToken,
                  modelValue: viewmodel.settings.translationAiModel,
                  onBaseUrlChanged: viewmodel.setTranslationAiBaseUrl,
                  onTokenChanged: viewmodel.setTranslationAiToken,
                  onModelChanged: viewmodel.setTranslationAiModel,
                  testConnectionKey: const ValueKey(
                    'settings-translation-ai-test-connection',
                  ),
                  testStatusKey:
                      const ValueKey('settings-translation-ai-test-status'),
                  testStatus: viewmodel.translationAiTestStatus,
                  isTestingConnection:
                      viewmodel.isTestingTranslationAiConnection,
                  onTestConnection: viewmodel.testTranslationAiConnection,
                ),
              ];
              if (!twoColumns) {
                return Column(
                  children: [
                    cards[0],
                    const SizedBox(height: 12),
                    cards[1],
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: cards[0]),
                  const SizedBox(width: 12),
                  Expanded(child: cards[1]),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCachePackageSection(BuildContext context) {
    return _buildSettingsSection(
      context,
      title: '缓存包',
      icon: Icons.inventory_2_outlined,
      accentColor: StudioTokens.warning,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.icon(
                key: const ValueKey('settings-cache-import-zip'),
                onPressed: viewmodel.isImportingStudioCache
                    ? null
                    : () => viewmodel.importStudioCacheFromZip(context),
                icon: viewmodel.isImportingStudioCache
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.archive_outlined),
                label: const Text('载入缓存 ZIP'),
              ),
              OutlinedButton.icon(
                key: const ValueKey('settings-cache-import-folder'),
                onPressed: viewmodel.isImportingStudioCache
                    ? null
                    : () => viewmodel.importStudioCacheFromDirectory(context),
                icon: const Icon(Icons.folder_open_outlined),
                label: const Text('载入缓存文件夹'),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: Text(
                  viewmodel.studioCacheImportStatus,
                  key: const ValueKey('settings-cache-import-status'),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: StudioTokens.textMuted,
                      ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAiCredentialCard(
    BuildContext context, {
    required String title,
    required String description,
    required Key baseUrlKey,
    required Key tokenKey,
    List<Widget> headerExtras = const [],
    bool showCredentialFields = true,
    Key? modelKey,
    Key? reasoningEffortKey,
    required String baseUrlValue,
    required String tokenValue,
    String? modelValue,
    String? reasoningEffortValue,
    required ValueChanged<String> onBaseUrlChanged,
    required ValueChanged<String> onTokenChanged,
    ValueChanged<String>? onModelChanged,
    ValueChanged<String>? onReasoningEffortChanged,
    Key? testConnectionKey,
    Key? testStatusKey,
    String? testStatus,
    bool isTestingConnection = false,
    VoidCallback? onTestConnection,
  }) {
    final translationGoogleSelected =
        tokenKey == const ValueKey('settings-translation-ai-token') &&
            viewmodel.settings.translationProviderMode ==
                TranslationProviderMode.google;
    final showFields = showCredentialFields && !translationGoogleSelected;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: StudioTokens.surface3,
        borderRadius: StudioTokens.radiusSlot,
        border: StudioTokens.cardBorder,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            description,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: StudioTokens.textMuted,
                ),
          ),
          ...headerExtras,
          if (showFields) ...[
            const SizedBox(height: 12),
            TextFormField(
              key: baseUrlKey,
              initialValue: baseUrlValue,
              decoration: const InputDecoration(
                labelText: '接口地址',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: onBaseUrlChanged,
            ),
            if (modelKey != null &&
                modelValue != null &&
                onModelChanged != null) ...[
              const SizedBox(height: 10),
              TextFormField(
                key: modelKey,
                initialValue: modelValue,
                decoration: const InputDecoration(
                  labelText: '模型',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: onModelChanged,
              ),
            ],
            if (reasoningEffortKey != null &&
                reasoningEffortValue != null &&
                onReasoningEffortChanged != null) ...[
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                key: reasoningEffortKey,
                initialValue:
                    normalizeScriptAiReasoningEffort(reasoningEffortValue),
                decoration: const InputDecoration(
                  labelText: '思考程度',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  for (final effort in scriptAiReasoningEffortOptions)
                    DropdownMenuItem(
                      value: effort,
                      child: Text(_scriptAiReasoningEffortLabel(effort)),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    onReasoningEffortChanged(value);
                  }
                },
              ),
            ],
            const SizedBox(height: 10),
            TextFormField(
              key: tokenKey,
              initialValue: tokenValue,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Token',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: onTokenChanged,
            ),
            if (testStatus != null && onTestConnection != null) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                alignment: WrapAlignment.spaceBetween,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360),
                    child: Text(
                      testStatus,
                      key: testStatusKey,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: StudioTokens.textMuted,
                          ),
                    ),
                  ),
                  OutlinedButton.icon(
                    key: testConnectionKey,
                    onPressed: isTestingConnection ? null : onTestConnection,
                    icon: isTestingConnection
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.network_check_outlined),
                    label: Text(isTestingConnection ? '测试中' : '测试连通性'),
                  ),
                ],
              ),
            ],
          ] else ...[
            const SizedBox(height: 12),
            Text(
              'Google 模式会直接使用内置翻译接口，不需要这里的 AI 地址、模型或 Token。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: StudioTokens.textSecondary,
                  ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildThemeModeTile(BuildContext context) {
    final themeMode = viewmodel.payloadConfig.settings.themeMode;
    return SelectableListTile(
      title: tr('theme_mode'),
      leading: const Icon(Icons.dark_mode_outlined),
      currentValue: themeMode,
      currentValueText: _themeModeLabel(themeMode),
      options: themeModeStrings,
      optionsText: const ['浅色', '深色', '跟随系统'],
      onSelectComplete: (value) => viewmodel.setThemeMode(value, context),
    );
  }

  Widget _buildDisplayScaleTile(BuildContext context) {
    final scale = viewmodel.payloadConfig.settings.uiTextScale;
    final percent = (scale * 100).round();
    final selectedScale = _nearestDisplayScale(scale);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.format_size_outlined),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '字号缩放',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$percent%',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              SegmentedButton<double>(
                segments: const [
                  ButtonSegment(value: 1.0, label: Text('标准')),
                  ButtonSegment(value: 1.1, label: Text('舒适')),
                  ButtonSegment(value: 1.2, label: Text('大')),
                  ButtonSegment(value: 1.3, label: Text('特大')),
                ],
                selected: {selectedScale},
                onSelectionChanged: (values) {
                  viewmodel.setUiTextScale(values.single);
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '界面显示',
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ],
      ),
    );
  }

  Widget _buildPromptTranslationShortcutTile(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.sell_outlined),
      title: const Text('提示词翻译快捷键'),
      subtitle: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(AppDisplaySettings.promptTranslationShortcutLabel),
          Text('翻译鼠标悬停的提示词卡片。'),
        ],
      ),
      trailing: TextButton(
        onPressed: AppDisplaySettings.translateHoveredPromptCard,
        child: const Text('翻译悬停卡片'),
      ),
    );
  }

  double _nearestDisplayScale(double scale) {
    const options = [1.0, 1.1, 1.2, 1.3];
    return options.reduce(
      (best, option) =>
          (option - scale).abs() < (best - scale).abs() ? option : best,
    );
  }

  Widget _buildLanguageTile(BuildContext context) {
    return ListTile(
      title: const Text('语言'),
      leading: const Icon(Icons.translate),
      subtitle: Text(context.locale.toLanguageTag()),
      onTap: () => _showLanguageSelectionDialog(context),
    );
  }

  void _showLanguageSelectionDialog(BuildContext context) {
    final locales = context.supportedLocales;
    String getLocaleName(Locale locale) {
      if (locale.countryCode == null) {
        return locale.languageCode;
      } else {
        return '${locale.languageCode}-${locale.countryCode}';
      }
    }

    showDialog(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('选择语言'),
                content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: locales
                        .map((l) => ListTile(
                              title: Text(getLocaleName(l)),
                              onTap: () {
                                Navigator.of(context).pop();
                                context.setLocale(l);
                              },
                            ))
                        .toList()),
                actions: [
                  TextButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                      child: Text(context.tr('confirm')))
                ]));
  }

  Widget _buildSavedConfigTile(BuildContext context) {
    return ListTile(
      title: Text(tr('saved_config')),
      leading: const Icon(Icons.save_outlined),
      onTap: () {
        viewmodel.saveCurrentConfig();
        Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) => ConfigSelectionPageView(
                      notificationCallback: () => viewmodel.notify(),
                    )));
      },
    );
  }
}

String _scriptAiReasoningEffortLabel(String value) {
  return switch (value) {
    '' => '默认',
    'none' => 'none',
    'minimal' => 'minimal',
    'low' => 'low',
    'medium' => 'medium',
    'high' => 'high',
    'xhigh' => 'xhigh',
    _ => '默认',
  };
}

String _themeModeLabel(String value) {
  return switch (value) {
    'light' => '浅色',
    'dark' => '深色',
    'system' => '跟随系统',
    _ => value,
  };
}
