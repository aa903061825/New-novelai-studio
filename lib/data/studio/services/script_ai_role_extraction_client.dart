import 'dart:convert';

import 'package:nai_casrand/data/models/api_request.dart';
import 'package:nai_casrand/data/services/api_service.dart';
import 'package:nai_casrand/data/studio/services/script_ai_client.dart';
import 'package:nai_casrand/data/studio/services/script_ai_openai_chat_client.dart';

const _scriptAiReasoningEffortOptions = ['low', 'medium', 'high', 'xhigh'];

String _normalizeScriptAiReasoningEffort(String? value) {
  final normalized = value?.trim() ?? '';
  return _scriptAiReasoningEffortOptions.contains(normalized) ? normalized : '';
}

typedef ScriptAiStreamData = Future<ApiResponse> Function(
  ApiRequest request, {
  required void Function(String text) onTextChunk,
});

typedef ScriptAiRoleExtractionStreamUpdate = void Function(
  ScriptAiRoleExtractionStreamDelta delta,
);

abstract interface class ScriptAiRoleExtractionClient {
  Future<ScriptAiRoleExtractionClientResult> extractRoles(
    ScriptAiRoleExtractionClientRequest request,
  );
}

class ScriptAiRoleExtractionStreamDelta {
  final String reasoningContentDelta;
  final String contentDelta;

  const ScriptAiRoleExtractionStreamDelta({
    this.reasoningContentDelta = '',
    this.contentDelta = '',
  });
}

class ScriptAiRoleExtractionClientRequest {
  final String baseUrl;
  final String token;
  final String model;
  final String reasoningEffort;
  final String proxy;
  final Map<String, dynamic> requestJson;
  final ScriptAiRoleExtractionStreamUpdate? onStreamDelta;

  const ScriptAiRoleExtractionClientRequest({
    required this.baseUrl,
    required this.token,
    required this.model,
    this.reasoningEffort = '',
    this.proxy = '',
    required this.requestJson,
    this.onStreamDelta,
  });
}

class ScriptAiRoleExtractionClientResult {
  final String rawJson;
  final String reasoningContent;

  const ScriptAiRoleExtractionClientResult({
    required this.rawJson,
    this.reasoningContent = '',
  });
}

class ScriptAiRoleExtractionClientException implements Exception {
  final String message;

  const ScriptAiRoleExtractionClientException(this.message);

  @override
  String toString() => message;
}

