import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_studio/data/studio/models/script_role_mapping_profile.dart';
import 'package:novel_studio/data/studio/services/role_mapping_profile_repository.dart';

void main() {
  late Directory temporaryDirectory;
  late File libraryFile;

  setUp(() async {
    temporaryDirectory =
        await Directory.systemTemp.createTemp('role-mapping-profile-test-');
    libraryFile = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}profiles.json',
    );
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('default location is application support novel_studio/global', () async {
    final repository = RoleMappingProfileRepository(
      supportDirectoryProvider: () async => temporaryDirectory,
    );

    expect(
      (await repository.resolveFile()).path,
      '${temporaryDirectory.path}${Platform.pathSeparator}novel_studio'
      '${Platform.pathSeparator}global'
      '${Platform.pathSeparator}role_mapping_profiles.json',
    );
  });

  test('missing file loads an empty library and saved data round-trips',
      () async {
    final repository = RoleMappingProfileRepository(fileOverride: libraryFile);
    expect((await repository.load()).profiles, isEmpty);

    final profile = _profile('profile-pepe', '佩佩');
    await repository.save(RoleMappingProfileLibrary(profiles: [profile]));

    final restored = await repository.load();
    expect(restored.schemaVersion, roleMappingProfileLibrarySchemaVersion);
    expect(restored.profiles.single.name, '佩佩');
  });

  test('serialized updates preserve concurrent profile additions', () async {
    final repository = RoleMappingProfileRepository(fileOverride: libraryFile);

    await Future.wait([
      repository.update(
        (current) => current.copyWith(
          profiles: [...current.profiles, _profile('profile-a', '佩佩')],
        ),
      ),
      repository.update(
        (current) => current.copyWith(
          profiles: [...current.profiles, _profile('profile-b', '百合花')],
        ),
      ),
    ]);

    final restored = await repository.load();
    expect(
      restored.profiles.map((profile) => profile.name),
      containsAll(['佩佩', '百合花']),
    );
  });

  test('duplicate names are rejected case-insensitively', () async {
    final repository = RoleMappingProfileRepository(fileOverride: libraryFile);

    await expectLater(
      repository.save(
        RoleMappingProfileLibrary(
          profiles: [
            _profile('profile-a', 'PePe'),
            _profile('profile-b', ' pepe '),
          ],
        ),
      ),
      throwsFormatException,
    );
  });

  test('malformed and newer files are not silently replaced', () async {
    final repository = RoleMappingProfileRepository(fileOverride: libraryFile);
    await libraryFile.writeAsString('{invalid');
    await expectLater(repository.load(), throwsFormatException);
    await expectLater(
      repository.save(
        RoleMappingProfileLibrary(
          profiles: [_profile('replacement', '不能覆盖')],
        ),
      ),
      throwsFormatException,
    );
    expect(await libraryFile.readAsString(), '{invalid');

    await libraryFile.writeAsString(
      jsonEncode({
        'schemaVersion': roleMappingProfileLibrarySchemaVersion + 1,
        'profiles': const [],
      }),
    );
    await expectLater(repository.load(), throwsFormatException);
    await expectLater(
      repository.save(
        RoleMappingProfileLibrary(
          profiles: [_profile('replacement', '不能降级')],
        ),
      ),
      throwsFormatException,
    );
    expect(
      jsonDecode(await libraryFile.readAsString())['schemaVersion'],
      roleMappingProfileLibrarySchemaVersion + 1,
    );
  });

  test('schema v1 blocks migrate losslessly into a legacy shared layer',
      () async {
    final repository = RoleMappingProfileRepository(fileOverride: libraryFile);
    await libraryFile.writeAsString(
      jsonEncode({
        'schemaVersion': 1,
        'profiles': [
          {
            'id': 'legacy',
            'name': '旧缓存',
            'blocks': [
              {
                'id': 'dress-block',
                'terms': [
                  {
                    'id': 'dress',
                    'text': 'black dress',
                    'normalizedKey': 'black_dress',
                  },
                ],
                'matchMode': 'any',
                'action': 'replace',
                'targetPrompt': 'white dress',
              },
            ],
            'createdAt': '2026-07-23T00:00:00.000Z',
            'updatedAt': '2026-07-23T00:00:00.000Z',
          },
        ],
      }),
    );

    final restored = await repository.load();

    expect(restored.schemaVersion, 2);
    expect(restored.profiles.single.layers, hasLength(1));
    expect(
      restored.profiles.single.layers.single.kind,
      RoleMappingProfileLayerKind.shared,
    );
    expect(restored.profiles.single.layers.single.displayName, '旧缓存');
    expect(
      restored.profiles.single.layers.single.blocks.single.targetPrompt,
      'white dress',
    );
    expect(restored.toJson()['schemaVersion'], 2);
    expect(
      (restored.toJson()['profiles'] as List).single,
      contains('layers'),
    );
  });

  test('invalid non-positive schema is rejected', () async {
    final repository = RoleMappingProfileRepository(fileOverride: libraryFile);
    await libraryFile.writeAsString(
      jsonEncode({'schemaVersion': 0, 'profiles': const []}),
    );

    await expectLater(repository.load(), throwsFormatException);
  });

  test('failed atomic commit preserves the previous valid library', () async {
    final seed = RoleMappingProfileRepository(fileOverride: libraryFile);
    await seed.save(
      RoleMappingProfileLibrary(
        profiles: [_profile('profile-old', '旧内容')],
      ),
    );
    final repository = RoleMappingProfileRepository(
      fileOverride: libraryFile,
      atomicCommitter: (_, __) async {
        throw const FileSystemException('simulated atomic commit failure');
      },
    );

    await expectLater(
      repository.save(
        RoleMappingProfileLibrary(
          profiles: [_profile('profile-new', '新内容')],
        ),
      ),
      throwsA(isA<FileSystemException>()),
    );

    final restored = await seed.load();
    expect(restored.profiles.single.name, '旧内容');
    expect(
      libraryFile.parent
          .listSync()
          .whereType<File>()
          .where((file) => file.path.contains('.tmp-')),
      isEmpty,
    );
  });
}

RoleMappingProfile _profile(String id, String name) {
  return RoleMappingProfile(
    id: id,
    name: name,
    createdAt: DateTime.utc(2026, 7, 23),
    updatedAt: DateTime.utc(2026, 7, 23),
  );
}
