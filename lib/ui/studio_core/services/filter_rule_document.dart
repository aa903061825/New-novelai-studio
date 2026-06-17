import 'package:novel_studio/data/studio/tools/prompt_tag_classifier.dart';
import 'package:novel_studio/data/studio/tools/prompt_tag_processor.dart';
import 'package:novel_studio/data/workspace/models/workspace_entities.dart';
import 'package:novel_studio/data/workspace/workspace_paths.dart';

typedef FilterRuleBlockResolver = String Function(String text);

class FilterRuleDocument {
  final FilterRuleBlockResolver resolveBlock;
  final List<String> blocks;
  final Map<String, List<String>> _tagsByBlock;

  FilterRuleDocument.fromText(
    String text, {
    required this.resolveBlock,
    this.blocks = WorkspacePaths.blocks,
  }) : _tagsByBlock = _groupTags(
          parseFilterRuleWords(text),
          resolveBlock: resolveBlock,
        );

  FilterRuleDocument.fromWords(
    Iterable<String> words, {
    required this.resolveBlock,
    this.blocks = WorkspacePaths.blocks,
  }) : _tagsByBlock = _groupTags(
          words,
          resolveBlock: resolveBlock,
        );

  FilterRuleDocument.fromBlocks(
    Map<String, List<String>> tagsByBlock, {
    required this.resolveBlock,
    this.blocks = WorkspacePaths.blocks,
  }) : _tagsByBlock = _copyBlocks(tagsByBlock);

  FilterRuleDocument._({
    required this.resolveBlock,
    required this.blocks,
    required Map<String, List<String>> tagsByBlock,
  }) : _tagsByBlock = tagsByBlock;

  Map<String, List<String>> get tagsByBlock => _copyBlocks(_tagsByBlock);

  Iterable<String> get sourceOrderBlocks =>
      filterRuleSourceOrderBlocks(_tagsByBlock, blocks: blocks);

  List<String> flatten() {
    return [
      for (final block in sourceOrderBlocks)
        ..._tagsByBlock[block] ?? const <String>[],
    ];
  }

  String toRuleText() => flatten().join(', ');

  FilterRuleDocument addToBlock(String block, Iterable<String> values) {
    final next = _copyBlocks(_tagsByBlock);
    final list = _listFor(next, block);
    for (final value in values) {
      appendUniqueFilterRuleTag(list, value);
    }
    return FilterRuleDocument._(
      resolveBlock: resolveBlock,
      blocks: blocks,
      tagsByBlock: next,
    );
  }

  FilterRuleDocument addAuto(Iterable<String> values) {
    final next = _copyBlocks(_tagsByBlock);
    for (final value in values) {
      appendUniqueFilterRuleTag(_listFor(next, resolveBlock(value)), value);
    }
    return FilterRuleDocument._(
      resolveBlock: resolveBlock,
      blocks: blocks,
      tagsByBlock: next,
    );
  }
}

List<String> parseFilterRuleWords(String text) {
  return PromptTagProcessor.splitWorkshopTags(text)
      .map((tag) => tag.trim())
      .where((tag) => tag.isNotEmpty)
      .toList(growable: true);
}

String filterRuleMatchKey(String text) {
  return PromptTagProcessor.normalizeMatchKey(text);
}

void appendUniqueFilterRuleTag(List<String> list, String value) {
  final text = value.trim();
  final key = filterRuleMatchKey(text);
  if (key.isEmpty) {
    return;
  }
  final exists = list.any((tag) => filterRuleMatchKey(tag) == key);
  if (!exists) {
    list.add(text);
  }
}

Iterable<String> filterRuleSourceOrderBlocks<T>(
  Map<String, List<T>> rulesByBlock, {
  List<String> blocks = WorkspacePaths.blocks,
}) sync* {
  final emitted = <String>{};
  for (final entry in rulesByBlock.entries) {
    if (entry.value.isNotEmpty && emitted.add(entry.key)) {
      yield entry.key;
    }
  }
  for (final block in blocks) {
    if (emitted.add(block)) {
      yield block;
    }
  }
}

