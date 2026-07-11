import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:png_chunks_extract/png_chunks_extract.dart' as png_extract;

class VibeConfigV4 {
  static const int _maxLegacyImageB64Length = 16 * 1024 * 1024;
  static const String _expectedITXtKeyword = 'NovelAI_Vibe_Encoding_Base64';

  String fileName;
  String vibeB64;
  double infoExtracted;
  double referenceStrength;
  Uint8List? imageBytes;
  String? sourceImagePath;
  String? legacyImageB64;

  VibeConfigV4({
    required this.fileName,
    required this.vibeB64,
    double infoExtracted = 1.0,
    required this.referenceStrength,
    this.imageBytes,
    this.sourceImagePath,
    this.legacyImageB64,
  }) : infoExtracted = infoExtracted.clamp(0.0, 1.0).toDouble();

  static double _parseDouble(dynamic value, double fallback) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? fallback;
    return fallback;
  }

  factory VibeConfigV4.fromPngBytes(
    String fileName,
    Uint8List imageBytes,
    double referenceStrength,
  ) {
    final chunks = png_extract.extractChunks(imageBytes);
    String? extractedVibeB64;

    for (final chunk in chunks) {
      if (chunk['name'] != 'iTXt') continue;
      final iTXtData = chunk['data'] as Uint8List;

      try {
        final keywordEndIndex = iTXtData.indexOf(0);
        if (keywordEndIndex == -1) continue;
        final keyword = utf8.decode(iTXtData.sublist(0, keywordEndIndex));
        if (keyword != _expectedITXtKeyword) continue;

        var currentIndex = keywordEndIndex + 1;
        if (currentIndex >= iTXtData.length) continue;
        final compressionFlag = iTXtData[currentIndex++];
        if (compressionFlag != 0) {
          throw FormatException(
            "Unsupported iTXt compression flag: $compressionFlag for keyword "
            "'$_expectedITXtKeyword'. Expected 0.",
          );
        }

        if (currentIndex >= iTXtData.length) continue;
        currentIndex += 1; // compression method

        final langTagEndIndex = iTXtData.indexOf(0, currentIndex);
        if (langTagEndIndex == -1) continue;
        currentIndex = langTagEndIndex + 1;

        final translatedKeywordEndIndex = iTXtData.indexOf(0, currentIndex);
        if (translatedKeywordEndIndex == -1) continue;
        currentIndex = translatedKeywordEndIndex + 1;

        if (currentIndex >= iTXtData.length) {
          throw const FormatException(
            "iTXt chunk for '$_expectedITXtKeyword' has an empty text field.",
          );
        }
        extractedVibeB64 = utf8.decode(iTXtData.sublist(currentIndex));
        break;
      } catch (e) {
        if (kDebugMode) {
          print('Error parsing a candidate iTXt chunk: $e');
        }
      }
    }

    if (extractedVibeB64 == null) {
      throw ArgumentError(
        "Required iTXt chunk with keyword '$_expectedITXtKeyword' not found "
        "in PNG image '$fileName'.",
      );
    }

    return VibeConfigV4(
      fileName: fileName,
      vibeB64: extractedVibeB64,
      referenceStrength: referenceStrength,
      imageBytes: imageBytes,
    );
  }

  factory VibeConfigV4.fromNaiV4VibeJson(
    String originalFileName,
    Map<String, dynamic> jsonData,
    double defaultReferenceStrength,
  ) {
    final name = jsonData['name'] as String? ?? originalFileName;

    final importInfo = jsonData['importInfo'] as Map<String, dynamic>?;
    var strength = defaultReferenceStrength;
    if (importInfo != null && importInfo['strength'] != null) {
      strength = _parseDouble(importInfo['strength'], defaultReferenceStrength);
    }
    final infoExtracted = importInfo == null
        ? 1.0
        : _parseDouble(
            importInfo['information_extracted'] ??
                importInfo['info_extracted'] ??
                importInfo['infoExtracted'] ??
                importInfo['informationExtracted'],
            1.0,
          );

    String? vibeB64String;
    final encodingsMap = jsonData['encodings'] as Map<String, dynamic>?;
    if (encodingsMap != null) {
      outerLoop:
      for (final modelKey in encodingsMap.keys) {
        final modelEncodings = encodingsMap[modelKey] as Map<String, dynamic>?;
        if (modelEncodings == null) continue;

        for (final typeKey in modelEncodings.keys) {
          final typeEncodingInfo =
              modelEncodings[typeKey] as Map<String, dynamic>?;
          final encodingValue = typeEncodingInfo?['encoding'];
          if (encodingValue is String && encodingValue.isNotEmpty) {
            vibeB64String = encodingValue;
            break outerLoop;
          }
        }
      }
    }

    if (vibeB64String == null) {
      throw ArgumentError(
        "Could not find a valid 'encoding' field in the .naiv4vibe JSON data "
        "for file '$originalFileName'.",
      );
    }

    return VibeConfigV4(
      fileName: name,
      vibeB64: vibeB64String,
      infoExtracted: infoExtracted.clamp(0.0, 1.0),
      referenceStrength: strength.clamp(0.0, 1.0),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'file_name': fileName,
      'vibe_b64': vibeB64,
      if (infoExtracted != 1.0) 'info_extracted': infoExtracted,
      'reference_strength': referenceStrength,
      if (sourceImagePath != null && sourceImagePath!.trim().isNotEmpty)
        'source_image_path': sourceImagePath,
      if ((sourceImagePath == null || sourceImagePath!.trim().isEmpty) &&
          legacyImageB64 != null &&
          legacyImageB64!.trim().isNotEmpty)
        'image_b64': legacyImageB64,
    };
  }

  factory VibeConfigV4.fromJson(Map<String, dynamic> json) {
    final imageB64 = json['image_b64'];

    final sourceImagePath = json['source_image_path'];
    return VibeConfigV4(
      fileName: json['file_name'] as String? ?? 'Unnamed vibe',
      vibeB64: json['vibe_b64'] as String? ?? '',
      infoExtracted: _parseDouble(
        json['info_extracted'] ?? json['infoExtracted'],
        1.0,
      ).clamp(0.0, 1.0),
      referenceStrength:
          _parseDouble(json['reference_strength'], 0.2).clamp(0.0, 1.0),
      sourceImagePath: sourceImagePath is String ? sourceImagePath : null,
      legacyImageB64: imageB64 is String &&
              imageB64.isNotEmpty &&
              imageB64.length <= _maxLegacyImageB64Length
          ? imageB64
          : null,
    );
  }
}
