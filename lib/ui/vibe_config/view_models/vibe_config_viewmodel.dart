import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:nai_casrand/data/models/payload_config.dart';
import 'package:nai_casrand/data/services/config_service.dart';
import 'package:nai_casrand/data/models/vibe_config.dart';

class VibeConfigViewmodel extends ChangeNotifier {
  final VibeConfig config;

  PayloadConfig get payloadConfig => GetIt.I<PayloadConfig>();
  ConfigService get configService => GetIt.I<ConfigService>();

  VibeConfigViewmodel({required this.config});

  String get fileName => config.fileName;
  double get referenceStrength => config.referenceStrength;
  double get infoExtracted => config.infoExtracted;

  void setInfoExtracted(double value) {
    config.infoExtracted = value;
    notifyListeners();
    configService.saveConfig(payloadConfig.toJson());
  }

  void setReferenceStrength(double value) {
    config.referenceStrength = value;
    notifyListeners();
    configService.saveConfig(payloadConfig.toJson());
  }
}
