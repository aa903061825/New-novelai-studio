import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/data/studio/tools/online_ai_tools.dart';

void main() {
  group('OnlineAiToolSettings', () {
    test('serializes only export-safe runtime settings', () {
      const settings = OnlineAiToolSettings(
        enabled: true,
        mode: OnlineAiMode.ai,
        secretRef: 'studio-secret',
        apiKey: 'sk-raw-key',
        endpointUrl: 'https://private.example/v1',
        proxyUrl: 'http://127.0.0.1:7890',
        bearerToken: 'Bearer pst-secret-token',
      );

      final encoded = jsonEncode(settings.toJson());

      expect(encoded, contains('studio-secret'));
      expect(encoded, contains('ai'));
      expect(encoded, isNot(contains('sk-raw-key')));
      expect(encoded, isNot(contains('private.example')));
      expect(encoded, isNot(contains('127.0.0.1')));
      expect(encoded, isNot(contains('Bearer')));
      expect(encoded, isNot(contains('pst-secret-token')));
    });
  });

  group('OnlineAiTools translation', () {
    test(
      'uses injected translator provider and returns online metadata',
      () async {
        final tools = OnlineAiTools(
          translators: [
            (request) async {
              expect(request.text, 'cat');
              expect(request.targetLanguage, 'zh');
              return const OnlineTranslationProviderResult(
                translatedText: '猫',
                providerName: 'fake-google',
              );
            },
          ],
        );

        final result = await tools.translate(
          const OnlineTranslationRequest(
            text: 'cat',
            sourceLanguage: 'en',
            targetLanguage: 'zh',
          ),
        );

        expect(result.text, '猫');
        expect(result.source, OnlineAiResultSource.online);
        expect(result.providerName, 'fake-google');
        expect(result.error, isNull);
      },
    );

    test(
      'falls back to injected local/cache translator after provider failure',
      () async {
        final tools = OnlineAiTools(
          translators: [(_) async => throw StateError('network unavailable')],
          localTranslator: (request, error) async {
            expect(request.text, 'dress');
            expect(error, isA<StateError>());
            return const OnlineTranslationFallbackResult(
              translatedText: '连衣裙',
              source: OnlineAiResultSource.localFallback,
            );
          },
        );

        final result = await tools.translate(
          const OnlineTranslationRequest(text: 'dress', targetLanguage: 'zh'),
        );

        expect(result.text, '连衣裙');
        expect(result.source, OnlineAiResultSource.localFallback);
        expect(result.error, contains('network unavailable'));
      },
    );
  });

  group('OnlineAiTools classification', () {
    test('uses injected classifier provider for bucket suggestions', () async {
      final tools = OnlineAiTools(
        classifier: (request) async {
          expect(request.tags, ['solo', 'watercolor']);
          return const OnlineClassificationProviderResult(
            buckets: {
              'Scene': ['solo'],
              'Style': ['watercolor'],
            },
            providerName: 'fake-classifier',
          );
        },
      );

      final result = await tools.classify(
        const OnlineClassificationRequest(tags: ['solo', 'watercolor']),
      );

      expect(result.buckets['Scene'], ['solo']);
      expect(result.buckets['Style'], ['watercolor']);
      expect(result.source, OnlineAiResultSource.online);
      expect(result.providerName, 'fake-classifier');
    });

    test('falls back to local heuristic when classifier fails', () async {
      final tools = OnlineAiTools(
        classifier: (_) async => throw Exception('model timeout'),
      );

      final result = await tools.classify(
        const OnlineClassificationRequest(
          tags: ['solo', 'artist:abc', 'watercolor', 'masterpiece'],
        ),
      );

      expect(result.buckets['Scene'], ['solo']);
      expect(result.buckets['Artist'], ['artist:abc']);
      expect(result.buckets['Style'], ['watercolor']);
      expect(result.buckets['Quality'], ['masterpiece']);
      expect(result.source, OnlineAiResultSource.localFallback);
      expect(result.error, contains('model timeout'));
    });

    test(
      'returns an empty local result when no classifier is configured',
      () async {
        final result = await const OnlineAiTools().classify(
          const OnlineClassificationRequest(tags: []),
        );

        expect(result.buckets, isEmpty);
        expect(result.source, OnlineAiResultSource.emptyFallback);
        expect(result.error, isNull);
      },
    );
  });
}
