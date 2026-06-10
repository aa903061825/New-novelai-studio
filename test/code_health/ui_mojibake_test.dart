import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('production UI strings do not keep known mojibake remnants', () {
    final libDir = Directory('lib');
    final offenders = <String, List<String>>{};
    const mojibakeFragments = [
      '瀹屾垚',
      '涓婅韩',
      '涓嬭韩',
      '淇濈暀',
      '璺熼殢',
      '瑕嗙洊',
      '灏氭湭',
      '宸蹭粠缂撳瓨',
      '锟斤拷',
      '\uFFFD',
    ];

    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      final source = entity.readAsStringSync();
      final matches = [
        for (final fragment in mojibakeFragments)
          if (source.contains(fragment)) fragment,
      ];
      if (matches.isNotEmpty) {
        offenders[entity.path] = matches;
      }
    }

    expect(offenders, isEmpty);
  });
}
