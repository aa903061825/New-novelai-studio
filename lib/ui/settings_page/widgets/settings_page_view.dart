import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nai_casrand/core/constants/settings.dart';
import 'package:nai_casrand/ui/settings_page/view_models/settings_page_viewmodel.dart';
import 'package:nai_casrand/ui/core/widgets/editable_list_tile.dart';
import 'package:nai_casrand/ui/settings_page/widgets/config_selection_page_view.dart';
import 'package:nai_casrand/ui/studio_core/theme/studio_tokens.dart';
import 'package:nai_casrand/ui/studio_core/widgets/studio_panel.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/defaults.dart';

class SettingsPageView extends StatelessWidget {
  final SettingsPageViewmodel viewmodel = SettingsPageViewmodel();

  SettingsPageView({super.key});

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
    final isWide = constraints.maxWidth >= 980;
    final horizontalPadding = constraints.maxWidth >= 900 ? 24.0 : 14.0;

    final accountSection = _buildSettingsSection(
      context,
      title: tr('NAI_API_key'),
      icon: Icons.key,
      accentColor: StudioTokens.primary,
      children: [_buildApiKeyTile()],
    );
    final generationSection = _buildSettingsSection(
      context,
      title: tr('generation'),
      icon: Icons.auto_awesome,
      accentColor: StudioTokens.warning,
      children: [
        _buildBatchTile(),
        _buildEraseMetadataTile(context),
      ],
    );
    final outputSection = _buildSettingsSection(
      context,
      title: tr('output_folder'),
      icon: Icons.folder_copy_outlined,
      accentColor: StudioTokens.info,
      children: [
        if (!kIsWeb && Platform.isWindows) _buildOutputSelectionTile(),
        _buildPrefixKeyTile(),
        if (!kIsWeb) _buildProxyTile(),
      ],
    );
    final profileSection = _buildSettingsSection(
      context,
      title: tr('saved_config'),
      icon: Icons.widgets_outlined,
      accentColor: StudioTokens.active,
      children: [
        _buildSavedConfigTile(context),
        _buildThemeModeTile(context),
        _buildLanguageTile(context),
      ],
    );

