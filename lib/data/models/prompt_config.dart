import 'dart:math';

class PromptSelectionMetadata {
  final List<int> contentOrderIndexes;

  const PromptSelectionMetadata({
    this.contentOrderIndexes = const [],
  });

  PromptSelectionMetadata merge(PromptSelectionMetadata other) {
    if (contentOrderIndexes.isEmpty) return other;
    if (other.contentOrderIndexes.isEmpty) return this;
    return PromptSelectionMetadata(
      contentOrderIndexes: [
        ...contentOrderIndexes,
        ...other.contentOrderIndexes,
      ],
    );
  }
}

sealed class NestedPrompt {
  String toPrompt();
  String toComment();
  PromptSelectionMetadata get metadata;

  NestedPrompt replaceVariables(
    Pattern pattern,
    List<PromptConfig> configList,
  );

  /// DFS search that returns prompt with specified key.
  String? findPromptWithKey(String key);
}

/// Leaf node with no child.
class NestedPromptString extends NestedPrompt {
  String title;
  String content;
  @override
  final PromptSelectionMetadata metadata;
  NestedPromptString({
    required this.title,
    required this.content,
    this.metadata = const PromptSelectionMetadata(),
  });

  @override
  String toPrompt() {
    return content;
  }

  @override
  String toComment() {
    return '$title: $content';
  }

  @override
  String? findPromptWithKey(String key) {
    if (title == key) return content;
    return null;
  }

  @override
  NestedPrompt replaceVariables(
    Pattern pattern,
    List<PromptConfig> configList,
  ) {
    // 执行实际替换逻辑
    final replaced = content.replaceAllMapped(
        pattern, (m) => _getReplacement(m[1]!, configList));
    return NestedPromptString(
      title: title,
      content: replaced,
      metadata: metadata,
    );
  }

  String _getReplacement(String key, List<PromptConfig> configList) {
    try {
      return configList
          .firstWhere((e) => e.comment == key)
          .getPrmpts()
          .toPrompt();
    } catch (_) {
      return '__${key}__'; // 保持未替换状态
    }
  }
}

/// Root node with a list of children.
class NestedPromptList extends NestedPrompt {
  String title;
  List<NestedPrompt> children;

  NestedPromptList({required this.title, required this.children});

  @override
  PromptSelectionMetadata get metadata {
    var merged = const PromptSelectionMetadata();
    for (final child in children) {
      merged = merged.merge(child.metadata);
    }
    return merged;
  }

  @override
  String toPrompt() {
    return children
        .map((child) => child.toPrompt())
        .where((prompt) => prompt.isNotEmpty)
        .join(', ');
  }

  @override
  String toComment() {
    if (children.isEmpty) return '$title: <None>';
    var result = '$title:\n';
    for (final (idx, child) in children.indexed) {
      final comment = child.toComment();
      result += _indent(comment.isNotEmpty ? comment : '<None>', 2);
      if (idx != children.length - 1) result += '\n';
    }
    return result;
  }

  @override
  String? findPromptWithKey(String key) {
    if (key == title) return toPrompt();
    for (final child in children) {
      final result = child.findPromptWithKey(key);
      if (result != null) return result;
    }
    return null;
  }

  /// Aux function that splits string and adds indent to each line.
  String _indent(String str, int spaces) {
    var indentation = ' ' * spaces;
    var lines = str.split('\n');
    return lines.map((line) => '$indentation$line').join('\n');
  }

  @override
  NestedPrompt replaceVariables(
    Pattern pattern,
    List<PromptConfig> configList,
  ) {
    // 递归处理子节点
    return NestedPromptList(
        title: title,
        children: children
            .map((c) => c.replaceVariables(pattern, configList))
            .toList());
  }
}

class PromptConfig {
  String selectionMethod;
  bool shuffled;
  double prob;
  int num;
  int randomBracketsUpper;
  int randomBracketsLower;
  String type;
  String comment;
  String filter;
  List<String> strs;
  List<PromptConfig> prompts;
  bool enabled;

  int _sequentialIdx = 0;
  int _sequentialRepeatIdx = 0;

  PromptConfig({
    this.selectionMethod = 'all',
    this.shuffled = true,
    this.prob = 0.0,
    this.num = 1,
    this.randomBracketsUpper = 0,
    this.randomBracketsLower = 0,
    this.type = 'str',
    this.comment = 'Unnamed config',
    this.filter = '',
    required this.strs,
    required this.prompts,
    this.enabled = true,
  });

