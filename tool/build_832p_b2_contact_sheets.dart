import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as image;

const queuePath =
    'C:/Users/admin/Downloads/NAI_NEW/tool/asset-library-requested-character-previews-832p-b2.json';
const previewRoot = 'E:/codeximage/nai-new/preview-images';

void main() {
  final queue = (jsonDecode(File(queuePath).readAsStringSync()) as List)
      .cast<Map<String, Object?>>();
  _writeSheet(
    queue.where((item) => item['type'] == 'character').toList(),
    '$previewRoot/audit-character-previews-832p-b2.png',
  );
  _writeSheet(
    queue.where((item) => item['type'] == 'outfit').toList(),
    '$previewRoot/audit-outfit-previews-832p-b2.png',
  );
}

void _writeSheet(List<Map<String, Object?>> items, String outputPath) {
  const thumbW = 156;
  const thumbH = 228;
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
    final thumb = image.copyResize(source, width: thumbW, height: thumbH);
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
