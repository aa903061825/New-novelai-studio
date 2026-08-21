import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/data/studio/tools/artist_chain_v5_test_prompt.dart';

void main() {
  test('uses the canonical quality vocabulary and card identity tags', () {
    final prompt = buildArtistChainV5TestPrompt(
      artistTerms: const [
        'artist:demo',
        'artist:demo',
        '1.2::soft skin::',
      ],
      characterName: '角色甲',
      characterFrontFull: 'demo_character, animal ears',
      characterIdentityTags: const ['animal ears', 'blue eyes'],
      characterAnchorTags: const ['demo_character'],
      stripRealisticMediumTags: true,
    );

    expect(prompt, contains(artistChainV5QualityTerms));
    expect(prompt, contains('amazing quality'));
    expect(prompt, contains('absurdres'));
    expect(prompt, contains('demo_character'));
    expect(prompt, contains('blue eyes'));
    expect(prompt, contains('1.2:: soft skin ::'));
    expect(prompt, contains('upper body'));
    expect(prompt, contains('2d'));
    expect(prompt, isNot(contains('photorealistic')));
    expect(prompt, isNot(contains('3d')));
    expect(prompt, isNot(contains('adult original character')));
    expect('artist:demo'.allMatches(prompt).length, 1);
  });

  test('filters weighted realistic medium tags without dropping artist tags',
      () {
    final prompt = buildArtistChainV5TestPrompt(
      artistTerms: const [
        'artist:keep_me',
        '2:: photorealistic ::',
        '2:: 3d ::',
      ],
      characterName: '角色甲',
      characterFrontFull: 'demo_character',
      stripRealisticMediumTags: true,
    );

    expect(prompt, contains('artist:keep_me'));
    expect(prompt, isNot(contains('photorealistic')));
    expect(prompt, isNot(contains('3d')));
  });

  test('filters realistic tags embedded in a complete artist-chain prompt', () {
    final prompt = buildArtistChainV5TestPrompt(
      artistTerms: const [
        'artist:keep_me, 2:: 3d ::, 2:: photorealistic ::, glossy skin',
      ],
      characterName: '角色甲',
      characterFrontFull: 'demo_character',
      stripRealisticMediumTags: true,
    );

    expect(prompt, contains('artist:keep_me'));
    expect(prompt, contains('glossy skin'));
    expect(prompt, isNot(contains('photorealistic')));
    expect(prompt, isNot(contains('3d')));
  });

  test('detects realistic medium tags in a complete artist-chain prompt', () {
    expect(
      artistChainV5HasRealisticMediumTags(
        const ['artist:keep_me, 2:: 3d ::'],
      ),
      isTrue,
    );
    expect(
      artistChainV5HasRealisticMediumTags(const ['artist:keep_me']),
      isFalse,
    );
  });
}
