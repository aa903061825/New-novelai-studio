import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:image/image.dart' as image;

const _defaultQueuePath =
    'C:/Users/admin/Downloads/NAI_NEW/tool/asset-library-artist-chain-varsize-preview-queue.json';
const _defaultReportPath =
    'C:/Users/admin/AppData/Roaming/org.exception0x0194/nai3_autodraw/novel_studio/library/asset_artist_chain_varsize_visual_audit.json';
const _defaultContactSheetName = 'audit-artist-chain-flagged-visual-risk.png';
const previewRoot = 'E:/codeximage/nai-new/preview-images';

void main(List<String> args) {
  final options = _Options.parse(args);
  final queue = (jsonDecode(File(options.queuePath).readAsStringSync()) as List)
      .cast<Map<String, Object?>>();
  final rows = <Map<String, Object?>>[];

  for (final item in queue) {
    final fileName = (item['imageRef'] as String).split('/').last;
    final file = File('$previewRoot/$fileName');
    final decoded = image.decodeImage(file.readAsBytesSync());
    if (decoded == null) {
      throw StateError('Could not decode $fileName');
    }
    final metrics = _metrics(decoded);
    final promptFlags = _promptFlags(item['prompt'] as String? ?? '');
    final score = _riskScore(metrics, promptFlags);
    rows.add({
      'id': item['id'],
      'artistChainId': item['artistChainId'],
      'artistChainName': item['artistChainName'],
      'characterId': item['characterId'],
      'characterName': item['characterName'],
      'sizeKey': item['sizeKey'],
      'width': item['width'],
      'height': item['height'],
      'imageRef': item['imageRef'],
      'score': score,
      ...metrics,
      'promptFlags': promptFlags,
    });
  }

  rows.sort((a, b) => (b['score'] as num).compareTo(a['score'] as num));
  final flagged = rows.where((row) => (row['score'] as num) >= 55).toList();
  File(options.reportPath).writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'generatedAt': DateTime.now().toIso8601String(),
      'queuePath': options.queuePath,
      'queueCount': rows.length,
      'flaggedCount': flagged.length,
      'flagged': flagged,
      'top': rows.take(24).toList(),
    }),
  );
  final contactSheetPath = '$previewRoot/${options.contactSheetName}';
  _writeContactSheet(flagged.take(24).toList(), contactSheetPath);
  stdout.writeln(
    const JsonEncoder.withIndent('  ').convert({
      'flaggedCount': flagged.length,
      'top': rows.take(12).map((row) {
        return {
          'score': row['score'],
          'id': row['id'],
          'chain': row['artistChainId'],
          'size': row['sizeKey'],
          'meanSaturation': row['meanSaturation'],
          'hotColorFraction': row['hotColorFraction'],
          'brightFraction': row['brightFraction'],
          'promptFlags': row['promptFlags'],
        };
      }).toList(),
      'reportPath': options.reportPath,
      'contactSheet': contactSheetPath,
    }),
  );
}

Map<String, Object?> _metrics(image.Image source) {
  final resized = image.copyResize(source, width: min(source.width, 320));
  final saturations = <double>[];
  var bright = 0;
  var dark = 0;
  var hotColor = 0;
  var clipped = 0;
  var total = 0;

  for (final pixel in resized) {
    final r = pixel.rNormalized;
    final g = pixel.gNormalized;
    final b = pixel.bNormalized;
    final maxRgb = max(r, max(g, b));
    final minRgb = min(r, min(g, b));
    final chroma = maxRgb - minRgb;
    final saturation = maxRgb == 0 ? 0.0 : chroma / maxRgb;
    saturations.add(saturation);
    if (maxRgb > 0.95) bright++;
    if (maxRgb < 0.08) dark++;
    if (saturation > 0.82 && maxRgb > 0.72) hotColor++;
    if ((r > 0.985 || g > 0.985 || b > 0.985) && saturation > 0.7) clipped++;
    total++;
  }

  saturations.sort();
  double pct(double value) => _round(value * 100);
  return {
    'meanSaturation': _round(
      saturations.reduce((a, b) => a + b) / saturations.length,
    ),
    'p95Saturation': _round(saturations[(saturations.length * 0.95).floor()]),
    'hotColorFraction': pct(hotColor / total),
    'brightFraction': pct(bright / total),
    'darkFraction': pct(dark / total),
    'clippedColorFraction': pct(clipped / total),
  };
}

