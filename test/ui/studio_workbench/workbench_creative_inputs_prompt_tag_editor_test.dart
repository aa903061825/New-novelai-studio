import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:get_it/get_it.dart';
import 'package:nai_casrand/data/models/character_config.dart';
import 'package:nai_casrand/data/models/param_config.dart';
import 'package:nai_casrand/data/models/payload_config.dart';
import 'package:nai_casrand/data/models/prompt_config.dart';
import 'package:nai_casrand/data/models/settings.dart';
import 'package:nai_casrand/ui/studio_core/theme/studio_theme.dart';
import 'package:nai_casrand/ui/studio_core/widgets/prompt_tag_editor.dart';
import 'package:nai_casrand/ui/studio_workbench/view_models/workbench_single_image_parameters_viewmodel.dart';
import 'package:nai_casrand/ui/studio_workbench/widgets/workbench_single_image_console.dart';

const _sharedPreferencesChannel = MethodChannel(
  'plugins.flutter.io/shared_preferences',
);

class _WorkbenchAssetLoader extends AssetLoader {
  const _WorkbenchAssetLoader();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async {
    return {
      'drag_and_drop_image_notice': 'Drag and drop image',
      'enable_precise_reference': 'Enable precise reference',
      'enable_precise_reference_hint': 'Enable precise reference hint',
      'enable_vibe_transfer': 'Enable vibe transfer',
      'enable_vibe_transfer_hint': 'Enable vibe transfer hint',
      'vibe_v4_page_tip': 'Vibe tip',
    };
  }
}

PayloadConfig _payload() {
  return PayloadConfig(
    rootPromptConfig: PromptConfig(strs: const [], prompts: const []),
    characterConfigList: [
      CharacterConfig.fromEmpty()..positivePromptConfig.strs = ['silver hair'],
    ],
    savedPromptConfigList: const [],
    paramConfig: ParamConfig(negativePrompt: 'bad hands'),
    settings: Settings.fromJson({}),
    overridePrompt: '',
    useOverridePrompt: false,
    useCharacterPromptWithOverride: false,
  );
}

Widget _host(PayloadConfig payload) {
  return EasyLocalization(
    supportedLocales: const [Locale('en')],
    path: 'assets/l10n',
    assetLoader: const _WorkbenchAssetLoader(),
    fallbackLocale: const Locale('en'),
    startLocale: const Locale('en'),
    saveLocale: false,
    child: Builder(
      builder: (context) {
        return MaterialApp(
          theme: StudioTheme.build(),
          locale: context.locale,
          supportedLocales: context.supportedLocales,
          localizationsDelegates: context.localizationDelegates,
          home: Scaffold(
            body: SizedBox(
              width: 900,
              height: 760,
              child: WorkbenchCreativeInputsPanel(
                parametersViewmodel:
                    WorkbenchSingleImageParametersViewmodel(payload),
              ),
            ),
          ),
        );
      },
    ),
  );
}

Future<void> _addPromptTags(
  WidgetTester tester,
  Finder editor,
  String text,
) async {
  final addButton = find.descendant(
    of: editor,
    matching: find.byKey(const ValueKey('prompt-tag-editor-add')),
  );
  await tester.ensureVisible(addButton);
  await tester.pump();
  await tester.tap(addButton);
  await tester.pumpAndSettle();
  await tester.enterText(
    find.descendant(
      of: editor,
      matching: find.byKey(const ValueKey('prompt-tag-editor-input')),
    ),
    text,
  );
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pumpAndSettle();
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

  tearDown(() async {
    await GetIt.I.reset();
  });

  testWidgets('negative and character prompts are edited as tags',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final payload = _payload();
    GetIt.I.registerSingleton<PayloadConfig>(payload);

    await tester.pumpWidget(_host(payload));
    await tester.pumpAndSettle();

    final negativeEditor =
        find.byKey(const ValueKey('workbench-negative-prompt-editor'));
    expect(negativeEditor, findsOneWidget);
    expect(
      find.descendant(
          of: negativeEditor, matching: find.byType(PromptTagEditor)),
      findsOneWidget,
    );

    await _addPromptTags(tester, negativeEditor, 'low quality, blurry');

    expect(
        payload.paramConfig.negativePrompt, 'bad hands, low quality, blurry');

    await tester.tap(find.byKey(const ValueKey('workbench-character-card-0')));
    await tester.pumpAndSettle();

    final characterEditor =
        find.byKey(const ValueKey('workbench-character-prompt-0'));
    expect(characterEditor, findsOneWidget);
    expect(
      find.descendant(
        of: characterEditor,
        matching: find.byType(PromptTagEditor),
      ),
      findsOneWidget,
    );

    await _addPromptTags(tester, characterEditor, 'blue eyes, smile');

    expect(
      payload.characterConfigList.single.positivePromptConfig.strs,
      ['silver hair, blue eyes, smile'],
    );
  });

  testWidgets('negative prompt editor uses negative tag category colors',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final payload = _payload();
    GetIt.I.registerSingleton<PayloadConfig>(payload);

    await tester.pumpWidget(_host(payload));
    await tester.pumpAndSettle();

    final negativeEditor =
        find.byKey(const ValueKey('workbench-negative-prompt-editor'));
    final marker = tester.widget<DecoratedBox>(
      find.descendant(
        of: negativeEditor,
        matching: find.byKey(
          const ValueKey('prompt-tag-editor-chip-marker-0'),
        ),
      ),
    );
    final decoration = marker.decoration as BoxDecoration;

    expect(decoration.color, const Color(0xFFDB2777));
  });
}
