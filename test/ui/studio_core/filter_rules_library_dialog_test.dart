import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/studio/tools/filter_rule_config.dart';
import 'package:nai_casrand/data/workspace/models/workspace_entities.dart';
import 'package:nai_casrand/ui/studio_core/theme/studio_tokens.dart';
import 'package:nai_casrand/ui/studio_core/widgets/filter_rules_library_dialog.dart';

class _FilterRulesAssetLoader extends AssetLoader {
  const _FilterRulesAssetLoader();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async {
    return const {
      'filter_rules_library_title': 'Filter Rules Library',
      'filter_rules_delete_keywords': 'Delete keywords',
      'filter_rules_strong_keywords': 'Strong filter keywords',
      'filter_rules_replace_rules': 'Replace rules',
      'filter_rules_empty_block': 'No rules in this block',
      'filter_rules_add_tag': 'Add tag',
      'filter_rules_batch_add_tags': 'Batch add tags',
      'filter_rules_add_replace_rule': 'Add replacement',
      'filter_rules_replace_source': 'Source',
      'filter_rules_replace_target': 'Target',
      'cancel': 'Cancel',
      'save': 'Save',
    };
  }
}

class _LocalizedDialogApp extends StatelessWidget {
  final FilterRuleConfig initialConfig;
  final FilterRulesConfigSaver onSave;
  final FilterRulesAvailableTagsLoader? loadAvailableTags;

  const _LocalizedDialogApp({
    this.initialConfig = const FilterRuleConfig(
      deleteKeywords: 'lowres',
      strongFilterKeywords: 'mosaic',
      replaceRules: 'old -> new',
      removeWeights: true,
      exactMatch: true,
      deleteArtistTags: false,
    ),
    this.onSave = _noopSave,
    this.loadAvailableTags,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      locale: context.locale,
      supportedLocales: context.supportedLocales,
      localizationsDelegates: context.localizationDelegates,
      home: Scaffold(
        body: FilterRulesLibraryDialog(
          initialConfig: initialConfig,
          onSave: onSave,
          loadAvailableTags: loadAvailableTags,
        ),
      ),
    );
  }
}

Future<void> _noopSave(FilterRuleConfig config) async {}

const _sharedPreferencesChannel = MethodChannel(
  'plugins.flutter.io/shared_preferences',
);

