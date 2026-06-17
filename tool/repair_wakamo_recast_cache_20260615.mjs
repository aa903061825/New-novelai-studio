import fs from 'node:fs';
import path from 'node:path';

const TARGET_FILE = 'script-e175b3e44c1a0198.json';
const WAKAMO_ROLE_ID = 'role-wakamo-blue-archive';
const WAKAMO_DISPLAY =
  'wakamo_(blue_archive) / \u72d0\u5742\u82e5\u85fb\uff08\u78a7\u84dd\u6863\u6848\uff09';
const UNKNOWN_CLOTHING_LABEL = '\u670d\u88c5\u4e0d\u660e';

const GENERIC_IDENTITY_TERMS = new Set([
  '1girl',
  '1boy',
  '2girls',
  '2boys',
  '3girls',
  '3boys',
  'multiple girls',
  'multiple boys',
  'girl',
  'boy',
  'solo',
]);

const ROLE_STATE_TERMS = new Set([
  'bikini aside',
  'bottomless',
  'bottomless female',
  'completely nude',
  'male topless',
  'naked',
  'no clothes',
  'no panties',
  'nude',
  'panty pull',
  'topless',
]);

const NON_SCENE_TERMS = new Set(['year 2024', 'year 2025']);

const options = parseArgs(process.argv.slice(2));
const cacheDir =
  options.cacheDir ??
  path.join(
    process.env.APPDATA ?? '',
    'Novel Studio',
    'Novel Studio',
    'novel_studio',
    'script_recast',
    'cache',
  );
const reportPath =
  options.report ?? path.join('build', 'wakamo_recast_case_repair_20260615.json');

const files = resolveInputFiles({ file: options.file, cacheDir, nameContains: options.nameContains });

const summary = {
  apply: options.apply,
  cache_dir: options.file ? null : path.resolve(cacheDir),
  files_scanned: files.length,
  files_changed: 0,
  changes_total: 0,
  files: [],
};

for (const filePath of files) {
  const cache = JSON.parse(fs.readFileSync(filePath, 'utf8'));
  const original = JSON.stringify(cache);
  const fileReport = {
    file_name: path.basename(filePath),
    script_name: stringValue(cache.scriptName),
    changes: [],
  };

  repairWakamoDisplay(cache, fileReport);
  removeGenericIdentityTerms(cache, fileReport);
  removeRoleStateTermsFromStageFields(cache, fileReport);
  repairUnknownClothingStageLabels(cache, fileReport);
  removeNonSceneTerms(cache, fileReport);

  fileReport.postcheck = auditCache(cache);

  if (JSON.stringify(cache) !== original) {
    summary.files_changed += 1;
    summary.changes_total += fileReport.changes.length;
    if (options.apply) {
      fs.writeFileSync(filePath, `${JSON.stringify(cache, null, 2)}\n`, 'utf8');
    }
  }
  summary.files.push(fileReport);
}

fs.mkdirSync(path.dirname(path.resolve(reportPath)), { recursive: true });
fs.writeFileSync(reportPath, `${JSON.stringify(summary, null, 2)}\n`, 'utf8');
console.log(JSON.stringify(summary, null, 2));

function repairWakamoDisplay(cache, fileReport) {
  const role = findRole(cache, WAKAMO_ROLE_ID);
  if (role) {
    setValue(role, 'display_name', WAKAMO_DISPLAY, fileReport, {
      section: 'aiRoleExtraction.roles',
      role_id: WAKAMO_ROLE_ID,
      field: 'display_name',
    });
    setValue(role, 'canonical_name', 'wakamo', fileReport, {
      section: 'aiRoleExtraction.roles',
      role_id: WAKAMO_ROLE_ID,
      field: 'canonical_name',
    });
    setValue(role, 'franchise', 'blue archive', fileReport, {
      section: 'aiRoleExtraction.roles',
      role_id: WAKAMO_ROLE_ID,
      field: 'franchise',
    });
  }

  const assembly = findAssembly(cache, WAKAMO_ROLE_ID);
  if (assembly) {
    setValue(assembly, 'displayLabel', WAKAMO_DISPLAY, fileReport, {
      section: 'mapping.roleAssemblies',
      role_id: WAKAMO_ROLE_ID,
      field: 'displayLabel',
    });
    setValue(assembly, 'sourceName', WAKAMO_DISPLAY, fileReport, {
      section: 'mapping.roleAssemblies',
      role_id: WAKAMO_ROLE_ID,
      field: 'sourceName',
    });
  }

  const promptGroup = findRolePromptGroup(cache, WAKAMO_ROLE_ID);
  if (promptGroup) {
    setValue(promptGroup, 'displayLabel', WAKAMO_DISPLAY, fileReport, {
      section: 'mapping.rolePromptReplacements',
      role_id: WAKAMO_ROLE_ID,
      field: 'displayLabel',
    });
  }
}

