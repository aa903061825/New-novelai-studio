import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as image;

const _defaultQueuePath =
    'C:/Users/admin/Downloads/NAI_NEW/tool/asset-library-artist-chain-varsize-preview-queue.json';
const _defaultPrefix = 'audit-artist-chain';
const previewRoot = 'E:/codeximage/nai-new/preview-images';

void main(List<String> args) {
  final options = _Options.parse(args);
  final queue = (jsonDecode(File(options.queuePath).readAsStringSync()) as List)
      .cast<Map<String, Object?>>();
  for (final entry in [
    ('portrait-832x1216', '${options.prefix}-portrait-832x1216.png'),
    ('square-1024x1024', '${options.prefix}-square-1024x1024.png'),
    ('wide-1216x832', '${options.prefix}-wide-1216x832.png'),
  ]) {
    final items = queue.where((item) => item['sizeKey'] == entry.$1).toList();
    _writeSheet(items, '$previewRoot/${entry.$2}');
  }
}

void _writeSheet(List<Map<String, Object?>> items, String outputPath) {
  const thumbW = 164;
  const thumbH = 164;
  const pad = 12;
  const cols = 8;
  final rows = (items.length / cols).ceil();
  final sheet = image.Image(
    width: pad + cols * (thumbW + pad),
    height: pad + rows * (thumbH + pad),
  );
  image.fill(sheet, color: image.ColorRgb8(250, 250, 248));

  for (var i = 0; i < items.length; i++) {
    final item = items[i];
    final imageRef = item['imageRef'] as String;
    final fileName = imageRef.split('/').last;
    final source = image.decodeImage(
      File('$previewRoot/$fileName').readAsBytesSync(),
    );
    if (source == null) {
      throw StateError('Could not decode $fileName');
    }
    final thumb = image.copyResizeCropSquare(source, size: thumbW);
    final col = i % cols;
    final row = i ~/ cols;
    image.compositeImage(
      sheet,
      thumb,
      dstX: pad + col * (thumbW + pad),
      dstY: pad + row * (thumbH + pad),
    );
  }

  final output = File(outputPath)..parent.createSync(recursive: true);
  output.writeAsBytesSync(image.encodePng(sheet));
  stdout.writeln('${items.length} -> $outputPath');
}

class _Options {
  final String queuePath;
  final String prefix;

  const _Options({
    required this.queuePath,
    required this.prefix,
  });

  factory _Options.parse(List<String> args) {
    var queuePath = _defaultQueuePath;
    var prefix = _defaultPrefix;
    for (final arg in args) {
      if (arg.startsWith('--queue=')) {
        queuePath = arg.substring('--queue='.length);
      } else if (arg.startsWith('--prefix=')) {
        prefix = arg.substring('--prefix='.length);
      }
    }
    return _Options(queuePath: queuePath, prefix: prefix);
  }
}