Future<void> _pumpLocalizedDialog(
  WidgetTester tester, {
  FilterRuleConfig initialConfig = const FilterRuleConfig(
    deleteKeywords: 'lowres',
    strongFilterKeywords: 'mosaic',
    replaceRules: 'old -> new',
    removeWeights: true,
    exactMatch: true,
    deleteArtistTags: false,
  ),
  FilterRulesConfigSaver onSave = _noopSave,
  FilterRulesAvailableTagsLoader? loadAvailableTags,
}) async {
  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('en')],
      path: 'assets/l10n',
      assetLoader: const _FilterRulesAssetLoader(),
      fallbackLocale: const Locale('en'),
      startLocale: const Locale('en'),
      saveLocale: false,
      child: _LocalizedDialogApp(
        initialConfig: initialConfig,
        onSave: onSave,
        loadAvailableTags: loadAvailableTags,
      ),
    ),
  );
  await tester.pump();
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

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_sharedPreferencesChannel, null);
  });

  testWidgets('filter rules library renders block-managed sections',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpLocalizedDialog(tester);

    for (final label in const [
      'Filter Rules Library',
      'Delete keywords',
      'Strong filter keywords',
      'Replace rules',
      'Cancel',
      'Save',
    ]) {
      expect(find.text(label), findsOneWidget);
    }

    expect(
      find.byKey(const ValueKey('filter-rules-tag-search-field')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('filter-rules-add-typed-tag')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('filter-rule-layout-toggle-delete')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('filter-rule-section-add-delete')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('filter-rule-section-batch-add-delete')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('filter-rule-token-delete-all-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('filter-rule-token-delete-all-0-up')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('filter-rule-token-delete-all-0-down')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('filter-rule-block-delete-camera')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('filter-rules-remove-weights')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('filter-rules-exact-match')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('filter-rules-delete-artists')),
      findsNothing,
    );
  });

  testWidgets('filter rule tags are added from the target block',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    FilterRuleConfig? saved;

    await _pumpLocalizedDialog(
      tester,
      initialConfig: const FilterRuleConfig(
        deleteKeywords: 'lowres, cinematic lighting',
        strongFilterKeywords: 'mosaic',
        replaceRules: 'old jacket -> new coat',
      ),
      onSave: (config) async {
        saved = config;
      },
      loadAvailableTags: () async => const [
        TagEntry(
          id: 'camera-light',
          tag: 'cinematic lighting',
          zh: 'cinematic lighting',
          block: 'camera',
          category: 'lighting',
        ),
      ],
    );

    expect(
      find.byKey(const ValueKey('filter-rule-token-delete-all-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('filter-rule-token-delete-all-1')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('filter-rule-token-delete-all-0-remove')),
    );
    await tester.pumpAndSettle();
    expect(find.text('lowres'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('filter-rule-token-delete-all-0-edit')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('filter-rule-tag-edit-field')),
      'bad framing',
    );
    await tester.tap(find.byKey(const ValueKey('filter-rule-tag-edit-save')));
    await tester.pumpAndSettle();

    final addDelete =
        find.byKey(const ValueKey('filter-rule-section-add-delete'));
    await tester.ensureVisible(addDelete);
    await tester.pumpAndSettle();
    await tester.tap(addDelete);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('filter-rule-tag-edit-field')),
      'low angle',
    );
    await tester.tap(find.byKey(const ValueKey('filter-rule-tag-edit-save')));
    await tester.pumpAndSettle();

    final lowAngleToken =
        find.byKey(const ValueKey('filter-rule-token-delete-all-1'));
    final badFramingToken =
        find.byKey(const ValueKey('filter-rule-token-delete-all-0'));
    await tester.dragFrom(
      tester.getCenter(lowAngleToken),
      tester.getCenter(badFramingToken) - tester.getCenter(lowAngleToken),
    );
    await tester.pumpAndSettle();

    tester
        .widget<FilledButton>(find.byKey(const ValueKey('filter-rules-save')))
        .onPressed!();
    await tester.pumpAndSettle();

    expect(saved?.deleteKeywords, 'low angle, bad framing');
    expect(saved?.strongFilterKeywords, 'mosaic');
    expect(saved?.replaceRules, 'old jacket -> new coat');
  });

  testWidgets('filter rule sections switch to non-empty grouped blocks',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpLocalizedDialog(
      tester,
      initialConfig: const FilterRuleConfig(
        deleteKeywords: 'lowres, cinematic lighting',
      ),
      loadAvailableTags: () async => const [
        TagEntry(
          id: 'camera-light',
          tag: 'cinematic lighting',
          block: 'camera',
          category: 'lighting',
        ),
      ],
    );

    expect(
      find.byKey(const ValueKey('filter-rule-block-delete-style')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey('filter-rule-layout-toggle-delete')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('filter-rule-block-delete-style')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('filter-rule-block-delete-camera')),
      findsOneWidget,
    );
    final sectionWidth = tester
        .getSize(find.byKey(const ValueKey('filter-rule-section-delete')))
        .width;
    final cameraBlockWidth = tester
        .getSize(find.byKey(const ValueKey('filter-rule-block-delete-camera')))
        .width;
    expect(cameraBlockWidth, greaterThan(sectionWidth * 0.9));
    expect(
      find.byKey(const ValueKey('filter-rule-block-delete-action')),
      findsNothing,
    );
  });

  testWidgets('filter rule blocks can batch add tags', (tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    FilterRuleConfig? saved;

    await _pumpLocalizedDialog(
      tester,
      initialConfig: const FilterRuleConfig(deleteKeywords: 'lowres'),
      onSave: (config) async {
        saved = config;
      },
    );

    final batchAdd = find.byKey(
      const ValueKey('filter-rule-section-batch-add-delete'),
    );
    await tester.ensureVisible(batchAdd);
    await tester.pumpAndSettle();
    await tester.tap(batchAdd);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('filter-rule-batch-tag-edit-field')),
      'city lights\nnight rain, train platform',
    );
    await tester.tap(
      find.byKey(const ValueKey('filter-rule-batch-tag-edit-save')),
    );
    await tester.pumpAndSettle();

    tester
        .widget<FilledButton>(find.byKey(const ValueKey('filter-rules-save')))
        .onPressed!();
    await tester.pumpAndSettle();

    expect(
      saved?.deleteKeywords,
      'lowres, city lights, night rain, train platform',
    );
  });

  testWidgets('filter rule add dialog and tokens expose hover feedback',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpLocalizedDialog(
      tester,
      initialConfig: const FilterRuleConfig(deleteKeywords: 'lowres'),
    );

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(
      tester.getCenter(
        find.byKey(const ValueKey('filter-rule-token-delete-all-0')),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 180));

    final tokenSurface = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey('filter-rule-token-delete-all-0-surface')),
    );
    final tokenDecoration = tokenSurface.decoration! as BoxDecoration;
    final tokenBorder = tokenDecoration.border! as Border;
    expect(tokenDecoration.color, StudioTokens.surface4);
    expect(tokenBorder.top.color, StudioTokens.borderStrong);

    final addDelete =
        find.byKey(const ValueKey('filter-rule-section-add-delete'));
    await tester.ensureVisible(addDelete);
    await tester.pumpAndSettle();
    await tester.tap(addDelete);
    await tester.pumpAndSettle();

    final saveButton = tester.widget<FilledButton>(
      find.byKey(const ValueKey('filter-rule-tag-edit-save')),
    );
    expect(
      saveButton.style?.overlayColor?.resolve({WidgetState.hovered}),
      StudioTokens.onPrimary.withAlpha(36),
    );
  });

  testWidgets('filter rules can add replacement rules from a block',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    FilterRuleConfig? saved;

    await _pumpLocalizedDialog(
      tester,
      initialConfig: const FilterRuleConfig(replaceRules: 'old -> new'),
      onSave: (config) async {
        saved = config;
      },
    );

    final addClothingReplace =
        find.byKey(const ValueKey('filter-rule-section-add-replace'));
    await tester.ensureVisible(addClothingReplace);
    await tester.pumpAndSettle();
    await tester.tap(addClothingReplace);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('filter-rule-replace-source-edit-field')),
      'blue dress',
    );
    await tester.enterText(
      find.byKey(const ValueKey('filter-rule-replace-target-edit-field')),
      'blue coat',
    );
    await tester.tap(
      find.byKey(const ValueKey('filter-rule-replace-edit-save')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('filter-rule-replace-row-all-1')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('filter-rule-replace-row-all-0-remove')),
    );
    await tester.pumpAndSettle();

    tester
        .widget<FilledButton>(find.byKey(const ValueKey('filter-rules-save')))
        .onPressed!();
    await tester.pumpAndSettle();

    expect(saved?.replaceRules, 'blue dress -> blue coat');
  });

  testWidgets(
      'filter rule tags show translated color chips without nested groups',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpLocalizedDialog(
      tester,
      initialConfig: const FilterRuleConfig(
        deleteKeywords: 'masterpiece, artist: sy4',
      ),
      loadAvailableTags: () async => const [
        TagEntry(
          id: 'tag-artist',
          tag: 'artist: sy4',
          zh: 'artist sy4',
          block: 'style',
          category: 'artist',
        ),
      ],
    );

    expect(
      find.byKey(const ValueKey('filter-rule-layout-toggle-delete')),
      findsOneWidget,
    );
    expect(find.text('artist sy4'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('prompt-tag-group-quality')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('prompt-tag-group-artist')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey('filter-rule-layout-toggle-delete')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('filter-rule-block-delete-style')),
      findsOneWidget,
    );
    expect(find.text('artist sy4'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('prompt-tag-group-artist')),
      findsNothing,
    );
  });
}
