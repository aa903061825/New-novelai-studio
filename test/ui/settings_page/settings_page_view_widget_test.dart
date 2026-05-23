import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:nai_casrand/data/models/param_config.dart';
import 'package:nai_casrand/data/models/payload_config.dart';
import 'package:nai_casrand/data/models/prompt_config.dart';
import 'package:nai_casrand/data/models/settings.dart';
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

  testWidgets('settings page shows jitter inputs in batch settings', (
    tester,
  ) async {
    await _pumpLocalizedSettingsPage(tester);

    await tester.tap(find.text('Batch settings'));
    await tester.pumpAndSettle();

    expect(find.text('Minimum random jitter (seconds)'), findsOneWidget);
    expect(find.text('Maximum random jitter (seconds)'), findsOneWidget);
  });

  testWidgets('settings page shows 429 retry controls in batch settings', (
    tester,
  ) async {
    await _pumpLocalizedSettingsPage(tester);

    await tester.tap(find.text('Batch settings'));
    await tester.pumpAndSettle();

    expect(find.text('Fast retry on HTTP 429'), findsOneWidget);

    final retryToggleFinder = find.text('Fast retry on HTTP 429');
    await tester.ensureVisible(retryToggleFinder);
    await tester.pumpAndSettle();

    await tester.tap(retryToggleFinder);
    await tester.pumpAndSettle();

    expect(find.text('429 retry delay (seconds)'), findsOneWidget);
    expect(
      find.text(
        'If enabled, HTTP 429 waits the configured seconds and retries the current request.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('settings page does not expose workbench file exchange', (
    tester,
  ) async {
    await _pumpLocalizedSettingsPage(tester);

    expect(find.text('Import settings from file'), findsNothing);
    expect(find.text('Export settings to file'), findsNothing);
  });
}
