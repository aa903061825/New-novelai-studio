import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:novel_studio/core/constants/defaults.dart';
import 'package:novel_studio/data/models/generation_capabilities.dart';
import 'package:novel_studio/data/studio/tools/artist_chain_v5_test_prompt.dart';
import 'package:novel_studio/data/studio/tools/prompt_tag_processor.dart';

const _defaultWorkspace =
    r'C:\Users\admin\AppData\Roaming\org.exception0x0194\nai3_autodraw\novel_studio';
const _defaultModel = naiDiffusion5Full;
const _defaultSeed = 20260823;
const _defaultWidth = 832;
const _defaultHeight = 1216;
const _defaultSteps = 28;
const _defaultScale = 6.5;
const _defaultSampler = 'k_euler_ancestral';
const _defaultCfgRescale = 0.1;

Future<void> main(List<String> args) async {
  final options = _Options.parse(args);
  final workspace = Directory(options.workspacePath);
  if (!await workspace.exists()) {
    throw StateError('Workspace does not exist: ${workspace.path}');
  }

  final artistChainsFile = File(
    '${workspace.path}${Platform.pathSeparator}library'
    '${Platform.pathSeparator}artist_chains.json',
  );
  if (!await artistChainsFile.exists()) {
    throw StateError(
        'Artist-chain library file does not exist: ${artistChainsFile.path}');
  }
  final decoded = jsonDecode(await artistChainsFile.readAsString());
  if (decoded is! List) {
    throw const FormatException('artist_chains.json must be a JSON array.');
  }
  final chains = [
    for (final entry in decoded)
      if (entry is Map) _RawArtistChain.fromJson(entry.cast<String, dynamic>()),
  ];
  if (chains.isEmpty) {
    throw StateError('No artist chains found in ${workspace.path}.');
  }

  final characterFile = File(
    '${workspace.path}${Platform.pathSeparator}library'
    '${Platform.pathSeparator}characters.json',
  );
  if (!await characterFile.exists()) {
    throw StateError(
        'Character-card library file does not exist: ${characterFile.path}');
  }
  final decodedCharacters = jsonDecode(await characterFile.readAsString());
  if (decodedCharacters is! List) {
    throw const FormatException('characters.json must be a JSON array.');
  }
  final characters = [
    for (final entry in decodedCharacters)
      if (entry is Map)
        _RawCharacterCard.fromJson(entry.cast<String, dynamic>()),
  ];
  if (characters.isEmpty) {
    throw StateError('No character cards found in ${characterFile.path}.');
  }

  final selected = chains.take(options.limit).toList(growable: false);
  final shuffledCharacters = [...characters]..shuffle(Random(options.seed));
  final outputDirectory = Directory(options.outputDirectory);
  await outputDirectory.create(recursive: true);
  final queuePath = File(
    '${outputDirectory.path}${Platform.pathSeparator}v5-test-queue.json',
  );
  final requestPayloadManifestPath = _join(
    outputDirectory.path,
    'v5-request-payloads.json',
  );
  final queue = [
    for (var index = 0; index < selected.length; index++)
      for (var attempt = 1; attempt <= options.attempts; attempt++)
        _queueItem(
          chain: selected[index],
          character: shuffledCharacters[index % shuffledCharacters.length],
          outputDirectory: outputDirectory.path,
          requestPayloadManifestPath: requestPayloadManifestPath,
          seed: options.seed + attempt - 1,
          attempt: attempt,
          stripRealisticMediumTags: options.stripRealisticMediumTags &&
              !selected[index].hasRealisticMediumTags,
        ),
  ];
  await queuePath.writeAsString(
    const JsonEncoder.withIndent('  ').convert(queue),
  );

  stdout.writeln('Prepared ${queue.length} NAI V5 artist-chain tests.');
  stdout.writeln('Queue: ${queuePath.path}');
  for (var index = 0; index < selected.length; index++) {
    final character = shuffledCharacters[index % shuffledCharacters.length];
    stdout.writeln(
        ' - ${selected[index].id}: ${selected[index].name} ← ${character.id}: ${character.name}'
        '${selected[index].hasRealisticMediumTags ? ' · 保留原 3D/真人媒介词' : ''}');
  }
}

