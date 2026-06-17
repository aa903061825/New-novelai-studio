import 'package:novel_studio/data/studio/tools/filter_rule_config.dart';

class FilterTagsResult {
  final List<String> clean;
  final List<String> deleted;
  final List<String> quantity;

  const FilterTagsResult({
    required this.clean,
    required this.deleted,
    required this.quantity,
  });
}

class HeuristicBuckets {
  final List<String> scene;
  final List<String> artist;
  final List<String> style;
  final List<String> quality;
  final List<String> character;
  final List<String> deleted;

  const HeuristicBuckets({
    required this.scene,
    required this.artist,
    required this.style,
    required this.quality,
    required this.character,
    required this.deleted,
  });
}

enum WorkshopTagWarning { none, suspectedMissingComma }

class WorkshopTagAnalysis {
  final String text;
  final String displayText;
  final double? weight;
  final WorkshopTagWarning warning;
  final List<String> suggestedParts;

  const WorkshopTagAnalysis({
    required this.text,
    String? displayText,
    this.weight,
    this.warning = WorkshopTagWarning.none,
    this.suggestedParts = const [],
  }) : displayText = displayText ?? text;

  String? get weightLabel {
    final value = weight;
    if (value == null) {
      return null;
    }
    return 'x${value.toStringAsFixed(2)}';
  }
}

class PromptTagDescriptor {
  final String rawText;
  final String displayText;
  final double? weight;

  const PromptTagDescriptor({
    required this.rawText,
    required this.displayText,
    this.weight,
  });

  String? get weightLabel {
    final value = weight;
    if (value == null) {
      return null;
    }
    return 'x${value.toStringAsFixed(2)}';
  }
}

class PromptTagProcessor {
  static const double _bracketWeightStep = 1.05;
  static final RegExp _inlineWeight = RegExp(
    r'^\s*([-+]?\d*\.?\d+)::(.*?)(?:::\s*)?$',
  );
  static final RegExp _sdWeight = RegExp(r'^\((.*):\s*([-+]?\d*\.?\d+)\)$');
  static final RegExp _ruleSplit = RegExp(r'[,，\n]');
  static final RegExp _weightStart = RegExp(r'^\s*([-+]?\d*\.?\d+)::(.*)$');
  static final RegExp _weightEnd = RegExp(r'^(.*?)(\s*::)\s*$');
  static final RegExp _quantityPattern = RegExp(
    r'^(\d+(girl|boy|male|female)s?|solo|multiple (girls|boys)|absurdres|highres)$',
    caseSensitive: false,
  );
  static final RegExp _artistPattern = RegExp(
    r'artist\s*:',
    caseSensitive: false,
  );
  static final Set<String> _qualityWords = {
    'masterpiece',
    'best quality',
    'high quality',
    'amazing quality',
    'very aesthetic',
    'highres',
    'absurdres',
    'uhd',
    'newest',
    'ultra detailed',
    'official art',
  };
  static final Set<String> _styleHints = {
    'watercolor',
    'ink',
    'sketch',
    'lineart',
    'monochrome',
    'anime',
    'manga',
    'realistic',
    'photorealistic',
    'chibi',
    'cg',
    'cgi',
    '3d',
    '2d',
    'soft shading',
    'flat color',
    'vibrant color',
    'muted color',
    'chiaroscuro',
    'cinematic lighting',
  };
  static const List<String> _artistPrefixes = ['artist:', 'artis:', 'artsit:'];
  static const Set<String> _knownCompoundTags = {
    'best quality',
    'high quality',
    'amazing quality',
    'very aesthetic',
    'ultra detailed',
    'official art',
    'soft shading',
    'flat color',
    'vibrant color',
    'muted color',
    'cinematic lighting',
    'blue eyes',
    'red eyes',
    'green eyes',
    'yellow eyes',
    'long hair',
    'short hair',
    'white hair',
    'black hair',
    'simple background',
    'white background',
    'depth of field',
    'looking at viewer',
    'open mouth',
    'closed mouth',
    'cat ears',
  };
  static const Set<String> _standaloneTags = {
    'male',
    'female',
    'boy',
    'girl',
    'blush',
    'standing',
    'sitting',
    'walking',
    'running',
    'smile',
    'close-up',
    'portrait',
    'solo',
  };