function removeGenericIdentityTerms(cache, fileReport) {
  for (const role of cache.aiRoleExtraction?.roles ?? []) {
    const roleId = stringValue(role.source_role_id);
    const beforeRaw = Array.isArray(role.raw_identity_tags) ? [...role.raw_identity_tags] : null;
    if (beforeRaw) {
      role.raw_identity_tags = role.raw_identity_tags.filter(
        (term) => !GENERIC_IDENTITY_TERMS.has(normalize(term)),
      );
      recordArrayChange(beforeRaw, role.raw_identity_tags, fileReport, {
        section: 'aiRoleExtraction.roles',
        role_id: roleId,
        field: 'raw_identity_tags',
        reason: 'removed_generic_identity_terms',
      });
    }

    const beforeEvidence = Array.isArray(role.evidence_terms) ? [...role.evidence_terms] : null;
    if (beforeEvidence) {
      role.evidence_terms = role.evidence_terms.filter(
        (term) => !GENERIC_IDENTITY_TERMS.has(normalize(term)),
      );
      recordArrayChange(beforeEvidence, role.evidence_terms, fileReport, {
        section: 'aiRoleExtraction.roles',
        role_id: roleId,
        field: 'evidence_terms',
        reason: 'removed_generic_identity_terms',
      });
    }

    const beforePromptTerms = Array.isArray(role.prompt_terms) ? role.prompt_terms.length : null;
    if (beforePromptTerms !== null) {
      role.prompt_terms = role.prompt_terms.filter(
        (term) =>
          !(
            stringValue(term.category) === 'identity' &&
            GENERIC_IDENTITY_TERMS.has(normalize(term.text))
          ),
      );
      if (role.prompt_terms.length !== beforePromptTerms) {
        addChange(fileReport, {
          section: 'aiRoleExtraction.roles.prompt_terms',
          role_id: roleId,
          field: 'prompt_terms',
          before: beforePromptTerms,
          after: role.prompt_terms.length,
          reason: 'removed_generic_identity_terms',
        });
      }
    }

    for (const stage of role.stages ?? []) {
      cleanIdentityField(stage, 'identity', {
        fileReport,
        section: 'aiRoleExtraction.roles.stages',
        roleId,
        stageId: stringValue(stage.stage_id),
      });
      const beforeStageEvidence = Array.isArray(stage.evidence_terms)
        ? [...stage.evidence_terms]
        : null;
      if (beforeStageEvidence) {
        stage.evidence_terms = stage.evidence_terms.filter(
          (term) => !GENERIC_IDENTITY_TERMS.has(normalize(term)),
        );
        recordArrayChange(beforeStageEvidence, stage.evidence_terms, fileReport, {
          section: 'aiRoleExtraction.roles.stages',
          role_id: roleId,
          stage_id: stringValue(stage.stage_id),
          field: 'evidence_terms',
          reason: 'removed_generic_identity_terms',
        });
      }
      refreshMissingField(stage, 'identity', 'missing_identity');
    }
  }

  for (const assembly of cache.mapping?.roleAssemblies ?? []) {
    for (const stage of assembly.stages ?? []) {
      if (!stage.sourceParts) continue;
      cleanIdentityField(stage.sourceParts, 'identity', {
        fileReport,
        section: 'mapping.roleAssemblies.stages',
        roleId: stringValue(assembly.sourceRoleId),
        stageId: stringValue(stage.id),
      });
      refreshMappingStageSummary(stage);
    }
  }

  for (const group of cache.mapping?.rolePromptReplacements ?? []) {
    const before = Array.isArray(group.rules) ? group.rules.length : null;
    if (before === null) continue;
    for (const rule of group.rules) {
      if (!Array.isArray(rule.sourceTerms)) continue;
      rule.sourceTerms = rule.sourceTerms.filter(
        (term) =>
          !(
            stringValue(term.category) === 'identity' &&
            GENERIC_IDENTITY_TERMS.has(normalize(term.text))
          ),
      );
    }
    group.rules = group.rules.filter((rule) => (rule.sourceTerms ?? []).length > 0);
    if (group.rules.length !== before) {
      addChange(fileReport, {
        section: 'mapping.rolePromptReplacements',
        role_id: stringValue(group.sourceRoleId),
        field: 'rules',
        before,
        after: group.rules.length,
        reason: 'removed_generic_identity_terms',
      });
    }
  }
}

