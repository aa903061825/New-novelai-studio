import 'dart:convert';
import 'dart:typed_data';

class VibeConfig {
  String imageB64;
  String fileName;
  double infoExtracted;
  double referenceStrength;

  VibeConfig({
    required this.imageB64,
    required this.fileName,
    required this.infoExtracted,
    required this.referenceStrength,
  });

  factory VibeConfig.fromBytes(
    Uint8List imageBytes,
    String fileName,
    double infoExtracted,
    double referenceStrength,
  ) {
    return VibeConfig(
      imageB64: base64Encode(imageBytes),
      fileName: fileName,
      infoExtracted: infoExtracted,
      referenceStrength: referenceStrength,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'image_b64': imageB64,
      'file_name': fileName,
      'info_extracted': infoExtracted,
      'reference_strength': referenceStrength,
    };
  }

  factory VibeConfig.fromJson(Map<String, dynamic> json) {
    double parseDouble(dynamic value, double fallback) {
      if (value is double) return value;
      if (value is int) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? fallback;
      return fallback;
    }

    return VibeConfig(
      imageB64: json['image_b64'] ?? '',
      fileName: json['file_name'] ?? 'Unnamed vibe',
      infoExtracted: parseDouble(json['info_extracted'], 1.0).clamp(0.0, 1.0),
      referenceStrength:
          parseDouble(json['reference_strength'], 0.3).clamp(0.0, 1.0),
    );
  }
}
