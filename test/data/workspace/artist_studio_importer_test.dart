import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/workspace/importers/artist_studio_importer.dart';

void main() {
  late Directory root;
  late Directory studioDir;

  setUp(() async {
    root =
        await Directory.systemTemp.createTemp('artist-studio-importer-test-');
    studioDir = Directory('${root.path}/artist_studio_app');
    final dataDir = Directory('${root.path}/artist_studio_data/data');
    await studioDir.create(recursive: true);
    await dataDir.create(recursive: true);
    await File('${dataDir.path}/data.json').writeAsString(
      jsonEncode({
        'artists': [
          {
            'id': 'artist-1',
            'name': 'Soft Painter',
            'tags': ['soft color', 'pastel'],
            'prompt': 'artist:soft painter',
            'images': ['images/a.png'],
          },
        ],
        'characters': [
          {
            'id': 'char-1',
            'name': 'Muse',
            'features': 'green eyes',
            'images': ['images/c.png'],
            'outfit': {'top': 'white blouse', 'bottom': 'blue skirt'},
            'presets': [
              {
                'name': 'Festival',
                'outfit': {'all': 'white dress'},
              },
            ],
            'activePresetIdx': 0,
            'notes': 'import me',
          },
        ],
      }),
    );
    await File('${root.path}/nai_unified_config.json').writeAsString(
      jsonEncode({
        'strong_filter_keywords': 'mosaic,censor',
        'openai_api_key': 'pst-filter-secret',
        'assistant_url': 'https://ai.local/v1',
      }),
    );
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  test('imports artist chains, characters, and filter rules', () async {
    final result = await ArtistStudioImporter().importDataRoot(studioDir.path);

    expect(result.artistChains.single.name, 'Soft Painter');
    expect(result.artistChains.single.prompt, 'artist:soft painter');
    expect(result.artistChains.single.imageRefs, ['images/a.png']);
    expect(result.characters.single.traits.frontFull, 'green eyes');
    expect(result.characters.single.outfits.first.tags.frontFull,
        contains('white blouse'));
    expect(result.characters.single.outfits.first.tags.frontFull,
        contains('blue skirt'));
    expect(result.characters.single.outfits.last.name, 'Festival');
    expect(result.characters.single.outfits.last.tags.frontFull, 'white dress');
    expect(result.characters.single.defaultOutfitId, 'char-1-preset-0');
    expect(result.filterRules['strong_filter_keywords'], 'mosaic,censor');
    expect(result.filterRules.containsKey('openai_api_key'), isFalse);
    expect(result.filterRules.containsKey('assistant_url'), isFalse);
  });

  test('sanitizes artist studio prompts and private outfit parts', () async {
    await File('${root.path}/artist_studio_data/data/data.json').writeAsString(
      jsonEncode({
        'artists': [
          {
            'id': 'artist-1',
            'name': 'Soft Painter',
            'tags': ['soft color', 'pst-artist-tag-secret'],
            'prompt': 'Bearer artist-prompt-secret',
            'notes': 'api_key pst-artist-note-secret',
          },
        ],
        'characters': [
          {
            'id': 'char-1',
            'name': 'Muse',
            'features': 'green eyes',
            'outfit': {
              'top': 'white blouse',
              'private': 'pst-private-outfit',
            },
          },
        ],
      }),
    );

    final result = await ArtistStudioImporter().importDataRoot(studioDir.path);
    final artistJson = jsonEncode(result.artistChains.single.toJson());
    final characterJson = jsonEncode(result.characters.single.toJson());

    expect(result.artistChains.single.toJson()['tags'], ['soft color']);
    expect(artistJson, isNot(contains('pst-artist-tag-secret')));
    expect(artistJson, isNot(contains('Bearer artist-prompt-secret')));
    expect(artistJson, isNot(contains('pst-artist-note-secret')));
    expect(characterJson, contains('white blouse'));
    expect(characterJson, isNot(contains('pst-private-outfit')));
  });
}
