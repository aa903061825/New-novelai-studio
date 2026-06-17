import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:novel_studio/core/constants/parameters.dart';
import 'package:novel_studio/data/models/character_config.dart';
import 'package:novel_studio/data/models/payload_config.dart';
import 'package:novel_studio/data/models/prompt_config.dart';
import 'package:novel_studio/data/services/image_service.dart';
import 'package:novel_studio/data/studio/tools/nai_metadata_parser.dart';
import 'package:png_chunks_extract/png_chunks_extract.dart' as png_extract;

class WorkbenchMetadataImportSummary {
  final String fileName;
  final int fieldsLoaded;
  final int charactersLoaded;
  final bool usedStructuredMetadata;

  const WorkbenchMetadataImportSummary({
    required this.fileName,
    required this.fieldsLoaded,
    required this.charactersLoaded,
    required this.usedStructuredMetadata,
  });

  int get totalLoaded => fieldsLoaded + charactersLoaded;
}

class WorkbenchMetadataImportService {
  final ImageService imageService;

  WorkbenchMetadataImportService({
    ImageService? imageService,
  }) : imageService = imageService ?? ImageService();

  Future<WorkbenchMetadataImportSummary> importBytes(
    PayloadConfig target,
    String fileName,
    Uint8List bytes,
  ) async {
    final parsed = await parseBytes(fileName, bytes);
    return applyParsed(target, fileName, parsed);
  }

  Future<NaiMetadataParseResult> parseBytes(
    String fileName,
    Uint8List bytes,
  ) async {
    if (fileName.toLowerCase().endsWith('.png')) {
      return _parsePngBytes(bytes);
    }
    return NaiMetadataParser.parseString(utf8.decode(bytes));
  }

  Future<NaiMetadataParseResult> parseFile(File file) async {
    final fileName = _fileName(file);
    if (fileName.toLowerCase().endsWith('.png')) {
      final parsed = await _parsePngTextMetadataFile(file);
      if (parsed != null) {
        return parsed;
      }
    }
    return parseBytes(fileName, await file.readAsBytes());
  }

  Future<NaiMetadataParseResult> _parsePngBytes(Uint8List bytes) async {
    final chunkMetadata = _extractPngTextChunks(bytes);
    if (chunkMetadata.isNotEmpty) {
      final parsed = NaiMetadataParser.parseMap(chunkMetadata);
      if (parsed.hasStructuredMetadata) {
        return parsed;
      }
    }

    final stealthMetadata = _extractStealthPngMetadata(bytes);
    if (stealthMetadata != null && stealthMetadata.trim().isNotEmpty) {
      return NaiMetadataParser.parseString(stealthMetadata);
    }

    final image = img.decodeImage(bytes);
    if (image == null) {
      throw const FormatException('Selected PNG could not be decoded.');
    }
    final decodedStealthMetadata = await imageService.extractMetadata(image);
    if (decodedStealthMetadata == null ||
        decodedStealthMetadata.trim().isEmpty) {
      throw const FormatException('No NovelAI metadata found in PNG.');
    }
    return NaiMetadataParser.parseString(decodedStealthMetadata);
  }

  Future<NaiMetadataParseResult?> _parsePngTextMetadataFile(File file) async {
    RandomAccessFile? reader;
    try {
      final fileLength = await file.length();
      reader = await file.open();
      final signature = await reader.read(8);
      if (signature.length < 8 || !_hasPngSignature(signature)) {
        return null;
      }

      final metadata = <String, dynamic>{};
      while (await reader.position() + 8 <= fileLength) {
        final header = await reader.read(8);
        if (header.length < 8) return null;
        final length = _uint32At(header, 0);
        final type = ascii.decode(header.sublist(4, 8));
        if (type == 'IDAT') {
          final parsed = _structuredPngTextMetadataResult(metadata);
          if (parsed != null &&
              _canStopAfterPngTextMetadata(parsed, metadata)) {
            return parsed;
          }
        }
        final dataStart = await reader.position();
        final dataEnd = dataStart + length;
        final nextOffset = dataEnd + 4;
        if (dataEnd > fileLength || nextOffset > fileLength) {
          return null;
        }

        if (type == 'tEXt' || type == 'iTXt' || type == 'zTXt') {
          final data = await reader.read(length);
          if (data.length < length) return null;
          final entry = switch (type) {
            'tEXt' => _parseTextChunk(data),
            'iTXt' => _parseInternationalTextChunk(data),
            'zTXt' => _parseCompressedTextChunk(data),
            _ => null,
          };
          if (entry != null) {
            metadata[entry.key] = entry.value;
            final parsed = _structuredPngTextMetadataResult(metadata);
            if (parsed != null &&
                _canStopAfterPngTextMetadata(parsed, metadata)) {
              return parsed;
            }
          }
          await reader.setPosition(nextOffset);
        } else {
          await reader.setPosition(nextOffset);
        }

        if (type == 'IEND') {
          return _structuredPngTextMetadataResult(metadata);
        }
      }
    } catch (_) {
      return null;
    } finally {
      await reader?.close();
    }
    return null;
  }

