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

  test('ImageService returns null for images without stealth metadata',
      () async {
    final source = img.Image(width: 800, height: 400, numChannels: 4);
    img.fill(source, color: img.ColorRgba8(139, 92, 246, 255));

    final metadata = await ImageService().extractMetadata(source);

    expect(metadata, isNull);
  });

  test('ImageService round trips embedded stealth metadata', () async {
    final service = ImageService();
    final source = img.Image(width: 128, height: 128, numChannels: 4);
    img.fill(source, color: img.ColorRgba8(139, 92, 246, 255));
    final sourceBytes = img.encodePng(source);
    const metadata = '{"Description":"1girl","Comment":"{}"}';

    final embeddedBytes = await service.embedMetadata(sourceBytes, metadata);
    final embedded = img.decodePng(embeddedBytes);

    expect(embedded, isNotNull);
    expect(await service.extractMetadata(embedded!), metadata);
  });
}
