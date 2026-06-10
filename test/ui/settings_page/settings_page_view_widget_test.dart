import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:nai_casrand/data/models/param_config.dart';
import 'package:nai_casrand/data/models/payload_config.dart';
import 'package:nai_casrand/data/models/prompt_config.dart';
import 'package:nai_casrand/data/models/settings.dart';
import 'package:nai_casrand/ui/core/app_display_settings.dart';
import 'package:nai_casrand/ui/settings_page/widgets/settings_page_view.dart';

class _EnglishSettingsAssetLoader extends AssetLoader {
  const _EnglishSettingsAssetLoader();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async {
    return {
      'NAI_API_key': 'NAI API Token',
      'NAI_API_key_hint':
          'Available at: Home Page → Settings → Account → Get Persistent API Token',
      'generation': 'Image Generation',
      'settings': 'Settings',
      'batch_settings': 'Batch settings',
      'batch_count': 'Request per batch',
      'batch_interval': 'Interval between batches (seconds)',
      'batch_interval_jitter_min': 'Minimum random jitter (seconds)',
      'batch_interval_jitter_max': 'Maximum random jitter (seconds)',
      'retry_on_429_enabled': 'Fast retry on HTTP 429',
      'retry_on_429_delay_sec': '429 retry delay (seconds)',
      'retry_on_429_description':
          'If enabled, HTTP 429 waits the configured seconds and retries the current request.',
      'batch_settings_info':
          'Requests per batch: {batch_count}, interval between batches: {interval}s, total requests: {number_of_requests}',
      'image_number_to_generate': 'Total Generation Count',
      'metadata_erase_enabled': 'Erase metadata in generated images',
      'output_folder': 'Output Folder',
      'system_document_folder': 'System document folder',
      'output_file_name_prefix': 'Output File Name Prefix',
      'output_file_name_prefix_hint': 'Prefix used for generated files',
      'nai_api_settings': 'NovelAI API',
      'proxy_settings': 'HTTP Proxy',
      'proxy_settings_notice': 'Example: 127.0.0.1:12345; blank means direct',
      'proxy_settings_direct': 'DIRECT',
      'saved_config': 'Saved Config',
      'theme_mode': 'Theme Mode',
      'import_settings_from_file': 'Import settings from file',
      'export_settings_to_file': 'Export settings to file',
    };
  }
}

class _LocalizedSettingsApp extends StatelessWidget {
  const _LocalizedSettingsApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      locale: context.locale,
      supportedLocales: context.supportedLocales,
      localizationsDelegates: context.localizationDelegates,
      home: SettingsPageView(),
    );
  }
}

const _sharedPreferencesChannel = MethodChannel(
  'plugins.flutter.io/shared_preferences',
);

PayloadConfig _buildPayloadConfig() {
  return PayloadConfig(
    rootPromptConfig: PromptConfig(strs: const [], prompts: const []),
    characterConfigList: const [],
    savedPromptConfigList: const [],
    paramConfig: ParamConfig(),
    settings: Settings.fromJson({}),
    overridePrompt: '',
    useOverridePrompt: false,
    useCharacterPromptWithOverride: false,
  );
}

