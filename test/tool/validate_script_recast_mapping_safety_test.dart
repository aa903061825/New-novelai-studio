import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('validator fails closed for hidden and unsafe mappings', () async {
    final fixture = await _ValidationFixture.create();
    addTearDown(fixture.dispose);
    fixture.writeCache(_badCache(fixture.sourceRoot.path));

    final result = await fixture.runValidator();

    expect(result.exitCode, isNot(0));
    final report = fixture.readReport();
    expect(report['eligible_cache_files'], 1);
    expect(report['hidden_role_swap_count'], 1);
    expect(report['mapped_male_role_count'], 1);
    expect(report['mapped_role_prompt_term_coverage_gap_count'], 1);
    expect(report['pseudo_partial_role_count'], 1);
    expect(report['appearance_collision_count'], greaterThan(0));
    expect(report['target_stage_mismatch_count'], 1);
    expect(report['regression_male_target_count'], 1);
    expect(report['violation_count'], greaterThanOrEqualTo(6));
  });

  test('validator accepts a visible identity mapping and untouched male slot',
      () async {
    final fixture = await _ValidationFixture.create();
    addTearDown(fixture.dispose);
    fixture.writeCache(_cleanCache(fixture.sourceRoot.path));

    final result = await fixture.runValidator();

    expect(
      result.exitCode,
      0,
      reason: 'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
    );
    final report = fixture.readReport();
    expect(report['eligible_cache_files'], 1);
    expect(report['mapped_role_count'], 1);
    expect(report['violation_count'], 0);
  });

  test('validator keeps legacy behavior when term review is disabled',
      () async {
    final fixture = await _ValidationFixture.create();
    addTearDown(fixture.dispose);
    final cache = _cleanCache(fixture.sourceRoot.path);
    final role =
        ((cache['aiRoleExtraction'] as Map<String, dynamic>)['roles'] as List)
            .cast<Map<String, dynamic>>()
            .first;
    final promptTerm =
        (role['prompt_terms'] as List).cast<Map<String, dynamic>>().first;
    promptTerm['source_occurrences'] = [
      _occurrence(32, 'role identity evidence'),
    ];
    fixture.writeCache(cache);

    final result = await fixture.runValidator();

    expect(
      result.exitCode,
      0,
      reason: 'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
    );
    final report = fixture.readReport();
    expect(report['violation_count'], 0);
  });

  test('strict term review accepts synchronized reviewed membership', () async {
    final fixture = await _ValidationFixture.create();
    addTearDown(fixture.dispose);
    fixture.writeCache(
      _termMembershipCache(
        fixture.sourceRoot.path,
        aiRoleTerms: [
          _promptTerm('reisa (blue archive)', 'character'),
          _promptTerm('twin drills', 'upperBody'),
        ],
        mappingRoleTerms: [
          _promptTerm('reisa (blue archive)', 'character'),
          _promptTerm('twin drills', 'upperBody'),
        ],
      ),
    );
    fixture.writeTermReview(_completeTermMembershipReview());

    final result = await fixture.runValidator(termReview: true);

    expect(
      result.exitCode,
      0,
      reason: 'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
    );
    final report = fixture.readReport();
    expect(report['term_review_decision_count'], 4);
    expect(report['term_review_missing_term_count'], 0);
    expect(report['term_review_unresolved_term_count'], 0);
    expect(report['term_review_complete'], isTrue);
    expect(report['violation_count'], 0);
  });

  test('strict term review allows omitted generic identity on a concrete role',
      () async {
    final fixture = await _ValidationFixture.create();
    addTearDown(fixture.dispose);
    fixture.writeCache(
      _termMembershipCache(
        fixture.sourceRoot.path,
        roleCaption: 'reisa (blue archive), girl, loli, child, twin drills',
        aiRoleTerms: [
          _promptTerm('reisa (blue archive)', 'character'),
          _promptTerm('twin drills', 'upperBody'),
        ],
        mappingRoleTerms: [
          _promptTerm('reisa (blue archive)', 'character'),
          _promptTerm('twin drills', 'upperBody'),
        ],
      ),
    );
    fixture.writeTermReview({
      'schema_version': 1,
      'kind': 'script_recast_term_membership_review',
      'api_used': false,
      'decisions': [
        _reviewDecision('reisa (blue archive)', 'role', 'character'),
        for (final term in ['girl', 'loli', 'child'])
          _reviewDecision(term, 'role', 'character'),
        _reviewDecision('twin drills', 'role', 'upperBody'),
        _reviewDecision('outdoors', 'scene', 'scene'),
      ],
    });

    final result = await fixture.runValidator(termReview: true);

    expect(
      result.exitCode,
      0,
      reason: 'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
    );
    final report = fixture.readReport();
    expect(report['term_review_required_role_missing_ai_count'], 0);
    expect(report['term_review_required_role_missing_mapping_count'], 0);
    expect(report['violation_count'], 0);
  });

  test(
      'strict term review allows omitted male generic identity on a concrete role',
      () async {
    final fixture = await _ValidationFixture.create();
    addTearDown(fixture.dispose);
    fixture.writeCache(
      _termMembershipCache(
        fixture.sourceRoot.path,
        roleCaption: 'sensei (blue archive), boy, male, child, twin drills',
        roleName: 'Sensei',
        rawIdentityTags: const ['sensei_(blue_archive)', 'male'],
        targetCharacterId: null,
        aiRoleTerms: [
          _promptTerm('sensei (blue archive)', 'character'),
          _promptTerm('twin drills', 'upperBody'),
        ],
        mappingRoleTerms: [
          _promptTerm('sensei (blue archive)', 'character'),
          _promptTerm('twin drills', 'upperBody'),
        ],
      ),
    );
    fixture.writeTermReview({
      'schema_version': 1,
      'kind': 'script_recast_term_membership_review',
      'api_used': false,
      'decisions': [
        _reviewDecision('sensei (blue archive)', 'role', 'character'),
        for (final term in ['boy', 'male', 'child'])
          _reviewDecision(term, 'role', 'character'),
        _reviewDecision('twin drills', 'role', 'upperBody'),
        _reviewDecision('outdoors', 'scene', 'scene'),
      ],
    });

    final result = await fixture.runValidator(termReview: true);

    expect(
      result.exitCode,
      0,
      reason: 'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
    );
    final report = fixture.readReport();
    expect(report['term_review_required_role_missing_ai_count'], 0);
    expect(report['term_review_required_role_missing_mapping_count'], 0);
    expect(report['violation_count'], 0);
  });

  test('strict term review still requires other role terms on a concrete role',
      () async {
    final fixture = await _ValidationFixture.create();
    addTearDown(fixture.dispose);
    fixture.writeCache(
      _termMembershipCache(
        fixture.sourceRoot.path,
        roleCaption: 'reisa (blue archive), girl, twin drills',
        aiRoleTerms: [
          _promptTerm('reisa (blue archive)', 'character'),
        ],
        mappingRoleTerms: [
          _promptTerm('reisa (blue archive)', 'character'),
        ],
      ),
    );
    fixture.writeTermReview({
      'schema_version': 1,
      'kind': 'script_recast_term_membership_review',
      'api_used': false,
      'decisions': [
        _reviewDecision('reisa (blue archive)', 'role', 'character'),
        _reviewDecision('girl', 'role', 'character'),
        _reviewDecision('twin drills', 'role', 'upperBody'),
        _reviewDecision('outdoors', 'scene', 'scene'),
      ],
    });

    final result = await fixture.runValidator(termReview: true);

    expect(result.exitCode, isNot(0));
    final report = fixture.readReport();
    expect(report['term_review_required_role_missing_ai_count'], 1);
    expect(report['term_review_required_role_missing_mapping_count'], 1);
  });

  test('strict term review does not exempt generic identity on a generic role',
      () async {
    final fixture = await _ValidationFixture.create();
    addTearDown(fixture.dispose);
    fixture.writeCache(
      _termMembershipCache(
        fixture.sourceRoot.path,
        roleCaption: 'girl',
        rawIdentityTags: const ['girl'],
        roleName: 'Girl',
        aiRoleTerms: const [],
        mappingRoleTerms: const [],
      ),
    );
    fixture.writeTermReview({
      'schema_version': 1,
      'kind': 'script_recast_term_membership_review',
      'api_used': false,
      'decisions': [
        _reviewDecision('girl', 'role', 'character'),
        _reviewDecision('outdoors', 'scene', 'scene'),
      ],
    });

    final result = await fixture.runValidator(termReview: true);

    expect(result.exitCode, isNot(0));
    final report = fixture.readReport();
    expect(report['term_review_required_role_missing_ai_count'], 1);
    expect(report['term_review_required_role_missing_mapping_count'], 1);
  });

  test('strict term review does not exempt a generic any-role decision',
      () async {
    final fixture = await _ValidationFixture.create();
    addTearDown(fixture.dispose);
    final cache = _termMembershipCache(
      fixture.sourceRoot.path,
      roleCaption: 'reisa (blue archive), twin drills',
      aiRoleTerms: [
        _promptTerm('reisa (blue archive)', 'character'),
        _promptTerm('twin drills', 'upperBody'),
      ],
      mappingRoleTerms: [
        _promptTerm('reisa (blue archive)', 'character'),
        _promptTerm('twin drills', 'upperBody'),
      ],
    );
    final snapshot = cache['scriptSnapshot'] as Map<String, dynamic>;
    final frame = (snapshot['frames'] as List).single as Map<String, dynamic>;
    final parsed = frame['parsed'] as Map<String, dynamic>;
    parsed['baseCaption'] = 'outdoors, girl';
    fixture.writeCache(cache);
    fixture.writeTermReview({
      'schema_version': 1,
      'kind': 'script_recast_term_membership_review',
      'api_used': false,
      'decisions': [
        _reviewDecision('reisa (blue archive)', 'role', 'character'),
        _reviewDecision('twin drills', 'role', 'upperBody'),
        _reviewDecision('girl', 'role', 'character'),
        _reviewDecision('outdoors', 'scene', 'scene'),
      ],
    });

    final result = await fixture.runValidator(termReview: true);

    expect(result.exitCode, isNot(0));
    final report = fixture.readReport();
    expect(report['term_review_required_role_missing_ai_count'], 1);
    expect(report['term_review_required_role_missing_mapping_count'], 1);
  });

  test('strict term review does not exempt non-generic character terms',
      () async {
    final fixture = await _ValidationFixture.create();
    addTearDown(fixture.dispose);
    fixture.writeCache(
      _termMembershipCache(
        fixture.sourceRoot.path,
        roleCaption: 'reisa (blue archive), girl, idol, dog, paparazzi, '
            'twin drills',
        aiRoleTerms: [
          _promptTerm('reisa (blue archive)', 'character'),
          _promptTerm('twin drills', 'upperBody'),
        ],
        mappingRoleTerms: [
          _promptTerm('reisa (blue archive)', 'character'),
          _promptTerm('twin drills', 'upperBody'),
        ],
      ),
    );
    fixture.writeTermReview({
      'schema_version': 1,
      'kind': 'script_recast_term_membership_review',
      'api_used': false,
      'decisions': [
        _reviewDecision('reisa (blue archive)', 'role', 'character'),
        _reviewDecision('girl', 'role', 'character'),
        for (final term in ['idol', 'dog', 'paparazzi'])
          _reviewDecision(term, 'role', 'character'),
        _reviewDecision('twin drills', 'role', 'upperBody'),
        _reviewDecision('outdoors', 'scene', 'scene'),
      ],
    });

    final result = await fixture.runValidator(termReview: true);

    expect(result.exitCode, isNot(0));
    final report = fixture.readReport();
    expect(report['term_review_required_role_missing_ai_count'], 3);
    expect(report['term_review_required_role_missing_mapping_count'], 3);
  });

  test('strict term review rejects crotch focus even when AI and mapping agree',
      () async {
    final fixture = await _ValidationFixture.create();
    addTearDown(fixture.dispose);
    fixture.writeCache(
      _termMembershipCache(
        fixture.sourceRoot.path,
        aiRoleTerms: [
          _promptTerm('reisa (blue archive)', 'character'),
          _promptTerm('twin drills', 'upperBody'),
          _promptTerm('crotch focus', 'lowerBody'),
        ],
        mappingRoleTerms: [
          _promptTerm('reisa (blue archive)', 'character'),
          _promptTerm('twin drills', 'upperBody'),
          _promptTerm('crotch focus', 'lowerBody'),
        ],
      ),
    );
    fixture.writeTermReview(_completeTermMembershipReview());

    final result = await fixture.runValidator(termReview: true);

    expect(result.exitCode, isNot(0));
    final report = fixture.readReport();
    expect(report['term_review_missing_term_count'], 0);
    expect(report['term_review_excluded_ai_leak_count'], 1);
    expect(report['term_review_excluded_mapping_leak_count'], 1);
    expect(report['term_review_ai_mapping_term_set_mismatch_count'], 0);
    expect(report['violation_count'], greaterThanOrEqualTo(2));
  });

  test('strict term review rejects stage residue that can resurrect on reopen',
      () async {
    final fixture = await _ValidationFixture.create();
    addTearDown(fixture.dispose);
    final cache = _termMembershipCache(
      fixture.sourceRoot.path,
      aiRoleTerms: [
        _promptTerm('reisa (blue archive)', 'character'),
        _promptTerm('twin drills', 'upperBody'),
      ],
      mappingRoleTerms: [
        _promptTerm('reisa (blue archive)', 'character'),
        _promptTerm('twin drills', 'upperBody'),
      ],
    );
    final extraction = cache['aiRoleExtraction'] as Map<String, dynamic>;
    final role = (extraction['roles'] as List).single as Map<String, dynamic>;
    final stage = (role['stages'] as List).single as Map<String, dynamic>;
    stage['lower_body'] = 'crotch focus';
    stage['non_role'] = 'hand in clothes';
    stage.remove('non_role_materialized');
    fixture.writeCache(cache);
    fixture.writeTermReview(_completeTermMembershipReview());

    final result = await fixture.runValidator(termReview: true);

    expect(result.exitCode, isNot(0));
    final report = fixture.readReport();
    expect(report['term_review_excluded_stage_leak_count'], 1);
    expect(
      report['term_review_stage_materialization_marker_missing_count'],
      1,
    );
    expect(report['term_review_stage_non_role_residue_count'], 1);
    expect(report['term_review_complete'], isFalse);
  });

  test('strict term review reports incomplete and divergent membership',
      () async {
    final fixture = await _ValidationFixture.create();
    addTearDown(fixture.dispose);
    fixture.writeCache(
      _termMembershipCache(
        fixture.sourceRoot.path,
        roleCaption: 'reisa (blue archive), twin drills, alternate hairstyle, '
            'magical girl, high twintails, standing, facial',
        aiRoleTerms: [
          _promptTerm('reisa (blue archive)', 'character'),
          _promptTerm('alternate hairstyle', 'upperBody'),
          _promptTerm('magical girl', 'upperBody'),
          _promptTerm('high twintails', 'upperBody'),
        ],
        mappingRoleTerms: [
          _promptTerm('reisa (blue archive)', 'character'),
          _promptTerm('twin drills', 'upperBody'),
          _promptTerm('magical girl', 'upperBody'),
          _promptTerm('high twintails', 'character'),
        ],
      ),
    );
    fixture.writeTermReview({
      'schema_version': 1,
      'kind': 'script_recast_term_membership_review',
      'api_used': false,
      'decisions': [
        _reviewDecision('reisa (blue archive)', 'role', 'character'),
        _reviewDecision('twin drills', 'role', 'upperBody'),
        _reviewDecision('alternate hairstyle', 'role', 'upperBody'),
        _reviewDecision('magical girl', 'role', 'character'),
        _reviewDecision('high twintails', 'role', 'upperBody'),
        _reviewDecision('facial', 'unresolved'),
        _reviewDecision('outdoors', 'scene', 'scene'),
      ],
    });

    final result = await fixture.runValidator(termReview: true);

    expect(result.exitCode, isNot(0));
    final report = fixture.readReport();
    expect(report['term_review_missing_term_count'], 1);
    expect(report['term_review_unresolved_term_count'], 1);
    expect(report['term_review_required_role_missing_ai_count'], 1);
    expect(report['term_review_required_role_missing_mapping_count'], 1);
    expect(
      report['term_review_required_role_category_mismatch_count'],
      2,
    );
    expect(report['term_review_ai_mapping_term_set_mismatch_count'], 2);
    expect(report['term_review_ai_mapping_category_mismatch_count'], 1);
    expect(report['term_review_complete'], isFalse);
  });

  test(
      'strict term review accepts exact occurrence routed to a compatible owner',
      () async {
    final fixture = await _ValidationFixture.create();
    addTearDown(fixture.dispose);
    fixture.writeCache(
      _crossOwnerOccurrenceCache(fixture.sourceRoot.path),
    );
    fixture.writeTermReview(_twoFrameTwoSlotReview());

    final result = await fixture.runValidator(termReview: true);

    expect(
      result.exitCode,
      0,
      reason: 'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
    );
    final report = fixture.readReport();
    expect(report['term_review_required_role_missing_ai_count'], 0);
    expect(report['term_review_required_role_missing_mapping_count'], 0);
    expect(report['term_review_source_occurrence_missing_ai_count'], 0);
    expect(report['term_review_source_occurrence_missing_mapping_count'], 0);
    expect(report['term_review_complete'], isTrue);
  });

  test(
      'strict term review keeps concrete generic omission local to its source role',
      () async {
    final fixture = await _ValidationFixture.create();
    addTearDown(fixture.dispose);
    fixture.writeCache(
      _genericConcreteOmissionCache(fixture.sourceRoot.path),
    );
    fixture.writeTermReview({
      ..._twoFrameTwoSlotReview(),
      'decisions': [
        _reviewDecision('reisa (blue archive)', 'role', 'character'),
        _reviewDecision('girl', 'role', 'character'),
        _reviewDecision('twin drills', 'role', 'upperBody'),
        _reviewDecision('outdoors', 'scene', 'scene'),
      ],
    });

    final result = await fixture.runValidator(termReview: true);

    expect(
      result.exitCode,
      0,
      reason: 'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
    );
    final report = fixture.readReport();
    expect(report['term_review_source_occurrence_missing_ai_count'], 0);
    expect(report['term_review_source_occurrence_missing_mapping_count'], 0);
    expect(report['term_review_complete'], isTrue);
  });

  test('strict term review rejects a missing physical slot occurrence',
      () async {
    final fixture = await _ValidationFixture.create();
    addTearDown(fixture.dispose);
    final cache = _twoFrameTwoSlotOccurrenceCache(fixture.sourceRoot.path);
    _removeOccurrence(
      _aiRoleTerm(cache, 'role-alice', 'blue jacket'),
      frameIndex: 33,
      sourceLocation: 'slot-0 prompt',
    );
    _removeOccurrence(
      _mappingRoleTerm(cache, 'role-alice', 'blue jacket'),
      frameIndex: 33,
      sourceLocation: 'slot-0 prompt',
    );
    fixture.writeCache(cache);
    fixture.writeTermReview(_twoFrameTwoSlotReview());

    final result = await fixture.runValidator(termReview: true);

    expect(result.exitCode, isNot(0));
    final report = fixture.readReport();
    expect(report['term_review_source_occurrence_missing_ai_count'], 1);
    expect(report['term_review_source_occurrence_missing_mapping_count'], 1);
    expect(report['term_review_complete'], isFalse);
  });

  test('strict term review rejects an AI occurrence dropped by mapping',
      () async {
    final fixture = await _ValidationFixture.create();
    addTearDown(fixture.dispose);
    final cache = _twoFrameTwoSlotOccurrenceCache(fixture.sourceRoot.path);
    _removeOccurrence(
      _mappingRoleTerm(cache, 'role-alice', 'blue jacket'),
      frameIndex: 33,
      sourceLocation: 'slot-0 prompt',
    );
    fixture.writeCache(cache);
    fixture.writeTermReview(_twoFrameTwoSlotReview());

    final result = await fixture.runValidator(termReview: true);

    expect(result.exitCode, isNot(0));
    final report = fixture.readReport();
    expect(report['term_review_source_occurrence_missing_ai_count'], 0);
    expect(report['term_review_source_occurrence_missing_mapping_count'], 1);
    expect(
      report['term_review_source_occurrence_ai_mapping_mismatch_count'],
      greaterThan(0),
    );
  });

  test('strict term review rejects Cartesian-forged physical occurrences',
      () async {
    final fixture = await _ValidationFixture.create();
    addTearDown(fixture.dispose);
    final cache = _twoFrameTwoSlotOccurrenceCache(fixture.sourceRoot.path);
    final snapshot = cache['scriptSnapshot'] as Map<String, dynamic>;
    final frames = (snapshot['frames'] as List).cast<Map<String, dynamic>>();
    ((frames[0]['parsed'] as Map<String, dynamic>)['charCaptions'] as List)[1] =
        'bob_(series)';
    ((frames[1]['parsed'] as Map<String, dynamic>)['charCaptions'] as List)[0] =
        'alice_(series)';
    final forged = [
      _occurrence(32, 'slot-1 prompt'),
      _occurrence(33, 'slot-0 prompt'),
    ];
    _setOccurrences(_aiRoleTerm(cache, 'role-alice', 'blue jacket'), forged);
    _setOccurrences(_aiRoleTerm(cache, 'role-bob', 'blue jacket'), forged);
    _setOccurrences(
      _mappingRoleTerm(cache, 'role-alice', 'blue jacket'),
      forged,
    );
    _setOccurrences(
      _mappingRoleTerm(cache, 'role-bob', 'blue jacket'),
      forged,
    );
    fixture.writeCache(cache);
    fixture.writeTermReview(_twoFrameTwoSlotReview());

    final result = await fixture.runValidator(termReview: true);

    expect(result.exitCode, isNot(0));
    final report = fixture.readReport();
    expect(report['term_review_source_occurrence_missing_ai_count'], 2);
    expect(report['term_review_source_occurrence_missing_mapping_count'], 2);
    expect(
      report['term_review_source_occurrence_unbacked_ai_count'],
      greaterThan(0),
    );
    expect(
      report['term_review_source_occurrence_unbacked_mapping_count'],
      greaterThan(0),
    );
  });

  test('strict term review rejects excluded physical term leakage', () async {
    final fixture = await _ValidationFixture.create();
    addTearDown(fixture.dispose);
    final cache = _twoFrameTwoSlotOccurrenceCache(fixture.sourceRoot.path);
    final snapshot = cache['scriptSnapshot'] as Map<String, dynamic>;
    final frames = (snapshot['frames'] as List).cast<Map<String, dynamic>>();
    final firstParsed = frames[0]['parsed'] as Map<String, dynamic>;
    firstParsed['baseCaption'] = 'outdoors, crotch focus';
    final excludedTerm = _promptTermWithOccurrences(
      'crotch focus',
      'lowerBody',
      [_occurrence(32, 'base prompt')],
    );
    (_aiRole(cache, 'role-alice')['prompt_terms'] as List).add(excludedTerm);
    _appendMappingRoleTerm(
      cache,
      'role-alice',
      _mappingPhysicalTerm(excludedTerm),
    );
    fixture.writeCache(cache);
    fixture.writeTermReview({
      ..._twoFrameTwoSlotReview(),
      'decisions': [
        ...(_twoFrameTwoSlotReview()['decisions'] as List),
        _reviewDecision('crotch focus', 'exclude'),
      ],
    });

    final result = await fixture.runValidator(termReview: true);

    expect(result.exitCode, isNot(0));
    final report = fixture.readReport();
    expect(report['term_review_excluded_ai_leak_count'], 1);
    expect(report['term_review_excluded_mapping_leak_count'], 1);
    expect(report['term_review_source_occurrence_invalid_ai_count'], 0);
    expect(report['term_review_source_occurrence_unbacked_mapping_count'], 0);
  });

  test('strict term review accepts exact two-frame two-slot occurrences',
      () async {
    final fixture = await _ValidationFixture.create();
    addTearDown(fixture.dispose);
    fixture.writeCache(
      _twoFrameTwoSlotOccurrenceCache(fixture.sourceRoot.path),
    );
    fixture.writeTermReview(_twoFrameTwoSlotReview());

    final result = await fixture.runValidator(termReview: true);

    expect(
      result.exitCode,
      0,
      reason: 'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
    );
    final report = fixture.readReport();
    expect(report['term_review_source_occurrence_invalid_ai_count'], 0);
    expect(report['term_review_source_occurrence_invalid_mapping_count'], 0);
    expect(report['term_review_source_occurrence_duplicate_ai_count'], 0);
    expect(report['term_review_source_occurrence_duplicate_mapping_count'], 0);
    expect(report['term_review_source_occurrence_unbacked_ai_count'], 0);
    expect(report['term_review_source_occurrence_unbacked_mapping_count'], 0);
    expect(report['term_review_source_occurrence_missing_ai_count'], 0);
    expect(report['term_review_source_occurrence_missing_mapping_count'], 0);
    expect(
      report['term_review_source_occurrence_ai_mapping_mismatch_count'],
      0,
    );
    expect(report['term_review_complete'], isTrue);
    expect(report['violation_count'], 0);
  });

  test('strict term review counts invalid and duplicate structured occurrences',
      () async {
    final fixture = await _ValidationFixture.create();
    addTearDown(fixture.dispose);
    final cache = _twoFrameTwoSlotOccurrenceCache(fixture.sourceRoot.path);
    _setOccurrences(
      _aiRoleTerm(cache, 'role-alice', 'alice_(series)'),
      [
        _occurrence(32, 'role identity evidence'),
        _occurrence(32, 'slot-0 prompt'),
        _occurrence(32, 'slot-0 prompt'),
      ],
    );
    fixture.writeCache(cache);
    fixture.writeTermReview(_twoFrameTwoSlotReview());

    final result = await fixture.runValidator(termReview: true);

    expect(result.exitCode, isNot(0));
    final report = fixture.readReport();
    expect(report['term_review_source_occurrence_invalid_ai_count'], 1);
    expect(report['term_review_source_occurrence_duplicate_ai_count'], 1);
    expect(report['term_review_complete'], isFalse);
  });

  test('validator rejects a canonical name made from a non-character tag',
      () async {
    final fixture = await _ValidationFixture.create();
    addTearDown(fixture.dispose);
    fixture.writeCache(_pseudoCanonicalCache(fixture.sourceRoot.path));

    final result = await fixture.runValidator();

    expect(result.exitCode, isNot(0));
    final report = fixture.readReport();
    expect(report['pseudo_partial_role_count'], 1);
  });

  test('validator rejects an object tag used as a character identity',
      () async {
    final fixture = await _ValidationFixture.create();
    addTearDown(fixture.dispose);
    fixture.writeCache(_objectIdentityCache(fixture.sourceRoot.path));

    final result = await fixture.runValidator();

    expect(result.exitCode, isNot(0));
    final report = fixture.readReport();
    expect(report['pseudo_partial_role_count'], 1);
  });

  test('validator rejects a franchise-qualified visual object as a role',
      () async {
    final fixture = await _ValidationFixture.create();
    addTearDown(fixture.dispose);
    fixture.writeCache(_franchiseObjectIdentityCache(fixture.sourceRoot.path));

    final result = await fixture.runValidator();

    expect(result.exitCode, isNot(0));
    final report = fixture.readReport();
    expect(report['pseudo_partial_role_count'], 1);
  });
}

