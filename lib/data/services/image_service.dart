import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:archive/archive.dart';

class ImageService {
  String encodePreviewThumbnailB64(
    Uint8List imageBytes, {
    int maxSide = 320,
  }) {
    final sourceImage = img.decodeImage(imageBytes);
    if (sourceImage == null) {
      throw const FormatException('Failed to decode preview image.');
    }

    final longestSide = math.max(sourceImage.width, sourceImage.height);
    final scale = longestSide <= maxSide ? 1.0 : maxSide / longestSide;
    final targetWidth = math.max(1, (sourceImage.width * scale).round());
    final targetHeight = math.max(1, (sourceImage.height * scale).round());
    final thumbnail = img.copyResize(
      sourceImage,
      width: targetWidth,
      height: targetHeight,
      interpolation: img.Interpolation.average,
    );

    return base64Encode(img.encodePng(thumbnail));
  }

  /// Process response bytes and return image bytes.
  Uint8List processResponse(Uint8List zippedResponseBytes) {
    try {
      var archive = ZipDecoder().decodeBytes(zippedResponseBytes);
      for (final file in archive) {
        if (file.name != 'image_0.png') continue;
        return file.content;
      }
      throw Exception('Image file image_0.png not found in archive.');
    } catch (e) {
      final bytes = zippedResponseBytes;
      throw Exception(
        'Error unpacking response: ${e.toString()};\nResponse data: '
        "${bytes.length < 1000 ? utf8.decode(bytes) : '${bytes.length} bytes'}",
      );
    }
  }

  Future<Uint8List> embedMetadata(
    Uint8List imageBytes,
    String metadataString,
  ) async {
    final image = img.decodePng(imageBytes);
    if (image == null) {
      throw Exception('Image decode failed while embedding metadata.');
    }
    final codec = GZipCodec();
    final magicBytes = utf8.encode('stealth_pngcomp');
    final encodedData = codec.encode(utf8.encode(metadataString));
    final bitLength = encodedData.length * 8;
    final bitLengthInBytes = ByteData(4);
    bitLengthInBytes.setInt32(0, bitLength);
    final dataToEmbed = [
      ...magicBytes,
      ...bitLengthInBytes.buffer.asUint8List(),
      ...encodedData,
    ];

    var bitIndex = 0;
    for (var x = 0; x < image.width; x++) {
      for (var y = 0; y < image.height; y++) {
        final byteIndex = (bitIndex / 8).floor();
        if (byteIndex >= dataToEmbed.length) break;
        final bit = (dataToEmbed[byteIndex] >> (7 - bitIndex % 8)) & 1;
        final pixel = image.getPixel(x, y);
        pixel.a = 254 | bit;
        image.setPixel(x, y, pixel);
        bitIndex++;
      }
    }
    return img.encodePng(image);
  }

  Future<String?> extractMetadata(img.Image image) async {
    final magicBytes = utf8.encode('stealth_pngcomp');
    final reader = _AlphaBitReader(image);
    final headerBytes = reader.readBytes(magicBytes.length);
    if (!listEquals(headerBytes, magicBytes)) {
      return null;
    }

    final bitLengthBytes = reader.readBytes(4);
    if (bitLengthBytes.length < 4) {
      return null;
    }

    final bitLength =
        ByteData.sublistView(Uint8List.fromList(bitLengthBytes)).getInt32(0);
    if (bitLength <= 0) {
      return null;
    }

    final dataLength = (bitLength / 8).ceil();
    if (dataLength > reader.remainingByteCapacity) {
      return null;
    }

    final compressedData = reader.readBytes(dataLength);
    if (compressedData.length < dataLength) {
      return null;
    }

    final codec = GZipCodec();
    final decodedData = codec.decode(Uint8List.fromList(compressedData));
    return utf8.decode(decodedData);
  }
}

class _AlphaBitReader {
  final img.Image image;
  var _x = 0;
  var _y = 0;
  var _bitsRead = 0;

  _AlphaBitReader(this.image);

  int get _totalBits => image.width * image.height;

  int get remainingByteCapacity => (_totalBits - _bitsRead) ~/ 8;

  List<int> readBytes(int length) {
    final bytes = <int>[];
    for (var i = 0; i < length; i++) {
      var value = 0;
      for (var bit = 0; bit < 8; bit++) {
        final nextBit = _readBit();
        if (nextBit == null) {
          return bytes;
        }
        value = (value << 1) | nextBit;
      }
      bytes.add(value);
    }
    return bytes;
  }

  int? _readBit() {
    if (_x >= image.width) {
      return null;
    }
    final pixel = image.getPixel(_x, _y);
    final bit = pixel.a.toInt() & 1;
    _bitsRead++;
    _y++;
    if (_y >= image.height) {
      _y = 0;
      _x++;
    }
    return bit;
  }
}
