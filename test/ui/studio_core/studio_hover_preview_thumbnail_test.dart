import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/ui/studio_core/theme/studio_theme.dart';
import 'package:novel_studio/ui/studio_core/widgets/studio_hover_preview_thumbnail.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('hover preview stays visible near the viewport bottom',
      (tester) async {
    tester.view.physicalSize = const Size(420, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final previewPath = '${Uri.base.toFilePath()}assets/appicon.png';

    await tester.pumpWidget(
      MaterialApp(
        theme: StudioTheme.build(),
        home: Scaffold(
          body: Stack(
            children: [
              Positioned(
                left: 28,
                top: 260,
                child: StudioHoverPreviewThumbnail(
                  previewPaths: [previewPath],
                  overlayKey: const ValueKey('hover-preview-overlay'),
                  overlayWidth: 220,
                  overlayHeight: 180,
                  overlayOffset: const Offset(56, 0),
                  builder: (context, previewPath) {
                    return const SizedBox(
                      key: ValueKey('hover-preview-thumbnail'),
                      width: 48,
                      height: 48,
                      child: DecoratedBox(
                        decoration: BoxDecoration(color: Colors.black),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(
      location: tester.getCenter(
        find.byKey(const ValueKey('hover-preview-thumbnail')),
      ),
    );
    await tester.pump();
    await tester.pump(kStudioHoverPreviewActivationDelay);

    final overlay = find.byKey(const ValueKey('hover-preview-overlay'));
    expect(overlay, findsOneWidget);
    expect(tester.getSize(overlay), const Size(220, 180));

    final overlayRect = tester.getRect(overlay);
    expect(overlayRect.top, greaterThanOrEqualTo(12));
    expect(overlayRect.bottom, lessThanOrEqualTo(320 - 12));

    await mouse.removePointer();
  });

  testWidgets('quick wheel before hover activation scrolls the parent',
      (tester) async {
    tester.view.physicalSize = const Size(420, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);

    await tester.pumpWidget(
      _buildScrollableHoverPreview(
        scrollController: scrollController,
        previewPaths: const ['preview-a.png', 'preview-b.png'],
      ),
    );

    final thumbnail = find.byKey(const ValueKey('hover-preview-thumbnail'));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: tester.getCenter(thumbnail));
    await tester.pump();

    expect(find.byKey(const ValueKey('hover-preview-overlay')), findsNothing);

    tester.binding.handlePointerEvent(
      PointerScrollEvent(
        position: tester.getCenter(thumbnail),
        scrollDelta: const Offset(0, 80),
      ),
    );
    await tester.pump();

    expect(scrollController.offset, greaterThan(0));
    expect(find.text('preview-b.png'), findsNothing);
  });

  testWidgets('wheel after hover activation switches preview variants',
      (tester) async {
    tester.view.physicalSize = const Size(420, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);

    await tester.pumpWidget(
      _buildScrollableHoverPreview(
        scrollController: scrollController,
        previewPaths: const ['preview-a.png', 'preview-b.png'],
      ),
    );

    final thumbnail = find.byKey(const ValueKey('hover-preview-thumbnail'));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: tester.getCenter(thumbnail));
    await tester.pump();

    await tester.pump(
      kStudioHoverPreviewActivationDelay - const Duration(milliseconds: 1),
    );
    expect(find.byKey(const ValueKey('hover-preview-overlay')), findsNothing);

    await tester.pump(const Duration(milliseconds: 1));
    expect(
      find.byKey(const ValueKey('hover-preview-overlay')),
      findsOneWidget,
    );

    tester.binding.handlePointerEvent(
      PointerScrollEvent(
        position: tester.getCenter(thumbnail),
        scrollDelta: const Offset(0, 80),
      ),
    );
    await tester.pump();

    expect(scrollController.offset, 0);
    expect(find.text('preview-b.png'), findsOneWidget);
  });
}

Widget _buildScrollableHoverPreview({
  required ScrollController scrollController,
  required List<String> previewPaths,
}) {
  return MaterialApp(
    theme: StudioTheme.build(),
    home: Scaffold(
      body: SizedBox(
        height: 320,
        child: ListView(
          controller: scrollController,
          children: [
            const SizedBox(height: 24),
            Align(
              alignment: Alignment.centerLeft,
              child: StudioHoverPreviewThumbnail(
                previewPaths: previewPaths,
                overlayKey: const ValueKey('hover-preview-overlay'),
                overlayWidth: 120,
                overlayHeight: 120,
                overlayOffset: const Offset(140, 0),
                builder: (context, previewPath) {
                  return SizedBox(
                    key: const ValueKey('hover-preview-thumbnail'),
                    width: 96,
                    height: 96,
                    child: DecoratedBox(
                      decoration: const BoxDecoration(color: Colors.black),
                      child: Center(
                        child: Text(
                          previewPath ?? 'none',
                          textDirection: TextDirection.ltr,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 800),
          ],
        ),
      ),
    ),
  );
}
