import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

class PreciseReferenceConfig {
  String imageB64;
  String fileName;
  String type;
  double strength;
  double fidelity;

  PreciseReferenceConfig({
    required this.imageB64,
    required this.fileName,
    required this.type,
    required this.strength,
    required this.fidelity,
  });

  factory PreciseReferenceConfig.fromBytes(
    Uint8List imageBytes,
    String fileName, {
    String type = 'character&style',
    double strength = 1.0,
    double fidelity = 1.0,
  }) {
    final normalizedBytes = _normalizeImage(imageBytes);
    return PreciseReferenceConfig(
      imageB64: base64Encode(normalizedBytes),
      fileName: fileName,
      type: type,
      strength: strength.clamp(0.0, 1.0),
      fidelity: fidelity.clamp(0.0, 1.0),
    );
  }

  Uint8List get imageBytes => base64Decode(imageB64);

  Map<String, dynamic> toJson() {
    return {
      'image_b64': imageB64,
      'file_name': fileName,
      'type': type,
      'strength': strength,
      'fidelity': fidelity,
    };
  }

  factory PreciseReferenceConfig.fromJson(Map<String, dynamic> json) {
    double parseDouble(dynamic value, double fallback) {
      if (value is double) return value;
      if (value is int) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? fallback;
      return fallback;
    }

    final strength = parseDouble(json['strength'], 1.0).clamp(0.0, 1.0);
    final fidelity = parseDouble(json['fidelity'], 1.0).clamp(0.0, 1.0);

    var normalizedImageB64 = json['image_b64'] ?? '';
    if (normalizedImageB64 is String && normalizedImageB64.isNotEmpty) {
      try {
        final normalizedBytes =
            _normalizeImage(base64Decode(normalizedImageB64));
        normalizedImageB64 = base64Encode(normalizedBytes);
      } catch (_) {
        // Keep original value for backward compatibility when normalization fails.
      }
    }

    final imageB64 = normalizedImageB64 is String ? normalizedImageB64 : '';

    return PreciseReferenceConfig(
      imageB64: imageB64,
      fileName: json['file_name'] ?? 'Unnamed reference',
      type: json['type'] ?? 'character&style',
      strength: strength,
      fidelity: fidelity,
    );
  }

  static const List<(int, int)> _targetCanvases = [
    (1024, 1536),
    (1536, 1024),
    (1472, 1472),
  ];

  static Uint8List _normalizeImage(Uint8List imageBytes) {
    final sourceImage = img.decodeImage(imageBytes);
    if (sourceImage == null) {
      throw const FormatException('Failed to decode precise reference image.');
    }

    final targetCanvas =
        _pickTargetCanvas(sourceImage.width, sourceImage.height);
    final targetWidth = targetCanvas.$1;
    final targetHeight = targetCanvas.$2;

    final scale = math.min(
      targetWidth / sourceImage.width,
      targetHeight / sourceImage.height,
    );
    final resizedWidth =
        ((sourceImage.width * scale).round()).clamp(1, targetWidth);
    final resizedHeight =
        ((sourceImage.height * scale).round()).clamp(1, targetHeight);

    final resizedImage = img.copyResize(
      sourceImage,
      width: resizedWidth,
      height: resizedHeight,
      interpolation: img.Interpolation.average,
    );

    final outputImage = img.Image(
      width: targetWidth,
      height: targetHeight,
      numChannels: 3,
    );
    img.fill(outputImage, color: img.ColorRgb8(0, 0, 0));
    img.compositeImage(
      outputImage,
      resizedImage,
      dstX: (targetWidth - resizedWidth) ~/ 2,
      dstY: (targetHeight - resizedHeight) ~/ 2,
    );

    return Uint8List.fromList(img.encodePng(outputImage));
  }

  static (int, int) _pickTargetCanvas(int width, int height) {
    final aspectRatio = width / height;
    var selectedCanvas = _targetCanvases.first;
    var minimumDiff = double.infinity;

    for (final canvas in _targetCanvases) {
      final diff = ((canvas.$1 / canvas.$2) - aspectRatio).abs();
      if (diff < minimumDiff) {
        minimumDiff = diff;
        selectedCanvas = canvas;
      }
    }

    return selectedCanvas;
  }
}
