import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:nai_casrand/core/constants/image_formats.dart';
import 'package:nai_casrand/data/models/generation_size.dart';
import 'package:nai_casrand/data/models/param_config.dart';
import 'package:nai_casrand/data/services/image_service.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

import 'package:nai_casrand/data/models/i2i_config.dart';

class I2iVibeViewmodel extends ChangeNotifier {
  I2IConfig config;
  ParamConfig paramConfig;

  I2iVibeViewmodel({required this.config, required this.paramConfig});

  double get imageSize => 300.0;

  void setOverridePromptEnabled(bool? value) {
    if (value == null) return;
    config.setOverridePromptEnabled(value);
    notifyListeners();
  }

  void setOverridePrompt(String value) {
    config.setOverridePrompt(value);
    notifyListeners();
  }

  void removeImage() {
    config.clearImage();
    notifyListeners();
  }

  Future<void> addImage(
    BuildContext context,
    Function(Map<String, dynamic>) paramReadSuccessEvent,
    Function paramReadFailureEvent,
  ) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;

    final bytes = file.bytes ??
        (file.path == null ? null : await File(file.path!).readAsBytes());
    if (bytes == null || bytes.isEmpty) return;

    await loadImageBytes(
      bytes,
      paramReadSuccessEvent,
      paramReadFailureEvent,
    );
  }

  handleDragEvent(
    PerformDropEvent event,
    Function(Map<String, dynamic>) paramReadSuccessEvent,
    Function paramReadFailureEvent,
  ) async {
    final item = event.session.items.first;
    final reader = item.dataReader!;
    reader.getFile(imageFormat, (file) async {
      final bytes = await file.readAll();
      await loadImageBytes(
        bytes,
        paramReadSuccessEvent,
        paramReadFailureEvent,
      );
    });
  }

  Future<void> loadImageBytes(
    Uint8List bytes,
    Function(Map<String, dynamic>) paramReadSuccessEvent,
    Function paramReadFailureEvent,
  ) async {
    // Import image into I2I config
    config.setImage(bytes);

    // Skip metadata reading for images > 5M
    if (bytes.length > 5e6) {
      notifyListeners();
      return;
    }

    // Try parse and import metadata
    final image = img.decodeImage(bytes);
    Map<String, dynamic>? parameters;
    try {
      final metadataString = await ImageService().extractMetadata(image!);
      final Map<String, dynamic> metadata = json.decode(metadataString!);
      parameters = json.decode(metadata['Comment']);
    } catch (err) {
      paramReadFailureEvent();
      notifyListeners();
      return;
    }
    if (parameters != null) {
      paramReadSuccessEvent(parameters);
    }
    notifyListeners();
  }

  int importMetadataParameters(Map<String, dynamic> parameters) {
    final count = paramConfig.loadJson(parameters);
    notifyListeners();
    return count;
  }

  List<GenerationSize> getTargetSizeOptions() {
    if (config.width <= 0 || config.height <= 0) {
      return paramConfig.sizes;
    }

    final options = <GenerationSize>[
      GenerationSize(width: config.width, height: config.height),
      for (final factor in getPossibleScaleFactors(config.width, config.height))
        GenerationSize(
          width: (factor * config.width / 64).ceil() * 64,
          height: (factor * config.height / 64).ceil() * 64,
        ),
      ...paramConfig.sizes,
    ];

    final seen = <String>{};
    return [
      for (final option in options)
        if (seen.add('${option.width}x${option.height}')) option,
    ];
  }

  void setTargetSize(GenerationSize size) {
    paramConfig.sizes = [size];
    notifyListeners();
  }

  String getSizeChangeText() {
    final sizes = paramConfig.sizes
        .map((elem) => '${elem.width} x ${elem.height}')
        .join(" || ");
    final srcWidth = config.width;
    final srcHeight = config.height;
    final targetSize = '[$sizes]';
    final currentSize =
        config.imageB64 == null ? 'N/A' : '$srcWidth x $srcHeight';
    return '$currentSize → $targetSize';
  }

  double getEnhancePresetValue() {
    final s = config.strength;
    if (s <= 0.2) return 1;
    if (s <= 0.4) return 2;
    if (s <= 0.5) return 3;
    if (s <= 0.6) return 4;
    return 5;
  }

  void setPreset(double value) {
    final result = [
      [0.2, 0],
      [0.4, 0],
      [0.5, 0],
      [0.6, 0],
      [0.7, 0.1]
    ][value.toInt() - 1];
    config.updateStrengthAndNoise(result[0].toDouble(), result[1].toDouble());
    notifyListeners();
  }

  void setStrength(double value) {
    config.updateStrength(value);
    notifyListeners();
  }

  void setNoise(double value) {
    config.updateNoise(value);
    notifyListeners();
  }

  List<double> getPossibleScaleFactors(int width, int height,
      {double step = 0.25}) {
    List<double> ret = [];
    const maxPixels = 2048 * 1536;
    for (double f = 1.0;; f += step) {
      int w = (f * width / 64).ceil() * 64;
      int h = (f * height / 64).ceil() * 64;
      if (w * h <= maxPixels) {
        ret.add(f);
      } else {
        break;
      }
    }
    return ret;
  }
}
