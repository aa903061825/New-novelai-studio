import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/workspace/importers/kamia_importer.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('kamia-importer-test-');
    await Directory('${root.path}/data/recipes').create(recursive: true);
    await Directory('${root.path}/data/tags').create(recursive: true);
    await Directory('${root.path}/data/workflows').create(recursive: true);
    await Directory('${root.path}/data/batch_plans').create(recursive: true);
    await Directory('${root.path}/data/assembly_presets').create(recursive: true);
    await File('${root.path}/data/recipes/style.json').writeAsString(
      jsonEncode([
        {
          'id': 'style-1',
          'name': 'Quality',
          'block': 'style',
          'category': 'base',
          'group': 'quality',
          'tags': 'masterpiece',
          'tags_front_full': 'masterpiece, best quality',
          'tags_private': 'pst-kamia-private-block',
          'image': 'images/style.png',
          'note': 'Bearer kamia-note-secret',
        },
      ]),
    );
    await File('${root.path}/data/tags/style.json').writeAsString(
      jsonEncode([
        {
          'tag': 'masterpiece',
          'name_zh': 'masterpiece zh',
          'block': 'style',
          'category': 'quality',
          'image': 'images/tag.png',
        },
      ]),
    );
    await File('${root.path}/data/characters.json').writeAsString(
      jsonEncode([
        {
          'id': 'char-1',
          'name': 'Heroine',
          'preview_image': 'images/heroine.png',
          'traits': {'front_full': 'blue eyes'},
          'outfits': [
            {
              'id': 'outfit-1',
              'name': 'Uniform',
              'preview_image': 'images/uniform.png',
              'tags': {'front_full': 'school uniform'},
            },
          ],
          'default_outfit': 'outfit-1',
        },
      ]),
    );
    await File('${root.path}/data/inspirations.json').writeAsString(
      jsonEncode([
        {
          'id': 'insp-1',
          'name': 'Night Alley',
          'prompt': 'rainy alley, neon puddles',
          'image': 'images/inspiration.png',
          'tags': ['rain', 'city'],
        },
      ]),
    );
    await File('${root.path}/data/loras.json').writeAsString(
      jsonEncode([
        {
          'id': 'lora-1',
          'name': 'SoftRain',
          'base_model': 'nai-diffusion-4',
          'trigger_words': ['softrain', 'mist'],
          'weight': 0.65,
          'preview_image': 'images/lora.png',
        },
      ]),
    );
    await File('${root.path}/data/workflows/city_stack.json').writeAsString(
      jsonEncode({
        'id': 'workflow-1',
        'name': 'City Stack',
        'summary': 'Comfy city workflow',
        'graph': {'nodes': 4},
      }),
    );
    await File('${root.path}/data/batch_plans/night_queue.json').writeAsString(
      jsonEncode({
        'id': 'batch-1',
        'name': 'Night Queue',
        'items': [
          {'recipe': 'style-1'},
        ],
      }),
    );
    await File(
      '${root.path}/data/assembly_presets/city_assembly.json',
    ).writeAsString(
      jsonEncode({
        'id': 'assembly-1',
        'name': 'City Assembly',
        'summary': 'Reusable city assembly',
        'payload': {'blocks': ['style', 'scene']},
      }),
    );
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  test('imports recipes, tags, and characters from KAMIA data folder',
      () async {
    final result = await KamiaImporter().importProject(root.path);

    expect(result.recipes['style']!.single.id, 'style-1');
    expect(result.recipes['style']!.single.tags, 'masterpiece');
    expect(
      result.recipes['style']!.single.variants['front_full'],
      'masterpiece, best quality',
    );
    expect(result.recipes['style']!.single.imageRefs, ['images/style.png']);
    expect(result.tags['style']!.single.zh, 'masterpiece zh');
    expect(result.tags['style']!.single.imageRefs, ['images/tag.png']);
    expect(result.characters.single.name, 'Heroine');
    expect(result.characters.single.traits.frontFull, 'blue eyes');
    expect(result.characters.single.imageRefs, ['images/heroine.png']);
    expect(result.characters.single.defaultOutfitId, 'outfit-1');
    expect(result.characters.single.outfits.single.tags.frontFull,
        'school uniform');
    expect(result.characters.single.outfits.single.imageRefs,
        ['images/uniform.png']);
  });

  test('sanitizes private KAMIA blocks before workspace serialization',
      () async {
    final result = await KamiaImporter().importProject(root.path);
    final recipeJson = result.recipes['style']!.single.toJson();
    final encoded = jsonEncode(recipeJson);

    expect((recipeJson['variants'] as Map).containsKey('private'), isFalse);
    expect(encoded, isNot(contains('pst-kamia-private-block')));
    expect(encoded, isNot(contains('Bearer kamia-note-secret')));
  });

  test('imports non-basic KAMIA assets for catalog indexing', () async {
    final result = await KamiaImporter().importProject(root.path);

    expect(result.inspirations.single.name, 'Night Alley');
    expect(result.inspirations.single.prompt, 'rainy alley, neon puddles');
    expect(result.loras.single.triggerWords, ['softrain', 'mist']);
    expect(result.loras.single.defaultStrength, 0.65);
    expect(result.workflows.single.name, 'City Stack');
    expect(result.workflows.single.payload['graph'], {'nodes': 4});
    expect(result.batchPlans.single.name, 'Night Queue');
    expect(result.batchPlans.single.items.single['recipe'], 'style-1');
    expect(result.assemblyPresets.single.name, 'City Assembly');
    expect(
      result.assemblyPresets.single.payload['payload'],
      {'blocks': ['style', 'scene']},
    );
  });
}