Map<String, String> buildKnownFilterRuleBlocks(Iterable<TagEntry> tags) {
  final knownBlocks = <String, String>{};
  for (final tag in tags) {
    final block = knownFilterRuleBlockForTagEntry(tag);
    if (block == null) {
      continue;
    }
    _rememberKnownBlock(knownBlocks, tag.tag, block);
    for (final alias in tag.aliases) {
      _rememberKnownBlock(knownBlocks, alias, block);
    }
  }
  return Map.unmodifiable(knownBlocks);
}

String? knownFilterRuleBlockForTagEntry(TagEntry tag) {
  final block = canonicalFilterRuleBlock(tag.block);
  if (block != null) {
    return block;
  }
  final category = filterRuleCategoryFromTagEntry(tag);
  if (category == null) {
    return null;
  }
  return filterRuleBlockFromCategory(category);
}

PromptTagCategory? filterRuleCategoryFromTagEntry(TagEntry tag) {
  for (final value in [tag.category, tag.block]) {
    final key = value.toLowerCase();
    if (key.contains('artist')) return PromptTagCategory.artist;
    if (key.contains('quality')) return PromptTagCategory.quality;
    if (key.contains('character') || key.contains('expression')) {
      return PromptTagCategory.character;
    }
    if (key.contains('upper clothing') || key.contains('upper outfit')) {
      return PromptTagCategory.upperClothing;
    }
    if (key.contains('lower clothing') || key.contains('lower outfit')) {
      return PromptTagCategory.lowerClothing;
    }
    if (key.contains('upper')) return PromptTagCategory.upperBody;
    if (key.contains('lower')) return PromptTagCategory.lowerBody;
    if (key.contains('clothing') || key.contains('outfit')) {
      return PromptTagCategory.clothing;
    }
    if (key.contains('action') || key.contains('pose')) {
      return PromptTagCategory.action;
    }
    if (key.contains('camera')) return PromptTagCategory.camera;
    if (key.contains('scene') || key.contains('background')) {
      return PromptTagCategory.scene;
    }
    if (key.contains('style') || key.contains('lighting')) {
      return PromptTagCategory.style;
    }
  }
  return null;
}

String? canonicalFilterRuleBlock(String value) {
  final block = value.trim().toLowerCase();
  if (WorkspacePaths.blocks.contains(block)) {
    return block;
  }
  return null;
}

String filterRuleBlockFromCategory(PromptTagCategory category) {
  return switch (category) {
    PromptTagCategory.character => 'character',
    PromptTagCategory.upperBody ||
    PromptTagCategory.lowerBody ||
    PromptTagCategory.upperClothing ||
    PromptTagCategory.lowerClothing ||
    PromptTagCategory.clothing ||
    PromptTagCategory.negativeBody =>
      'clothing',
    PromptTagCategory.action => 'action',
    PromptTagCategory.scene => 'scene',
    PromptTagCategory.camera => 'camera',
    PromptTagCategory.artist ||
    PromptTagCategory.negativeArtist ||
    PromptTagCategory.style ||
    PromptTagCategory.quality ||
    PromptTagCategory.negativeQuality ||
    PromptTagCategory.negativeContent ||
    PromptTagCategory.promptSyntax ||
    PromptTagCategory.other =>
      'style',
  };
}

Map<String, List<String>> _groupTags(
  Iterable<String> tags, {
  required FilterRuleBlockResolver resolveBlock,
}) {
  final result = <String, List<String>>{};
  for (final tag in tags) {
    final text = tag.trim();
    if (text.isEmpty) {
      continue;
    }
    appendUniqueFilterRuleTag(_listFor(result, resolveBlock(text)), text);
  }
  return result;
}

Map<String, List<String>> _copyBlocks(Map<String, List<String>> tagsByBlock) {
  return {
    for (final entry in tagsByBlock.entries)
      entry.key: List<String>.of(entry.value),
  };
}

List<T> _listFor<T>(Map<String, List<T>> blockMap, String block) {
  return blockMap.putIfAbsent(block, () => <T>[]);
}

void _rememberKnownBlock(
  Map<String, String> knownBlocks,
  String text,
  String block,
) {
  final key = filterRuleMatchKey(text);
  if (key.isNotEmpty) {
    knownBlocks[key] = block;
  }
}