  static List<ReplaceRule> parseReplaceRulesText(String? text) {
    final rules = <ReplaceRule>[];
    for (final line in (text ?? '').split('\n')) {
      if (!line.contains('->')) {
        continue;
      }
      final parts = line.split('->');
      final oldValue = parts.first.trim();
      final newValue = parts.skip(1).join('->').trim();
      if (oldValue.isEmpty) {
        continue;
      }
      rules.add(ReplaceRule(oldValue, newValue));
    }
    return rules;
  }

  static String fixMissingCommas(String text) {
    return text.replaceAllMapped(
      RegExp(r'(::)\s+(?=[-+]?\d*\.?\d+::)'),
      (match) => '${match.group(1)}, ',
    );
  }

  static String repairWorkshopDelimiters(String text) {
    return fixMissingCommas(text).replaceAllMapped(
      RegExp(r'(^|[^-+\d.])::\s+(?=[^,，\n\s])'),
      (match) => '${match.group(1)}, ',
    );
  }

  static String stripWeightMarkers(String text) {
    var cleanText = text.replaceAll('\n', ' ').replaceAll('\r', ' ').trim();
    cleanText = cleanText.replaceFirst(RegExp(r'^\s*[-+]?\d*\.?\d+::'), '');
    cleanText = cleanText.replaceFirst(RegExp(r'\s*::\s*$'), '');
    cleanText = cleanText.replaceFirst(
      RegExp(r'\s*:\s*[-+]?\d*\.?\d+\s*$'),
      '',
    );
    return cleanText.trim();
  }

  static String cleanTagPure(String text) {
    final lowered =
        text.replaceAll(RegExp(r'[{}\[\]\(\)]+'), ' ').toLowerCase();
    return stripWeightMarkers(lowered);
  }

  static String normalizeMatchKey(String text) {
    return cleanTagPure(text).replaceAll(RegExp(r'[\s_]+'), ' ').trim();
  }

  static String cleanTagDisplay(String text, {bool removeWeights = true}) {
    var cleanText = text.replaceAll('\n', ' ').replaceAll('\r', ' ');
    if (!removeWeights) {
      return cleanText.trim();
    }
    cleanText = cleanText.replaceAll(RegExp(r'[{}\[\]]'), '');
    return stripWeightMarkers(cleanText);
  }

  static List<String> splitWorkshopTags(
    String text, {
    bool splitSpace = false,
  }) {
    if (!splitSpace) {
      return [
        for (final tag in analyzeWorkshopTags(text))
          _materializeWorkshopTag(tag),
      ];
    }

    final separator = RegExp(r'[ ,，\n]');
    return repairWorkshopDelimiters(text)
        .split(separator)
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
  }

  static String _materializeWorkshopTag(WorkshopTagAnalysis tag) {
    final raw = tag.text.trim();
    final weight = tag.weight;
    if (weight == null) {
      return raw;
    }
    if (hasCompleteNonInlineWeightSyntax(raw)) {
      return raw;
    }
    final display = tag.displayText.trim();
    if (display.isEmpty) {
      return raw;
    }
    return formatInlineWeightTag(display, weight);
  }

  static String formatInlineWeightTag(String tag, double weight) {
    return '${_formatPromptWeight(weight)}:: ${tag.trim()} ::';
  }

  static bool hasCompleteNonInlineWeightSyntax(String tag) {
    final value = tag.trim();
    return RegExp(r'^\(.+:\s*[-+]?\d*\.?\d+\)$').hasMatch(value) ||
        (value.length >= 2 &&
            ((value.startsWith('{') && value.endsWith('}')) ||
                (value.startsWith('[') && value.endsWith(']'))));
  }

  static String _formatPromptWeight(double weight) {
    final text = weight.toStringAsFixed(6);
    return text.replaceFirst(RegExp(r'\.?0+$'), '');
  }

  static List<WorkshopTagAnalysis> analyzeWorkshopTags(
    String text, {
    bool splitSpace = false,
  }) {
    if (!splitSpace) {
      final analyses = <WorkshopTagAnalysis>[];
      for (final segment in _splitWeightedSegments(
        repairWorkshopDelimiters(text),
      )) {
        if (!segment.isWeighted) {
          analyses.add(_analyzeWorkshopTag(segment.text));
          continue;
        }
        final inheritedWeight = _parseWeightPrefix(segment.prefix);
        for (final (index, item) in segment.items.indexed) {
          var rawText = item;
          if (index == 0) {
            rawText = '${segment.prefix}$rawText';
          }
          if (index == segment.items.length - 1) {
            rawText = '$rawText${segment.suffix}';
          }
          analyses.add(
            _analyzeWorkshopTag(
              item,
              inheritedWeight: inheritedWeight,
              rawText: rawText,
            ),
          );
        }
      }
      return analyses;
    }
    return [
      for (final tag in splitWorkshopTags(text, splitSpace: splitSpace))
        _analyzeWorkshopTag(tag),
    ];
  }

