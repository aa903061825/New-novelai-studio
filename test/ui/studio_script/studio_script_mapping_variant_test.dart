import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/data/studio/models/script_recast.dart';
import 'package:novel_studio/data/studio/models/script_recast_knowledge.dart';
import 'package:novel_studio/data/studio/models/script_role_mapping_profile.dart';
import 'package:novel_studio/data/studio/services/role_mapping_profile_repository.dart';
import 'package:novel_studio/data/studio/services/script_recast_cache_restore_service.dart';
import 'package:novel_studio/data/studio/services/script_recast_parser_service.dart';
import 'package:novel_studio/data/studio/tools/prompt_tag_classifier.dart';
import 'package:novel_studio/data/workspace/models/workspace_entities.dart';
import 'package:novel_studio/ui/studio_core/theme/studio_theme.dart';
import 'package:novel_studio/ui/studio_script/view_models/studio_script_viewmodel.dart';
import 'package:novel_studio/ui/studio_script/widgets/studio_script_page.dart';

const _fixturePath = 'test/fixtures/script_recast/v4_slotted';

void main() {
  group('StudioScriptViewModel mapping variants', () {
    test('switches and persists a complete version snapshot', () async {
      final fixture = await _variantFixture();
      RecastScriptCache? saved;
      var bulkLoadCount = 0;
      final viewModel = StudioScriptViewModel(
        loadRecastCacheByScriptId: (_) async => fixture.cache,
        loadRecastCaches: () async {
          bulkLoadCount += 1;
          throw StateError('single-script save must not scan all caches');
        },
        saveRecastCache: (cache) async => saved = cache,
      );

      await viewModel.importScriptPath(_fixturePath);
      await viewModel.activateMappingVariant('variant-b');

      expect(viewModel.activeMappingVariantId, 'variant-b');
      expect(
        viewModel.currentMapping!.promptBlockSwaps.single.manualPrompt,
        'version b style',
      );
      expect(
        viewModel.promptBlockMappings
            .firstWhere((item) => item.block == 'style')
            .manualPrompt,
        'version b style',
      );
      expect(saved, isNotNull);
      expect(bulkLoadCount, 0);
      expect(saved!.activeMappingVariantId, 'variant-b');
      expect(saved!.mappingVariants, hasLength(3));
      expect(
        saved!.mapping.promptBlockSwaps.single.manualPrompt,
        'version b style',
      );
    });

    test(
        'dropping a character keeps editable rules in the active script version',
        () async {
      final fixture = await _variantFixture();
      const replacement = ScriptRolePromptReplacement(
        sourceRoleId: 'slot-0',
        displayLabel: 'Mari',
        targetCharacterId: 'old-character',
        targetIdentityPrompt: 'old identity',
        activeMappingProfileId: 'old-global-profile',
        rules: [
          ScriptPromptReplacementRule(
            id: 'preserved-rule',
            sourceTerms: [
              ScriptPromptReplacementTerm(
                id: 'preserved-term',
                text: 'old source',
                category: PromptTagCategory.character,
              ),
            ],
            action: ScriptPromptReplacementAction.replace,
            targetPrompt: 'old target',
          ),
        ],
      );
      final mapping = fixture.cache.mapping.copyWith(
        rolePromptReplacements: const [replacement],
      );
      final cache = fixture.cache.copyWith(
        mapping: mapping,
        mappingVariants: [
          for (final variant in fixture.cache.mappingVariants)
            variant.id == 'variant-a'
                ? variant.copyWith(mapping: mapping)
                : variant,
        ],
      );
      final viewModel = StudioScriptViewModel(
        loadRecastCacheByScriptId: (_) async => cache,
        saveRecastCache: (_) async {},
        loadCharacters: () async => const [
          CharacterEntry(
            id: 'new-character',
            name: '新角色',
            traits: ViewVariantTexts(frontFull: 'new_character'),
          ),
        ],
      );

      await viewModel.importScriptPath(_fixturePath);
      viewModel.setRoleReplacementTargetCharacter(
        'slot-0',
        'new-character',
      );

      final current = viewModel.roleReplacementMappings.single;
      expect(viewModel.activeMappingVariantId, 'variant-a');
      expect(current.targetCharacterId, 'new-character');
      expect(current.activeMappingProfileId, isNull);
      expect(
          current.rules.single.action, ScriptPromptReplacementAction.replace);
      expect(current.rules.single.targetPrompt, 'old target');
      expect(
        viewModel.mappingVariantItems
            .singleWhere((item) => item.id == 'variant-a')
            .isModified,
        isTrue,
      );
    });

    test('rolls back the working mapping when switch persistence fails',
        () async {
      final fixture = await _variantFixture();
      final viewModel = StudioScriptViewModel(
        loadRecastCacheByScriptId: (_) async => fixture.cache,
        saveRecastCache: (_) async => throw StateError('disk unavailable'),
      );

      await viewModel.importScriptPath(_fixturePath);
      expect(viewModel.activeMappingVariantId, 'variant-a');

      await expectLater(
        viewModel.activateMappingVariant('variant-b'),
        throwsA(isA<StateError>()),
      );

      expect(viewModel.activeMappingVariantId, 'variant-a');
      expect(
        viewModel.currentMapping!.promptBlockSwaps.single.manualPrompt,
        'version a style',
      );
    });

    test('missing global profile keeps inline mapping and profile reference',
        () async {
      final fixture = await _variantFixture(includeProfileReference: true);
      final tempDirectory = await Directory.systemTemp.createTemp(
        'novel-studio-mapping-variant-profile-',
      );
      addTearDown(() => tempDirectory.delete(recursive: true));
      final repository = RoleMappingProfileRepository(
        fileOverride: File('${tempDirectory.path}/missing-profiles.json'),
      );
      final viewModel = StudioScriptViewModel(
        loadRecastCacheByScriptId: (_) async => fixture.cache,
        saveRecastCache: (_) async {},
        roleMappingProfileRepository: repository,
      );

      await viewModel.importScriptPath(_fixturePath);
      await viewModel.ensureRoleMappingProfilesLoaded();
      await viewModel.activateMappingVariant('variant-b');

      final replacement = viewModel.currentMapping!.rolePromptReplacements
          .firstWhere((entry) => entry.sourceRoleId == 'slot-0');
      expect(replacement.activeMappingProfileId, 'missing-global-profile');
      expect(replacement.targetIdentityPrompt, 'inline mari identity');
      expect(replacement.rules.single.targetPrompt, 'inline mari result');
    });

    test('saved version keeps profile target name without a character card',
        () async {
      final fixture = await _variantFixture(includeProfileReference: true);
      final tempDirectory = await Directory.systemTemp.createTemp(
        'novel-studio-mapping-variant-profile-name-',
      );
      addTearDown(() => tempDirectory.delete(recursive: true));
      final repository = RoleMappingProfileRepository(
        fileOverride: File('${tempDirectory.path}/profiles.json'),
      );
      final now = DateTime.utc(2026, 8, 20);
      await repository.save(
        RoleMappingProfileLibrary(
          profiles: [
            RoleMappingProfile(
              id: 'missing-global-profile',
              name: '迷迭香完整档案',
              targetCharacterNameSnapshot: '迷迭香',
              targetIdentityPrompt: 'inline mari identity',
              createdAt: now,
              updatedAt: now,
            ),
          ],
        ),
      );
      final replacement = fixture.cache.mapping.rolePromptReplacements.single
          .copyWith(targetCharacterId: null);
      final cache = fixture.cache.copyWith(
        mapping: fixture.cache.mapping.copyWith(
          rolePromptReplacements: [replacement],
        ),
        mappingVariants: const [],
        activeMappingVariantId: null,
      );
      RecastScriptCache? saved;
      final viewModel = StudioScriptViewModel(
        loadRecastCacheByScriptId: (_) async => cache,
        saveRecastCache: (next) async => saved = next,
        roleMappingProfileRepository: repository,
      );

      await viewModel.importScriptPath(_fixturePath);
      await viewModel.ensureRoleMappingProfilesLoaded();
      final variant = await viewModel.saveCurrentMappingAsVariant('迷迭香快照');

      expect(
        variant.targetCharacterNamesByRoleId,
        const {'slot-0': '迷迭香'},
      );
      expect(
        saved!.mappingVariants.single.targetCharacterNamesByRoleId,
        const {'slot-0': '迷迭香'},
      );
      expect(
        variant.mapping.rolePromptReplacements.single.activeMappingProfileId,
        'missing-global-profile',
      );
    });

    test(
        'scopes an automatic profile snapshot to the roles linked to that profile',
        () async {
      final fixture = await _variantFixture(includeProfileReference: true);
      final tempDirectory = await Directory.systemTemp.createTemp(
        'novel-studio-scoped-mapping-variants-',
      );
      addTearDown(() => tempDirectory.delete(recursive: true));
      final repository = RoleMappingProfileRepository(
        fileOverride: File('${tempDirectory.path}/profiles.json'),
      );
      final now = DateTime.utc(2026, 8, 20);
      final pepe = _requiredProfile('佩佩（无兜帽）', 0, now);
      final suzuran = _requiredProfile('铃兰', 1, now);
      await repository.save(
        RoleMappingProfileLibrary(profiles: [pepe, suzuran]),
      );
      final roleA = _requiredVariantSourceReplacement.copyWith(
        sourceRoleId: 'role-a',
        displayLabel: '角色 A',
        targetIdentityPrompt: 'baseline A',
        activeMappingProfileId: pepe.id,
      );
      final roleB = _requiredVariantSourceReplacement.copyWith(
        sourceRoleId: 'role-b',
        displayLabel: '角色 B',
        targetIdentityPrompt: 'baseline B',
        activeMappingProfileId: suzuran.id,
      );
      final baseMapping = fixture.cache.mapping.copyWith(
        rolePromptReplacements: [roleA, roleB],
      );
      final cache = fixture.cache.copyWith(
        mapping: baseMapping,
        mappingVariants: const [],
        activeMappingVariantId: null,
      );
      final viewModel = StudioScriptViewModel(
        loadRecastCacheByScriptId: (_) async => cache,
        saveRecastCache: (_) async {},
        roleMappingProfileRepository: repository,
      );

      await viewModel.importScriptPath(_fixturePath);

      expect(viewModel.mappingVariants, hasLength(2));
      final pepeVariant = viewModel.mappingVariants.singleWhere(
        (variant) => variant.name == '佩佩（无兜帽）',
      );
      final pepeRoleA = pepeVariant.mapping.rolePromptReplacements
          .singleWhere((replacement) => replacement.sourceRoleId == 'role-a');
      final pepeRoleB = pepeVariant.mapping.rolePromptReplacements
          .singleWhere((replacement) => replacement.sourceRoleId == 'role-b');
      expect(pepeRoleA.targetIdentityPrompt, 'identity-佩佩（无兜帽）');
      expect(pepeRoleA.activeMappingProfileId, pepe.id);
      expect(pepeRoleB.targetIdentityPrompt, 'baseline B');
      expect(pepeRoleB.activeMappingProfileId, suzuran.id);
      expect(
        pepeRoleB.rules
            .singleWhere((rule) => rule.id == 'girl-rule')
            .targetPrompt,
        'baseline girl',
        reason: '未绑定该档案的角色不能被整套覆盖',
      );
      expect(
        pepeVariant.targetCharacterNamesByRoleId,
        const {'role-a': '佩佩（无兜帽）', 'role-b': '铃兰'},
      );

      final suzuranVariant = viewModel.mappingVariants.singleWhere(
        (variant) => variant.name == '铃兰',
      );
      final suzuranRoleA = suzuranVariant.mapping.rolePromptReplacements
          .singleWhere((replacement) => replacement.sourceRoleId == 'role-a');
      final suzuranRoleB = suzuranVariant.mapping.rolePromptReplacements
          .singleWhere((replacement) => replacement.sourceRoleId == 'role-b');
      expect(suzuranRoleA.targetIdentityPrompt, 'baseline A');
      expect(suzuranRoleA.activeMappingProfileId, pepe.id);
      expect(suzuranRoleB.targetIdentityPrompt, 'identity-铃兰');
      expect(suzuranRoleB.activeMappingProfileId, suzuran.id);
    });

    test(
        'auto creates the linked global-profile snapshot without changing the working mapping',
        () async {
      final fixture = await _variantFixture(includeProfileReference: true);
      final tempDirectory = await Directory.systemTemp.createTemp(
        'novel-studio-required-mapping-variants-',
      );
      addTearDown(() => tempDirectory.delete(recursive: true));
      final repository = RoleMappingProfileRepository(
        fileOverride: File('${tempDirectory.path}/profiles.json'),
      );
      final now = DateTime.utc(2026, 8, 20);
      final requiredProfiles = [
        _requiredProfile(_requiredVariantTargets.first, 0, now),
      ];
      await repository.save(
        RoleMappingProfileLibrary(
          profiles: [
            _requiredProfile('不相关档案', 99, now),
            ...requiredProfiles.reversed,
          ],
        ),
      );
      final baseMapping = fixture.cache.mapping.copyWith(
        rolePromptReplacements: [
          _requiredVariantSourceReplacement.copyWith(
            activeMappingProfileId: requiredProfiles.single.id,
          ),
        ],
      );
      final cache = fixture.cache.copyWith(
        mapping: baseMapping,
        mappingVariants: const [],
        activeMappingVariantId: null,
      );
      RecastScriptCache? saved;
      final viewModel = StudioScriptViewModel(
        loadRecastCacheByScriptId: (_) async => cache,
        saveRecastCache: (next) async => saved = next,
        roleMappingProfileRepository: repository,
      );

      await viewModel.importScriptPath(_fixturePath);

      expect(viewModel.mappingVariants, hasLength(1));
      expect(
        viewModel.mappingVariants.map((variant) => variant.name).toSet(),
        {_requiredVariantTargets.first},
      );
      expect(viewModel.activeMappingVariantId, isNull);
      expect(
        viewModel.currentMapping!.rolePromptReplacements.single
            .activeMappingProfileId,
        requiredProfiles.single.id,
      );
      expect(
        viewModel
            .currentMapping!.rolePromptReplacements.single.targetIdentityPrompt,
        'baseline identity',
      );
      expect(
        viewModel.currentMapping!.promptBlockSwaps.single.manualPrompt,
        'version a style',
      );

      final profile = requiredProfiles.single;
      final target = _requiredVariantTargets.first;
      final variant = viewModel.mappingVariants.singleWhere(
        (entry) => entry.id == 'auto-global-profile-${profile.id}',
      );
      expect(variant.scriptId, cache.scriptId);
      expect(variant.sourceFingerprint, cache.sourceFingerprint);
      expect(
        variant.sourceContentFingerprint,
        cache.sourceContentFingerprint,
      );
      expect(
        variant.targetCharacterNamesByRoleId,
        {'slot-0': target},
      );
      expect(
        variant.mapping.promptBlockSwaps.single.manualPrompt,
        'version a style',
        reason: '版本必须保留整套剧本映射中的非角色字段',
      );
      final replacement = variant.mapping.rolePromptReplacements.single;
      expect(replacement.activeMappingProfileId, profile.id);
      expect(replacement.targetIdentityPrompt, 'identity-$target');
      final girlRule = replacement.rules.singleWhere(
        (rule) => rule.sourceTerms.any((term) => term.id == 'girl-term'),
      );
      final hoodieRule = replacement.rules.singleWhere(
        (rule) => rule.sourceTerms.any((term) => term.id == 'hoodie-term'),
      );
      expect(
        girlRule.targetPrompt,
        'identity-$target',
        reason: '角色身份规则必须使用完整角色身份输出，而不是局部映射片段',
      );
      expect(
        hoodieRule.targetPrompt,
        'mapped-$target-hoodie',
        reason: '必须读取第二层档案，而不是只读取首层',
      );

      expect(saved, isNotNull);
      expect(
        saved!.mappingVariants,
        hasLength(1),
      );
      expect(
        saved!.mapping.rolePromptReplacements.single.activeMappingProfileId,
        requiredProfiles.single.id,
      );
      expect(await viewModel.ensureRequiredScriptMappingVariants(), 0);
      expect(viewModel.mappingVariants, hasLength(1));
    });

    test('keeps the 星移 outfit as a required script-level variant', () async {
      final fixture = await _variantFixture(includeProfileReference: true);
      final tempDirectory = await Directory.systemTemp.createTemp(
        'novel-studio-xingyi-mapping-variant-',
      );
      addTearDown(() => tempDirectory.delete(recursive: true));
      final repository = RoleMappingProfileRepository(
        fileOverride: File('${tempDirectory.path}/profiles.json'),
      );
      final now = DateTime.utc(2026, 8, 22);
      final xingyi = _requiredProfile('佩佩（星移）', 42, now);
      await repository.save(
        RoleMappingProfileLibrary(profiles: [xingyi]),
      );
      final cache = fixture.cache.copyWith(
        mapping: fixture.cache.mapping.copyWith(
          rolePromptReplacements: [
            _requiredVariantSourceReplacement.copyWith(
              activeMappingProfileId: xingyi.id,
            ),
          ],
        ),
        mappingVariants: const [],
        activeMappingVariantId: null,
      );
      RecastScriptCache? saved;
      final viewModel = StudioScriptViewModel(
        loadRecastCacheByScriptId: (_) async => cache,
        saveRecastCache: (next) async => saved = next,
        roleMappingProfileRepository: repository,
      );

      await viewModel.importScriptPath(_fixturePath);

      expect(
        viewModel.mappingVariants.map((variant) => variant.name),
        contains('佩佩（星移）'),
      );
      expect(saved, isNotNull);
      expect(
        saved!.mappingVariants.map((variant) => variant.name),
        contains('佩佩（星移）'),
      );
    });

    test('generates only profiles linked to a source role', () async {
      final fixture = await _variantFixture(includeProfileReference: true);
      final tempDirectory = await Directory.systemTemp.createTemp(
        'novel-studio-incomplete-mapping-variants-',
      );
      addTearDown(() => tempDirectory.delete(recursive: true));
      final repository = RoleMappingProfileRepository(
        fileOverride: File('${tempDirectory.path}/profiles.json'),
      );
      final now = DateTime.utc(2026, 8, 20);
      await repository.save(
        RoleMappingProfileLibrary(
          profiles: [
            _requiredProfile('不相关档案', 99, now),
            _requiredProfile(_requiredVariantTargets.first, 0, now),
            _requiredProfile(_requiredVariantTargets[1], 1, now),
            _requiredProfile(_requiredVariantTargets[2], 2, now),
            _requiredProfile(_requiredVariantTargets[3], 3, now),
          ],
        ),
      );
      final cache = fixture.cache.copyWith(
        mapping: fixture.cache.mapping.copyWith(
          rolePromptReplacements: [
            _requiredVariantSourceReplacement.copyWith(
              activeMappingProfileId: 'required-profile-0',
            ),
          ],
        ),
        mappingVariants: [
          RecastMappingVariant(
            id: 'auto-global-profile-required-profile-1',
            name: _requiredVariantTargets[1],
            scriptId: fixture.cache.scriptId,
            sourceFingerprint: fixture.cache.sourceFingerprint,
            capturedAt: DateTime.utc(2026, 8, 19),
            mapping: fixture.cache.mapping,
            targetCharacterNamesByRoleId: const {'slot-0': '铃兰'},
          ),
          RecastMappingVariant(
            id: 'auto-global-profile-unrelated-profile',
            name: '不相关档案',
            scriptId: fixture.cache.scriptId,
            sourceFingerprint: fixture.cache.sourceFingerprint,
            sourceContentFingerprint: fixture.cache.sourceContentFingerprint,
            capturedAt: DateTime.utc(2026, 8, 19, 1),
            mapping: fixture.cache.mapping,
            targetCharacterNamesByRoleId: const {'slot-0': '不相关档案'},
          ),
        ],
        activeMappingVariantId: null,
      );
      final viewModel = StudioScriptViewModel(
        loadRecastCacheByScriptId: (_) async => cache,
        saveRecastCache: (_) async {},
        roleMappingProfileRepository: repository,
      );

      await viewModel.importScriptPath(_fixturePath);

      expect(
        viewModel.mappingVariants,
        hasLength(2),
        reason: '有效的必需离线版本要保留，但未列入必需角色的陈旧版本要清理',
      );
      expect(
        viewModel.mappingVariants.any((variant) => variant.name == '铃兰'),
        isTrue,
      );
      expect(
        viewModel.mappingVariants.any((variant) => variant.name == '不相关档案'),
        isFalse,
      );
      expect(
        viewModel.currentMapping!.rolePromptReplacements.single
            .activeMappingProfileId,
        'required-profile-0',
      );
    });

    test(
        'preserves valid offline required variants that are not linked by the working mapping',
        () async {
      final fixture = await _variantFixture(includeProfileReference: true);
      final tempDirectory = await Directory.systemTemp.createTemp(
        'novel-studio-preserve-required-variants-',
      );
      addTearDown(() => tempDirectory.delete(recursive: true));
      final repository = RoleMappingProfileRepository(
        fileOverride: File('${tempDirectory.path}/profiles.json'),
      );
      final now = DateTime.utc(2026, 8, 20);
      final linkedProfile = _requiredProfile(
        _requiredVariantTargets.first,
        0,
        now,
      );
      final offlineProfile = _requiredProfile(
        _requiredVariantTargets[1],
        1,
        now,
      );
      await repository.save(
        RoleMappingProfileLibrary(
          profiles: [linkedProfile, offlineProfile],
        ),
      );
      final baseMapping = fixture.cache.mapping.copyWith(
        rolePromptReplacements: [
          _requiredVariantSourceReplacement.copyWith(
            activeMappingProfileId: linkedProfile.id,
          ),
        ],
      );
      final offlineVariant = RecastMappingVariant(
        id: 'auto-global-profile-${offlineProfile.id}',
        name: offlineProfile.name,
        scriptId: fixture.cache.scriptId,
        sourceFingerprint: fixture.cache.sourceFingerprint,
        sourceContentFingerprint: fixture.cache.sourceContentFingerprint,
        capturedAt: DateTime.utc(2026, 8, 19),
        mapping: baseMapping,
        targetCharacterNamesByRoleId: const {'slot-0': '铃兰'},
      );
      final cache = fixture.cache.copyWith(
        mapping: baseMapping,
        mappingVariants: [offlineVariant],
        activeMappingVariantId: null,
      );
      final viewModel = StudioScriptViewModel(
        loadRecastCacheByScriptId: (_) async => cache,
        saveRecastCache: (_) async {},
        roleMappingProfileRepository: repository,
      );

      await viewModel.importScriptPath(_fixturePath);

      expect(
        viewModel.mappingVariants.map((variant) => variant.name).toSet(),
        {_requiredVariantTargets.first, _requiredVariantTargets[1]},
        reason: '已有的有效离线版本不能因为当前映射未链接它而被删除',
      );
      expect(
        viewModel.mappingVariants,
        hasLength(2),
      );
      expect(
        viewModel.mappingVariants
            .singleWhere((variant) => variant.name == offlineProfile.name)
            .id,
        'auto-global-profile-${offlineProfile.id}',
      );
    });
  });

  testWidgets('page lists, switches, and saves script mapping versions',
      (tester) async {
    tester.view.physicalSize = const Size(1500, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    late _VariantFixture fixture;
    await tester.runAsync(() async {
      fixture = await _variantFixture();
    });
    RecastScriptCache? saved;
    final viewModel = StudioScriptViewModel(
      loadRecastCacheByScriptId: (_) async => fixture.cache,
      saveRecastCache: (cache) async => saved = cache,
    );
    await tester.runAsync(() async {
      await viewModel.importScriptPath(_fixturePath);
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: StudioTheme.build(),
        home: StudioScriptPage(viewModel: viewModel),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('剧本级版本 (3)'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('script-mapping-version-open')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('script-mapping-version-dialog')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('script-mapping-version-panel')),
      findsOneWidget,
    );
    expect(find.text('剧本级映射版本'), findsWidgets);
    expect(find.textContaining('全局角色档案'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('script-mapping-version-current-variant-a')),
      findsOneWidget,
    );
    expect(find.textContaining('空映射（无规则）'), findsOneWidget);
    expect(find.textContaining('目标：迷迭香'), findsOneWidget);

    final variantB =
        find.byKey(const ValueKey('script-mapping-version-option-variant-b'));
    await tester.ensureVisible(variantB);
    await tester.tap(variantB);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(viewModel.activeMappingVariantId, 'variant-b');
    expect(
      find.byKey(const ValueKey('script-mapping-version-current-variant-b')),
      findsOneWidget,
    );

    final saveButton =
        find.byKey(const ValueKey('script-mapping-version-save'));
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.byKey(const ValueKey('script-mapping-version-name-dialog')),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const ValueKey('script-mapping-version-name-field')),
      '用户 r15 现状',
    );
    await tester.tap(
      find.byKey(const ValueKey('script-mapping-version-name-confirm')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(viewModel.mappingVariants, hasLength(4));
    expect(find.text('用户 r15 现状'), findsOneWidget);
    expect(saved, isNotNull);
    expect(saved!.mappingVariants, hasLength(4));
  });

  testWidgets(
      'role picker applies a saved script version to the current role only',
      (tester) async {
    tester.view.physicalSize = const Size(1500, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    late _VariantFixture fixture;
    await tester.runAsync(() async {
      fixture = await _variantFixture(
        includeProfileReference: true,
        distinctRoleMapping: true,
      );
    });
    RecastScriptCache? saved;
    final viewModel = StudioScriptViewModel(
      loadRecastCacheByScriptId: (_) async => fixture.cache,
      saveRecastCache: (cache) async => saved = cache,
    );
    await tester.runAsync(() async {
      await viewModel.importScriptPath(_fixturePath);
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: StudioTheme.build(),
        home: StudioScriptPage(viewModel: viewModel),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    final picker = find.byKey(
      const ValueKey('role-mapping-profile-picker-slot-0'),
    );
    await tester.ensureVisible(picker);
    expect(find.text('映射库（剧本版本 3 · 全局档案 0）'), findsOneWidget);
    await tester.tap(picker);
    await tester.pumpAndSettle();

    final scriptHeader = find.byKey(
      const ValueKey('role-mapping-script-header-slot-0'),
    );
    final globalHeader = find.byKey(
      const ValueKey('role-mapping-profile-global-header-slot-0'),
    );
    expect(scriptHeader, findsOneWidget);
    expect(globalHeader, findsOneWidget);
    expect(
      tester.getTopLeft(scriptHeader).dy,
      lessThan(tester.getTopLeft(globalHeader).dy),
    );
    expect(
      find.byKey(const ValueKey('role-mapping-script-current-slot-0')),
      findsOneWidget,
    );
    expect(find.text('当前角色的剧本缓存'), findsOneWidget);
    expect(find.text('全局角色档案'), findsOneWidget);
    expect(find.textContaining('空映射（无规则）'), findsOneWidget);
    expect(find.textContaining('此角色：迷迭香'), findsOneWidget);

    final variantB = find.byKey(
      const ValueKey('role-mapping-script-variant-slot-0-variant-b'),
    );
    await tester.ensureVisible(variantB);
    await tester.tap(variantB);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(viewModel.activeMappingVariantId, 'variant-a');
    expect(
      viewModel.currentMapping!.promptBlockSwaps.single.manualPrompt,
      'version a style',
    );
    expect(
      viewModel.currentMapping!.artistSwap?.manualPrompt,
      'version a style artist',
    );
    expect(
      viewModel
          .currentMapping!.rolePromptReplacements.single.targetIdentityPrompt,
      'variant b role',
    );
    expect(saved?.activeMappingVariantId, 'variant-a');
    expect(
      find.byKey(const ValueKey('role-mapping-profile-dropdown-slot-0')),
      findsNothing,
    );
  });
}

const _requiredVariantTargets = [
  '佩佩（无兜帽）',
  '铃兰',
  '巫恋',
  '迷迭香',
  '薄绿',
  '洛可可',
  '洛茜',
  '果宝',
  '佩佩（星移）',
];

const _requiredVariantSourceReplacement = ScriptRolePromptReplacement(
  sourceRoleId: 'slot-0',
  displayLabel: 'Mari',
  targetIdentityPrompt: 'baseline identity',
  activeMappingProfileId: 'manual-r15',
  rules: [
    ScriptPromptReplacementRule(
      id: 'girl-rule',
      sourceTerms: [
        ScriptPromptReplacementTerm(
          id: 'girl-term',
          text: 'girl',
          category: PromptTagCategory.character,
        ),
      ],
      action: ScriptPromptReplacementAction.replace,
      targetPrompt: 'baseline girl',
    ),
    ScriptPromptReplacementRule(
      id: 'hoodie-rule',
      sourceTerms: [
        ScriptPromptReplacementTerm(
          id: 'hoodie-term',
          text: 'hoodie',
          category: PromptTagCategory.upperClothing,
        ),
      ],
      action: ScriptPromptReplacementAction.replace,
      targetPrompt: 'baseline hoodie',
    ),
  ],
);

RoleMappingProfile _requiredProfile(
  String target,
  int index,
  DateTime now,
) {
  final profileId = 'required-profile-$index';
  return RoleMappingProfile(
    id: profileId,
    name: target,
    targetCharacterNameSnapshot: target,
    targetIdentityPrompt: 'identity-$target',
    layers: [
      RoleMappingProfileLayer(
        id: '$profileId-shared',
        kind: RoleMappingProfileLayerKind.shared,
        displayName: '共享',
        blocks: [
          RoleMappingProfileBlock.fromRule(
            ScriptPromptReplacementRule(
              id: '$profileId-girl',
              sourceTerms: const [
                ScriptPromptReplacementTerm(
                  id: 'girl-term',
                  text: 'girl',
                  category: PromptTagCategory.character,
                ),
              ],
              action: ScriptPromptReplacementAction.replace,
              targetPrompt: 'mapped-$target-girl',
            ),
          ),
        ],
      ),
      RoleMappingProfileLayer(
        id: '$profileId-pending',
        kind: RoleMappingProfileLayerKind.pending,
        displayName: '待确认',
        blocks: [
          RoleMappingProfileBlock.fromRule(
            ScriptPromptReplacementRule(
              id: '$profileId-hoodie',
              sourceTerms: const [
                ScriptPromptReplacementTerm(
                  id: 'hoodie-term',
                  text: 'hoodie',
                  category: PromptTagCategory.upperClothing,
                ),
              ],
              action: ScriptPromptReplacementAction.replace,
              targetPrompt: 'mapped-$target-hoodie',
            ),
          ),
        ],
      ),
    ],
    createdAt: now,
    updatedAt: now,
  );
}

Future<_VariantFixture> _variantFixture({
  bool includeProfileReference = false,
  bool distinctRoleMapping = false,
}) async {
  final script = await const ScriptRecastParserService().parseDirectory(
    Directory(_fixturePath),
  );
  const restoreService = ScriptRecastCacheRestoreService();
  final sourceFingerprint = restoreService.sourceFingerprint(script);
  final sourceContentFingerprint =
      restoreService.sourceContentFingerprint(script);
  final mappingA = _mapping(
    script.id,
    stylePrompt: 'version a style',
    includeProfileReference: includeProfileReference,
    roleIdentityPrompt: distinctRoleMapping ? 'variant a role' : null,
  );
  final mappingB = _mapping(
    script.id,
    stylePrompt: 'version b style',
    includeProfileReference: includeProfileReference,
    roleIdentityPrompt: distinctRoleMapping ? 'variant b role' : null,
  );
  final variants = [
    RecastMappingVariant(
      id: 'variant-a',
      name: 'r14',
      scriptId: script.id,
      sourceFingerprint: sourceFingerprint,
      sourceContentFingerprint: sourceContentFingerprint,
      capturedAt: DateTime.utc(2026, 8, 20, 1),
      mapping: mappingA,
      targetCharacterNamesByRoleId: const {'slot-0': '巫恋'},
    ),
    RecastMappingVariant(
      id: 'variant-b',
      name: 'r15 Mari',
      scriptId: script.id,
      sourceFingerprint: sourceFingerprint,
      sourceContentFingerprint: sourceContentFingerprint,
      capturedAt: DateTime.utc(2026, 8, 20, 2),
      mapping: mappingB,
      targetCharacterNamesByRoleId: const {'slot-0': '迷迭香'},
    ),
    RecastMappingVariant(
      id: 'variant-empty',
      name: '空白对照',
      scriptId: script.id,
      sourceFingerprint: sourceFingerprint,
      sourceContentFingerprint: sourceContentFingerprint,
      capturedAt: DateTime.utc(2026, 8, 20, 3),
      mapping: RecastMapping.defaults(script.id),
    ),
  ];
  return _VariantFixture(
    cache: RecastScriptCache(
      scriptId: script.id,
      scriptName: script.name,
      sourceRootPath: script.rootPath,
      sourceFingerprint: sourceFingerprint,
      sourceContentFingerprint: sourceContentFingerprint,
      updatedAt: DateTime.utc(2026, 8, 20, 3),
      mapping: mappingA,
      mappingVariants: variants,
      activeMappingVariantId: 'variant-a',
      scriptSnapshot: script.toJson(),
    ),
  );
}

RecastMapping _mapping(
  String scriptId, {
  required String stylePrompt,
  required bool includeProfileReference,
  String? roleIdentityPrompt,
}) {
  return RecastMapping.defaults(scriptId).copyWith(
    artistSwap: ArtistSwap(
      targetArtistChainId: '',
      manualPrompt: '$stylePrompt artist',
    ),
    promptBlockSwaps: [
      PromptBlockSwap(
        block: 'style',
        manualPrompt: stylePrompt,
      ),
    ],
    rolePromptReplacements: includeProfileReference
        ? [
            ScriptRolePromptReplacement(
              sourceRoleId: 'slot-0',
              displayLabel: 'Mari',
              targetCharacterId: 'mari',
              targetIdentityPrompt:
                  roleIdentityPrompt ?? 'inline mari identity',
              activeMappingProfileId: 'missing-global-profile',
              rules: [
                ScriptPromptReplacementRule(
                  id: 'mari-rule',
                  action: ScriptPromptReplacementAction.replace,
                  targetPrompt: 'inline mari result',
                ),
              ],
            ),
          ]
        : const [],
  );
}

class _VariantFixture {
  final RecastScriptCache cache;

  const _VariantFixture({required this.cache});
}
