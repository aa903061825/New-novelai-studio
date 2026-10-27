import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/data/studio/models/script_recast.dart';
import 'package:novel_studio/data/studio/models/script_role_mapping_profile.dart';
import 'package:novel_studio/data/studio/services/script_role_mapping_profile_service.dart';
import 'package:novel_studio/data/studio/tools/prompt_tag_classifier.dart';
import 'package:novel_studio/data/workspace/models/workspace_entities.dart';

void main() {
  const service = ScriptRoleMappingProfileService();

  test('normalizes case and spaces without guessing aliases', () {
    expect(normalizeRoleMappingProfileTerm('  Cat Girl  '), 'cat_girl');
    expect(normalizeRoleMappingProfileTerm('cat__girl'), 'cat_girl');
    expect(normalizeRoleMappingProfileTerm('1.5:: Cat Girl ::'), 'cat_girl');
    expect(normalizeRoleMappingProfileTerm('{Cat_Girl}'), 'cat_girl');
    expect(
      normalizeRoleMappingProfileTerm('girl'),
      isNot(normalizeRoleMappingProfileTerm('1girl')),
    );
    expect(
      normalizeRoleMappingProfileTerm('girl'),
      isNot(normalizeRoleMappingProfileTerm('female')),
    );
  });

  test('tag-system syntax still auto-matches a cached source term', () {
    final profile = _profile(
      block: const RoleMappingProfileBlock(
        id: 'weighted-girl-block',
        terms: [
          RoleMappingProfileTerm(
            id: 'cached-girl',
            text: 'girl',
            normalizedKey: 'girl',
          ),
        ],
        targetPrompt: 'cat girl',
      ),
    );
    final replacement = _replacement(
      rules: [
        _rule(
          id: 'weighted-current',
          terms: const [('1.5:: girl ::', 'weighted-girl')],
        ),
      ],
    );

    final preview = service.buildPreview(
      profile: profile,
      replacement: replacement,
    );

    expect(preview.entries.single.selectedTermIds, ['weighted-girl']);
    expect(preview.entries.single.selectedByDefault, isTrue);
  });

  test('reconciles stale target terms after a profile is retargeted', () {
    const pepe = CharacterEntry(
      id: 'pepe',
      name: '佩佩',
      traits: ViewVariantTexts(
        frontFull: 'pepe_(arknights), cat ears, Lotus flower headdress, hood, '
            'wearing hood, animal hood',
      ),
    );
    const guobao = CharacterEntry(
      id: 'guobao',
      name: '果宝',
      traits: ViewVariantTexts(
        frontFull: '1girl, guobao, white hair, green bonnet',
      ),
    );
    final profile = RoleMappingProfile(
      id: 'retargeted-profile',
      name: '果宝',
      targetCharacterId: guobao.id,
      targetIdentityPrompt: 'pepe_(arknights), white hair, -3:: hood ::',
      blocks: const [
        RoleMappingProfileBlock(
          id: 'head-block',
          terms: [
            RoleMappingProfileTerm(
              id: 'bonnet',
              text: 'bonnet',
              normalizedKey: 'bonnet',
            ),
          ],
          targetPrompt:
              '1.5:: cat ears ::, -3:: hood ::, -3:: wearing hood ::, '
              '-3:: animal hood ::, white hair, custom target',
          action: ScriptPromptReplacementAction.replace,
        ),
      ],
      createdAt: DateTime.utc(2026, 8, 21),
      updatedAt: DateTime.utc(2026, 8, 21),
    );

    final repaired = service.reconcileTargetCharacter(
      profile: profile,
      targetCharacter: guobao,
      characterCatalog: const [pepe, guobao],
      fallbackIdentityPrompt: 'guobao, white hair, green bonnet',
    );

    expect(
      repaired.targetIdentityPrompt,
      'guobao, white hair, green bonnet',
    );
    expect(
      repaired.blocks.single.targetPrompt,
      'white hair, custom target',
    );
  });

  test('clears old target outputs when applying a different linked character',
      () {
    final profile = RoleMappingProfile(
      id: 'target-switch-profile',
      name: '果宝',
      targetCharacterId: 'guobao',
      targetIdentityPrompt: 'guobao',
      blocks: const [
        RoleMappingProfileBlock(
          id: 'bonnet-block',
          terms: [
            RoleMappingProfileTerm(
              id: 'bonnet',
              text: 'bonnet',
              normalizedKey: 'bonnet',
            ),
          ],
          targetPrompt: 'white hair',
          action: ScriptPromptReplacementAction.replace,
        ),
      ],
      createdAt: DateTime.utc(2026, 8, 21),
      updatedAt: DateTime.utc(2026, 8, 21),
    );
    final replacement = ScriptRolePromptReplacement(
      sourceRoleId: 'role-1',
      displayLabel: '角色 1',
      targetCharacterId: 'pepe',
      targetIdentityPrompt: 'pepe_(arknights)',
      rules: [
        _rule(
          id: 'bonnet-current',
          terms: const [('bonnet', 'current-bonnet')],
          target: 'cat ears',
        ),
        _rule(
          id: 'ribbon-current',
          terms: const [('ribbon', 'current-ribbon')],
          target: 'Lotus flower headdress',
        ),
      ],
    );

    final applied = service.applySelections(
      profile: profile,
      replacement: replacement,
      selections: const [
        RoleMappingProfileApplySelection(
          blockId: 'bonnet-block',
          termIds: ['current-bonnet'],
        ),
      ],
    );

    expect(applied.targetCharacterId, 'guobao');
    expect(applied.targetIdentityPrompt, 'guobao');
    expect(
      applied.rules
          .singleWhere((rule) => rule.id.startsWith('profile-'))
          .targetPrompt,
      'white hair',
    );
    expect(
      applied.rules
          .singleWhere(
            (rule) => rule.sourceTerms.any((term) => term.text == 'ribbon'),
          )
          .targetPrompt,
      isEmpty,
    );
  });

  test('writes a custom identity token only to character rules', () {
    final profile = RoleMappingProfile(
      id: 'fruit-profile',
      name: '果宝',
      targetIdentityPromptToken: '果宝',
      targetIdentityPrompt: 'white_hair, girl',
      blocks: const [
        RoleMappingProfileBlock(
          id: 'character-block',
          terms: [
            RoleMappingProfileTerm(
              id: 'source-mari',
              text: 'mari (blue archive)',
              normalizedKey: 'mari_blue_archive',
            ),
          ],
          action: ScriptPromptReplacementAction.replace,
          targetPrompt: 'white_hair',
        ),
        RoleMappingProfileBlock(
          id: 'hair-block',
          terms: [
            RoleMappingProfileTerm(
              id: 'source-hair',
              text: 'long hair',
              normalizedKey: 'long_hair',
            ),
          ],
          action: ScriptPromptReplacementAction.replace,
          targetPrompt: 'white_hair, very_long_hair',
        ),
      ],
      createdAt: DateTime.utc(2026, 8, 22),
      updatedAt: DateTime.utc(2026, 8, 22),
    );
    final replacement = _replacement(
      rules: [
        _rule(
          id: 'character-rule',
          terms: const [('mari (blue archive)', 'current-mari')],
          target: 'old character target',
        ),
        _categorizedRule(
          id: 'hair-rule',
          text: 'long hair',
          category: PromptTagCategory.upperBody,
          frameIndexes: const [0],
          target: 'old hair target',
        ),
      ],
    );

    final applied = service.applySelections(
      profile: profile,
      replacement: replacement,
      selections: const [
        RoleMappingProfileApplySelection(
          blockId: 'character-block',
          termIds: ['current-mari'],
        ),
        RoleMappingProfileApplySelection(
          blockId: 'hair-block',
          termIds: ['term-hair-rule'],
        ),
      ],
    );

    expect(applied.targetIdentityPrompt, '果宝, white_hair, girl');
    expect(
      applied.rules
          .singleWhere(
            (rule) => rule.sourceTerms.any(
              (term) => term.text == 'mari (blue archive)',
            ),
          )
          .targetPrompt,
      '果宝',
    );
    expect(
      applied.rules
          .singleWhere(
            (rule) => rule.sourceTerms.any((term) => term.text == 'long hair'),
          )
          .targetPrompt,
      'white_hair, very_long_hair',
    );
  });

  test('materializes a delete-only character identity for offline variants',
      () {
    final replacement = _replacement(
      targetIdentityPrompt: 'girl, loli, white_hair, lop_rabbit_ears',
      rules: [
        _categorizedRule(
          id: 'identity-delete-a',
          text: 'arona (blue archive)',
          category: PromptTagCategory.character,
          action: ScriptPromptReplacementAction.delete,
        ),
        _categorizedRule(
          id: 'identity-delete-b',
          text: 'girl',
          category: PromptTagCategory.character,
          action: ScriptPromptReplacementAction.delete,
        ),
        _categorizedRule(
          id: 'clothing-delete',
          text: 'tight clothes',
          category: PromptTagCategory.clothing,
          action: ScriptPromptReplacementAction.delete,
        ),
      ],
    );

    final materialized =
        service.materializeTargetIdentityReplacement(replacement);
    final identity = materialized.rules.singleWhere(
      (rule) => rule.id == 'identity-delete-a',
    );

    expect(identity.effectiveAction, ScriptPromptReplacementAction.replace);
    expect(identity.targetPrompt, replacement.targetIdentityPrompt);
    expect(
      identity.sourceTerms.map((term) => term.text),
      ['arona (blue archive)', 'girl'],
    );
    expect(
      materialized.rules.map((rule) => rule.id),
      ['identity-delete-a', 'clothing-delete'],
    );
    expect(
      materialized.rules
          .singleWhere((rule) => rule.id == 'clothing-delete')
          .effectiveAction,
      ScriptPromptReplacementAction.delete,
    );
  });

  test(
      'materializes unmatched character terms instead of leaving a zero rule mapping',
      () {
    final replacement = _replacement(
      targetIdentityPrompt: 'girl, loli, white_hair, lop_rabbit_ears',
      rules: [
        _categorizedRule(
          id: 'unmatched-character-a',
          text: 'ganyu (genshin impact)',
          category: PromptTagCategory.character,
        ),
        _categorizedRule(
          id: 'unmatched-character-b',
          text: 'girl',
          category: PromptTagCategory.character,
        ),
        _categorizedRule(
          id: 'clothing-delete',
          text: 'tight clothes',
          category: PromptTagCategory.clothing,
          action: ScriptPromptReplacementAction.delete,
        ),
      ],
    );

    final materialized =
        service.materializeTargetIdentityReplacement(replacement);
    final identity = materialized.rules.singleWhere(
      (rule) => rule.id == 'unmatched-character-a',
    );

    expect(identity.effectiveAction, ScriptPromptReplacementAction.replace);
    expect(identity.targetPrompt, replacement.targetIdentityPrompt);
    expect(
      identity.sourceTerms.map((term) => term.text),
      ['ganyu (genshin impact)', 'girl'],
    );
    expect(
      materialized.rules.map((rule) => rule.id),
      ['unmatched-character-a', 'clothing-delete'],
    );
  });

  test('splits character terms out of a mixed delete rule', () {
    final replacement = _replacement(
      targetIdentityPrompt: 'girl, loli, white_hair',
      rules: [
        ScriptPromptReplacementRule(
          id: 'mixed-delete',
          sourceTerms: const [
            ScriptPromptReplacementTerm(
              id: 'mari-term',
              text: 'mari (blue archive)',
              category: PromptTagCategory.character,
            ),
            ScriptPromptReplacementTerm(
              id: 'girl-term',
              text: 'girl',
              category: PromptTagCategory.character,
            ),
            ScriptPromptReplacementTerm(
              id: 'yellow-hat-term',
              text: 'yellow hat',
              category: PromptTagCategory.accessory,
            ),
          ],
          action: ScriptPromptReplacementAction.delete,
        ),
        _categorizedRule(
          id: 'existing-identity',
          text: 'nun',
          category: PromptTagCategory.character,
          action: ScriptPromptReplacementAction.replace,
          target: 'existing identity',
        ),
      ],
    );

    final materialized =
        service.materializeTargetIdentityReplacement(replacement);
    final identity = materialized.rules.first;
    final accessory = materialized.rules.last;

    expect(identity.effectiveAction, ScriptPromptReplacementAction.replace);
    expect(identity.targetPrompt, replacement.targetIdentityPrompt);
    expect(
      identity.sourceTerms.map((term) => term.text),
      ['mari (blue archive)', 'girl', 'nun'],
    );
    expect(accessory.effectiveAction, ScriptPromptReplacementAction.delete);
    expect(
      accessory.sourceTerms.map((term) => term.text),
      ['yellow hat'],
    );
    expect(
      materialized.rules.where((rule) => rule.id == 'existing-identity'),
      isEmpty,
    );
  });

  test('splits character terms out of a mixed replace rule', () {
    final replacement = _replacement(
      targetIdentityPrompt: 'girl, loli, white_hair',
      rules: [
        ScriptPromptReplacementRule(
          id: 'mixed-replace',
          sourceTerms: const [
            ScriptPromptReplacementTerm(
              id: 'mari-term',
              text: 'mari (blue archive)',
              category: PromptTagCategory.character,
            ),
            ScriptPromptReplacementTerm(
              id: 'girl-term',
              text: 'girl',
              category: PromptTagCategory.character,
            ),
            ScriptPromptReplacementTerm(
              id: 'yellow-hat-term',
              text: 'yellow hat',
              category: PromptTagCategory.accessory,
            ),
          ],
          action: ScriptPromptReplacementAction.replace,
          targetPrompt: 'girl, cat_ears',
        ),
        _categorizedRule(
          id: 'existing-identity',
          text: 'nun',
          category: PromptTagCategory.character,
          action: ScriptPromptReplacementAction.replace,
          target: 'existing identity',
        ),
      ],
    );

    final materialized =
        service.materializeTargetIdentityReplacement(replacement);
    final identity = materialized.rules.first;
    final accessory = materialized.rules[1];

    expect(identity.effectiveAction, ScriptPromptReplacementAction.replace);
    expect(identity.targetPrompt, replacement.targetIdentityPrompt);
    expect(
      identity.sourceTerms.map((term) => term.text),
      ['mari (blue archive)', 'girl', 'nun'],
    );
    expect(accessory.id, 'mixed-replace-non-identity');
    expect(
      accessory.sourceTerms.map((term) => term.text),
      ['yellow hat'],
    );
    expect(accessory.targetPrompt, 'girl, cat_ears');
    expect(
      materialized.rules.where((rule) => rule.id == 'existing-identity'),
      isEmpty,
    );
  });

  test('deduplicates target tags while keeping identity output authoritative',
      () {
    final replacement = _replacement(
      rules: [
        _categorizedRule(
          id: 'identity',
          text: 'girl',
          category: PromptTagCategory.character,
          action: ScriptPromptReplacementAction.replace,
          target: 'girl, loli, white_hair',
        ),
        _categorizedRule(
          id: 'hair',
          text: 'blue hair',
          category: PromptTagCategory.upperBody,
          action: ScriptPromptReplacementAction.replace,
          target: 'white_hair, long_hair',
        ),
        _categorizedRule(
          id: 'ears',
          text: 'animal ears',
          category: PromptTagCategory.accessory,
          action: ScriptPromptReplacementAction.replace,
          target: 'long_hair, cat_ears',
        ),
      ],
    );

    final deduplicated = service.deduplicateTargetOutputs(replacement);

    expect(
      deduplicated.rules.singleWhere((rule) => rule.id == 'hair').targetPrompt,
      'long_hair',
    );
    expect(
      deduplicated.rules.singleWhere((rule) => rule.id == 'ears').targetPrompt,
      'cat_ears',
    );
  });

  test('active profile binding survives script cache JSON round-trip', () {
    final restored = ScriptRolePromptReplacement.fromJson(
      const ScriptRolePromptReplacement(
        sourceRoleId: 'role-1',
        displayLabel: '角色 1',
        activeMappingProfileId: 'profile-pepe',
      ).toJson(),
    );

    expect(restored.activeMappingProfileId, 'profile-pepe');
  });

  test('keeps a many-source identity mapping as one profile block', () {
    final profile = service.createProfile(
      id: 'profile-papyrus',
      name: '百合花',
      replacement: _replacement(
        rules: [
          _rule(
            id: 'identity',
            terms: const [
              ('faceless female', 'faceless'),
              ('loli', 'loli'),
              ('shun (small) (blue archive)', 'shun'),
              ('tiger girl', 'tiger'),
            ],
            target: 'papyrus (arknights)',
          ),
        ],
      ),
      now: DateTime.utc(2026, 7, 23),
    );

    expect(profile.blocks, hasLength(1));
    expect(profile.blocks.single.terms, hasLength(4));
    expect(
      profile.blocks.single.terms.every((term) => term.autoDetect),
      isTrue,
    );
    expect(
      profile.blocks.single.targetPrompt,
      'papyrus (arknights)',
    );
  });

  test('trigger key gathers present companion terms across current rules', () {
    final profile = _profile(
      block: RoleMappingProfileBlock(
        id: 'identity-block',
        terms: const [
          RoleMappingProfileTerm(
            id: 'saved-shun',
            text: 'shun (small) (blue archive)',
            normalizedKey: 'shun_(small)_(blue_archive)',
          ),
          RoleMappingProfileTerm(
            id: 'saved-loli',
            text: 'loli',
            normalizedKey: 'loli',
            autoDetect: false,
          ),
          RoleMappingProfileTerm(
            id: 'saved-tiger',
            text: 'tiger girl',
            normalizedKey: 'tiger_girl',
            autoDetect: false,
          ),
        ],
        targetPrompt: 'papyrus (arknights)',
        action: ScriptPromptReplacementAction.replace,
      ),
    );
    final replacement = _replacement(
      rules: [
        _rule(
          id: 'specific',
          terms: const [
            ('shun (small) (blue archive)', 'current-shun'),
          ],
        ),
        _rule(
          id: 'generic',
          terms: const [
            ('loli', 'current-loli'),
            ('red eyes', 'current-eyes'),
          ],
        ),
      ],
    );

    final preview = service.buildPreview(
      profile: profile,
      replacement: replacement,
    );
    final entry = preview.entries.single;

    expect(entry.status, RoleMappingApplyPreviewStatus.matched);
    expect(entry.selectedByDefault, isTrue);
    expect(
      entry.selectedTermIds,
      containsAll(['current-shun', 'current-loli']),
    );
    expect(entry.selectedTermIds, isNot(contains('current-eyes')));
    expect(entry.pendingSplitRuleIds, ['generic']);
    expect(entry.pendingMergeRuleIds, containsAll(['specific', 'generic']));
  });

  test('unchecked generic term cannot trigger a profile block alone', () {
    final profile = _profile(
      block: RoleMappingProfileBlock(
        id: 'identity-block',
        terms: const [
          RoleMappingProfileTerm(
            id: 'saved-shun',
            text: 'shun (small) (blue archive)',
            normalizedKey: 'shun_(small)_(blue_archive)',
          ),
          RoleMappingProfileTerm(
            id: 'saved-loli',
            text: 'loli',
            normalizedKey: 'loli',
            autoDetect: false,
          ),
        ],
        targetPrompt: 'papyrus (arknights)',
        action: ScriptPromptReplacementAction.replace,
      ),
    );

    final preview = service.buildPreview(
      profile: profile,
      replacement: _replacement(
        rules: [
          _rule(
            id: 'generic',
            terms: const [('loli', 'current-loli')],
          ),
        ],
      ),
    );

    expect(
      preview.entries.single.status,
      RoleMappingApplyPreviewStatus.unmatched,
    );
  });

  test('all and anchor modes honor enabled detection keys', () {
    const terms = [
      RoleMappingProfileTerm(
        id: 'girl',
        text: 'girl',
        normalizedKey: 'girl',
      ),
      RoleMappingProfileTerm(
        id: 'loli',
        text: 'loli',
        normalizedKey: 'loli',
        autoDetect: false,
      ),
      RoleMappingProfileTerm(
        id: 'cat',
        text: 'cat girl',
        normalizedKey: 'cat_girl',
      ),
    ];
    final allProfile = _profile(
      block: const RoleMappingProfileBlock(
        id: 'all-block',
        terms: terms,
        matchMode: ScriptPromptReplacementMatchMode.all,
        targetPrompt: 'pepe',
      ),
    );
    final bothPresent = _replacement(
      rules: [
        _rule(
          id: 'current',
          terms: const [
            ('GIRL', 'current-girl'),
            ('cat_girl', 'current-cat'),
          ],
        ),
      ],
    );
    expect(
      service
          .buildPreview(profile: allProfile, replacement: bothPresent)
          .entries
          .single
          .status,
      RoleMappingApplyPreviewStatus.matched,
    );
    expect(
      service
          .buildPreview(
            profile: allProfile,
            replacement: _replacement(
              rules: [
                _rule(
                  id: 'girl-only',
                  terms: const [('girl', 'current-girl')],
                ),
              ],
            ),
          )
          .entries
          .single
          .status,
      RoleMappingApplyPreviewStatus.unmatched,
    );

    final anchorProfile = _profile(
      block: const RoleMappingProfileBlock(
        id: 'anchor-block',
        terms: terms,
        matchMode: ScriptPromptReplacementMatchMode.anchor,
        anchorTermKey: 'cat_girl',
        targetPrompt: 'pepe',
      ),
    );
    expect(
      service
          .buildPreview(profile: anchorProfile, replacement: bothPresent)
          .entries
          .single
          .status,
      RoleMappingApplyPreviewStatus.matched,
    );
    final disabledAnchor = _profile(
      block: RoleMappingProfileBlock(
        id: 'anchor-block',
        terms: [
          for (final term in terms)
            if (term.normalizedKey == 'cat_girl')
              term.copyWith(autoDetect: false)
            else
              term,
        ],
        matchMode: ScriptPromptReplacementMatchMode.anchor,
        anchorTermKey: 'cat_girl',
        targetPrompt: 'pepe',
      ),
    );
    expect(
      service
          .buildPreview(profile: disabledAnchor, replacement: bothPresent)
          .entries
          .single
          .status,
      RoleMappingApplyPreviewStatus.unmatched,
    );
  });

  test('a block without detection keys stays manual-only', () {
    final profile = _profile(
      block: const RoleMappingProfileBlock(
        id: 'manual',
        terms: [
          RoleMappingProfileTerm(
            id: 'girl',
            text: 'girl',
            normalizedKey: 'girl',
            autoDetect: false,
          ),
        ],
        targetPrompt: 'pepe',
      ),
    );
    final replacement = _replacement(
      rules: [
        _rule(
          id: 'current',
          terms: const [('girl', 'current-girl')],
        ),
      ],
    );
    final entry = service
        .buildPreview(profile: profile, replacement: replacement)
        .entries
        .single;
    expect(entry.status, RoleMappingApplyPreviewStatus.unmatched);
    expect(entry.availableTermIds, contains('current-girl'));

    final applied = service.applySelections(
      profile: profile,
      replacement: replacement,
      selections: const [
        RoleMappingProfileApplySelection(
          blockId: 'manual',
          termIds: ['current-girl'],
        ),
      ],
    );
    expect(applied.rules.single.targetPrompt, 'pepe');
  });

  test('merges selected current terms and leaves unselected terms in place',
      () {
    final profile = _profile(
      block: RoleMappingProfileBlock(
        id: 'identity-block',
        terms: const [
          RoleMappingProfileTerm(
            id: 'saved-shun',
            text: 'shun (small) (blue archive)',
            normalizedKey: 'shun_(small)_(blue_archive)',
          ),
          RoleMappingProfileTerm(
            id: 'saved-loli',
            text: 'loli',
            normalizedKey: 'loli',
          ),
        ],
        targetPrompt: 'papyrus (arknights)',
        action: ScriptPromptReplacementAction.replace,
      ),
    );
    final replacement = _replacement(
      rules: [
        _rule(
          id: 'specific',
          terms: const [
            ('shun (small) (blue archive)', 'current-shun'),
          ],
        ),
        _rule(
          id: 'mixed',
          terms: const [
            ('loli', 'current-loli'),
            ('red eyes', 'current-eyes'),
          ],
        ),
      ],
    );
    final applied = service.applySelections(
      profile: profile,
      replacement: replacement,
      selections: const [
        RoleMappingProfileApplySelection(
          blockId: 'identity-block',
          termIds: ['current-shun', 'current-loli'],
        ),
      ],
    );

    final merged = applied.rules.singleWhere(
      (rule) => rule.targetPrompt == 'papyrus (arknights)',
    );
    expect(
      merged.sourceTerms.map((term) => term.text),
      ['shun (small) (blue archive)', 'loli'],
    );
    final remainder = applied.rules.singleWhere(
      (rule) => rule.sourceTerms.any((term) => term.text == 'red eyes'),
    );
    expect(remainder.sourceTerms.map((term) => term.text), ['red eyes']);
    expect(applied.activeMappingProfileId, isNull);
    final linked = service.applySelections(
      profile: profile,
      replacement: replacement,
      linkProfile: true,
      selections: const [
        RoleMappingProfileApplySelection(
          blockId: 'identity-block',
          termIds: ['current-shun', 'current-loli'],
        ),
      ],
    );
    expect(linked.activeMappingProfileId, profile.id);
    final preserved = merged.sourceTerms.singleWhere(
      (term) => term.id == 'current-loli',
    );
    expect(preserved.sourcePhrase, 'phrase-current-loli');
    expect(preserved.sourceLocation, 'location-current-loli');
    expect(preserved.frameIndexes, [0]);
  });

  test('same target with extra source terms is reported as a pending split',
      () {
    final profile = _profile(
      block: const RoleMappingProfileBlock(
        id: 'girl-block',
        terms: [
          RoleMappingProfileTerm(
            id: 'girl',
            text: 'girl',
            normalizedKey: 'girl',
          ),
        ],
        targetPrompt: 'loli, cat girl',
      ),
    );
    final entry = service
        .buildPreview(
          profile: profile,
          replacement: _replacement(
            rules: [
              _rule(
                id: 'mixed',
                terms: const [
                  ('girl', 'current-girl'),
                  ('red eyes', 'current-eyes'),
                ],
                target: 'loli, cat girl',
              ),
            ],
          ),
        )
        .entries
        .single;

    expect(entry.status, RoleMappingApplyPreviewStatus.matched);
    expect(entry.pendingSplitRuleIds, ['mixed']);
  });

  test('anchor apply rejects a selection that omits the cached anchor', () {
    final profile = _profile(
      block: const RoleMappingProfileBlock(
        id: 'anchor-block',
        terms: [
          RoleMappingProfileTerm(
            id: 'girl',
            text: 'girl',
            normalizedKey: 'girl',
          ),
          RoleMappingProfileTerm(
            id: 'cat',
            text: 'cat girl',
            normalizedKey: 'cat_girl',
          ),
        ],
        matchMode: ScriptPromptReplacementMatchMode.anchor,
        anchorTermKey: 'cat_girl',
        targetPrompt: 'pepe',
      ),
    );
    final replacement = _replacement(
      rules: [
        _rule(
          id: 'current',
          terms: const [('girl', 'current-girl')],
        ),
      ],
    );

    expect(
      () => service.applySelections(
        profile: profile,
        replacement: replacement,
        selections: const [
          RoleMappingProfileApplySelection(
            blockId: 'anchor-block',
            termIds: ['current-girl'],
          ),
        ],
      ),
      throwsArgumentError,
    );
  });

  test('existing different target is a deterministic selected overwrite', () {
    final profile = _profile(
      block: const RoleMappingProfileBlock(
        id: 'girl-block',
        terms: [
          RoleMappingProfileTerm(
            id: 'girl',
            text: 'girl',
            normalizedKey: 'girl',
          ),
        ],
        targetPrompt: 'loli, cat girl',
        action: ScriptPromptReplacementAction.replace,
      ),
    );
    final preview = service.buildPreview(
      profile: profile,
      replacement: _replacement(
        rules: [
          _rule(
            id: 'girl-current',
            terms: const [('girl', 'current-girl')],
            target: 'adult woman',
          ),
        ],
      ),
    );

    expect(
      preview.entries.single.status,
      RoleMappingApplyPreviewStatus.conflict,
    );
    expect(preview.entries.single.selectedByDefault, isTrue);
  });

  test('manually included current term is learned as an auto-detect companion',
      () {
    final profile = _profile(
      block: const RoleMappingProfileBlock(
        id: 'girl-block',
        terms: [
          RoleMappingProfileTerm(
            id: 'girl',
            text: 'girl',
            normalizedKey: 'girl',
          ),
        ],
        targetPrompt: 'loli, cat girl',
        action: ScriptPromptReplacementAction.replace,
      ),
    );
    final replacement = _replacement(
      rules: [
        _rule(
          id: 'identity',
          terms: const [
            ('girl', 'current-girl'),
            ('green eyes', 'current-green-eyes'),
          ],
        ),
      ],
    );

    final learned = service.withAppliedCompanionTerms(
      profile: profile,
      sourceReplacement: replacement,
      selections: const [
        RoleMappingProfileApplySelection(
          blockId: 'girl-block',
          termIds: ['current-girl', 'current-green-eyes'],
        ),
      ],
      now: DateTime.utc(2026, 7, 24),
    );

    final added = learned.blocks.single.terms.singleWhere(
      (term) => term.normalizedKey == 'green_eyes',
    );
    expect(added.autoDetect, isTrue);
  });

  test('creates shared, stage, and pending cache layers', () {
    const assembly = RoleAssembly(
      sourceRoleId: 'role-1',
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
    final replacement = _replacement(
      rules: [
        _categorizedRule(
          id: 'identity',
          text: 'girl',
          category: PromptTagCategory.character,
          frameIndexes: const [0, 1],
          target: 'loli',
        ),
        _categorizedRule(
          id: 'casual-rule',
          text: 'hoodie',
          category: PromptTagCategory.upperClothing,
          frameIndexes: const [0],
          target: 'white hoodie',
        ),
        _categorizedRule(
          id: 'evening-rule',
          text: 'black dress',
          category: PromptTagCategory.upperClothing,
          frameIndexes: const [1],
          target: 'white dress',
        ),
        ScriptPromptReplacementRule(
          id: 'mixed',
          sourceTerms: [
            const ScriptPromptReplacementTerm(
              id: 'mixed-hoodie',
              text: 'hoodie',
              category: PromptTagCategory.upperClothing,
              frameIndexes: [0],
            ),
            const ScriptPromptReplacementTerm(
              id: 'mixed-dress',
              text: 'dress',
              category: PromptTagCategory.upperClothing,
              frameIndexes: [1],
            ),
          ],
          targetPrompt: 'coat',
        ),
      ],
    );

    final profile = service.createProfile(
      id: 'layered',
      name: '分层缓存',
      replacement: replacement,
      assembly: assembly,
      now: DateTime.utc(2026, 7, 24),
    );

    expect(
      profile.layers.map((layer) => layer.kind),
      [
        RoleMappingProfileLayerKind.shared,
        RoleMappingProfileLayerKind.stage,
        RoleMappingProfileLayerKind.stage,
        RoleMappingProfileLayerKind.pending,
      ],
    );
    expect(profile.layers[1].displayName, '便服');
    expect(profile.layers[1].recognitionSignature, ['hoodie']);
    expect(profile.layers[1].blocks.single.targetPrompt, 'white hoodie');
    expect(profile.layers.last.blocks.single.targetPrompt, 'coat');
  });

  test('uniquely matches cached stages by normalized source signatures', () {
    final profile = RoleMappingProfile(
      id: 'layered',
      name: '分层缓存',
      layers: const [
        RoleMappingProfileLayer(
          id: 'cached-casual',
          kind: RoleMappingProfileLayerKind.stage,
          displayName: '便服',
          recognitionSignature: ['hoodie'],
        ),
        RoleMappingProfileLayer(
          id: 'cached-evening',
          kind: RoleMappingProfileLayerKind.stage,
          displayName: '礼服',
          recognitionSignature: ['black_dress'],
        ),
      ],
      createdAt: DateTime.utc(2026, 7, 24),
      updatedAt: DateTime.utc(2026, 7, 24),
    );
    const currentAssembly = RoleAssembly(
      sourceRoleId: 'role-1',
      displayLabel: '角色 1',
      stages: [
        RoleAssemblyStage(
          id: 'current-a',
          label: '阶段 A',
          frameIndexes: [10],
        ),
        RoleAssemblyStage(
          id: 'current-b',
          label: '阶段 B',
          frameIndexes: [20],
        ),
      ],
    );
    final replacement = _replacement(
      rules: [
        _categorizedRule(
          id: 'hoodie',
          text: 'Hoodie',
          category: PromptTagCategory.upperClothing,
          frameIndexes: const [10],
        ),
        _categorizedRule(
          id: 'dress',
          text: 'black  dress',
          category: PromptTagCategory.upperClothing,
          frameIndexes: const [20],
        ),
      ],
    );

    final preview = service.buildPreview(
      profile: profile,
      replacement: replacement,
      assembly: currentAssembly,
    );

    expect(
      preview.layerEntries.map((entry) => entry.status),
      [
        RoleMappingProfileLayerMatchStatus.matched,
        RoleMappingProfileLayerMatchStatus.matched,
      ],
    );
    expect(
      preview.layerEntries.map((entry) => entry.matchedCurrentLayerId),
      ['stage:current-a', 'stage:current-b'],
    );
  });

  test('stage matching rejects score ties and competing cached stages', () {
    final replacement = _replacement(
      rules: [
        _categorizedRule(
          id: 'hoodie',
          text: 'hoodie',
          category: PromptTagCategory.upperClothing,
          frameIndexes: const [0],
        ),
        _categorizedRule(
          id: 'dress',
          text: 'dress',
          category: PromptTagCategory.upperClothing,
          frameIndexes: const [1],
        ),
      ],
    );
    const assembly = RoleAssembly(
      sourceRoleId: 'role-1',
      displayLabel: '角色 1',
      stages: [
        RoleAssemblyStage(id: 'a', label: 'A', frameIndexes: [0]),
        RoleAssemblyStage(id: 'b', label: 'B', frameIndexes: [1]),
      ],
    );
    final tied = RoleMappingProfile(
      id: 'tied',
      name: '并列',
      layers: const [
        RoleMappingProfileLayer(
          id: 'cached',
          kind: RoleMappingProfileLayerKind.stage,
          displayName: '缓存阶段',
          recognitionSignature: ['hoodie', 'dress'],
        ),
      ],
      createdAt: DateTime.utc(2026, 7, 24),
      updatedAt: DateTime.utc(2026, 7, 24),
    );
    final competing = tied.copyWith(
      id: 'competing',
      name: '争用',
      layers: const [
        RoleMappingProfileLayer(
          id: 'cached-1',
          kind: RoleMappingProfileLayerKind.stage,
          displayName: '缓存阶段 1',
          recognitionSignature: ['hoodie'],
        ),
        RoleMappingProfileLayer(
          id: 'cached-2',
          kind: RoleMappingProfileLayerKind.stage,
          displayName: '缓存阶段 2',
          recognitionSignature: ['hoodie'],
        ),
      ],
    );

    expect(
      service
          .buildPreview(
            profile: tied,
            replacement: replacement,
            assembly: assembly,
          )
          .layerEntries
          .single
          .status,
      RoleMappingProfileLayerMatchStatus.ambiguous,
    );
    expect(
      service
          .buildPreview(
            profile: competing,
            replacement: replacement,
            assembly: assembly,
          )
          .layerEntries
          .map((entry) => entry.status),
      everyElement(RoleMappingProfileLayerMatchStatus.conflict),
    );
  });

  test('applying a matched cached stage writes a current-stage override', () {
    const block = RoleMappingProfileBlock(
      id: 'hoodie-block',
      terms: [
        RoleMappingProfileTerm(
          id: 'hoodie',
          text: 'hoodie',
          normalizedKey: 'hoodie',
        ),
      ],
      targetPrompt: 'white hoodie',
    );
    final profile = RoleMappingProfile(
      id: 'layered',
      name: '分层缓存',
      layers: const [
        RoleMappingProfileLayer(
          id: 'cached-casual',
          kind: RoleMappingProfileLayerKind.stage,
          displayName: '便服',
          recognitionSignature: ['hoodie'],
          blocks: [block],
        ),
      ],
      createdAt: DateTime.utc(2026, 7, 24),
      updatedAt: DateTime.utc(2026, 7, 24),
    );
    const assembly = RoleAssembly(
      sourceRoleId: 'role-1',
      displayLabel: '角色 1',
      stages: [
        RoleAssemblyStage(
          id: 'current-casual',
          label: '当前便服',
          frameIndexes: [3],
        ),
      ],
    );
    final replacement = _replacement(
      rules: [
        _categorizedRule(
          id: 'current',
          text: 'hoodie',
          category: PromptTagCategory.upperClothing,
          frameIndexes: const [3],
        ),
      ],
    );
    final preview = service.buildPreview(
      profile: profile,
      replacement: replacement,
      assembly: assembly,
    );
    final currentLayers = service.layerService.resolve(
      replacement: replacement,
      assembly: assembly,
    );
    expect(profile.effectiveLayers.single.recognitionSignature, ['hoodie']);
    expect(
      currentLayers.assignmentForRule('current')?.kind,
      ScriptRoleReplacementRuleLayerKind.stage,
    );
    expect(currentLayers.layers[1].ruleIds, ['current']);
    expect(
      preview.layerEntries.single.status,
      RoleMappingProfileLayerMatchStatus.matched,
    );
    expect(
      preview.layerEntries.single.matchedCurrentLayerId,
      'stage:current-casual',
    );

    final applied = service.applySelections(
      profile: profile,
      replacement: replacement,
      assembly: assembly,
      selections: const [
        RoleMappingProfileApplySelection(
          blockId: 'hoodie-block',
          termIds: ['term-current'],
        ),
      ],
    );

    expect(applied.rules.single.targetPrompt, 'white hoodie');
    expect(applied.layerOverrides.single.kind,
        ScriptRoleReplacementRuleLayerKind.stage);
    expect(applied.layerOverrides.single.stageId, 'current-casual');
  });

  test('moving a rule layer keeps cache memory until deletion is confirmed',
      () {
    const assembly = RoleAssembly(
      sourceRoleId: 'role-1',
      displayLabel: '角色 1',
      stages: [
        RoleAssemblyStage(id: 'casual', label: '便服', frameIndexes: [0]),
        RoleAssemblyStage(id: 'evening', label: '礼服', frameIndexes: [1]),
      ],
    );
    final before = _replacement(
      rules: [
        _categorizedRule(
          id: 'hoodie',
          text: 'hoodie',
          category: PromptTagCategory.upperClothing,
          frameIndexes: const [0],
          target: 'white hoodie',
        ),
      ],
    );
    final profile = service.createProfile(
      id: 'layered',
      name: '分层缓存',
      replacement: before,
      assembly: assembly,
      now: DateTime.utc(2026, 7, 24),
    );
    final after = before.copyWith(
      layerOverrides: const [
        ScriptRoleReplacementRuleLayerOverride(
          ruleId: 'hoodie',
          kind: ScriptRoleReplacementRuleLayerKind.stage,
          stageId: 'evening',
        ),
      ],
    );

    final prompts = service.deletionPrompts(
      profile: profile,
      before: before,
      after: after,
      beforeAssembly: assembly,
      afterAssembly: assembly,
    );
    final learned = service.learnReplacement(
      profile: profile,
      before: before,
      after: after,
      assembly: assembly,
      now: DateTime.utc(2026, 7, 24, 1),
    );

    expect(prompts, hasLength(1));
    expect(prompts.single.kind, RoleMappingProfileDeletionKind.layerMove);
    expect(
      learned.effectiveLayers
          .singleWhere((layer) => layer.id == 'stage:evening')
          .blocks,
      hasLength(1),
    );

    final deleted = service.resolveDeletion(
      profile: learned,
      prompt: prompts.single,
      now: DateTime.utc(2026, 7, 24, 2),
    );
    expect(deleted.blocks, isEmpty);
  });

  test('routes a source term to the matching upper or lower body side', () {
    final profile = RoleMappingProfile(
      id: 'side-aware-profile',
      name: '上下身约束',
      targetCharacterId: 'character-pepe',
      targetIdentityPrompt: 'pepe (arknights)',
      blocks: const [
        RoleMappingProfileBlock(
          id: 'upper-block',
          terms: [
            RoleMappingProfileTerm(
              id: 'upper-tail',
              text: 'rabbit tail',
              normalizedKey: 'rabbit_tail',
            ),
          ],
          targetPrompt: 'white hair',
          targetCategories: [PromptTagCategory.upperBody],
        ),
        RoleMappingProfileBlock(
          id: 'lower-block',
          terms: [
            RoleMappingProfileTerm(
              id: 'lower-tail',
              text: 'rabbit tail',
              normalizedKey: 'rabbit_tail',
            ),
          ],
          targetPrompt: 'cat tail',
          targetCategories: [PromptTagCategory.lowerBody],
        ),
      ],
      createdAt: DateTime.utc(2026, 8, 22),
      updatedAt: DateTime.utc(2026, 8, 22),
    );
    final preview = service.buildPreview(
      profile: profile,
      replacement: _replacement(
        rules: [
          _categorizedRule(
            id: 'rabbit-tail-current',
            text: 'rabbit tail',
            category: PromptTagCategory.lowerBody,
          ),
        ],
      ),
    );

    final upper = preview.entries.singleWhere(
      (entry) => entry.block.id == 'upper-block',
    );
    final lower = preview.entries.singleWhere(
      (entry) => entry.block.id == 'lower-block',
    );
    expect(upper.selectedTermIds, isEmpty);
    expect(lower.selectedTermIds, ['term-rabbit-tail-current']);
  });

  test('does not force mixed clothing into a one-sided target block', () {
    final profile = RoleMappingProfile(
      id: 'mixed-clothing-profile',
      name: '混合服装约束',
      targetCharacterId: 'character-pepe',
      targetIdentityPrompt: 'pepe (arknights)',
      blocks: const [
        RoleMappingProfileBlock(
          id: 'upper-only-block',
          terms: [
            RoleMappingProfileTerm(
              id: 'mixed-clothing',
              text: 'bra and panties',
              normalizedKey: 'bra_and_panties',
            ),
          ],
          targetPrompt: 'black jacket',
          targetCategories: [PromptTagCategory.upperClothing],
        ),
      ],
      createdAt: DateTime.utc(2026, 8, 22),
      updatedAt: DateTime.utc(2026, 8, 22),
    );
    final preview = service.buildPreview(
      profile: profile,
      replacement: _replacement(
        rules: [
          _categorizedRule(
            id: 'mixed-current',
            text: 'bra and panties',
            category: PromptTagCategory.clothing,
          ),
        ],
      ),
    );

    expect(preview.entries.single.selectedTermIds, isEmpty);
    expect(
      preview.entries.single.status,
      RoleMappingApplyPreviewStatus.unmatched,
    );
  });

  test('does not apply a target identity when no source term was selected', () {
    final profile = _profile(
      block: const RoleMappingProfileBlock(
        id: 'girl-block',
        terms: [
          RoleMappingProfileTerm(
            id: 'girl',
            text: 'girl',
            normalizedKey: 'girl',
          ),
        ],
        targetPrompt: 'white hair',
      ),
    );
    final replacement = _replacement(
      targetIdentityPrompt: 'old target',
      rules: [
        _categorizedRule(
          id: 'unrelated',
          text: 'boy',
          category: PromptTagCategory.character,
        ),
      ],
    );

    final applied = service.applySelections(
      profile: profile,
      replacement: replacement,
      linkProfile: true,
      selections: const [],
    );

    expect(applied.targetCharacterId, replacement.targetCharacterId);
    expect(applied.targetIdentityPrompt, 'old target');
    expect(applied.activeMappingProfileId, isNull);
  });
}

RoleMappingProfile _profile({required RoleMappingProfileBlock block}) {
  return RoleMappingProfile(
    id: 'profile',
    name: '佩佩',
    targetCharacterId: 'character-pepe',
    targetCharacterNameSnapshot: '佩佩',
    targetIdentityPrompt: 'pepe (arknights)',
    blocks: [block],
    createdAt: DateTime.utc(2026, 7, 23),
    updatedAt: DateTime.utc(2026, 7, 23),
  );
}

ScriptRolePromptReplacement _replacement({
  String targetIdentityPrompt = '',
  List<ScriptPromptReplacementRule> rules = const [],
}) {
  return ScriptRolePromptReplacement(
    sourceRoleId: 'role-1',
    displayLabel: '角色 1',
    targetIdentityPrompt: targetIdentityPrompt,
    rules: rules,
  );
}

ScriptPromptReplacementRule _rule({
  required String id,
  required List<(String, String)> terms,
  String target = '',
}) {
  return ScriptPromptReplacementRule(
    id: id,
    sourceTerms: [
      for (final (text, termId) in terms)
        ScriptPromptReplacementTerm(
          id: termId,
          text: text,
          category: PromptTagCategory.character,
          sourcePhrase: 'phrase-$termId',
          sourceLocation: 'location-$termId',
          frameIndexes: const [0],
        ),
    ],
    targetPrompt: target,
    action: target.isEmpty
        ? ScriptPromptReplacementAction.none
        : ScriptPromptReplacementAction.replace,
  );
}

ScriptPromptReplacementRule _categorizedRule({
  required String id,
  required String text,
  required PromptTagCategory category,
  List<int> frameIndexes = const [],
  String target = '',
  ScriptPromptReplacementAction? action,
}) {
  return ScriptPromptReplacementRule(
    id: id,
    sourceTerms: [
      ScriptPromptReplacementTerm(
        id: 'term-$id',
        text: text,
        category: category,
        frameIndexes: frameIndexes,
      ),
    ],
    action: action ??
        (target.isEmpty
            ? ScriptPromptReplacementAction.none
            : ScriptPromptReplacementAction.replace),
    targetPrompt: target,
  );
}
