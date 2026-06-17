import 'dart:convert';
import 'dart:io';

import 'package:novel_studio/data/studio/models/production_task.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln(
      'Usage: dart run tool/compact_production_plans.dart '
      '<production/deterministic_plans directory>',
    );
    exitCode = 64;
    return;
  }

  final directory = Directory(args.first);
  if (!await directory.exists()) {
    stderr.writeln('Directory does not exist: ${directory.path}');
    exitCode = 66;
    return;
  }

  final files = await directory
      .list()
      .where((entry) => entry is File && entry.path.endsWith('.json'))
      .cast<File>()
      .toList();
  files.sort((left, right) => left.path.compareTo(right.path));

  final backup = Directory(
    '${directory.path}${Platform.pathSeparator}'
    'backup-${_timestamp()}-compact-production-plans',
  );
  var changed = 0;
  var beforeBytes = 0;
  var afterBytes = 0;
  var totalFiles = 0;
  final encoder = JsonEncoder.withIndent('  ');

  for (final file in files) {
    totalFiles += 1;
    final source = await file.readAsString();
    beforeBytes += source.length;
    final decoded = jsonDecode(source);
    final plan = ProductionPlan.fromJson(decoded);
    final compacted = plan.compactSharedPayloadParameters();
    final next = '${encoder.convert(compacted.toJson())}\n';
    afterBytes += next.length;
    if (next == source) {
      continue;
    }
    await backup.create(recursive: true);
    await file.copy('${backup.path}${Platform.pathSeparator}${_name(file)}');
    await file.writeAsString(next);
    changed += 1;
  }

  stdout.writeln(
    jsonEncode({
      'directory': directory.path,
      'files': totalFiles,
      'changed': changed,
      'beforeBytes': beforeBytes,
      'afterBytes': afterBytes,
      'savedBytes': beforeBytes - afterBytes,
      if (changed > 0) 'backup': backup.path,
    }),
  );
}

String _timestamp() {
  final now = DateTime.now().toUtc();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${now.year}${two(now.month)}${two(now.day)}-'
      '${two(now.hour)}${two(now.minute)}${two(now.second)}';
}

String _name(File file) => file.uri.pathSegments.last;
