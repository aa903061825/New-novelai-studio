import 'dart:convert';

String stableIdFromText({
  required String prefix,
  required String text,
  String? label,
}) {
  final slug = _asciiSlug(label ?? text);
  final hash = stableTextFingerprint(text);
  if (slug.isEmpty) {
    return '$prefix-$hash';
  }
  return '$prefix-$slug-$hash';
}

String safeWorkspaceEntityId({
  required String prefix,
  required String id,
}) {
  final trimmed = id.trim();
  if (RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$').hasMatch(trimmed)) {
    return trimmed;
  }
  return stableIdFromText(prefix: prefix, text: trimmed);
}

String stableTextFingerprint(String text) {
  var hash = _fnv64Offset;
  for (final byte in utf8.encode(text)) {
    hash ^= BigInt.from(byte);
    hash = (hash * _fnv64Prime) & _fnv64Mask;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}

String _asciiSlug(String value) {
  final buffer = StringBuffer();
  var previousDash = false;
  for (final rune in value.toLowerCase().runes) {
    final isDigit = rune >= 0x30 && rune <= 0x39;
    final isLowerLetter = rune >= 0x61 && rune <= 0x7a;
    if (isDigit || isLowerLetter) {
      buffer.writeCharCode(rune);
      previousDash = false;
      continue;
    }
    if (!previousDash && buffer.isNotEmpty) {
      buffer.write('-');
      previousDash = true;
    }
  }
  final slug = buffer.toString().replaceFirst(RegExp(r'-+$'), '');
  if (slug.length <= 48) {
    return slug;
  }
  return slug.substring(0, 48).replaceFirst(RegExp(r'-+$'), '');
}

final BigInt _fnv64Offset = BigInt.parse('cbf29ce484222325', radix: 16);
final BigInt _fnv64Prime = BigInt.parse('100000001b3', radix: 16);
final BigInt _fnv64Mask = BigInt.parse('ffffffffffffffff', radix: 16);