  NaiMetadataParseResult? _structuredPngTextMetadataResult(
    Map<String, dynamic> metadata,
  ) {
    if (metadata.isEmpty) return null;
    final parsed = NaiMetadataParser.parseMap(metadata);
    return parsed.hasStructuredMetadata ? parsed : null;
  }

  bool _canStopAfterPngTextMetadata(
    NaiMetadataParseResult parsed,
    Map<String, dynamic> metadata,
  ) {
    return metadata.containsKey('Comment') ||
        metadata.containsKey('prompt') ||
        parsed.parameters.isNotEmpty ||
        parsed.negativePrompt?.trim().isNotEmpty == true ||
        parsed.charCaptions.isNotEmpty ||
        parsed.negativeCharCaptions.isNotEmpty ||
        parsed.coords.isNotEmpty ||
        parsed.width != null ||
        parsed.height != null;
  }

  WorkbenchMetadataImportSummary applyParsed(
    PayloadConfig target,
    String fileName,
    NaiMetadataParseResult parsed,
  ) {
    if (!parsed.hasStructuredMetadata && parsed.prompt == null) {
      throw const FormatException('No NovelAI metadata found.');
    }

    var fieldsLoaded = 0;
    final prompt = parsed.prompt?.trim();
    if (prompt != null && prompt.isNotEmpty) {
      target.overridePrompt = prompt;
      target.useOverridePrompt = true;
      fieldsLoaded++;
    }

    fieldsLoaded += target.paramConfig.loadJson(parsed.parameters);
    if (parsed.width != null && parsed.height != null) {
      fieldsLoaded += target.paramConfig.loadJson({
        'width': parsed.width,
        'height': parsed.height,
      });
    }

    final negativePrompt = parsed.negativePrompt?.trim();
    if (negativePrompt != null && negativePrompt.isNotEmpty) {
      target.paramConfig.negativePrompt = negativePrompt;
      fieldsLoaded++;
    }

    final model = sourceToModel[parsed.source];
    if (model != null) {
      target.paramConfig.model = model;
      fieldsLoaded++;
    }

    final characters = _charactersFrom(parsed);
    if (characters.isNotEmpty) {
      target.characterConfigList = characters;
      target.useCharacterPromptWithOverride = true;
    }

    return WorkbenchMetadataImportSummary(
      fileName: fileName,
      fieldsLoaded: fieldsLoaded,
      charactersLoaded: characters.length,
      usedStructuredMetadata: parsed.hasStructuredMetadata,
    );
  }

  Map<String, dynamic> _extractPngTextChunks(Uint8List bytes) {
    final chunks = png_extract.extractChunks(bytes);
    final metadata = <String, dynamic>{};

    for (final chunk in chunks) {
      final name = chunk['name'];
      final data = chunk['data'];
      if (data is! Uint8List) continue;
      switch (name) {
        case 'tEXt':
          final entry = _parseTextChunk(data);
          if (entry != null) metadata[entry.key] = entry.value;
          break;
        case 'iTXt':
          final entry = _parseInternationalTextChunk(data);
          if (entry != null) metadata[entry.key] = entry.value;
          break;
        case 'zTXt':
          final entry = _parseCompressedTextChunk(data);
          if (entry != null) metadata[entry.key] = entry.value;
          break;
      }
    }

    return metadata;
  }

  MapEntry<String, String>? _parseTextChunk(Uint8List data) {
    final separator = data.indexOf(0);
    if (separator <= 0) return null;
    return MapEntry(
      utf8.decode(data.sublist(0, separator), allowMalformed: true),
      utf8.decode(data.sublist(separator + 1), allowMalformed: true),
    );
  }

  MapEntry<String, String>? _parseCompressedTextChunk(Uint8List data) {
    final separator = data.indexOf(0);
    if (separator <= 0 || separator + 2 > data.length) return null;
    final compressionMethod = data[separator + 1];
    if (compressionMethod != 0) return null;
    final inflated = ZLibCodec().decode(data.sublist(separator + 2));
    return MapEntry(
      utf8.decode(data.sublist(0, separator), allowMalformed: true),
      utf8.decode(inflated, allowMalformed: true),
    );
  }

