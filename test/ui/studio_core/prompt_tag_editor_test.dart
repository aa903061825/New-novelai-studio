import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:novel_studio/data/models/character_config.dart';
import 'package:novel_studio/data/models/param_config.dart';
import 'package:novel_studio/data/models/payload_config.dart';
import 'package:novel_studio/data/models/prompt_config.dart';
import 'package:novel_studio/data/models/settings.dart';
import 'package:novel_studio/data/studio/services/prompt_translation_service.dart';
import 'package:novel_studio/data/studio/tools/online_ai_tools.dart';
import 'package:novel_studio/data/studio/tools/translation_cache.dart';
import 'package:novel_studio/ui/studio_core/services/prompt_tag_auto_translation_queue.dart';
import 'package:novel_studio/ui/studio_core/services/prompt_tag_filter_rules.dart';
import 'package:novel_studio/ui/studio_core/theme/studio_theme.dart';
import 'package:novel_studio/ui/studio_core/theme/studio_tokens.dart';
import 'package:novel_studio/ui/studio_core/widgets/prompt_tag_drag.dart';
import 'package:novel_studio/ui/studio_core/widgets/prompt_tag_display.dart'
    hide
        PromptTagFilterRuleAdder,
        PromptTagFilterRuleTarget,
        PromptTagFilterRulesController;
import 'package:novel_studio/ui/studio_core/widgets/prompt_tag_editor.dart';

Widget _host(Widget child) {
  return MaterialApp(
    theme: StudioTheme.build(),
    home: Scaffold(
        body: Padding(padding: const EdgeInsets.all(16), child: child)),
  );
}

Finder _editorChip(int index) {
  return find.byKey(ValueKey('prompt-tag-editor-chip-$index'));
}

PayloadConfig _payloadConfig({String translationProvider = 'ai'}) {
  return PayloadConfig(
    rootPromptConfig: PromptConfig(strs: const [], prompts: const []),
    characterConfigList: const <CharacterConfig>[],
    savedPromptConfigList: const <PromptConfig>[],
    paramConfig: ParamConfig(),
    settings: Settings.fromJson({
      'translation_provider': translationProvider,
    }),
    overridePrompt: '',
    useOverridePrompt: false,
    useCharacterPromptWithOverride: false,
  );
}

Rect _dropAreaRectContaining(WidgetTester tester, Finder chip) {
  final chipCenter = tester.getCenter(chip);
  for (final element
      in find.byKey(const ValueKey('prompt-tag-editor-drop-area')).evaluate()) {
    final box = element.renderObject as RenderBox;
    final topLeft = box.localToGlobal(Offset.zero);
    final rect = topLeft & box.size;
    if (rect.contains(chipCenter)) {
      return rect;
    }
  }
  throw StateError('No prompt tag editor drop area contains the chip.');
}

Future<void> _dragSelectionAround(
  WidgetTester tester,
  Finder first,
  Finder last, {
  bool additive = false,
}) async {
  if (additive) {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  }
  final start =
      _dropAreaRectContaining(tester, first).topLeft + const Offset(1, 1);
  final end = tester.getBottomRight(last) - const Offset(1, 1);
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: start);
  await tester.pump();

  await mouse.down(start);
  await mouse.moveTo(end);
  await tester.pump();
  await mouse.up();
  await tester.pump();
  await mouse.removePointer();
  if (additive) {
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  }
}

Future<void> _tapEditorBlankSpace(WidgetTester tester, Finder chip) async {
  final rect = _dropAreaRectContaining(tester, chip);
  await tester.tapAt(rect.bottomRight - const Offset(8, 8));
  await tester.pump();
}

