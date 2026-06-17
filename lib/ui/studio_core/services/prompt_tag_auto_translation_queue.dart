import 'dart:async';
import 'dart:collection';

import 'package:novel_studio/data/studio/services/prompt_translation_service.dart';
import 'package:novel_studio/data/studio/services/prompt_workshop_bridge.dart';
import 'package:novel_studio/data/studio/tools/online_ai_tools.dart';
import 'package:novel_studio/data/studio/tools/translation_cache.dart';

typedef PromptTagTranslationCachePersister = Future<void> Function(
  TranslationCache cache,
);

class PromptTagAutoTranslationQueue {
  static final PromptTagAutoTranslationQueue instance =
      PromptTagAutoTranslationQueue._();

  final Queue<_PromptTagAutoTranslationJob> _queue =
      Queue<_PromptTagAutoTranslationJob>();
  final Map<String, _PromptTagAutoTranslationJob> _jobs =
      <String, _PromptTagAutoTranslationJob>{};
  bool _running = false;

  PromptTagAutoTranslationQueue._();

  void resetForTesting() {
    _queue.clear();
    _jobs.clear();
    _running = false;
  }

  Future<OnlineTranslationResult> request({
    required String tag,
    required String sourceLanguage,
    required String targetLanguage,
    required TranslationCache cache,
    required PromptTranslationService service,
    bool preferCache = true,
    PromptTagTranslationCachePersister? saveTranslationCache,
  }) {
    final cleanedTag = tag.trim();
    if (cleanedTag.isEmpty) {
      return Future.value(
        const OnlineTranslationResult(
          text: '',
          source: OnlineAiResultSource.emptyFallback,
        ),
      );
    }
    final key = _key(
      cleanedTag,
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
      preferCache: preferCache,
      cache: cache,
      service: service,
    );
    final existing = _jobs[key];
    if (existing != null) {
      return existing.completer.future;
    }
    final job = _PromptTagAutoTranslationJob(
      key: key,
      tag: cleanedTag,
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
      cache: cache,
      service: service,
      preferCache: preferCache,
      saveTranslationCache: saveTranslationCache,
    );
    _jobs[key] = job;
    _queue.add(job);
    unawaited(_drain());
    return job.completer.future;
  }

  Future<void> _drain() async {
    if (_running) {
      return;
    }
    _running = true;
    while (_queue.isNotEmpty) {
      final job = _queue.removeFirst();
      try {
        final result = await job.service.translate(
          OnlineTranslationRequest(
            text: job.tag,
            sourceLanguage: job.sourceLanguage,
            targetLanguage: job.targetLanguage,
          ),
          preferCache: job.preferCache,
        );
        final translated = result.text.trim();
        if (translated.isNotEmpty &&
            result.source == OnlineAiResultSource.online) {
          job.cache.setCached(
            job.tag,
            translated,
            source: result.providerName ?? job.service.currentMode.name,
          );
          unawaited(_saveCacheBestEffort(job));
        }
        job.completer.complete(result);
      } catch (error) {
        job.completer.complete(
          OnlineTranslationResult(
            text: '',
            source: OnlineAiResultSource.emptyFallback,
            error: error.toString(),
          ),
        );
      } finally {
        _jobs.remove(job.key);
      }
      await Future<void>.delayed(Duration.zero);
    }
    _running = false;
    if (_queue.isNotEmpty) {
      unawaited(_drain());
    }
  }

  Future<void> _saveCacheBestEffort(_PromptTagAutoTranslationJob job) async {
    try {
      final saver = job.saveTranslationCache;
      if (saver != null) {
        await saver(job.cache);
      } else {
        await PromptWorkshopBridge.saveTranslationCache(job.cache);
      }
    } catch (_) {
      // The visible translation result should still be returned if persistence fails.
    }
  }

  String _key(
    String tag, {
    required String sourceLanguage,
    required String targetLanguage,
    required bool preferCache,
    required TranslationCache cache,
    required PromptTranslationService service,
  }) {
    return [
      sourceLanguage,
      targetLanguage,
      preferCache ? 'cache' : 'fresh',
      identityHashCode(cache),
      identityHashCode(service),
      tag.toLowerCase(),
    ].join('::');
  }
}

class _PromptTagAutoTranslationJob {
  final String key;
  final String tag;
  final String sourceLanguage;
  final String targetLanguage;
  final TranslationCache cache;
  final PromptTranslationService service;
  final bool preferCache;
  final PromptTagTranslationCachePersister? saveTranslationCache;
  final Completer<OnlineTranslationResult> completer =
      Completer<OnlineTranslationResult>();

  _PromptTagAutoTranslationJob({
    required this.key,
    required this.tag,
    required this.sourceLanguage,
    required this.targetLanguage,
    required this.cache,
    required this.service,
    required this.preferCache,
    this.saveTranslationCache,
  });
}
