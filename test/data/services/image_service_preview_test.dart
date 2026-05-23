import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nai_casrand/data/services/image_service.dart';

void main() {
  test('ImageService encodes preview thumbnails with a 320px maximum side', () {
    final source = img.Image(width: 800, height: 400, numChannels: 3);
    img.fill(source, color: img.ColorRgb8(139, 92, 246));
    final sourceBytes = img.encodePng(source);

    final thumbnailB64 = ImageService().encodePreviewThumbnailB64(sourceBytes);
    final thumbnail = img.decodePng(base64Decode(thumbnailB64));

    expect(thumbnail, isNotNull);
    expect(thumbnail!.width, 320);
    expect(thumbnail.height, 160);
  });
}
