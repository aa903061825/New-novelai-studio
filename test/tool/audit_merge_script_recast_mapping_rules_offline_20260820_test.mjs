import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

import {
  analyzeCacheForSafeMerges,
  resolveRoleReplacementLayers,
  runOfflineAuditMerge,
} from '../../tool/audit_merge_script_recast_mapping_rules_offline_20260820.mjs';

test('audits structural zero-count layers and finds only same-layer safe merges', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'recast-safe-merge-audit-'));
  try {
    const cacheDir = path.join(root, 'workspace', 'script_recast', 'cache');
    const sourceRoot = path.join(root, 'source');
    fs.mkdirSync(cacheDir, { recursive: true });
    fs.mkdirSync(sourceRoot, { recursive: true });
    const filePath = path.join(cacheDir, 'script-fixture.json');
    const cache = fixtureCache(path.join(sourceRoot, 'story'));
    fs.writeFileSync(filePath, `${JSON.stringify(cache, null, 2)}\n`, 'utf8');
    const before = fs.readFileSync(filePath, 'utf8');

    const report = runOfflineAuditMerge({
      cacheDir,
      sourceRoot,
      apply: false,
      cacheFiles: [],
      now: new Date('2026-08-20T10:00:00.000Z'),
    });

    assert.equal(report.api_used, false);
    assert.equal(report.summary.cache_files_matched, 1);
    assert.equal(report.summary.safe_cache_merge_group_count, 1);
    assert.equal(report.summary.cache_rules_removed_if_applied, 1);
    assert.equal(report.summary.empty_stage_layer_count, 1);
    assert.equal(report.summary.suspicious_empty_stage_count, 0);
    assert.equal(report.summary.no_effect_rule_count, 1);
    assert.equal(report.summary.suspicious_no_effect_rule_count, 0);
    assert.deepEqual(
      report.safe_cache_merge_groups[0].sourceTerms.map((term) => term.text),
      ['white rabbit ears', 'pink hair ribbon'],
    );
    assert.equal(report.safe_cache_merge_groups[0].layerId, 'stage:stage-2');
    assert.equal(fs.readFileSync(filePath, 'utf8'), before);
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

test('apply backs up cache and profile, preserves evidence, and is idempotent', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'recast-safe-merge-apply-'));
  try {
    const workspace = path.join(root, 'workspace');
    const cacheDir = path.join(workspace, 'script_recast', 'cache');
    const sourceRoot = path.join(root, 'source');
    const profileFile = path.join(workspace, 'global', 'role_mapping_profiles.json');
    const backupDir = path.join(root, 'build', 'backup');
    fs.mkdirSync(cacheDir, { recursive: true });
    fs.mkdirSync(path.dirname(profileFile), { recursive: true });
    fs.mkdirSync(sourceRoot, { recursive: true });
    const cacheFile = path.join(cacheDir, 'script-fixture.json');
    const cache = fixtureCache(path.join(sourceRoot, 'story'));
    const profile = fixtureProfileLibrary();
    fs.writeFileSync(cacheFile, `${JSON.stringify(cache, null, 2)}\n`, 'utf8');
    fs.writeFileSync(profileFile, `${JSON.stringify(profile, null, 2)}\n`, 'utf8');

    const report = runOfflineAuditMerge({
      workspace,
      cacheDir,
      sourceRoot,
      profileFile,
      apply: true,
      backupDir,
      cacheFiles: [],
      now: new Date('2026-08-20T10:05:00.000Z'),
    });

    assert.equal(report.summary.files_written, 2);
    assert.equal(report.summary.safe_cache_merge_group_count, 1);
    assert.equal(report.summary.safe_profile_merge_group_count, 1);
    assert.equal(report.summary.profile_blocks_removed_if_applied, 1);
    assert.ok(fs.existsSync(path.join(backupDir, 'script-fixture.json')));
    assert.ok(fs.existsSync(path.join(backupDir, 'role_mapping_profiles.json')));
    assert.ok(fs.existsSync(path.join(backupDir, 'manifest.json')));
    assert.deepEqual(
      JSON.parse(fs.readFileSync(path.join(backupDir, 'script-fixture.json'), 'utf8')),
      cache,
    );

    const updated = JSON.parse(fs.readFileSync(cacheFile, 'utf8'));
    const replacement = updated.mapping.rolePromptReplacements[0];
    assert.equal(replacement.rules.length, 3);
    const merged = replacement.rules.find((rule) => rule.id === 'rule-rabbit-ears');
    assert.deepEqual(
      merged.sourceTerms.map((term) => term.text),
      ['white rabbit ears', 'pink hair ribbon'],
    );
    assert.deepEqual(updated.scriptSnapshot, cache.scriptSnapshot);
    assert.deepEqual(updated.aiRoleExtraction, cache.aiRoleExtraction);
    assert.equal(updated.sourceFingerprint, cache.sourceFingerprint);
    assert.equal(updated.updatedAt, '2026-08-20T10:05:00.000Z');
    const assembly = updated.mapping.roleAssemblies[0];
    const layers = resolveRoleReplacementLayers(replacement, assembly);
    assert.equal(
      layers.assignmentsByRuleId.get('rule-rabbit-ears').layerId,
      'stage:stage-2',
    );

    const updatedProfile = JSON.parse(fs.readFileSync(profileFile, 'utf8'));
    const blocks = updatedProfile.profiles[0].layers[0].blocks;
    assert.equal(blocks.length, 2);
    assert.deepEqual(
      blocks[1].terms.map((term) => term.text),
      ['white rabbit ears', 'pink hair ribbon'],
    );

    const secondPass = runOfflineAuditMerge({
      workspace,
      cacheDir,
      sourceRoot,
      profileFile,
      apply: false,
      cacheFiles: [],
      now: new Date('2026-08-20T10:06:00.000Z'),
    });
    assert.equal(secondPass.summary.safe_cache_merge_group_count, 0);
    assert.equal(secondPass.summary.safe_profile_merge_group_count, 0);
    assert.equal(secondPass.summary.files_written, 0);
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

test('does not merge identical outputs across different resolved stages', () => {
  const cache = fixtureCache('C:/source/story');
  const replacement = cache.mapping.rolePromptReplacements[0];
  replacement.rules.find((rule) => rule.id === 'rule-rabbit-ears')
    .sourceTerms[0].frameIndexes = [1];
  replacement.rules.find((rule) => rule.id === 'rule-rabbit-ears')
    .sourceTerms[0].sourceOccurrences = [
      { frameIndex: 1, sourceLocation: 'slot-0 prompt' },
    ];
  const analysis = analyzeCacheForSafeMerges(cache, 'fixture.json');
  assert.equal(analysis.safeGroups.length, 0);
  assert.ok(
    analysis.rejectedNearGroups.some((group) =>
      group.reasons.includes('different-resolved-layers'),
    ),
  );
});

test('apply requires a backup directory before any write', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'recast-safe-merge-backup-'));
  try {
    const cacheDir = path.join(root, 'workspace', 'script_recast', 'cache');
    const sourceRoot = path.join(root, 'source');
    fs.mkdirSync(cacheDir, { recursive: true });
    fs.mkdirSync(sourceRoot, { recursive: true });
    fs.writeFileSync(
      path.join(cacheDir, 'script-fixture.json'),
      JSON.stringify(fixtureCache(path.join(sourceRoot, 'story'))),
      'utf8',
    );
    assert.throws(
      () =>
        runOfflineAuditMerge({
          cacheDir,
          sourceRoot,
          apply: true,
          cacheFiles: [],
        }),
      /--backup-dir is required/,
    );
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

function fixtureCache(sourceRootPath) {
  const headTarget =
    '1.5:: cat_ears ::, -3:: hood ::, -3:: wearing hood ::, '
    + '-3:: animal hood ::, 2:: lotus_flower_headdress ::';
  return {
    scriptId: 'script-fixture',
    scriptName: 'Fixture script',
    sourceRootPath,
    sourceFingerprint: 'fixture-fingerprint',
    sourceContentFingerprint: 'fixture-content-fingerprint',
    updatedAt: '2026-08-20T09:00:00.000Z',
    mapping: {
      id: 'mapping-script-fixture',
      scriptId: 'script-fixture',
      roleSwaps: [],
      roleAssemblies: [
        {
          sourceRoleId: 'role-heroine',
          displayLabel: 'Heroine / 女主角',
          sourceName: 'Heroine',
          sourceAppearances: [
            {
              sourceId: 'slot-0',
              sourceKind: 'slot',
              frameIndexes: [1, 2],
            },
          ],
          stages: [
            {
              id: 'stage-1',
              label: '常服',
              frameIndexes: [1],
              sourceSummary: 'heroine',
              sourceParts: { identity: 'heroine' },
            },
            {
              id: 'stage-2',
              label: '兔耳装饰',
              frameIndexes: [2],
              sourceSummary:
                'heroine, white rabbit ears, pink hair ribbon, black choker',
              sourceParts: {
                identity: 'heroine',
                upperBody: 'white rabbit ears, pink hair ribbon, black choker',
              },
            },
          ],
        },
      ],
      rolePromptReplacements: [
        {
          sourceRoleId: 'role-heroine',
          displayLabel: 'Heroine / 女主角',
          targetCharacterId: 'legacy-character-sheet-r14',
          targetIdentityPrompt: 'pepe_(arknights), girl, loli, cat_girl',
          rules: [
            replacementRule({
              id: 'rule-identity',
              text: 'heroine',
              category: 'character',
              frameIndexes: [1, 2],
              targetPrompt: 'pepe_(arknights), girl, loli, cat_girl',
            }),
            replacementRule({
              id: 'rule-rabbit-ears',
              text: 'white rabbit ears',
              category: 'accessory',
              frameIndexes: [2],
              targetPrompt: headTarget,
            }),
            replacementRule({
              id: 'rule-hair-ribbon',
              text: 'pink hair ribbon',
              category: 'accessory',
              frameIndexes: [2],
              targetPrompt: headTarget,
            }),
            replacementRule({
              id: 'rule-choker',
              text: 'black choker',
              category: 'accessory',
              frameIndexes: [2],
              targetPrompt: '',
            }),
          ],
        },
      ],
      scenePromptReplacements: [],
    },
    aiRoleExtraction: {
      schema_version: 1,
      status: 'ready',
      roles: [
        {
          source_role_id: 'role-heroine',
          display_name: 'Heroine / 女主角',
          prompt_terms: [],
        },
      ],
      scene_terms: [],
    },
    scriptSnapshot: {
      id: 'script-fixture',
      name: 'Fixture script',
      rootPath: sourceRootPath,
      frames: [
        {
          index: 1,
          parsed: {
            baseCaption: 'masterpiece',
            charCaptions: ['heroine, standing'],
          },
        },
        {
          index: 2,
          parsed: {
            baseCaption: 'masterpiece',
            charCaptions: [
              'heroine, white rabbit ears, pink hair ribbon, black choker',
            ],
          },
        },
      ],
    },
  };
}

function replacementRule({
  id,
  text,
  category,
  frameIndexes,
  targetPrompt,
}) {
  return {
    id,
    sourceTerms: [
      {
        id: `term-${id}`,
        text,
        category,
        sourcePhrase: text,
        sourceLocation: 'slot-0 prompt',
        frameIndexes,
        sourceOccurrences: frameIndexes.map((frameIndex) => ({
          frameIndex,
          sourceLocation: 'slot-0 prompt',
        })),
      },
    ],
    ...(targetPrompt
      ? { action: 'replace', targetPrompt }
      : {}),
  };
}

function fixtureProfileLibrary() {
  const headTarget =
    '1.5:: cat_ears ::, -3:: hood ::, -3:: wearing hood ::, '
    + '-3:: animal hood ::, 2:: lotus_flower_headdress ::';
  return {
    schemaVersion: 2,
    profiles: [
      {
        id: 'profile-pepe',
        name: '佩佩（无兜帽）',
        targetCharacterId: 'legacy-character-sheet-r14',
        targetCharacterNameSnapshot: '佩佩（无兜帽）',
        targetIdentityPrompt: 'pepe_(arknights), girl, loli, cat_girl',
        layers: [
          {
            id: 'shared-pepe',
            kind: 'shared',
            displayName: '全局精确映射',
            recognitionSignature: [
              'heroine',
              'white_rabbit_ears',
              'pink_hair_ribbon',
            ],
            blocks: [
              profileBlock(
                'block-identity',
                'heroine',
                'pepe_(arknights), girl, loli, cat_girl',
              ),
              profileBlock(
                'block-rabbit-ears',
                'white rabbit ears',
                headTarget,
              ),
              profileBlock(
                'block-hair-ribbon',
                'pink hair ribbon',
                headTarget,
              ),
            ],
          },
        ],
        createdAt: '2026-08-20T09:00:00.000Z',
        updatedAt: '2026-08-20T09:00:00.000Z',
      },
    ],
  };
}

function profileBlock(id, text, targetPrompt) {
  return {
    id,
    terms: [
      {
        id: `term-${id}`,
        text,
        normalizedKey: text.toLowerCase().replaceAll(' ', '_'),
        autoDetect: true,
      },
    ],
    matchMode: 'any',
    action: 'replace',
    targetPrompt,
  };
}
