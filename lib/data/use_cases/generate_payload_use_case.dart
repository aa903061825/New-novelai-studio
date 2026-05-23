import 'package:easy_localization/easy_localization.dart';
import 'package:nai_casrand/data/models/character_config.dart';
import 'package:nai_casrand/data/models/param_config.dart';
import 'package:nai_casrand/data/models/payload_config.dart';
import 'package:nai_casrand/data/models/precise_reference_config.dart';
import 'package:nai_casrand/data/models/prompt_config.dart';
import 'package:nai_casrand/data/models/prompt_replace_rule.dart';
import 'package:nai_casrand/data/models/vibe_config.dart';
import 'package:nai_casrand/data/models/vibe_config_v4.dart';

const Map<int, String> xMapping = {
  0: 'X',
  1: 'A',
  2: 'B',
  3: 'C',
  4: 'D',
  5: 'E',
};

const Map<int, double> doubleMapping = {
  0: 0.0,
  1: 0.1,
  2: 0.3,
  3: 0.5,
  4: 0.7,
  5: 0.9
};

final RegExp _numericShellPattern = RegExp(r'^([+-]?\d+(?:\.\d+)?)::(.*)::$');

class PromptCommentPair {
  String prompt;
  String comment;

  PromptCommentPair({
    required this.prompt,
    required this.comment,
  });
}

class PayloadGenerationResult {
  Map<String, dynamic> payload;
  String comment;
  String suggestedFileName;
  String? contentOrderText;

  PayloadGenerationResult({
    required this.payload,
    required this.comment,
    required this.suggestedFileName,
    this.contentOrderText,
  });
}

class _WeightShell {
  final String open;
  final String close;

  const _WeightShell({
    required this.open,
    required this.close,
  });
}

class _ParsedTag {
  final String raw;
  final String trimmed;
  final String comparable;
  final _WeightShell? shell;

  const _ParsedTag({
    required this.raw,
    required this.trimmed,
    required this.comparable,
    required this.shell,
  });
}

class _ParsedShell {
  final String core;
  final _WeightShell? shell;

  const _ParsedShell({
    required this.core,
    required this.shell,
  });
}

class GeneratePayloadUseCase {
  final PayloadConfig payloadConfig;

  GeneratePayloadUseCase({
    required this.payloadConfig,
  });

  ParamConfig get paramConfig => payloadConfig.paramConfig;
  PromptConfig get rootPromptConfig => payloadConfig.rootPromptConfig;
  List<CharacterConfig> get characterConfigList =>
      payloadConfig.characterConfigList;
  List<PromptConfig> get savedConfigList => payloadConfig.savedPromptConfigList;
  List<PromptReplaceRule> get promptReplaceRules =>
      payloadConfig.promptReplaceRules;
  List<VibeConfig> get vibeConfigList => payloadConfig.vibeConfigList;
  List<VibeConfigV4> get vibeConfigV4List => payloadConfig.vibeConfigListV4;
  List<PreciseReferenceConfig> get preciseReferenceList =>
      payloadConfig.preciseReferenceList;
  String get fileNameKey => payloadConfig.settings.fileNamePrefixKey;
  bool get vibeEnabled => payloadConfig.generationRuntimeState.vibeEnabled;