function removeRoleStateTermsFromStageFields(cache, fileReport) {
  for (const role of cache.aiRoleExtraction?.roles ?? []) {
    const beforeRoleEvidence = Array.isArray(role.evidence_terms) ? [...role.evidence_terms] : null;
    if (beforeRoleEvidence) {
      role.evidence_terms = role.evidence_terms.filter(
        (term) => !ROLE_STATE_TERMS.has(normalize(term)),
      );
      recordArrayChange(beforeRoleEvidence, role.evidence_terms, fileReport, {
        section: 'aiRoleExtraction.roles',
        role_id: stringValue(role.source_role_id),
        field: 'evidence_terms',
        reason: 'removed_role_state_term_from_role_evidence',
      });
    }

    for (const stage of role.stages ?? []) {
      for (const field of ['identity', 'upper_body', 'lower_body', 'upper_clothing', 'lower_clothing']) {
        const before = stringValue(stage[field]);
        const after = removeTerms(before, ROLE_STATE_TERMS);
        if (after === before) continue;
        stage[field] = after;
        if (field === 'lower_clothing' && !after) {
          refreshMissingField(stage, field, 'missing_lower_clothing');
          stage.field_reasons ??= {};
          stage.field_reasons.lower_clothing =
            'State-only terms are tracked as clothingState prompt terms; no stable lower-clothing evidence remains.';
        }
        addChange(fileReport, {
          section: 'aiRoleExtraction.roles.stages',
          role_id: stringValue(role.source_role_id),
          stage_id: stringValue(stage.stage_id),
          field,
          before,
          after,
          reason: 'removed_role_state_term_from_stage_field',
        });
      }
      const beforeEvidence = Array.isArray(stage.evidence_terms) ? [...stage.evidence_terms] : null;
      if (beforeEvidence) {
        stage.evidence_terms = stage.evidence_terms.filter(
          (term) => !ROLE_STATE_TERMS.has(normalize(term)),
        );
        recordArrayChange(beforeEvidence, stage.evidence_terms, fileReport, {
          section: 'aiRoleExtraction.roles.stages',
          role_id: stringValue(role.source_role_id),
          stage_id: stringValue(stage.stage_id),
          field: 'evidence_terms',
          reason: 'removed_role_state_term_from_stage_evidence',
        });
      }
    }
  }

  for (const assembly of cache.mapping?.roleAssemblies ?? []) {
    for (const stage of assembly.stages ?? []) {
      const parts = stage.sourceParts;
      if (!parts) continue;
      for (const field of [
        'identity',
        'upperBody',
        'lowerBody',
        'upperClothing',
        'lowerClothing',
      ]) {
        const before = stringValue(parts[field]);
        const after = removeTerms(before, ROLE_STATE_TERMS);
        if (after === before) continue;
        if (after) {
          parts[field] = after;
        } else {
          delete parts[field];
          addOmittedPart(stage, field);
        }
        refreshMappingStageSummary(stage);
        addChange(fileReport, {
          section: 'mapping.roleAssemblies.stages',
          role_id: stringValue(assembly.sourceRoleId),
          stage_id: stringValue(stage.id),
          field,
          before,
          after,
          reason: 'removed_role_state_term_from_stage_field',
        });
      }
    }
  }
}