class _ValidationFixture {
  final Directory root;
  final Directory cacheDir;
  final Directory sourceRoot;
  final File reportFile;
  final File termReviewFile;

  const _ValidationFixture({
    required this.root,
    required this.cacheDir,
    required this.sourceRoot,
    required this.reportFile,
    required this.termReviewFile,
  });

  static Future<_ValidationFixture> create() async {
    final root = await Directory.systemTemp.createTemp(
      'script-recast-mapping-validator-test-',
    );
    final cacheDir = Directory('${root.path}/cache')..createSync();
    final sourceRoot = Directory('${root.path}/source')..createSync();
    Directory('${sourceRoot.path}/story').createSync();
    return _ValidationFixture(
      root: root,
      cacheDir: cacheDir,
      sourceRoot: sourceRoot,
      reportFile: File('${root.path}/report.json'),
      termReviewFile: File('${root.path}/term-review.json'),
    );
  }

  void writeCache(Map<String, dynamic> cache) {
    File('${cacheDir.path}/script-safety.json')
        .writeAsStringSync(jsonEncode(cache));
  }

  void writeTermReview(Map<String, dynamic> review) {
    termReviewFile.writeAsStringSync(jsonEncode(review));
  }

  Future<ProcessResult> runValidator({bool termReview = false}) {
    return Process.run(
      'node',
      [
        'tool/validate_script_recast_mapping_safety.mjs',
        '--cache-dir',
        cacheDir.path,
        '--source-root',
        sourceRoot.path,
        '--report',
        reportFile.path,
        '--regression-script-id',
        'script-safety',
        '--regression-frame-file',
        'story_p32.png',
        if (termReview) ...[
          '--term-review',
          termReviewFile.path,
        ],
      ],
      workingDirectory: Directory.current.path,
    );
  }

