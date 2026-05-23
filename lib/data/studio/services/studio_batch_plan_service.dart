import 'dart:math';

import 'package:nai_casrand/data/models/payload_config.dart';
import 'package:nai_casrand/data/workspace/models/workspace_entities.dart';
import 'package:nai_casrand/data/workspace/workspace_service.dart';

class StudioBatchQueuePlan {
  final BatchPlan plan;
  final List<StudioBatchQueueItem> items;

  const StudioBatchQueuePlan({
    required this.plan,
    required this.items,
  });
}

class StudioBatchQueueItem {
  final String id;
  final String planId;
  final String planName;
  final int index;
  final String title;
  final String summary;
  final Map<String, dynamic> raw;

  StudioBatchQueueItem({
    required this.id,
    required this.planId,
    required this.planName,
    required this.index,
    required this.title,
    required this.summary,
    required Map<String, dynamic> raw,
  }) : raw = Map.unmodifiable(Map<String, dynamic>.from(raw));
}

class StudioBatchApplyResult {
  final String? positivePrompt;
  final String? negativePrompt;
  final int paramChangeCount;
  final int batchSettingChangeCount;

  const StudioBatchApplyResult({
    this.positivePrompt,
    this.negativePrompt,
    required this.paramChangeCount,
    required this.batchSettingChangeCount,
  });
}

class StudioBatchPlanService {
  final WorkspaceService workspaceService;

  const StudioBatchPlanService({required this.workspaceService});

  Future<List<StudioBatchQueuePlan>> loadQueuePlans() async {
    final plans = await workspaceService.loadBatchPlans();
    return [
      for (final plan in plans)
        StudioBatchQueuePlan(
          plan: plan,
          items: [
            for (final (index, raw) in plan.items.indexed)
              StudioBatchQueueItem(
                id: '${plan.id}:$index',
                planId: plan.id,
                planName: plan.name,
                index: index,
                title: _titleFor(plan, raw, index),
                summary: _summaryFor(raw),
                raw: raw,
              ),
          ],
        ),
    ];
  }

  StudioBatchApplyResult applyQueueItem({
    required StudioBatchQueueItem item,
    required PayloadConfig target,
  }) {
    final positivePrompt = _firstPromptText(item.raw, const [
      'prompt',
      'positivePrompt',
      'positive_prompt',
      'positive',
      'override_prompt',
      'input',
      'prompts',
    ]);
    if (positivePrompt != null) {
      target.overridePrompt = positivePrompt;
      target.useOverridePrompt = true;
    }

    final negativePrompt = _firstPromptText(item.raw, const [
      'negativePrompt',
      'negative_prompt',
      'negative',
      'uc',
    ]);
    if (negativePrompt != null) {
      target.paramConfig.negativePrompt = negativePrompt;
    }

    final paramOverrides = _paramOverrides(item.raw);
    final paramChangeCount = target.paramConfig.loadJson(paramOverrides);

    final batchOverrides = _batchOverrides(item.raw);
    final batchSettingChangeCount = _applyBatchOverrides(
      target,
      batchOverrides,
    );

    return StudioBatchApplyResult(
      positivePrompt: positivePrompt,
      negativePrompt: negativePrompt,
      paramChangeCount: paramChangeCount,
      batchSettingChangeCount: batchSettingChangeCount,
    );
  }

  String _titleFor(
    BatchPlan plan,
    Map<String, dynamic> raw,
    int index,
  ) {
    for (final key in const ['title', 'name', 'id', 'prompt', 'recipe']) {
      final value = _stringValue(raw[key]);
      if (value != null) {
        return _shorten(value, 48);
      }
    }
    return '${plan.name} #${index + 1}';
  }

  String _summaryFor(Map<String, dynamic> raw) {
    final entries = raw.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    return entries
        .take(4)
        .map((entry) => '${entry.key}: ${_previewValue(entry.value)}')
        .join(' · ');
  }

  String _previewValue(dynamic value) {
    if (value is Map) {
      return '{${value.keys.take(3).join(', ')}}';
    }
    if (value is List) {
      return '[${value.take(3).map(_previewValue).join(', ')}]';
    }
    return _shorten('$value', 40);
  }

  String? _firstPromptText(Map<String, dynamic> raw, List<String> keys) {
    for (final key in keys) {
      final value = _promptText(raw[key]);
      if (value != null) return value;
    }
    return null;
  }