Map<String, dynamic> _queueItem({
  required _RawArtistChain chain,
  required _RawCharacterCard character,
  required String outputDirectory,
  required String requestPayloadManifestPath,
  required int seed,
  required int attempt,
  required bool stripRealisticMediumTags,
}) {
  return {
    'id': 'artist-chain-v5-test-${_safeFilePart(chain.id)}-attempt$attempt',
    'testRunId': 'r3-strong-quality-character-card',
    'mediumGuardPolicy':
        'only strip explicit realistic/3D medium tags when the chain does not contain them',
    'artistChainId': chain.id,
    'artistChainName': chain.name,
    'characterCardId': character.id,
    'characterCardName': character.name,
    'characterCardPrompt': character.prompt,
    'characterCardIdentityTags': character.identityTags,
    'characterCardAnchorTags': character.anchorTags,
    'attempt': attempt,
    'qualityTerms': artistChainV5QualityTerms,
    'mediumGuard': stripRealisticMediumTags
        ? 'strip explicit 3D/photorealistic medium tags; add 2D anime guard'
        : 'keep original artist-chain medium tags',
    'prompt': buildArtistChainV5TestPrompt(
      artistTerms: chain.promptArtistTerms,
      characterName: character.name,
      characterFrontFull: character.frontFull,
      characterIdentityTags: character.identityTags,
      characterAnchorTags: character.anchorTags,
      stripRealisticMediumTags: stripRealisticMediumTags,
    ),
    'negativePrompt': joinArtistChainV5PromptParts([
      defaultUC,
      ...artistChainV5NegativeTerms,
      if (stripRealisticMediumTags) ...artistChainV5MediumNegativeTerms,
    ]),
    'outputPath': _join(
      outputDirectory,
      '${_safeFilePart(chain.id)}-v5-test-r3-strong-quality-'
      'attempt$attempt-${_defaultWidth}x$_defaultHeight-seed$seed.png',
    ),
    'requestPayloadManifestPath': requestPayloadManifestPath,
    'model': _defaultModel,
    'width': _defaultWidth,
    'height': _defaultHeight,
    'steps': _defaultSteps,
    'scale': _defaultScale,
    'sampler': _defaultSampler,
    'cfg_rescale': _defaultCfgRescale,
    'quality_preset': 'standard',
    'uc_preset_mode': 'heavy',
    'seed': seed,
    'replaceV5': true,
  };
}

String _safeFilePart(String value) {
  final normalized = value
      .trim()
      .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^[-.]+|[-.]+$'), '');
  return normalized.isEmpty ? 'artist-chain' : normalized;
}

String _join(String directory, String fileName) {
  return '$directory${Platform.pathSeparator}$fileName';
}

class _Options {
  final String workspacePath;
  final String outputDirectory;
  final int limit;
  final int seed;
  final int attempts;
  final bool stripRealisticMediumTags;

  const _Options({
    required this.workspacePath,
    required this.outputDirectory,
    required this.limit,
    required this.seed,
    required this.attempts,
    required this.stripRealisticMediumTags,
  });

  factory _Options.parse(List<String> args) {
    var workspacePath = _defaultWorkspace;
    String? outputDirectory;
    var limit = 25;
    var seed = _defaultSeed;
    var attempts = 2;
    var stripRealisticMediumTags = true;
    for (final arg in args) {
      if (arg.startsWith('--workspace=')) {
        workspacePath = arg.substring('--workspace='.length);
      } else if (arg.startsWith('--output-dir=')) {
        outputDirectory = arg.substring('--output-dir='.length);
      } else if (arg.startsWith('--limit=')) {
        limit = int.tryParse(arg.substring('--limit='.length)) ?? limit;
      } else if (arg.startsWith('--seed=')) {
        seed = int.tryParse(arg.substring('--seed='.length)) ?? seed;
      } else if (arg.startsWith('--attempts=')) {
        attempts =
            int.tryParse(arg.substring('--attempts='.length)) ?? attempts;
      } else if (arg == '--keep-medium') {
        stripRealisticMediumTags = false;
      }
    }
    final effectiveOutputDirectory = outputDirectory ??
        _join(
          workspacePath,
          'assets${Platform.pathSeparator}references'
          '${Platform.pathSeparator}artist-chain-v5-previews',
        );
    return _Options(
      workspacePath: workspacePath,
      outputDirectory: effectiveOutputDirectory,
      limit: limit < 1 ? 1 : limit,
      seed: seed,
      attempts: attempts < 1 ? 1 : attempts,
      stripRealisticMediumTags: stripRealisticMediumTags,
    );
  }
}