  Map<String, dynamic> readReport() {
    return jsonDecode(reportFile.readAsStringSync()) as Map<String, dynamic>;
  }

  Future<void> dispose() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  }
}

Map<String, dynamic> _completeTermMembershipReview() {
  return {
    'schema_version': 1,
    'kind': 'script_recast_term_membership_review',
    'api_used': false,
    'decisions': [
      _reviewDecision('reisa (blue archive)', 'role', 'character'),
      _reviewDecision('{{twin drills', 'role', 'upperBody'),
      _reviewDecision('crotch focus', 'exclude'),
      _reviewDecision('outdoors', 'scene', 'scene'),
    ],
  };
}

Map<String, dynamic> _reviewDecision(
  String term,
  String placement, [
  String? category,
]) {
  return {
    'term': term,
    'placement': placement,
    if (category != null) 'category': category,
  };
}

Map<String, dynamic> _promptTerm(String text, String category) {
  final id = text
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  final sourceLocation = category == 'scene' ? 'base prompt' : 'slot-0 prompt';
  return {
    'id': 'term-$id',
    'text': text,
    'category': category,
    'frame_indexes': [32],
    'source_occurrences': [
      {
        'frame_index': 32,
        'source_location': sourceLocation,
      },
    ],
  };
}

Map<String, dynamic> _termMembershipCache(
  String sourceRoot, {
  required List<Map<String, dynamic>> aiRoleTerms,
  required List<Map<String, dynamic>> mappingRoleTerms,
  String roleCaption = 'reisa (blue archive), twin drills, crotch focus',
  String roleName = 'Reisa',
  List<String> rawIdentityTags = const ['reisa_(blue_archive)', 'girl'],
  String? targetCharacterId = 'legacy-character-sheet-r14',
}) {
  final cache = _cacheFixture(
    sourceRoot: sourceRoot,
    roles: [
      {
        ..._role(
          id: 'role-reisa-blue-archive',
          name: roleName,
          rawIdentityTags: rawIdentityTags,
          sourceId: 'slot-0',
          caption: roleCaption,
        ),
        'prompt_terms': aiRoleTerms,
        'stages': [
          {
            'stage_id': 'stage-1',
            'label': 'default',
            'frame_indexes': [32],
            'identity': 'reisa (blue archive)',
            'upper_body': 'twin drills',
            'lower_body': '',
            'upper_clothing': '',
            'lower_clothing': '',
            'non_role': '',
            'non_role_materialized': true,
          },
        ],
      },
    ],
    roleSwaps: const [],
    replacements: [
      _termMembershipReplacement(
        mappingRoleTerms,
        targetCharacterId: targetCharacterId,
      ),
    ],
    assemblies: [
      _assembly(
        'role-reisa-blue-archive',
        'slot-0',
        targetCharacterId: targetCharacterId,
      ),
    ],
  );
  final snapshot = cache['scriptSnapshot'] as Map<String, dynamic>;
  final frame = (snapshot['frames'] as List).single as Map<String, dynamic>;
  final parsed = frame['parsed'] as Map<String, dynamic>;
  parsed['baseCaption'] = 'outdoors';
  parsed['charCaptions'] = [roleCaption];

  final extraction = cache['aiRoleExtraction'] as Map<String, dynamic>;
  extraction['scene_terms'] = [_promptTerm('outdoors', 'scene')];
  final mapping = cache['mapping'] as Map<String, dynamic>;
  mapping['scenePromptReplacements'] = [
    {
      'id': 'scene-ai',
      'label': 'Scene',
      'rules': [
        {
          'id': 'rule-scene-outdoors',
          'sourceTerms': [
            _mappingPromptTerm(_promptTerm('outdoors', 'scene')),
          ],
        },
      ],
    },
  ];
  return cache;
}