    return SingleChildScrollView(
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
              if (isWide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _buildSectionColumn([
                        generationSection,
                        outputSection,
                      ]),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: _buildSectionColumn([
                        accountSection,
                        profileSection,
                      ]),
                    ),
                  ],
                )
              else
                _buildSectionColumn([
                  generationSection,
                  accountSection,
                  outputSection,
                  profileSection,
                ]),
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

  Widget _buildApiKeyTile() {
    return EditableListTile(
        leading: const Icon(Icons.token_outlined),
        title: tr('NAI_API_key'),
        notice: tr('NAI_API_key_hint'),
        currentValue: viewmodel.settings.apiKey,
        confirmOnSubmit: true,
        onEditComplete: (value) => viewmodel.setApiKey(value));
  }

  Widget _buildBatchTile() {
    final displayedNumberOfRequests = viewmodel.settings.numberOfRequests == 0
        ? '∞'
        : viewmodel.settings.numberOfRequests.toString();
    return ExpansionTile(
      leading: const Icon(Icons.schedule),
      title: Text(tr('batch_settings')),
      subtitle: Text(tr('batch_settings_info', namedArgs: {
        'batch_count': viewmodel.settings.batchCount.toString(),
        'interval': viewmodel.settings.batchIntervalSec.toString(),
        'number_of_requests': displayedNumberOfRequests,
      })),
      children: [
        // Batch count
        Padding(
          padding: const EdgeInsets.only(left: 20),
          child: EditableListTile(
              leading: const Icon(Icons.checklist),
              title: tr('batch_count'),
              currentValue: viewmodel.settings.batchCount.toString(),
              keyboardType: TextInputType.number,
              confirmOnSubmit: true,
              onEditComplete: (value) => viewmodel.setBatchCount(value)),
        ),
        // Batch interval
        Padding(
            padding: const EdgeInsets.only(left: 20),
            child: EditableListTile(
                leading: const Icon(Icons.hourglass_empty),
                title: tr('batch_interval'),
                currentValue: viewmodel.settings.batchIntervalSec.toString(),
                keyboardType: TextInputType.number,
                confirmOnSubmit: true,
                onEditComplete: (value) =>
                    viewmodel.setBatchIntervalSet(value))),
        Padding(
            padding: const EdgeInsets.only(left: 20),
            child: EditableListTile(
                leading: const Icon(Icons.tune),
                title: tr('batch_interval_jitter_min'),
                currentValue:
                    viewmodel.settings.batchIntervalJitterMinSec.toString(),
                keyboardType: TextInputType.number,
                confirmOnSubmit: true,
                onEditComplete: (value) =>
                    viewmodel.setBatchIntervalJitterMin(value))),
        Padding(
            padding: const EdgeInsets.only(left: 20),
            child: EditableListTile(
                leading: const Icon(Icons.tune),
                title: tr('batch_interval_jitter_max'),
                currentValue:
                    viewmodel.settings.batchIntervalJitterMaxSec.toString(),
                keyboardType: TextInputType.number,
                confirmOnSubmit: true,
                onEditComplete: (value) =>
                    viewmodel.setBatchIntervalJitterMax(value))),
        Padding(
          padding: const EdgeInsets.only(left: 20),
          child: CheckboxListTile(
            secondary: const Icon(Icons.refresh),
            title: Text(tr('retry_on_429_enabled')),
            value: viewmodel.settings.retryOn429Enabled,
            onChanged: (value) => viewmodel.setRetryOn429Enabled(value),
          ),
        ),
        if (viewmodel.settings.retryOn429Enabled)
          Padding(
            padding: const EdgeInsets.only(left: 40),
            child: EditableListTile(
              leading: const Icon(Icons.timer_outlined),
              title: tr('retry_on_429_delay_sec'),
              currentValue: viewmodel.settings.retryOn429DelaySec.toString(),
              keyboardType: TextInputType.number,
              confirmOnSubmit: true,
              onEditComplete: (value) => viewmodel.setRetryOn429DelaySec(value),
            ),
          ),
        if (viewmodel.settings.retryOn429Enabled)
          Builder(
            builder: (context) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 8),
              child: Text(
                tr('retry_on_429_description'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        // Number of requests
        Padding(
            padding: const EdgeInsets.only(left: 20),
            child: EditableListTile(
              leading: const Icon(Icons.alarm),
              title: tr('image_number_to_generate'),
              currentValue: displayedNumberOfRequests,
              editValue: viewmodel.settings.numberOfRequests.toString(),
              notice: '0 → ∞',
              onEditComplete: (value) => viewmodel.setNumberOfRequests(value),
              keyboardType: TextInputType.number,
              confirmOnSubmit: true,
            )),
      ],
    );
  }

  Widget _buildEraseMetadataTile(BuildContext context) {
    List<Widget> tiles = [
      CheckboxListTile(
          secondary: const Icon(Icons.delete_sweep),
          title: Text(tr('metadata_erase_enabled')),
          value: viewmodel.settings.metadataEraseEnabled,
          onChanged: (value) => viewmodel.setEraseMetadataEnabled(value))
    ];
    if (viewmodel.settings.metadataEraseEnabled) {
      tiles.add(Padding(
          padding: const EdgeInsets.only(left: 20),
          child: CheckboxListTile(
              secondary: const Icon(Icons.edit_note),
              title: Text(tr('custom_metadata_enabled')),
              value: viewmodel.settings.customMetadataEnabled,
              onChanged: (value) =>
                  viewmodel.setCustomMetadataEnabled(value))));
    }
    if (viewmodel.settings.metadataEraseEnabled &&
        viewmodel.settings.customMetadataEnabled) {
      tiles.add(Padding(
          padding: const EdgeInsets.only(left: 30),
          child: ListTile(
            title: Text(tr('custom_metadata_content')),
            subtitle: Text(
              viewmodel.settings.customMetadataContent,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => _showEditCustomMetadataDialog(context),
          )));
    }
    return Column(
      children: tiles,
    );
  }

  Widget _buildOutputSelectionTile() {
    if (kIsWeb || Platform.isAndroid) return const SizedBox.shrink();
    final outputDirPath = viewmodel.settings.outputFolderPath == ''
        ? '<${tr('system_document_folder')}>\\nai_generated'
        : viewmodel.settings.outputFolderPath;
    return ListTile(
      leading: const Icon(Icons.folder_outlined),
      title: Text(tr('output_folder')),
      subtitle: Text(outputDirPath),
      onTap: () => viewmodel.pickOutputFolderPath(),
    );
  }

  Widget _buildProxyTile() {
    if (kIsWeb) return const SizedBox.shrink();
    final proxy = viewmodel.settings.proxy;
    return EditableListTile(
      leading: const Icon(Icons.route),
      title: tr('proxy_settings'),
      currentValue: proxy == '' ? tr('proxy_settings_direct') : proxy,
      editValue: proxy,
      notice: tr('proxy_settings_notice'),
      confirmOnSubmit: true,
      onEditComplete: (value) => viewmodel.setProxy(value),
    );
  }

  void _showEditCustomMetadataDialog(context) {
    final controller =
        TextEditingController(text: viewmodel.settings.customMetadataContent);
    submit() {
      viewmodel.setCustomMetadataContent(controller.text);
      Navigator.of(context).pop();
    }

    showDialog(
        context: context,
        builder: (context) => StatefulBuilder(
              builder: (context, setState) => AlertDialog(
                title: Text(
                    tr('edit') + tr('colon') + tr('custom_metadata_content')),
                content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(tr('edit_custom_metadata_content_hint')),
                      TextField(
                        maxLines: null,
                        autofocus: true,
                        controller: controller,
                        onSubmitted: (_) => submit(),
                      )
                    ]),
                actions: [
                  Row(
                    children: [
                      TextButton(
                          onPressed: () => setState(
                              () => controller.text = defaultWatermarkContent),
                          child: const Text('👻')),
                      const Spacer(),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(tr('cancel')),
                      ),
                      TextButton(
                        onPressed: () => submit(),
                        child: Text(tr('confirm')),
                      )
                    ],
                  ),
                ],
              ),
            ));
  }

  Widget _buildPrefixKeyTile() {
    final shownPrefix = viewmodel.settings.fileNamePrefixKey.isNotEmpty
        ? viewmodel.settings.fileNamePrefixKey
        : 'nai-generated';
    return EditableListTile(
      leading: const Icon(Icons.description),
      title: tr('output_file_name_prefix'),
      notice: tr('output_file_name_prefix_hint'),
      editValue: viewmodel.settings.fileNamePrefixKey,
      currentValue: shownPrefix,
      confirmOnSubmit: true,
      onEditComplete: (value) => viewmodel.setFileNamePrefixKey(value),
    );
  }

  Widget _buildThemeModeTile(BuildContext context) {
    return SelectableListTile(
      title: tr('theme_mode'),
      leading: const Icon(Icons.dark_mode_outlined),
      currentValue: viewmodel.payloadConfig.settings.themeMode,
      options: themeModeStrings,
      onSelectComplete: (value) => viewmodel.setThemeMode(value, context),
    );
  }

  Widget _buildLanguageTile(BuildContext context) {
    return ListTile(
      title: const Text('Language'),
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
                title: const Text('Select language...'),
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