List<String> _promptFlags(String prompt) {
  final flags = <String>[];
  final checks = {
    'official_art_stack': RegExp(
      r'official art|official_style|masterpiece|extremely detailed|8k|cg unity',
      caseSensitive: false,
    ),
    'skin_shine_stack': RegExp(
      r'glossy skin|soft skin|subsurface scattering|humid skin|shiny skin|deep skin|detailed skin texture',
      caseSensitive: false,
    ),
    'lighting_stack': RegExp(
      r'beautiful detailed glow|best illumination|cinematic lighting|detailed lighting|neon reflections|rim lighting',
      caseSensitive: false,
    ),
    'motion_lines': RegExp(
      r'motion lines|speed lines',
      caseSensitive: false,
    ),
    'chibi_or_sd': RegExp(r'\bchibi\b|\bsd\b', caseSensitive: false),
  };
  for (final entry in checks.entries) {
    if (entry.value.hasMatch(prompt)) flags.add(entry.key);
  }
  return flags;
}

double _riskScore(Map<String, Object?> metrics, List<String> promptFlags) {
  final meanSat = metrics['meanSaturation'] as double;
  final p95Sat = metrics['p95Saturation'] as double;
  final hot = metrics['hotColorFraction'] as double;
  final bright = metrics['brightFraction'] as double;
  final clipped = metrics['clippedColorFraction'] as double;
  var score = 0.0;
  score += max(0, meanSat - 0.43) * 80;
  score += max(0, p95Sat - 0.88) * 80;
  score += hot * 1.8;
  score += max(0, bright - 18) * 1.2;
  score += clipped * 2.0;
  score += promptFlags.length * 8;
  return _round(score);
}

double _round(double value) => (value * 1000).round() / 1000;

void _writeContactSheet(List<Map<String, Object?>> items, String outputPath) {
  const thumb = 180;
  const pad = 12;
  const cols = 6;
  final rows = max(1, (items.length / cols).ceil());
  final sheet = image.Image(
    width: pad + cols * (thumb + pad),
    height: pad + rows * (thumb + pad),
  );
  image.fill(sheet, color: image.ColorRgb8(250, 250, 248));

  for (var i = 0; i < items.length; i++) {
    final fileName = (items[i]['imageRef'] as String).split('/').last;
    final decoded = image.decodeImage(
      File('$previewRoot/$fileName').readAsBytesSync(),
    );
    if (decoded == null) continue;
    final square = image.copyResizeCropSquare(decoded, size: thumb);
    final col = i % cols;
    final row = i ~/ cols;
    image.compositeImage(
      sheet,
      square,
      dstX: pad + col * (thumb + pad),
      dstY: pad + row * (thumb + pad),
    );
  }

  File(outputPath)
    ..parent.createSync(recursive: true)
    ..writeAsBytesSync(image.encodePng(sheet));
}

class _Options {
  final String queuePath;
  final String reportPath;
  final String contactSheetName;

  const _Options({
    required this.queuePath,
    required this.reportPath,
    required this.contactSheetName,
  });

  factory _Options.parse(List<String> args) {
    var queuePath = _defaultQueuePath;
    var reportPath = _defaultReportPath;
    var contactSheetName = _defaultContactSheetName;
    for (final arg in args) {
      if (arg.startsWith('--queue=')) {
        queuePath = arg.substring('--queue='.length);
      } else if (arg.startsWith('--report=')) {
        reportPath = arg.substring('--report='.length);
      } else if (arg.startsWith('--sheet=')) {
        contactSheetName = arg.substring('--sheet='.length);
      }
    }
    return _Options(
      queuePath: queuePath,
      reportPath: reportPath,
      contactSheetName: contactSheetName,
    );
  }
}