Future<void> _pumpLocalizedSettingsPage(WidgetTester tester) async {
  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('en')],
      path: 'assets/l10n',
      assetLoader: const _EnglishSettingsAssetLoader(),
      fallbackLocale: const Locale('en'),
      startLocale: const Locale('en'),
      saveLocale: false,
      child: const _LocalizedSettingsApp(),
    ),
  );

  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_sharedPreferencesChannel,
            (methodCall) async {
      if (methodCall.method == 'getAll') {
        return <String, Object>{};
      }

      return true;
    });
    await EasyLocalization.ensureInitialized();
  });

  setUp(() async {
    await GetIt.I.reset();
    GetIt.I.registerSingleton<PayloadConfig>(_buildPayloadConfig());
  });

  tearDown(() async {
    await GetIt.I.reset();
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_sharedPreferencesChannel, null);
  });

  testWidgets('settings page does not expose batch execution settings', (
    tester,
  ) async {
    await _pumpLocalizedSettingsPage(tester);

    expect(find.text('Batch settings'), findsNothing);
    expect(find.text('Request per batch'), findsNothing);
    expect(find.text('Interval between batches (seconds)'), findsNothing);
    expect(find.text('Minimum random jitter (seconds)'), findsNothing);
    expect(find.text('Maximum random jitter (seconds)'), findsNothing);
    expect(find.text('Fast retry on HTTP 429'), findsNothing);
    expect(find.text('429 retry delay (seconds)'), findsNothing);
    expect(find.text('Total Generation Count'), findsNothing);
    expect(find.text('Erase metadata in generated images'), findsNothing);
    expect(find.text('Output Folder'), findsNothing);
    expect(find.text('Output File Name Prefix'), findsNothing);
  });

  testWidgets('settings page does not expose workbench file exchange', (
    tester,
  ) async {
    await _pumpLocalizedSettingsPage(tester);

    expect(find.text('Import settings from file'), findsNothing);
    expect(find.text('Export settings to file'), findsNothing);
  });

  testWidgets('settings page exposes app font scaling', (tester) async {
    await _pumpLocalizedSettingsPage(tester);

    expect(find.text('界面显示'), findsOneWidget);
    expect(find.text('字号缩放'), findsOneWidget);
    expect(find.text('110%'), findsOneWidget);

    await tester.tap(find.text('大'));
    await tester.pumpAndSettle();

    final config = GetIt.I<PayloadConfig>();
    expect(config.settings.uiTextScale, 1.2);
    expect(find.text('120%'), findsOneWidget);
  });

  testWidgets('settings page exposes prompt translation shortcut',
      (tester) async {
    await _pumpLocalizedSettingsPage(tester);

    expect(find.text('提示词翻译快捷键'), findsOneWidget);
    expect(find.text(AppDisplaySettings.promptTranslationShortcutLabel),
        findsOneWidget);
    expect(find.text('翻译鼠标悬停的提示词卡片。'), findsOneWidget);
    expect(find.text('Prompt translation shortcut'), findsNothing);
    expect(find.text('Translates the hovered prompt card.'), findsNothing);
    expect(find.text('Translate hovered card'), findsNothing);
    expect(find.text('语言'), findsOneWidget);
    expect(find.text('Language'), findsNothing);
    expect(find.text('跟随系统'), findsOneWidget);
    expect(find.text('light'), findsNothing);
    expect(find.text('system'), findsNothing);

    final before = AppDisplaySettings.promptTranslationShortcutSerial.value;
    await tester.tap(find.text('翻译悬停卡片'));
    await tester.pump();

    expect(
      AppDisplaySettings.promptTranslationShortcutSerial.value,
      before + 1,
    );
  });

  testWidgets('settings page exposes NovelAI token and HTTP proxy inputs',
      (tester) async {
    await _pumpLocalizedSettingsPage(tester);

    final tokenFinder = find.byKey(const ValueKey('settings-nai-api-token'));
    final proxyFinder = find.byKey(const ValueKey('settings-nai-http-proxy'));

    expect(find.text('NovelAI API'), findsOneWidget);
    expect(find.text('NAI API Token'), findsOneWidget);
    expect(tokenFinder, findsOneWidget);
    expect(proxyFinder, findsOneWidget);

    await tester.enterText(tokenFinder, ' pst-novelai-token ');
    await tester.enterText(proxyFinder, '127.0.0.1:7890');
    await tester.pump();

    final config = GetIt.I<PayloadConfig>();
    expect(config.settings.apiKey, 'pst-novelai-token');
    expect(config.settings.proxy, '127.0.0.1:7890');
  });

  testWidgets('settings page exposes script and translation ai credentials',
      (tester) async {
    await _pumpLocalizedSettingsPage(tester);

    expect(find.text('AI 设置'), findsOneWidget);
    expect(find.text('剧本 AI'), findsOneWidget);
    expect(find.text('翻译 AI'), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-script-ai-base-url')),
        findsOneWidget);
    expect(
        find.byKey(const ValueKey('settings-script-ai-token')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('settings-script-ai-model')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-script-ai-test-connection')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('settings-script-ai-test-status')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('settings-translation-ai-base-url')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('settings-translation-provider')),
        findsOneWidget);
    expect(find.text('AI'), findsWidgets);
    expect(find.text('Google'), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-translation-ai-token')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('settings-translation-ai-model')),
        findsOneWidget);
    expect(
        find.byKey(const ValueKey('settings-translation-ai-test-connection')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('settings-translation-ai-test-status')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('settings-translation-cache-ai-refresh')),
        findsOneWidget);
    expect(
        find.byKey(const ValueKey('settings-translation-cache-refresh-status')),
        findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const ValueKey('settings-translation-provider')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Google').last, warnIfMissed: false);
    await tester.pumpAndSettle();

    final config = GetIt.I<PayloadConfig>();
    expect(config.settings.translationProvider, 'google');
    expect(find.byKey(const ValueKey('settings-translation-ai-base-url')),
        findsNothing);
    expect(find.byKey(const ValueKey('settings-translation-ai-token')),
        findsNothing);
    expect(find.byKey(const ValueKey('settings-translation-ai-model')),
        findsNothing);
    expect(
        find.byKey(const ValueKey('settings-translation-ai-test-connection')),
        findsNothing);
    expect(find.byKey(const ValueKey('settings-translation-ai-test-status')),
        findsNothing);
    expect(find.byKey(const ValueKey('settings-translation-cache-ai-refresh')),
        findsOneWidget);
  });

  testWidgets('settings page exposes cache package import actions',
      (tester) async {
    await _pumpLocalizedSettingsPage(tester);

    expect(find.text('缓存包'), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-cache-import-zip')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('settings-cache-import-folder')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('settings-cache-import-status')),
        findsOneWidget);
  });
}
