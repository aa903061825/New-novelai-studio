import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as image;

Future<void> main(List<String> args) async {
  final manifestPath = _argument(
        args,
        '--manifest=',
      ) ??
      r'C:\Users\admin\AppData\Roaming\org.exception0x0194\nai3_autodraw\novel_studio\assets\references\artist-chain-v5-previews\v5-test-manifest.json';
  final manifestFile = File(manifestPath);
  final manifest = jsonDecode(await manifestFile.readAsString());
  if (manifest is! Map) {
    throw const FormatException('V5 manifest must be a JSON object.');
  }
  final entries = [
    for (final entry in (manifest['entries'] as List? ?? const []))
      if (entry is Map && entry['status'] == 'generated')
        entry.cast<String, dynamic>(),
  ];
  if (entries.isEmpty) {
    throw StateError('V5 manifest has no generated entries.');
  }
  final deletionProposalPath = _argument(args, '--deletion-proposal=') ??
      '${manifestFile.parent.path}${Platform.pathSeparator}v5-deletion-proposal.json';
  final deletionProposal = await _readOptionalMap(deletionProposalPath);

  final reportDirectory = Directory(
    '${manifestFile.parent.path}${Platform.pathSeparator}report',
  );
  final cropsDirectory = Directory(
    '${reportDirectory.path}${Platform.pathSeparator}crops',
  );
  await cropsDirectory.create(recursive: true);
  await reportDirectory.create(recursive: true);

  final sheet = _buildContactSheet(entries);
  await File(
    '${reportDirectory.path}${Platform.pathSeparator}contact-sheet-v5.png',
  ).writeAsBytes(image.encodePng(sheet));

  final cards = <String>[];
  for (var index = 0; index < entries.length; index++) {
    final entry = entries[index];
    final sourcePath = entry['absoluteImagePath'] as String;
    final sourceFile = File(sourcePath);
    final decoded = image.decodeImage(await sourceFile.readAsBytes());
    if (decoded == null) throw StateError('Could not decode $sourcePath');
    final baseName = _fileName(sourcePath);
    final cropName = '$baseName-original-crop.png';
    final crop = image.copyCrop(
      decoded,
      x: 0,
      y: 0,
      width: math.min(decoded.width, 832),
      height: math.min(decoded.height, 832),
    );
    await File(
      '${cropsDirectory.path}${Platform.pathSeparator}$cropName',
    ).writeAsBytes(image.encodePng(crop));
    cards.add(_cardHtml(index, entry, baseName, cropName));
  }

  final html = _buildHtml(
    manifest.cast<String, dynamic>(),
    cards,
    deletionProposal,
  );
  final reportFile = File(
    '${reportDirectory.path}${Platform.pathSeparator}index.html',
  );
  await reportFile.writeAsString(html);
  stdout.writeln('Report: ${reportFile.path}');
  stdout.writeln('Contact sheet: ${entries.length} image(s)');
}

image.Image _buildContactSheet(List<Map<String, dynamic>> entries) {
  const thumbWidth = 220;
  const thumbHeight = 322;
  const labelHeight = 42;
  const padding = 16;
  const columns = 5;
  final rows = (entries.length / columns).ceil();
  final cellHeight = thumbHeight + labelHeight;
  final sheet = image.Image(
    width: padding + columns * (thumbWidth + padding),
    height: padding + rows * (cellHeight + padding),
  );
  image.fill(sheet, color: image.ColorRgb8(25, 29, 38));

  for (var index = 0; index < entries.length; index++) {
    final entry = entries[index];
    final sourcePath = entry['absoluteImagePath'] as String;
    final source = image.decodeImage(File(sourcePath).readAsBytesSync());
    if (source == null) throw StateError('Could not decode $sourcePath');
    final thumb = image.copyResizeCropSquare(source, size: thumbWidth);
    final column = index % columns;
    final row = index ~/ columns;
    final x = padding + column * (thumbWidth + padding);
    final y = padding + row * (cellHeight + padding);
    image.compositeImage(sheet, thumb, dstX: x, dstY: y);
    image.drawString(
      sheet,
      '#${index + 1} ${_truncate(entry['artistChainName']?.toString() ?? '', 14)} · '
      '${_truncate(entry['characterCardName']?.toString() ?? '角色卡', 8)} '
      'A${entry['attempt'] ?? 1}',
      font: image.arial14,
      x: x,
      y: y + thumbHeight + 8,
      color: image.ColorRgb8(235, 239, 248),
    );
  }
  return sheet;
}

