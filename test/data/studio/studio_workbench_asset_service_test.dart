import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_casrand/data/models/param_config.dart';
import 'package:nai_casrand/data/models/payload_config.dart';
import 'package:nai_casrand/data/models/prompt_config.dart';
import 'package:nai_casrand/data/models/settings.dart';
import 'package:nai_casrand/data/studio/services/studio_workbench_asset_service.dart';
import 'package:nai_casrand/data/workspace/models/workspace_entities.dart';
import 'package:nai_casrand/data/workspace/workspace_service.dart';

PayloadConfig _payload({String prompt = ''}) {
  return PayloadConfig(
    rootPromptConfig: PromptConfig(strs: const [], prompts: const []),
    characterConfigList: const [],
    savedPromptConfigList: const [],
    paramConfig: ParamConfig(),
    settings: Settings.fromJson({}),
    overridePrompt: prompt,
    useOverridePrompt: prompt.isNotEmpty,
    useCharacterPromptWithOverride: false,
  );
}

void main() {
  test(
      'appendCharacter sends character traits to the editable workbench prompt',
      () {
    final payload = _payload(prompt: 'soft light');

    StudioWorkbenchAssetService(payloadConfig: payload).appendCharacter(
      const CharacterEntry(
        id: 'char-1',
        name: 'Heroine',
        traits: ViewVariantTexts(frontFull: 'blue eyes, silver hair'),
      ),
    );

    expect(payload.useOverridePrompt, isTrue);
    expect(payload.overridePrompt, 'soft light, blue eyes, silver hair');
  });

  test('appendCharacter records a reusable workbench material stack entry', () {
    final payload = _payload(prompt: 'soft light');
    final service = StudioWorkbenchAssetService(payloadConfig: payload);

    service.appendCharacter(
      const CharacterEntry(
        id: 'char-1',
        name: 'Heroine',
        traits: ViewVariantTexts(frontFull: 'blue eyes, silver hair'),
      ),
    );

    expect(service.fragments, hasLength(1));
    expect(service.fragments.single.id, isNotEmpty);
    expect(service.fragments.single.kind, StudioWorkbenchAssetKind.character);
    expect(service.fragments.single.sourceId, 'char-1');
    expect(service.fragments.single.typeLabel, '角色');
    expect(service.fragments.single.name, 'Heroine');
    expect(service.fragments.single.originalPositiveText, 'blue eyes, silver hair');
    expect(service.fragments.single.positiveText, 'blue eyes, silver hair');
    expect(service.fragments.single.prompt, 'blue eyes, silver hair');
    expect(service.fragments.single.isDirty, isFalse);
  });

  test('clearFragments removes stack fragments and restores manual prompt', () {
    final payload = _payload(prompt: 'manual base');
    final service = StudioWorkbenchAssetService(payloadConfig: payload);

    service.appendTag(
      const TagEntry(
        id: 'tag-1',
        tag: 'cinematic lighting',
        block: 'camera',
      ),
    );
    service.clearFragments();

    expect(service.fragments, isEmpty);
    expect(payload.useOverridePrompt, isTrue);
    expect(payload.overridePrompt, 'manual base');
  });

  test('clearFragments disables override prompt when stack started empty', () {
    final payload = _payload();
    final service = StudioWorkbenchAssetService(payloadConfig: payload);

    service.appendTag(
      const TagEntry(
        id: 'tag-1',
        tag: 'cinematic lighting',
        block: 'camera',
      ),
    );
    service.clearFragments();

    expect(service.fragments, isEmpty);
    expect(payload.useOverridePrompt, isFalse);
    expect(payload.overridePrompt, isEmpty);
  });

  test('appendOutfit sends outfit tags to the editable workbench prompt', () {
    final payload = _payload();

    StudioWorkbenchAssetService(payloadConfig: payload).appendOutfit(
      const CharacterEntry(
        id: 'char-1',
        name: 'Heroine',
        traits: ViewVariantTexts(frontFull: 'silver hair'),
      ),
      const WorkspaceOutfit(
        id: 'outfit-1',
        name: 'Rain Coat',
        tags: ViewVariantTexts(frontFull: 'yellow rain coat, rubber boots'),
      ),
    );

    expect(payload.useOverridePrompt, isTrue);
    expect(payload.overridePrompt, 'yellow rain coat, rubber boots');
  });

  test('saveBack persists an edited tag only after explicit save', () async {
    final tempDir = await Directory.systemTemp.createTemp('workbench-save-tag-');
    addTearDown(() => tempDir.delete(recursive: true));
    final workspace = WorkspaceService();
    await workspace.createWorkspace(tempDir.path);
    await workspace.saveTags('camera', const [
      TagEntry(id: 'tag-1', tag: 'cinematic lighting', block: 'camera'),
    ]);
    final service = StudioWorkbenchAssetService(
      payloadConfig: _payload(),
      workspaceService: workspace,
    );

    service.appendTag(
      const TagEntry(id: 'tag-1', tag: 'cinematic lighting', block: 'camera'),
    );
    service.updatePositiveText(service.fragments.single.id, 'golden rim light');

    expect((await workspace.loadTags('camera')).single.tag, 'cinematic lighting');

    await service.saveBack(service.fragments.single.id);

    expect((await workspace.loadTags('camera')).single.tag, 'golden rim light');
    expect(service.fragments.single.isDirty, isFalse);
  });

  test('saveBack persists a nested outfit when parent identity is known',
      () async {
    final tempDir =
        await Directory.systemTemp.createTemp('workbench-save-outfit-');
    addTearDown(() => tempDir.delete(recursive: true));
    final workspace = WorkspaceService();
    await workspace.createWorkspace(tempDir.path);
    const character = CharacterEntry(
      id: 'char-1',
      name: 'Heroine',
      traits: ViewVariantTexts(frontFull: 'silver hair'),
      outfits: [
        WorkspaceOutfit(
          id: 'outfit-1',
          name: 'Rain Coat',
          tags: ViewVariantTexts(frontFull: 'yellow rain coat'),
        ),
      ],
    );
    await workspace.saveCharacters([character]);
    final service = StudioWorkbenchAssetService(
      payloadConfig: _payload(),
      workspaceService: workspace,
    );

    service.appendOutfit(character, character.outfits.single);
    service.updatePositiveText(service.fragments.single.id, 'red rain coat');
    await service.saveBack(service.fragments.single.id);

    expect(
      (await workspace.loadCharacters()).single.outfits.single.tags.frontFull,
      'red rain coat',
    );
    expect(service.fragments.single.isDirty, isFalse);
  });

  test('appendArtistChain prefers explicit prompt and falls back to tags', () {
    final payload = _payload();
    final service = StudioWorkbenchAssetService(payloadConfig: payload);

    service.appendArtistChain(
      const ArtistChain(
        id: 'artist-1',
        name: 'Painter',
        prompt: 'watercolor wash',
        tags: ['unused tag'],
      ),
    );

    expect(payload.overridePrompt, 'watercolor wash');
  });

  test('appendRecipe and appendTag add reusable fragments in order', () {
    final payload = _payload(prompt: '1girl');
    final service = StudioWorkbenchAssetService(payloadConfig: payload);

    service.appendRecipe(
      const Recipe(
        id: 'recipe-1',
        name: 'Rain Street',
        block: 'scene',
        tags: 'rainy street, wet pavement',
      ),
    );
    service.appendTag(
      const TagEntry(
        id: 'tag-1',
        tag: 'cinematic lighting',
        block: 'camera',
      ),
    );

    expect(
      payload.overridePrompt,
      '1girl, rainy street, wet pavement, cinematic lighting',
    );
  });

  test('appendRecipe can use variant values when tags are empty', () {
    final payload = _payload();

    StudioWorkbenchAssetService(payloadConfig: payload).appendRecipe(
      const Recipe(
        id: 'recipe-1',
        name: 'Outfit',
        block: 'clothing',
        variants: {'front': 'white dress', 'detail': 'lace trim'},
      ),
    );

    expect(payload.overridePrompt, 'white dress, lace trim');
  });

  test('editing and ordering workbench blocks recomposes override prompt', () {
    final payload = _payload(prompt: 'manual base');
    final service = StudioWorkbenchAssetService(payloadConfig: payload);

    service.appendTag(
      const TagEntry(
        id: 'tag-1',
        tag: 'cinematic lighting',
        block: 'camera',
      ),
    );
    service.appendRecipe(
      const Recipe(
        id: 'recipe-1',
        name: 'Rain Street',
        block: 'scene',
        tags: 'wet pavement',
      ),
    );

    final tag = service.fragments.first;
    final recipe = service.fragments.last;
    service.updatePositiveText(tag.id, 'golden hour lighting');
    service.moveFragment(recipe.id, 0);

    expect(
      service.fragments.map((fragment) => fragment.name),
      ['Rain Street', 'cinematic lighting'],
    );
    expect(tag.isDirty, isTrue);
    expect(tag.sourceBlock, 'camera');
    expect(recipe.sourceBlock, 'scene');
    expect(payload.overridePrompt, 'manual base, wet pavement, golden hour lighting');
  });

  test('manual prompt and negative prompt stay in the payload path', () {
    final payload = _payload(prompt: ' old manual ');
    final service = StudioWorkbenchAssetService(payloadConfig: payload);

    expect(service.manualPositivePrompt, 'old manual');
    expect(service.manualNegativePrompt, payload.paramConfig.negativePrompt);

    service.setManualPositivePrompt('new manual');
    service.setManualNegativePrompt('bad anatomy');

    expect(service.manualPositivePrompt, 'new manual');
    expect(service.manualNegativePrompt, 'bad anatomy');
    expect(payload.overridePrompt, 'new manual');
    expect(payload.useOverridePrompt, isTrue);
    expect(payload.paramConfig.negativePrompt, 'bad anatomy');
  });

  test('removing the last block preserves manual prompt text', () {
    final payload = _payload(prompt: 'manual base');
    final service = StudioWorkbenchAssetService(payloadConfig: payload);

    service.appendCharacter(
      const CharacterEntry(
        id: 'char-1',
        name: 'Heroine',
        traits: ViewVariantTexts(frontFull: 'silver hair'),
      ),
    );

    service.removeFragment(service.fragments.single.id);

    expect(service.fragments, isEmpty);
    expect(payload.overridePrompt, 'manual base');
  });
}