final class _RawArtistChain {
  final String id;
  final String name;
  final List<String> tags;
  final String prompt;
  final List<String> styleTags;
  final List<_RawArtistEntry> artists;
  final List<_RawWeightedTag> styleHintsWeighted;

  const _RawArtistChain({
    required this.id,
    required this.name,
    required this.tags,
    required this.prompt,
    required this.styleTags,
    required this.artists,
    required this.styleHintsWeighted,
  });

  factory _RawArtistChain.fromJson(Map<String, dynamic> json) {
    return _RawArtistChain(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      tags: _stringList(json['tags']),
      prompt: json['prompt']?.toString() ?? '',
      styleTags: [
        if (json['styleTags'] is List)
          ...(json['styleTags'] as List).whereType<String>(),
      ],
      artists: [
        if (json['artists'] is List)
          for (final entry in json['artists'])
            if (entry is Map)
              _RawArtistEntry.fromJson(entry.cast<String, dynamic>()),
      ],
      styleHintsWeighted: [
        if (json['styleHintsWeighted'] is List)
          for (final entry in json['styleHintsWeighted'])
            if (entry is Map)
              _RawWeightedTag.fromJson(entry.cast<String, dynamic>()),
      ],
    );
  }

  bool get hasRealisticMediumTags {
    return artistChainV5HasRealisticMediumTags(promptArtistTerms);
  }

  Iterable<String> get promptArtistTerms sync* {
    if (artists.isNotEmpty) {
      yield* artists.map((artist) => artist.tag);
      yield* artistChainV5NonArtistPromptTerms(prompt);
    } else {
      yield* tags;
      yield prompt;
    }
    yield* styleTags;
    yield* styleHintsWeighted.map((tag) => tag.formatted);
  }
}

final class _RawArtistEntry {
  final String name;
  final String prefix;
  final double weight;

  const _RawArtistEntry({
    required this.name,
    required this.prefix,
    required this.weight,
  });

  factory _RawArtistEntry.fromJson(Map<String, dynamic> json) {
    final weight = json['weight'];
    return _RawArtistEntry(
      name: json['name']?.toString() ?? '',
      prefix: json['prefix']?.toString() ?? 'artist:',
      weight: weight is num ? weight.toDouble() : 1,
    );
  }

  String get tag => weight == 1
      ? '$prefix$name'
      : PromptTagProcessor.formatInlineWeightTag('$prefix$name', weight);
}

final class _RawWeightedTag {
  final String tag;
  final double weight;

  const _RawWeightedTag({required this.tag, required this.weight});

  factory _RawWeightedTag.fromJson(Map<String, dynamic> json) {
    final weight = json['weight'];
    return _RawWeightedTag(
      tag: json['tag']?.toString() ?? '',
      weight: weight is num ? weight.toDouble() : 1,
    );
  }

  String get formatted =>
      weight == 1 ? tag : PromptTagProcessor.formatInlineWeightTag(tag, weight);
}

final class _RawCharacterCard {
  final String id;
  final String name;
  final String frontFull;
  final List<String> identityTags;
  final List<String> anchorTags;

  const _RawCharacterCard({
    required this.id,
    required this.name,
    required this.frontFull,
    required this.identityTags,
    required this.anchorTags,
  });

  factory _RawCharacterCard.fromJson(Map<String, dynamic> json) {
    final traits = json['traits'] is Map
        ? (json['traits'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    return _RawCharacterCard(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      frontFull: traits['front_full']?.toString() ?? '',
      identityTags: _stringList(json['identityTags']),
      anchorTags: _stringList(json['anchorTags']),
    );
  }

  String get prompt => buildArtistChainV5PromptCardSummary(
        name: name,
        frontFull: frontFull,
        identityTags: identityTags,
        anchorTags: anchorTags,
      );
}

List<String> _stringList(dynamic value) {
  if (value is! List) return const [];
  return [
    for (final entry in value)
      if (entry is String) entry
  ];
}

String buildArtistChainV5PromptCardSummary({
  required String name,
  required String frontFull,
  required List<String> identityTags,
  required List<String> anchorTags,
}) {
  final parts = <String>[
    name,
    frontFull,
    ...identityTags,
    ...anchorTags,
  ];
  return joinArtistChainV5PromptParts(parts);
}