  PayloadGenerationResult call() {
    final pattern = RegExp(
      r'__([\p{L}0-9_\-（）().\u4e00-\u9fff\uff00-\uffef]+?)__',
      unicode: true,
    );

    // Get prompt
    final NestedPrompt basePromptResult;
    if (payloadConfig.useOverridePrompt) {
      basePromptResult = NestedPromptString(
        title: tr('override_prompt'),
        content: payloadConfig.overridePrompt,
      );
    } else {
      basePromptResult = rootPromptConfig
          .getPrmpts()
          .replaceVariables(pattern, savedConfigList);
    }
    final basePair = PromptCommentPair(
      prompt: _applyPromptReplaceRules(basePromptResult.toPrompt()),
      comment: _applyPromptReplaceRules(basePromptResult.toComment(),
          isComment: true),
    );
    final effectiveParamConfig =
        payloadConfig.globalGenerationParams.resolveParamConfig(paramConfig);
    final paramPayload = effectiveParamConfig.getPayload();
    String payloadComment = basePair.comment;

    // Get character prompt
    final List<CharacterPromptResult> characterPromptResultList = [];
    if (!payloadConfig.useOverridePrompt ||
        payloadConfig.useCharacterPromptWithOverride) {
      for (final config in characterConfigList) {
        if (!config.enabled) continue;
        characterPromptResultList.add(config.getPrompt());
      }
    }

    // Character prompts
    final characterPrompts = [];
    final v4CharPosCaptions = [];
    final v4CharNegCaptions = [];
    for (final (index, result) in characterPromptResultList.indexed) {
      final posAsString = '${xMapping[result.center.x]}${result.center.y}';
      final posAsDouble = {
        'x': doubleMapping[result.center.x]!,
        'y': doubleMapping[result.center.y]!,
      };
      result.prompt = result.prompt.replaceVariables(pattern, savedConfigList);
      final rawCharacterPrompt = result.prompt.toPrompt();
      if (_isCharacterPromptPlaceholder(rawCharacterPrompt)) {
        continue;
      }
      final characterPair = PromptCommentPair(
        prompt: _applyPromptReplaceRules(rawCharacterPrompt),
        comment: _applyPromptReplaceRules(result.prompt.toComment(),
            isComment: true),
      );
      // characterPair.processPair(savedConfigList);
      payloadComment +=
          '\n\nCharacter#$index at $posAsString:\n${characterPair.comment}';
      characterPrompts.add({
        'prompt': characterPair.prompt,
        'uc': result.uc,
        'center': posAsDouble,
      });
      v4CharPosCaptions.add({
        'char_caption': characterPair.prompt,
        'centers': [posAsDouble],
      });
      v4CharNegCaptions.add({
        'char_caption': result.uc,
        'centers': [posAsDouble],
      });
    }
    final v4Prompt = {
      'caption': {
        'base_caption': basePair.prompt,
        'char_captions': v4CharPosCaptions,
      },
      'use_coords': !effectiveParamConfig.autoPosition,
      'use_order': true,
    };
    final v4NegPrompt = {
      'caption': {
        'base_caption': effectiveParamConfig.negativePrompt,
        'char_captions': v4CharNegCaptions,
      },
      'legacy_uc': effectiveParamConfig.legacyUc,
    };
    paramPayload['v4_prompt'] = v4Prompt;
    paramPayload['v4_negative_prompt'] = v4NegPrompt;
    paramPayload['characterPrompts'] = characterPrompts;

    final isV45Model = effectiveParamConfig.model.contains('-4-5-');
    final usePreciseReference = payloadConfig.usePreciseReference &&
        isV45Model &&
        preciseReferenceList.isNotEmpty;

    if (usePreciseReference) {
      final imageB64List = [];
      final referenceStrengthList = [];
      final referenceSecondaryStrengthList = [];
      final referenceInfoExtractedList = [];
      final referenceDescriptionsList = [];

      for (final ref in preciseReferenceList) {
        final safeType = switch (ref.type) {
          'character' => 'character',
          'style' => 'style',
          _ => 'character&style',
        };
        final strength = ref.strength.clamp(0.0, 1.0);
        final fidelity = ref.fidelity.clamp(0.0, 1.0);

        imageB64List.add(ref.imageB64);
        referenceStrengthList.add(strength);
        referenceSecondaryStrengthList.add(1.0 - fidelity);
        referenceInfoExtractedList.add(1.0);
        referenceDescriptionsList.add({
          'caption': {
            'base_caption': safeType,
            'char_captions': [],
          },
          'legacy_uc': false,
        });
      }

      paramPayload['director_reference_images'] = imageB64List;
      paramPayload['director_reference_strength_values'] =
          referenceStrengthList;
      paramPayload['director_reference_secondary_strength_values'] =
          referenceSecondaryStrengthList;
      paramPayload['director_reference_information_extracted'] =
          referenceInfoExtractedList;
      paramPayload['director_reference_descriptions'] =
          referenceDescriptionsList;

      // Keep Precise Reference and Vibe Transfer mutually exclusive.
      paramPayload.remove('reference_image_multiple');
      paramPayload.remove('reference_strength_multiple');
      paramPayload.remove('reference_information_extracted_multiple');
    } else if (vibeEnabled && effectiveParamConfig.model.contains('-3')) {
      // Vibe config for NAI3 models
      final imageB64List = [];
      final referenceStrengthList = [];
      final imformationExtractedList = [];
      for (final vc in vibeConfigList) {
        imageB64List.add(vc.imageB64);
        referenceStrengthList.add(vc.referenceStrength);
        imformationExtractedList.add(vc.infoExtracted);
      }
      paramPayload['reference_image_multiple'] = imageB64List;
      paramPayload['reference_strength_multiple'] = referenceStrengthList;
      paramPayload['reference_information_extracted_multiple'] =
          imformationExtractedList;
    } else if (vibeEnabled && effectiveParamConfig.model.contains('-4-')) {
      // Vibe config for NAI4 models
      final imageB64List = [];
      final infoExtractedList = [];
      final referenceStrengthList = [];
      for (final vc in vibeConfigV4List) {
        imageB64List.add(vc.vibeB64);
        referenceStrengthList.add(vc.referenceStrength);
        infoExtractedList.add(1.0);
      }
      paramPayload['reference_image_multiple'] = imageB64List;
      paramPayload['reference_strength_multiple'] = referenceStrengthList;
      paramPayload['reference_information_extracted_multiple'] =
          infoExtractedList;
    } else if (!vibeEnabled) {
      paramPayload.remove('reference_image_multiple');
      paramPayload.remove('reference_strength_multiple');
      paramPayload.remove('reference_information_extracted_multiple');
    }

    final processedFileName = _applyPromptReplaceRules(
      _processFileNameKey(fileNameKey, basePromptResult),
    );
    final contentOrderIndexes = basePromptResult.metadata.contentOrderIndexes;
    final contentOrderText =
        contentOrderIndexes.isEmpty ? null : contentOrderIndexes.join(',');

    return PayloadGenerationResult(
      comment: payloadComment,
      suggestedFileName: processedFileName,
      contentOrderText: contentOrderText,
      payload: {
        'input': basePair.prompt,
        'model': effectiveParamConfig.model,
        'action': 'generate',
        'parameters': paramPayload,
      },
    );
  }

