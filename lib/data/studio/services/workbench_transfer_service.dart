import 'dart:convert';

import 'package:nai_casrand/data/models/payload_config.dart';
import 'package:nai_casrand/data/studio/models/workbench_document.dart';

class WorkbenchTransferService {
  String exportText(PayloadConfig config) {
    const encoder = JsonEncoder.withIndent('  ');
    final document = WorkbenchDocument.fromPayloadConfig(config);
    return '${encoder.convert(document.toJson())}\n';
  }

  WorkbenchDocument decode(String text) {
    final decoded = jsonDecode(text);
    if (decoded is! Map) {
      throw const FormatException('Workbench transfer must be a JSON object.');
    }

    final json = decoded.cast<String, dynamic>();
    if (json['kind'] == WorkbenchDocument.kind) {
      return WorkbenchDocument.fromJson(json);
    }
    if (json.containsKey('prompt_config')) {
      return WorkbenchDocument.fromPayloadJson(json);
    }
    throw const FormatException('Unsupported workbench transfer file.');
  }

  void importText(PayloadConfig target, String text) {
    decode(text).applyTo(target);
  }
}