Map<String, dynamic> _termMembershipReplacement(
  List<Map<String, dynamic>> terms, {
  String? targetCharacterId = 'legacy-character-sheet-r14',
}) {
  return {
    'sourceRoleId': 'role-reisa-blue-archive',
    'displayLabel': 'Reisa',
    if (targetCharacterId != null) ...{
      'targetCharacterId': targetCharacterId,
      'targetIdentityPrompt': 'target_identity',
    },
    'rules': [
      for (final term in terms)
        {
          'id': 'rule-${term['id']}',
          'sourceTerms': [_mappingPromptTerm(term)],
          if (targetCharacterId != null && term['category'] == 'character') ...{
            'action': 'replace',
            'targetPrompt': 'target_identity',
          },
        },
    ],
  };
}

Map<String, dynamic> _mappingPromptTerm(Map<String, dynamic> term) {
  return {
    'id': term['id'],
    'text': term['text'],
    'category': term['category'],
    'frameIndexes': [32],
    if (term['source_occurrences'] is List)
      'sourceOccurrences': (term['source_occurrences'] as List)
          .map((occurrence) => {
                'frameIndex': occurrence['frame_index'],
                'sourceLocation': occurrence['source_location'],
              })
          .toList(),
  };
}

Map<String, dynamic> _occurrence(int frameIndex, String sourceLocation) {
  return {
    'frame_index': frameIndex,
    'source_location': sourceLocation,
  };
}