  static WorkshopTagAnalysis _analyzeWorkshopTag(
    String tag, {
    double? inheritedWeight,
    String? rawText,
  }) {
    final descriptor = describeWorkshopTag(
      tag,
      inheritedWeight: inheritedWeight,
    );
    final normalized = normalizeMatchKey(descriptor.displayText);
    if (_knownCompoundTags.contains(normalized)) {
      return WorkshopTagAnalysis(
        text: rawText ?? tag,
        displayText: descriptor.displayText,
        weight: descriptor.weight,
      );
    }
    final parts = normalized.split(RegExp(r'\s+'));
    if (parts.length == 2 && parts.every(_standaloneTags.contains)) {
      return WorkshopTagAnalysis(
        text: rawText ?? tag,
        displayText: descriptor.displayText,
        weight: descriptor.weight,
        warning: WorkshopTagWarning.suspectedMissingComma,
        suggestedParts: parts,
      );
    }
    return WorkshopTagAnalysis(
      text: rawText ?? tag,
      displayText: descriptor.displayText,
      weight: descriptor.weight,
    );
  }

  static PromptTagDescriptor describeWorkshopTag(
    String text, {
    double? inheritedWeight,
  }) {
    var display = text.replaceAll('\n', ' ').replaceAll('\r', ' ').trim();
    var hasWeight = inheritedWeight != null;
    var weight = inheritedWeight ?? 1.0;

    final inlineMatch = _inlineWeight.firstMatch(display);
    if (inlineMatch != null) {
      final parsed = double.tryParse(inlineMatch.group(1) ?? '');
      if (parsed != null) {
        weight *= parsed;
        hasWeight = true;
        display = inlineMatch.group(2)?.trim() ?? display;
      }
    }

    final sdMatch = _sdWeight.firstMatch(display);
    if (sdMatch != null) {
      final parsed = double.tryParse(sdMatch.group(2) ?? '');
      if (parsed != null) {
        weight *= parsed;
        hasWeight = true;
        display = sdMatch.group(1)?.trim() ?? display;
      }
    }

    while (display.length >= 2 &&
        display.startsWith('{') &&
        display.endsWith('}')) {
      weight *= _bracketWeightStep;
      hasWeight = true;
      display = display.substring(1, display.length - 1).trim();
    }

    while (display.length >= 2 &&
        display.startsWith('[') &&
        display.endsWith(']')) {
      weight /= _bracketWeightStep;
      hasWeight = true;
      display = display.substring(1, display.length - 1).trim();
    }

    return PromptTagDescriptor(
      rawText: text,
      displayText: cleanTagDisplay(display),
      weight: hasWeight ? weight : null,
    );
  }

