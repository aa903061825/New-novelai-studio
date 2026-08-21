import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/data/models/api_request.dart';
import 'package:novel_studio/data/services/nai_account_usage_service.dart';

ApiResponse _response(Map<String, dynamic> json) => ApiResponse(
      status: '200',
      data: Uint8List.fromList(utf8.encode(jsonEncode(json))),
    );

Map<String, dynamic> _usageResponse({
  double percent = 50,
  bool isNegative = false,
  int timeUntilNextPercent = 7200,
}) {
  return {
    'subscription': {
      'tier': 3,
      'active': true,
      'usage': {
        'percent': percent,
        'isNegative': isNegative,
        'timeUntilNextPercent': timeUntilNextPercent,
      },
      'trainingStepsLeft': {
        'fixedTrainingStepsLeft': 10000,
        'purchasedTrainingSteps': 250,
      },
    },
  };
}

void main() {
  test('derives NovelAI account endpoint from generation endpoint', () {
    expect(
      NaiAccountUsageService.userDataEndpointFor(
        'https://image.novelai.net/ai/generate-image?debug=true',
      ),
      'https://image.novelai.net/user/data',
    );
    expect(
      NaiAccountUsageService.userDataEndpointFor('not a url'),
      isNull,
    );
  });

  test('loads Opus usage and Anlas from a simulated account response',
      () async {
    ApiRequest? capturedRequest;
    final service = NaiAccountUsageService(
      fetchData: (request) async {
        capturedRequest = request;
        return _response(_usageResponse());
      },
    );

    await service.refresh(
      generationEndpoint: 'https://image.novelai.net/ai/generate-image',
      proxy: '',
      headers: const {'Authorization': 'Bearer pst-simulated'},
    );

    expect(capturedRequest?.endpoint, 'https://image.novelai.net/user/data');
    expect(service.state, NaiAccountUsageLoadState.available);
    expect(service.snapshot?.isOpus, isTrue);
    expect(service.snapshot?.opusUsage?.visiblePercent, 50);
    expect(service.snapshot?.opusUsage?.estimatedNormalImages, 865);
    expect(service.snapshot?.opusUsage?.refillPercentPerDay, 12);
    expect(service.snapshot?.totalAnlas, 10250);
  });

  test('negative Opus usage is exposed as exhausted', () async {
    final service = NaiAccountUsageService(
      fetchData: (_) async => _response(
        _usageResponse(percent: -0.1, isNegative: true),
      ),
    );

    await service.refresh(
      generationEndpoint: 'https://image.novelai.net/ai/generate-image',
      proxy: '',
      headers: const {'authorization': 'Bearer pst-simulated'},
    );

    expect(service.snapshot?.opusUsage?.isNegative, isTrue);
    expect(service.snapshot?.opusUsage?.visiblePercent, 0);
    expect(service.snapshot?.opusUsage?.estimatedNormalImages, 0);
  });

  test('placeholder token never triggers an account request', () async {
    var callCount = 0;
    final service = NaiAccountUsageService(
      fetchData: (_) async {
        callCount += 1;
        return _response(_usageResponse());
      },
    );

    await service.refresh(
      generationEndpoint: 'https://image.novelai.net/ai/generate-image',
      proxy: '',
      headers: const {'authorization': 'Bearer pst-abcd'},
    );

    expect(callCount, 0);
    expect(service.state, NaiAccountUsageLoadState.unavailable);
    expect(service.snapshot, isNull);
  });

  test('malformed account data becomes unavailable instead of crashing',
      () async {
    final service = NaiAccountUsageService(
      fetchData: (_) async => _response({
        'subscription': {'tier': 3}
      }),
    );

    await service.refresh(
      generationEndpoint: 'https://image.novelai.net/ai/generate-image',
      proxy: '',
      headers: const {'authorization': 'Bearer pst-simulated'},
    );

    expect(service.state, NaiAccountUsageLoadState.unavailable);
    expect(service.errorMessage, contains('额度同步失败'));
  });
}
