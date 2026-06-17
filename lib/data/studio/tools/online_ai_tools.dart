import 'package:novel_studio/data/studio/tools/prompt_tag_processor.dart';

typedef OnlineTranslatorProvider = Future<OnlineTranslationProviderResult>
    Function(
  OnlineTranslationRequest request,
);

typedef OnlineTranslationFallback = Future<OnlineTranslationFallbackResult?>
    Function(
  OnlineTranslationRequest request,
  Object? error,
);

typedef OnlineClassifierProvider = Future<OnlineClassificationProviderResult>
    Function(
  OnlineClassificationRequest request,
);

enum OnlineAiMode { google, ai }

enum OnlineAiResultSource { online, localFallback, emptyFallback }

class OnlineAiToolSettings {
  final bool enabled;
  final OnlineAiMode mode;
  final String? secretRef;
  final String? apiKey;
  final String? endpointUrl;
  final String? proxyUrl;
  final String? bearerToken;

  const OnlineAiToolSettings({
    this.enabled = false,
    this.mode = OnlineAiMode.google,
    this.secretRef,
    this.apiKey,
    this.endpointUrl,
    this.proxyUrl,
    this.bearerToken,
  });

  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'mode': mode.name,
      if (secretRef != null && secretRef!.isNotEmpty) 'secret_ref': secretRef,
    };
  }
}

class OnlineTranslationRequest {
  final String text;
  final String? sourceLanguage;
  final String targetLanguage;

  const OnlineTranslationRequest({
    required this.text,
    this.sourceLanguage,
    required this.targetLanguage,
  });
}

class OnlineTranslationProviderResult {
  final String translatedText;
  final String providerName;

  const OnlineTranslationProviderResult({
    required this.translatedText,
    required this.providerName,
  });
}

class OnlineTranslationFallbackResult {
  final String translatedText;
  final OnlineAiResultSource source;

  const OnlineTranslationFallbackResult({
    required this.translatedText,
    required this.source,
  });
}

class OnlineTranslationResult {
  final String text;
  final OnlineAiResultSource source;
  final String? providerName;
  final String? error;

  const OnlineTranslationResult({
    required this.text,
    required this.source,
    this.providerName,
    this.error,
  });
}

class OnlineClassificationRequest {
  final List<String> tags;

  const OnlineClassificationRequest({required this.tags});
}

class OnlineClassificationProviderResult {
  final Map<String, List<String>> buckets;
  final String providerName;

  const OnlineClassificationProviderResult({
    required this.buckets,
    required this.providerName,
  });
}

class OnlineClassificationResult {
  final Map<String, List<String>> buckets;
  final OnlineAiResultSource source;
  final String? providerName;
  final String? error;

  const OnlineClassificationResult({
    required this.buckets,
    required this.source,
    this.providerName,
    this.error,
  });
}

class OnlineAiTools {
  final List<OnlineTranslatorProvider> translators;
  final OnlineTranslationFallback? localTranslator;
  final OnlineClassifierProvider? classifier;

  const OnlineAiTools({
    this.translators = const [],
    this.localTranslator,
    this.classifier,
  });

  Future<OnlineTranslationResult> translate(
    OnlineTranslationRequest request,
  ) async {
    Object? lastError;
    for (final translator in translators) {
      try {
        final result = await translator(request);
        return OnlineTranslationResult(
          text: result.translatedText,
          source: OnlineAiResultSource.online,
          providerName: result.providerName,
        );
      } catch (error) {
        lastError = error;
      }
    }

    final fallback = await localTranslator?.call(request, lastError);
    if (fallback != null) {
      return OnlineTranslationResult(
        text: fallback.translatedText,
        source: fallback.source,
        error: lastError?.toString(),
      );
    }

    return OnlineTranslationResult(
      text: request.text,
      source: OnlineAiResultSource.emptyFallback,
      error: lastError?.toString(),
    );
  }

  Future<OnlineClassificationResult> classify(
    OnlineClassificationRequest request,
  ) async {
    try {
      final provider = classifier;
      if (provider != null) {
        final result = await provider(request);
        return OnlineClassificationResult(
          buckets: _freezeBuckets(result.buckets),
          source: OnlineAiResultSource.online,
          providerName: result.providerName,
        );
      }
    } catch (error) {
      return _localClassification(request.tags, error);
    }

    return _localClassification(request.tags, null);
  }

  OnlineClassificationResult _localClassification(
    List<String> tags,
    Object? error,
  ) {
    if (tags.isEmpty) {
      return OnlineClassificationResult(
        buckets: const {},
        source: OnlineAiResultSource.emptyFallback,
        error: error?.toString(),
      );
    }

    final buckets = PromptTagProcessor.heuristicSplit(tags.join(', '));
    return OnlineClassificationResult(
      buckets: _freezeBuckets({
        'Scene': buckets.scene,
        'Artist': buckets.artist,
        'Style': buckets.style,
        'Quality': buckets.quality,
        'Character': buckets.character,
        if (buckets.deleted.isNotEmpty) 'Deleted': buckets.deleted,
      }),
      source: OnlineAiResultSource.localFallback,
      error: error?.toString(),
    );
  }

  Map<String, List<String>> _freezeBuckets(Map<String, List<String>> buckets) {
    return Map.unmodifiable({
      for (final entry in buckets.entries)
        if (entry.value.isNotEmpty)
          entry.key: List<String>.unmodifiable(entry.value),
    });
  }
}
