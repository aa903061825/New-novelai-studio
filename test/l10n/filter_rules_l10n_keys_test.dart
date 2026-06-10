import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('filter rules library keys exist in both locales', () {
    final en = json.decode(
      File('assets/l10n/en.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final zh = json.decode(
      File('assets/l10n/zh-CN.json').readAsStringSync(),
    ) as Map<String, dynamic>;

    const requiredKeys = [
      'filter_rules_library_title',
      'filter_rules_delete_keywords',
      'filter_rules_strong_keywords',
      'filter_rules_replace_rules',
      'filter_rules_empty_block',
      'filter_rules_add_tag',
      'filter_rules_batch_add_tags',
      'filter_rules_add_replace_rule',
      'filter_rules_replace_source',
      'filter_rules_replace_target',
      'cancel',
      'save',
    ];

    for (final key in requiredKeys) {
      expect(en.containsKey(key), isTrue, reason: 'en.json missing $key');
      expect(zh.containsKey(key), isTrue, reason: 'zh-CN.json missing $key');
    }
  });
}
