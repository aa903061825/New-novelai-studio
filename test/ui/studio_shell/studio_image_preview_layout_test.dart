import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/ui/core/app_display_settings.dart';
import 'package:nai_casrand/ui/studio_shell/widgets/studio_image_preview_layout.dart';

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
}