void main() {
  tearDown(() async {
    PromptTagAutoTranslationQueue.instance.resetForTesting();
    await GetIt.I.reset();
  });

  testWidgets('shows translated labels by default and toggles from the toolbar',
      (tester) async {
    String value = 'blue eyes, long hair';
    GetIt.I.registerSingleton<TranslationCache>(
      TranslationCache(clock: () => 1710000000)
        ..setManual('blue eyes', '蓝眼睛')
        ..setManual('long hair', '长发'),
    );

    await tester.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (context, setState) {
            return PromptTagEditor(
              value: value,
              onChanged: (next) => setState(() => value = next),
            );
          },
        ),
      ),
    );

    expect(find.text('blue eyes'), findsOneWidget);
    expect(find.text('long hair'), findsOneWidget);
    expect(find.text('蓝眼睛'), findsOneWidget);
    expect(find.text('长发'), findsOneWidget);
    expect(value, 'blue eyes, long hair');

    await tester.tap(
      find.byKey(const ValueKey('prompt-tag-editor-translation-toggle')),
    );
    await tester.pumpAndSettle();

    expect(find.text('blue eyes'), findsOneWidget);
    expect(find.text('long hair'), findsOneWidget);
    expect(find.text('蓝眼睛'), findsNothing);
    expect(find.text('长发'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('prompt-tag-editor-translation-toggle')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('prompt-tag-editor-delete-0')));
    await tester.pumpAndSettle();

    expect(value, 'long hair');
    expect(find.text('long hair'), findsOneWidget);
    expect(find.text('长发'), findsOneWidget);
    expect(find.text('blue eyes'), findsNothing);
    expect(find.text('蓝眼睛'), findsNothing);
  });

  testWidgets('single editor tag drag feedback reuses chip presentation', (
    tester,
  ) async {
    GetIt.I.registerSingleton<TranslationCache>(
      TranslationCache(clock: () => 1710000000)
        ..setManual('blue eyes', 'blue translated'),
    );

    await tester.pumpWidget(
      _host(
        PromptTagEditor(
          value: 'blue eyes, long hair',
          initialShowTranslations: true,
          onChanged: (_) {},
        ),
      ),
    );

    final chip = _editorChip(0);
    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryMouseButton,
    );
    await gesture.down(tester.getCenter(chip));
    await tester.pump();
    await gesture.moveBy(const Offset(72, 24));
    await tester.pump();

    final feedbackBody = find.byKey(
      const ValueKey('prompt-tag-drag-feedback-chip-body'),
    );
    expect(feedbackBody, findsOneWidget);
    expect(
      find.byKey(const ValueKey('prompt-tag-editor-selection-rectangle')),
      findsNothing,
    );
    expect(
      find.descendant(
        of: feedbackBody,
        matching: find.text('blue translated'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('prompt-tag-drag-feedback-chip-check')),
      findsNothing,
    );
    final marker = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('prompt-tag-drag-feedback-chip-marker')),
    );
    expect(
      (marker.decoration as BoxDecoration).color,
      const Color(0xFF5B8DEF),
    );
    final body = tester.widget<AnimatedContainer>(feedbackBody);
    expect((body.decoration! as BoxDecoration).color, StudioTokens.surface3);

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 50));
  });

  testWidgets('multi editor tag drag feedback uses the drag start chip', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        PromptTagEditor(
          value: 'blue eyes, long hair',
          onChanged: (_) {},
        ),
      ),
    );

    await _dragSelectionAround(tester, _editorChip(0), _editorChip(1));

    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryMouseButton,
    );
    await gesture.down(tester.getCenter(_editorChip(1)));
    await tester.pump();
    await gesture.moveBy(const Offset(72, 24));
    await tester.pump();

    final feedbackBody = find.byKey(
      const ValueKey('prompt-tag-drag-feedback-chip-body'),
    );
    expect(
      find.descendant(of: feedbackBody, matching: find.text('long hair')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: feedbackBody, matching: find.text('blue eyes')),
      findsNothing,
    );
    expect(find.text('x2'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('prompt-tag-drag-feedback-count-badge')),
      findsOneWidget,
    );

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 50));
  });

  testWidgets('preferTranslatedLabels promotes cached translation to primary',
      (tester) async {
    GetIt.I.registerSingleton<TranslationCache>(
      TranslationCache(clock: () => 1710000000)
        ..setManual('animal_ears', 'cached animal ears'),
    );

    await tester.pumpWidget(
      _host(
        PromptTagEditor(
          value: 'animal_ears',
          initialShowTranslations: true,
          onChanged: (_) {},
          showControls: false,
          preferTranslatedLabels: true,
        ),
      ),
    );

    final chip = find.byKey(const ValueKey('prompt-tag-editor-chip-0'));
    final labels = tester
        .widgetList<Text>(
            find.descendant(of: chip, matching: find.byType(Text)))
        .map((widget) => widget.data)
        .whereType<String>()
        .toList(growable: false);

    expect(labels.take(2), ['cached animal ears', 'animal_ears']);
  });

  testWidgets('single chip delete clears shared selection state',
      (tester) async {
    String value = 'blue eyes, long hair';
    final selectionController = PromptTagSelectionController();
    addTearDown(selectionController.dispose);

    await tester.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (context, setState) {
            return PromptTagEditor(
              value: value,
              selectionController: selectionController,
              selectionFieldId: 'role-output-part-test',
              onChanged: (next) => setState(() => value = next),
            );
          },
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('prompt-tag-editor-delete-0')));
    await tester.pumpAndSettle();

    expect(value, 'long hair');
    expect(selectionController.selectedCount, 0);
    expect(find.text('long hair'), findsOneWidget);
    expect(find.text('blue eyes'), findsNothing);
  });

  test('shared selection normal tap replaces previous field selection', () {
    final selectionController = PromptTagSelectionController();
    addTearDown(selectionController.dispose);

    selectionController.toggle('role-output-part-slot-stage-upperClothing', 0);
    selectionController.toggle('role-source-part-slot-stage-upperClothing', 0);

    expect(
      selectionController.selectedCountFor(
        'role-output-part-slot-stage-upperClothing',
      ),
      0,
    );
    expect(
      selectionController.selectedCountFor(
        'role-source-part-slot-stage-upperClothing',
      ),
      1,
    );
  });

  test('shared field selection replaces previous field selection', () {
    final selectionController = PromptTagSelectionController();
    addTearDown(selectionController.dispose);

    selectionController.setFieldSelection(
      'role-output-part-slot-stage-upperClothing',
      {0},
    );
    selectionController.setFieldSelection(
      'role-source-part-slot-stage-upperClothing',
      {0},
    );

    expect(
      selectionController.selectedCountFor(
        'role-output-part-slot-stage-upperClothing',
      ),
      0,
    );
    expect(
      selectionController.selectedCountFor(
        'role-source-part-slot-stage-upperClothing',
      ),
      1,
    );
  });

  testWidgets(
    'source display drag into replacement editor keeps source prompt selected after prior output selection',
    (tester) async {
      const sourceFieldId = 'role-source-part-slot-stage-upperClothing';
      const outputFieldId = 'role-output-part-slot-stage-upperClothing';
      var source = 'cat ears';
      var output = 'old cloak';
      final selectionController = PromptTagSelectionController();
      addTearDown(selectionController.dispose);

      await tester.pumpWidget(
        _host(
          StatefulBuilder(
            builder: (context, setState) {
              return Column(
                children: [
                  PromptTagDisplay(
                    key: const ValueKey('source-display'),
                    text: source,
                    enableTagActions: true,
                    selectionController: selectionController,
                    selectionFieldId: sourceFieldId,
                    onChanged: (next) => setState(() => source = next),
                  ),
                  const SizedBox(height: 24),
                  PromptTagEditor(
                    key: const ValueKey('output-editor'),
                    value: output,
                    selectionController: selectionController,
                    selectionFieldId: outputFieldId,
                    removeDroppedTagsFromSource: (data) {
                      return !data.sourceFieldIds.any(
                        (fieldId) => fieldId.startsWith(
                          'role-source-part-slot-stage-',
                        ),
                      );
                    },
                    onChanged: (next) => setState(() => output = next),
                  ),
                ],
              );
            },
          ),
        ),
      );

      selectionController.setFieldSelection(outputFieldId, {0});
      await tester.pump();

      final sourceChip = find.descendant(
        of: find.byKey(const ValueKey('source-display')),
        matching: find.byKey(
          const ValueKey('prompt-tag-chip-cat ears-0-idle'),
        ),
      );
      await tester.tap(sourceChip);
      await tester.pump();
      final selectedSourceChip = find.descendant(
        of: find.byKey(const ValueKey('source-display')),
        matching: find.byKey(
          const ValueKey('prompt-tag-chip-cat ears-0-selected'),
        ),
      );
      final outputDropArea = find.descendant(
        of: find.byKey(const ValueKey('output-editor')),
        matching: find.byKey(
          const ValueKey('prompt-tag-editor-selection-area'),
        ),
      );

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      final start = tester.getCenter(selectedSourceChip);
      final end = tester.getCenter(outputDropArea);
      await mouse.addPointer(location: start);
      await tester.pump();
      await mouse.down(start);
      await mouse.moveTo(end);
      await tester.pump();
      await mouse.up();
      await tester.pumpAndSettle();
      await mouse.removePointer();

      expect(source, 'cat ears');
      expect(output, 'old cloak, cat ears');
    },
  );

  testWidgets('source order chips keep the prompt tag category color stripe',
      (tester) async {
    await tester.pumpWidget(
      _host(
        PromptTagEditor(
          value: 'blue eyes, white shirt',
          onChanged: (_) {},
        ),
      ),
    );

    final characterMarker = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('prompt-tag-editor-chip-marker-0')),
    );
    final characterDecoration = characterMarker.decoration as BoxDecoration;
    expect(characterDecoration.color, const Color(0xFF5B8DEF));

    final clothingMarker = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('prompt-tag-editor-chip-marker-1')),
    );
    final clothingDecoration = clothingMarker.decoration as BoxDecoration;
    expect(clothingDecoration.color, const Color(0xFF00A676));
  });

  testWidgets('auto translates tags missing from the cache', (tester) async {
    GetIt.I.registerSingleton<TranslationCache>(
      TranslationCache(clock: () => 1710000000),
    );
    GetIt.I.registerSingleton<PromptTranslationService>(
      _FakePromptTranslationService((request) async {
        if (request.text == 'animal ears') {
          return const OnlineTranslationResult(
            text: '动物耳朵',
            source: OnlineAiResultSource.online,
            providerName: 'fake',
          );
        }
        return const OnlineTranslationResult(
          text: '',
          source: OnlineAiResultSource.emptyFallback,
        );
      }),
    );

    await tester.pumpWidget(
      _host(
        PromptTagEditor(
          value: 'animal ears',
          initialShowTranslations: true,
          onChanged: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('animal ears'), findsOneWidget);
    expect(find.text('动物耳朵'), findsOneWidget);
    expect(
      GetIt.I<TranslationCache>().getCached('animal ears'),
      '动物耳朵',
    );
  });

  testWidgets('dense editors auto translate without visible controls',
      (tester) async {
    GetIt.I.registerSingleton<TranslationCache>(
      TranslationCache(clock: () => 1710000000),
    );
    GetIt.I.registerSingleton<PromptTranslationService>(
      _FakePromptTranslationService((request) async {
        if (request.text == 'public restrooms') {
          return const OnlineTranslationResult(
            text: '公共厕所',
            source: OnlineAiResultSource.online,
            providerName: 'fake',
          );
        }
        return const OnlineTranslationResult(
          text: '',
          source: OnlineAiResultSource.emptyFallback,
        );
      }),
    );

    await tester.pumpWidget(
      _host(
        PromptTagEditor(
          value: 'public restrooms',
          initialShowTranslations: true,
          onChanged: (_) {},
          dense: true,
          showControls: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('public restrooms'), findsOneWidget);
    expect(find.text('公共厕所'), findsOneWidget);
  });

  testWidgets('auto translation merges duplicate work across editors',
      (tester) async {
    final requestedTags = <String>[];
    final completion = Completer<OnlineTranslationResult>();
    GetIt.I.registerSingleton<TranslationCache>(
      TranslationCache(clock: () => 1710000000),
    );
    GetIt.I.registerSingleton<PromptTranslationService>(
      _FakePromptTranslationService((request) async {
        requestedTags.add(request.text);
        return completion.future;
      }),
    );

    await tester.pumpWidget(
      _host(
        Column(
          children: [
            PromptTagEditor(
              value: 'queue duplicate alpha',
              initialShowTranslations: true,
              onChanged: (_) {},
            ),
            PromptTagEditor(
              value: 'queue duplicate alpha',
              initialShowTranslations: true,
              onChanged: (_) {},
            ),
          ],
        ),
      ),
    );
    await tester.pump();

    expect(requestedTags, ['queue duplicate alpha']);

    completion.complete(
      const OnlineTranslationResult(
        text: '蓝眼睛',
        source: OnlineAiResultSource.online,
        providerName: 'fake',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('蓝眼睛'), findsNWidgets(2));
  });

  testWidgets('manual retranslate joins in-flight auto translation',
      (tester) async {
    final requestedTags = <String>[];
    final completion = Completer<OnlineTranslationResult>();
    GetIt.I.registerSingleton<TranslationCache>(
      TranslationCache(clock: () => 1710000000),
    );
    GetIt.I.registerSingleton<PromptTranslationService>(
      _FakePromptTranslationService((request) async {
        requestedTags.add(request.text);
        return completion.future;
      }),
    );

    await tester.pumpWidget(
      _host(
        PromptTagEditor(
          value: 'queue duplicate alpha',
          initialShowTranslations: true,
          onChanged: (_) {},
        ),
      ),
    );
    await tester.pump();

    expect(requestedTags, ['queue duplicate alpha']);

    await tester.tap(
      find.text('queue duplicate alpha'),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('prompt-tag-editor-ai-retranslate')),
    );
    await tester.pump();

    expect(requestedTags, ['queue duplicate alpha']);

    completion.complete(
      const OnlineTranslationResult(
        text: '蓝眼睛',
        source: OnlineAiResultSource.online,
        providerName: 'fake',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('蓝眼睛'), findsOneWidget);
  });

  testWidgets('auto translation processes tags sequentially', (tester) async {
    final requestedTags = <String>[];
    final completions = <String, Completer<OnlineTranslationResult>>{};
    GetIt.I.registerSingleton<TranslationCache>(
      TranslationCache(clock: () => 1710000000),
    );
    GetIt.I.registerSingleton<PromptTranslationService>(
      _FakePromptTranslationService((request) async {
        requestedTags.add(request.text);
        final completion = Completer<OnlineTranslationResult>();
        completions[request.text] = completion;
        return completion.future;
      }),
    );

    await tester.pumpWidget(
      _host(
        PromptTagEditor(
          value: 'tag one, tag two, tag three',
          initialShowTranslations: true,
          onChanged: (_) {},
        ),
      ),
    );
    await tester.pump();

    expect(requestedTags, ['tag one']);

    completions['tag one']!.complete(
      const OnlineTranslationResult(
        text: '翻译一',
        source: OnlineAiResultSource.online,
        providerName: 'fake',
      ),
    );
    await tester.pumpAndSettle();

    expect(requestedTags, ['tag one', 'tag two']);
    expect(find.text('翻译一'), findsOneWidget);
    expect(find.text('translated tag one'), findsNothing);

    completions['tag two']!.complete(
      const OnlineTranslationResult(
        text: '翻译二',
        source: OnlineAiResultSource.online,
        providerName: 'fake',
      ),
    );
    await tester.pumpAndSettle();

    expect(requestedTags, ['tag one', 'tag two', 'tag three']);
    expect(find.text('翻译二'), findsOneWidget);

    completions['tag three']!.complete(
      const OnlineTranslationResult(
        text: '翻译三',
        source: OnlineAiResultSource.online,
        providerName: 'fake',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('翻译三'), findsOneWidget);
  });

  testWidgets('auto translation limit can still opt out large groups',
      (tester) async {
    final requestedTags = <String>[];
    GetIt.I.registerSingleton<TranslationCache>(
      TranslationCache(clock: () => 1710000000),
    );
    GetIt.I.registerSingleton<PromptTranslationService>(
      _FakePromptTranslationService((request) async {
        requestedTags.add(request.text);
        return const OnlineTranslationResult(
          text: 'translated',
          source: OnlineAiResultSource.online,
          providerName: 'fake',
        );
      }),
    );

    await tester.pumpWidget(
      _host(
        PromptTagEditor(
          value: 'tag one, tag two, tag three',
          initialShowTranslations: true,
          onChanged: (_) {},
          autoTranslateTagLimit: 2,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(requestedTags, isEmpty);
    expect(find.text('tag one'), findsOneWidget);
    expect(find.text('translated'), findsNothing);
  });

  testWidgets('editor falls back to payload translation settings',
      (tester) async {
    GetIt.I.registerSingleton<PayloadConfig>(
      _payloadConfig(translationProvider: 'google'),
    );

    await tester.pumpWidget(
      _host(
        PromptTagEditor(
          value: 'public restrooms',
          onChanged: (_) {},
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('prompt-tag-editor-chip-0')),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();

    expect(find.text('Google重译'), findsOneWidget);
  });

  testWidgets('translation toggle switches translated secondary labels off',
      (tester) async {
    GetIt.I.registerSingleton<TranslationCache>(
      TranslationCache(clock: () => 1710000000)..setManual('blue eyes', '蓝眼睛'),
    );

    await tester.pumpWidget(
      _host(
        PromptTagEditor(
          value: 'blue eyes',
          initialShowTranslations: true,
          onChanged: (_) {},
        ),
      ),
    );

    expect(find.text('blue eyes'), findsOneWidget);
    expect(find.text('蓝眼睛'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('prompt-tag-editor-translation-toggle')),
    );
    await tester.pumpAndSettle();

    expect(find.text('blue eyes'), findsOneWidget);
    expect(find.text('蓝眼睛'), findsNothing);
  });

  testWidgets('each editor tag can toggle its own translation', (tester) async {
    GetIt.I.registerSingleton<TranslationCache>(
      TranslationCache(clock: () => 1710000000)
        ..setManual('blue eyes', '蓝眼睛')
        ..setManual('long hair', '长发'),
    );

    await tester.pumpWidget(
      _host(
        PromptTagEditor(
          value: 'blue eyes, long hair',
          initialShowTranslations: true,
          onChanged: (_) {},
        ),
      ),
    );

    expect(find.text('蓝眼睛'), findsOneWidget);
    expect(find.text('长发'), findsOneWidget);

    await tester.tap(
      find.byKey(
        const ValueKey('prompt-tag-editor-translation-toggle-0'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('蓝眼睛'), findsNothing);
    expect(find.text('长发'), findsOneWidget);

    await tester.tap(
      find.byKey(
        const ValueKey('prompt-tag-editor-translation-toggle-0'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('蓝眼睛'), findsOneWidget);
  });

  testWidgets('chips do not expose duplicate text as hover tooltips',
      (tester) async {
    GetIt.I.registerSingleton<TranslationCache>(
      TranslationCache(clock: () => 1710000000)..setManual('blue eyes', '蓝眼睛'),
    );

    await tester.pumpWidget(
      _host(
        PromptTagEditor(
          value: 'blue eyes',
          onChanged: (_) {},
        ),
      ),
    );

    final tooltipMessages = tester
        .widgetList<Tooltip>(find.byType(Tooltip))
        .map((tooltip) => tooltip.message ?? tooltip.richMessage?.toString())
        .whereType<String>();

    expect(
      tooltipMessages.where(
        (message) => message.contains('blue eyes') || message.contains('蓝眼睛'),
      ),
      isEmpty,
    );
  });

  testWidgets('can start in grouped layout', (tester) async {
    await tester.pumpWidget(
      _host(
        PromptTagEditor(
          value: 'best quality, blue eyes, white shirt, walking',
          onChanged: (_) {},
          initialGroupedLayout: true,
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('prompt-tag-editor-group-quality')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('prompt-tag-editor-group-clothing')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('prompt-tag-editor-group-action')),
      findsOneWidget,
    );
  });

  testWidgets('layout toggle switches source order tags into grouped blocks',
      (tester) async {
    await tester.pumpWidget(
      _host(
        PromptTagEditor(
          value: 'masterpiece, artist: sy4, blue eyes, standing',
          onChanged: (_) {},
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('prompt-tag-editor-group-quality')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey('prompt-tag-editor-layout-toggle')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('prompt-tag-editor-group-quality')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('prompt-tag-editor-group-artist')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('prompt-tag-editor-group-character')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('prompt-tag-editor-group-action')),
      findsOneWidget,
    );
  });

  testWidgets('layout controls can switch into role field groups',
      (tester) async {
    await tester.pumpWidget(
      _host(
        SingleChildScrollView(
          child: PromptTagEditor(
            value:
                'girl, collarbone, white shirt, black shorts, dress, fox tail',
            onChanged: (_) {},
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('prompt-tag-editor-group-upperBody')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey('prompt-tag-editor-layout-layered')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('prompt-tag-editor-group-character')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('prompt-tag-editor-group-upperBody')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('prompt-tag-editor-group-upperClothing')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('prompt-tag-editor-group-lowerClothing')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('prompt-tag-editor-group-clothing')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('prompt-tag-editor-group-lowerBody')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('prompt-tag-editor-layout-sourceOrder')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('prompt-tag-editor-group-upperBody')),
      findsNothing,
    );
  });

  testWidgets('shows tags and hides the inline input until plus is pressed',
      (tester) async {
    await tester.pumpWidget(
      _host(
        PromptTagEditor(
          value: 'blue eyes, long hair',
          onChanged: (_) {},
        ),
      ),
    );

    expect(find.text('blue eyes'), findsOneWidget);
    expect(find.text('long hair'), findsOneWidget);
    expect(find.byKey(const ValueKey('prompt-tag-editor-input')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('prompt-tag-editor-add')));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('prompt-tag-editor-input')), findsOneWidget);
  });

  testWidgets('can hide the add affordance for read-mostly tag fields',
      (tester) async {
    await tester.pumpWidget(
      _host(
        PromptTagEditor(
          value: 'blue eyes, long hair',
          allowAdd: false,
          onChanged: (_) {},
        ),
      ),
    );

    expect(find.text('blue eyes'), findsOneWidget);
    expect(find.text('long hair'), findsOneWidget);
    expect(find.byKey(const ValueKey('prompt-tag-editor-add')), findsNothing);
    expect(find.byKey(const ValueKey('prompt-tag-editor-input')), findsNothing);
  });

  testWidgets('splits comma separated input into multiple tags',
      (tester) async {
    String value = 'blue eyes';

    await tester.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (context, setState) {
            return PromptTagEditor(
              value: value,
              onChanged: (next) => setState(() => value = next),
            );
          },
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('prompt-tag-editor-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('prompt-tag-editor-input')),
      'long hair, smile',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(value, 'blue eyes, long hair, smile');
    expect(find.text('long hair'), findsOneWidget);
    expect(find.text('smile'), findsOneWidget);
    expect(find.byKey(const ValueKey('prompt-tag-editor-input')), findsNothing);
  });

  testWidgets('adds plain input as one tag when no comma is present',
      (tester) async {
    String value = 'blue eyes';

    await tester.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (context, setState) {
            return PromptTagEditor(
              value: value,
              onChanged: (next) => setState(() => value = next),
            );
          },
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('prompt-tag-editor-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('prompt-tag-editor-input')),
      'long hair',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(value, 'blue eyes, long hair');
    expect(find.text('long hair'), findsOneWidget);
  });

  testWidgets('keeps Chinese input as a raw prompt tag by default',
      (tester) async {
    String value = '';
    final requests = <OnlineTranslationRequest>[];
    GetIt.I.registerSingleton<TranslationCache>(
      TranslationCache(clock: () => 1710000000),
    );
    GetIt.I.registerSingleton<PromptTranslationService>(
      _FakePromptTranslationService((request) async {
        requests.add(request);
        if (request.text == '\u7ea2\u773c' &&
            request.sourceLanguage == 'zh' &&
            request.targetLanguage == 'en') {
          return const OnlineTranslationResult(
            text: 'red eyes',
            source: OnlineAiResultSource.online,
            providerName: 'fake',
          );
        }
        return const OnlineTranslationResult(
          text: '',
          source: OnlineAiResultSource.emptyFallback,
        );
      }),
    );

    await tester.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (context, setState) {
            return PromptTagEditor(
              value: value,
              onChanged: (next) => setState(() => value = next),
            );
          },
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('prompt-tag-editor-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('prompt-tag-editor-input')),
      '\u7ea2\u773c',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(value, '\u7ea2\u773c');
    expect(find.text('\u7ea2\u773c'), findsOneWidget);
    expect(find.text('red eyes'), findsNothing);
    expect(requests, isEmpty);
  });

  testWidgets('can opt in to translating Chinese input', (tester) async {
    String value = '';
    GetIt.I.registerSingleton<TranslationCache>(
      TranslationCache(clock: () => 1710000000),
    );
    GetIt.I.registerSingleton<PromptTranslationService>(
      _FakePromptTranslationService((request) async {
        if (request.text == '\u7ea2\u773c' &&
            request.sourceLanguage == 'zh' &&
            request.targetLanguage == 'en') {
          return const OnlineTranslationResult(
            text: 'red eyes',
            source: OnlineAiResultSource.online,
            providerName: 'fake',
          );
        }
        return const OnlineTranslationResult(
          text: '',
          source: OnlineAiResultSource.emptyFallback,
        );
      }),
    );

    await tester.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (context, setState) {
            return PromptTagEditor(
              value: value,
              translateChineseInput: true,
              onChanged: (next) => setState(() => value = next),
            );
          },
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('prompt-tag-editor-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('prompt-tag-editor-input')),
      '\u7ea2\u773c',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(value, 'red eyes');
    expect(find.text('red eyes'), findsOneWidget);
  });

  testWidgets(
      'saving a weight edit after pending Chinese translation preserves the new tag',
      (tester) async {
    String value = 'blue eyes';
    final completion = Completer<OnlineTranslationResult>();
    GetIt.I.registerSingleton<TranslationCache>(
      TranslationCache(clock: () => 1710000000),
    );
    GetIt.I.registerSingleton<PromptTranslationService>(
      _FakePromptTranslationService((request) async {
        if (request.text == '\u7ea2\u773c' &&
            request.sourceLanguage == 'zh' &&
            request.targetLanguage == 'en') {
          return completion.future;
        }
        return const OnlineTranslationResult(
          text: '',
          source: OnlineAiResultSource.emptyFallback,
        );
      }),
    );

    await tester.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (context, setState) {
            return PromptTagEditor(
              value: value,
              translateChineseInput: true,
              onChanged: (next) => setState(() => value = next),
            );
          },
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('prompt-tag-editor-add')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('prompt-tag-editor-input')),
      '\u7ea2\u773c',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    await tester.tap(_editorChip(0));
    await tester.pump(kDoubleTapMinTime);
    await tester.tap(_editorChip(0));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(
      find.byKey(const ValueKey('prompt-tag-editor-edit-weight-field')),
      '0.8',
    );

    completion.complete(
      const OnlineTranslationResult(
        text: 'red eyes',
        source: OnlineAiResultSource.online,
        providerName: 'fake',
      ),
    );
    await tester.pumpAndSettle();

    expect(value, 'blue eyes, red eyes');

    await tester.tap(
      find.byKey(const ValueKey('prompt-tag-editor-edit-tag-save')),
    );
    await tester.pumpAndSettle();

    expect(value, '0.8:: blue eyes ::, red eyes');
    expect(find.text('red eyes'), findsOneWidget);
    expect(find.text('x0.80'), findsOneWidget);
  });

  testWidgets(
      'pending Chinese translation rebases onto weight edits saved while it is in flight',
      (tester) async {
    String value = 'blue eyes';
    final completion = Completer<OnlineTranslationResult>();
    GetIt.I.registerSingleton<TranslationCache>(
      TranslationCache(clock: () => 1710000000),
    );
    GetIt.I.registerSingleton<PromptTranslationService>(
      _FakePromptTranslationService((request) async {
        if (request.text == '\u7ea2\u773c' &&
            request.sourceLanguage == 'zh' &&
            request.targetLanguage == 'en') {
          return completion.future;
        }
        return const OnlineTranslationResult(
          text: '',
          source: OnlineAiResultSource.emptyFallback,
        );
      }),
    );

    await tester.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (context, setState) {
            return PromptTagEditor(
              value: value,
              translateChineseInput: true,
              onChanged: (next) => setState(() => value = next),
            );
          },
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('prompt-tag-editor-add')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('prompt-tag-editor-input')),
      '\u7ea2\u773c',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    await tester.tap(_editorChip(0));
    await tester.pump(kDoubleTapMinTime);
    await tester.tap(_editorChip(0));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(
      find.byKey(const ValueKey('prompt-tag-editor-edit-weight-field')),
      '0.8',
    );
    await tester.tap(
      find.byKey(const ValueKey('prompt-tag-editor-edit-tag-save')),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(value, '0.8:: blue eyes ::');

    completion.complete(
      const OnlineTranslationResult(
        text: 'red eyes',
        source: OnlineAiResultSource.online,
        providerName: 'fake',
      ),
    );
    await tester.pumpAndSettle();

    expect(value, '0.8:: blue eyes ::, red eyes');
    expect(find.text('red eyes'), findsOneWidget);
    expect(find.text('x0.80'), findsOneWidget);
  });

  testWidgets('adds one English tag when Chinese translation returns synonyms',
      (tester) async {
    String value = '';
    GetIt.I.registerSingleton<TranslationCache>(
      TranslationCache(clock: () => 1710000000),
    );
    GetIt.I.registerSingleton<PromptTranslationService>(
      _FakePromptTranslationService((request) async {
        if (request.text == '\u672a\u7ecf\u5ba1\u67e5' &&
            request.sourceLanguage == 'zh' &&
            request.targetLanguage == 'en') {
          return const OnlineTranslationResult(
            text: 'unreviewed, unverified',
            source: OnlineAiResultSource.online,
            providerName: 'fake',
          );
        }
        return const OnlineTranslationResult(
          text: '',
          source: OnlineAiResultSource.emptyFallback,
        );
      }),
    );

    await tester.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (context, setState) {
            return PromptTagEditor(
              value: value,
              translateChineseInput: true,
              onChanged: (next) => setState(() => value = next),
            );
          },
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('prompt-tag-editor-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('prompt-tag-editor-input')),
      '\u672a\u7ecf\u5ba1\u67e5',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(value, 'unreviewed');
    expect(find.text('unreviewed'), findsOneWidget);
    expect(find.text('unverified'), findsNothing);
  });

  testWidgets('deletes a tag and rewrites the prompt string', (tester) async {
    String value = 'blue eyes, long hair';

    await tester.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (context, setState) {
            return PromptTagEditor(
              value: value,
              onChanged: (next) => setState(() => value = next),
            );
          },
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('prompt-tag-editor-delete-0')));
    await tester.pumpAndSettle();

    expect(value, 'long hair');
    expect(find.text('blue eyes'), findsNothing);
    expect(find.text('long hair'), findsOneWidget);
  });

  testWidgets('chip delete button keeps a forgiving hit target',
      (tester) async {
    await tester.pumpWidget(
      _host(
        PromptTagEditor(
          value: 'blue eyes, long hair',
          dense: true,
          onChanged: (_) {},
        ),
      ),
    );

    final deleteButtonSize = tester.getSize(
      find.byKey(const ValueKey('prompt-tag-editor-delete-0')),
    );

    expect(deleteButtonSize.width, greaterThanOrEqualTo(32));
    expect(deleteButtonSize.height, greaterThanOrEqualTo(32));
  });

  testWidgets('clear all button removes every tag in one click',
      (tester) async {
    String value = 'blue eyes, long hair';

    await tester.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (context, setState) {
            return PromptTagEditor(
              value: value,
              onChanged: (next) => setState(() => value = next),
            );
          },
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('prompt-tag-editor-clear-all')),
    );
    await tester.pumpAndSettle();

    expect(value, isEmpty);
    expect(find.text('blue eyes'), findsNothing);
    expect(find.text('long hair'), findsNothing);
    expect(
      find.byKey(const ValueKey('prompt-tag-editor-clear-all')),
      findsOneWidget,
    );
  });

  testWidgets('box selection and delete key remove selected tags',
      (tester) async {
    String value = 'blue eyes, long hair, white shirt';

    await tester.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (context, setState) {
            return PromptTagEditor(
              value: value,
              onChanged: (next) => setState(() => value = next),
            );
          },
        ),
      ),
    );

    await _dragSelectionAround(tester, _editorChip(0), _editorChip(1));

    expect(
      find.byKey(const ValueKey('prompt-tag-editor-chip-check-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('prompt-tag-editor-chip-check-1')),
      findsOneWidget,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pumpAndSettle();

    expect(value, 'white shirt');
    expect(find.text('blue eyes'), findsNothing);
    expect(find.text('long hair'), findsNothing);
    expect(find.text('white shirt'), findsOneWidget);
  });

  testWidgets('ordinary left click replaces editor chip selection',
      (tester) async {
    await tester.pumpWidget(
      _host(
        PromptTagEditor(
          value: 'blue eyes, long hair, white shirt',
          onChanged: (_) {},
        ),
      ),
    );

    await tester.tap(_editorChip(0));
    await tester.pump();
    await tester.tap(_editorChip(1));
    await tester.pump(kDoubleTapTimeout);

    expect(
      find.byKey(const ValueKey('prompt-tag-editor-chip-check-0')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('prompt-tag-editor-chip-check-1')),
      findsOneWidget,
    );
  });

  testWidgets('ctrl left click appends editor chip selection', (tester) async {
    await tester.pumpWidget(
      _host(
        PromptTagEditor(
          value: 'blue eyes, long hair, white shirt',
          onChanged: (_) {},
        ),
      ),
    );

    await tester.tap(_editorChip(0));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.tap(_editorChip(2));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump(kDoubleTapTimeout);

    expect(
      find.byKey(const ValueKey('prompt-tag-editor-chip-check-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('prompt-tag-editor-chip-check-2')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('prompt-tag-editor-chip-check-1')),
      findsNothing,
    );
  });

  testWidgets('blank click clears editor multi-selection', (tester) async {
    await tester.pumpWidget(
      _host(
        SizedBox(
          width: 420,
          child: PromptTagEditor(
            value: 'blue eyes, long hair, white shirt',
            onChanged: (_) {},
          ),
        ),
      ),
    );

    await _dragSelectionAround(tester, _editorChip(0), _editorChip(1));

    expect(
      find.byKey(const ValueKey('prompt-tag-editor-chip-check-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('prompt-tag-editor-chip-check-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('prompt-tag-editor-selection-toolbar')),
      findsOneWidget,
    );

    await _tapEditorBlankSpace(tester, _editorChip(2));

    expect(
      find.byKey(const ValueKey('prompt-tag-editor-chip-check-0')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('prompt-tag-editor-chip-check-1')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('prompt-tag-editor-selection-toolbar')),
      findsNothing,
    );
  });

  testWidgets('pointer cancel without active box drag keeps selection',
      (tester) async {
    await tester.pumpWidget(
      _host(
        PromptTagEditor(
          value: 'blue eyes, long hair, white shirt',
          onChanged: (_) {},
        ),
      ),
    );

    await _dragSelectionAround(tester, _editorChip(0), _editorChip(1));

    expect(
      find.byKey(const ValueKey('prompt-tag-editor-chip-check-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('prompt-tag-editor-chip-check-1')),
      findsOneWidget,
    );

    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(
      pointer.down(
        tester.getCenter(_editorChip(0)),
        buttons: kSecondaryMouseButton,
      ),
    );
    await tester.sendEventToBinding(pointer.cancel());
    await tester.pump();

    expect(
      find.byKey(const ValueKey('prompt-tag-editor-chip-check-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('prompt-tag-editor-chip-check-1')),
      findsOneWidget,
    );
  });

  testWidgets('selection toolbar floats without shifting editor tags',
      (tester) async {
    await tester.pumpWidget(
      _host(
        PromptTagEditor(
          value: 'blue eyes, long hair',
          onChanged: (_) {},
        ),
      ),
    );

    final firstChipTopBefore = tester.getTopLeft(_editorChip(0));

    await _dragSelectionAround(tester, _editorChip(0), _editorChip(0));

    expect(
      find.byKey(const ValueKey('prompt-tag-editor-clear-selection')),
      findsOneWidget,
    );
    final toolbarTop = tester.getTopLeft(
      find.byKey(const ValueKey('prompt-tag-editor-selection-toolbar')),
    );
    final firstChipTop = tester.getTopLeft(_editorChip(0));

    expect(firstChipTop.dy, closeTo(firstChipTopBefore.dy, 0.1));
    expect(toolbarTop.dy, lessThan(firstChipTop.dy));
  });

  testWidgets('selected editor tags can be dragged into another editor',
      (tester) async {
    var upper = 'cat ears, hair ornament';
    var lower = 'cat tail';

    await tester.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (context, setState) {
            return Column(
              children: [
                PromptTagEditor(
                  key: const ValueKey('upper-editor'),
                  value: upper,
                  onChanged: (next) => setState(() => upper = next),
                ),
                const SizedBox(height: 24),
                PromptTagEditor(
                  key: const ValueKey('lower-editor'),
                  value: lower,
                  onChanged: (next) => setState(() => lower = next),
                ),
              ],
            );
          },
        ),
      ),
    );

    final upperEditor = find.byKey(const ValueKey('upper-editor'));
    final lowerEditor = find.byKey(const ValueKey('lower-editor'));
    final upperFirstChip = find.descendant(
      of: upperEditor,
      matching: find.byKey(const ValueKey('prompt-tag-editor-chip-0')),
    );
    final lowerDropArea = find.descendant(
      of: lowerEditor,
      matching: find.byKey(const ValueKey('prompt-tag-editor-selection-area')),
    );

    await _dragSelectionAround(tester, upperFirstChip, upperFirstChip);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    final start = tester.getCenter(upperFirstChip);
    final end = tester.getCenter(lowerDropArea);
    await mouse.addPointer(location: start);
    await tester.pump();
    await mouse.down(start);
    await mouse.moveTo(end);
    await tester.pump();
    await mouse.up();
    await tester.pumpAndSettle();
    await mouse.removePointer();

    expect(upper, 'hair ornament');
    expect(lower, 'cat tail, cat ears');
  });

  testWidgets('selected editor tags can be dragged into an empty editor',
      (tester) async {
    var upper = 'cat ears, hair ornament';
    var lower = '';

    await tester.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (context, setState) {
            return Column(
              children: [
                PromptTagEditor(
                  key: const ValueKey('upper-editor'),
                  value: upper,
                  onChanged: (next) => setState(() => upper = next),
                ),
                const SizedBox(height: 24),
                PromptTagEditor(
                  key: const ValueKey('lower-editor'),
                  value: lower,
                  onChanged: (next) => setState(() => lower = next),
                ),
              ],
            );
          },
        ),
      ),
    );

    final upperEditor = find.byKey(const ValueKey('upper-editor'));
    final lowerEditor = find.byKey(const ValueKey('lower-editor'));
    final upperFirstChip = find.descendant(
      of: upperEditor,
      matching: find.byKey(const ValueKey('prompt-tag-editor-chip-0')),
    );
    final lowerDropArea = find.descendant(
      of: lowerEditor,
      matching: find.byKey(const ValueKey('prompt-tag-editor-selection-area')),
    );

    await _dragSelectionAround(tester, upperFirstChip, upperFirstChip);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    final start = tester.getCenter(upperFirstChip);
    final end = tester.getCenter(lowerDropArea);
    await mouse.addPointer(location: start);
    await tester.pump();
    await mouse.down(start);
    await mouse.moveTo(end);
    await tester.pump();
    await mouse.up();
    await tester.pumpAndSettle();
    await mouse.removePointer();

    expect(upper, 'hair ornament');
    expect(lower, 'cat ears');
  });

  testWidgets('selected editor tags can be dragged to reorder in place',
      (tester) async {
    var value = 'cat ears, hair ornament, cat tail';

    await tester.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (context, setState) {
            return PromptTagEditor(
              value: value,
              onChanged: (next) => setState(() => value = next),
            );
          },
        ),
      ),
    );

    await _dragSelectionAround(tester, _editorChip(0), _editorChip(0));

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    final start = tester.getCenter(_editorChip(0));
    final end = tester.getCenter(_editorChip(2));
    await mouse.addPointer(location: start);
    await tester.pump();
    await mouse.down(start);
    await mouse.moveTo(end);
    await tester.pump();
    await mouse.up();
    await tester.pumpAndSettle();
    await mouse.removePointer();

    expect(value, 'hair ornament, cat ears, cat tail');
  });

  testWidgets('alt dragging editor tags copies when enabled', (tester) async {
    var value = 'cat ears, hair ornament, cat tail';

    await tester.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (context, setState) {
            return PromptTagEditor(
              value: value,
              copyDraggedTagsWithAlt: true,
              onChanged: (next) => setState(() => value = next),
            );
          },
        ),
      ),
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    final start = tester.getCenter(_editorChip(0));
    final end = tester.getCenter(_editorChip(2));
    await mouse.addPointer(location: start);
    await tester.pump();
    await mouse.down(start);
    await mouse.moveTo(end);
    await tester.pump();
    await mouse.up();
    await tester.pumpAndSettle();
    await mouse.removePointer();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);

    expect(value, 'cat ears, hair ornament, cat ears, cat tail');
  });

  testWidgets(
      'unselected editor tag can be dragged directly without becoming selected',
      (tester) async {
    var value = 'cat ears, hair ornament, cat tail';

    await tester.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (context, setState) {
            return PromptTagEditor(
              value: value,
              onChanged: (next) => setState(() => value = next),
            );
          },
        ),
      ),
    );

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    final start = tester.getCenter(_editorChip(0));
    final end = tester.getCenter(_editorChip(2));
    await mouse.addPointer(location: start);
    await tester.pump();
    await mouse.down(start);
    await mouse.moveTo(end);
    await tester.pump();
    await mouse.up();
    await tester.pumpAndSettle();
    await mouse.removePointer();

    expect(value, 'hair ornament, cat ears, cat tail');
    expect(
      find.byKey(const ValueKey('prompt-tag-editor-chip-check-1')),
      findsNothing,
    );
  });

  testWidgets('ctrl v pastes clipboard tags into enabled editor selection',
      (tester) async {
    var value = 'blue eyes, long hair';

    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.getData') {
          return {'text': 'silver hair, 1.2:: red eyes ::'};
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (context, setState) {
            return PromptTagEditor(
              value: value,
              enableKeyboardPaste: true,
              onChanged: (next) => setState(() => value = next),
            );
          },
        ),
      ),
    );

    await tester.tap(_editorChip(0));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(value, 'silver hair, 1.2:: red eyes ::, long hair');
    expect(find.text('silver hair'), findsOneWidget);
    expect(find.text('red eyes'), findsOneWidget);
    expect(find.text('x1.20'), findsOneWidget);
  });

  testWidgets('cross-editor drop changes can be wrapped in one batch',
      (tester) async {
    var upper = 'blue eyes, long hair';
    var lower = 'white shirt';
    var batchActive = false;
    var batchCalls = 0;
    final changes = <String>[];

    await tester.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (context, setState) {
            return Column(
              children: [
                PromptTagEditor(
                  key: const ValueKey('batch-upper-editor'),
                  value: upper,
                  selectionFieldId: 'batch-upper',
                  onChanged: (next) {
                    changes.add('upper:${batchActive ? 'batched' : 'plain'}');
                    setState(() => upper = next);
                  },
                ),
                const SizedBox(height: 24),
                PromptTagEditor(
                  key: const ValueKey('batch-lower-editor'),
                  value: lower,
                  selectionFieldId: 'batch-lower',
                  onDroppedTagsBatch: (applyDrop) {
                    batchCalls += 1;
                    batchActive = true;
                    applyDrop();
                    batchActive = false;
                  },
                  onChanged: (next) {
                    changes.add('lower:${batchActive ? 'batched' : 'plain'}');
                    setState(() => lower = next);
                  },
                ),
              ],
            );
          },
        ),
      ),
    );

    final upperChip = find.descendant(
      of: find.byKey(const ValueKey('batch-upper-editor')),
      matching: _editorChip(0),
    );
    final lowerDropArea = find.descendant(
      of: find.byKey(const ValueKey('batch-lower-editor')),
      matching: find.byKey(const ValueKey('prompt-tag-editor-selection-area')),
    );

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    final start = tester.getCenter(upperChip);
    final end = tester.getCenter(lowerDropArea);
    await mouse.addPointer(location: start);
    await tester.pump();
    await mouse.down(start);
    await mouse.moveTo(end);
    await tester.pump();
    await mouse.up();
    await tester.pumpAndSettle();
    await mouse.removePointer();

    expect(batchCalls, 1);
    expect(changes, ['lower:batched', 'upper:batched']);
    expect(lower, 'white shirt, blue eyes');
    expect(upper, 'long hair');
  });

  testWidgets('right click menu can copy and delete editor tags',
      (tester) async {
    String value = 'blue eyes, long hair, white shirt';
    String? copiedText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedText = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await tester.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (context, setState) {
            return PromptTagEditor(
              value: value,
              onChanged: (next) => setState(() => value = next),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('blue eyes'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();

    final deleteCurrent = find.byKey(
      const ValueKey('prompt-tag-editor-delete-current'),
    );
    final copyCurrent = find.byKey(
      const ValueKey('prompt-tag-editor-copy-current'),
    );
    expect(deleteCurrent, findsOneWidget);
    expect(copyCurrent, findsOneWidget);
    expect(
      tester.getTopLeft(copyCurrent).dy,
      lessThan(tester.getTopLeft(deleteCurrent).dy),
    );
    expect(find.text('复制标签'), findsOneWidget);
    expect(find.text('删除标签'), findsOneWidget);

    await tester.tap(find.text('复制标签'));
    await tester.pumpAndSettle();
    expect(copiedText, 'blue eyes');

    await _dragSelectionAround(tester, _editorChip(0), _editorChip(1));
    await tester.tap(find.text('blue eyes'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('prompt-tag-editor-delete-selected')),
      findsOneWidget,
    );

    await tester.tap(find.text('删除选中'));
    await tester.pumpAndSettle();

    expect(value, 'white shirt');
    expect(find.text('blue eyes'), findsNothing);
    expect(find.text('long hair'), findsNothing);
  });

  testWidgets('right click menu can edit editor tags', (tester) async {
    String value = 'blue eyes, long hair';

    await tester.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (context, setState) {
            return PromptTagEditor(
              value: value,
              onChanged: (next) => setState(() => value = next),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('blue eyes'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑标签'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('prompt-tag-editor-edit-tag-field')),
      'red eyes',
    );
    await tester.tap(
      find.byKey(const ValueKey('prompt-tag-editor-edit-tag-save')),
    );
    await tester.pumpAndSettle();

    expect(value, 'red eyes, long hair');
    expect(find.text('red eyes'), findsOneWidget);
    expect(find.text('blue eyes'), findsNothing);
  });

  testWidgets('double click opens the editor tag edit dialog', (tester) async {
    await tester.pumpWidget(
      _host(
        PromptTagEditor(
          value: 'blue eyes, long hair',
          onChanged: (_) {},
        ),
      ),
    );

    await tester.tap(_editorChip(0));
    await tester.pump(kDoubleTapMinTime);
    await tester.tap(_editorChip(0));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('prompt-tag-editor-edit-tag-dialog')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('prompt-tag-editor-edit-tag-field')),
      findsOneWidget,
    );
  });

  testWidgets('double click opens edit dialog while translations are visible',
      (tester) async {
    GetIt.I.registerSingleton<TranslationCache>(
      TranslationCache(clock: () => 1710000000)..setManual('blue eyes', '蓝眼睛'),
    );

    await tester.pumpWidget(
      _host(
        PromptTagEditor(
          value: '1.2::blue eyes::',
          onChanged: (_) {},
        ),
      ),
    );

    final chipRect = tester.getRect(_editorChip(0));
    final chipPaddingPoint = Offset(chipRect.left + 6, chipRect.center.dy);
    await tester.tapAt(chipPaddingPoint);
    await tester.pump(kDoubleTapMinTime);
    await tester.tapAt(chipPaddingPoint);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('prompt-tag-editor-edit-tag-dialog')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('prompt-tag-editor-edit-weight-field')),
      findsOneWidget,
    );
  });

  testWidgets('double clicking a translation toggle does not edit the tag',
      (tester) async {
    GetIt.I.registerSingleton<TranslationCache>(
      TranslationCache(clock: () => 1710000000)..setManual('blue eyes', '蓝眼睛'),
    );
    await tester.pumpWidget(
      _host(
        PromptTagEditor(
          value: 'blue eyes',
          onChanged: (_) {},
        ),
      ),
    );

    final toggle = find.byKey(
      const ValueKey('prompt-tag-editor-translation-toggle-0'),
    );
    await tester.tap(toggle);
    await tester.pump(kDoubleTapMinTime);
    await tester.tap(toggle);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('prompt-tag-editor-edit-tag-dialog')),
      findsNothing,
    );
  });

  testWidgets('double click opens tag editor without repeated shared selection',
      (tester) async {
    final selectionController = PromptTagSelectionController();
    addTearDown(selectionController.dispose);
    var selectionChanges = 0;
    selectionController.addListener(() {
      selectionChanges += 1;
    });

    await tester.pumpWidget(
      _host(
        PromptTagEditor(
          value: 'blue eyes, long hair',
          selectionController: selectionController,
          selectionFieldId: 'prompt-tag-editor-test',
          onChanged: (_) {},
        ),
      ),
    );

    await tester.tap(_editorChip(0));
    await tester.pump(kDoubleTapMinTime);
    await tester.tap(_editorChip(0));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('prompt-tag-editor-edit-tag-dialog')),
      findsOneWidget,
    );
    expect(selectionController.selectedCount, 1);
    expect(selectionChanges, 1);
  });

  testWidgets('second double click press and slight drift do not rebuild tags',
      (tester) async {
    var highlightCalls = 0;
    final tags = List.generate(24, (index) => 'tag $index').join(', ');

    await tester.pumpWidget(
      _host(
        PromptTagEditor(
          value: tags,
          onChanged: (_) {},
          highlightForTag: (_) {
            highlightCalls += 1;
            return null;
          },
        ),
      ),
    );

    final start = tester.getCenter(_editorChip(0));

    await tester.tap(_editorChip(0));
    await tester.pump(kDoubleTapMinTime);

    final callsAfterFirstTap = highlightCalls;
    final pointer = TestPointer(1, PointerDeviceKind.mouse);

    await tester.sendEventToBinding(pointer.down(start));
    await tester.pump();
    expect(highlightCalls, callsAfterFirstTap);

    await tester.sendEventToBinding(pointer.move(start + const Offset(3, 0)));
    await tester.pump();

    expect(highlightCalls, callsAfterFirstTap);

    await tester.sendEventToBinding(pointer.up());
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('prompt-tag-editor-edit-tag-dialog')),
      findsOneWidget,
    );
  });

  testWidgets(
      'double click with slight mouse drift opens the editor tag edit dialog',
      (tester) async {
    await tester.pumpWidget(
      _host(
        PromptTagEditor(
          value: 'blue eyes, long hair',
          onChanged: (_) {},
        ),
      ),
    );

    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    final start = tester.getCenter(_editorChip(0));

    await tester.sendEventToBinding(pointer.down(start));
    await tester.sendEventToBinding(pointer.up());
    await tester.pump(kDoubleTapMinTime);
    await tester.sendEventToBinding(pointer.down(start));
    await tester.sendEventToBinding(pointer.move(start + const Offset(3, 0)));
    await tester.sendEventToBinding(pointer.up());
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('prompt-tag-editor-edit-tag-dialog')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('prompt-tag-editor-edit-tag-field')),
      findsOneWidget,
    );
  });

  testWidgets('editing an existing tag translates Chinese input to English',
      (tester) async {
    String value = 'blue eyes, long hair';
    GetIt.I.registerSingleton<TranslationCache>(
      TranslationCache(clock: () => 1710000000),
    );
    GetIt.I.registerSingleton<PromptTranslationService>(
      _FakePromptTranslationService((request) async {
        if (request.text == '\u7ea2\u773c' &&
            request.sourceLanguage == 'zh' &&
            request.targetLanguage == 'en') {
          return const OnlineTranslationResult(
            text: 'red eyes',
            source: OnlineAiResultSource.online,
            providerName: 'fake',
          );
        }
        return const OnlineTranslationResult(
          text: '',
          source: OnlineAiResultSource.emptyFallback,
        );
      }),
    );

    await tester.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (context, setState) {
            return PromptTagEditor(
              value: value,
              translateChineseInput: true,
              onChanged: (next) => setState(() => value = next),
            );
          },
        ),
      ),
    );

    await tester.tap(_editorChip(0));
    await tester.pump(kDoubleTapMinTime);
    await tester.tap(_editorChip(0));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('prompt-tag-editor-edit-tag-field')),
      '\u7ea2\u773c',
    );
    await tester.tap(
      find.byKey(const ValueKey('prompt-tag-editor-edit-tag-save')),
    );
    await tester.pumpAndSettle();

    expect(value, 'red eyes, long hair');
    expect(find.text('red eyes'), findsOneWidget);
    expect(find.text('blue eyes'), findsNothing);
  });

  testWidgets('tag edit dialog can edit weight', (tester) async {
    String value = '1.2::blue eyes::, long hair';

    await tester.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (context, setState) {
            return PromptTagEditor(
              value: value,
              onChanged: (next) => setState(() => value = next),
            );
          },
        ),
      ),
    );

    expect(find.text('blue eyes'), findsOneWidget);
    expect(find.text('x1.20'), findsOneWidget);
    expect(find.text('1.2::blue eyes::'), findsNothing);

    await tester.tap(find.text('blue eyes'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('prompt-tag-editor-edit-weight')),
      findsOneWidget,
    );
    expect(find.text('编辑权重'), findsNothing);
    await tester
        .tap(find.byKey(const ValueKey('prompt-tag-editor-edit-weight')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('prompt-tag-editor-edit-tag-field')),
          )
          .controller
          ?.text,
      'blue eyes',
    );
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('prompt-tag-editor-edit-weight-field')),
          )
          .controller
          ?.text,
      '1.2',
    );
    await tester.enterText(
      find.byKey(const ValueKey('prompt-tag-editor-edit-weight-field')),
      '0.8',
    );
    await tester.tap(
      find.byKey(const ValueKey('prompt-tag-editor-edit-tag-save')),
    );
    await tester.pumpAndSettle();

    expect(value, '0.8:: blue eyes ::, long hair');
    expect(find.text('x0.80'), findsOneWidget);
    expect(find.text('x1.20'), findsNothing);
  });

  testWidgets('double click weight edit applies to selected editor chips',
      (tester) async {
    String value = 'blue eyes, long hair, white shirt';

    await tester.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (context, setState) {
            return PromptTagEditor(
              value: value,
              onChanged: (next) => setState(() => value = next),
            );
          },
        ),
      ),
    );

    await _dragSelectionAround(
      tester,
      _editorChip(0),
      _editorChip(1),
    );
    await tester.pumpAndSettle();

    await tester.tap(_editorChip(1));
    await tester.pump(kDoubleTapMinTime);
    await tester.tap(_editorChip(1));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('prompt-tag-editor-edit-weight-field')),
      '0.75',
    );
    await tester.tap(
      find.byKey(const ValueKey('prompt-tag-editor-edit-tag-save')),
    );
    await tester.pumpAndSettle();

    expect(
      value,
      '0.75:: blue eyes ::, 0.75:: long hair ::, white shirt',
    );
    expect(find.text('x0.75'), findsNWidgets(2));
    expect(find.text('white shirt'), findsOneWidget);
  });

  testWidgets('clearing weight in tag edit dialog removes the weight',
      (tester) async {
    String value = '1.2::blue eyes::, long hair';

    await tester.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (context, setState) {
            return PromptTagEditor(
              value: value,
              onChanged: (next) => setState(() => value = next),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('blue eyes'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑标签'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('prompt-tag-editor-edit-weight-field')),
      '',
    );
    await tester.tap(
      find.byKey(const ValueKey('prompt-tag-editor-edit-tag-save')),
    );
    await tester.pumpAndSettle();

    expect(value, 'blue eyes, long hair');
    expect(find.text('x1.20'), findsNothing);
    expect(find.text('blue eyes'), findsOneWidget);
  });

  testWidgets('negative weighted tag badges use danger colors', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        PromptTagEditor(
          value: '-3::hood::, hood up',
          onChanged: (_) {},
        ),
      ),
    );

    final badge = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('prompt-tag-editor-chip-weight-0')),
    );
    final decoration = badge.decoration as BoxDecoration;
    final border = decoration.border! as Border;

    expect(find.text('x-3.00'), findsOneWidget);
    expect(decoration.color, StudioTokens.danger.withAlpha(30));
    expect(border.top.color, StudioTokens.danger.withAlpha(150));
    expect(
      tester.widget<Text>(find.text('x-3.00')).style?.color,
      StudioTokens.danger,
    );
  });

  testWidgets('right click menu can retranslate and add to filter rules',
      (tester) async {
    List<String>? addedTags;
    PromptTagFilterRuleTarget? addedTarget;
    GetIt.I.registerSingleton<TranslationCache>(
      TranslationCache(clock: () => 1710000000),
    );
    GetIt.I.registerSingleton<PromptTranslationService>(
      _FakePromptTranslationService((request) async {
        return const OnlineTranslationResult(
          text: '蓝眼睛',
          source: OnlineAiResultSource.online,
          providerName: 'fake',
        );
      }),
    );

    await tester.pumpWidget(
      _host(
        PromptTagEditor(
          value: 'blue eyes',
          onChanged: (_) {},
          onAddToFilterRules: (tags, target) async {
            addedTags = tags;
            addedTarget = target;
          },
        ),
      ),
    );

    await tester.tap(find.text('blue eyes'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('AI重译'));
    await tester.pumpAndSettle();

    expect(find.text('蓝眼睛'), findsOneWidget);

    await tester.tap(find.text('blue eyes'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('加入屏蔽库'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('prompt-tag-editor-filter-target-strong')),
    );
    await tester.pumpAndSettle();

    expect(addedTags, ['blue eyes']);
    expect(addedTarget, PromptTagFilterRuleTarget.strongFilterKeywords);
  });

  testWidgets('right click on selected chips keeps multi-selection menu',
      (tester) async {
    await tester.pumpWidget(
      _host(
        PromptTagEditor(
          value: 'blue eyes, long hair',
          onChanged: (_) {},
        ),
      ),
    );

    await _dragSelectionAround(
      tester,
      _editorChip(0),
      _editorChip(1),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('blue eyes'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('prompt-tag-editor-delete-selected')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('prompt-tag-editor-copy-selected')),
      findsOneWidget,
    );
  });

  testWidgets('AI retranslate on a selected chip targets the clicked tag',
      (tester) async {
    final translatedTags = <String>[];
    GetIt.I.registerSingleton<TranslationCache>(
      TranslationCache(clock: () => 1710000000),
    );
    GetIt.I.registerSingleton<PromptTranslationService>(
      _FakePromptTranslationService((request) async {
        translatedTags.add(request.text);
        return OnlineTranslationResult(
          text: 'AI ${request.text}',
          source: OnlineAiResultSource.online,
          providerName: 'fake',
        );
      }),
    );

    await tester.pumpWidget(
      _host(
        PromptTagEditor(
          value: 'blue eyes, long hair',
          onChanged: (_) {},
        ),
      ),
    );

    await _dragSelectionAround(
      tester,
      _editorChip(0),
      _editorChip(1),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('long hair'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('prompt-tag-editor-ai-retranslate')),
    );
    await tester.pumpAndSettle();

    expect(translatedTags, ['long hair']);
    expect(find.text('AI long hair'), findsOneWidget);
    expect(find.text('AI blue eyes'), findsNothing);
  });

  testWidgets('filter target dialog options show hover feedback',
      (tester) async {
    await tester.pumpWidget(
      _host(
        PromptTagEditor(
          value: 'blue eyes',
          onChanged: (_) {},
          onAddToFilterRules: (_, __) async {},
        ),
      ),
    );

    await tester.tap(find.text('blue eyes'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('prompt-tag-editor-add-to-filter-rules')),
    );
    await tester.pumpAndSettle();

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(
      tester.getCenter(
        find.byKey(const ValueKey('prompt-tag-editor-filter-target-delete')),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 180));

    final hoveredSurface = tester.widget<AnimatedContainer>(
      find.byKey(
        const ValueKey('prompt-tag-editor-filter-target-delete-surface'),
      ),
    );
    final decoration = hoveredSurface.decoration! as BoxDecoration;
    final border = decoration.border! as Border;
    expect(decoration.color, StudioTokens.surface3);
    expect(border.top.color, StudioTokens.borderStrong);
  });

  testWidgets('adding selected tags to filter rules removes them from editor',
      (tester) async {
    String value = 'blue eyes, long hair, white shirt';
    List<String>? addedTags;
    PromptTagFilterRuleTarget? addedTarget;
    await tester.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (context, setState) {
            return PromptTagEditor(
              value: value,
              onChanged: (next) => setState(() => value = next),
              onAddToFilterRules: (tags, target) async {
                addedTags = tags;
                addedTarget = target;
              },
            );
          },
        ),
      ),
    );

    await _dragSelectionAround(
      tester,
      _editorChip(0),
      _editorChip(1),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('blue eyes'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('prompt-tag-editor-add-to-filter-rules')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('prompt-tag-editor-filter-target-delete')),
    );
    await tester.pumpAndSettle();

    expect(addedTags, ['blue eyes', 'long hair']);
    expect(addedTarget, PromptTagFilterRuleTarget.deleteKeywords);
    expect(value, 'white shirt');
    expect(find.text('blue eyes'), findsNothing);
    expect(find.text('long hair'), findsNothing);
    expect(find.text('white shirt'), findsOneWidget);
  });
}

class _FakePromptTranslationService implements PromptTranslationService {
  final Future<OnlineTranslationResult> Function(OnlineTranslationRequest)
      handler;

  const _FakePromptTranslationService(this.handler);

  @override
  OnlineAiMode get currentMode => OnlineAiMode.ai;

  @override
  Future<OnlineTranslationResult> translate(
    OnlineTranslationRequest request, {
    bool preferCache = true,
  }) {
    return handler(request);
  }
}