  static FilterTagsResult filterTags(
    String rawText, {
    FilterRuleConfig config = const FilterRuleConfig(),
  }) {
    final deleteSet = <String>{};
    final deleteContainsSet = <String>{};
    for (final word in _splitRuleWords(config.deleteKeywords)) {
      final hasWildcard = word.contains('*');
      final key = normalizeMatchKey(word.replaceAll('*', ' '));
      if (key.isEmpty) {
        continue;
      }
      if (hasWildcard) {
        deleteContainsSet.add(key);
      } else {
        deleteSet.add(key);
      }
    }

    final strongContainsSet = {
      for (final word in _splitRuleWords(config.strongFilterKeywords))
        if (normalizeMatchKey(word).isNotEmpty) normalizeMatchKey(word),
    };
    final replaceRules = parseReplaceRulesText(config.replaceRules);
    final cleanList = <String>[];
    final deletedList = <String>[];
    final quantityList = <String>[];

    TagDecision categorizeTag(String tag) {
      final replaced = _applyReplaceRules(tag, replaceRules);
      final pureCheck = cleanTagPure(replaced);
      final matchKey = normalizeMatchKey(replaced);

      for (final blocked in strongContainsSet) {
        if (matchKey.contains(blocked)) {
          return TagDecision(
            status: TagStatus.deleted,
            replaced: replaced,
            display: cleanTagDisplay(
              replaced,
              removeWeights: config.removeWeights,
            ),
          );
        }
      }

      if (_quantityPattern.hasMatch(pureCheck)) {
        return TagDecision(
          status: TagStatus.quantity,
          replaced: replaced,
          display: cleanTagDisplay(
            replaced,
            removeWeights: config.removeWeights,
          ),
        );
      }

      var isDeleted = deleteSet.contains(matchKey);
      if (!isDeleted) {
        final containsSet = config.exactMatch
            ? deleteContainsSet
            : {...deleteSet, ...deleteContainsSet};
        isDeleted = containsSet.any(matchKey.contains);
      }

      final display = cleanTagDisplay(
        replaced,
        removeWeights: config.removeWeights,
      );
      if (display.isEmpty) {
        return TagDecision(
          status: TagStatus.skip,
          replaced: replaced,
          display: display,
        );
      }

      final lowered = replaced.toLowerCase();
      if (config.deleteArtistTags &&
          _artistPrefixes.any((prefix) => lowered.contains(prefix))) {
        return TagDecision(
          status: TagStatus.deleted,
          replaced: replaced,
          display: '$display (artist)',
        );
      }
      if (isDeleted) {
        return TagDecision(
          status: TagStatus.deleted,
          replaced: replaced,
          display: display,
        );
      }
      return TagDecision(
        status: TagStatus.clean,
        replaced: replaced,
        display: display,
      );
    }

    for (final segment in _splitWeightedSegments(rawText)) {
      if (!segment.isWeighted) {
        final decision = categorizeTag(segment.text);
        _appendDecision(decision, cleanList, deletedList, quantityList);
        continue;
      }

      final keptItems = <String>[];
      for (final (index, item) in segment.items.indexed) {
        var fullTag = item;
        if (index == 0) {
          fullTag = '${segment.prefix}$fullTag';
        }
        if (index == segment.items.length - 1) {
          fullTag = '$fullTag${segment.suffix}';
        }
        final decision = categorizeTag(fullTag);
        if (decision.status == TagStatus.clean) {
          keptItems.add(stripWeightMarkers(decision.replaced));
        } else {
          _appendDecision(decision, cleanList, deletedList, quantityList);
        }
      }
      if (keptItems.isEmpty) {
        continue;
      }
      final rebuilt = _rebuildWeightedGroup(
        segment.prefix,
        keptItems,
        segment.suffix,
      );
      final display = cleanTagDisplay(
        rebuilt,
        removeWeights: config.removeWeights,
      );
      if (display.isNotEmpty) {
        cleanList.add(display);
      }
    }

    return FilterTagsResult(
      clean: List.unmodifiable(cleanList),
      deleted: List.unmodifiable(deletedList),
      quantity: List.unmodifiable(quantityList),
    );
  }

  static String heuristicBucket(String tag) {
    final value = stripWeightMarkers(tag).toLowerCase();
    if (_artistPattern.hasMatch(value)) {
      return 'Artist';
    }
    if (_qualityWords.any((term) => _containsHeuristicTerm(value, term))) {
      return 'Quality';
    }
    if (_styleHints.any((term) => _containsHeuristicTerm(value, term))) {
      return 'Style';
    }
    if (value.contains('(') &&
        value.contains(')') &&
        !value.contains('artist')) {
      return 'Character';
    }
    return 'Scene';
  }

  static bool _containsHeuristicTerm(String value, String term) {
    final cleanTerm = term.trim().toLowerCase();
    if (cleanTerm.isEmpty) {
      return false;
    }
    return RegExp(
      '(^|[^a-z0-9])${RegExp.escape(cleanTerm)}([^a-z0-9]|\$)',
    ).hasMatch(value);
  }

  static HeuristicBuckets heuristicSplit(
    String promptText, {
    FilterRuleConfig config = const FilterRuleConfig(),
  }) {
    final filtered = filterTags(promptText, config: config);
    final scene = <String>[
      for (final tag in filtered.quantity) ...splitWorkshopTags(tag),
    ];
    final artist = <String>[];
    final style = <String>[];
    final quality = <String>[];
    final character = <String>[];

    for (final tag in filtered.clean) {
      for (final splitTag in splitWorkshopTags(tag)) {
        switch (heuristicBucket(splitTag)) {
          case 'Artist':
            artist.add(splitTag);
          case 'Quality':
            quality.add(splitTag);
          case 'Style':
            style.add(splitTag);
          case 'Character':
            character.add(splitTag);
          default:
            scene.add(splitTag);
        }
      }
    }

    return HeuristicBuckets(
      scene: List.unmodifiable(scene),
      artist: List.unmodifiable(artist),
      style: List.unmodifiable(style),
      quality: List.unmodifiable(quality),
      character: List.unmodifiable(character),
      deleted: filtered.deleted,
    );
  }

