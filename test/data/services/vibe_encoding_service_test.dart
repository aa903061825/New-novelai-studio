import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/data/models/api_request.dart';
import 'package:novel_studio/data/models/vibe_config_v4.dart';
import 'package:novel_studio/data/services/vibe_encoding_service.dart';

void main() {
  test('encodes a changed Vibe on generation and reuses the cached variant',
      () async {
    final tempDirectory =
        await Directory.systemTemp.createTemp('vibe-encoding-test-');
    addTearDown(() => tempDirectory.delete(recursive: true));
    final source =
        File('${tempDirectory.path}${Platform.pathSeparator}vibe.png');
    await source.writeAsBytes(const [1, 2, 3, 4]);
    final vibe = VibeConfigV4(
      fileName: 'style',
      vibeB64: 'old-encoding',
      infoExtracted: 0.42,
      encodedInfoExtracted: 0.76,
      referenceStrength: 0.3,
      sourceImagePath: source.path,
    );
    var calls = 0;
    late ApiRequest request;
    final service = VibeEncodingService(
      fetchData: (nextRequest) async {
        calls++;
        request = nextRequest;
        return ApiResponse(
          status: '201',
          data: Uint8List.fromList(const [5, 6, 7]),
        );
      },
    );

    final encoded = await service.prepareForGeneration(
      vibes: [vibe],
      model: 'nai-diffusion-4-5-full',
      generationEndpoint: 'https://image.novelai.net/ai/generate-image',
      proxy: '',
      headers: const {'authorization': 'Bearer test'},
    );

    expect(encoded, 1);
    expect(calls, 1);
    expect(request.endpoint, VibeEncodingService.defaultEndpoint);
    expect(request.payload['image'], base64Encode(const [1, 2, 3, 4]));
    expect(request.payload['information_extracted'], 0.42);
    expect(request.payload['model'], 'nai-diffusion-4-5-full');
    expect(vibe.vibeB64, base64Encode(const [5, 6, 7]));
    expect(vibe.encodedInfoExtracted, 0.42);

    final reused = await service.prepareForGeneration(
      vibes: [vibe],
      model: 'nai-diffusion-4-5-full',
      generationEndpoint: 'https://image.novelai.net/ai/generate-image',
      proxy: '',
      headers: const {'authorization': 'Bearer test'},
    );

    expect(reused, 0);
    expect(calls, 1);
  });

  test('does not treat an encoded-only Vibe as pending paid encoding', () {
    final vibe = VibeConfigV4(
      fileName: 'metadata-vibe',
      vibeB64: 'encoding',
      infoExtracted: 0.76,
      referenceStrength: 0.3,
    );

    expect(
      VibeEncodingService.pendingEncodingCount(
        [vibe],
        'nai-diffusion-4-5-full',
      ),
      0,
    );
    expect(VibeEncodingService.hasSourceImage(vibe), isFalse);
  });
}
