import 'dart:math';

import 'package:novel_studio/data/models/prompt_config.dart';

class CharacterPromptResult {
  Point<int> gridCenter;
  Point<double> freeformCenter;
  NestedPrompt prompt;
  String uc;

  CharacterPromptResult({
    required this.gridCenter,
    required this.freeformCenter,
    required this.prompt,
    required this.uc,
  });
}

class CharacterConfig {
  String name;
  List<Point<int>> positions;
  Point<double>? freeformPosition;
  PromptConfig positivePromptConfig;
  String negativePrompt;
  bool enabled;

  CharacterConfig({
    this.name = '',
    required this.positions,
    this.freeformPosition,
    required this.positivePromptConfig,
    required this.negativePrompt,
    required this.enabled,
  });

  CharacterPromptResult getPrompt({Point<double>? fallbackCenter}) {
    final random = Random();
    final promptResult = positivePromptConfig.getPrmpts();
    final resolvedFallback = fallbackCenter ?? const Point(0.5, 0.5);
    final Point<int> positionAsInt;
    if (positions.isNotEmpty) {
      positionAsInt = positions[random.nextInt(positions.length)];
    } else {
      positionAsInt = _gridPositionFromNormalized(resolvedFallback);
    }
    return CharacterPromptResult(
      gridCenter: positionAsInt,
      freeformCenter: freeformPosition ??
          _normalizedGridPosition(positionAsInt) ??
          resolvedFallback,
      prompt: promptResult,
      uc: negativePrompt,
    );
  }

  factory CharacterConfig.fromEmpty({String name = ''}) {
    return CharacterConfig(
      name: name,
      positions: [],
      positivePromptConfig: PromptConfig(strs: [], prompts: []),
      negativePrompt: '',
      enabled: true,
    );
  }

  factory CharacterConfig.fromJson(Map<String, dynamic> json) {
    final positionsJson = json['positions'] as List<dynamic>;
    final positions = positionsJson.map((position) {
      final point = position as Map<String, dynamic>;
      return Point<int>(point['x'], point['y']);
    }).toList();
    final freeformPosition = _pointFromJson(json['freeform_position']);

    return CharacterConfig(
      name: json['name'] ?? '',
      positions: positions,
      freeformPosition: freeformPosition,
      positivePromptConfig: PromptConfig.fromJson(json['positivePromptConfig']),
      negativePrompt: json['negativePrompt'] ?? '',
      enabled: json['enabled'] ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'positions': positions.map((point) {
        return {
          'x': point.x,
          'y': point.y,
        };
      }).toList(),
      if (freeformPosition case final position?)
        'freeform_position': {
          'x': position.x,
          'y': position.y,
        },
      'positivePromptConfig': positivePromptConfig.toJson(),
      'negativePrompt': negativePrompt,
      'enabled': enabled,
    };
  }
}

Point<double> defaultCharacterCenter(int index) {
  const preferred = <Point<double>>[
    Point(0.5, 0.5),
    Point(0.3, 0.5),
    Point(0.7, 0.5),
    Point(0.1, 0.5),
    Point(0.9, 0.5),
    Point(0.5, 0.3),
    Point(0.5, 0.7),
    Point(0.3, 0.3),
    Point(0.7, 0.3),
    Point(0.3, 0.7),
    Point(0.7, 0.7),
    Point(0.1, 0.3),
    Point(0.9, 0.3),
    Point(0.1, 0.7),
    Point(0.9, 0.7),
    Point(0.5, 0.1),
    Point(0.5, 0.9),
    Point(0.3, 0.1),
    Point(0.7, 0.1),
    Point(0.3, 0.9),
    Point(0.7, 0.9),
    Point(0.1, 0.1),
    Point(0.9, 0.1),
    Point(0.1, 0.9),
    Point(0.9, 0.9),
  ];
  if (index < 0 || index >= preferred.length) {
    return const Point(0.5, 0.5);
  }
  return preferred[index];
}

Point<double>? _normalizedGridPosition(Point<int> point) {
  const values = <int, double>{
    1: 0.1,
    2: 0.3,
    3: 0.5,
    4: 0.7,
    5: 0.9,
  };
  final x = values[point.x];
  final y = values[point.y];
  return x == null || y == null ? null : Point(x, y);
}

Point<int> _gridPositionFromNormalized(Point<double> point) {
  const values = <double>[0.1, 0.3, 0.5, 0.7, 0.9];
  int nearest(double value) {
    var bestIndex = 0;
    var bestDistance = double.infinity;
    for (var index = 0; index < values.length; index += 1) {
      final distance = (values[index] - value).abs();
      if (distance < bestDistance) {
        bestIndex = index;
        bestDistance = distance;
      }
    }
    return bestIndex + 1;
  }

  return Point(nearest(point.x), nearest(point.y));
}

Point<double>? _pointFromJson(dynamic value) {
  if (value is! Map) return null;
  final x = value['x'];
  final y = value['y'];
  if (x is! num || y is! num) return null;
  return Point(
    x.toDouble().clamp(0.0, 1.0).toDouble(),
    y.toDouble().clamp(0.0, 1.0).toDouble(),
  );
}
