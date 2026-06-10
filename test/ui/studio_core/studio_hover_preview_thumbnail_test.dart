import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/ui/studio_core/theme/studio_theme.dart';
import 'package:nai_casrand/ui/studio_core/widgets/studio_hover_preview_thumbnail.dart';

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

    final overlay = find.byKey(const ValueKey('hover-preview-overlay'));
    expect(overlay, findsOneWidget);
    expect(tester.getSize(overlay), const Size(220, 180));

    final overlayRect = tester.getRect(overlay);
    expect(overlayRect.top, greaterThanOrEqualTo(12));
    expect(overlayRect.bottom, lessThanOrEqualTo(320 - 12));

    await mouse.removePointer();
  });
}
