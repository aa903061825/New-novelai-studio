import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:novel_studio/data/models/generation_capabilities.dart';
import 'package:novel_studio/data/services/nai_account_usage_service.dart';

enum NaiAnlasChargeState {
  free,
  charged,
  uncertain,
}

@immutable
class NaiImageCostEstimate {
  final NaiAnlasChargeState chargeState;
  final int baseAnlasPerImage;
  final int minimumAnlas;
  final int maximumAnlas;
  final int extraAnlas;
  final int generationCount;
  final String reason;

  const NaiImageCostEstimate({
    required this.chargeState,
    required this.baseAnlasPerImage,
    required this.minimumAnlas,
    required this.maximumAnlas,
    required this.extraAnlas,
    required this.generationCount,
    required this.reason,
  });

  bool get isExact => minimumAnlas == maximumAnlas;
  bool get isFree => isExact && maximumAnlas == 0;
  bool get requiresConfirmation => minimumAnlas > 0;

  String get displayLabel {
    if (isFree) return '预计免费';
    if (isExact) return '预计消耗 $maximumAnlas Anlas';
    return '预计 $minimumAnlas–$maximumAnlas Anlas';
  }

  String get amountDescription {
    if (isFree) return '0 Anlas';
    if (isExact) return '约 $maximumAnlas Anlas';
    return '约 $minimumAnlas–$maximumAnlas Anlas';
  }
}

/// Best-effort preview of NovelAI Image Anlas usage.
///
/// NovelAI performs the final billing. The base estimate mirrors the current
/// V3+ WebUI pricing curve; account, Opus and V5 allowance data come from the
/// same `/user/data` snapshot displayed beside the Generate action.
final class NaiImageCostEstimator {
  const NaiImageCostEstimator._();

  static NaiImageCostEstimate estimate({
    required String model,
    required int width,
    required int height,
    required int steps,
    required int generationCount,
    required bool hasBaseImage,
    required double imageToImageStrength,
    required bool smea,
    required bool smeaDynamic,
    required int extraAnlas,
    required NaiAccountUsageSnapshot? account,
  }) {
    final capabilities = GenerationModelCapabilities.fromModel(model);
    final count = math.max(1, generationCount);
    final perImage = estimateBaseAnlasPerImage(
      width: width,
      height: height,
      steps: steps,
      strength: hasBaseImage ? imageToImageStrength : 1,
      smea: capabilities.supportsSmeaControls && smea,
      smeaDynamic: capabilities.supportsSmeaControls && smeaDynamic,
    );

    final pixelCount = math.max(1, width) * math.max(1, height);
    final opusParametersEligible =
        !hasBaseImage && steps <= 28 && pixelCount <= 1024 * 1024;

    var state = NaiAnlasChargeState.charged;
    var minimumChargedImages = count;
    var maximumChargedImages = count;
    late String reason;

    if (!opusParametersEligible) {
      if (hasBaseImage) {
        reason = '使用了图生图底图，基础生成不在 Opus 免费范围内。';
      } else if (steps > 28) {
        reason = '步数超过 28，基础生成不在 Opus 免费范围内。';
      } else {
        reason = '分辨率超过 1024×1024，基础生成不在 Opus 免费范围内。';
      }
    } else if (account == null) {
      state = NaiAnlasChargeState.uncertain;
      minimumChargedImages = 0;
      reason = '账户状态尚未同步，暂时无法确认 Opus 免费资格。';
    } else if (!account.isOpus) {
      reason = '当前账户不是有效的 Opus 订阅，基础生成会消耗 Anlas。';
    } else if (!capabilities.isV5) {
      state = NaiAnlasChargeState.free;
      minimumChargedImages = 0;
      maximumChargedImages = 0;
      reason = '符合 Opus 单张免费生成条件。';
    } else {
      final usage = account.opusUsage;
      if (usage == null) {
        state = NaiAnlasChargeState.uncertain;
        minimumChargedImages = 0;
        reason = 'V5 Opus 额度尚未同步，暂时无法确认基础费用。';
      } else if (usage.isNegative) {
        reason = 'V5 Opus 免费额度已用尽，基础生成会消耗 Anlas。';
      } else {
        final freeImages = math.min(count, usage.estimatedNormalImages);
        minimumChargedImages = count - freeImages;
        maximumChargedImages = minimumChargedImages;
        if (minimumChargedImages == 0) {
          state = NaiAnlasChargeState.free;
          reason = '本次生成数量在当前 V5 Opus 免费额度内。';
        } else {
          reason = '当前 V5 Opus 额度预计可覆盖 $freeImages 张，其余 '
              '$minimumChargedImages 张会消耗 Anlas。';
        }
      }
    }

    final minimum = minimumChargedImages * perImage + extraAnlas;
    final maximum = maximumChargedImages * perImage + extraAnlas;
    if (extraAnlas > 0) {
      reason = '$reason 另含 $extraAnlas Anlas 的参考图相关附加费用。';
    }

    return NaiImageCostEstimate(
      chargeState: state,
      baseAnlasPerImage: perImage,
      minimumAnlas: minimum,
      maximumAnlas: maximum,
      extraAnlas: extraAnlas,
      generationCount: count,
      reason: reason,
    );
  }

  static int estimateBaseAnlasPerImage({
    required int width,
    required int height,
    required int steps,
    double strength = 1,
    bool smea = false,
    bool smeaDynamic = false,
  }) {
    final pixels = math.max(65536, math.max(1, width) * math.max(1, height));
    final safeSteps = math.max(0, steps);
    final raw = (2.951823174884865e-6 * pixels) +
        (5.753298233447344e-7 * pixels * safeSteps);
    final smeaFactor = smeaDynamic ? 1.4 : (smea ? 1.2 : 1.0);
    final safeStrength = strength.clamp(0.0, 1.0).toDouble();
    return math.max(2, (raw.ceil() * smeaFactor * safeStrength).ceil());
  }
}
