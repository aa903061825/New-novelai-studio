const generationQualityPresets = ['none', 'standard', 'light'];
const generationUcPresets = [
  'none',
  'heavy',
  'light',
  'humanFocus',
  'furryFocus',
];

const _qualityTags = <String, List<String>>{
  'standard': ['very aesthetic', 'masterpiece', 'no text'],
  'light': ['very aesthetic', 'amazing quality', 'no text'],
};

const _ucTags = <String, List<String>>{
  'heavy': [
    'lowres',
    'artistic error',
    'film grain',
    'scan artifacts',
    'worst quality',
    'bad quality',
    'jpeg artifacts',
    'very displeasing',
    'chromatic aberration',
    'dithering',
    'halftone',
    'screentone',
    'multiple views',
    'logo',
    'too many watermarks',
    'negative space',
    'blank page',
  ],
  'light': [
    'lowres',
    'bad hands',
    'bad anatomy',
    'artistic error',
    'sepia',
    'white haze',
    'worst quality',
    'very displeasing',
    'jpeg artifacts',
    '0::ai-generated::',
  ],
  'humanFocus': [
    'lowres',
    'artistic error',
    'film grain',
    'scan artifacts',
    'worst quality',
    'bad quality',
    'jpeg artifacts',
    'very displeasing',
    'chromatic aberration',
    'dithering',
    'halftone',
    'screentone',
    'multiple views',
    'logo',
    'too many watermarks',
    'negative space',
    'blank page',
    '@_@',
    'mismatched pupils',
    'glowing eyes',
    'bad anatomy',
  ],
  'furryFocus': [
    '{worst quality}',
    'distracting watermark',
    'unfinished',
    'bad quality',
    '{widescreen}',
    'upscale',
    '{sequence}',
    '{{grandfathered content}}',
    'blurred foreground',
    'chromatic aberration',
    'sketch',
    'everyone',
    '[sketch background]',
    'simple',
    '[flat colors]',
    'ych (character)',
    'outline',
    'multiple scenes',
    '[[horror (theme)]]',
    'comic',
  ],
};

int qualityPresetHint(String preset) => switch (preset) {
      'standard' => 1,
      'light' => 3,
      _ => 0,
    };

int ucPresetHint(String preset) => switch (preset) {
      'heavy' => 2,
      'light' => 3,
      'humanFocus' => 4,
      'furryFocus' => 5,
      _ => 0,
    };

String qualityPresetFromHint(Object? hint) => switch (_asInt(hint)) {
      1 => 'standard',
      3 => 'light',
      _ => 'none',
    };

String ucPresetFromHint(Object? hint) => switch (_asInt(hint)) {
      2 => 'heavy',
      3 => 'light',
      4 => 'humanFocus',
      5 => 'furryFocus',
      _ => 'none',
    };

String applyV5PositivePreset(
  String prompt, {
  required String qualityPreset,
  required bool transparentBackground,
}) {
  final additions = <String>[
    if (transparentBackground) 'transparent background',
    ...?_qualityTags[qualityPreset],
  ];
  return _mergeTags(prompt, additions, prepend: false);
}

String applyV5NegativePreset(String prompt, String preset) {
  return _mergeTags(prompt, _ucTags[preset] ?? const [], prepend: true);
}

String _mergeTags(
  String prompt,
  List<String> additions, {
  required bool prepend,
}) {
  final existing = prompt
      .split(RegExp(r'[,，]'))
      .map((tag) => tag.trim())
      .where((tag) => tag.isNotEmpty)
      .toList();
  final seen = <String>{for (final tag in existing) tag.toLowerCase()};
  final uniqueAdditions = <String>[];
  for (final tag in additions) {
    if (seen.add(tag.toLowerCase())) uniqueAdditions.add(tag);
  }
  final merged = prepend
      ? <String>[...uniqueAdditions, ...existing]
      : <String>[...existing, ...uniqueAdditions];
  return merged.join(', ');
}

int? _asInt(Object? value) {
  if (value is int) return value;
  return int.tryParse('$value');
}
