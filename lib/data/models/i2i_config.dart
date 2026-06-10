import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:image_size_getter/image_size_getter.dart';

class I2IConfigResult {
  String imageB64;
  double strength;
  double noise;
  int extraNoiseSeed;
  String? overridePrompts;

  I2IConfigResult({
    required this.imageB64,
    required this.strength,
    required this.noise,
    required this.extraNoiseSeed,
    required this.overridePrompts,
  });
}

class I2IConfig with ChangeNotifier {
  // Basic settings
  String? imageB64;
  int width = 0;
  int height = 0;

  double strength;
  double noise;

  // Prompt overrides
  bool overridePromptEnabled;
  String overridePrompt;

  I2IConfigResult getConfigResult() {
    if (imageB64 == null) {
      throw Exception('I2I input image is null!');
    }
    final trimmedOverridePrompt = overridePrompt.trim();
    return I2IConfigResult(
      imageB64: imageB64!,
      strength: strength,
      noise: noise,
      extraNoiseSeed: Random().nextInt(1 << 32 - 1),
      overridePrompts: overridePromptEnabled && trimmedOverridePrompt.isNotEmpty
          ? trimmedOverridePrompt
          : null,
    );
  }

  I2IConfig({
    this.imageB64,
    this.width = 0,
    this.height = 0,
    this.strength = 0.5,
    this.noise = 0,
    this.overridePromptEnabled = false,
    this.overridePrompt = '',
  });

  Map<String, dynamic> toJson() {
    return {
      'image_b64': imageB64,
      'width': width,
      'height': height,
      'strength': strength,
      'noise': noise,
      'override_prompt_enabled': overridePromptEnabled,
      'override_prompt': overridePrompt,
    };
  }

  factory I2IConfig.fromJson(Map<String, dynamic> json) {
    return I2IConfig(
      imageB64: _parseNullableString(json['image_b64']),
      width: _parseInt(json['width'], 0),
      height: _parseInt(json['height'], 0),
      strength: _parseDouble(json['strength'], 0.5).clamp(0.0, 1.0),
      noise: _parseDouble(json['noise'], 0).clamp(0.0, 1.0),
      overridePromptEnabled: _parseBool(json['override_prompt_enabled'], false),
      overridePrompt: _parseString(json['override_prompt'], ''),
    );
  }

  void loadJson(Map<String, dynamic> json) {
    final loaded = I2IConfig.fromJson(json);
    imageB64 = loaded.imageB64;
    width = loaded.width;
    height = loaded.height;
    strength = loaded.strength;
    noise = loaded.noise;
    overridePromptEnabled = loaded.overridePromptEnabled;
    overridePrompt = loaded.overridePrompt;
    notifyListeners();
  }

  void reset() {
    loadJson(const <String, dynamic>{});
  }

  void setImage(Uint8List bytes) {
    final size = ImageSizeGetter.getSizeResult(MemoryInput(bytes)).size;
    width = size.width;
    height = size.height;
    imageB64 = base64Encode(bytes);
    notifyListeners();
  }

  void clearImage() {
    imageB64 = null;
    width = 0;
    height = 0;
    notifyListeners();
  }

  void updateStrength(double value) {
    strength = value.clamp(0.0, 1.0);
    notifyListeners();
  }

  void updateNoise(double value) {
    noise = value.clamp(0.0, 1.0);
    notifyListeners();
  }

  void updateStrengthAndNoise(double strengthValue, double noiseValue) {
    strength = strengthValue.clamp(0.0, 1.0);
    noise = noiseValue.clamp(0.0, 1.0);
    notifyListeners();
  }

  void setOverridePromptEnabled(bool value) {
    overridePromptEnabled = value;
    notifyListeners();
  }

  void setOverridePrompt(String value) {
    overridePrompt = value;
    notifyListeners();
  }

  static String? _parseNullableString(dynamic value) {
    if (value == null) return null;
    if (value is String) return value;
    return null;
  }

  static String _parseString(dynamic value, String fallback) {
    if (value is String) return value;
    return fallback;
  }

  static int _parseInt(dynamic value, int fallback) {
    if (value is int) return value;
    if (value is double) return value.round();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }

  static double _parseDouble(dynamic value, double fallback) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? fallback;
    return fallback;
  }

  static bool _parseBool(dynamic value, bool fallback) {
    if (value is bool) return value;
    if (value is String) return bool.tryParse(value) ?? fallback;
    return fallback;
  }
}
