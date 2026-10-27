import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/private_prompt_append.dart';

void main() {
  test('appends private text but redacts it from saved payloads', () async {
    final directory = await Directory.systemTemp.createTemp(
      'nai-private-prompt-append-',
    );
    addTearDown(() => directory.delete(recursive: true));

    const privateText = 'private-only-artist-token';
    final file = File('${directory.path}${Platform.pathSeparator}append.txt');
    await file.writeAsString(privateText);

    final append = await loadPrivatePromptAppend(explicitPath: file.path);
    expect(append.isActive, isTrue);
    expect(append.appendTo('base prompt'), 'base prompt,$privateText');

    final redacted = append.redactPayload(<String, dynamic>{
      'input': 'base prompt,$privateText',
      'parameters': <String, dynamic>{
        'v4_prompt': <String, dynamic>{
          'caption': <String, dynamic>{
            'base_caption': 'base prompt,$privateText',
          },
        },
      },
    });

    expect(jsonEncode(redacted), isNot(contains(privateText)));
    expect(redacted['input'], PrivatePromptAppend.redactedMarker);
    expect(
      (redacted['parameters'] as Map)['private_prompt_append'],
      <String, dynamic>{'applied': true, 'contents': 'omitted'},
    );
  });

  test('missing private file leaves prompts and payloads unchanged', () async {
    final append = await loadPrivatePromptAppend(
      explicitPath: '${Directory.systemTemp.path}${Platform.pathSeparator}'
          'nai-private-prompt-does-not-exist.txt',
    );

    expect(append.isActive, isFalse);
    expect(append.appendTo('base prompt'), 'base prompt');
    final payload = <String, dynamic>{'input': 'base prompt'};
    expect(append.redactPayload(payload), same(payload));
  });
}
