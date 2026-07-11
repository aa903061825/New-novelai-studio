import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/data/studio/tools/prompt_tag_classifier.dart';
import 'package:novel_studio/ui/studio_core/motion/studio_motion_tokens.dart';
import 'package:novel_studio/ui/studio_core/theme/studio_theme.dart';
import 'package:novel_studio/ui/studio_core/theme/studio_tokens.dart';
import 'package:novel_studio/ui/studio_core/widgets/prompt_tag_chip.dart';

void main() {
  Widget host(Widget child) {
    return MaterialApp(
      theme: StudioTheme.build(),
      home: Scaffold(body: Center(child: child)),
    );
  }

  testWidgets('renders shared chip keys and handles delete', (tester) async {
    var deleted = false;

    await tester.pumpWidget(
      host(
        PromptTagChip(
          label: 'blue eyes',
          translation: 'blue translated',
          weightLabel: 'x-2.00',
          weight: -2,
          category: PromptTagCategory.upperBody,
          selected: true,
          highlighted: true,
          highlightTooltip: 'from cache',
          onDeleted: () => deleted = true,
          bodyKey: const ValueKey('shared-chip-body'),
          markerKey: const ValueKey('shared-chip-marker'),
          weightKey: const ValueKey('shared-chip-weight'),
          deleteKey: const ValueKey('shared-chip-delete'),
          checkKey: const ValueKey('shared-chip-check'),
          highlightKey: const ValueKey('shared-chip-highlight'),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('shared-chip-body')), findsOneWidget);
    expect(find.byKey(const ValueKey('shared-chip-marker')), findsOneWidget);
    expect(find.byKey(const ValueKey('shared-chip-weight')), findsOneWidget);
    expect(find.byKey(const ValueKey('shared-chip-check')), findsOneWidget);
    expect(find.byKey(const ValueKey('shared-chip-highlight')), findsOneWidget);
    expect(find.text('blue eyes'), findsOneWidget);
    expect(find.text('blue translated'), findsOneWidget);
    expect(find.text('x-2.00'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('shared-chip-delete')));
    await tester.pump();

    expect(deleted, isTrue);
  });

  testWidgets('renders loading label only without a translation',
      (tester) async {
    await tester.pumpWidget(
      host(
        const PromptTagChip(
          label: 'silver hair',
          translation: '',
          loading: true,
          loadingLabel: 'loading...',
          category: PromptTagCategory.upperBody,
          bodyKey: ValueKey('loading-chip-body'),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('loading-chip-body')), findsOneWidget);
    expect(find.text('silver hair'), findsOneWidget);
    expect(find.text('loading...'), findsOneWidget);

    await tester.pumpWidget(
      host(
        const PromptTagChip(
          label: 'silver hair',
          translation: 'silver translated',
          loading: true,
          loadingLabel: 'loading...',
          category: PromptTagCategory.upperBody,
        ),
      ),
    );

    expect(find.text('silver translated'), findsOneWidget);
    expect(find.text('loading...'), findsNothing);
  });

  testWidgets('preview chrome skips implicit animation during drag hover', (
    tester,
  ) async {
    const bodyKey = ValueKey('preview-chip-body');

    await tester.pumpWidget(
      host(
        const PromptTagChip(
          label: 'black jacket',
          translation: 'black jacket translated',
          category: PromptTagCategory.upperBody,
          previewed: true,
          bodyKey: bodyKey,
        ),
      ),
    );

    expect(find.byKey(bodyKey), findsOneWidget);
    expect(tester.widget(find.byKey(bodyKey)), isNot(isA<AnimatedContainer>()));
  });

  testWidgets('previewed and selected chips get local scale feedback', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const PromptTagChip(
          label: 'black jacket',
          translation: '',
          category: PromptTagCategory.upperBody,
          bodyKey: ValueKey('scale-chip-body'),
        ),
      ),
    );

    AnimatedScale chipScale() =>
        tester.widget<AnimatedScale>(find.byType(AnimatedScale));

    expect(chipScale().scale, 1);

    await tester.pumpWidget(
      host(
        const PromptTagChip(
          label: 'black jacket',
          translation: '',
          category: PromptTagCategory.upperBody,
          previewed: true,
          bodyKey: ValueKey('scale-chip-body'),
        ),
      ),
    );
    await tester.pump(StudioMotionTokens.fast);

    expect(chipScale().scale, greaterThan(1));

    await tester.pumpWidget(
      host(
        const PromptTagChip(
          label: 'black jacket',
          translation: '',
          category: PromptTagCategory.upperBody,
          selected: true,
          bodyKey: ValueKey('scale-chip-body'),
        ),
      ),
    );
    await tester.pump(StudioMotionTokens.fast);

    expect(chipScale().scale, greaterThan(1));
  });

  testWidgets('preview chrome omits action controls during drag hover', (
    tester,
  ) async {
    const deleteKey = ValueKey('preview-chip-delete');

    await tester.pumpWidget(
      host(
        PromptTagChip(
          label: 'black jacket',
          translation: '',
          category: PromptTagCategory.upperBody,
          previewed: true,
          deleteKey: deleteKey,
          onDeleted: () {},
        ),
      ),
    );

    expect(find.byKey(deleteKey), findsNothing);
  });

  testWidgets('highlighted diff state uses primary gold chrome', (
    tester,
  ) async {
    const bodyKey = ValueKey('highlighted-diff-chip-body');
    const diffKey = ValueKey('highlighted-diff-chip-icon');

    await tester.pumpWidget(
      host(
        const PromptTagChip(
          label: 'fox ears',
          translation: '',
          category: PromptTagCategory.upperBody,
          diffState: PromptTagChipDiffState.highlighted,
          diffBadgeLabel: '角色 1',
          bodyKey: bodyKey,
          diffKey: diffKey,
        ),
      ),
    );

    final body = tester.widget<AnimatedContainer>(find.byKey(bodyKey));
    final decoration = body.decoration! as BoxDecoration;
    final border = decoration.border! as Border;
    expect(border.top.color, StudioTokens.primary);

    final icon = tester.widget<Icon>(find.byKey(diffKey));
    expect(icon.color, StudioTokens.primary);
    expect(icon.icon, Icons.check_circle_outline);
    expect(find.text('角色 1'), findsOneWidget);
  });
}