class OpenAiCompatibleScriptAiRoleExtractionClient
    implements ScriptAiRoleExtractionClient {
  final ScriptAiFetchData fetchData;
  final ScriptAiStreamData streamData;
  final ScriptAiOpenAiChatClient chatClient;

  OpenAiCompatibleScriptAiRoleExtractionClient({
    ScriptAiFetchData? fetchData,
    ScriptAiStreamData? streamData,
    ApiService? apiService,
    this.chatClient = const ScriptAiOpenAiChatClient(),
  })  : fetchData = fetchData ?? (apiService ?? ApiService()).fetchData,
        streamData = streamData ?? (apiService ?? ApiService()).streamData;

  @override
  Future<ScriptAiRoleExtractionClientResult> extractRoles(
    ScriptAiRoleExtractionClientRequest request,
  ) async {
    chatClient.validateConfig(
      baseUrl: request.baseUrl,
      token: request.token,
      model: request.model,
      label: 'Script AI role extraction',
      createException: ScriptAiRoleExtractionClientException.new,
    );
    final apiRequest = _apiRequest(
      request,
      stream: request.onStreamDelta != null,
    );
    if (request.onStreamDelta != null) {
      return _streamContentFromOpenAiResponse(request, apiRequest);
    }

    final response = await fetchData(apiRequest);

    chatClient.ensureSuccess(
      response: response,
      label: 'Script AI role extraction',
      createException: ScriptAiRoleExtractionClientException.new,
    );

    return _contentFromOpenAiResponse(response);
  }

  ApiRequest _apiRequest(
    ScriptAiRoleExtractionClientRequest request, {
    required bool stream,
  }) {
    return ApiRequest(
      endpoint: chatClient.chatCompletionsEndpoint(request.baseUrl),
      proxy: request.proxy,
      timeout: const Duration(minutes: 5),
      logLabel: 'script-ai-role-extraction',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${request.token.trim()}',
      },
      payload: {
        'model': request.model.trim(),
        'messages': [
          {
            'role': 'system',
            'content': _systemPrompt,
          },
          {
            'role': 'user',
            'content': jsonEncode(request.requestJson),
          },
        ],
        'temperature': 0,
        'response_format': {
          'type': 'json_object',
        },
        if (_normalizeScriptAiReasoningEffort(request.reasoningEffort)
            .isNotEmpty)
          'reasoning_effort':
              _normalizeScriptAiReasoningEffort(request.reasoningEffort),
        if (stream) 'stream': true,
      },
    );
  }

  Future<ScriptAiRoleExtractionClientResult> _streamContentFromOpenAiResponse(
    ScriptAiRoleExtractionClientRequest request,
    ApiRequest apiRequest,
  ) async {
    final accumulator = _OpenAiStreamAccumulator(
      onStreamDelta: request.onStreamDelta!,
    );
    final response = await streamData(
      apiRequest,
      onTextChunk: accumulator.addText,
    );
    chatClient.ensureSuccess(
      response: response,
      label: 'Script AI role extraction',
      createException: ScriptAiRoleExtractionClientException.new,
    );
    final streamed = accumulator.finish();
    if (streamed.rawJson.trim().isNotEmpty ||
        streamed.reasoningContent.trim().isNotEmpty) {
      return streamed;
    }
    return _contentFromOpenAiResponse(response);
  }

  ScriptAiRoleExtractionClientResult _contentFromOpenAiResponse(
    ApiResponse response,
  ) {
    final content = chatClient.contentFromResponse(
      response: response,
      label: 'Script AI role extraction',
      createException: ScriptAiRoleExtractionClientException.new,
    );
    return ScriptAiRoleExtractionClientResult(
      rawJson: content.rawJson,
      reasoningContent: content.reasoningContent,
    );
  }

  static String? _stringValue(Object? value) {
    if (value is String && value.isNotEmpty) {
      return value;
    }
    return null;
  }

  static String? _deltaString(Map delta, String key) =>
      _stringValue(delta[key]);

  static void _emitDelta(
    ScriptAiRoleExtractionStreamUpdate onStreamDelta, {
    String reasoningContentDelta = '',
    String contentDelta = '',
  }) {
    if (reasoningContentDelta.isEmpty && contentDelta.isEmpty) {
      return;
    }
    onStreamDelta(
      ScriptAiRoleExtractionStreamDelta(
        reasoningContentDelta: reasoningContentDelta,
        contentDelta: contentDelta,
      ),
    );
  }

  static const _systemPrompt = '''
You are a Script AI role extraction engine for Script Recast.

Return strict JSON only. Do not include Markdown, comments, prose, explanations, or code fences.

You receive raw script tag evidence. Your job is to infer the actual roles and fill only the five Script Recast fields:

1. identity
2. upper_body
3. lower_body
4. upper_clothing
5. lower_clothing

You also extract:

1. meaningful outfit stage changes for each role
2. artist-chain evidence terms
3. mosaic/censor terms for strong filter keywords
4. warnings and unassigned terms

You do not manage action, pose, expression, camera, background, lighting, composition, quality tags, vibe references, or local asset matching.

Input can contain:
- slotted character captions
- base/global prompt tags
- slotless_base_prompt_frames, a deterministic list of frames where no
  non-empty character slot exists and the base prompt is the only positive
  prompt source
- negative prompt tags
- raw tag frequency and frame evidence

Role inference rules:
- A source slot is a frame position, not necessarily a character identity.
- If one actual character stays in one slot source, reuse that source_id exactly as source_role_id, such as slot-0.
- If one actual character appears in multiple slot sources across different frames, create one identity-level role with source_kind "cross_slot", a stable source_role_id such as role-0, and an appearances array listing every slot source_id plus the frame_indexes where that character appears in that slot.
- Use cross_slot roles when exact identity tags, repeated distinctive body/accessory tags, or frame_prompts show that the same character moved between slot-0, slot-1, etc.
- If base/global prompt evidence clearly contains characters without slot IDs, create global roles: global-0, global-1, global-2, etc.
- You may infer multiple global roles from one mixed base prompt if the evidence supports it.
- Never skip slotless_base_prompt_frames. Inspect the base source for those frames. If the base evidence clearly contains one identifiable or generic character role, create or extend a role with an appearance using source_id "base", source_kind "base", and the exact frame_indexes. If the same actual character appears in slots elsewhere, one identity-level role may include both slot and base appearances.
- slotless_base_prompt_frames are structural evidence only. They do not prove that the base prompt contains a character. If the base prompt is scene/style/quality only, do not create a role from it.
- Every role must include evidence_terms and frame_indexes.
- Every role must explicitly say who the role is in display_name and explain the evidence in role_reason.
- Every role's display_name must be UI-facing and include a concise Chinese translation. Keep canonical_name and franchise in source-faithful normalized form; do not translate prompt replacement fields.
- Every role must include canonical_name, franchise, raw_identity_tags, variant_tags, and merge_with_role_id.
- official costume variants, event variants, version variants, and parenthetical outfit variants are not separate characters. For example, kokkoro (princess_connect!) and kokkoro (ceremonial) (princess_connect!) are one canonical role with canonical_name "kokkoro" and franchise "princess_connect!"; "ceremonial" belongs in variant_tags, not as a second role.
- If a role is the same canonical character as another role, set merge_with_role_id to the target role id. Do not create a second role solely because the raw identity tag contains swimsuit, maid, bunny, dress, school uniform, ceremonial, alter costume, or another outfit/version/event qualifier.
- Same canonical_name plus same franchise means the same role. Same name across different franchises must remain separate unless evidence clearly says otherwise.
- Do not invent tags. Every term in identity, upper_body, lower_body, upper_clothing, lower_clothing, artist_chains, strong_filter_keywords, and unassigned_terms must come from input evidence or an exact normalized spelling variant of input evidence.
- The frame_prompts section, when present in chunk or merge requests, contains exact per-frame prompt text for audit. Use tag meaning for field classification and return normalized tag text; prompt weights are restored by the application UI, not by model reasoning.
- If role separation is uncertain, keep confidence below 0.75 and add warnings such as ambiguous_global_roles or cannot_assign_terms_to_role.
- If terms cannot be safely assigned to one role, put them in unassigned_terms.
- Do not create extra stage candidate fields. Terms that are not stable identity, body/accessory, or worn garment evidence must stay out of the role stage output.
- Do not put another role's terms, global quality terms, global artist-chain terms, background, camera, or clearly unrelated prompt terms into any role stage field.
- For slot-* roles, stage fields must come only from that same slot source evidence. For global-* roles, stage fields must come only from the global/base evidence used for that role.
- For cross_slot roles, stage fields must come only from the slot/frame evidence listed in that role's appearances.

Five-field classification rules:
- The five fields are reusable replacement fields for character identity,
  stable non-explicit body/accessory traits, and worn garments. They are not
  a general tag sorter.
- identity: character name/source identity plus generic role or demographic tags only, such as girl, boy, loli, child, woman, or man.
- Series-qualified character tags such as himekawa yoshino (date a live), yatogami tohka (date a live), character_name_(series), or character name (series) are concrete source identity terms. Put them in identity, never in unassigned_terms or warnings-only output.
- Costume-qualified character tags with both a costume/variant and series, such as ako (dress) (blue archive), are still concrete source identity terms. Put them in identity, not non_role, even when the costume word looks like clothing.
- Parenthetical outfit/version qualifiers inside character tags, such as ceremonial in kokkoro (ceremonial) (princess_connect!), are raw identity evidence plus variant evidence. Keep the raw tag in raw_identity_tags, put the qualifier in variant_tags, and merge it with the same canonical character role.
- If the user later wants to preserve the source character, keeping that source character tag in identity is the correct representation. Do not omit a concrete source identity merely because it may later be replaced.
- Do not put species, animal part, body part, or accessory tags in identity. For example, fox girl should become girl when no better source identity exists, fox ears belongs in upper_body, and fox tail belongs in lower_body.
- upper_body: hair, eyes, ears, horns, halo, arms, hands, neck, non-explicit upper torso traits, and upper-body accessories such as choker, collar, necklace, earrings, hat, or head ornament. Exclude expressions and poses.
- lower_body: legs, feet, tail, non-explicit lower torso traits, and lower-body accessories. Exclude actions and poses.
- upper_clothing: shirt, blouse, jacket, coat, robe top, armor top, uniform upper part, gloves when they are outfit pieces.
- lower_clothing: skirt, pants, shorts, legwear, socks, thighhighs, shoes, boots, armor lower part, dress lower part.
- Missing fields are valid. Do not invent upper_clothing or lower_clothing to fill blanks.
- If a stage has no upper_clothing, add missing_upper_clothing to missing_fields.
- If a stage has no lower_clothing, add missing_lower_clothing to missing_fields.
- If a full outfit cannot be split into upper/lower fields, put it in the most appropriate field and add warning full_outfit_unsplit.
- Stable upper-body traits such as small breasts or large breasts belong in upper_body.
- Never put sexualized body-state, fetish, residue, genitals, or body-only exposure terms in any of identity, upper_body, lower_body, upper_clothing, or lower_clothing. Put them in unassigned_terms with reason "not_a_replacement_field".
- Never put body-only, anatomy, expression, pose, action, sexual act, or residue tags in upper_clothing or lower_clothing.
- Examples of terms forbidden from all five fields include nipples, areola, stomach bulge, big belly, navel, thighs, ass, butt, pussy, cleft of venus, blush, nose blush, tongue out, open mouth, heavy breathing, breast press, spread legs, cum on body, cum on breast, cum string, orgasm, nervous, shy, and sideways glance.
- Accessories such as choker/collar/necklace/halo/animal ears/tail belong in upper_body or lower_body, not upper_clothing or lower_clothing, and accessory-only differences must not create separate outfit stages.

Outfit stage rules:
- Treat each stage as an outfit slot, not a story/action/camera phase.
- For each stage, assign appearance_group_id to the stable outfit/appearance group it belongs to.
- If two or more stages are the same stable appearance and should be merged, list which stages should be merged in merge_with_stage_ids on each affected stage.
- For every stage, include field_reasons explaining why each stable term belongs to identity, upper_body, lower_body, upper_clothing, or lower_clothing. The reasons should make clear that action/pose/expression/transient terms are not replacement fields and must not be output as stage terms.
- Output every stage label in Chinese. Use concise Chinese outfit names such as "校服", "和服", "休闲服", "比基尼泳装", "裸体", or "裸体（项圈）"; do not output English labels such as "Casual Outfit" or "Completely nude with choker".
- When source frames provide stable scene, location, or work context, prefer context-aware Chinese stage labels such as "浴室裸体" or "车间工装". Use context only in the label; do not copy scene/action context into identity, body, or clothing fields unless the original tag is valid five-field role evidence.
- Create separate stages only when the character's core worn garment set changes into a different outfit category, such as school uniform vs nightgown vs towel wrap vs china dress, or when the evidence changes from wearing garments to no garments at all.
- A variant tag alone must not invent outfit fields or an outfit stage. If "ceremonial" appears only inside the character identity tag and there is no concrete stable clothing evidence, keep it as variant/stage evidence or an attention item, and do not create a ceremonial clothing field.
- Do not split separate outfit slots for state variants of the same outfit. Merge them into the same stage.
- Same-outfit state variants include barefoot vs socks/shoes/no shoes, gloves vs no gloves, choker/accessory present vs absent, coat/jacket on vs no coat, clothes pulled/lifted, wetness, stains, partial undressing, body exposure, action, pose, expression, camera, lighting, background, or temporary quality noise.
- Nude/body-only variants such as completely nude, completely nude with choker, oiled body, beach/oiled, stomach bulge, thighs, ass, pussy, spread legs, cum on body, or heavy breathing are one no-core-clothing stage unless real garments change.
- When state variants share the same core outfit, combine their terms into the same five fields and add warning outfit_state_variant_merged when useful.
- If a term is only action/pose/camera/background/expression, keep it out of the five fields and do not output it as a stage candidate. Put only genuinely unresolved role assignment conflicts in unassigned_terms when needed.
- Stable identity and body fields can repeat across stages.
- Stage frame_indexes must describe where the stage appears according to evidence.

Artist-chain rules:
- Extract artist-chain evidence from tags such as artist:NAME, official art, official style, official_art_style, official art style, official_style, and close official-style variants present in input.
- Treat official art/style terms as artist-chain evidence, not ordinary style tags.
- Do not select or invent artist-chain IDs.

Strong filter rules:
- Extract mosaic/censor terms only when they appear in input evidence.
- Examples include mosaic, mosaic censoring, censored, censor, bar censor, censor bar, pixelated censor, censorship, mosaic censorship, mosaic censor, 马赛克, 审查.
- Return these terms in strong_filter_keywords.
- Do not invent related safety terms that were not present or directly normalized from present input.

If request_kind is chunk_extract_v2:
- The input contains source-level tag_evidence plus timeline_segments.
- timeline_segments contain frame_range, representative_caption, stable_tags, variant_tags, and frame_indexes.
- cross_slot_tag_candidates lists exact tags that appear in more than one slot source, with slot/frame appearances. Treat these as review evidence for possible cross_slot roles, not as automatic proof.
- Return one chunk-local extraction object when evidence is sufficient.
- Include chunk_id from input.
- If evidence is insufficient, return status "needs_more_evidence" with bounded evidence_requests.

If returning status "needs_more_evidence":
- Request only source_id plus frame_indexes from the current chunk.
- Request only frame/source evidence; never file paths, directories, images, external assets, arbitrary JSON files, character cards, outfit cards, or vibe data.
- Use at most 3 evidence request groups.
- Use at most 12 frames per request group.
- Prefer low confidence over over-requesting or inventing tags.

If request_kind is evidence_followup:
- Use the supplied exact frame evidence to return final status "ready" or "failed".
- Do not return another needs_more_evidence response.

If request_kind is merge_extractions:
- Merge chunk extraction objects into one final script-level extraction.
- Merge slot-* roles by exact source_role_id.
- Merge cross_slot roles by exact source_role_id and preserve their appearances.
- Merge roles with the same canonical_name and franchise/source. Preserve raw_identity_tags and variant_tags from all merged roles.
- Merge global roles only when identity/body/clothing evidence clearly refers to the same character.
- Keep global roles separate when evidence conflicts.
- Preserve appearances whose source_id is "base"; they are required for replacing slotless base prompt frames.
- De-duplicate artist-chain terms and strong_filter_keywords.
- Preserve unresolved conflicts in attention_items and unassigned_terms.

Output JSON shape:
{
  "schema_version": 1,
  "status": "ready",
  "chunk_id": "optional chunk id",
  "confidence": 0.0,
  "roles": [
    {
      "source_role_id": "slot-0, role-0, or global-0",
      "source_kind": "slot, cross_slot, or global",
      "display_name": "short UI name with Chinese translation, e.g. original tag / Chinese name",
      "role_reason": "why this role is one actual character and which evidence identifies it",
      "canonical_name": "character name with outfit/version/event qualifiers removed",
      "franchise": "source work or franchise such as princess_connect!",
      "raw_identity_tags": ["kokkoro (princess_connect!)", "kokkoro (ceremonial) (princess_connect!)"],
      "variant_tags": ["ceremonial"],
      "merge_with_role_id": "target role id when this role is the same canonical character, otherwise empty",
      "confidence": 0.0,
      "frame_indexes": [1, 2],
      "appearances": [
        {
          "source_id": "slot-0 or base",
          "source_kind": "slot or base",
          "frame_indexes": [1]
        }
      ],
      "evidence_terms": ["raw evidence terms"],
      "warnings": [],
      "stages": [
        {
          "stage_id": "stable id",
          "label": "short Chinese outfit label, context-aware when source evidence supports it",
          "appearance_group_id": "stable outfit or appearance group id",
          "merge_with_stage_ids": ["other stage ids that should merge into this stable appearance"],
          "field_reasons": {
            "identity": "why identity terms belong here",
            "upper_body": "why upper body terms belong here",
            "lower_body": "why lower body terms belong here",
            "upper_clothing": "why upper clothing terms belong here",
            "lower_clothing": "why lower clothing terms belong here",
            "omitted_terms": "why action, pose, expression, camera, scene, or temporary state terms were not output"
          },
          "confidence": 0.0,
          "frame_indexes": [1, 2],
          "identity": "comma separated raw tags",
          "upper_body": "comma separated raw tags",
          "lower_body": "comma separated raw tags",
          "upper_clothing": "comma separated raw tags",
          "lower_clothing": "comma separated raw tags",
          "evidence_terms": ["raw evidence terms"],
          "missing_fields": [],
          "warnings": []
        }
      ],
      "unassigned_terms": [
        {
          "term": "raw term",
          "frame_indexes": [1],
          "reason": "why not assigned"
        }
      ]
    }
  ],
  "artist_chains": [
    {
      "label": "official art or artist group",
      "terms": ["artist:example", "official art"],
      "frame_indexes": [1],
      "confidence": 0.0,
      "evidence_terms": ["artist:example", "official art"]
    }
  ],
  "strong_filter_keywords": [
    {
      "term": "mosaic censoring",
      "frame_indexes": [12],
      "reason": "mosaic/censor term found in script evidence"
    }
  ],
  "attention_items": [
    {
      "id": "stable id",
      "kind": "low_confidence or ambiguous_global_roles or missing_field or parse_failure",
      "message": "short explanation",
      "source_role_id": "optional role id",
      "frame_indexes": [],
      "blocking": false
    }
  ],
  "unassigned_terms": [
    {
      "term": "raw term",
      "frame_indexes": [1],
      "reason": "why not assigned"
    }
  ]
}
''';
}

