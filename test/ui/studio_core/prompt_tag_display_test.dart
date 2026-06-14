import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:nai_casrand/data/studio/services/prompt_translation_service.dart';
import 'package:nai_casrand/data/studio/tools/online_ai_tools.dart';
import 'package:nai_casrand/data/studio/tools/prompt_tag_classifier.dart';
import 'package:nai_casrand/data/studio/tools/translation_cache.dart';
import 'package:nai_casrand/ui/core/app_display_settings.dart';
import 'package:nai_casrand/ui/studio_core/theme/studio_theme.dart';
import 'package:nai_casrand/ui/studio_core/theme/studio_tokens.dart';
import 'package:nai_casrand/ui/studio_core/widgets/prompt_tag_display.dart';

void main() {
  setUp(() async {
    await GetIt.I.reset();
  });

  tearDown(() async {
    await GetIt.I.reset();
  });

  TranslationCache cache() {
    return TranslationCache(clock: () => 1710000000)
      ..setManual('blue eyes', '蓝眼睛')
      ..setManual('long hair', '长发');
  }

  Widget host(Widget child) {
    return MaterialApp(
      theme: StudioTheme.build(),
      home: Scaffold(body: Center(child: child)),
    );
  }

  Finder chipKey(String text, int index, {required bool selected}) {
    return find.byKey(
      ValueKey(
        'prompt-tag-chip-$text-$index-${selected ? 'selected' : 'idle'}',
      ),
    );
  }

  Rect dropAreaRectContaining(WidgetTester tester, Finder chip) {
    final chipCenter = tester.getCenter(chip);
    for (final element
        in find.byKey(const ValueKey('prompt-tag-drop-area')).evaluate()) {
      final box = element.renderObject as RenderBox;
      final topLeft = box.localToGlobal(Offset.zero);
      final rect = topLeft & box.size;
      if (rect.contains(chipCenter)) {
        return rect;
      }
    }
    throw StateError('No prompt tag drop area contains the chip.');
  }

  Offset selectionStartNear(WidgetTester tester, Finder chip) {
    final chipTopLeft = tester.getTopLeft(chip);
    final dropRect = dropAreaRectContaining(tester, chip);
    final aboveChip = Offset(chipTopLeft.dx + 1, chipTopLeft.dy - 2);
    if (dropRect.contains(aboveChip)) {
      return aboveChip;
    }
    return dropRect.topLeft + const Offset(1, 1);
  }

  Future<void> dragSelectionAround(
    WidgetTester tester,
    Finder first,
    Finder last, {
    bool additive = false,
  }) async {
    if (additive) {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    }
    final start = selectionStartNear(tester, first);
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

  testWidgets('renders prompt text as raw tags by default', (tester) async {
    await tester.pumpWidget(
      host(
        PromptTagDisplay(
          text: 'blue eyes, long hair',
          translationCache: cache(),
        ),
      ),
    );

    expect(find.text('blue eyes'), findsOneWidget);
    expect(find.text('long hair'), findsOneWidget);
    expect(find.text('蓝眼睛'), findsNothing);
  });

  testWidgets('renders prompt weight badges beside clean tag text', (
    tester,
  ) async {
    final translationCache = TranslationCache(clock: () => 1710000000)
      ..setManual('blue eyes', 'blue translated');

    await tester.pumpWidget(
      host(
        PromptTagDisplay(
          text: '1.2::blue eyes::, [long hair]',
          defaultTranslated: true,
          translationCache: translationCache,
        ),
      ),
    );

    expect(chipKey('blue eyes', 0, selected: false), findsOneWidget);
    expect(chipKey('long hair', 1, selected: false), findsOneWidget);
    expect(find.text('x1.20'), findsOneWidget);
    expect(find.text('x0.95'), findsOneWidget);
    expect(find.text('1.2::blue eyes::'), findsNothing);
    expect(find.text('blue translated'), findsOneWidget);
  });

  testWidgets('negative prompt weight badges use danger colors', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        PromptTagDisplay(
          text: '-2::animal ear hood::',
          translationCache: cache(),
        ),
      ),
    );

    final badge = tester.widget<DecoratedBox>(
      find.byKey(
        const ValueKey('prompt-tag-chip-weight-animal ear hood-0'),
      ),
    );
    final decoration = badge.decoration as BoxDecoration;
    final border = decoration.border! as Border;

    expect(decoration.color, StudioTokens.danger.withAlpha(30));
    expect(border.top.color, StudioTokens.danger.withAlpha(150));
    expect(tester.widget<Text>(find.text('x-2.00')).style?.color,
        StudioTokens.danger);
  });

  testWidgets('non interactive tag chips keep the basic cursor', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        PromptTagDisplay(
          text: 'blue eyes, long hair',
          translationCache: cache(),
        ),
      ),
    );

    final cursorRegions = tester.widgetList<MouseRegion>(
      find.byType(MouseRegion),
    );

    expect(
      cursorRegions.where(
        (region) => region.cursor == SystemMouseCursors.basic,
      ),
      isNotEmpty,
    );
  });

  testWidgets('renders translated tags when default translation is enabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        PromptTagDisplay(
          text: 'blue eyes, long hair',
          defaultTranslated: true,
          translationCache: cache(),
        ),
      ),
    );

    expect(find.text('blue eyes'), findsOneWidget);
    expect(find.text('蓝眼睛'), findsOneWidget);
    expect(find.text('长发'), findsOneWidget);
  });

  testWidgets('calls onTagTap when a non interactive chip is tapped', (
    tester,
  ) async {
    String? tappedTag;

    await tester.pumpWidget(
      host(
        PromptTagDisplay(
          text: 'blue eyes, long hair',
          translationCache: cache(),
          onTagTap: (tag) {
            tappedTag = tag;
          },
        ),
      ),
    );

    await tester.tap(chipKey('blue eyes', 0, selected: false));
    await tester.pump();

    expect(tappedTag, 'blue eyes');
  });

  testWidgets('editable chips expose a visible delete button', (
    tester,
  ) async {
    String? changedText;

    await tester.pumpWidget(
      host(
        PromptTagDisplay(
          text: 'blue eyes, long hair',
          translationCache: cache(),
          enableTagActions: true,
          onChanged: (value) {
            changedText = value;
          },
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('prompt-tag-chip-delete-blue eyes-0')),
    );
    await tester.pump();

    expect(changedText, 'long hair');
  });

  testWidgets(
    'auto translates missing tags with prompt translation service when default translation is enabled',
    (tester) async {
      final translationCache = TranslationCache(clock: () => 1710000000);
      GetIt.I.registerSingleton<PromptTranslationService>(
        _FakePromptTranslationService(
          const OnlineTranslationResult(
            text: '缂冩垹绮堕拑婵堟簜',
            source: OnlineAiResultSource.online,
            providerName: 'fake-ai',
          ),
        ),
      );

      await tester.pumpWidget(
        host(
          PromptTagDisplay(
            text: 'silver hair',
            defaultTranslated: true,
            translationCache: translationCache,
          ),
        ),
      );

      expect(find.text('silver hair'), findsOneWidget);
      expect(find.text('缂冩垹绮堕拑婵堟簜'), findsNothing);

      await tester.pumpAndSettle();
      await tester.pump();

      expect(find.text('缂冩垹绮堕拑婵堟簜'), findsOneWidget);
      expect(translationCache.getCached('silver hair'), '缂冩垹绮堕拑婵堟簜');
    },
  );

  testWidgets('translates only after the hovered shortcut trigger', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        PromptTagDisplay(
          text: 'blue eyes, long hair',
          enableHoverShortcut: true,
          translationCache: cache(),
        ),
      ),
    );

    expect(find.text('蓝眼睛'), findsNothing);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(
      location: tester.getCenter(find.byType(PromptTagDisplay)),
    );
    addTearDown(gesture.removePointer);
    await tester.pump();

    AppDisplaySettings.translateHoveredPromptCard();
    await tester.pump();

    expect(find.text('蓝眼睛'), findsOneWidget);
    expect(find.text('长发'), findsOneWidget);
  });

  testWidgets('interactive tags expose right click translate edit and copy', (
    tester,
  ) async {
    final translationCache = cache();
    String? copiedText;
    var aiCalled = false;
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
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(
      host(
        PromptTagDisplay(
          text: 'blue eyes, long hair',
          defaultTranslated: true,
          enableTagActions: true,
          translationCache: translationCache,
          onAiRetranslate: (tag) async {
            aiCalled = true;
            return 'AI: $tag';
          },
        ),
      ),
    );

    final cursorRegions = tester.widgetList<MouseRegion>(
      find.byType(MouseRegion),
    );
    expect(
      cursorRegions.where((region) => region.cursor == SystemMouseCursors.text),
      isEmpty,
    );
    expect(find.byType(SelectionArea), findsNothing);

    await tester.tap(find.text('blue eyes'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();

    expect(find.text('AI重译'), findsOneWidget);
    expect(find.text('手动编辑'), findsOneWidget);
    expect(find.text('复制标签'), findsOneWidget);

    await tester.tap(find.text('复制标签'));
    await tester.pump();

    expect(copiedText, 'blue eyes');

    await tester.tap(find.text('blue eyes'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('AI重译'));
    await tester.pumpAndSettle();

    expect(aiCalled, isTrue);
    expect(find.text('AI: blue eyes'), findsOneWidget);

    await tester.tap(find.text('blue eyes'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('手动编辑'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('prompt-tag-manual-translation-field')),
      '手动蓝眼',
    );
    await tester.tap(find.byKey(const ValueKey('prompt-tag-manual-save')));
    await tester.pumpAndSettle();

    expect(find.text('手动蓝眼'), findsOneWidget);
    expect(translationCache.getCached('blue eyes'), '手动蓝眼');
  });

  testWidgets('manual translation dialog ignores stale AI refusal cache', (
    tester,
  ) async {
    final translationCache = TranslationCache(
      entries: {
        TranslationCache.cacheKey('(sincos)(year 2025)'):
            const TranslationCacheEntry(
          translation: '抱歉，我无法回答这个问题，请提出其他合规的问题',
          source: 'ai',
          ts: 1710000000,
        ),
      },
    );

    await tester.pumpWidget(
      host(
        PromptTagDisplay(
          text: '(sincos)(year 2025)',
          defaultTranslated: true,
          enableTagActions: true,
          translationCache: translationCache,
        ),
      ),
    );

    expect(find.textContaining('抱歉'), findsNothing);

    await tester.tap(
      find.text('(sincos)(year 2025)'),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('手动编辑'));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('prompt-tag-manual-translation-field')),
    );
    expect(field.controller?.text, isEmpty);
  });

  testWidgets('interactive tags support box selection and reset by default', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        PromptTagDisplay(
          text: 'year_2021, year_2022, year_2023',
          enableTagActions: true,
          translationCache: cache(),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('prompt-tag-selection-area')),
      findsOneWidget,
    );

    await dragSelectionAround(
      tester,
      chipKey('year_2021', 0, selected: false),
      chipKey('year_2022', 1, selected: false),
    );

    expect(chipKey('year_2021', 0, selected: true), findsOneWidget);
    expect(chipKey('year_2022', 1, selected: true), findsOneWidget);
    expect(chipKey('year_2023', 2, selected: true), findsNothing);

    await dragSelectionAround(
      tester,
      chipKey('year_2023', 2, selected: false),
      chipKey('year_2023', 2, selected: false),
    );

    expect(chipKey('year_2021', 0, selected: true), findsNothing);
    expect(chipKey('year_2022', 1, selected: true), findsNothing);
    expect(chipKey('year_2023', 2, selected: true), findsOneWidget);
  });

  testWidgets('ctrl box selection appends selected chips', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        PromptTagDisplay(
          text: 'year_2021, year_2022, year_2023',
          enableTagActions: true,
          translationCache: cache(),
        ),
      ),
    );

    await dragSelectionAround(
      tester,
      chipKey('year_2021', 0, selected: false),
      chipKey('year_2021', 0, selected: false),
    );
    await dragSelectionAround(
      tester,
      chipKey('year_2023', 2, selected: false),
      chipKey('year_2023', 2, selected: false),
      additive: true,
    );

    expect(chipKey('year_2021', 0, selected: true), findsOneWidget);
    expect(chipKey('year_2023', 2, selected: true), findsOneWidget);
    expect(
      find.byKey(const ValueKey('prompt-tag-chip-check-year_2021-0')),
      findsOneWidget,
    );
    expect(chipKey('year_2022', 1, selected: true), findsNothing);
  });

  testWidgets('ctrl c copies selected interactive display tags', (
    tester,
  ) async {
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
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(
      host(
        PromptTagDisplay(
          text: 'blue eyes, long hair, white shirt',
          enableTagActions: true,
          translationCache: cache(),
        ),
      ),
    );

    await dragSelectionAround(
      tester,
      chipKey('blue eyes', 0, selected: false),
      chipKey('long hair', 1, selected: false),
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(copiedText, 'blue eyes, long hair');
  });

  testWidgets(
    'selected editable display tags can be dragged between displays',
    (tester) async {
      var upper = 'fox ears, red halo';
      var lower = 'fox tail';

      await tester.pumpWidget(
        host(
          StatefulBuilder(
            builder: (context, setState) {
              return Column(
                children: [
                  PromptTagDisplay(
                    key: const ValueKey('upper-display'),
                    text: upper,
                    enableTagActions: true,
                    translationCache: cache(),
                    onChanged: (next) => setState(() => upper = next),
                  ),
                  const SizedBox(height: 24),
                  PromptTagDisplay(
                    key: const ValueKey('lower-display'),
                    text: lower,
                    enableTagActions: true,
                    translationCache: cache(),
                    onChanged: (next) => setState(() => lower = next),
                  ),
                ],
              );
            },
          ),
        ),
      );

      final upperDisplay = find.byKey(const ValueKey('upper-display'));
      final lowerDisplay = find.byKey(const ValueKey('lower-display'));
      final idleSourceChip = find.descendant(
        of: upperDisplay,
        matching: chipKey('fox ears', 0, selected: false),
      );
      final lowerDropArea = find.descendant(
        of: lowerDisplay,
        matching: find.byKey(const ValueKey('prompt-tag-selection-area')),
      );

      await dragSelectionAround(tester, idleSourceChip, idleSourceChip);

      final selectedSourceChip = find.descendant(
        of: upperDisplay,
        matching: chipKey('fox ears', 0, selected: true),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      final start = tester.getCenter(selectedSourceChip);
      final end = tester.getCenter(lowerDropArea);
      await mouse.addPointer(location: start);
      await tester.pump();
      await mouse.down(start);
      await mouse.moveTo(end);
      await tester.pump();
      await mouse.up();
      await tester.pumpAndSettle();
      await mouse.removePointer();

      expect(upper, 'red halo');
      expect(lower, 'fox tail, fox ears');
    },
  );

  testWidgets(
    'unselected editable display tag can be dragged directly between displays',
    (tester) async {
      var upper = 'fox ears, red halo';
      var lower = 'fox tail';

      await tester.pumpWidget(
        host(
          StatefulBuilder(
            builder: (context, setState) {
              return Column(
                children: [
                  PromptTagDisplay(
                    key: const ValueKey('upper-display'),
                    text: upper,
                    enableTagActions: true,
                    translationCache: cache(),
                    onChanged: (next) => setState(() => upper = next),
                  ),
                  const SizedBox(height: 24),
                  PromptTagDisplay(
                    key: const ValueKey('lower-display'),
                    text: lower,
                    enableTagActions: true,
                    translationCache: cache(),
                    onChanged: (next) => setState(() => lower = next),
                  ),
                ],
              );
            },
          ),
        ),
      );

      final upperDisplay = find.byKey(const ValueKey('upper-display'));
      final lowerDisplay = find.byKey(const ValueKey('lower-display'));
      final idleSourceChip = find.descendant(
        of: upperDisplay,
        matching: chipKey('fox ears', 0, selected: false),
      );
      final lowerDropArea = find.descendant(
        of: lowerDisplay,
        matching: find.byKey(const ValueKey('prompt-tag-selection-area')),
      );

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      final start = tester.getCenter(idleSourceChip);
      final end = tester.getCenter(lowerDropArea);
      await mouse.addPointer(location: start);
      await tester.pump();
      await mouse.down(start);
      await mouse.moveTo(end);
      await tester.pump();
      await mouse.up();
      await tester.pumpAndSettle();
      await mouse.removePointer();

      expect(upper, 'red halo');
      expect(lower, 'fox tail, fox ears');
    },
  );

  testWidgets('escape and clear button empty interactive tag selection', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        PromptTagDisplay(
          text: 'blue eyes, long hair',
          enableTagActions: true,
          translationCache: cache(),
        ),
      ),
    );

    await tester.tap(find.text('blue eyes'));
    await tester.pump();
    expect(chipKey('blue eyes', 0, selected: true), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(chipKey('blue eyes', 0, selected: true), findsNothing);

    await tester.tap(find.text('long hair'));
    await tester.pump();
    expect(chipKey('long hair', 1, selected: true), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('prompt-tag-clear-selection')));
    await tester.pump();
    expect(chipKey('long hair', 1, selected: true), findsNothing);
  });

  testWidgets('selection toolbar floats without shifting tag layout', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        PromptTagDisplay(
          text: 'blue eyes, long hair',
          enableTagActions: true,
          translationCache: cache(),
        ),
      ),
    );

    final firstChipTopBefore = tester.getTopLeft(
      chipKey('blue eyes', 0, selected: false),
    );

    await tester.tap(find.text('long hair'));
    await tester.pump();

    expect(find.byKey(const ValueKey('prompt-tag-clear-selection')), findsOne);
    final toolbarTop = tester.getTopLeft(
      find.byKey(const ValueKey('prompt-tag-selection-toolbar')),
    );
    final firstChipTop = tester.getTopLeft(
      chipKey('blue eyes', 0, selected: false),
    );

    expect(firstChipTop.dy, closeTo(firstChipTopBefore.dy, 0.1));
    expect(toolbarTop.dy, lessThan(firstChipTop.dy));
  });

  testWidgets('selection toolbar stays inside bounded tag display', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 260);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      host(
        SizedBox(
          width: 280,
          child: DecoratedBox(
            key: const ValueKey('bounded-tag-display'),
            decoration: BoxDecoration(
              border: Border.all(color: StudioTokens.border),
            ),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: PromptTagDisplay(
                text:
                    'detailed eyes, best quality, amazing quality, very aesthetic',
                enableTagActions: true,
                showLayoutControls: true,
                initialLayoutMode: PromptTagLayoutMode.grouped,
                translationCache: cache(),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('best quality'));
    await tester.pump();

    final bounds = tester.getRect(
      find.byKey(const ValueKey('bounded-tag-display')),
    );
    final toolbar = tester.getRect(
      find.byKey(const ValueKey('prompt-tag-selection-toolbar')),
    );

    expect(toolbar.top, greaterThanOrEqualTo(bounds.top));
    expect(toolbar.right, lessThanOrEqualTo(bounds.right));
  });

  testWidgets(
    'selected chips use the preview border and keep category stripe',
    (tester) async {
      await tester.pumpWidget(
        host(
          PromptTagDisplay(
            text: 'blue eyes',
            enableTagActions: true,
            translationCache: cache(),
          ),
        ),
      );

      await tester.tap(find.text('blue eyes'));
      await tester.pump();

      final selectedChip = tester.widget<AnimatedContainer>(
        chipKey('blue eyes', 0, selected: true),
      );
      final decoration = selectedChip.decoration! as BoxDecoration;
      final border = decoration.border! as Border;

      expect(selectedChip.clipBehavior, Clip.antiAlias);
      expect(decoration.color, const Color(0xFF22200B));
      expect(border.top.color, StudioTokens.primary);
      expect(decoration.borderRadius, StudioTokens.radiusTag);
      expect(
        find.byKey(const ValueKey('prompt-tag-chip-marker-blue eyes-0')),
        findsOneWidget,
      );
      final marker = tester.widget<DecoratedBox>(
        find.byKey(const ValueKey('prompt-tag-chip-marker-blue eyes-0')),
      );
      final markerDecoration = marker.decoration as BoxDecoration;
      expect(markerDecoration.color, const Color(0xFF5B8DEF));
      expect(
        find.byKey(const ValueKey('prompt-tag-chip-check-blue eyes-0')),
        findsOneWidget,
      );
    },
  );

  testWidgets('idle and drag-preview chips keep category color as a stripe', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        PromptTagDisplay(
          text: 'blue eyes, long hair',
          enableTagActions: true,
          translationCache: cache(),
        ),
      ),
    );

    final idleChip = tester.widget<AnimatedContainer>(
      chipKey('blue eyes', 0, selected: false),
    );
    final idleDecoration = idleChip.decoration! as BoxDecoration;
    final idleBorder = idleDecoration.border! as Border;

    expect(idleChip.clipBehavior, Clip.antiAlias);
    expect(idleDecoration.color, const Color(0xFF181818));
    expect(idleBorder.top.color, StudioTokens.border);
    final idleMarker = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('prompt-tag-chip-marker-blue eyes-0')),
    );
    expect(
      (idleMarker.decoration as BoxDecoration).color,
      const Color(0xFF5B8DEF),
    );

    final start =
        selectionStartNear(tester, chipKey('blue eyes', 0, selected: false));
    final end =
        tester.getBottomRight(chipKey('blue eyes', 0, selected: false)) -
            const Offset(1, 1);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: start);
    await tester.pump();

    await mouse.down(start);
    await mouse.moveTo(end);
    await tester.pump();

    final previewChip = tester.widget<Container>(
      chipKey('blue eyes', 0, selected: false),
    );
    final decoration = previewChip.decoration! as BoxDecoration;
    final border = decoration.border! as Border;

    expect(previewChip.clipBehavior, Clip.antiAlias);
    expect(decoration.color, const Color(0xFF1F2430));
    expect(border.top.color, StudioTokens.info);
    final previewMarker = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('prompt-tag-chip-marker-blue eyes-0')),
    );
    expect(
      (previewMarker.decoration as BoxDecoration).color,
      const Color(0xFF5B8DEF),
    );

    await mouse.up();
    await tester.pump();
    await mouse.removePointer();
  });

  testWidgets('right click opens the Danbooru wiki for normalized tags', (
    tester,
  ) async {
    Uri? openedUri;
    await tester.pumpWidget(
      host(
        PromptTagDisplay(
          text: 'blue eyes',
          enableTagActions: true,
          translationCache: cache(),
          onOpenDanbooru: (uri) async {
            openedUri = uri;
          },
        ),
      ),
    );

    await tester.tap(find.text('blue eyes'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();

    expect(find.text('打开 Danbooru Wiki'), findsOneWidget);

    await tester.tap(find.text('打开 Danbooru Wiki'));
    await tester.pumpAndSettle();

    expect(
      openedUri.toString(),
      'https://danbooru.donmai.us/wiki_pages/blue_eyes',
    );
  });

  testWidgets('right click can add selected tags to filter rules', (
    tester,
  ) async {
    List<String>? addedTags;
    await tester.pumpWidget(
      host(
        PromptTagDisplay(
          text: 'blue eyes, long hair, white shirt',
          enableTagActions: true,
          translationCache: cache(),
          onAddToFilterRules: (tags, target) async {
            addedTags = tags;
            expect(target, PromptTagFilterRuleTarget.deleteKeywords);
          },
        ),
      ),
    );

    await dragSelectionAround(
      tester,
      chipKey('blue eyes', 0, selected: false),
      chipKey('long hair', 1, selected: false),
    );
    await tester.tap(find.text('blue eyes'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('prompt-tag-add-to-filter-rules')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('prompt-tag-add-to-filter-rules')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('prompt-tag-filter-target-dialog')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('prompt-tag-filter-target-delete')),
    );
    await tester.pumpAndSettle();

    expect(addedTags, ['blue eyes', 'long hair']);
  });

  testWidgets('right click weight edit applies to selected display tags', (
    tester,
  ) async {
    var value = 'blue eyes, long hair, white shirt';

    await tester.pumpWidget(
      host(
        StatefulBuilder(
          builder: (context, setState) {
            return PromptTagDisplay(
              text: value,
              enableTagActions: true,
              translationCache: cache(),
              onChanged: (next) => setState(() => value = next),
            );
          },
        ),
      ),
    );

    await dragSelectionAround(
      tester,
      chipKey('blue eyes', 0, selected: false),
      chipKey('long hair', 1, selected: false),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('long hair'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('prompt-tag-edit-weight')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('prompt-tag-edit-weight-field')),
      '0.6',
    );
    await tester.tap(find.byKey(const ValueKey('prompt-tag-edit-weight-save')));
    await tester.pumpAndSettle();

    expect(value, '0.6:: blue eyes ::, 0.6:: long hair ::, white shirt');
    expect(find.text('x0.60'), findsNWidgets(2));
    expect(find.text('white shirt'), findsOneWidget);
  });

  testWidgets('right click can expose an extra script-only filter target', (
    tester,
  ) async {
    List<String>? addedTags;
    PromptTagFilterRuleTarget? addedTarget;
    await tester.pumpWidget(
      host(
        PromptTagDisplay(
          text: 'city lights',
          enableTagActions: true,
          translationCache: cache(),
          filterRuleTargets: const [
            PromptTagFilterRuleTarget.deleteKeywords,
            PromptTagFilterRuleTarget.scriptScopedBlockWords,
          ],
          onAddToFilterRules: (tags, target) async {
            addedTags = tags;
            addedTarget = target;
          },
        ),
      ),
    );

    await tester.tap(find.text('city lights'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('prompt-tag-add-to-filter-rules')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('prompt-tag-filter-target-script')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('prompt-tag-filter-target-script')),
    );
    await tester.pumpAndSettle();

    expect(addedTags, ['city lights']);
    expect(addedTarget, PromptTagFilterRuleTarget.scriptScopedBlockWords);
  });

  testWidgets('right click on an unselected tag moves the active selection', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        PromptTagDisplay(
          text: 'blue eyes, long hair, white shirt',
          enableTagActions: true,
          translationCache: cache(),
        ),
      ),
    );

    await dragSelectionAround(
      tester,
      chipKey('blue eyes', 0, selected: false),
      chipKey('long hair', 1, selected: false),
    );

    expect(chipKey('blue eyes', 0, selected: true), findsOneWidget);
    expect(chipKey('long hair', 1, selected: true), findsOneWidget);

    await tester.tap(find.text('white shirt'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();

    expect(chipKey('blue eyes', 0, selected: true), findsNothing);
    expect(chipKey('long hair', 1, selected: true), findsNothing);
    expect(chipKey('white shirt', 2, selected: true), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
  });

  testWidgets('filter target dialog options show hover feedback', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        PromptTagDisplay(
          text: 'blue eyes',
          enableTagActions: true,
          translationCache: cache(),
          onAddToFilterRules: (_, __) async {},
        ),
      ),
    );

    await tester.tap(find.text('blue eyes'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('prompt-tag-add-to-filter-rules')),
    );
    await tester.pumpAndSettle();

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(
      tester.getCenter(
        find.byKey(const ValueKey('prompt-tag-filter-target-delete')),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 180));

    final hoveredSurface = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey('prompt-tag-filter-target-delete-surface')),
    );
    final decoration = hoveredSurface.decoration! as BoxDecoration;
    final border = decoration.border! as Border;
    expect(decoration.color, StudioTokens.surface3);
    expect(border.top.color, StudioTokens.borderStrong);
  });

  testWidgets('right click uses the global filter rule controller', (
    tester,
  ) async {
    List<String>? addedTags;
    PromptTagFilterRuleTarget? addedTarget;
    GetIt.I.registerSingleton<PromptTagFilterRulesController>(
      PromptTagFilterRulesController(
        addTags: (tags, target) async {
          addedTags = tags;
          addedTarget = target;
        },
      ),
    );
    await tester.pumpWidget(
      host(
        PromptTagDisplay(
          text: 'blue eyes',
          enableTagActions: true,
          translationCache: cache(),
        ),
      ),
    );

    await tester.tap(find.text('blue eyes'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('prompt-tag-add-to-filter-rules')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('prompt-tag-add-to-filter-rules')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('prompt-tag-filter-target-strong')),
    );
    await tester.pumpAndSettle();

    expect(addedTags, ['blue eyes']);
    expect(addedTarget, PromptTagFilterRuleTarget.strongFilterKeywords);
  });

  testWidgets('grouped layout renders package blocks and category cache', (
    tester,
  ) async {
    final classificationCache = PromptTagClassificationCache(
      clock: () => 1710000000,
    );

    await tester.pumpWidget(
      host(
        PromptTagDisplay(
          text: 'masterpiece, artist: sy4, blue eyes, standing',
          initialLayoutMode: PromptTagLayoutMode.grouped,
          showLayoutControls: true,
          enableTagActions: true,
          translationCache: cache(),
          classificationCache: classificationCache,
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('prompt-tag-group-quality')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('prompt-tag-group-artist')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('prompt-tag-group-character')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('prompt-tag-group-action')),
      findsOneWidget,
    );
    expect(classificationCache.entryFor('artist: sy4'), isNotNull);
  });

  testWidgets('layout controls switch between source order and grouped blocks',
      (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        PromptTagDisplay(
          text: 'masterpiece, artist: sy4, blue eyes, standing',
          initialLayoutMode: PromptTagLayoutMode.grouped,
          showLayoutControls: true,
          translationCache: cache(),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('prompt-tag-layout-sourceOrder')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('prompt-tag-layout-grouped')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('prompt-tag-group-quality')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('prompt-tag-layout-sourceOrder')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('prompt-tag-group-quality')),
      findsNothing,
    );
    expect(chipKey('masterpiece', 0, selected: false), findsOneWidget);
    expect(chipKey('artist: sy4', 1, selected: false), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('prompt-tag-layout-grouped')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('prompt-tag-group-quality')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('prompt-tag-group-artist')),
      findsOneWidget,
    );
  });

  test('v4 prompt groups keep role captions before base prompt', () {
    final groups = promptTagGroupsFromV4Prompt({
      'caption': {
        'base_caption': 'best quality, city',
        'char_captions': [
          {'char_caption': 'hero, red hair'},
          {'char_caption': 'sidekick, blue eyes'},
        ],
      },
    });

    expect(groups.map((group) => group.id), ['role-1', 'role-2', 'base']);
    expect(groups[0].text, 'hero, red hair');
    expect(groups[1].text, 'sidekick, blue eyes');
    expect(groups[2].text, 'best quality, city');
    expect(groups[0].negative, isFalse);
  });

  testWidgets('prompt tag display stays grouped without layout controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        PromptTagDisplay(
          text: 'masterpiece, artist: sy4, blue eyes, standing',
          initialLayoutMode: PromptTagLayoutMode.sourceOrder,
          showLayoutControls: false,
          translationCache: cache(),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('prompt-tag-group-quality')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('prompt-tag-group-artist')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('prompt-tag-group-character')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('prompt-tag-group-action')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('prompt-tag-layout-sourceOrder')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('prompt-tag-layout-grouped')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('prompt-tag-layout-layered')),
      findsNothing,
    );
  });

  testWidgets(
    'dragging a selected tag onto a grouped block changes its block',
    (tester) async {
      var value = 'masterpiece, artist: sy4, blue eyes, standing';
      var classificationChangeCount = 0;
      var saveCount = 0;
      final classificationCache = PromptTagClassificationCache(
        clock: () => 1710000000,
      );

      await tester.pumpWidget(
        host(
          StatefulBuilder(
            builder: (context, setState) {
              return PromptTagDisplay(
                text: value,
                initialLayoutMode: PromptTagLayoutMode.grouped,
                showLayoutControls: true,
                enableTagActions: true,
                translationCache: cache(),
                classificationCache: classificationCache,
                onChanged: (next) => setState(() => value = next),
                onClassificationChanged: () {
                  classificationChangeCount += 1;
                },
                saveClassificationCache: (_) async {
                  saveCount += 1;
                },
              );
            },
          ),
        ),
      );

      await dragSelectionAround(
        tester,
        chipKey('standing', 3, selected: false),
        chipKey('standing', 3, selected: false),
      );

      final selectedStanding = chipKey('standing', 3, selected: true);
      final artistGroup = find.byKey(const ValueKey('prompt-tag-group-artist'));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      final start = tester.getCenter(selectedStanding);
      final end = tester.getTopRight(artistGroup) + const Offset(-14, 14);
      await mouse.addPointer(location: start);
      await tester.pump();
      await mouse.down(start);
      await mouse.moveTo(end);
      await tester.pump();
      await mouse.up();
      await tester.pumpAndSettle();
      await mouse.removePointer();

      expect(
        classificationCache.entryFor('standing')?.category,
        PromptTagCategory.artist,
      );
      expect(classificationChangeCount, 1);
      expect(saveCount, 1);
      expect(
        find.descendant(of: artistGroup, matching: find.text('standing')),
        findsOneWidget,
      );
      expect(value, 'masterpiece, artist: sy4, blue eyes, standing');
    },
  );

  testWidgets('grouped layout renders group header actions', (tester) async {
    PromptTagGroupActionContext? capturedContext;
    await tester.pumpWidget(
      host(
        PromptTagDisplay(
          text: '1.2::artist: sy4::, blue eyes',
          initialLayoutMode: PromptTagLayoutMode.grouped,
          translationCache: cache(),
          groupActionBuilder: (context, groupContext) {
            if (groupContext.group.id != 'artist') {
              return null;
            }
            capturedContext = groupContext;
            return TextButton(
              key: const ValueKey('artist-group-save-action'),
              onPressed: () {},
              child: const Text('save'),
            );
          },
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('prompt-tag-group-artist')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('artist-group-save-action')),
      findsOneWidget,
    );
    expect(capturedContext?.group.id, 'artist');
    expect(capturedContext?.displayTags, ['artist: sy4']);
    expect(capturedContext?.promptTags, ['1.2:: artist: sy4 ::']);
  });

  testWidgets('render-only rule classifications are not persisted', (
    tester,
  ) async {
    var saveCount = 0;
    final classificationCache = PromptTagClassificationCache(
      clock: () => 1710000000,
    );

    await tester.pumpWidget(
      host(
        PromptTagDisplay(
          text: 'eonsang, freng',
          initialLayoutMode: PromptTagLayoutMode.grouped,
          translationCache: cache(),
          classificationCache: classificationCache,
          saveClassificationCache: (_) async {
            saveCount += 1;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(classificationCache.entryFor('eonsang'), isNotNull);
    expect(saveCount, 0);
  });

  testWidgets(
    'grouped layout falls back to source order when only one group is present',
    (tester) async {
      await tester.pumpWidget(
        host(
          PromptTagDisplay(
            text: 'year_2023, year_2024',
            initialLayoutMode: PromptTagLayoutMode.grouped,
            translationCache: cache(),
          ),
        ),
      );

      expect(
        find.byKey(const ValueKey('prompt-tag-group-other')),
        findsNothing,
      );
      expect(chipKey('year_2023', 0, selected: false), findsOneWidget);
      expect(chipKey('year_2024', 1, selected: false), findsOneWidget);
    },
  );

  testWidgets('legacy layered initial mode still renders grouped blocks', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        PromptTagDisplay(
          text: 'masterpiece, artist: sy4',
          initialLayoutMode: PromptTagLayoutMode.layered,
          translationCache: cache(),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('prompt-tag-group-quality')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('prompt-tag-group-artist')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('prompt-tag-layer-quality')),
      findsNothing,
    );
  });

  testWidgets('AI retranslate uses registered prompt translation service', (
    tester,
  ) async {
    final translationCache = cache();
    GetIt.I.registerSingleton<PromptTranslationService>(
      _FakePromptTranslationService(
        const OnlineTranslationResult(
          text: '网络蓝眼睛',
          source: OnlineAiResultSource.online,
          providerName: 'fake-ai',
        ),
      ),
    );

    await tester.pumpWidget(
      host(
        PromptTagDisplay(
          text: 'blue eyes',
          defaultTranslated: true,
          enableTagActions: true,
          translationCache: translationCache,
        ),
      ),
    );

    await tester.tap(find.text('blue eyes'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('AI'));
    await tester.pumpAndSettle();

    expect(find.text('网络蓝眼睛'), findsOneWidget);
    expect(translationCache.getCached('blue eyes'), '网络蓝眼睛');
  });
}

class _FakePromptTranslationService implements PromptTranslationService {
  final OnlineTranslationResult result;

  const _FakePromptTranslationService(this.result);

  @override
  OnlineAiMode get currentMode => OnlineAiMode.ai;

  @override
  Future<OnlineTranslationResult> translate(
    OnlineTranslationRequest request, {
    bool preferCache = true,
  }) async {
    return result;
  }
}