  String _processFileNameKey(
    String rawKey,
    NestedPrompt prompt,
  ) {
    return rawKey.replaceAllMapped(
      // 允许Unicode字符
      RegExp(
        r'__([\p{L}0-9_\-（）().\u4e00-\u9fff\uff00-\uffef]+?)__',
        unicode: true,
      ),
      (match) =>
          prompt.findPromptWithKey(match[1].toString()) ?? '__${match[1]}__',
    );
  }

  bool _isCharacterPromptPlaceholder(String prompt) {
    final trimmed = prompt.trim();
    return trimmed == ',' || trimmed == '，';
  }

  String _applyPromptReplaceRules(String input, {bool isComment = false}) {
    var output = input;
    for (final rule in promptReplaceRules) {
      if (!rule.enabled) continue;
      if (_isGroupedReplaceSource(rule.source)) {
        output = isComment
            ? _applyGroupedRuleToComment(output, rule)
            : _applyGroupedRuleToTagList(output, rule);
        continue;
      }
      output = isComment
          ? _applySingleRuleToComment(output, rule)
          : _applySinglePromptReplaceRule(output, rule);
    }
    return output;
  }

  String _applySinglePromptReplaceRule(String input, PromptReplaceRule rule) {
    final source = rule.source.trim();
    if (source.isEmpty) return input;
    final normalizedTokens = source
        .split(RegExp(r'\s+', unicode: true))
        .where((token) => token.isNotEmpty)
        .map(RegExp.escape)
        .toList();
    if (normalizedTokens.isEmpty) return input;
    final sourcePattern = RegExp(
      normalizedTokens.join(r'\s+'),
      unicode: true,
      caseSensitive: false,
    );
    final output = input.replaceAll(sourcePattern, rule.target);
    if (rule.target.isNotEmpty) {
      return output;
    }
    return _cleanWhitespaceAfterDeletion(output);
  }

