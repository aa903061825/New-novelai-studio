import 'dart:convert';
import 'dart:io';

const _defaultManifest =
    r'C:\Users\admin\AppData\Roaming\org.exception0x0194\nai3_autodraw\novel_studio\assets\references\artist-chain-v5-previews\r3c-strong-quality-conditional\v5-test-manifest.json';

const _manualFindings = <String, Map<int, _Finding>>{
  'legacy-artist-sheet-r10c5': {
    1: _Finding(
      reason: '连续两次都出现主角色外的大量小角色/拥挤构图，偏离单角色画师串测试目标。',
      recommendation: '拟删除 A1；若确认该串本来就要多角色，再改为保留。',
    ),
    2: _Finding(
      reason: '连续两次都出现主角色外的大量小角色/拥挤构图，偏离单角色画师串测试目标。',
      recommendation: '拟删除 A2；若确认该串本来就要多角色，再改为保留。',
    ),
  },
  'legacy-artist-sheet-r12c5': {
    1: _Finding(
      reason: '连续两次都出现主角色外的小角色群/背景人物，单角色主体一致性不足。',
      recommendation: '拟删除 A1。',
    ),
    2: _Finding(
      reason: '连续两次都出现主角色外的小角色群/背景人物，单角色主体一致性不足。',
      recommendation: '拟删除 A2。',
    ),
  },
  'legacy-character-sheet-r1-outfit-7-artist-chain': {
    1: _Finding(
      reason: '连续两次都出现大面积额外小角色/群像元素，主体被稀释。',
      recommendation: '拟删除 A1。',
    ),
    2: _Finding(
      reason: '连续两次都出现大面积额外小角色/群像元素，主体被稀释。',
      recommendation: '拟删除 A2。',
    ),
  },
  'legacy-artist-sheet-r12c7': {
    2: _Finding(
      reason: 'A2 出现明显背景人物/拥挤元素；同串 A1 更干净，属于单次失败样本。',
      recommendation: '拟删除 A2；保留同串 A1。',
    ),
  },
};

const _keepNotes = <Map<String, String>>[
  {
    'artistChainId': 'legacy-artist-sheet-r4c1',
    'artistChainName': 'dishwasher1910',
    'decision': 'keep',
    'reason': '画师串明确包含 3d / photorealistic 媒介词；按用户规则，真人/半写实表现不作为删除理由。',
  },
];

Future<void> main(List<String> args) async {
  final manifestPath = _argument(args, '--manifest=') ?? _defaultManifest;
  final manifestFile = File(manifestPath);
  final decoded = jsonDecode(await manifestFile.readAsString());
  if (decoded is! Map) {
    throw const FormatException('V5 manifest must be a JSON object.');
  }
  final manifest = decoded.cast<String, dynamic>();
  final entries = [
    for (final raw in (manifest['entries'] as List? ?? const []))
      if (raw is Map && raw['status'] == 'generated')
        raw.cast<String, dynamic>(),
  ];
  if (entries.isEmpty) {
    throw StateError('V5 manifest has no generated entries.');
  }

  final proposed = <Map<String, dynamic>>[];
  for (final chainEntry in _manualFindings.entries) {
    for (final findingEntry in chainEntry.value.entries) {
      final matches = entries
          .where(
            (entry) =>
                entry['artistChainId'] == chainEntry.key &&
                (entry['attempt'] as num?)?.toInt() == findingEntry.key,
          )
          .toList(growable: false);
      if (matches.length != 1) {
        throw StateError(
          'Expected exactly one generated entry for ${chainEntry.key} '
          'attempt ${findingEntry.key}, found ${matches.length}.',
        );
      }
      final entry = matches.single;
      final finding = findingEntry.value;
      proposed.add({
        'status': 'proposed-delete',
        'artistChainId': entry['artistChainId'],
        'artistChainName': entry['artistChainName'],
        'characterCardId': entry['characterCardId'],
        'characterCardName': entry['characterCardName'],
        'attempt': entry['attempt'],
        'imageRef': entry['imageRef'],
        'absoluteImagePath': entry['absoluteImagePath'],
        'payloadSha256': entry['payloadSha256'],
        'reason': finding.reason,
        'recommendation': finding.recommendation,
      });
    }
  }

  final chainGroups = <String, List<Map<String, dynamic>>>{};
  for (final entry in proposed) {
    final chainId = entry['artistChainId']?.toString() ?? '';
    (chainGroups[chainId] ??= <Map<String, dynamic>>[]).add(entry);
  }
  final output = <String, dynamic>{
    'schemaVersion': 1,
    'status': 'proposed-only',
    'generatedAt': DateTime.now().toIso8601String(),
    'auditBasis': '人工审阅全量接触表、原图与原像素裁剪；不使用自动审美分数替代判断。',
    'deletionPolicy': '本文件只拟定删除，不执行删除；需要用户确认后才能改变素材库引用或删除文件。',
    'criteria': [
      '同一画师串的两次尝试都出现额外小角色/拥挤构图，且偏离本轮单角色测试目标：拟删除整串测试图。',
      '只有一次出现异常、同串另一张更干净：只拟删除异常 attempt，保留较好样本。',
      '画师串明确含 3d / photorealistic 等媒介词：真人或半写实外观不作为删除理由。',
    ],
    'summary': {
      'generatedImages': entries.length,
      'proposedDeleteImages': proposed.length,
      'proposedDeleteChains': chainGroups.length,
      'keepOrUnlistedImages': entries.length - proposed.length,
    },
    'proposedEntries': proposed,
    'keepNotes': _keepNotes,
  };

  final outputPath = _argument(args, '--output=') ??
      '${manifestFile.parent.path}${Platform.pathSeparator}v5-deletion-proposal.json';
  final outputFile = File(outputPath);
  await outputFile.parent.create(recursive: true);
  await outputFile.writeAsString(
    const JsonEncoder.withIndent('  ').convert(output),
  );
  stdout.writeln('Deletion proposal: ${outputFile.path}');
  stdout.writeln('Proposed delete image(s): ${proposed.length}');
}

String? _argument(List<String> args, String prefix) {
  for (final arg in args) {
    if (arg.startsWith(prefix)) return arg.substring(prefix.length);
  }
  return null;
}

class _Finding {
  final String reason;
  final String recommendation;

  const _Finding({required this.reason, required this.recommendation});
}