String _cardHtml(
  int index,
  Map<String, dynamic> entry,
  String imageName,
  String cropName,
) {
  final title = _html(entry['artistChainName']?.toString() ?? '未命名画师串');
  final chainId = _html(entry['artistChainId']?.toString() ?? '');
  final characterName =
      _html(entry['characterCardName']?.toString() ?? '未命名角色卡');
  final characterId = _html(entry['characterCardId']?.toString() ?? '');
  final characterPrompt = _html(entry['characterCardPrompt']?.toString() ?? '');
  final qualityTerms = _html(entry['qualityTerms']?.toString() ?? '');
  final attempt = _html(entry['attempt']?.toString() ?? '1');
  final prompt = _html(entry['positivePrompt']?.toString() ?? '');
  final negative = _html(entry['negativePrompt']?.toString() ?? '');
  final source = _html(entry['absoluteImagePath']?.toString() ?? '');
  final imageRef = _html(entry['imageRef']?.toString() ?? '');
  final payloadHash = _html(entry['payloadSha256']?.toString() ?? '');
  final pngStatus = _html(
    ((entry['pngCommentVerification'] as Map?)?['status']?.toString()) ??
        'unknown',
  );
  final payload = const JsonEncoder.withIndent('  ').convert(entry['payload']);
  return '''
<article class="card" id="image-${index + 1}">
  <div class="card-head">
    <span class="index">#${index + 1}</span>
    <div><h3>$title · 角色卡：$characterName · A$attempt</h3><code>$chainId</code></div>
    <span class="badge">V5 测试图</span>
  </div>
  <div class="images">
    <figure><a href="../$imageName"><img src="../$imageName" alt="$title V5 原图"></a><figcaption>原图 · 832×1216</figcaption></figure>
    <figure><a href="crops/$cropName"><img src="crops/$cropName" alt="$title 原像素裁剪"></a><figcaption>原像素裁剪 · 832×832</figcaption></figure>
  </div>
  <dl class="meta">
    <dt>模型</dt><dd>${_html(entry['model']?.toString() ?? '')}</dd>
    <dt>种子</dt><dd>${_html(entry['seed']?.toString() ?? '')}</dd>
    <dt>采样</dt><dd>${_html(entry['sampler']?.toString() ?? '')} · ${_html(entry['steps']?.toString() ?? '')} steps</dd>
    <dt>Scale / CFG rescale</dt><dd>${_html(entry['scale']?.toString() ?? '')} / ${_html(entry['cfgRescale']?.toString() ?? '')}</dd>
    <dt>Vibe</dt><dd>${_html(entry['vibeTransfer']?.toString() ?? '')}</dd>
    <dt>角色卡</dt><dd>$characterName · <code>$characterId</code></dd>
    <dt>角色卡正向词</dt><dd><code>$characterPrompt</code></dd>
    <dt>质量词</dt><dd><code>$qualityTerms</code></dd>
    <dt>质量/UC preset</dt><dd>${_html(entry['qualityPreset']?.toString() ?? '')} / ${_html(entry['ucPresetMode']?.toString() ?? '')}</dd>
    <dt>媒介防护</dt><dd>${_html(entry['mediumGuard']?.toString() ?? '')}</dd>
    <dt>PNG Comment</dt><dd>$pngStatus</dd>
    <dt>素材库引用</dt><dd><code>$imageRef</code></dd>
    <dt>绝对源路径</dt><dd><code>$source</code></dd>
    <dt>Payload SHA-256</dt><dd><code>$payloadHash</code></dd>
  </dl>
  <details><summary>Positive Prompt</summary><pre>$prompt</pre></details>
  <details><summary>Negative Prompt</summary><pre>$negative</pre></details>
  <details><summary>Exact Payload</summary><pre>${_html(payload)}</pre></details>
</article>
''';
}