  String? _promptText(dynamic value) {
    if (value is String) {
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
    if (value is List) {
      final parts = value
          .map(_promptText)
          .whereType<String>()
          .where((part) => part.isNotEmpty)
          .toList(growable: false);
      if (parts.isEmpty) return null;
      return parts.join(', ');
    }
    return null;
  }

  Map<String, dynamic> _paramOverrides(Map<String, dynamic> raw) {
    final result = <String, dynamic>{};
    for (final key in const [
      'paramsOverride',
      'params_override',
      'params',
      'parameters',
    ]) {
      final value = raw[key];
      if (value is Map) {
        result.addAll(_canonicalParamMap(value));
      }
    }

    for (final entry in raw.entries) {
      final canonicalKey = _canonicalParamKey(entry.key);
      if (canonicalKey != null) {
        result[canonicalKey] = entry.value;
      }
    }
    return result;
  }

  Map<String, dynamic> _canonicalParamMap(Map<dynamic, dynamic> source) {
    final result = <String, dynamic>{};
    for (final entry in source.entries) {
      final key = entry.key;
      if (key is! String) continue;
      final canonicalKey = _canonicalParamKey(key);
      if (canonicalKey != null) {
        result[canonicalKey] = entry.value;
      }
    }
    return result;
  }

  String? _canonicalParamKey(String key) {
    return switch (key) {
      'width' => 'width',
      'height' => 'height',
      'scale' => 'scale',
      'sampler' => 'sampler',
      'steps' => 'steps',
      'n_samples' || 'nSamples' => 'n_samples',
      'uc' => 'uc',
      'negative_prompt' => 'negative_prompt',
      'seed' => 'seed',
      'use_coords' || 'useCoords' => 'use_coords',
      _ => null,
    };
  }

  Map<String, dynamic> _batchOverrides(Map<String, dynamic> raw) {
    final result = <String, dynamic>{};
    for (final key in const [
      'batchDefaults',
      'batch_defaults',
      'settingsOverride',
      'settings_override',
      'settings',
    ]) {
      final value = raw[key];
      if (value is Map) {
        result.addAll(_canonicalBatchMap(value));
      }
    }

    for (final entry in raw.entries) {
      final canonicalKey = _canonicalBatchKey(entry.key);
      if (canonicalKey != null) {
        result[canonicalKey] = entry.value;
      }
    }
    return result;
  }

  Map<String, dynamic> _canonicalBatchMap(Map<dynamic, dynamic> source) {
    final result = <String, dynamic>{};
    for (final entry in source.entries) {
      final key = entry.key;
      if (key is! String) continue;
      final canonicalKey = _canonicalBatchKey(key);
      if (canonicalKey != null) {
        result[canonicalKey] = entry.value;
      }
    }
    return result;
  }

  String? _canonicalBatchKey(String key) {
    return switch (key) {
      'batch_count' || 'batchCount' => 'batch_count',
      'batch_interval' ||
      'batchInterval' ||
      'batchIntervalSec' =>
        'batch_interval',
      'batch_interval_jitter_min' ||
      'batchIntervalJitterMinSec' =>
        'batch_interval_jitter_min',
      'batch_interval_jitter_max' ||
      'batchIntervalJitterMaxSec' =>
        'batch_interval_jitter_max',
      'retry_on_429_enabled' || 'retryOn429Enabled' => 'retry_on_429_enabled',
      'retry_on_429_delay_sec' ||
      'retryOn429DelaySec' =>
        'retry_on_429_delay_sec',
      'number_of_requests' ||
      'numberOfRequests' ||
      'requestCount' =>
        'number_of_requests',
      _ => null,
    };
  }

  int _applyBatchOverrides(
    PayloadConfig target,
    Map<String, dynamic> overrides,
  ) {
    var count = 0;
    final settings = target.settings;
    for (final entry in overrides.entries) {
      switch (entry.key) {
        case 'batch_count':
          final value = _intValue(entry.value);
          if (value == null) break;
          settings.batchCount = max(1, value);
          count++;
          break;
        case 'batch_interval':
          final value = _intValue(entry.value);
          if (value == null) break;
          settings.batchIntervalSec = max(0, value);
          count++;
          break;
        case 'batch_interval_jitter_min':
          final value = _intValue(entry.value);
          if (value == null) break;
          settings.batchIntervalJitterMinSec = max(0, value);
          count++;
          break;
        case 'batch_interval_jitter_max':
          final value = _intValue(entry.value);
          if (value == null) break;
          settings.batchIntervalJitterMaxSec = max(0, value);
          count++;
          break;
        case 'retry_on_429_enabled':
          final value = _boolValue(entry.value);
          if (value == null) break;
          settings.retryOn429Enabled = value;
          count++;
          break;
        case 'retry_on_429_delay_sec':
          final value = _intValue(entry.value);
          if (value == null) break;
          settings.retryOn429DelaySec = max(1, value);
          count++;
          break;
        case 'number_of_requests':
          final value = _intValue(entry.value);
          if (value == null) break;
          settings.numberOfRequests = max(0, value);
          count++;
          break;
      }
    }
    return count;
  }

  String? _stringValue(dynamic value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  int? _intValue(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  bool? _boolValue(dynamic value) {
    if (value is bool) return value;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'true') return true;
      if (normalized == 'false') return false;
    }
    return null;
  }

  String _shorten(String value, int maxLength) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= maxLength) return normalized;
    return '${normalized.substring(0, maxLength - 3)}...';
  }
}