function repairUnknownClothingStageLabels(cache, fileReport) {
  setStageLabel(cache, 'role-muscular-male', 'stage-2', UNKNOWN_CLOTHING_LABEL, fileReport);
  setStageLabel(cache, 'role-anonymous-male', 'stage-1', UNKNOWN_CLOTHING_LABEL, fileReport);
}

function removeNonSceneTerms(cache, fileReport) {
  const beforeSceneTerms = Array.isArray(cache.aiRoleExtraction?.scene_terms)
    ? cache.aiRoleExtraction.scene_terms.length
    : null;
  if (beforeSceneTerms !== null) {
    cache.aiRoleExtraction.scene_terms = cache.aiRoleExtraction.scene_terms.filter(
      (term) => !NON_SCENE_TERMS.has(normalize(term.text)),
    );
    if (cache.aiRoleExtraction.scene_terms.length !== beforeSceneTerms) {
      addChange(fileReport, {
        section: 'aiRoleExtraction.scene_terms',
        field: 'scene_terms',
        before: beforeSceneTerms,
        after: cache.aiRoleExtraction.scene_terms.length,
        reason: 'removed_non_scene_style_terms',
      });
    }
  }

  for (const group of cache.mapping?.scenePromptReplacements ?? []) {
    const before = Array.isArray(group.rules) ? group.rules.length : null;
    if (before === null) continue;
    for (const rule of group.rules) {
      if (!Array.isArray(rule.sourceTerms)) continue;
      rule.sourceTerms = rule.sourceTerms.filter(
        (term) => !NON_SCENE_TERMS.has(normalize(term.text)),
      );
    }
    group.rules = group.rules.filter((rule) => (rule.sourceTerms ?? []).length > 0);
    if (group.rules.length !== before) {
      addChange(fileReport, {
        section: 'mapping.scenePromptReplacements',
        field: 'rules',
        before,
        after: group.rules.length,
        reason: 'removed_non_scene_style_terms',
      });
    }
  }
}

function setStageLabel(cache, roleId, stageId, label, fileReport) {
  const role = findRole(cache, roleId);
  const stage = role?.stages?.find((item) => item.stage_id === stageId);
  if (stage) {
    setValue(stage, 'label', label, fileReport, {
      section: 'aiRoleExtraction.roles.stages',
      role_id: roleId,
      stage_id: stageId,
      field: 'label',
    });
    const beforeWarnings = Array.isArray(stage.warnings) ? [...stage.warnings] : [];
    stage.warnings = beforeWarnings.filter((warning) => warning !== 'stage_label_needs_manual_review');
    recordArrayChange(beforeWarnings, stage.warnings, fileReport, {
      section: 'aiRoleExtraction.roles.stages',
      role_id: roleId,
      stage_id: stageId,
      field: 'warnings',
      reason: 'cleared_resolved_manual_review_warning',
    });
  }

  const assembly = findAssembly(cache, roleId);
  const mappingStage = assembly?.stages?.find((item) => item.id === stageId);
  if (mappingStage) {
    setValue(mappingStage, 'label', label, fileReport, {
      section: 'mapping.roleAssemblies.stages',
      role_id: roleId,
      stage_id: stageId,
      field: 'label',
    });
  }
}

