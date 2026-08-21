import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/data/studio/models/script_ai_role_extraction.dart';
import 'package:novel_studio/data/studio/models/script_recast.dart';
import 'package:novel_studio/data/studio/models/script_recast_knowledge.dart';
import 'package:novel_studio/data/studio/models/script_role_mapping_profile.dart';
import 'package:novel_studio/data/studio/services/role_mapping_profile_repository.dart';
import 'package:novel_studio/data/studio/services/script_recast_cache_restore_service.dart';
import 'package:novel_studio/data/studio/services/script_recast_parser_service.dart';
import 'package:novel_studio/data/studio/tools/prompt_tag_classifier.dart';
import 'package:novel_studio/ui/studio_core/theme/studio_theme.dart';
import 'package:novel_studio/ui/studio_core/widgets/prompt_tag_chip.dart';
import 'package:novel_studio/ui/studio_core/widgets/prompt_tag_display.dart';
import 'package:novel_studio/ui/studio_core/widgets/prompt_tag_editor.dart';
import 'package:novel_studio/ui/studio_script/view_models/studio_script_viewmodel.dart';
import 'package:novel_studio/ui/studio_script/widgets/role_mapping_profile_dialog.dart';
import 'package:novel_studio/ui/studio_script/widgets/studio_script_page.dart';

const _fixturePath = 'test/fixtures/script_recast/v4_slotted';

