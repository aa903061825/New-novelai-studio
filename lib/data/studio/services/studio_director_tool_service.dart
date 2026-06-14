import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:nai_casrand/data/models/api_request.dart';
import 'package:nai_casrand/data/models/payload_config.dart';
import 'package:nai_casrand/data/studio/models/studio_director_tool.dart';

class StudioDirectorToolService {
  static const augmentImageEndpoint =
      'https://image.novelai.net/ai/augment-image';

  const StudioDirectorToolService();

  ApiRequest buildRequest({
    required PayloadConfig config,
    required String sourceImageB64,
    required int sourceWidth,
    required int sourceHeight,
    required StudioDirectorToolOptions options,
  }) {
    if (sourceImageB64.trim().isEmpty) {
      throw StateError('Director Tool source image is missing.');
    }
    if (sourceWidth <= 0 || sourceHeight <= 0) {
      throw StateError('Director Tool source image dimensions are missing.');
    }

    final payload = <String, dynamic>{
      'image': sourceImageB64,
      'width': sourceWidth,
      'height': sourceHeight,
      'req_type': options.tool.requestType,
    };
    if (options.usesDefry) {
      payload['defry'] = options.defry.clamp(0, 5);
      payload['prompt'] = options.prompt.trim();
    }

    return ApiRequest(
      endpoint: augmentImageEndpoint,
      proxy: config.settings.proxy,
      headers: config.getHeaders(),
      payload: payload,
      timeout: const Duration(seconds: 60),
      logLabel: 'studio-director-tool',
    );
  }

  List<StudioDirectorToolResultImage> decodeResultImages(
    Uint8List responseBytes,
  ) {
    final archive = ZipDecoder().decodeBytes(responseBytes);
    final imageFiles = archive.files
        .where((file) => file.isFile && _isImageFile(file.name))
        .toList(growable: false)
      ..sort((a, b) => a.name.compareTo(b.name));
    if (imageFiles.isEmpty) {
      throw const FormatException(
        'Director Tool response did not contain image files.',
      );
    }
    return [
      for (final (index, file) in imageFiles.indexed)
        StudioDirectorToolResultImage(
          bytes: Uint8List.fromList(file.content as List<int>),
          variantName: _variantName(file.name),
          variantIndex: index,
        ),
    ];
  }

  bool _isImageFile(String name) {
    final lower = name.toLowerCase();
    return lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.webp');
  }

  String _variantName(String name) {
    final fileName = name.replaceAll('\\', '/').split('/').last;
    final extensionIndex = fileName.lastIndexOf('.');
    return extensionIndex <= 0
        ? fileName
        : fileName.substring(0, extensionIndex);
  }
}