Map<String, dynamic> _promptTermWithOccurrences(
  String text,
  String category,
  List<Map<String, dynamic>> occurrences,
) {
  final term = _promptTerm(text, category);
  term['frame_indexes'] = occurrences
      .map((occurrence) => occurrence['frame_index'])
      .toSet()
      .toList();
  term['source_occurrences'] = [
    for (final occurrence in occurrences)
      _occurrence(
        occurrence['frame_index'] as int,
        occurrence['source_location'] as String,
      ),
  ];
  term['source_location'] = occurrences
      .map((occurrence) => occurrence['source_location'])
      .toSet()
      .join('; ');
  return term;
}

Map<String, dynamic> _mappingPhysicalTerm(Map<String, dynamic> term) {
  final occurrences =
      (term['source_occurrences'] as List).cast<Map<String, dynamic>>();
  return {
    'id': term['id'],
    'text': term['text'],
    'category': term['category'],
    'frameIndexes': occurrences
        .map((occurrence) => occurrence['frame_index'])
        .toSet()
        .toList(),
    'sourceLocation': occurrences
        .map((occurrence) => occurrence['source_location'])
        .toSet()
        .join('; '),
    'sourceOccurrences': [
      for (final occurrence in occurrences)
        {
          'frameIndex': occurrence['frame_index'],
          'sourceLocation': occurrence['source_location'],
        },
    ],
  };
}