String _buildHtml(
  Map<String, dynamic> manifest,
  List<String> cards,
  Map<String, dynamic>? deletionProposal,
) {
  final model = _html(manifest['model']?.toString() ?? '');
  final generatedAt = _html(manifest['generatedAt']?.toString() ?? '');
  final dimensions = _html(jsonEncode(manifest['dimensions']));
  final qualityTerms = _html(manifest['qualityTerms']?.toString() ?? '');
  final characterSource = _html(manifest['characterSource']?.toString() ?? '');
  final characterAssignment =
      _html(manifest['characterAssignment']?.toString() ?? '');
  final testRunId = _html(manifest['testRunId']?.toString() ?? '');
  final mediumGuardPolicy =
      _html(manifest['mediumGuardPolicy']?.toString() ?? '');
  final entryCount = cards.length;
  final proposalNav =
      deletionProposal == null ? '' : '<a href="#deletion-proposal">拟删除建议</a>';
  final proposalHtml =
      deletionProposal == null ? '' : _deletionProposalHtml(deletionProposal);
  return '''<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>NAI V5 画师串测试 · $entryCount 条</title>
<style>
:root { color-scheme: dark; --bg:#0f1219; --panel:#181d28; --line:#2d3545; --muted:#9aa7bb; --text:#eef3fb; --accent:#73c7ff; --ok:#8ee0be; --warn:#f1d99d; --danger:#ff9f9f; }
* { box-sizing:border-box; } html { scroll-behavior:smooth; } body { margin:0; background:var(--bg); color:var(--text); font:14px/1.55 system-ui,-apple-system,"Segoe UI",sans-serif; }
header { padding:34px clamp(18px,4vw,64px) 22px; border-bottom:1px solid var(--line); background:linear-gradient(135deg,#182538,#10151f 60%); }
header h1 { margin:0 0 8px; font-size:clamp(24px,4vw,42px); } header p { max-width:920px; margin:6px 0; color:var(--muted); }
nav { position:sticky; top:0; z-index:3; display:flex; gap:8px; flex-wrap:wrap; padding:10px clamp(18px,4vw,64px); background:#111722eF; border-bottom:1px solid var(--line); backdrop-filter:blur(12px); }
nav a { color:var(--accent); text-decoration:none; padding:5px 10px; border:1px solid var(--line); border-radius:999px; } main { padding:26px clamp(18px,4vw,64px) 72px; }
section { max-width:1500px; margin:0 auto 38px; } section h2 { margin:0 0 14px; font-size:22px; } .notice { padding:14px 16px; border:1px solid #8a6d34; background:#332916; border-radius:12px; color:#f1d99d; }
.summary { display:grid; grid-template-columns:repeat(auto-fit,minmax(190px,1fr)); gap:10px; margin:18px 0; } .stat { padding:14px; border:1px solid var(--line); border-radius:12px; background:var(--panel); } .stat b { display:block; color:var(--accent); font-size:20px; }
.sheet-wrap { overflow:auto; padding:12px; border:1px solid var(--line); background:#080a0f; border-radius:14px; } .sheet-wrap img { display:block; max-width:none; }
.grid { display:grid; grid-template-columns:repeat(auto-fit,minmax(390px,1fr)); gap:16px; } .card { overflow:hidden; border:1px solid var(--line); border-radius:14px; background:var(--panel); } .card-head { display:flex; align-items:center; gap:10px; padding:14px 16px; border-bottom:1px solid var(--line); } .card-head h3 { margin:0; font-size:17px; } .card-head code { color:var(--muted); font-size:11px; } .index { color:var(--accent); font-weight:800; } .badge { margin-left:auto; color:#061219; background:var(--ok); padding:3px 8px; border-radius:999px; font-size:11px; white-space:nowrap; }
.images { display:grid; grid-template-columns:1.15fr .85fr; gap:8px; padding:10px; } figure { margin:0; } figure img { display:block; width:100%; height:auto; border-radius:8px; background:#0b0d12; } figure:nth-child(2) img { aspect-ratio:1; object-fit:cover; } figcaption { padding:5px 2px; color:var(--muted); font-size:11px; }
.meta { display:grid; grid-template-columns:135px 1fr; gap:5px 10px; padding:0 16px 12px; margin:0; } .meta dt { color:var(--muted); } .meta dd { margin:0; overflow-wrap:anywhere; } code { color:#c9e9ff; } details { border-top:1px solid var(--line); padding:10px 16px; } summary { cursor:pointer; color:var(--accent); } pre { white-space:pre-wrap; overflow:auto; max-height:260px; margin:9px 0 0; color:#dbe4f2; font:12px/1.5 ui-monospace,SFMono-Regular,Consolas,monospace; }
footer { max-width:1500px; margin:0 auto; color:var(--muted); padding:0 clamp(18px,4vw,64px) 40px; }
.proposal { padding:16px; border:1px solid #70404a; background:#291a22; border-radius:12px; }
.proposal h3 { margin:0 0 8px; color:var(--warn); }
.proposal p { color:var(--muted); }
.proposal table { width:100%; border-collapse:collapse; font-size:13px; }
.proposal th, .proposal td { text-align:left; vertical-align:top; padding:8px; border-top:1px solid #53313a; }
.proposal th { color:var(--warn); }
.proposal .danger { color:var(--danger); font-weight:700; }
</style></head><body>
<header id="overview"><h1>NAI V5 画师串多轮受控测试 · 质量词 + 角色卡</h1><p>运行：<code>$testRunId</code> · 固定条件：$model · $dimensions · seed ${_html(manifest['seed']?.toString() ?? '')} 起 · ${_html(manifest['sampler']?.toString() ?? '')} · ${_html(manifest['steps']?.toString() ?? '')} steps · Scale ${_html(manifest['scale']?.toString() ?? '')} · CFG rescale ${_html(manifest['cfgRescale']?.toString() ?? '')}。</p><p>生成时间：$generatedAt · 共 $entryCount 条（每条画师串多次尝试）。质量词：<code>$qualityTerms</code>。</p><p>角色来源：$characterSource；$characterAssignment。</p><p>媒介处理：$mediumGuardPolicy</p></header>
<nav><a href="#overview">概览</a>$proposalNav<a href="#contact-sheet">全量接触表</a><a href="#per-image">逐图与原像素裁剪</a></nav>
<main>
<section><div class="notice">这一版启用了质量/UC preset，使用更完整质量词，并从角色卡库固定抽取角色身份词。若画师串自身带有 3D/photorealistic 媒介词则原样保留；没有这类词的画师串才使用 2D 防护。图片已进入素材库的 V5 预览字段，用于比较画师串在 NAI 5.0 下的稳定表现，不自动代表正式 Vibe 或最终生产候选。</div><div class="summary"><div class="stat"><b>$entryCount</b>张多轮样本</div><div class="stat"><b>V5</b>预览家族</div><div class="stat"><b>832×1216</b>统一尺寸</div><div class="stat"><b>角色卡配对</b>固定种子</div></div></section>
$proposalHtml
<section id="contact-sheet"><h2>全量接触表</h2><div class="sheet-wrap"><img src="contact-sheet-v5.png" alt="NAI V5 画师串测试全量接触表"></div></section>
<section id="per-image"><h2>逐图审阅 · 原图 + 原像素裁剪</h2><div class="grid">${cards.join('\n')}</div></section>
</main><footer>本页为本地只读审计报告；原图、manifest、payload 与素材库引用均保留在同一素材目录。</footer>
</body></html>''';
}

