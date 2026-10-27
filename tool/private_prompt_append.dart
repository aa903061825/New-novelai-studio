import 'dart:convert';
import 'dart:io';

final _privatePromptAppendRelativePath =
    'org.exception0x0194${Platform.pathSeparator}'
    'nai3_autodraw${Platform.pathSeparator}'
    'novel_studio${Platform.pathSeparator}'
    'assets${Platform.pathSeparator}'
    'references${Platform.pathSeparator}'
    'artist-chain-v5-previews${Platform.pathSeparator}'
    '_prompt_append_private.txt';

String defaultPrivatePromptAppendPath() {
  final appData = Platform.environment['APPDATA']?.trim();
  if (appData != null && appData.isNotEmpty) {
    return '$appData${Platform.pathSeparator}$_privatePromptAppendRelativePath';
  }
  return r'C:\Users\admin\AppData\Roaming\org.exception0x0194\nai3_autodraw\novel_studio\assets\references\artist-chain-v5-previews\_prompt_append_private.txt';
}

Future<PrivatePromptAppend> loadPrivatePromptAppend({
  String? explicitPath,
}) async {
  final candidate = explicitPath?.trim();
  final path = candidate == null || candidate.isEmpty
      ? defaultPrivatePromptAppendPath()
      : candidate;
  final file = File(path);
  if (!await file.exists()) {
    return PrivatePromptAppend(path: path, text: '');
  }
  final contents = await file.readAsString(encoding: utf8);
  return PrivatePromptAppend(
    path: path,
    text: _stripUtf8Bom(contents).trim(),
  );
}

String _stripUtf8Bom(String value) {
  return value.startsWith('\uFEFF') ? value.substring(1) : value;
}

class PrivatePromptAppend {
  static const redactedMarker = '[private prompt append omitted]';

  final String path;
  final String _text;

  const PrivatePromptAppend({
    required this.path,
    required String text,
  }) : _text = text;

  bool get isActive => _text.isNotEmpty;

  String appendTo(String prompt) {
    if (!isActive) return prompt;
    final base = prompt.trim();
    return base.isEmpty ? _text : '$base,$_text';
  }

  Map<String, dynamic> redactPayload(Map<String, dynamic> payload) {
    if (!isActive) return payload;
    final decoded = jsonDecode(jsonEncode(payload));
    if (decoded is! Map) {
      return <String, dynamic>{
        'private_prompt_append': <String, dynamic>{
          'applied': true,
          'contents': 'omitted',
        },
      };
    }

    final redacted = decoded.cast<String, dynamic>();
    redacted['input'] = redactedMarker;
    final parameters = redacted['parameters'];
    if (parameters is Map) {
      final structuredPrompt = parameters['v4_prompt'];
      if (structuredPrompt is Map) {
        final caption = structuredPrompt['caption'];
        if (caption is Map) {
          caption['base_caption'] = redactedMarker;
        }
      }
      parameters['private_prompt_append'] = <String, dynamic>{
        'applied': true,
        'contents': 'omitted',
      };
    }
    redacted['private_prompt_append'] = <String, dynamic>{
      'applied': true,
      'contents': 'omitted',
    };
    return redacted;
  }
}