  factory PromptConfig.fromJson(Map<String, dynamic> json) {
    int upper, lower;
    if (json['randomBrackets'] != null) {
      upper = json['randomBrackets'];
      lower = -json['randomBrackets'];
    } else {
      upper = json['randomBracketsUpper'];
      lower = json['randomBracketsLower'];
    }

    return PromptConfig(
      selectionMethod: json['selectionMethod'],
      shuffled: json['shuffled'],
      prob:
          json['prob'] is int ? (json['prob'] as int).toDouble() : json['prob'],
      num: json['num'],
      randomBracketsUpper: upper.toInt(),
      randomBracketsLower: lower.toInt(),
      type: json['type'],
      comment: json['comment'],
      filter: json['filter'],
      strs:
          (json['strs'] as List<dynamic>?)?.map((e) => e as String).toList() ??
              [],
      prompts: (json['prompts'] as List<dynamic>?)
              ?.map((e) => PromptConfig.fromJson(e))
              .toList() ??
          [],
      enabled: json['enabled'] ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'selectionMethod': selectionMethod,
      'shuffled': shuffled,
      'prob': prob,
      'num': num,
      'randomBracketsUpper': randomBracketsUpper,
      'randomBracketsLower': randomBracketsLower,
      'type': type,
      'comment': comment,
      'filter': filter,
      'strs': strs,
      'prompts': prompts.map((x) => x.toJson()).toList(),
      'enabled': enabled,
    };
  }

  void resetSelectionState() {
    _sequentialIdx = 0;
    _sequentialRepeatIdx = 0;
    for (final prompt in prompts) {
      prompt.resetSelectionState();
    }
  }

  String addRandomBrackets(String s) {
    int n = randomBracketsLower +
        Random().nextInt(randomBracketsUpper - randomBracketsLower + 1);
    List<String> brackets;

    if (n < 0) {
      brackets = ["[", "]"];
      n = -n;
    } else {
      brackets = ["{", "}"];
    }

    final bracketString = List.from(brackets.map((b) => b * n));
    return bracketString[0] + s + bracketString[1];
  }

  NestedPrompt getPrmpts() {
    List<dynamic> chosenPrompts = [];
    List<dynamic> promptsToChoose = [];
    List<int> chosenIndexes = [];
    if (type == 'str') {
      promptsToChoose = List.from(strs);
    } else if (type == 'config') {
      promptsToChoose = List.from(prompts.where((p) => p.enabled));
    }
    final random = Random();

    switch (selectionMethod) {
      case 'single':
        if (promptsToChoose.isNotEmpty) {
          final index = random.nextInt(promptsToChoose.length);
          chosenPrompts.add(promptsToChoose[index]);
          chosenIndexes.add(index);
        }
        break;
      case 'all':
        chosenPrompts = promptsToChoose;
        chosenIndexes = List.generate(promptsToChoose.length, (index) => index);
        break;
      case 'multiple_prob':
        for (final (index, prompt) in promptsToChoose.indexed) {
          if (random.nextDouble() < prob) {
            chosenPrompts.add(prompt);
            chosenIndexes.add(index);
          }
        }
        break;
      case 'multiple_num':
        final indexedPrompts = promptsToChoose.indexed.toList();
        indexedPrompts.shuffle();
        final selected = indexedPrompts.take(num).toList();
        chosenPrompts = selected.map((entry) => entry.$2).toList();
        chosenIndexes = selected.map((entry) => entry.$1).toList();
        break;
      case 'single_sequential':
        chosenPrompts = [promptsToChoose[_sequentialIdx]];
        chosenIndexes = [_sequentialIdx];
        _sequentialRepeatIdx++;
        if (_sequentialRepeatIdx >= num) {
          _sequentialIdx = (_sequentialIdx + 1) % promptsToChoose.length;
          _sequentialRepeatIdx = 0;
        }
        break;
      default:
        chosenPrompts = List.from(promptsToChoose);
    }

    if (shuffled) {
      chosenPrompts.shuffle();
    }

    if (type == 'str') {
      final metadata = comment == '内容'
          ? PromptSelectionMetadata(
              contentOrderIndexes:
                  chosenIndexes.map((index) => index + 1).toList(),
            )
          : const PromptSelectionMetadata();
      return NestedPromptString(
        title: comment,
        content: chosenPrompts.map((p) => addRandomBrackets(p)).join(', '),
        metadata: metadata,
      );
    } else if (type == 'config') {
      return NestedPromptList(
          title: comment,
          children: chosenPrompts
              .map((p) => (p as PromptConfig).getPrmpts())
              .toList());
    } else {
      throw UnimplementedError();
    }
  }
}