Map<String, dynamic> _physicalRole({
  required String roleId,
  required String identity,
  required String sourceId,
  required List<Map<String, dynamic>> promptTerms,
}) {
  final role = _role(
    id: roleId,
    name: '$identity / girl',
    rawIdentityTags: ['${identity}_(series)', 'girl'],
    sourceId: sourceId,
    caption: '${identity}_(series), blue jacket',
  );
  role['frame_indexes'] = [32, 33];
  role['appearances'] = [
    {
      'source_id': sourceId,
      'source_kind': 'slot',
      'frame_indexes': [32, 33],
    },
  ];
  role['stages'] = [
    {
      'stage_id': 'stage-$roleId',
      'label': 'default',
      'frame_indexes': [32, 33],
      'identity': '${identity}_(series)',
      'upper_body': '',
      'lower_body': '',
      'upper_clothing': 'blue jacket',
      'lower_clothing': '',
      'non_role': '',
      'non_role_materialized': true,
    },
  ];
  role['prompt_terms'] = promptTerms;
  return role;
}

Map<String, dynamic> _physicalReplacement(
  String roleId,
  List<Map<String, dynamic>> promptTerms,
) {
  return {
    'sourceRoleId': roleId,
    'displayLabel': roleId,
    'targetCharacterId': 'legacy-character-sheet-r14',
    'targetIdentityPrompt': 'target_identity',
    'rules': [
      for (final term in promptTerms)
        {
          'id': 'rule-$roleId-${term['id']}',
          'sourceTerms': [_mappingPhysicalTerm(term)],
          if (term['category'] == 'character') ...{
            'action': 'replace',
            'targetPrompt': 'target_identity',
          },
        },
    ],
  };
}

Map<String, dynamic> _physicalAssembly(String roleId, String sourceId) {
  return {
    'sourceRoleId': roleId,
    'displayLabel': roleId,
    'sourceAppearances': [
      {
        'sourceId': sourceId,
        'sourceKind': 'slot',
        'frameIndexes': [32, 33],
      },
    ],
    'stages': [
      {
        'id': 'stage-$roleId',
        'label': 'default',
        'frameIndexes': [32, 33],
        'targetCharacterId': 'legacy-character-sheet-r14',
      },
    ],
  };
}

Map<String, dynamic> _physicalFrame(
  int frameIndex,
  List<String> charCaptions,
) {
  return {
    'index': frameIndex,
    'fileName': 'story_p$frameIndex.png',
    'parseStatus': 'parsed',
    'parsed': {
      'baseCaption': 'outdoors',
      'charCaptions': List<String>.from(charCaptions),
    },
  };
}

Map<String, dynamic> _twoFrameTwoSlotOccurrenceCache(String sourceRoot) {
  final aliceIdentity = [
    _occurrence(32, 'slot-0 prompt'),
    _occurrence(33, 'slot-0 prompt'),
  ];
  final bobIdentity = [
    _occurrence(32, 'slot-1 prompt'),
    _occurrence(33, 'slot-1 prompt'),
  ];
  final aliceTerms = [
    _promptTermWithOccurrences(
      'alice_(series)',
      'character',
      aliceIdentity,
    ),
    _promptTermWithOccurrences('blue jacket', 'upperClothing', aliceIdentity),
  ];
  final bobTerms = [
    _promptTermWithOccurrences('bob_(series)', 'character', bobIdentity),
    _promptTermWithOccurrences('blue jacket', 'upperClothing', bobIdentity),
  ];
  final sceneTerm = _promptTermWithOccurrences(
    'outdoors',
    'scene',
    [
      _occurrence(32, 'base prompt'),
      _occurrence(33, 'base prompt'),
    ],
  );
  return {
    'scriptId': 'script-safety',
    'scriptName': 'Physical occurrence fixture',
    'sourceRootPath': '$sourceRoot/story',
    'updatedAt': DateTime.utc(2026, 7, 14).toIso8601String(),
    'scriptSnapshot': {
      'frames': [
        _physicalFrame(
          32,
          const [
            'alice_(series), blue jacket',
            'bob_(series), blue jacket',
          ],
        ),
        _physicalFrame(
          33,
          const [
            'alice_(series), blue jacket',
            'bob_(series), blue jacket',
          ],
        ),
      ],
    },
    'aiRoleExtraction': {
      'status': 'ready',
      'roles': [
        _physicalRole(
          roleId: 'role-alice',
          identity: 'alice',
          sourceId: 'slot-0',
          promptTerms: aliceTerms,
        ),
        _physicalRole(
          roleId: 'role-bob',
          identity: 'bob',
          sourceId: 'slot-1',
          promptTerms: bobTerms,
        ),
      ],
      'scene_terms': [sceneTerm],
    },
    'mapping': {
      'id': 'mapping-physical-occurrences',
      'scriptId': 'script-safety',
      'roleSwaps': const [],
      'rolePromptReplacements': [
        _physicalReplacement('role-alice', aliceTerms),
        _physicalReplacement('role-bob', bobTerms),
      ],
      'roleAssemblies': [
        _physicalAssembly('role-alice', 'slot-0'),
        _physicalAssembly('role-bob', 'slot-1'),
      ],
      'scenePromptReplacements': [
        {
          'id': 'scene-ai',
          'label': 'Scene',
          'rules': [
            {
              'id': 'scene-outdoors',
              'sourceTerms': [_mappingPhysicalTerm(sceneTerm)],
            },
          ],
        },
      ],
    },
  };
}

Map<String, dynamic> _twoFrameTwoSlotReview() {
  return {
    'schema_version': 1,
    'kind': 'script_recast_term_membership_review',
    'api_used': false,
    'decisions': [
      _reviewDecision('alice_(series)', 'role', 'character'),
      _reviewDecision('bob_(series)', 'role', 'character'),
      _reviewDecision('blue jacket', 'role', 'upperClothing'),
      _reviewDecision('outdoors', 'scene', 'scene'),
    ],
  };
}

Map<String, dynamic> _crossOwnerOccurrenceCache(String sourceRoot) {
  final cache = _twoFrameTwoSlotOccurrenceCache(sourceRoot);
  final snapshot = cache['scriptSnapshot'] as Map<String, dynamic>;
  final frames = (snapshot['frames'] as List).cast<Map<String, dynamic>>();
  for (final frame in frames) {
    final parsed = frame['parsed'] as Map<String, dynamic>;
    (parsed['charCaptions'] as List)[1] = 'bob_(series)';
  }

  _removeAiRoleTerm(cache, 'role-alice', 'blue jacket');
  _removeMappingRoleTerm(cache, 'role-alice', 'blue jacket');
  final reroutedOccurrences = [
    _occurrence(32, 'slot-0 prompt'),
    _occurrence(33, 'slot-0 prompt'),
  ];
  _setOccurrences(
    _aiRoleTerm(cache, 'role-bob', 'blue jacket'),
    reroutedOccurrences,
  );
  _setOccurrences(
    _mappingRoleTerm(cache, 'role-bob', 'blue jacket'),
    reroutedOccurrences,
  );
  return cache;
}