  bool _isGroupedReplaceSource(String source) {
    return source.contains(',') || source.contains('，');
  }

  String _applySingleRuleToComment(String input, PromptReplaceRule rule) {
    return _applyRuleToComment(
      input,
      (value) => _applySinglePromptReplaceRule(value, rule),
    );
  }

  String _applyGroupedRuleToComment(String input, PromptReplaceRule rule) {
    return _applyRuleToComment(
      input,
      (value) => _applyGroupedRuleToTagList(value, rule),
    );
  }

  String _applyRuleToComment(
    String input,
    String Function(String value) replaceValue,
  ) {
    final lines = input.split('\n');
    final updatedLines = lines.map((line) {
      final colonIndex = line.indexOf(':');
      if (colonIndex == -1) {
        return line;
      }

      final prefix = line.substring(0, colonIndex + 1);
      final value = line.substring(colonIndex + 1);
      final leadingWhitespaceMatch = RegExp(r'^\s*').firstMatch(value);
      final leadingWhitespace = leadingWhitespaceMatch?.group(0) ?? '';
      final content = value.substring(leadingWhitespace.length);
      final replacedValue = replaceValue(content);

      if (replacedValue == content) {
        return line;
      }

      if (replacedValue.isEmpty) {
        return '$prefix$leadingWhitespace';
      }

      return '$prefix$leadingWhitespace$replacedValue';
    }).toList();

    return updatedLines.join('\n');
  }

  String _applyGroupedRuleToTagList(String input, PromptReplaceRule rule) {
    final candidates = _splitCommaSeparatedValues(rule.source)
        .map(_parseTag)
        .map((tag) => _normalizeComparableTag(tag.comparable))
        .where((tag) => tag.isNotEmpty)
        .toSet();
    if (candidates.isEmpty) {
      return input;
    }

    final promptTags =
        _splitCommaSeparatedValues(input).map(_parseTag).toList();
    if (promptTags.isEmpty) {
      return input;
    }

    final matchedIndexes = <int>[];
    for (final (index, tag) in promptTags.indexed) {
      if (_tagMatchesCandidates(tag, candidates)) {
        matchedIndexes.add(index);
      }
    }

    if (matchedIndexes.isEmpty) {
      return input;
    }

    final anchorIndex = matchedIndexes.first;
    final matchedIndexSet = matchedIndexes.toSet();
    final target = _buildGroupedReplacementTarget(
      rule.target,
      anchor: promptTags[anchorIndex],
    );
    final outputTags = <String>[];

    for (final (index, tag) in promptTags.indexed) {
      if (!matchedIndexSet.contains(index)) {
        outputTags.add(tag.trimmed);
        continue;
      }

      if (index == anchorIndex && target.isNotEmpty) {
        outputTags.add(target);
      }
    }

    return outputTags.join(', ');
  }

  String _cleanWhitespaceAfterDeletion(String input) {
    return input.replaceAll(RegExp(r'\s+', unicode: true), ' ').trim();
  }

  String _normalizeComparableTag(String value) {
    return value
        .trim()
        .replaceAll(RegExp(r'^[:：;；]+|[:：;；]+$'), '')
        .trim()
        .toLowerCase();
  }

  bool _tagMatchesCandidates(_ParsedTag tag, Set<String> candidates) {
    final comparable = _normalizeComparableTag(tag.comparable);
    if (candidates.contains(comparable)) {
      return true;
    }

    final innerTags = _splitCommaSeparatedValues(tag.comparable);
    if (innerTags.length <= 1) {
      return false;
    }

    return innerTags
        .map(_parseTag)
        .map((innerTag) => _normalizeComparableTag(innerTag.comparable))
        .any(candidates.contains);
  }

