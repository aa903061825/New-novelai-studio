import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:novel_studio/data/models/payload_config.dart';
import 'package:novel_studio/data/services/config_service.dart';

import '../../../data/models/vibe_config_v4.dart';

class VibeConfigV4Viewmodel extends ChangeNotifier {
  VibeConfigV4 config;

  PayloadConfig get payloadConfig => GetIt.I<PayloadConfig>();
  ConfigService get configService => GetIt.I<ConfigService>();

  VibeConfigV4Viewmodel({required this.config});

  String get fileName => config.fileName;
  Uint8List? get imageBytes => config.imageBytes;
  String? get sourceImagePath => config.sourceImagePath;
  double get infoExtracted => config.infoExtracted;
  double get referenceStrength => config.referenceStrength;

  setInfoExtracted(double value) {
    config.infoExtracted = value.clamp(0.0, 1.0).toDouble();
    notifyListeners();
    configService.saveConfig(payloadConfig.toJson());
  }

  setReferenceStrength(double value) {
    config.referenceStrength = value;
    notifyListeners();
    configService.saveConfig(payloadConfig.toJson());
  }
}