Map<String, dynamic> _genericConcreteOmissionCache(String sourceRoot) {
  const roleCaption = 'reisa (blue archive), girl, twin drills';
  final cache = _termMembershipCache(
    sourceRoot,
    roleCaption: roleCaption,
    aiRoleTerms: [
      _promptTerm('reisa (blue archive)', 'character'),
      _promptTerm('twin drills', 'upperBody'),
    ],
    mappingRoleTerms: [
      _promptTerm('reisa (blue archive)', 'character'),
      _promptTerm('twin drills', 'upperBody'),
    ],
  );
  final snapshot = cache['scriptSnapshot'] as Map<String, dynamic>;
  final frame = (snapshot['frames'] as List).single as Map<String, dynamic>;
  final parsed = frame['parsed'] as Map<String, dynamic>;
  parsed['charCaptions'] = [roleCaption, 'girl'];

  final sharedRole = _role(
    id: 'role-shared-evidence',
    name: 'shared evidence',
    rawIdentityTags: const ['shared evidence'],
    sourceId: 'slot-1',
    caption: 'girl',
  );
  sharedRole['canonical_name'] = '';
  sharedRole['frame_indexes'] = [32];
  sharedRole['appearances'] = [
    {
      'source_id': 'slot-1',
      'source_kind': 'slot',
      'frame_indexes': [32],
    },
  ];
  sharedRole['stages'] = [
    {
      'stage_id': 'stage-shared',
      'label': 'shared',
      'frame_indexes': [32],
      'identity': '',
      'upper_body': '',
      'lower_body': '',
      'upper_clothing': '',
      'lower_clothing': '',
      'non_role': '',
      'non_role_materialized': true,
    },
  ];
  final sharedTerm = _promptTermWithOccurrences(
    'girl',
    'character',
    [_occurrence(32, 'slot-1 prompt')],
  );
  sharedRole['prompt_terms'] = [sharedTerm];

  final extraction = cache['aiRoleExtraction'] as Map<String, dynamic>;
  (extraction['roles'] as List).add(sharedRole);
  final mapping = cache['mapping'] as Map<String, dynamic>;
  (mapping['rolePromptReplacements'] as List).add({
    'sourceRoleId': 'role-shared-evidence',
    'displayLabel': 'shared evidence',
    'rules': [
      {
        'id': 'rule-shared-girl',
        'sourceTerms': [_mappingPromptTerm(sharedTerm)],
      },
    ],
  });
  (mapping['roleAssemblies'] as List).add(
    _assembly('role-shared-evidence', 'slot-1'),
  );
  return cache;
}

Map<String, dynamic> _aiRole(Map<String, dynamic> cache, String roleId) {
  final extraction = cache['aiRoleExtraction'] as Map<String, dynamic>;
  return (extraction['roles'] as List)
      .cast<Map<String, dynamic>>()
      .firstWhere((role) => role['source_role_id'] == roleId);
}

Map<String, dynamic> _aiRoleTerm(
  Map<String, dynamic> cache,
  String roleId,
  String text,
) {
  return (_aiRole(cache, roleId)['prompt_terms'] as List)
      .cast<Map<String, dynamic>>()
      .firstWhere((term) => term['text'] == text);
}

Map<String, dynamic> _mappingReplacement(
  Map<String, dynamic> cache,
  String roleId,
) {
  final mapping = cache['mapping'] as Map<String, dynamic>;
  return (mapping['rolePromptReplacements'] as List)
      .cast<Map<String, dynamic>>()
      .firstWhere((replacement) => replacement['sourceRoleId'] == roleId);
}

Map<String, dynamic> _mappingRoleTerm(
  Map<String, dynamic> cache,
  String roleId,
  String text,
) {
  final replacement = _mappingReplacement(cache, roleId);
  for (final rule
      in (replacement['rules'] as List).cast<Map<String, dynamic>>()) {
    final terms = (rule['sourceTerms'] as List).cast<Map<String, dynamic>>();
    for (final term in terms) {
      if (term['text'] == text) return term;
    }
  }
  throw StateError('Missing mapping term $roleId/$text');
}

void _removeAiRoleTerm(
  Map<String, dynamic> cache,
  String roleId,
  String text,
) {
  final terms = (_aiRole(cache, roleId)['prompt_terms'] as List)
      .cast<Map<String, dynamic>>();
  terms.removeWhere((term) => term['text'] == text);
}

void _removeMappingRoleTerm(
  Map<String, dynamic> cache,
  String roleId,
  String text,
) {
  final replacement = _mappingReplacement(cache, roleId);
  (replacement['rules'] as List).removeWhere((rawRule) {
    final rule = rawRule as Map<String, dynamic>;
    return (rule['sourceTerms'] as List)
        .cast<Map<String, dynamic>>()
        .any((term) => term['text'] == text);
  });
}

void _appendMappingRoleTerm(
  Map<String, dynamic> cache,
  String roleId,
  Map<String, dynamic> term,
) {
  final replacement = _mappingReplacement(cache, roleId);
  (replacement['rules'] as List).add({
    'id': 'rule-$roleId-${term['id']}',
    'sourceTerms': [term],
  });
}

void _setOccurrences(
  Map<String, dynamic> term,
  List<Map<String, dynamic>> occurrences,
) {
  if (term.containsKey('source_occurrences')) {
    term['source_occurrences'] = [
      for (final occurrence in occurrences)
        _occurrence(
          occurrence['frame_index'] as int,
          occurrence['source_location'] as String,
        ),
    ];
  } else {
    term['sourceOccurrences'] = [
      for (final occurrence in occurrences)
        {
          'frameIndex': occurrence['frame_index'],
          'sourceLocation': occurrence['source_location'],
        },
    ];
  }
}

void _removeOccurrence(
  Map<String, dynamic> term, {
  required int frameIndex,
  required String sourceLocation,
}) {
  final key = term.containsKey('source_occurrences')
      ? 'source_occurrences'
      : 'sourceOccurrences';
  (term[key] as List).removeWhere((raw) {
    final occurrence = raw as Map;
    return (occurrence['frame_index'] ?? occurrence['frameIndex']) ==
            frameIndex &&
        (occurrence['source_location'] ?? occurrence['sourceLocation']) ==
            sourceLocation;
  });
}

Map<String, dynamic> _cleanCache(String sourceRoot) {
  return _cacheFixture(
    sourceRoot: sourceRoot,
    roles: [
      _role(
        id: 'role-alice',
        name: 'alice / girl',
        rawIdentityTags: ['alice_(series)', 'girl'],
        sourceId: 'slot-0',
      ),
      _role(
        id: 'role-male',
        name: 'faceless male',
        rawIdentityTags: ['boy', 'faceless male'],
        sourceId: 'slot-1',
      ),
    ],
    roleSwaps: const [],
    replacements: [
      _replacement('role-alice', 'legacy-character-sheet-r14'),
      _replacement('role-male', null),
    ],
    assemblies: [
      _assembly(
        'role-alice',
        'slot-0',
        targetCharacterId: 'legacy-character-sheet-r14',
      ),
      _assembly('role-male', 'slot-1'),
    ],
  );
}