  List<String> _splitCommaSeparatedValues(String input) {
    final values = <String>[];
    final buffer = StringBuffer();
    var index = 0;
    String? protectedClose;

    void flushBuffer() {
      final value = buffer.toString().trim();
      if (value.isNotEmpty) {
        values.add(value);
      }
      buffer.clear();
    }

    while (index < input.length) {
      if (protectedClose != null) {
        if (input.startsWith(protectedClose, index)) {
          buffer.write(protectedClose);
          index += protectedClose.length;
          protectedClose = null;
          continue;
        }

        buffer.write(input[index]);
        index += 1;
        continue;
      }

      final weightedShellStart = _detectWeightedShellStart(
        input,
        index,
        currentToken: buffer.toString(),
      );
      if (weightedShellStart != null) {
        buffer.write(input.substring(index, weightedShellStart.afterOpen));
        index = weightedShellStart.afterOpen;
        protectedClose = weightedShellStart.close;
        continue;
      }

      final char = input[index];
      if (char == ',' || char == '，') {
        flushBuffer();
        index += 1;
        continue;
      }

      buffer.write(char);
      index += 1;
    }

    flushBuffer();
    return values;
  }

  ({int afterOpen, String close})? _detectWeightedShellStart(
    String input,
    int index, {
    required String currentToken,
  }) {
    if (currentToken.trim().isNotEmpty) {
      return null;
    }

    var cursor = index;
    var close = '::';
    if (input.startsWith('{{', cursor)) {
      cursor += 2;
      close = '::}}';
    } else if (input.startsWith('{', cursor)) {
      cursor += 1;
      close = '::}';
    }

    final match = RegExp(r'[+-]?\d+(?:\.\d+)?::').matchAsPrefix(
      input.substring(cursor),
    );
    if (match == null) {
      return null;
    }

    return (afterOpen: cursor + match.end, close: close);
  }

  _ParsedTag _parseTag(String raw) {
    final trimmed = raw.trim();
    final parsedShell = _parseShell(trimmed);
    return _ParsedTag(
      raw: raw,
      trimmed: trimmed,
      comparable: parsedShell.core,
      shell: parsedShell.shell,
    );
  }

  _ParsedShell _parseShell(String value) {
    final trimmed = value.trim();
    if (trimmed.startsWith('{{') &&
        trimmed.endsWith('}}') &&
        trimmed.length >= 4) {
      return _parseBracedShell(
        trimmed,
        open: '{{',
        close: '}}',
      );
    }

    if (trimmed.startsWith('{') &&
        trimmed.endsWith('}') &&
        !trimmed.startsWith('{{') &&
        !trimmed.endsWith('}}') &&
        trimmed.length >= 2) {
      return _parseBracedShell(
        trimmed,
        open: '{',
        close: '}',
      );
    }

    final numericMatch = _numericShellPattern.firstMatch(trimmed);
    if (numericMatch != null) {
      final weight = numericMatch.group(1);
      return _ParsedShell(
        core: numericMatch.group(2)?.trim() ?? '',
        shell: weight == null || weight.isEmpty
            ? null
            : _WeightShell(open: '$weight::', close: '::'),
      );
    }

    return _ParsedShell(core: trimmed, shell: null);
  }

  _ParsedShell _parseBracedShell(
    String value, {
    required String open,
    required String close,
  }) {
    final inner =
        value.substring(open.length, value.length - close.length).trim();
    final numericMatch = _numericShellPattern.firstMatch(inner);
    if (numericMatch != null) {
      final weight = numericMatch.group(1);
      return _ParsedShell(
        core: numericMatch.group(2)?.trim() ?? '',
        shell: weight == null || weight.isEmpty
            ? _WeightShell(open: open, close: close)
            : _WeightShell(open: '$open$weight::', close: '::$close'),
      );
    }

    return _ParsedShell(
      core: inner,
      shell: _WeightShell(open: open, close: close),
    );
  }

  bool _hasRecognizedShell(String value) {
    return _parseShell(value).shell != null;
  }

  String _applyShell(String target, _WeightShell shell) {
    return '${shell.open}${target.trim()}${shell.close}';
  }

  String _buildGroupedReplacementTarget(String target,
      {required _ParsedTag anchor}) {
    final trimmedTarget = target.trim();
    if (trimmedTarget.isEmpty) {
      return '';
    }

    if (_hasRecognizedShell(trimmedTarget)) {
      return trimmedTarget;
    }

    final shell = anchor.shell;
    if (shell != null) {
      return _applyShell(trimmedTarget, shell);
    }

    return trimmedTarget;
  }
}