void main() {
  late Directory temporaryDirectory;
  late RoleMappingProfileRepository repository;
  late Script parsedScript;

  setUp(() async {
    temporaryDirectory =
        await Directory.systemTemp.createTemp('role-profile-viewmodel-test-');
    repository = RoleMappingProfileRepository(
      fileOverride: File(
        '${temporaryDirectory.path}${Platform.pathSeparator}profiles.json',
      ),
    );
    parsedScript = await const ScriptRecastParserService()
        .parseDirectory(Directory(_fixturePath));
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('creates a global grouped profile and persists active recording',
      () async {
    var caches = [_cache(parsedScript, _mappedSourceReplacement())];
    final viewModel = _viewModel(repository, caches, (next) => caches = next);

    await viewModel.importScriptPath(_fixturePath);
    final profile = await viewModel.createRoleMappingProfile(
      name: '百合花',
      sourceRoleId: 'slot-0',
    );

    expect(profile.blocks, hasLength(1));
    expect(profile.blocks.single.terms, hasLength(4));
    expect(
      profile.blocks.single.terms.every((term) => term.autoDetect),
      isTrue,
    );
    expect(
      viewModel.roleReplacementMappings.single.activeMappingProfileId,
      profile.id,
    );
    await Future<void>.delayed(const Duration(milliseconds: 550));
    final stored = await repository.load();
    expect(stored.profiles.single.name, '百合花');
    expect(
        caches.single.mapping.rolePromptReplacements.single
            .activeMappingProfileId,
        profile.id);
  });

  test('previews and automatically consolidates matching source terms',
      () async {
    var seedCaches = [_cache(parsedScript, _mappedSourceReplacement())];
    final seed = _viewModel(
      repository,
      seedCaches,
      (next) => seedCaches = next,
    );
    await seed.importScriptPath(_fixturePath);
    final profile = await seed.createRoleMappingProfile(
      name: '百合花',
      sourceRoleId: 'slot-0',
    );

    var targetCaches = [_cache(parsedScript, _splitTargetReplacement())];
    final target = _viewModel(
      repository,
      targetCaches,
      (next) => targetCaches = next,
    );
    await target.importScriptPath(_fixturePath);

    final preview = target.previewRoleMappingProfile(
      profileId: profile.id,
      sourceRoleId: 'slot-0',
    );
    final entry = preview.entries.single;
    expect(entry.selectedByDefault, isTrue);
    expect(entry.selectedTermIds, containsAll(['term-shun', 'term-loli']));
    expect(entry.selectedTermIds, isNot(contains('term-eyes')));

    await target.applyRoleMappingProfile(
      profileId: profile.id,
      sourceRoleId: 'slot-0',
      selections: [
        RoleMappingProfileApplySelection(
          blockId: entry.block.id,
          termIds: entry.selectedTermIds,
        ),
      ],
    );

    final rules = target.roleReplacementMappings.single.rules;
    final mapped = rules.singleWhere(
      (rule) => rule.targetPrompt == 'papyrus (arknights)',
    );
    expect(
      mapped.sourceTerms.map((term) => term.text),
      containsAll(['shun (small) (blue archive)', 'loli']),
    );
    expect(
      rules
          .expand((rule) => rule.sourceTerms)
          .where((term) => term.text == 'red eyes'),
      hasLength(1),
    );
  });

  test('active profile learns target edits and asks before deleting memory',
      () async {
    var caches = [_cache(parsedScript, _mappedSourceReplacement())];
    final viewModel = _viewModel(repository, caches, (next) => caches = next);
    await viewModel.importScriptPath(_fixturePath);
    final profile = await viewModel.createRoleMappingProfile(
      name: '百合花',
      sourceRoleId: 'slot-0',
    );

    viewModel.setRoleReplacementRuleTarget(
      'slot-0',
      'rule-identity',
      'papyrus (arknights), white hair',
    );
    expect(
      (await repository.load()).profiles.single.blocks.single.targetPrompt,
      'papyrus (arknights), white hair',
    );

    viewModel.setRoleReplacementRuleTarget(
      'slot-0',
      'rule-identity',
      '',
    );
    await repository.load();
    expect(viewModel.pendingRoleMappingProfileDeletion, isNotNull);
    expect(
      (await repository.load()).profiles.single.blocks,
      isNotEmpty,
    );

    await viewModel.resolveRoleMappingProfileDeletion(
      deleteFromProfile: true,
    );
    expect((await repository.load()).profiles.single.blocks, isEmpty);
    expect(
      viewModel.roleMappingProfileById(profile.id),
      isNotNull,
    );
  });

  test('missing linked material applies text without writing an invalid id',
      () async {
    var caches = [_cache(parsedScript, _mappedSourceReplacement())];
    final viewModel = _viewModel(repository, caches, (next) => caches = next);
    await viewModel.importScriptPath(_fixturePath);
    final created = await viewModel.createRoleMappingProfile(
      name: '佩佩',
      sourceRoleId: 'slot-0',
    );
    final profile = await viewModel.updateRoleMappingProfile(
      created.copyWith(
        targetCharacterId: 'missing-character',
        targetCharacterNameSnapshot: '已删除的佩佩素材',
      ),
    );

    await viewModel.applyRoleMappingProfile(
      profileId: profile.id,
      sourceRoleId: 'slot-0',
      selections: const [],
    );

    final current = viewModel.roleReplacementMappings.single;
    expect(current.targetCharacterId, isNull);
    expect(current.targetIdentityPrompt, 'papyrus (arknights)');
    expect(
      viewModel.roleMappingProfileById(profile.id)?.targetCharacterId,
      'missing-character',
    );
  });

  test(
      'merging selected rules keeps tag-system targets, weights, and final output',
      () async {
    const replacement = ScriptRolePromptReplacement(
      sourceRoleId: 'slot-0',
      displayLabel: '角色 1',
      rules: [
        ScriptPromptReplacementRule(
          id: 'tail-rule',
          sourceTerms: [
            ScriptPromptReplacementTerm(
              id: 'tail-term',
              text: 'fox_tail',
              category: PromptTagCategory.lowerBody,
              frameIndexes: [0],
            ),
          ],
          matchMode: ScriptPromptReplacementMatchMode.all,
        ),
        ScriptPromptReplacementRule(
          id: 'identity-rule',
          sourceTerms: [
            ScriptPromptReplacementTerm(
              id: 'identity-term',
              text: 'vulpisfoglia_(arknights)',
              category: PromptTagCategory.character,
              frameIndexes: [0],
            ),
          ],
          action: ScriptPromptReplacementAction.replace,
          targetPrompt: 'cat ears',
          targetWeightMultiplier: 2,
        ),
        ScriptPromptReplacementRule(
          id: 'umbrella-rule',
          sourceTerms: [
            ScriptPromptReplacementTerm(
              id: 'umbrella-term',
              text: 'holding umbrella',
              category: PromptTagCategory.action,
              frameIndexes: [1],
            ),
          ],
          action: ScriptPromptReplacementAction.replace,
          targetPrompt: '0.5:: cat tail ::',
        ),
      ],
      layerOverrides: [
        ScriptRoleReplacementRuleLayerOverride(
          ruleId: 'tail-rule',
          kind: ScriptRoleReplacementRuleLayerKind.shared,
        ),
        ScriptRoleReplacementRuleLayerOverride(
          ruleId: 'identity-rule',
          kind: ScriptRoleReplacementRuleLayerKind.shared,
        ),
        ScriptRoleReplacementRuleLayerOverride(
          ruleId: 'umbrella-rule',
          kind: ScriptRoleReplacementRuleLayerKind.shared,
        ),
      ],
    );
    var caches = [_cache(parsedScript, replacement)];
    final viewModel = _viewModel(repository, caches, (next) => caches = next);
    await viewModel.importScriptPath(_fixturePath);

    for (final rule in replacement.rules) {
      viewModel.setRoleReplacementRuleSelected('slot-0', rule.id, true);
    }
    viewModel.mergeSelectedRoleReplacementRules('slot-0');

    final merged = viewModel.roleReplacementMappings.single.rules.single;
    expect(
      merged.sourceTerms.map((term) => term.text),
      containsAll([
        'fox_tail',
        'vulpisfoglia_(arknights)',
        'holding umbrella',
      ]),
    );
    expect(merged.matchMode, ScriptPromptReplacementMatchMode.any);
    expect(merged.action, ScriptPromptReplacementAction.replace);
    expect(merged.targetPrompt, '2:: cat ears ::, 0.5:: cat tail ::');
    expect(merged.targetWeightMultiplier, isNull);
    expect(viewModel.diff.recast, contains('2:: cat ears ::'));
    expect(viewModel.diff.recast, contains('0.5:: cat tail ::'));
    expect(viewModel.diff.recast, isNot(contains('fox_tail')));

    await Future<void>.delayed(const Duration(milliseconds: 20));
    final cached =
        caches.single.mapping.rolePromptReplacements.single.rules.single;
    expect(cached.matchMode, ScriptPromptReplacementMatchMode.any);
    expect(cached.targetPrompt, '2:: cat ears ::, 0.5:: cat tail ::');
    expect(cached.targetWeightMultiplier, isNull);
  });

  test('drag-merging whole rules keeps both target tag sets', () async {
    const replacement = ScriptRolePromptReplacement(
      sourceRoleId: 'slot-0',
      displayLabel: '角色 1',
      rules: [
        ScriptPromptReplacementRule(
          id: 'source-rule',
          sourceTerms: [
            ScriptPromptReplacementTerm(
              id: 'identity-term',
              text: 'vulpisfoglia_(arknights)',
              category: PromptTagCategory.character,
              frameIndexes: [0],
            ),
          ],
          action: ScriptPromptReplacementAction.replace,
          targetPrompt: '1.5:: cat ears ::',
        ),
        ScriptPromptReplacementRule(
          id: 'target-rule',
          sourceTerms: [
            ScriptPromptReplacementTerm(
              id: 'tail-term',
              text: 'fox_tail',
              category: PromptTagCategory.lowerBody,
              frameIndexes: [0],
            ),
          ],
          action: ScriptPromptReplacementAction.replace,
          targetPrompt: 'cat tail',
        ),
      ],
      layerOverrides: [
        ScriptRoleReplacementRuleLayerOverride(
          ruleId: 'source-rule',
          kind: ScriptRoleReplacementRuleLayerKind.shared,
        ),
        ScriptRoleReplacementRuleLayerOverride(
          ruleId: 'target-rule',
          kind: ScriptRoleReplacementRuleLayerKind.shared,
        ),
      ],
    );
    var caches = [_cache(parsedScript, replacement)];
    final viewModel = _viewModel(repository, caches, (next) => caches = next);
    await viewModel.importScriptPath(_fixturePath);

    viewModel.mergeRoleReplacementRules(
      sourceRoleId: 'slot-0',
      sourceRuleId: 'source-rule',
      targetRuleId: 'target-rule',
    );

    final merged = viewModel.roleReplacementMappings.single.rules.single;
    expect(merged.id, 'target-rule');
    expect(merged.matchMode, ScriptPromptReplacementMatchMode.any);
    expect(merged.targetPrompt, 'cat tail, 1.5:: cat ears ::');
    expect(viewModel.diff.recast, contains('cat tail'));
    expect(viewModel.diff.recast, contains('1.5:: cat ears ::'));
  });

  test(
      'role replacement layers support manual assignment and split inheritance',
      () async {
    const assembly = RoleAssembly(
      sourceRoleId: 'slot-0',
      displayLabel: '角色 1',
      stages: [
        RoleAssemblyStage(
          id: 'casual',
          label: '便服',
          frameIndexes: [0, 1],
        ),
        RoleAssemblyStage(
          id: 'evening',
          label: '礼服',
          frameIndexes: [2, 3],
        ),
      ],
    );
    const replacement = ScriptRolePromptReplacement(
      sourceRoleId: 'slot-0',
      displayLabel: '角色 1',
      rules: [
        ScriptPromptReplacementRule(
          id: 'identity',
          sourceTerms: [
            ScriptPromptReplacementTerm(
              id: 'girl',
              text: 'girl',
              category: PromptTagCategory.character,
            ),
          ],
        ),
        ScriptPromptReplacementRule(
          id: 'casual-rule',
          sourceTerms: [
            ScriptPromptReplacementTerm(
              id: 'hoodie',
              text: 'hoodie',
              category: PromptTagCategory.upperClothing,
              frameIndexes: [0],
            ),
            ScriptPromptReplacementTerm(
              id: 'shorts',
              text: 'shorts',
              category: PromptTagCategory.lowerClothing,
              frameIndexes: [1],
            ),
          ],
        ),
      ],
    );
    var caches = [
      _cacheWithReplacements(
        parsedScript,
        const [replacement],
        roleAssemblies: const [assembly],
      ),
    ];
    final viewModel = _viewModel(repository, caches, (next) => caches = next);
    await viewModel.importScriptPath(_fixturePath);

    var role = viewModel.roleReplacementMappings.single;
    expect(role.layers.first.rules.map((rule) => rule.id), ['identity']);
    expect(
      role.layers
          .singleWhere((layer) => layer.stageId == 'casual')
          .rules
          .map((rule) => rule.id),
      ['casual-rule'],
    );
    viewModel.setRoleReplacementRuleSelected(
      'slot-0',
      'identity',
      true,
    );
    viewModel.setRoleReplacementRuleSelected(
      'slot-0',
      'casual-rule',
      true,
    );
    viewModel.mergeSelectedRoleReplacementRules('slot-0');
    expect(
      viewModel.roleReplacementMappings.single.rules,
      hasLength(2),
      reason: '跨层选择不能合并规则',
    );
    viewModel.clearRoleReplacementRuleSelection('slot-0');

    viewModel.assignRoleReplacementRulesToLayer(
      sourceRoleId: 'slot-0',
      ruleIds: const {'casual-rule'},
      kind: ScriptRoleReplacementRuleLayerKind.shared,
    );
    role = viewModel.roleReplacementMappings.single;
    expect(
      role.rules
          .singleWhere((rule) => rule.id == 'casual-rule')
          .manuallyLayered,
      isTrue,
    );

    viewModel.assignRoleReplacementRulesToLayer(
      sourceRoleId: 'slot-0',
      ruleIds: const {'casual-rule'},
      kind: ScriptRoleReplacementRuleLayerKind.stage,
      stageId: 'casual',
    );
    viewModel.splitRoleReplacementSourceTerms(
      sourceRoleId: 'slot-0',
      sourceRuleId: 'casual-rule',
      tags: const ['shorts'],
    );
    role = viewModel.roleReplacementMappings.single;
    final splitRules = role.rules
        .where((rule) => rule.id == 'casual-rule' || rule.id.contains('split'))
        .toList();
    expect(splitRules, hasLength(2));
    expect(splitRules.every((rule) => rule.manuallyLayered), isTrue);
    expect(splitRules.every((rule) => rule.layerStageId == 'casual'), isTrue);
    viewModel.clearRoleReplacementRuleSelection('slot-0');
    for (final rule in splitRules) {
      viewModel.setRoleReplacementRuleSelected(
        'slot-0',
        rule.id,
        true,
      );
    }
    viewModel.mergeSelectedRoleReplacementRules('slot-0');
    final mergedRules = viewModel.roleReplacementMappings.single.rules
        .where((rule) => rule.id != 'identity')
        .toList(growable: false);
    expect(mergedRules, hasLength(1));
    expect(mergedRules.single.manuallyLayered, isTrue);
    expect(mergedRules.single.layerStageId, 'casual');
  });

  test('stage edits prevent new overlaps and migrate manual assignments',
      () async {
    const assembly = RoleAssembly(
      sourceRoleId: 'slot-0',
      displayLabel: '角色 1',
      stages: [
        RoleAssemblyStage(
          id: 'casual',
          label: '便服',
          frameIndexes: [0, 1, 2],
        ),
        RoleAssemblyStage(
          id: 'evening',
          label: '礼服',
          frameIndexes: [3],
        ),
      ],
    );
    const replacement = ScriptRolePromptReplacement(
      sourceRoleId: 'slot-0',
      displayLabel: '角色 1',
      rules: [
        ScriptPromptReplacementRule(
          id: 'hoodie',
          sourceTerms: [
            ScriptPromptReplacementTerm(
              id: 'hoodie-term',
              text: 'hoodie',
              category: PromptTagCategory.upperClothing,
              frameIndexes: [0],
            ),
          ],
          targetPrompt: 'white hoodie',
        ),
      ],
    );
    var caches = [
      _cacheWithReplacements(
        parsedScript,
        const [replacement],
        roleAssemblies: const [assembly],
      ),
    ];
    final viewModel = _viewModel(repository, caches, (next) => caches = next);
    await viewModel.importScriptPath(_fixturePath);
    await viewModel.createRoleMappingProfile(
      name: '服装分层缓存',
      sourceRoleId: 'slot-0',
    );

    expect(
      viewModel.roleStageFrameOverlapMessage(
        sourceRoleId: 'slot-0',
        stageId: 'casual',
        frameIndexes: const [0, 3],
      ),
      isNotNull,
    );
    viewModel.setRoleStageFrameIndexes(
      sourceRoleId: 'slot-0',
      stageId: 'casual',
      frameIndexes: const [0, 3],
    );
    expect(
      viewModel.roleMappings.single.stageItems
          .singleWhere((stage) => stage.id == 'casual')
          .frameIndexes,
      [0, 1, 2],
    );

    viewModel.assignRoleReplacementRulesToLayer(
      sourceRoleId: 'slot-0',
      ruleIds: const {'hoodie'},
      kind: ScriptRoleReplacementRuleLayerKind.stage,
      stageId: 'casual',
    );
    final splitStageId = viewModel.splitRoleStage(
      sourceRoleId: 'slot-0',
      stageId: 'casual',
      label: '便服后段',
      frameIndexes: const [2],
    );
    expect(splitStageId, isNotNull);
    expect(
      viewModel.roleReplacementMappings.single.rules.single.layerStageId,
      'casual',
      reason: '人工归组在拆分时应留在原阶段',
    );

    expect(
      viewModel.mergeRoleStages(
        sourceRoleId: 'slot-0',
        sourceStageId: 'casual',
        targetStageId: splitStageId!,
      ),
      isTrue,
    );
    expect(
      viewModel.roleReplacementMappings.single.rules.single.layerStageId,
      splitStageId,
      reason: '合并阶段应迁移人工归组',
    );
    final profileAfterMerge = (await repository.load()).profiles.single;
    expect(
      profileAfterMerge.effectiveLayers
          .singleWhere((layer) => layer.id == 'stage:$splitStageId')
          .blocks,
      hasLength(1),
    );
    expect(
      viewModel.pendingRoleMappingProfileDeletion?.kind,
      RoleMappingProfileDeletionKind.layerMove,
    );
    await viewModel.resolveRoleMappingProfileDeletion(
      deleteFromProfile: false,
    );

    viewModel.deleteRoleStage(
      sourceRoleId: 'slot-0',
      stageId: splitStageId,
    );
    final profileAfterDelete = (await repository.load()).profiles.single;
    final pendingRule = viewModel.roleReplacementMappings.single.rules.single;
    expect(
      pendingRule.layerKind,
      ScriptRoleReplacementRuleLayerKind.pending,
    );
    expect(pendingRule.manuallyLayered, isTrue);
    expect(
      profileAfterDelete.effectiveLayers
          .singleWhere(
              (layer) => layer.kind == RoleMappingProfileLayerKind.pending)
          .blocks,
      hasLength(1),
    );
    expect(
      viewModel.pendingRoleMappingProfileDeletion?.kind,
      RoleMappingProfileDeletionKind.layerMove,
    );
    viewModel.deleteRoleStage(
      sourceRoleId: 'slot-0',
      stageId: 'evening',
    );
    expect(
      viewModel.roleReplacementMappings.single.stageCount,
      1,
      reason: '最后一个服装阶段不能删除',
    );
  });

  test('restoring AI layers replaces stage structure and clears overrides',
      () async {
    const assembly = RoleAssembly(
      sourceRoleId: 'slot-0',
      displayLabel: '角色 1',
      stages: [
        RoleAssemblyStage(
          id: 'manual-a',
          label: '人工阶段 A',
          frameIndexes: [0],
        ),
        RoleAssemblyStage(
          id: 'manual-b',
          label: '人工阶段 B',
          frameIndexes: [1],
        ),
      ],
    );
    const replacement = ScriptRolePromptReplacement(
      sourceRoleId: 'slot-0',
      displayLabel: '角色 1',
      layerOverrides: [
        ScriptRoleReplacementRuleLayerOverride(
          ruleId: 'hoodie',
          kind: ScriptRoleReplacementRuleLayerKind.stage,
          stageId: 'manual-b',
        ),
      ],
      rules: [
        ScriptPromptReplacementRule(
          id: 'hoodie',
          sourceTerms: [
            ScriptPromptReplacementTerm(
              id: 'hoodie-term',
              text: 'hoodie',
              category: PromptTagCategory.upperClothing,
              frameIndexes: [0],
            ),
          ],
        ),
      ],
    );
    var caches = [
      _cacheWithReplacements(
        parsedScript,
        const [replacement],
        roleAssemblies: const [assembly],
      ),
    ];
    final viewModel = _viewModel(repository, caches, (next) => caches = next);
    await viewModel.importScriptPath(_fixturePath);
    viewModel.aiRoleExtraction = const ScriptAiRoleExtraction(
      status: ScriptAiRoleExtractionStatus.ready,
      roles: [
        ScriptAiExtractedRole(
          sourceRoleId: 'slot-0',
          displayName: '角色 1',
          stages: [
            ScriptAiExtractedStage(
              stageId: 'ai-casual',
              label: 'AI 便服',
              frameIndexes: [0],
              upperClothing: 'hoodie',
            ),
            ScriptAiExtractedStage(
              stageId: 'ai-evening',
              label: 'AI 礼服',
              frameIndexes: [1],
              upperClothing: 'dress',
            ),
          ],
        ),
      ],
    );

    expect(viewModel.restoreAiRoleStageLayers('slot-0'), isTrue);

    final role = viewModel.roleReplacementMappings.single;
    expect(
      role.layers
          .where(
            (layer) => layer.kind == ScriptRoleReplacementRuleLayerKind.stage,
          )
          .map((layer) => layer.stageId),
      ['ai-casual', 'ai-evening'],
    );
    expect(role.rules.single.manuallyLayered, isFalse);
    expect(role.rules.single.layerStageId, 'ai-casual');
  });

  test('adding the first stage materializes an assembly for legacy mappings',
      () async {
    const replacement = ScriptRolePromptReplacement(
      sourceRoleId: 'slot-0',
      displayLabel: '旧缓存角色',
      rules: [
        ScriptPromptReplacementRule(
          id: 'hoodie',
          sourceTerms: [
            ScriptPromptReplacementTerm(
              id: 'hoodie-term',
              text: 'hoodie',
              category: PromptTagCategory.upperClothing,
              frameIndexes: [0],
            ),
          ],
        ),
      ],
    );
    var caches = [_cache(parsedScript, replacement)];
    final viewModel = _viewModel(repository, caches, (next) => caches = next);
    await viewModel.importScriptPath(_fixturePath);

    expect(
      viewModel.roleStageFrameOverlapMessage(
        sourceRoleId: 'slot-0',
        frameIndexes: const [0],
      ),
      isNull,
    );
    final stageId = viewModel.addRoleStage(
      sourceRoleId: 'slot-0',
      label: '便服',
      frameIndexes: const [0],
    );

    expect(stageId, isNotNull);
    expect(viewModel.roleReplacementMappings.single.stageCount, 1);
    expect(
      viewModel.roleReplacementMappings.single.rules.single.layerStageId,
      stageId,
    );
    viewModel.deleteRoleStage(
      sourceRoleId: 'slot-0',
      stageId: stageId!,
    );
    expect(
      viewModel.roleReplacementMappings.single.stageCount,
      1,
      reason: '首次建立的唯一阶段不能被删除',
    );
  });

  testWidgets('role layer tabs filter rules and accept rule-card drops',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    const assembly = RoleAssembly(
      sourceRoleId: 'slot-0',
      displayLabel: '角色 1',
      stages: [
        RoleAssemblyStage(
          id: 'casual',
          label: '便服',
          frameIndexes: [0],
        ),
        RoleAssemblyStage(
          id: 'evening',
          label: '礼服',
          frameIndexes: [1],
        ),
      ],
    );
    const replacement = ScriptRolePromptReplacement(
      sourceRoleId: 'slot-0',
      displayLabel: '角色 1',
      rules: [
        ScriptPromptReplacementRule(
          id: 'identity',
          sourceTerms: [
            ScriptPromptReplacementTerm(
              id: 'girl',
              text: 'girl',
              category: PromptTagCategory.character,
            ),
          ],
        ),
        ScriptPromptReplacementRule(
          id: 'hoodie',
          sourceTerms: [
            ScriptPromptReplacementTerm(
              id: 'hoodie-term',
              text: 'hoodie',
              category: PromptTagCategory.upperClothing,
              frameIndexes: [0],
            ),
          ],
        ),
        ScriptPromptReplacementRule(
          id: 'other-role-word',
          sourceTerms: [
            ScriptPromptReplacementTerm(
              id: 'other-role-word-term',
              text: 'blue archive',
              category: PromptTagCategory.other,
              frameIndexes: [0],
            ),
          ],
        ),
      ],
    );
    var caches = [
      _cacheWithReplacements(
        parsedScript,
        const [replacement],
        roleAssemblies: const [assembly],
      ),
    ];
    final viewModel = _viewModel(repository, caches, (next) => caches = next);
    await tester.runAsync(() => viewModel.importScriptPath(_fixturePath));
    await tester.pumpWidget(
      MaterialApp(
        theme: StudioTheme.build(),
        home: StudioScriptPage(viewModel: viewModel),
      ),
    );
    await tester.pump(const Duration(seconds: 2));

    final sharedTab = find.byKey(
      const ValueKey('role-replacement-layer-tab-slot-0-shared'),
    );
    final casualTab = find.byKey(
      const ValueKey('role-replacement-layer-tab-slot-0-stage:casual'),
    );
    final eveningTab = find.byKey(
      const ValueKey('role-replacement-layer-tab-slot-0-stage:evening'),
    );
    final pendingTab = find.byKey(
      const ValueKey('role-replacement-layer-tab-slot-0-pending'),
    );
    expect(sharedTab, findsOneWidget);
    expect(casualTab, findsOneWidget);
    expect(eveningTab, findsOneWidget);
    expect(pendingTab, findsOneWidget);
    expect(
      find.byKey(
        const ValueKey('replacement-rule-role-slot-0-identity'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('replacement-rule-role-slot-0-hoodie')),
      findsNothing,
    );

    await tester.ensureVisible(casualTab);
    await tester.pumpAndSettle();
    await tester.tap(casualTab);
    await tester.pumpAndSettle();
    final hoodieRule = find.byKey(
      const ValueKey('replacement-rule-role-slot-0-hoodie'),
    );
    expect(hoodieRule, findsOneWidget);
    expect(
      find.byKey(
        const ValueKey('replacement-rule-role-slot-0-identity'),
      ),
      findsNothing,
    );
    viewModel.setRoleReplacementRuleSelected(
      'slot-0',
      'hoodie',
      true,
    );
    await tester.pump();

    var dragHandle = find.byKey(
      const ValueKey(
        'replacement-rule-drag-handle-role-slot-0-hoodie',
      ),
    );
    final otherGroup = find.byKey(
      const ValueKey('replacement-rule-group-drop-role-slot-0-other'),
    );
    await tester.ensureVisible(otherGroup);
    await tester.drag(
      dragHandle,
      tester.getCenter(otherGroup) - tester.getCenter(dragHandle),
    );
    await tester.pumpAndSettle();

    var rule = viewModel.roleReplacementMappings.single.rules
        .singleWhere((entry) => entry.id == 'hoodie');
    expect(
      rule.sourceTerms.map((term) => term.category).toSet(),
      {PromptTagCategory.other},
    );
    expect(rule.selected, isFalse);

    viewModel.setRoleReplacementRuleSelected(
      'slot-0',
      'hoodie',
      true,
    );
    await tester.pump();
    dragHandle = find.byKey(
      const ValueKey(
        'replacement-rule-drag-handle-role-slot-0-hoodie',
      ),
    );
    await tester.drag(
      dragHandle,
      tester.getCenter(eveningTab) - tester.getCenter(dragHandle),
    );
    await tester.pumpAndSettle();

    rule = viewModel.roleReplacementMappings.single.rules
        .singleWhere((entry) => entry.id == 'hoodie');
    expect(rule.layerStageId, 'evening');
    expect(rule.manuallyLayered, isTrue);
    expect(rule.selected, isFalse);
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      caches.single.mapping.rolePromptReplacements.single.rules
          .singleWhere((entry) => entry.id == 'hoodie')
          .sourceTerms
          .map((term) => term.category)
          .toSet(),
      {PromptTagCategory.other},
    );
  });

  testWidgets(
      'compact role layer tabs expose pending state and stage editor without overflow',
      (tester) async {
    tester.view.physicalSize = const Size(900, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    const assembly = RoleAssembly(
      sourceRoleId: 'slot-0',
      displayLabel: '角色 1',
      stages: [
        RoleAssemblyStage(id: 'casual', label: '便服', frameIndexes: [0]),
        RoleAssemblyStage(id: 'evening', label: '礼服', frameIndexes: [1]),
      ],
    );
    const replacement = ScriptRolePromptReplacement(
      sourceRoleId: 'slot-0',
      displayLabel: '角色 1',
      rules: [
        ScriptPromptReplacementRule(
          id: 'mixed-outfit',
          sourceTerms: [
            ScriptPromptReplacementTerm(
              id: 'hoodie',
              text: 'hoodie',
              category: PromptTagCategory.upperClothing,
              frameIndexes: [0],
            ),
            ScriptPromptReplacementTerm(
              id: 'dress',
              text: 'dress',
              category: PromptTagCategory.upperClothing,
              frameIndexes: [1],
            ),
          ],
        ),
      ],
    );
    var caches = [
      _cacheWithReplacements(
        parsedScript,
        const [replacement],
        roleAssemblies: const [assembly],
      ),
    ];
    final viewModel = _viewModel(repository, caches, (next) => caches = next);
    await tester.runAsync(() => viewModel.importScriptPath(_fixturePath));
    await tester.pumpWidget(
      MaterialApp(
        theme: StudioTheme.build(),
        home: StudioScriptPage(viewModel: viewModel),
      ),
    );
    await tester.pump(const Duration(seconds: 2));

    expect(
      find.byKey(
        const ValueKey('role-replacement-layer-tab-slot-0-pending'),
      ),
      findsOneWidget,
    );
    expect(viewModel.roleReplacementMappings.single.pendingRuleCount, 1);
    final stageMenu = find.byKey(
      const ValueKey('role-stage-menu-slot-0'),
    );
    await tester.ensureVisible(stageMenu);
    await tester.tap(stageMenu);
    await tester.pumpAndSettle();
    expect(find.text('新增阶段'), findsOneWidget);

    await tester.tap(find.text('新增阶段'));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('role-stage-editor-dialog')), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('role-stage-label-field')),
      '战斗服',
    );
    await tester.enterText(
      find.byKey(const ValueKey('role-stage-frames-field')),
      '4-5',
    );
    await tester.tap(
      find.byKey(const ValueKey('role-stage-editor-save')),
    );
    await tester.pumpAndSettle();

    expect(viewModel.roleMappings.single.stageItems, hasLength(3));
    expect(find.text('战斗服'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 500));
  });

  testWidgets(
      'preview defaults to the chosen cache and applies deterministic overwrites',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final current = _mappedSourceReplacement();
    final timestamp = DateTime.utc(2026, 8, 20);
    final profile = RoleMappingProfile(
      id: 'profile-preview-overwrite',
      name: '百合花',
      targetIdentityPrompt: current.targetIdentityPrompt,
      blocks: [RoleMappingProfileBlock.fromRule(current.rules.single)],
      createdAt: timestamp,
      updatedAt: timestamp,
    );
    final inlineRepository = _InMemoryRoleMappingProfileRepository(
      RoleMappingProfileLibrary(profiles: [profile]),
    );
    final conflicting = current.copyWith(
      targetIdentityPrompt: 'old identity',
      activeMappingProfileId: null,
      rules: [
        current.rules.single.copyWith(targetPrompt: 'old mapped target'),
      ],
    );
    var targetCaches = [_cache(parsedScript, conflicting)];
    final target = _viewModel(
      inlineRepository,
      targetCaches,
      (next) => targetCaches = next,
    );
    await tester.runAsync(() => target.importScriptPath(_fixturePath));

    await tester.pumpWidget(
      MaterialApp(
        theme: StudioTheme.build(),
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              key: const ValueKey('open-deterministic-preview'),
              onPressed: () => showRoleMappingProfileApplyPreviewDialog(
                context,
                viewModel: target,
                profile: target.roleMappingProfileById(profile.id)!,
                sourceRoleId: 'slot-0',
              ),
              child: const Text('打开预览'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open-deterministic-preview')));
    await tester.pumpAndSettle();

    expect(find.text('系统已完成匹配'), findsOneWidget);
    expect(find.text('合并当前已有标签：'), findsNothing);
    final selectedSourceDisplay = tester.widget<PromptTagDisplay>(
      find.byKey(
        const ValueKey(
          'role-mapping-profile-preview-selected-source-rule-identity',
        ),
      ),
    );
    expect(selectedSourceDisplay.defaultTranslated, isTrue);
    expect(
      selectedSourceDisplay.classificationOverrides['loli'],
      PromptTagCategory.character,
    );
    expect(
      tester
          .widget<CheckboxListTile>(
            find.byKey(
              const ValueKey('role-mapping-profile-apply-identity'),
            ),
          )
          .value,
      isTrue,
    );
    final blockTile = find.ancestor(
      of: find.byKey(
        const ValueKey(
          'role-mapping-profile-preview-source-rule-identity',
        ),
      ),
      matching: find.byType(CheckboxListTile),
    );
    expect(tester.widget<CheckboxListTile>(blockTile).value, isTrue);

    await tester.tap(find.text('高级调整源标签'));
    await tester.pumpAndSettle();
    final sourceTermChip = tester.widget<PromptTagChip>(
      find.byKey(
        const ValueKey(
          'role-mapping-profile-source-term-rule-identity-term-loli',
        ),
      ),
    );
    expect(sourceTermChip.translationFirst, isTrue);
    expect(sourceTermChip.category, PromptTagCategory.character);
    expect(sourceTermChip.selected, isTrue);

    await tester.tap(
      find.byKey(const ValueKey('role-mapping-profile-apply')),
    );
    await tester.pumpAndSettle();

    final applied = target.roleReplacementMappings.single;
    expect(applied.targetIdentityPrompt, 'papyrus (arknights)');
    expect(applied.activeMappingProfileId, profile.id);
    expect(applied.rules.single.targetPrompt, 'papyrus (arknights)');
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets(
      'ambiguous cache stage preview lets the user choose shared and apply',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    const profileId = 'ambiguous-layer-profile';
    final timestamp = DateTime.utc(2026, 7, 24);
    final profile = RoleMappingProfile(
      id: profileId,
      name: '待选择分层缓存',
      layers: const [
        RoleMappingProfileLayer(
          id: 'cached-stage',
          kind: RoleMappingProfileLayerKind.stage,
          displayName: '缓存服装阶段',
          recognitionSignature: ['hoodie', 'dress'],
          blocks: [
            RoleMappingProfileBlock(
              id: 'hoodie-block',
              terms: [
                RoleMappingProfileTerm(
                  id: 'cached-hoodie',
                  text: 'hoodie',
                  normalizedKey: 'hoodie',
                ),
              ],
              targetPrompt: 'white hoodie',
            ),
          ],
        ),
        RoleMappingProfileLayer(
          id: 'cached-pending',
          kind: RoleMappingProfileLayerKind.pending,
          displayName: '待确认',
        ),
      ],
      createdAt: timestamp,
      updatedAt: timestamp,
    );
    final inlineRepository = _InMemoryRoleMappingProfileRepository(
      RoleMappingProfileLibrary(
        profiles: [profile],
      ),
    );
    const assembly = RoleAssembly(
      sourceRoleId: 'slot-0',
      displayLabel: '角色 1',
      stages: [
        RoleAssemblyStage(id: 'casual', label: '便服', frameIndexes: [0]),
        RoleAssemblyStage(id: 'evening', label: '礼服', frameIndexes: [1]),
      ],
    );
    const replacement = ScriptRolePromptReplacement(
      sourceRoleId: 'slot-0',
      displayLabel: '角色 1',
      rules: [
        ScriptPromptReplacementRule(
          id: 'hoodie-rule',
          sourceTerms: [
            ScriptPromptReplacementTerm(
              id: 'hoodie',
              text: 'hoodie',
              category: PromptTagCategory.upperClothing,
              frameIndexes: [0],
            ),
          ],
        ),
        ScriptPromptReplacementRule(
          id: 'dress-rule',
          sourceTerms: [
            ScriptPromptReplacementTerm(
              id: 'dress',
              text: 'dress',
              category: PromptTagCategory.upperClothing,
              frameIndexes: [1],
            ),
          ],
        ),
      ],
    );
    var caches = [
      _cacheWithReplacements(
        parsedScript,
        const [replacement],
        roleAssemblies: const [assembly],
      ),
    ];
    final viewModel =
        _viewModel(inlineRepository, caches, (next) => caches = next);
    await tester.runAsync(() => viewModel.importScriptPath(_fixturePath));
    final loadedProfile = viewModel.roleMappingProfileById(profileId)!;
    expect(
      viewModel
          .previewRoleMappingProfile(
            profileId: profileId,
            sourceRoleId: 'slot-0',
          )
          .layerEntries
          .singleWhere((entry) => entry.layer.id == 'cached-stage')
          .status,
      RoleMappingProfileLayerMatchStatus.ambiguous,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: StudioTheme.build(),
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              key: const ValueKey('open-layer-preview'),
              onPressed: () => showRoleMappingProfileApplyPreviewDialog(
                context,
                viewModel: viewModel,
                profile: loadedProfile,
                sourceRoleId: 'slot-0',
              ),
              child: const Text('打开预览'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open-layer-preview')));
    await tester.pumpAndSettle();
    expect(find.text('全局档案分层对应'), findsOneWidget);
    expect(
      tester
          .widget<DropdownButtonFormField<String>>(
            find.byKey(
              const ValueKey(
                'role-mapping-profile-layer-target-cached-pending',
              ),
            ),
          )
          .initialValue,
      'pending',
    );

    final layerTarget = find.byKey(
      const ValueKey(
        'role-mapping-profile-layer-target-cached-stage',
      ),
    );
    await tester.tap(layerTarget);
    await tester.pumpAndSettle();
    await tester.tap(find.text('共享层').last);
    await tester.pumpAndSettle();

    final blockTile = find.ancestor(
      of: find.byKey(
        const ValueKey(
          'role-mapping-profile-preview-source-hoodie-block',
        ),
      ),
      matching: find.byType(CheckboxListTile),
    );
    expect(tester.widget<CheckboxListTile>(blockTile).value, isTrue);
    await tester.tap(
      find.byKey(const ValueKey('role-mapping-profile-apply')),
    );
    await tester.pumpAndSettle();

    final rules = viewModel.roleReplacementMappings.single.rules;
    final mapped = rules
        .where((rule) => rule.targetPrompt == 'white hoodie')
        .toList(growable: false);
    expect(
      mapped,
      hasLength(1),
      reason:
          rules.map((rule) => '${rule.id}:${rule.targetPrompt}').join(' | '),
    );
    final hoodie = mapped.single;
    expect(hoodie.targetPrompt, 'white hoodie');
    expect(hoodie.layerKind, ScriptRoleReplacementRuleLayerKind.shared);
    expect(hoodie.manuallyLayered, isTrue);
    await tester.pump(const Duration(milliseconds: 500));
  });

  test('deleting a profile detaches recording but keeps visible mappings',
      () async {
    var caches = [_cache(parsedScript, _mappedSourceReplacement())];
    final viewModel = _viewModel(repository, caches, (next) => caches = next);
    await viewModel.importScriptPath(_fixturePath);
    final profile = await viewModel.createRoleMappingProfile(
      name: '佩佩',
      sourceRoleId: 'slot-0',
    );
    final visibleRules =
        viewModel.roleReplacementMappings.single.rules.map((rule) => rule.id);

    await viewModel.deleteRoleMappingProfile(profile.id);

    expect(
      viewModel.roleReplacementMappings.single.activeMappingProfileId,
      isNull,
    );
    expect(
      viewModel.roleReplacementMappings.single.rules.map((rule) => rule.id),
      visibleRules,
    );
  });

  testWidgets('role cache maintenance stays bound to the clicked role slot',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var caches = [_cache(parsedScript, _mappedSourceReplacement())];
    final viewModel = _viewModel(repository, caches, (next) => caches = next);
    await tester.runAsync(() async {
      await viewModel.importScriptPath(_fixturePath);
      await viewModel.createRoleMappingProfile(
        name: '百合花',
        sourceRoleId: 'slot-0',
      );
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: StudioTheme.build(),
        home: StudioScriptPage(viewModel: viewModel),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    expect(
      find.byKey(const ValueKey('role-mapping-profile-toolbar')),
      findsNothing,
    );
    final picker = find.byKey(
      const ValueKey('role-mapping-profile-picker-slot-0'),
    );
    expect(find.text('映射库（专属 0 · 全局 1）'), findsOneWidget);
    expect(find.text('剧本专属角色映射'), findsOneWidget);
    expect(
      find.textContaining('已连接全局角色档案“百合花”'),
      findsOneWidget,
    );
    final pickerSurface = tester.widget<Material>(
      find.byKey(
        const ValueKey('role-mapping-profile-picker-surface-slot-0'),
      ),
    );
    expect(pickerSurface.clipBehavior, Clip.antiAlias);
    final pickerInkWell = tester.widget<InkWell>(picker);
    expect(pickerInkWell.mouseCursor, SystemMouseCursors.click);
    expect(pickerInkWell.hoverColor, isNot(Colors.transparent));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(picker));
    await tester.pump(const Duration(milliseconds: 800));
    expect(
      find.text('蓝色为本剧本整套映射；黄色为跨剧本复用的全局角色档案'),
      findsOneWidget,
    );
    await mouse.moveTo(Offset.zero);
    await tester.pump();
    await tester.tap(picker);
    await tester.pumpAndSettle();
    final dropdown = find.byKey(
      const ValueKey('role-mapping-profile-dropdown-slot-0'),
    );
    expect(tester.widget<Material>(dropdown).clipBehavior, Clip.antiAlias);
    expect(
      find.byKey(const ValueKey('role-mapping-script-header-slot-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('role-mapping-script-current-slot-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey('role-mapping-profile-global-header-slot-0'),
      ),
      findsOneWidget,
    );
    expect(
      tester
          .getTopLeft(
            find.byKey(const ValueKey('role-mapping-script-header-slot-0')),
          )
          .dy,
      lessThan(
        tester
            .getTopLeft(
              find.byKey(
                const ValueKey('role-mapping-profile-global-header-slot-0'),
              ),
            )
            .dy,
      ),
    );
    final profileId = viewModel.roleMappingProfiles.single.id;
    final optionInkWell = tester.widget<InkWell>(
      find.byKey(
        ValueKey('role-mapping-profile-option-slot-0-$profileId'),
      ),
    );
    expect(optionInkWell.mouseCursor, SystemMouseCursors.click);
    expect(optionInkWell.hoverColor, isNot(Colors.transparent));
    final manageInkWell = tester.widget<InkWell>(
      find.byKey(const ValueKey('role-mapping-profile-manage-slot-0')),
    );
    expect(manageInkWell.mouseCursor, SystemMouseCursors.click);
    expect(manageInkWell.hoverColor, isNot(Colors.transparent));
    await tester.tap(
      find.byKey(const ValueKey('role-mapping-profile-manage-slot-0')),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('全局角色档案'), findsWidgets);
    expect(find.textContaining('当前栏位：源角色'), findsOneWidget);
    expect(find.text('百合花'), findsWidgets);
    expect(
      find.byKey(const ValueKey('role-mapping-profile-target-role')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('role-mapping-profile-fixed-target')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('role-mapping-profile-edit')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('role-mapping-profile-identity-display')),
      findsOneWidget,
    );
    expect(find.byType(PromptTagDisplay), findsAtLeastNWidgets(3));

    await tester.tap(
      find.byKey(const ValueKey('role-mapping-profile-edit')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('编辑全局角色档案'), findsOneWidget);
    expect(find.text('参与自动识别：'), findsWidgets);
    expect(find.text('匹配模式'), findsWidgets);
    expect(find.text('目标动作'), findsWidgets);
    expect(
      find.byKey(const ValueKey('role-mapping-profile-identity-editor')),
      findsOneWidget,
    );
    expect(find.byType(PromptTagEditor), findsAtLeastNWidgets(3));
  });

  testWidgets(
      'profile tag editors preserve term ids and detection while editing',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const profileId = 'profile-tag-editor';
    const blockId = 'block-stable';
    final timestamp = DateTime.utc(2026, 7, 23);
    final inlineRepository = _InMemoryRoleMappingProfileRepository(
      RoleMappingProfileLibrary(
        profiles: [
          RoleMappingProfile(
            id: profileId,
            name: '标签缓存',
            targetIdentityPrompt: 'old identity',
            blocks: const [
              RoleMappingProfileBlock(
                id: blockId,
                terms: [
                  RoleMappingProfileTerm(
                    id: 'term-a',
                    text: 'loli',
                    normalizedKey: 'loli',
                    autoDetect: false,
                  ),
                  RoleMappingProfileTerm(
                    id: 'term-b',
                    text: 'tiger girl',
                    normalizedKey: 'tiger_girl',
                  ),
                ],
                targetPrompt: 'old target',
                action: ScriptPromptReplacementAction.replace,
              ),
            ],
            createdAt: timestamp,
            updatedAt: timestamp,
          ),
        ],
      ),
    );
    var caches = [_cache(parsedScript, _mappedSourceReplacement())];
    final viewModel =
        _viewModel(inlineRepository, caches, (next) => caches = next);
    await tester.runAsync(() => viewModel.importScriptPath(_fixturePath));

    await tester.pumpWidget(
      MaterialApp(
        theme: StudioTheme.build(),
        home: StudioScriptPage(viewModel: viewModel),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    await tester.tap(
      find.byKey(const ValueKey('role-mapping-profile-picker-slot-0')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('role-mapping-profile-manage-slot-0')),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(
      find.byKey(const ValueKey('role-mapping-profile-edit')),
    );
    await tester.pump(const Duration(milliseconds: 400));

    tester
        .widget<PromptTagEditor>(
          find.byKey(
            const ValueKey('role-mapping-profile-identity-editor'),
          ),
        )
        .onChanged('new identity, blue eyes');
    tester
        .widget<PromptTagEditor>(
          find.byKey(
            const ValueKey(
              'role-mapping-profile-block-source-editor-block-stable',
            ),
          ),
        )
        .onChanged('tiger girl, loli, new tag');
    await tester.pump();
    tester
        .widget<PromptTagEditor>(
          find.byKey(
            const ValueKey(
              'role-mapping-profile-block-target-editor-block-stable',
            ),
          ),
        )
        .onChanged('new target, white hair');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pump(const Duration(seconds: 1));

    final updated = viewModel.roleMappingProfileById(profileId)!;
    expect(updated.targetIdentityPrompt, 'new identity, blue eyes');
    expect(updated.blocks.single.targetPrompt, 'new target, white hair');
    expect(
      updated.blocks.single.terms.map((term) => term.text),
      ['tiger girl', 'loli', 'new tag'],
    );
    expect(
      updated.blocks.single.terms
          .singleWhere((term) => term.text == 'tiger girl')
          .id,
      'term-b',
    );
    final loli =
        updated.blocks.single.terms.singleWhere((term) => term.text == 'loli');
    expect(loli.id, 'term-a');
    expect(loli.autoDetect, isFalse);
    final newTerm = updated.blocks.single.terms
        .singleWhere((term) => term.text == 'new tag');
    expect(newTerm.id, isNot(anyOf('term-a', 'term-b')));
  });

  testWidgets('role cache dropdown applies only to the clicked role slot',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const profileId = 'profile-inline-target';
    final timestamp = DateTime.utc(2026, 7, 23);
    final inlineRepository = _InMemoryRoleMappingProfileRepository(
      RoleMappingProfileLibrary(
        profiles: [
          RoleMappingProfile(
            id: profileId,
            name: '栏位二缓存',
            targetIdentityPrompt: 'cache target identity',
            blocks: const [
              RoleMappingProfileBlock(
                id: 'girl-cache-block',
                terms: [
                  RoleMappingProfileTerm(
                    id: 'cache-girl',
                    text: 'girl',
                    normalizedKey: 'girl',
                  ),
                ],
                action: ScriptPromptReplacementAction.replace,
                targetPrompt: 'cache mapped target',
              ),
              RoleMappingProfileBlock(
                id: 'unmatched-cache-block',
                terms: [
                  RoleMappingProfileTerm(
                    id: 'cache-unmatched',
                    text: 'fox tail',
                    normalizedKey: 'fox_tail',
                  ),
                ],
                action: ScriptPromptReplacementAction.replace,
                targetPrompt: 'unused target',
              ),
            ],
            createdAt: timestamp,
            updatedAt: timestamp,
          ),
        ],
      ),
    );
    var caches = [
      _cacheWithReplacements(
        parsedScript,
        const [
          ScriptRolePromptReplacement(
            sourceRoleId: 'slot-0',
            displayLabel: '第一角色',
            sourcePreview: 'first source',
            targetIdentityPrompt: 'first unchanged',
          ),
          ScriptRolePromptReplacement(
            sourceRoleId: 'slot-1',
            displayLabel: '第二角色',
            sourcePreview: 'second source, girl',
            targetIdentityPrompt: 'second before',
            rules: [
              ScriptPromptReplacementRule(
                id: 'slot-1-girl',
                sourceTerms: [
                  ScriptPromptReplacementTerm(
                    id: 'slot-1-current-girl',
                    text: 'girl',
                    category: PromptTagCategory.character,
                  ),
                ],
                action: ScriptPromptReplacementAction.replace,
                targetPrompt: 'old mapped target',
              ),
            ],
          ),
        ],
      ),
    ];
    final viewModel =
        _viewModel(inlineRepository, caches, (next) => caches = next);
    await tester.runAsync(() => viewModel.importScriptPath(_fixturePath));

    await tester.pumpWidget(
      MaterialApp(
        theme: StudioTheme.build(),
        home: StudioScriptPage(viewModel: viewModel),
      ),
    );
    await tester.pump(const Duration(seconds: 2));

    expect(
      find.byKey(const ValueKey('role-mapping-profile-picker-slot-0')),
      findsOneWidget,
    );
    final secondPicker = find.byKey(
      const ValueKey('role-mapping-profile-picker-slot-1'),
    );
    expect(secondPicker, findsOneWidget);
    await tester.tap(secondPicker);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const ValueKey(
          'role-mapping-profile-option-slot-1-profile-inline-target',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(
      find.byKey(const ValueKey('role-mapping-profile-dropdown-slot-1')),
      findsNothing,
    );
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(seconds: 1));
    });
    await tester.pump(const Duration(seconds: 1));

    final first = viewModel.roleReplacementMappings
        .singleWhere((role) => role.sourceRoleId == 'slot-0');
    final second = viewModel.roleReplacementMappings
        .singleWhere((role) => role.sourceRoleId == 'slot-1');
    expect(first.targetIdentityPrompt, 'first unchanged');
    expect(first.activeMappingProfileId, isNull);
    final snackBarTexts = tester
        .widgetList<Text>(
          find.descendant(
            of: find.byType(SnackBar),
            matching: find.byType(Text),
          ),
        )
        .map((widget) => widget.data)
        .whereType<String>()
        .toList();
    expect(
      second.targetIdentityPrompt,
      'cache target identity',
      reason: 'status=${viewModel.roleMappingProfileStatus}; '
          'snackbars=$snackBarTexts',
    );
    expect(second.activeMappingProfileId, profileId);
    expect(second.rules.single.targetPrompt, 'cache mapped target');
    expect(find.byType(Dialog), findsNothing);
  });
}

class _InMemoryRoleMappingProfileRepository
    extends RoleMappingProfileRepository {
  RoleMappingProfileLibrary library;

  _InMemoryRoleMappingProfileRepository(this.library);

  @override
  Future<RoleMappingProfileLibrary> load() async => library;

  @override
  Future<void> save(RoleMappingProfileLibrary next) async {
    library = next;
  }

  @override
  Future<RoleMappingProfileLibrary> update(
    RoleMappingProfileLibrary Function(RoleMappingProfileLibrary current)
        transform,
  ) async {
    library = transform(library);
    return library;
  }
}

StudioScriptViewModel _viewModel(
  RoleMappingProfileRepository repository,
  List<RecastScriptCache> caches,
  void Function(List<RecastScriptCache>) save,
) {
  return StudioScriptViewModel(
    roleMappingProfileRepository: repository,
    loadRecastCaches: () async => caches,
    saveRecastCaches: (next) async => save(next),
  );
}

RecastScriptCache _cache(
  Script script,
  ScriptRolePromptReplacement replacement,
) {
  return _cacheWithReplacements(script, [replacement]);
}

RecastScriptCache _cacheWithReplacements(
  Script script,
  List<ScriptRolePromptReplacement> replacements, {
  List<RoleAssembly> roleAssemblies = const [],
}) {
  const restoreService = ScriptRecastCacheRestoreService();
  return RecastScriptCache(
    scriptId: script.id,
    scriptName: script.name,
    sourceRootPath: script.rootPath,
    sourceFingerprint: restoreService.sourceFingerprint(script),
    sourceContentFingerprint: restoreService.sourceContentFingerprint(script),
    updatedAt: DateTime.utc(2026, 7, 23),
    mapping: RecastMapping.defaults(script.id).copyWith(
      rolePromptReplacements: replacements,
      roleAssemblies: roleAssemblies,
    ),
    scriptSnapshot: script.toJson(),
  );
}

ScriptRolePromptReplacement _mappedSourceReplacement() {
  return const ScriptRolePromptReplacement(
    sourceRoleId: 'slot-0',
    displayLabel: '源角色',
    sourcePreview: 'shun, loli',
    targetIdentityPrompt: 'papyrus (arknights)',
    rules: [
      ScriptPromptReplacementRule(
        id: 'rule-identity',
        sourceTerms: [
          ScriptPromptReplacementTerm(
            id: 'term-faceless',
            text: 'faceless female',
            category: PromptTagCategory.character,
            frameIndexes: [0],
          ),
          ScriptPromptReplacementTerm(
            id: 'term-loli',
            text: 'loli',
            category: PromptTagCategory.character,
            frameIndexes: [0],
          ),
          ScriptPromptReplacementTerm(
            id: 'term-shun',
            text: 'shun (small) (blue archive)',
            category: PromptTagCategory.character,
            frameIndexes: [0],
          ),
          ScriptPromptReplacementTerm(
            id: 'term-tiger',
            text: 'tiger girl',
            category: PromptTagCategory.character,
            frameIndexes: [0],
          ),
        ],
        action: ScriptPromptReplacementAction.replace,
        targetPrompt: 'papyrus (arknights)',
      ),
    ],
  );
}

ScriptRolePromptReplacement _splitTargetReplacement() {
  return const ScriptRolePromptReplacement(
    sourceRoleId: 'slot-0',
    displayLabel: '当前角色',
    sourcePreview: 'shun, loli, red eyes',
    rules: [
      ScriptPromptReplacementRule(
        id: 'rule-specific',
        sourceTerms: [
          ScriptPromptReplacementTerm(
            id: 'term-shun',
            text: 'shun (small) (blue archive)',
            category: PromptTagCategory.character,
            frameIndexes: [0],
          ),
        ],
      ),
      ScriptPromptReplacementRule(
        id: 'rule-mixed',
        sourceTerms: [
          ScriptPromptReplacementTerm(
            id: 'term-loli',
            text: 'loli',
            category: PromptTagCategory.character,
            frameIndexes: [1],
          ),
          ScriptPromptReplacementTerm(
            id: 'term-eyes',
            text: 'red eyes',
            category: PromptTagCategory.other,
            frameIndexes: [1],
          ),
        ],
      ),
    ],
  );
}