Map<String, dynamic> _badCache(String sourceRoot) {
  return _cacheFixture(
    sourceRoot: sourceRoot,
    roles: [
      {
        ..._role(
          id: 'role-girl-slot-0',
          name: 'girl',
          rawIdentityTags: ['girl'],
          sourceId: 'slot-0',
          caption: 'girl, pov hands, white gloves',
        ),
        'prompt_terms': [
          {
            'id': 'term-role-girl-slot-0',
            'text': 'girl',
            'category': 'character',
            'frame_indexes': [32],
          },
          {
            'id': 'term-uncovered-pink-hair',
            'text': 'pink hair',
            'category': 'upperBody',
            'frame_indexes': [32],
          },
        ],
      },
      _role(
        id: 'role-male',
        name: 'faceless male',
        rawIdentityTags: ['boy', 'faceless male'],
        sourceId: 'slot-1',
      ),
      _role(
        id: 'role-overlap',
        name: 'another girl',
        rawIdentityTags: ['girl'],
        sourceId: 'slot-1',
      ),
    ],
    roleSwaps: const [
      {
        'sourceRoleId': 'slot-1',
        'targetCharacterId': 'legacy-character-sheet-r13',
      },
    ],
    replacements: [
      _replacement('role-girl-slot-0', 'legacy-character-sheet-r14'),
      _replacement('role-male', 'legacy-character-sheet-r13'),
      _replacement('role-overlap', null),
    ],
    assemblies: [
      _assembly(
        'role-girl-slot-0',
        'slot-0',
        targetCharacterId: 'legacy-character-sheet-r13',
      ),
      _assembly(
        'role-male',
        'slot-1',
        targetCharacterId: 'legacy-character-sheet-r13',
      ),
      _assembly('role-overlap', 'slot-1'),
    ],
  );
}

Map<String, dynamic> _pseudoCanonicalCache(String sourceRoot) {
  return _cacheFixture(
    sourceRoot: sourceRoot,
    roles: [
      {
        ..._role(
          id: 'role-foreskin',
          name: 'foreskin',
          rawIdentityTags: ['foreskin', 'boy'],
          sourceId: 'slot-1',
          caption: 'boy, foreskin',
        ),
        'canonical_name': 'foreskin',
      },
    ],
    roleSwaps: const [],
    replacements: [_replacement('role-foreskin', null)],
    assemblies: [_assembly('role-foreskin', 'slot-1')],
  );
}

Map<String, dynamic> _objectIdentityCache(String sourceRoot) {
  return _cacheFixture(
    sourceRoot: sourceRoot,
    roles: [
      {
        ..._role(
          id: 'role-rebellion-sword',
          name: 'rebellion (sword)',
          rawIdentityTags: ['rebellion (sword)', 'boy'],
          sourceId: 'slot-1',
          caption: 'boy, goblin slayer, rebellion (sword)',
        ),
        'canonical_name': 'rebellion',
      },
    ],
    roleSwaps: const [],
    replacements: [_replacement('role-rebellion-sword', null)],
    assemblies: [_assembly('role-rebellion-sword', 'slot-1')],
  );
}

Map<String, dynamic> _franchiseObjectIdentityCache(String sourceRoot) {
  return _cacheFixture(
    sourceRoot: sourceRoot,
    roles: [
      {
        ..._role(
          id: 'role-ring-of-light-blue-archive',
          name: 'ring of light (blue archive)',
          rawIdentityTags: ['ring of light (blue archive)', 'girl'],
          sourceId: 'slot-1',
          caption: 'girl, iroha (blue archive), ring of light (blue archive)',
        ),
        'canonical_name': 'ring of light',
      },
    ],
    roleSwaps: const [],
    replacements: [_replacement('role-ring-of-light-blue-archive', null)],
    assemblies: [_assembly('role-ring-of-light-blue-archive', 'slot-1')],
  );
}

Map<String, dynamic> _cacheFixture({
  required String sourceRoot,
  required List<Map<String, dynamic>> roles,
  required List<Map<String, dynamic>> roleSwaps,
  required List<Map<String, dynamic>> replacements,
  required List<Map<String, dynamic>> assemblies,
}) {
  return {
    'scriptId': 'script-safety',
    'scriptName': 'Safety fixture',
    'sourceRootPath': '$sourceRoot/story',
    'updatedAt': DateTime.utc(2026, 7, 11).toIso8601String(),
    'scriptSnapshot': {
      'frames': [
        {
          'index': 32,
          'fileName': 'story_p32.png',
          'parseStatus': 'parsed',
          'parsed': {
            'baseCaption': '1girl, 1boy, indoors',
            'charCaptions': [
              'alice_(series), girl, red jacket',
              'boy, pov hands, holding chain',
            ],
          },
        },
      ],
    },
    'aiRoleExtraction': {
      'status': 'ready',
      'roles': roles,
    },
    'mapping': {
      'id': 'mapping-script-safety',
      'scriptId': 'script-safety',
      'roleSwaps': roleSwaps,
      'rolePromptReplacements': replacements,
      'roleAssemblies': assemblies,
    },
  };
}

Map<String, dynamic> _role({
  required String id,
  required String name,
  required List<String> rawIdentityTags,
  required String sourceId,
  String? caption,
}) {
  return {
    'source_role_id': id,
    'source_kind': 'slot',
    'display_name': name,
    'canonical_name': rawIdentityTags.first.contains('_(')
        ? rawIdentityTags.first.split('_(').first
        : '',
    'raw_identity_tags': rawIdentityTags,
    'frame_indexes': [32],
    'appearances': [
      {
        'source_id': sourceId,
        'source_kind': 'slot',
        'frame_indexes': [32],
      },
    ],
    'stages': [
      {
        'stage_id': 'stage-1',
        'label': 'default',
        'frame_indexes': [32],
        'identity': caption ?? name,
      },
    ],
    'prompt_terms': [
      {
        'id': 'term-$id',
        'text': rawIdentityTags.first,
        'category': 'character',
        'frame_indexes': [32],
      },
    ],
  };
}

Map<String, dynamic> _replacement(String roleId, String? targetId) {
  return {
    'sourceRoleId': roleId,
    'displayLabel': roleId,
    if (targetId != null) ...{
      'targetCharacterId': targetId,
      'targetIdentityPrompt': 'target_identity',
    },
    'rules': [
      {
        'id': 'rule-$roleId',
        'sourceTerms': [
          {
            'id': 'term-$roleId',
            'text': roleId,
            'category': 'character',
            'frameIndexes': [32],
          },
        ],
        if (targetId != null) ...{
          'action': 'replace',
          'targetPrompt': 'target_identity',
        },
      },
    ],
  };
}

Map<String, dynamic> _assembly(
  String roleId,
  String sourceId, {
  String? targetCharacterId,
}) {
  return {
    'sourceRoleId': roleId,
    'displayLabel': roleId,
    'sourceAppearances': [
      {
        'sourceId': sourceId,
        'sourceKind': 'slot',
        'frameIndexes': [32],
      },
    ],
    'stages': [
      {
        'id': 'stage-1',
        'label': 'default',
        'frameIndexes': [32],
        if (targetCharacterId != null) 'targetCharacterId': targetCharacterId,
      },
    ],
  };
}