function auditCache(cache) {
  const roleFieldIssues = [];
  const genericIdentityIssues = [];
  const stageWarningIssues = [];
  const sceneStyleIssues = [];

  for (const role of cache.aiRoleExtraction?.roles ?? []) {
    const roleId = stringValue(role.source_role_id);
    for (const term of role.raw_identity_tags ?? []) {
      if (GENERIC_IDENTITY_TERMS.has(normalize(term))) {
        genericIdentityIssues.push({ section: 'raw_identity_tags', role_id: roleId, term });
      }
    }
    for (const term of role.prompt_terms ?? []) {
      if (
        stringValue(term.category) === 'identity' &&
        GENERIC_IDENTITY_TERMS.has(normalize(term.text))
      ) {
        genericIdentityIssues.push({ section: 'prompt_terms', role_id: roleId, term: term.text });
      }
    }
    for (const stage of role.stages ?? []) {
      if ((stage.warnings ?? []).includes('stage_label_needs_manual_review')) {
        stageWarningIssues.push({ role_id: roleId, stage_id: stringValue(stage.stage_id) });
      }
      for (const field of ['identity', 'upper_body', 'lower_body', 'upper_clothing', 'lower_clothing']) {
        for (const term of splitTerms(stage[field])) {
          if (ROLE_STATE_TERMS.has(normalize(term))) {
            roleFieldIssues.push({
              section: 'aiRoleExtraction.roles.stages',
              role_id: roleId,
              stage_id: stringValue(stage.stage_id),
              field,
              term,
            });
          }
          if (field === 'identity' && GENERIC_IDENTITY_TERMS.has(normalize(term))) {
            genericIdentityIssues.push({
              section: 'stage.identity',
              role_id: roleId,
              stage_id: stringValue(stage.stage_id),
              term,
            });
          }
        }
      }
    }
  }

  for (const assembly of cache.mapping?.roleAssemblies ?? []) {
    for (const stage of assembly.stages ?? []) {
      const parts = stage.sourceParts ?? {};
      for (const [field, value] of Object.entries(parts)) {
        for (const term of splitTerms(value)) {
          if (ROLE_STATE_TERMS.has(normalize(term))) {
            roleFieldIssues.push({
              section: 'mapping.roleAssemblies.stages',
              role_id: stringValue(assembly.sourceRoleId),
              stage_id: stringValue(stage.id),
              field,
              term,
            });
          }
          if (field === 'identity' && GENERIC_IDENTITY_TERMS.has(normalize(term))) {
            genericIdentityIssues.push({
              section: 'mapping.stage.identity',
              role_id: stringValue(assembly.sourceRoleId),
              stage_id: stringValue(stage.id),
              term,
            });
          }
        }
      }
    }
  }

  for (const term of cache.aiRoleExtraction?.scene_terms ?? []) {
    if (NON_SCENE_TERMS.has(normalize(term.text))) {
      sceneStyleIssues.push({ section: 'aiRoleExtraction.scene_terms', term: term.text });
    }
  }
  for (const group of cache.mapping?.scenePromptReplacements ?? []) {
    for (const rule of group.rules ?? []) {
      for (const term of rule.sourceTerms ?? []) {
        if (NON_SCENE_TERMS.has(normalize(term.text))) {
          sceneStyleIssues.push({ section: 'mapping.scenePromptReplacements', term: term.text });
        }
      }
    }
  }

  const roles = cache.aiRoleExtraction?.roles ?? [];
  return {
    role_count: roles.length,
    stage_count: roles.reduce((total, role) => total + (role.stages?.length ?? 0), 0),
    prompt_term_count: roles.reduce((total, role) => total + (role.prompt_terms?.length ?? 0), 0),
    scene_term_count: cache.aiRoleExtraction?.scene_terms?.length ?? 0,
    role_prompt_rule_count: (cache.mapping?.rolePromptReplacements ?? []).reduce(
      (total, group) => total + (group.rules?.length ?? 0),
      0,
    ),
    scene_prompt_rule_count: (cache.mapping?.scenePromptReplacements ?? []).reduce(
      (total, group) => total + (group.rules?.length ?? 0),
      0,
    ),
    role_state_terms_in_stage_fields: roleFieldIssues,
    generic_identity_terms: genericIdentityIssues,
    unresolved_stage_label_warnings: stageWarningIssues,
    non_scene_style_terms: sceneStyleIssues,
  };
}

