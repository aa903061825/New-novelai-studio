import 'dart:typed_data';

enum StudioDirectorTool {
  removeBackground,
  lineArt,
  sketch,
  colorize,
  emotion,
  declutter,
}

class StudioDirectorToolResultImage {
  final Uint8List bytes;
  final String variantName;
  final int variantIndex;

  const StudioDirectorToolResultImage({
    required this.bytes,
    required this.variantName,
    required this.variantIndex,
  });
}

extension StudioDirectorToolRequestType on StudioDirectorTool {
  String get requestType => switch (this) {
        StudioDirectorTool.removeBackground => 'bg-removal',
        StudioDirectorTool.lineArt => 'lineart',
        StudioDirectorTool.sketch => 'sketch',
        StudioDirectorTool.colorize => 'colorize',
        StudioDirectorTool.emotion => 'emotion',
        StudioDirectorTool.declutter => 'declutter',
      };
}

class StudioDirectorToolOptions {
  final StudioDirectorTool tool;
  final String prompt;
  final int defry;

  const StudioDirectorToolOptions({
    required this.tool,
    this.prompt = '',
    this.defry = 0,
  });

  Map<String, dynamic> toLineageParameters({
    required int sourceWidth,
    required int sourceHeight,
  }) {
    final trimmedPrompt = prompt.trim();
    return {
      'tool': tool.name,
      'req_type': tool.requestType,
      'source_width': sourceWidth,
      'source_height': sourceHeight,
      if (trimmedPrompt.isNotEmpty) 'prompt': trimmedPrompt,
      if (usesDefry) 'defry': defry.clamp(0, 5),
    };
  }

  bool get usesDefry =>
      tool == StudioDirectorTool.colorize || tool == StudioDirectorTool.emotion;
}
