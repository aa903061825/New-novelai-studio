import 'dart:convert';

typedef ScriptAiJsonCandidateScore = int Function(Object? value);
typedef ScriptAiJsonCandidateFilter = bool Function(Object? value);

class ScriptAiJsonDecodeResult {
  final Object? value;
  final ScriptAiJsonDecodeFailure? failure;

  const ScriptAiJsonDecodeResult.value(this.value) : failure = null;

  const ScriptAiJsonDecodeResult.failure(this.failure) : value = null;

  bool get isFailure => failure != null;
}

class ScriptAiJsonDecodeFailure {
  final String message;

  const ScriptAiJsonDecodeFailure(this.message);
}

class ScriptAiJsonResponseDecoder {
  const ScriptAiJsonResponseDecoder();

  ScriptAiJsonDecodeResult decode(
    String source, {
    ScriptAiJsonCandidateScore? score,
    ScriptAiJsonCandidateFilter? canSelect,
    bool preferMapFallback = false,
  }) {
    ScriptAiJsonDecodeFailure? lastFailure;
    final decodedValues = <Object?>[];

    for (final candidate in _decodeCandidates(source)) {
      final decoded = _decodeCandidate(candidate);
      if (decoded.isFailure) {
        lastFailure = decoded.failure;
      } else {
        decodedValues.add(decoded.value);
      }
    }

    if (decodedValues.isEmpty) {
      return ScriptAiJsonDecodeResult.failure(
        lastFailure ??
            const ScriptAiJsonDecodeFailure('Unable to decode response'),
      );
    }

    if (score != null) {
      Object? bestValue;
      var bestScore = 0;
      for (final value in decodedValues) {
        if (canSelect != null && !canSelect(value)) continue;
        final valueScore = score(value);
        if (valueScore > bestScore) {
          bestValue = value;
          bestScore = valueScore;
        }
      }
      if (bestValue != null) {
        return ScriptAiJsonDecodeResult.value(bestValue);
      }
    }

    if (preferMapFallback) {
      for (final value in decodedValues) {
        if (value is Map) return ScriptAiJsonDecodeResult.value(value);
      }
    }

    return ScriptAiJsonDecodeResult.value(decodedValues.first);
  }

  ScriptAiJsonDecodeResult _decodeCandidate(String candidate) {
    try {
      final decoded = jsonDecode(candidate);
      if (decoded is String) {
        return decode(decoded.trim());
      }
      return ScriptAiJsonDecodeResult.value(decoded);
    } on FormatException catch (error) {
      return ScriptAiJsonDecodeResult.failure(
        ScriptAiJsonDecodeFailure(error.message),
      );
    }
  }

  Iterable<String> _decodeCandidates(String source) sync* {
    final emitted = <String>{};

    void emit(String candidate) {
      final trimmed = candidate.trim();
      if (trimmed.isEmpty || emitted.contains(trimmed)) return;
      emitted.add(trimmed);
    }

    emit(source);

    final fenced = _fencedJson(source);
    if (fenced != null) emit(fenced);

    for (final object in _jsonObjectSubstrings(source)) {
      emit(object);
    }

    yield* emitted;
  }

  String? _fencedJson(String source) {
    final match = RegExp(
      r'```(?:json)?\s*([\s\S]*?)\s*```',
      caseSensitive: false,
    ).firstMatch(source);
    return match?.group(1);
  }

  Iterable<String> _jsonObjectSubstrings(String source) sync* {
    for (var start = source.indexOf('{');
        start >= 0;
        start = source.indexOf('{', start + 1)) {
      final object = _balancedJsonObjectAt(source, start);
      if (object != null) yield object;
    }
  }

  String? _balancedJsonObjectAt(String source, int start) {
    var depth = 0;
    var inString = false;
    var isEscaped = false;

    for (var index = start; index < source.length; index += 1) {
      final codeUnit = source.codeUnitAt(index);

      if (inString) {
        if (isEscaped) {
          isEscaped = false;
        } else if (codeUnit == _backslash) {
          isEscaped = true;
        } else if (codeUnit == _doubleQuote) {
          inString = false;
        }
        continue;
      }

      if (codeUnit == _doubleQuote) {
        inString = true;
        continue;
      }
      if (codeUnit == _openBrace) {
        depth += 1;
        continue;
      }
      if (codeUnit == _closeBrace) {
        depth -= 1;
        if (depth == 0) {
          return source.substring(start, index + 1);
        }
      }
    }

    return null;
  }
}

const _backslash = 0x5C;
const _doubleQuote = 0x22;
const _openBrace = 0x7B;
const _closeBrace = 0x7D;