  static Iterable<String> _splitRuleWords(String text) sync* {
    for (final word in text.split(_ruleSplit)) {
      final trimmed = word.trim();
      if (trimmed.isNotEmpty) {
        yield trimmed;
      }
    }
  }

  static List<PromptSegment> _splitWeightedSegments(String rawText) {
    final parts = rawText
        .split(_ruleSplit)
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty);
    final segments = <PromptSegment>[];
    PromptSegment? currentGroup;

    for (var part in parts) {
      if (currentGroup == null) {
        final startMatch = _weightStart.firstMatch(part);
        if (startMatch == null) {
          segments.add(PromptSegment.tag(part));
          continue;
        }
        currentGroup = PromptSegment.weighted(
          prefix: '${startMatch.group(1)}::',
          suffix: '::',
          items: [],
        );
        final inner = startMatch.group(2)?.trim() ?? '';
        if (inner.isEmpty) {
          continue;
        }
        part = inner;
      }

      final endMatch = _weightEnd.firstMatch(part);
      if (endMatch != null) {
        final inner = endMatch.group(1)?.trim() ?? '';
        if (inner.isNotEmpty) {
          currentGroup.items.add(inner);
        }
        currentGroup = PromptSegment.weighted(
          prefix: currentGroup.prefix,
          suffix: endMatch.group(2) ?? '::',
          items: currentGroup.items,
        );
        segments.add(currentGroup);
        currentGroup = null;
      } else {
        currentGroup.items.add(part);
      }
    }

    if (currentGroup != null) {
      final items = currentGroup.items;
      if (items.isEmpty) {
        segments.add(PromptSegment.tag(currentGroup.prefix));
      } else {
        segments.add(PromptSegment.tag('${currentGroup.prefix}${items.first}'));
        for (final item in items.skip(1)) {
          segments.add(PromptSegment.tag(item));
        }
      }
    }
    return segments;
  }

  static double? _parseWeightPrefix(String prefix) {
    final match = RegExp(r'^\s*([-+]?\d*\.?\d+)::').firstMatch(prefix);
    if (match == null) {
      return null;
    }
    return double.tryParse(match.group(1) ?? '');
  }

  static String _applyReplaceRules(String tag, List<ReplaceRule> rules) {
    var result = tag;
    for (final rule in rules) {
      result = result.replaceAll(
        RegExp(RegExp.escape(rule.oldValue), caseSensitive: false),
        rule.newValue,
      );
    }
    return result;
  }

  static String _rebuildWeightedGroup(
    String prefix,
    List<String> items,
    String suffix,
  ) {
    final weight = _parseWeightPrefix(prefix);
    if (weight != null) {
      return '${_formatPromptWeight(weight)}:: ${items.join(', ')} ::';
    }
    final rebuilt = [...items];
    rebuilt[0] = '$prefix${rebuilt.first}';
    rebuilt[rebuilt.length - 1] = '${rebuilt.last}$suffix';
    return rebuilt.join(', ');
  }

  static void _appendDecision(
    TagDecision decision,
    List<String> cleanList,
    List<String> deletedList,
    List<String> quantityList,
  ) {
    switch (decision.status) {
      case TagStatus.quantity:
        quantityList.add(decision.display);
      case TagStatus.deleted:
        deletedList.add(decision.display);
      case TagStatus.clean:
        cleanList.add(decision.display);
      case TagStatus.skip:
        break;
    }
  }
}

enum TagStatus { clean, deleted, quantity, skip }

class TagDecision {
  final TagStatus status;
  final String replaced;
  final String display;

  const TagDecision({
    required this.status,
    required this.replaced,
    required this.display,
  });
}

class PromptSegment {
  final String text;
  final String prefix;
  final String suffix;
  final List<String> items;

  PromptSegment.tag(this.text)
      : prefix = '',
        suffix = '',
        items = const [];

  PromptSegment.weighted({
    required this.prefix,
    required this.suffix,
    required this.items,
  }) : text = '';

  bool get isWeighted => prefix.isNotEmpty;
}
