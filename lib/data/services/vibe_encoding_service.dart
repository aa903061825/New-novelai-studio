import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:novel_studio/data/models/api_request.dart';
import 'package:novel_studio/data/models/vibe_config_v4.dart';
import 'package:novel_studio/data/services/api_service.dart';

typedef VibeEncodingFetch = Future<ApiResponse> Function(ApiRequest request);

class VibeEncodingService {
  static const defaultEndpoint = 'https://image.novelai.net/ai/encode-vibe';

  final VibeEncodingFetch fetchData;

  VibeEncodingService({
    VibeEncodingFetch? fetchData,
  }) : fetchData = fetchData ?? ApiService().fetchData;

  static bool hasSourceImage(VibeConfigV4 vibe) {
    if (vibe.imageBytes != null && vibe.imageBytes!.isNotEmpty) {
      return true;
    }
    final legacyImage = vibe.legacyImageB64?.trim() ?? '';
    if (legacyImage.isNotEmpty) {
      return true;
    }
    final path = vibe.sourceImagePath?.trim() ?? '';
    return path.isNotEmpty && File(path).existsSync();
  }

  static bool needsEncoding(VibeConfigV4 vibe, String model) {
    return vibe.encodingFor(model, vibe.infoExtracted) == null;
  }

  static int pendingEncodingCount(
    Iterable<VibeConfigV4> vibes,
    String model,
  ) {
    return vibes
        .where(hasSourceImage)
        .where((vibe) => needsEncoding(vibe, model))
        .length;
  }

  Future<int> prepareForGeneration({
    required Iterable<VibeConfigV4> vibes,
    required String model,
    required String generationEndpoint,
    required String proxy,
    required Map<String, String> headers,
  }) async {
    var encodedCount = 0;
    for (final vibe in vibes) {
      final targetInfo = vibe.infoExtracted.clamp(0.0, 1.0).toDouble();
      if (vibe.useCachedEncoding(model, targetInfo)) {
        continue;
      }
      if (!hasSourceImage(vibe)) {
        throw StateError(
          'Vibe "${vibe.fileName}" has no source image for '
          'Information Extracted ${targetInfo.toStringAsFixed(2)}.',
        );
      }

      final response = await fetchData(
        ApiRequest(
          endpoint: encodingEndpointFor(generationEndpoint),
          proxy: proxy,
          headers: headers,
          payload: {
            'image': base64Encode(await _sourceImageBytes(vibe)),
            'information_extracted': targetInfo,
            'model': model,
          },
          timeout: const Duration(minutes: 2),
          logLabel: 'vibe-encoding',
        ),
      );
      final statusCode = int.tryParse(response.status) ?? 0;
      if (statusCode < 200 || statusCode >= 300) {
        throw VibeEncodingException(
          'Vibe encoding failed with HTTP ${response.status}.',
        );
      }
      if (response.data.isEmpty) {
        throw const VibeEncodingException(
          'Vibe encoding returned an empty response.',
        );
      }

      vibe.cacheEncoding(
        model: model,
        infoExtracted: targetInfo,
        encoding: base64Encode(response.data),
      );
      encodedCount++;
    }
    return encodedCount;
  }

  static String encodingEndpointFor(String generationEndpoint) {
    final trimmed = generationEndpoint.trim();
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return defaultEndpoint;
    }
    final segments = uri.pathSegments.toList();
    if (segments.isNotEmpty &&
        (segments.last == 'generate-image' ||
            segments.last == 'generate-image-stream')) {
      segments[segments.length - 1] = 'encode-vibe';
      return uri.replace(pathSegments: segments, query: null).toString();
    }
    return defaultEndpoint;
  }

  Future<Uint8List> _sourceImageBytes(VibeConfigV4 vibe) async {
    final bytes = vibe.imageBytes;
    if (bytes != null && bytes.isNotEmpty) {
      return bytes;
    }

    final legacyImage = vibe.legacyImageB64?.trim() ?? '';
    if (legacyImage.isNotEmpty) {
      return base64Decode(_stripDataUrlPrefix(legacyImage));
    }

    final path = vibe.sourceImagePath?.trim() ?? '';
    if (path.isEmpty) {
      throw StateError('Vibe "${vibe.fileName}" has no source image.');
    }
    return File(path).readAsBytes();
  }
}

class VibeEncodingException implements Exception {
  final String message;

  const VibeEncodingException(this.message);

  @override
  String toString() => message;
}

String _stripDataUrlPrefix(String value) {
  final commaIndex = value.indexOf(',');
  if (value.startsWith('data:') && commaIndex >= 0) {
    return value.substring(commaIndex + 1);
  }
  return value;
}
