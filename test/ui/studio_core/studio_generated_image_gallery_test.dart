import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:novel_studio/ui/studio_core/motion/studio_interactive_surface.dart';
import 'package:novel_studio/ui/studio_core/widgets/studio_generated_image_gallery.dart';

void main() {
  testWidgets('gallery renders complete image cards with names',
      (tester) async {
    final items = [
      StudioGeneratedImageItem.memory(
        id: 'one',
        name: 'Result #1',
        imageBytes: _pngBytes,
      ),
      StudioGeneratedImageItem.memory(
        id: 'two',
        name: 'Result #2',
        imageBytes: _pngBytes,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 640,
            child: StudioGeneratedImageGallery(
              items: items,
              columnWidth: 220,
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('studio-generated-image-gallery')),
        findsOneWidget);
    expect(
      find.ancestor(
        of: find.byKey(const ValueKey('studio-generated-image-card-one')),
        matching: find.byType(StudioInteractiveSurface),
      ),
      findsOneWidget,
    );
    expect(find.text('Result #1'), findsOneWidget);
    expect(find.text('Result #2'), findsOneWidget);

    final image = tester.widget<Image>(
      find.byKey(const ValueKey('studio-generated-image-one')).first,
    );
    expect(image.fit, BoxFit.contain);
  });

  testWidgets('tapping a card opens the shared image viewer', (tester) async {
    final items = [
      StudioGeneratedImageItem.memory(
        id: 'one',
        name: 'Result #1',
        imageBytes: _pngBytes,
      ),
      StudioGeneratedImageItem.memory(
        id: 'two',
        name: 'Result #2',
        imageBytes: _pngBytes,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 640,
            child: StudioGeneratedImageGallery(
              items: items,
              columnWidth: 220,
              onOpen: (context, item) {
                StudioGeneratedImageViewerDialog.show(
                  context,
                  items: items,
                  initialItemId: item.id,
                );
              },
            ),
          ),
        ),
      ),
    );

    await tester
        .tap(find.byKey(const ValueKey('studio-generated-image-card-two')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('studio-generated-image-viewer-dialog')),
        findsOneWidget);
    expect(find.text('Result #2'), findsOneWidget);

    final image = tester.widget<Image>(
      find
          .descendant(
            of: find.byKey(
              const ValueKey('studio-generated-image-viewer-dialog'),
            ),
            matching: find.byType(Image),
          )
          .last,
    );
    expect(image.fit, BoxFit.contain);
  });

  testWidgets('plain wheel does not navigate global image lists by default',
      (tester) async {
    final items = [
      StudioGeneratedImageItem.memory(
        id: 'one',
        name: 'Result #1',
        imageBytes: _pngBytes,
      ),
      StudioGeneratedImageItem.memory(
        id: 'two',
        name: 'Result #2',
        imageBytes: _pngBytes,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 640,
            child: StudioGeneratedImageGallery(
              items: items,
              columnWidth: 220,
              onOpen: (context, item) {
                StudioGeneratedImageViewerDialog.show(
                  context,
                  items: items,
                  initialItemId: item.id,
                );
              },
            ),
          ),
        ),
      ),
    );

    await tester
        .tap(find.byKey(const ValueKey('studio-generated-image-card-one')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Result #1  1/2'), findsOneWidget);

    final viewport = find.byKey(
      const ValueKey('studio-generated-image-zoomable-viewer'),
    );
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(viewport),
        scrollDelta: const Offset(0, 120),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Result #1  1/2'), findsOneWidget);
    expect(find.textContaining('Result #2  2/2'), findsNothing);
  });

  testWidgets('plain wheel navigates when caller marks items as local variants',
      (tester) async {
    final items = [
      StudioGeneratedImageItem.memory(
        id: 'one',
        name: 'Variant #1',
        imageBytes: _pngBytes,
      ),
      StudioGeneratedImageItem.memory(
        id: 'two',
        name: 'Variant #2',
        imageBytes: _pngBytes,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 640,
            child: StudioGeneratedImageGallery(
              items: items,
              columnWidth: 220,
              onOpen: (context, item) {
                StudioGeneratedImageViewerDialog.show(
                  context,
                  items: items,
                  initialItemId: item.id,
                  wheelNavigationEnabled: true,
                );
              },
            ),
          ),
        ),
      ),
    );

    await tester
        .tap(find.byKey(const ValueKey('studio-generated-image-card-one')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Variant #1  1/2'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('studio-generated-image-viewer-dots')),
      findsOneWidget,
    );

    final viewport = find.byKey(
      const ValueKey('studio-generated-image-zoomable-viewer'),
    );
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(viewport),
        scrollDelta: const Offset(0, 120),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Variant #2  2/2'), findsOneWidget);
  });

  testWidgets('viewer separates frame navigation from local variants',
      (tester) async {
    final items = [
      StudioGeneratedImageItem.memory(
        id: 'frame-1-latest',
        name: 'Frame 1 latest',
        imageBytes: _pngBytes,
      ),
      StudioGeneratedImageItem.memory(
        id: 'frame-1-old',
        name: 'Frame 1 older',
        imageBytes: _pngBytes,
      ),
      StudioGeneratedImageItem.memory(
        id: 'frame-2-latest',
        name: 'Frame 2 latest',
        imageBytes: _pngBytes,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return TextButton(
                onPressed: () {
                  StudioGeneratedImageViewerDialog.show(
                    context,
                    items: items,
                    initialItemId: 'frame-1-latest',
                    wheelNavigationEnabled: true,
                    wheelNavigationScopeIdsByItemId: const {
                      'frame-1-old': ['frame-1-latest', 'frame-1-old'],
                      'frame-1-latest': ['frame-1-latest', 'frame-1-old'],
                    },
                  );
                },
                child: const Text('Open'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Frame 1 latest  1/2'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    expect(find.textContaining('Frame 1 older  1/2'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();

    expect(find.textContaining('Frame 2 latest  2/2'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();

    expect(find.textContaining('Frame 1 latest  1/2'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();

    expect(find.textContaining('Frame 1 latest  1/2'), findsOneWidget);
  });

  testWidgets('file-backed viewer reveals the current image in file manager', (
    tester,
  ) async {
    final tempDir = Directory.systemTemp.createTempSync(
      'generated-image-reveal-test-',
    );
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final imageFile = File(
      '${tempDir.path}${Platform.pathSeparator}result.png',
    )..writeAsBytesSync(_pngBytes);
    final revealedPaths = <String>[];
    final items = [
      StudioGeneratedImageItem.file(
        id: 'file-one',
        name: 'Saved result',
        imagePath: imageFile.path,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 640,
            child: StudioGeneratedImageGallery(
              items: items,
              columnWidth: 220,
              onOpen: (context, item) {
                StudioGeneratedImageViewerDialog.show(
                  context,
                  items: items,
                  initialItemId: item.id,
                  revealInFileManager: (path) async {
                    revealedPaths.add(path);
                  },
                );
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('studio-generated-image-card-file-one')),
    );
    await tester.pumpAndSettle();

    final revealButton = find.byKey(
      const ValueKey('studio-generated-image-viewer-reveal-file'),
    );
    expect(revealButton, findsOneWidget);
    expect(tester.widget<IconButton>(revealButton).onPressed, isNotNull);

    await tester.tap(revealButton);
    await tester.pump();

    expect(revealedPaths, [imageFile.path]);
  });

  testWidgets('file-backed cards reserve natural aspect ratio before decode', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    final tempDir = Directory.systemTemp.createTempSync(
      'generated-image-height-test-',
    );
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final imageFile = File(
      '${tempDir.path}${Platform.pathSeparator}result.png',
    )..writeAsBytesSync(_pngBytes);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: StudioGeneratedImageGallery(
              items: [
                StudioGeneratedImageItem.file(
                  id: 'file-one',
                  name: 'Saved result',
                  imagePath: imageFile.path,
                ),
              ],
              columnWidth: 220,
            ),
          ),
        ),
      ),
    );

    final image = tester.widget<Image>(
      find.byKey(const ValueKey('studio-generated-image-file-one')),
    );
    expect(image.height, isNull);
    expect(image.image, isA<ResizeImage>());
    final resizedImage = image.image as ResizeImage;
    expect(resizedImage.width, isNotNull);
    expect(resizedImage.width!, lessThanOrEqualTo(320));
    expect(resizedImage.height, isNotNull);
    expect(resizedImage.height!, lessThanOrEqualTo(320));
    final aspectRatio = tester.widget<AspectRatio>(
      find.ancestor(
        of: find.byKey(const ValueKey('studio-generated-image-file-one')),
        matching: find.byType(AspectRatio),
      ),
    );
    expect(aspectRatio.aspectRatio, 1);
  });

  testWidgets(
      'fullscreen viewer lays out images at source pixel dimensions and centers them',
      (tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final items = [
      StudioGeneratedImageItem.memory(
        id: 'wide',
        name: 'Wide result',
        imageBytes: _pngBytesFor(width: 96, height: 64),
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: StudioGeneratedImageGallery(
              items: items,
              columnWidth: 220,
              onOpen: (context, item) {
                StudioGeneratedImageViewerDialog.show(
                  context,
                  items: items,
                  initialItemId: item.id,
                );
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(
      const ValueKey('studio-generated-image-card-wide'),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(
      const ValueKey('studio-generated-image-viewer-fullscreen'),
    ));
    await tester.pumpAndSettle();

    final imageFinder = find.byKey(
      const ValueKey('studio-generated-image-viewer-image-wide'),
    );

    expect(tester.getSize(imageFinder), const Size(96, 64));
    expect(tester.getCenter(imageFinder).dx, closeTo(400, 0.1));
    expect(tester.getCenter(imageFinder).dy, closeTo(300, 0.1));
  });

  testWidgets('fullscreen viewer requests native true fullscreen and restores',
      (tester) async {
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      _windowChannel,
      (call) async {
        calls.add(call.method);
        return true;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(_windowChannel, null),
    );

    final items = [
      StudioGeneratedImageItem.memory(
        id: 'one',
        name: 'Result #1',
        imageBytes: _pngBytes,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: StudioGeneratedImageGallery(
              items: items,
              columnWidth: 220,
              onOpen: (context, item) {
                StudioGeneratedImageViewerDialog.show(
                  context,
                  items: items,
                  initialItemId: item.id,
                );
              },
            ),
          ),
        ),
      ),
    );

    await tester
        .tap(find.byKey(const ValueKey('studio-generated-image-card-one')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('studio-generated-image-viewer-fullscreen')),
    );
    await tester.pumpAndSettle();

    expect(calls, contains('enterImagePreviewFullscreen'));

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(calls, contains('exitImagePreviewFullscreen'));
  });

  testWidgets('single tapping the windowed image enters fullscreen',
      (tester) async {
    final items = [
      StudioGeneratedImageItem.memory(
        id: 'one',
        name: 'Result #1',
        imageBytes: _pngBytes,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: StudioGeneratedImageGallery(
              items: items,
              columnWidth: 220,
              onOpen: (context, item) {
                StudioGeneratedImageViewerDialog.show(
                  context,
                  items: items,
                  initialItemId: item.id,
                  fullscreenKey: const ValueKey('single-tap-fullscreen-root'),
                  fullscreenButtonKey:
                      const ValueKey('single-tap-fullscreen-toggle'),
                );
              },
            ),
          ),
        ),
      ),
    );

    await tester
        .tap(find.byKey(const ValueKey('studio-generated-image-card-one')));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('studio-generated-image-zoomable-viewer')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('single-tap-fullscreen-root')),
      findsOneWidget,
    );
  });

  testWidgets('fullscreen chrome stays hidden until the mouse reaches the top',
      (tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final items = [
      StudioGeneratedImageItem.memory(
        id: 'one',
        name: 'Result #1',
        imageBytes: _pngBytes,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: StudioGeneratedImageGallery(
              items: items,
              columnWidth: 220,
              onOpen: (context, item) {
                StudioGeneratedImageViewerDialog.show(
                  context,
                  items: items,
                  initialItemId: item.id,
                );
              },
            ),
          ),
        ),
      ),
    );

    await tester
        .tap(find.byKey(const ValueKey('studio-generated-image-card-one')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('studio-generated-image-viewer-fullscreen')),
    );
    await tester.pumpAndSettle();

    expect(_fullscreenTopChromeOpacity(tester), 0);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: const Offset(400, 300));
    await tester.pumpAndSettle();

    expect(_fullscreenTopChromeOpacity(tester), 0);

    await mouse.moveTo(const Offset(400, 8));
    await tester.pumpAndSettle();

    expect(_fullscreenTopChromeOpacity(tester), 1);

    await mouse.moveTo(const Offset(400, 300));
    await tester.pumpAndSettle();

    expect(_fullscreenTopChromeOpacity(tester), 0);
  });

  testWidgets('windowed viewer centers source image when a footer is shown',
      (tester) async {
    tester.view.physicalSize = const Size(1320, 980);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final items = [
      StudioGeneratedImageItem.memory(
        id: 'portrait',
        name: 'Portrait result',
        imageBytes: _pngBytesFor(width: 832, height: 1216),
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 420,
            child: StudioGeneratedImageGallery(
              items: items,
              columnWidth: 220,
              onOpen: (context, item) {
                StudioGeneratedImageViewerDialog.show(
                  context,
                  items: items,
                  initialItemId: item.id,
                  footerBuilder: (context, item, fullscreen) {
                    return const SizedBox(height: 240);
                  },
                );
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(
      const ValueKey('studio-generated-image-card-portrait'),
    ));
    await tester.pumpAndSettle();

    final imageFinder = find.byKey(
      const ValueKey('studio-generated-image-viewer-image-portrait'),
    );
    final viewportFinder = find.byKey(
      const ValueKey('studio-generated-image-zoomable-viewer'),
    );

    expect(tester.getSize(imageFinder), const Size(832, 1216));
    expect(
      tester.getCenter(imageFinder).dx,
      closeTo(tester.getCenter(viewportFinder).dx, 0.1),
    );
    expect(
      tester.getCenter(imageFinder).dy,
      closeTo(tester.getCenter(viewportFinder).dy, 0.1),
    );
  });
}

const _windowChannel = MethodChannel('novel_studio/window');

double _fullscreenTopChromeOpacity(WidgetTester tester) {
  return tester
      .widget<AnimatedOpacity>(
        find.byKey(
          const ValueKey('studio-generated-image-viewer-top-chrome'),
        ),
      )
      .opacity;
}

final Uint8List _pngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAFgwJ/l7G6GQAAAABJRU5ErkJggg==',
);

Uint8List _pngBytesFor({required int width, required int height}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(120, 80, 200));
  return Uint8List.fromList(img.encodePng(image));
}