String? _argument(List<String> args, String prefix) {
  for (final arg in args) {
    if (arg.startsWith(prefix)) return arg.substring(prefix.length);
  }
  return null;
}

Future<Map<String, dynamic>?> _readOptionalMap(String path) async {
  final file = File(path);
  if (!await file.exists()) return null;
  final decoded = jsonDecode(await file.readAsString());
  if (decoded is! Map) {
    throw FormatException('Deletion proposal must be a JSON object: $path');
  }
  return decoded.cast<String, dynamic>();
}

String _deletionProposalHtml(Map<String, dynamic> proposal) {
  final executed = proposal['status']?.toString() == 'executed';
  final summary = (proposal['summary'] as Map?)?.cast<String, dynamic>() ?? {};
  final entries = executed
      ? [
          for (final raw
              in (proposal['removedArtistChains'] as List? ?? const []))
            if (raw is Map)
              {
                'artistChainName': raw['artistChainName'],
                'artistChainId': raw['artistChainId'],
                'characterCardName': '—',
                'attempt': '全部',
                'reason': '用户确认删除该画师串本体及其预览引用。',
                'recommendation': '已执行；保留的例外串不在此表。',
                'imageRef': [
                  if ((raw['removedV5Refs'] as List? ?? const []).isNotEmpty)
                    'V5: ${(raw['removedV5Refs'] as List).join(' | ')}',
                  if ((raw['removedV45Refs'] as List? ?? const []).isNotEmpty)
                    'V4.5: ${(raw['removedV45Refs'] as List).join(' | ')}',
                ].join('\n'),
              },
        ]
      : [
          for (final raw in (proposal['proposedEntries'] as List? ?? const []))
            if (raw is Map) raw.cast<String, dynamic>(),
        ];
  final criteria = [
    for (final value in (proposal['criteria'] as List? ?? const []))
      value.toString(),
  ];
  final keepNotes = [
    for (final raw in (proposal['keepNotes'] as List? ?? const []))
      if (raw is Map) raw.cast<String, dynamic>(),
  ];
  final effectiveKeepNotes = keepNotes.isNotEmpty
      ? keepNotes
      : [
          if (executed && proposal['keptException'] is Map)
            {
              'artistChainName': 'ningen_mame 2号',
              'reason':
                  (proposal['keptException'] as Map)['reason']?.toString() ??
                      '按用户要求保留。',
            },
        ];
  final rows = entries.map((entry) {
    final source = entry['absoluteImagePath']?.toString() ?? '';
    return '<tr><td class="danger">拟删除</td>'
        '<td>${_html(entry['artistChainName']?.toString() ?? '')}<br>'
        '<code>${_html(entry['artistChainId']?.toString() ?? '')}</code></td>'
        '<td>${_html(entry['characterCardName']?.toString() ?? '')}</td>'
        '<td>A${_html(entry['attempt']?.toString() ?? '')}</td>'
        '<td>${_html(entry['reason']?.toString() ?? '')}<br>'
        '<span class="proposal-note">${_html(entry['recommendation']?.toString() ?? '')}</span></td>'
        '<td><code>${_html(entry['imageRef']?.toString() ?? '')}</code><br>'
        '<code>${_html(source)}</code></td></tr>';
  }).join('\n');
  final keepHtml = effectiveKeepNotes.map((entry) {
    return '<li><b>${_html(entry['artistChainName']?.toString() ?? '')}</b>：'
        '${_html(entry['reason']?.toString() ?? '')}</li>';
  }).join('\n');
  final criteriaHtml =
      criteria.map((value) => '<li>${_html(value)}</li>').join('\n');
  final heading = executed ? '质量审阅 · 已执行删除记录' : '质量审阅 · 拟删除建议';
  final status = executed ? '已执行删除' : '仅拟定，不执行删除';
  final rootCause = proposal['rootCauseNote']?.toString() ?? '';
  final summaryText = executed
      ? '已删除 ${summary['removedArtistChains'] ?? ''} 条画师串、${summary['removedFiles'] ?? ''} 个文件；保留例外串 ${proposal['keptException'] == null ? 0 : 1} 条。'
      : '本轮共 ${summary['generatedImages']?.toString() ?? ''} 张；拟删除 ${summary['proposedDeleteImages']?.toString() ?? ''} 张；其余 ${summary['keepOrUnlistedImages']?.toString() ?? ''} 张暂不列入删除。';
  return '''<section id="deletion-proposal"><h2>$heading</h2>
<div class="proposal"><h3>$status</h3>
<p>${_html(proposal['deletionPolicy']?.toString() ?? (executed ? '已按用户确认执行。' : '需要用户确认后执行。'))}</p>
<p>$summaryText</p>
${rootCause.isEmpty ? '' : '<p><b>根因记录：</b>${_html(rootCause)}</p>'}
${criteriaHtml.isEmpty ? '' : '<h4>判定口径</h4><ul>$criteriaHtml</ul>'}
<table><thead><tr><th>状态</th><th>画师串</th><th>角色卡</th><th>尝试</th><th>原因 / 建议</th><th>引用 / 源路径</th></tr></thead><tbody>$rows</tbody></table>
${keepHtml.isEmpty ? '' : '<h4>明确保留例外</h4><ul>$keepHtml</ul>'}
</div></section>''';
}

String _fileName(String path) {
  final normalized = path.replaceAll('\\', '/');
  final index = normalized.lastIndexOf('/');
  return index < 0 ? normalized : normalized.substring(index + 1);
}

String _truncate(String value, int maxLength) {
  if (value.length <= maxLength) return value;
  return '${value.substring(0, maxLength - 1)}…';
}

String _html(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