class _OpenAiStreamAccumulator {
  final ScriptAiRoleExtractionStreamUpdate onStreamDelta;
  final StringBuffer _pending = StringBuffer();
  final StringBuffer _content = StringBuffer();
  final StringBuffer _reasoning = StringBuffer();

  _OpenAiStreamAccumulator({required this.onStreamDelta});

  void addText(String text) {
    if (text.isEmpty) {
      return;
    }
    _pending.write(text);
    _drainCompleteLines();
  }

  ScriptAiRoleExtractionClientResult finish() {
    final leftover = _pending.toString().trim();
    if (leftover.isNotEmpty) {
      _pending.clear();
      _processLine(leftover);
    }
    return ScriptAiRoleExtractionClientResult(
      rawJson: _content.toString(),
      reasoningContent: _reasoning.toString(),
    );
  }

  void _drainCompleteLines() {
    var text = _pending.toString();
    var newlineIndex = text.indexOf('\n');
    while (newlineIndex >= 0) {
      final line = text.substring(0, newlineIndex);
      _processLine(line);
      text = text.substring(newlineIndex + 1);
      newlineIndex = text.indexOf('\n');
    }
    _pending
      ..clear()
      ..write(text);
  }

  void _processLine(String rawLine) {
    final line = rawLine.trim();
    if (line.isEmpty || !line.startsWith('data:')) {
      return;
    }
    final payload = line.substring(5).trim();
    if (payload.isEmpty || payload == '[DONE]') {
      return;
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(payload);
    } on FormatException {
      return;
    }
    if (decoded is! Map) {
      return;
    }
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty || choices.first is! Map) {
      return;
    }
    final delta = (choices.first as Map)['delta'];
    if (delta is! Map) {
      return;
    }
    final reasoningDelta =
        OpenAiCompatibleScriptAiRoleExtractionClient._deltaString(
              delta,
              'reasoning_content',
            ) ??
            OpenAiCompatibleScriptAiRoleExtractionClient._deltaString(
              delta,
              'reasoning',
            ) ??
            '';
    final contentDelta =
        OpenAiCompatibleScriptAiRoleExtractionClient._deltaString(
              delta,
              'content',
            ) ??
            '';
    if (reasoningDelta.isNotEmpty) {
      _reasoning.write(reasoningDelta);
    }
    if (contentDelta.isNotEmpty) {
      _content.write(contentDelta);
    }
    OpenAiCompatibleScriptAiRoleExtractionClient._emitDelta(
      onStreamDelta,
      reasoningContentDelta: reasoningDelta,
      contentDelta: contentDelta,
    );
  }
}
