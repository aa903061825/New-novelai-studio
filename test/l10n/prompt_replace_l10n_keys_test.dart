import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('prompt replacement dashboard keys exist in both locales', () {
    final en = json.decode(
      File('assets/l10n/en.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final zh = json.decode(
      File('assets/l10n/zh-CN.json').readAsStringSync(),
    ) as Map<String, dynamic>;

    const requiredKeys = [
      'prompt_dashboard_title',
      'prompt_dashboard_hint',
      'prompt_dashboard_base_title',
      'prompt_dashboard_character_title',
      'prompt_dashboard_character_subtitle',
      'prompt_dashboard_replace_title',
      'prompt_dashboard_replace_subtitle',
      'prompt_dashboard_saved_title',
      'prompt_dashboard_saved_subtitle',
      'prompt_replace_rules_title',
      'prompt_replace_rules_stats',
      'prompt_replace_add_rule',
      'prompt_replace_rules_hint',
      'prompt_replace_rules_empty',
      'prompt_replace_rule_label',
      'prompt_replace_source',
      'prompt_replace_target',
      'prompt_replace_batch_input',
      'prompt_replace_batch_placeholder',
      'prompt_replace_batch_hint',
      'prompt_replace_batch_add',
      'prompt_replace_delete',
      'prompt_replace_source_placeholder',
      'prompt_replace_target_placeholder',
      'prompt_replace_duplicate',
    ];

    for (final key in requiredKeys) {
      expect(en.containsKey(key), isTrue, reason: 'en.json missing $key');
      expect(zh.containsKey(key), isTrue, reason: 'zh-CN.json missing $key');
    }
  });
}