function cleanIdentityField(container, key, context) {
  const before = stringValue(container[key]);
  const after = removeTerms(before, GENERIC_IDENTITY_TERMS);
  if (after === before) return;
  if (after) {
    container[key] = after;
  } else {
    delete container[key];
  }
  addChange(context.fileReport, {
    section: context.section,
    role_id: context.roleId,
    stage_id: context.stageId,
    field: key,
    before,
    after,
    reason: 'removed_generic_identity_terms',
  });
}

function refreshMappingStageSummary(stage) {
  const parts = stage.sourceParts ?? {};
  const values = ['identity', 'upperBody', 'lowerBody', 'upperClothing', 'lowerClothing']
    .map((field) => stringValue(parts[field]))
    .filter(Boolean);
  stage.sourceSummary = values.join(', ');
}

function refreshMissingField(stage, field, missingField) {
  stage.missing_fields = Array.isArray(stage.missing_fields) ? stage.missing_fields : [];
  const hasValue = stringValue(stage[field]).length > 0;
  if (!hasValue && !stage.missing_fields.includes(missingField)) {
    stage.missing_fields.push(missingField);
  }
  if (hasValue) {
    stage.missing_fields = stage.missing_fields.filter((item) => item !== missingField);
  }
}

function addOmittedPart(stage, field) {
  stage.omittedParts = Array.isArray(stage.omittedParts) ? stage.omittedParts : [];
  if (!stage.omittedParts.includes(field)) {
    stage.omittedParts.push(field);
  }
}

function findRole(cache, roleId) {
  return (cache.aiRoleExtraction?.roles ?? []).find((role) => role.source_role_id === roleId);
}

function findAssembly(cache, roleId) {
  return (cache.mapping?.roleAssemblies ?? []).find((assembly) => assembly.sourceRoleId === roleId);
}

function findRolePromptGroup(cache, roleId) {
  return (cache.mapping?.rolePromptReplacements ?? []).find(
    (group) => group.sourceRoleId === roleId,
  );
}

function setValue(object, key, value, fileReport, context) {
  const before = object[key];
  if (before === value) return;
  object[key] = value;
  addChange(fileReport, { ...context, before, after: value, reason: 'set_case_verified_value' });
}

function recordArrayChange(before, after, fileReport, context) {
  if (JSON.stringify(before) === JSON.stringify(after)) return;
  addChange(fileReport, { ...context, before, after });
}

function addChange(fileReport, change) {
  fileReport.changes.push(change);
}

function removeTerms(value, bannedTerms) {
  const terms = splitTerms(value);
  const kept = terms.filter((term) => !bannedTerms.has(normalize(term)));
  return kept.join(', ');
}

function splitTerms(value) {
  return stringValue(value)
    .split(',')
    .map((term) => term.trim())
    .filter(Boolean);
}

function normalize(value) {
  return stringValue(value).trim().toLowerCase().replace(/_/g, ' ').replace(/\s+/g, ' ');
}

function stringValue(value) {
  return typeof value === 'string' ? value : '';
}

function resolveInputFiles({ file, cacheDir, nameContains }) {
  if (file) return [path.resolve(file)];
  if (!fs.existsSync(cacheDir)) {
    throw new Error(`Missing cache dir: ${cacheDir}`);
  }
  return fs
    .readdirSync(cacheDir)
    .filter((entry) => entry === TARGET_FILE || (nameContains && entry.includes(nameContains)))
    .filter((entry) => entry.endsWith('.json'))
    .sort()
    .map((entry) => path.join(cacheDir, entry));
}

function parseArgs(argv) {
  const result = {
    apply: false,
    cacheDir: null,
    file: null,
    nameContains: null,
    report: null,
  };
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === '--apply') {
      result.apply = true;
    } else if (arg === '--cache-dir') {
      result.cacheDir = argv[++index];
    } else if (arg === '--file') {
      result.file = argv[++index];
    } else if (arg === '--name-contains') {
      result.nameContains = argv[++index];
    } else if (arg === '--report') {
      result.report = argv[++index];
    } else {
      throw new Error(`Unknown argument: ${arg}`);
    }
  }
  return result;
}