  MapEntry<String, String>? _parseInternationalTextChunk(Uint8List data) {
    final keywordEnd = data.indexOf(0);
    if (keywordEnd <= 0 || keywordEnd + 5 > data.length) return null;
    final keyword = utf8.decode(
      data.sublist(0, keywordEnd),
      allowMalformed: true,
    );
    var cursor = keywordEnd + 1;
    final compressionFlag = data[cursor++];
    final compressionMethod = data[cursor++];
    if (compressionFlag != 0 && compressionMethod != 0) return null;

    final languageEnd = data.indexOf(0, cursor);
    if (languageEnd < 0) return null;
    cursor = languageEnd + 1;
    final translatedEnd = data.indexOf(0, cursor);
    if (translatedEnd < 0) return null;
    cursor = translatedEnd + 1;

    final textBytes = data.sublist(cursor);
    final text = compressionFlag == 0
        ? utf8.decode(textBytes, allowMalformed: true)
        : utf8.decode(ZLibCodec().decode(textBytes), allowMalformed: true);
    return MapEntry(keyword, text);
  }

  String? _extractStealthPngMetadata(Uint8List bytes) {
    try {
      final alpha = _extractPngAlphaBytes(bytes);
      if (alpha == null || alpha.isEmpty) {
        return null;
      }
      final reader =
          _AlphaStealthBitReader(alpha.bytes, alpha.width, alpha.height);
      final headerBytes = reader.readBytes('stealth_pngcomp'.length);
      final header = utf8.decode(headerBytes, allowMalformed: true);
      if (header != 'stealth_pngcomp' && header != 'stealth_pnginfo') {
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
      final data = reader.readBytes(dataLength);
      if (data.length < dataLength) {
        return null;
      }
      final decodedData =
          header == 'stealth_pngcomp' ? GZipCodec().decode(data) : data;
      return utf8.decode(decodedData, allowMalformed: true);
    } catch (_) {
      return null;
    }
  }

  _PngAlphaBytes? _extractPngAlphaBytes(Uint8List bytes) {
    if (bytes.length < 33 || !_hasPngSignature(bytes)) {
      return null;
    }

    var offset = 8;
    int? width;
    int? height;
    int? bitDepth;
    int? colorType;
    int? interlace;
    final idat = BytesBuilder(copy: false);

    while (offset + 12 <= bytes.length) {
      final length = _uint32At(bytes, offset);
      final typeStart = offset + 4;
      final dataStart = offset + 8;
      final dataEnd = dataStart + length;
      final nextOffset = dataEnd + 4;
      if (length < 0 || dataEnd > bytes.length || nextOffset > bytes.length) {
        return null;
      }
      final type = ascii.decode(bytes.sublist(typeStart, typeStart + 4));
      final data = bytes.sublist(dataStart, dataEnd);
      switch (type) {
        case 'IHDR':
          if (data.length < 13) return null;
          width = _uint32At(data, 0);
          height = _uint32At(data, 4);
          bitDepth = data[8];
          colorType = data[9];
          interlace = data[12];
          break;
        case 'IDAT':
          idat.add(data);
          break;
        case 'IEND':
          offset = bytes.length;
          continue;
      }
      offset = nextOffset;
    }

    if (width == null ||
        height == null ||
        width <= 0 ||
        height <= 0 ||
        bitDepth != 8 ||
        interlace != 0 ||
        (colorType != 4 && colorType != 6)) {
      return null;
    }

    final channelCount = colorType == 6 ? 4 : 2;
    final rowLength = width * channelCount;
    final inflated = ZLibCodec().decode(idat.toBytes());
    final expectedMinLength = (rowLength + 1) * height;
    if (inflated.length < expectedMinLength) {
      return null;
    }

    final alphaBytes = Uint8List(width * height);
    var cursor = 0;
    var previous = Uint8List(rowLength);
    for (var y = 0; y < height; y += 1) {
      final filter = inflated[cursor++];
      final row =
          Uint8List.fromList(inflated.sublist(cursor, cursor + rowLength));
      cursor += rowLength;
      final reconstructed = _unfilterPngScanline(
        filter: filter,
        row: row,
        previous: previous,
        bytesPerPixel: channelCount,
      );
      final alphaOffset = colorType == 6 ? 3 : 1;
      for (var x = 0; x < width; x += 1) {
        alphaBytes[y * width + x] =
            reconstructed[x * channelCount + alphaOffset];
      }
      previous = reconstructed;
    }
    return _PngAlphaBytes(width: width, height: height, bytes: alphaBytes);
  }

  Uint8List _unfilterPngScanline({
    required int filter,
    required Uint8List row,
    required Uint8List previous,
    required int bytesPerPixel,
  }) {
    final result = Uint8List(row.length);
    for (var index = 0; index < row.length; index += 1) {
      final left = index >= bytesPerPixel ? result[index - bytesPerPixel] : 0;
      final up = previous[index];
      final upLeft =
          index >= bytesPerPixel ? previous[index - bytesPerPixel] : 0;
      final predictor = switch (filter) {
        0 => 0,
        1 => left,
        2 => up,
        3 => (left + up) >> 1,
        4 => _paethPredictor(left, up, upLeft),
        _ => throw const FormatException('Unsupported PNG scanline filter.'),
      };
      result[index] = (row[index] + predictor) & 0xff;
    }
    return result;
  }

  int _paethPredictor(int left, int up, int upLeft) {
    final prediction = left + up - upLeft;
    final leftDistance = (prediction - left).abs();
    final upDistance = (prediction - up).abs();
    final upLeftDistance = (prediction - upLeft).abs();
    if (leftDistance <= upDistance && leftDistance <= upLeftDistance) {
      return left;
    }
    return upDistance <= upLeftDistance ? up : upLeft;
  }

  bool _hasPngSignature(Uint8List bytes) {
    const signature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
    for (var index = 0; index < signature.length; index += 1) {
      if (bytes[index] != signature[index]) return false;
    }
    return true;
  }

  String _fileName(File file) {
    final segments = file.uri.pathSegments;
    if (segments.isEmpty) return file.path;
    return Uri.decodeComponent(segments.last);
  }

  int _uint32At(Uint8List bytes, int offset) {
    return ByteData.sublistView(bytes, offset, offset + 4).getUint32(0);
  }

  List<CharacterConfig> _charactersFrom(NaiMetadataParseResult parsed) {
    final characters = <CharacterConfig>[];
    for (var index = 0; index < parsed.charCaptions.length; index++) {
      final caption = parsed.charCaptions[index].trim();
      if (caption.isEmpty) continue;
      final coord = index < parsed.coords.length ? parsed.coords[index] : null;
      characters.add(
        CharacterConfig(
          positions: [
            if (coord != null) _positionFromCoord(coord),
          ],
          positivePromptConfig: PromptConfig(
            strs: [caption],
            prompts: const [],
          ),
          negativePrompt: index < parsed.negativeCharCaptions.length
              ? parsed.negativeCharCaptions[index]
              : '',
          enabled: true,
        ),
      );
    }
    return characters;
  }

  Point<int> _positionFromCoord(Map<String, num> coord) {
    return Point(
      _nearestPositionIndex(coord['x']),
      _nearestPositionIndex(coord['y']),
    );
  }

  int _nearestPositionIndex(num? value) {
    if (value == null) return 3;
    var nearest = 3;
    var nearestDistance = double.infinity;
    for (final entry in doubleMapping.entries) {
      if (entry.key == 0) continue;
      final distance = (entry.value - value.toDouble()).abs();
      if (distance < nearestDistance) {
        nearest = entry.key;
        nearestDistance = distance;
      }
    }
    return nearest;
  }
}

class _PngAlphaBytes {
  final int width;
  final int height;
  final Uint8List bytes;

  const _PngAlphaBytes({
    required this.width,
    required this.height,
    required this.bytes,
  });

  bool get isEmpty => bytes.isEmpty;
}

class _AlphaStealthBitReader {
  final Uint8List alphaBytes;
  final int width;
  final int height;
  var _x = 0;
  var _y = 0;
  var _bitsRead = 0;

  _AlphaStealthBitReader(this.alphaBytes, this.width, this.height);

  int get _totalBits => width * height;

  int get remainingByteCapacity => (_totalBits - _bitsRead) ~/ 8;

  List<int> readBytes(int length) {
    final bytes = <int>[];
    for (var index = 0; index < length; index += 1) {
      var value = 0;
      for (var bit = 0; bit < 8; bit += 1) {
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
    if (_x >= width) {
      return null;
    }
    final bit = alphaBytes[_y * width + _x] & 1;
    _bitsRead += 1;
    _y += 1;
    if (_y >= height) {
      _y = 0;
      _x += 1;
    }
    return bit;
  }
}
