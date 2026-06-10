import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/studio/tools/prompt_tag_classifier.dart';
import 'package:nai_casrand/ui/studio_core/theme/studio_theme.dart';
import 'package:nai_casrand/ui/studio_core/widgets/prompt_tag_chip.dart';

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

  testWidgets('renders loading label only without a translation', (tester) async {
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
}
