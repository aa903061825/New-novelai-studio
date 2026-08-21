import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:novel_studio/data/models/api_request.dart';
import 'package:novel_studio/data/services/api_service.dart';

typedef NaiAccountUsageFetcher = Future<ApiResponse> Function(
  ApiRequest request,
);

enum NaiAccountUsageLoadState {
  idle,
  loading,
  available,
  unavailable,
}

@immutable
class NaiOpusUsage {
  final double percent;
  final bool isNegative;
  final int timeUntilNextPercent;

  const NaiOpusUsage({
    required this.percent,
    required this.isNegative,
    required this.timeUntilNextPercent,
  });

  double get visiblePercent =>
      isNegative ? 0 : percent.clamp(0.0, 100.0).toDouble();

  int get estimatedNormalImages => (visiblePercent * 17.3).round();

  double? get refillPercentPerDay {
    if (timeUntilNextPercent <= 0) return null;
    return (86400 / timeUntilNextPercent * 10).roundToDouble() / 10;
  }

  factory NaiOpusUsage.fromJson(Map<String, dynamic> json) {
    final percent = _number(json['percent']);
    final isNegative = json['isNegative'];
    final timeUntilNextPercent = _number(json['timeUntilNextPercent']);
    if (percent == null ||
        isNegative is! bool ||
        timeUntilNextPercent == null) {
      throw const FormatException('NovelAI Opus usage data is incomplete.');
    }
    return NaiOpusUsage(
      percent: percent.toDouble(),
      isNegative: isNegative,
      timeUntilNextPercent: timeUntilNextPercent.round(),
    );
  }
}

@immutable
class NaiAccountUsageSnapshot {
  final int tier;
  final bool active;
  final NaiOpusUsage? opusUsage;
  final int? subscriptionAnlas;
  final int? purchasedAnlas;

  const NaiAccountUsageSnapshot({
    required this.tier,
    required this.active,
    required this.opusUsage,
    this.subscriptionAnlas,
    this.purchasedAnlas,
  });

  bool get isOpus => active && tier >= 3;

  int? get totalAnlas {
    if (subscriptionAnlas == null && purchasedAnlas == null) return null;
    return (subscriptionAnlas ?? 0) + (purchasedAnlas ?? 0);
  }

  factory NaiAccountUsageSnapshot.fromJson(Map<String, dynamic> json) {
    final subscription = _map(json['subscription']);
    if (subscription == null) {
      throw const FormatException('NovelAI subscription data is missing.');
    }
    final tier = _number(subscription['tier'])?.round();
    final active = subscription['active'];
    if (tier == null || active is! bool) {
      throw const FormatException('NovelAI subscription data is incomplete.');
    }

    final usageJson = _map(subscription['usage']);
    final trainingSteps = _map(subscription['trainingStepsLeft']);
    return NaiAccountUsageSnapshot(
      tier: tier,
      active: active,
      opusUsage: usageJson == null ? null : NaiOpusUsage.fromJson(usageJson),
      subscriptionAnlas:
          _number(trainingSteps?['fixedTrainingStepsLeft'])?.round(),
      purchasedAnlas:
          _number(trainingSteps?['purchasedTrainingSteps'])?.round(),
    );
  }
}

class NaiAccountUsageService extends ChangeNotifier {
  final NaiAccountUsageFetcher _fetchData;

  NaiAccountUsageService({NaiAccountUsageFetcher? fetchData})
      : _fetchData = fetchData ?? ApiService().fetchGetData;

  NaiAccountUsageLoadState _state = NaiAccountUsageLoadState.idle;
  NaiAccountUsageSnapshot? _snapshot;
  String? _errorMessage;
  Future<void>? _activeRefresh;

  NaiAccountUsageLoadState get state => _state;
  NaiAccountUsageSnapshot? get snapshot => _snapshot;
  String? get errorMessage => _errorMessage;
  bool get isLoading => _state == NaiAccountUsageLoadState.loading;

  Future<void> refresh({
    required String generationEndpoint,
    required String proxy,
    required Map<String, String> headers,
  }) {
    final active = _activeRefresh;
    if (active != null) return active;
    final refresh = _refresh(
      generationEndpoint: generationEndpoint,
      proxy: proxy,
      headers: headers,
    );
    _activeRefresh = refresh;
    return refresh.whenComplete(() => _activeRefresh = null);
  }

  Future<void> _refresh({
    required String generationEndpoint,
    required String proxy,
    required Map<String, String> headers,
  }) async {
    final endpoint = userDataEndpointFor(generationEndpoint);
    if (endpoint == null) {
      _setUnavailable('当前生成地址无法同步 NovelAI 账户额度。');
      return;
    }
    String? authorization;
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == 'authorization') {
        authorization = entry.value.trim();
        break;
      }
    }
    if (authorization == null ||
        authorization.isEmpty ||
        authorization == 'Bearer pst-abcd') {
      _setUnavailable('设置有效的 NovelAI Persistent API Token 后可同步额度。');
      return;
    }

    _state = NaiAccountUsageLoadState.loading;
    _errorMessage = null;
    notifyListeners();
    try {
      final response = await _fetchData(
        ApiRequest(
          endpoint: endpoint,
          proxy: proxy,
          headers: headers,
          payload: const {},
          timeout: const Duration(seconds: 15),
          logLabel: 'nai-account-usage',
        ),
      );
      final statusCode = int.tryParse(response.status) ?? 0;
      if (statusCode < 200 || statusCode >= 300) {
        throw FormatException('NovelAI account request returned $statusCode.');
      }
      final decoded = jsonDecode(utf8.decode(response.data));
      final root = _map(decoded);
      if (root == null) {
        throw const FormatException(
            'NovelAI account response is not an object.');
      }
      _snapshot = NaiAccountUsageSnapshot.fromJson(root);
      _state = NaiAccountUsageLoadState.available;
      _errorMessage = null;
      notifyListeners();
    } catch (error) {
      _setUnavailable('额度同步失败：$error', preserveSnapshot: true);
    }
  }

  void _setUnavailable(
    String message, {
    bool preserveSnapshot = false,
  }) {
    if (!preserveSnapshot) _snapshot = null;
    _state = NaiAccountUsageLoadState.unavailable;
    _errorMessage = message;
    notifyListeners();
  }

  static String? userDataEndpointFor(String generationEndpoint) {
    final uri = Uri.tryParse(generationEndpoint.trim());
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
    if (uri.scheme != 'https' && uri.scheme != 'http') return null;
    return Uri(
      scheme: uri.scheme,
      userInfo: uri.userInfo,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: '/user/data',
    ).toString();
  }
}

Map<String, dynamic>? _map(dynamic value) {
  if (value is Map) return value.cast<String, dynamic>();
  return null;
}

num? _number(dynamic value) => value is num ? value : num.tryParse('$value');
