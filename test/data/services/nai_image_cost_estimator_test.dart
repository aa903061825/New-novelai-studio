import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/data/services/nai_account_usage_service.dart';
import 'package:novel_studio/data/services/nai_image_cost_estimator.dart';

const _opusAccount = NaiAccountUsageSnapshot(
  tier: 3,
  active: true,
  opusUsage: NaiOpusUsage(
    percent: 50,
    isNegative: false,
    timeUntilNextPercent: 7200,
  ),
  subscriptionAnlas: 1000,
  purchasedAnlas: 25,
);

void main() {
  test('estimates the V3+ 1024 square base price', () {
    expect(
      NaiImageCostEstimator.estimateBaseAnlasPerImage(
        width: 1024,
        height: 1024,
        steps: 28,
      ),
      20,
    );
  });

  test('marks eligible V4.5 Opus generations as free', () {
    final estimate = NaiImageCostEstimator.estimate(
      model: 'nai-diffusion-4-5-full',
      width: 1024,
      height: 1024,
      steps: 28,
      generationCount: 3,
      hasBaseImage: false,
      imageToImageStrength: 0.5,
      smea: false,
      smeaDynamic: false,
      extraAnlas: 0,
      account: _opusAccount,
    );

    expect(estimate.chargeState, NaiAnlasChargeState.free);
    expect(estimate.isFree, isTrue);
    expect(estimate.displayLabel, '预计免费');
  });

  test('charges non-Opus generations and scales with count', () {
    final estimate = NaiImageCostEstimator.estimate(
      model: 'nai-diffusion-5-full',
      width: 1024,
      height: 1024,
      steps: 28,
      generationCount: 2,
      hasBaseImage: false,
      imageToImageStrength: 0.5,
      smea: false,
      smeaDynamic: false,
      extraAnlas: 0,
      account: const NaiAccountUsageSnapshot(
        tier: 2,
        active: true,
        opusUsage: null,
      ),
    );

    expect(estimate.chargeState, NaiAnlasChargeState.charged);
    expect(estimate.minimumAnlas, 40);
    expect(estimate.maximumAnlas, 40);
  });

  test('uses V5 allowance to estimate a partially charged run', () {
    final estimate = NaiImageCostEstimator.estimate(
      model: 'nai-diffusion-5-full',
      width: 1024,
      height: 1024,
      steps: 28,
      generationCount: 3,
      hasBaseImage: false,
      imageToImageStrength: 0.5,
      smea: false,
      smeaDynamic: false,
      extraAnlas: 0,
      account: const NaiAccountUsageSnapshot(
        tier: 3,
        active: true,
        opusUsage: NaiOpusUsage(
          percent: 0.05,
          isNegative: false,
          timeUntilNextPercent: 7200,
        ),
      ),
    );

    expect(estimate.minimumAnlas, 40);
    expect(estimate.maximumAnlas, 40);
    expect(estimate.reason, contains('可覆盖 1 张'));
  });

  test('shows a range while account status is unavailable', () {
    final estimate = NaiImageCostEstimator.estimate(
      model: 'nai-diffusion-4-5-full',
      width: 1024,
      height: 1024,
      steps: 28,
      generationCount: 1,
      hasBaseImage: false,
      imageToImageStrength: 0.5,
      smea: false,
      smeaDynamic: false,
      extraAnlas: 2,
      account: null,
    );

    expect(estimate.chargeState, NaiAnlasChargeState.uncertain);
    expect(estimate.minimumAnlas, 2);
    expect(estimate.maximumAnlas, 22);
    expect(estimate.displayLabel, '预计 2–22 Anlas');
  });

  test('img2img is charged and applies generation strength', () {
    final estimate = NaiImageCostEstimator.estimate(
      model: 'nai-diffusion-4-5-full',
      width: 1024,
      height: 1024,
      steps: 28,
      generationCount: 1,
      hasBaseImage: true,
      imageToImageStrength: 0.5,
      smea: false,
      smeaDynamic: false,
      extraAnlas: 0,
      account: _opusAccount,
    );

    expect(estimate.minimumAnlas, 10);
    expect(estimate.maximumAnlas, 10);
    expect(estimate.reason, contains('图生图底图'));
  });
}
