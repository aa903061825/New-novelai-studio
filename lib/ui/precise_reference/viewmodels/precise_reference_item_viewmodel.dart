import 'package:flutter/foundation.dart';
import 'package:nai_casrand/data/models/precise_reference_config.dart';

class PreciseReferenceItemViewmodel extends ChangeNotifier {
  final PreciseReferenceConfig config;

  PreciseReferenceItemViewmodel({required this.config});

  String get fileName => config.fileName;
  String get type => config.type;
  double get strength => config.strength;
  double get fidelity => config.fidelity;

  Uint8List? get imageBytes {
    try {
      return config.imageBytes;
    } catch (_) {
      return null;
    }
  }

  void setType(String value) {
    final safeType = switch (value) {
      'character' => 'character',
      'style' => 'style',
      _ => 'character&style',
    };
    config.type = safeType;
    notifyListeners();
  }

  void setStrength(double value) {
    config.strength = value.clamp(0.0, 1.0);
    notifyListeners();
  }

  void setFidelity(double value) {
    config.fidelity = value.clamp(0.0, 1.0);
    notifyListeners();
  }
}
