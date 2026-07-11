import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:novel_studio/data/models/param_config.dart';
import 'package:novel_studio/data/models/payload_config.dart';
import 'package:novel_studio/data/models/prompt_config.dart';
import 'package:novel_studio/data/models/settings.dart';
import 'package:novel_studio/data/services/config_service.dart';
import 'package:novel_studio/ui/settings_page/widgets/config_selection_page_view.dart';

const _sharedPreferencesChannel = MethodChannel(
  'plugins.flutter.io/shared_preferences',
);

class _EnglishConfigSelectionAssetLoader extends AssetLoader {
  const _EnglishConfigSelectionAssetLoader();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async {
    return {
      'saved_config': 'Saved Config',
      'config_selection_page_hint': 'Tap Use to load a saved config.',
      'copy_current_config': 'Copy current config',
      'import_from_file': 'Import from file',
      'last_modified': 'Last saved: {time}',
      'config_presets_search_hint': 'Search presets',
      'config_presets_sort_recent': 'Recent',
      'config_presets_sort_name': 'Name',
      'config_presets_use': 'Use',
      'config_presets_active': 'Active',
      'config_preview_open': 'Preview',
      'config_preview_dialog_title': 'Config preview',
      'config_preview_set_cover': 'Set as cover',
      'config_preview_no_preview': 'No preview saved',
      'edit': 'Edit',
      'info_export_file': 'Export file',
      'colon': ': ',
      'title': 'Title',
      'cancel': 'Cancel',
      'confirm': 'Confirm',
    };
  }
}

class _PreviewConfigService extends ConfigService {
  int saveConfigIndexCallCount = 0;

  @override
  void saveConfigIndex() {
    saveConfigIndexCallCount++;
  }
}

const _onePixelPngB64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=';

String get _secondOnePixelPngB64 => base64Encode(base64Decode(_onePixelPngB64));

class _LocalizedConfigSelectionApp extends StatelessWidget {
  const _LocalizedConfigSelectionApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      locale: context.locale,
      supportedLocales: context.supportedLocales,
      localizationsDelegates: context.localizationDelegates,
      home: ConfigSelectionPageView(notificationCallback: () {}),
    );
  }
}

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

Future<void> _pumpConfigSelectionPage(WidgetTester tester) async {
  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('en')],
      path: 'assets/l10n',
      assetLoader: const _EnglishConfigSelectionAssetLoader(),
      fallbackLocale: const Locale('en'),
      startLocale: const Locale('en'),
      saveLocale: false,
      child: const _LocalizedConfigSelectionApp(),
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
    GetIt.I.registerSingleton<ConfigService>(
      _PreviewConfigService()
        ..currentUuid = 'active'
        ..configIndex = {
          'active': SavedConfigInfo(
            title: 'Cyber Princess.json',
            lastModified: DateTime(2026, 3, 9, 19, 43),
            previewImages: [_onePixelPngB64, _secondOnePixelPngB64],
            previewCoverIndex: 1,
          ),
          'second': SavedConfigInfo(
            title: '400+.json',
            lastModified: DateTime(2026, 2, 25, 10, 28),
          ),
          'third': SavedConfigInfo(
            title: 'Blue Archive.json',
            lastModified: DateTime(2026, 3, 7, 18, 24),
          ),
        },
    );
  });

  tearDown(() async {
    await GetIt.I.reset();
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_sharedPreferencesChannel, null);
  });

  testWidgets('saved config page presents searchable preset cards', (
    tester,
  ) async {
    await _pumpConfigSelectionPage(tester);

    expect(
      find.byKey(const ValueKey('config-presets-search-field')),
      findsOneWidget,
    );
    expect(find.text('Cyber Princess.json'), findsOneWidget);
    expect(find.text('Use'), findsWidgets);

    await tester.enterText(
      find.byKey(const ValueKey('config-presets-search-field')),
      '400',
    );
    await tester.pumpAndSettle();

    expect(find.text('400+.json'), findsOneWidget);
    expect(find.text('Cyber Princess.json'), findsNothing);
    expect(find.text('Blue Archive.json'), findsNothing);
  });

  testWidgets('saved config preview dialog can change the card cover', (
    tester,
  ) async {
    await _pumpConfigSelectionPage(tester);

    expect(
      find.byKey(const ValueKey('config-preset-cover-active')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('config-preset-preview-active')),
      findsOneWidget,
    );

    await tester
        .tap(find.byKey(const ValueKey('config-preset-preview-active')));
    await tester.pumpAndSettle();

    expect(find.text('Config preview'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('config-preset-preview-option-active-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('config-preset-preview-option-active-1')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('config-preset-preview-option-active-0')),
    );
    await tester.pumpAndSettle();

    final configService = GetIt.I<ConfigService>() as _PreviewConfigService;
    expect(configService.configIndex['active']!.previewCoverIndex, 0);
    expect(configService.saveConfigIndexCallCount, 1);
  });
}
