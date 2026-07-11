import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/ui/core/app_display_settings.dart';
import 'package:novel_studio/ui/studio_core/widgets/studio_scrollbar.dart';
import 'package:novel_studio/ui/studio_shell/widgets/studio_image_preview_layout.dart';

void main() {
  setUp(() {
    AppDisplaySettings.clearImagePreviewDialogHeightPersistence();
    AppDisplaySettings.setImagePreviewDialogHeight(
      AppDisplaySettings.defaultImagePreviewDialogHeight,
      persist: false,
    );
  });

  tearDown(() {
    AppDisplaySettings.clearImagePreviewDialogHeightPersistence();
  });

  testWidgets('resizable image preview window persists dragged height',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final persistedHeights = <double>[];
    AppDisplaySettings.configureImagePreviewDialogHeightPersistence(
      persistedHeights.add,
    );
    AppDisplaySettings.setImagePreviewDialogHeight(640, persist: false);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: StudioResizableImagePreviewWindow(
              windowKey: ValueKey('test-image-preview-window'),
              child: SizedBox.expand(),
            ),
          ),
        ),
      ),
    );

    expect(
      tester.getSize(find.byKey(const ValueKey('test-image-preview-window'))),
      const Size(1152, 640),
    );

    await tester.drag(
      find.byKey(const ValueKey('studio-image-preview-height-handle')),
      const Offset(0, 400),
    );
    await tester.pump();

    expect(
      tester.getSize(find.byKey(const ValueKey('test-image-preview-window'))),
      const Size(1152, 900),
    );
    expect(AppDisplaySettings.imagePreviewDialogHeight.value, 900);
    expect(persistedHeights, [900]);
  });

  testWidgets('automatic desktop scrollbars reserve a trailing gutter',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        scrollBehavior: const StudioScrollBehavior(),
        theme: ThemeData(platform: TargetPlatform.windows),
        home: const Scaffold(
          body: SizedBox(
            width: 120,
            height: 120,
            child: SingleChildScrollView(
              child: SizedBox(
                key: ValueKey('automatic-scroll-body'),
                height: 320,
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(Scrollbar), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Padding &&
            widget.padding ==
                const EdgeInsetsDirectional.only(
                  end: StudioScrollBehavior.verticalScrollbarGutter,
                ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('image preview prompt scroll keeps content out of its scrollbar',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: StudioImagePreviewPromptScroll(
            child: SizedBox(
              key: ValueKey('preview-prompt-content'),
              height: 720,
            ),
          ),
        ),
      ),
    );

    expect(find.byType(Scrollbar), findsOneWidget);
    expect(
      find.ancestor(
        of: find.byKey(const ValueKey('preview-prompt-content')),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Padding &&
              widget.padding ==
                  const EdgeInsetsDirectional.only(
                    end: StudioScrollBehavior.verticalScrollbarGutter,
                  ),
        ),
      ),
      findsOneWidget,
    );
  });
}
