import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/data/models/param_config.dart';
import 'package:novel_studio/data/models/payload_config.dart';
import 'package:novel_studio/data/models/prompt_config.dart';
import 'package:novel_studio/data/models/settings.dart';
import 'package:novel_studio/data/studio/services/workbench_transfer_service.dart';
import 'package:novel_studio/ui/studio_workbench/view_models/workbench_transfer_viewmodel.dart';
import 'package:novel_studio/ui/studio_workbench/widgets/workbench_transfer_actions.dart';

const _sharedPreferencesChannel = MethodChannel(
  'plugins.flutter.io/shared_preferences',
);

class _WorkbenchAssetLoader extends AssetLoader {
  const _WorkbenchAssetLoader();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async {
    return {
      'workbench_import': 'Import workbench',
      'workbench_export': 'Export workbench',
    };
  }
}

PayloadConfig _payload() {
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_sharedPreferencesChannel, (call) async {
      if (call.method == 'getAll') return <String, Object>{};
      return true;
    });
    await EasyLocalization.ensureInitialized();
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_sharedPreferencesChannel, null);
  });

  testWidgets('workbench transfer actions expose import and export buttons',
      (tester) async {
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en')],
        path: 'assets/l10n',
        assetLoader: const _WorkbenchAssetLoader(),
        fallbackLocale: const Locale('en'),
        startLocale: const Locale('en'),
        saveLocale: false,
        child: Builder(
          builder: (context) => MaterialApp(
            locale: context.locale,
            supportedLocales: context.supportedLocales,
            localizationsDelegates: context.localizationDelegates,
            home: Scaffold(
              body: WorkbenchTransferActions(
                viewModel: WorkbenchTransferViewModel(
                  payloadConfig: _payload(),
                  transferService: WorkbenchTransferService(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('workbench-import-action')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('workbench-export-action')),
      findsOneWidget,
    );
  });
}
