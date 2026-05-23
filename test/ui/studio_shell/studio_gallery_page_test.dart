import 'package:flutter/material.dart';
import 'package:flutter_command/flutter_command.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:nai_casrand/data/models/command_status.dart';
import 'package:nai_casrand/data/models/info_card_content.dart';
import 'package:nai_casrand/data/models/param_config.dart';
import 'package:nai_casrand/data/models/payload_config.dart';
import 'package:nai_casrand/data/models/prompt_config.dart';
import 'package:nai_casrand/data/models/settings.dart';
import 'package:nai_casrand/data/studio/models/studio_gallery_record.dart';
import 'package:nai_casrand/data/studio/services/studio_gallery_service.dart';
import 'package:nai_casrand/data/workspace/workspace_service.dart';
import 'package:nai_casrand/ui/generation_page/view_models/generation_page_viewmodel.dart';
import 'package:nai_casrand/ui/studio_core/theme/studio_theme.dart';
import 'package:nai_casrand/ui/studio_shell/widgets/studio_gallery_page.dart';

PayloadConfig _payload({String prompt = ''}) {
  return PayloadConfig(
    rootPromptConfig: PromptConfig(strs: [prompt], prompts: const []),
    characterConfigList: const [],
    savedPromptConfigList: const [],
    paramConfig: ParamConfig(),
    settings: Settings.fromJson({}),
    overridePrompt: prompt,
    useOverridePrompt: prompt.isNotEmpty,
    useCharacterPromptWithOverride: false,
  );
}

class _FakeGalleryService extends StudioGalleryService {
  _FakeGalleryService(this.records)
      : super(workspaceService: WorkspaceService());

  final List<StudioGalleryRecord> records;
  final List<String> restoredIds = [];

  @override
  Future<List<StudioGalleryRecord>> loadRecords() async {
    return records;
  }

  @override
  void restoreToWorkbench(
    StudioGalleryRecord record,
    PayloadConfig target,
  ) {
    restoredIds.add(record.id);
    record.restoreTo(target);
  }
}

StudioGalleryRecord _record({
  required String id,
  required String prompt,
  required String title,
  String? imagePath,
  String? info,
  Map<String, dynamic> additionalInfo = const {},
}) {
  return StudioGalleryRecord.fromPayloadConfig(
    config: _payload(prompt: prompt),
    id: id,
    createdAt: DateTime.parse('2026-05-22T08:00:00Z'),
    title: title,
    imagePath: imagePath,
    info: info ?? prompt,
    additionalInfo: additionalInfo,
  );
}

void main() {
  setUp(() async {
    await GetIt.I.reset();
    GetIt.I.registerSingleton<PayloadConfig>(_payload());
    GetIt.I.registerSingleton<CommandStatus>(CommandStatus());
  });

  tearDown(() async {
    await GetIt.I.reset();
  });

  testWidgets('gallery page reflects current generated result count',
      (tester) async {
    final commandStatus = GetIt.I<CommandStatus>();
    commandStatus.commandList.add(
      Command.createSyncNoParam<InfoCardContent>(
        () => const InfoCardContent(
          title: 'one',
          info: 'ok',
          additionalInfo: {},
        ),
        initialValue: const InfoCardContent(
          title: 'one',
          info: 'ok',
          additionalInfo: {},
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: StudioTheme.build(),
        home: StudioGalleryPage(
          viewModel: GenerationPageViewmodel(),
          galleryService: _FakeGalleryService(const []),
          payloadConfig: GetIt.I<PayloadConfig>(),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('gallery-header-title')), findsOneWidget);
    expect(find.byKey(const ValueKey('gallery-session-metric')), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('gallery page restores a saved record to the workbench',
      (tester) async {
    final payload = GetIt.I<PayloadConfig>();
    final record = _record(
      id: 'record-1',
      prompt: 'gallery prompt',
      title: 'favorite.png',
      info: 'gallery prompt',
      additionalInfo: const {'seed': 777},
    );
    final galleryService = _FakeGalleryService([record]);

    await tester.pumpWidget(
      MaterialApp(
        theme: StudioTheme.build(),
        home: StudioGalleryPage(
          viewModel: GenerationPageViewmodel(),
          galleryService: galleryService,
          payloadConfig: payload,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('favorite.png'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('gallery-card-restore-record-1')));
    await tester.pump();

    expect(galleryService.restoredIds, ['record-1']);
    expect(payload.overridePrompt, 'gallery prompt');
  });

  testWidgets('gallery page filters by search and metadata status',
      (tester) async {
    final records = [
      _record(
        id: 'parsed-1',
        prompt: 'city prompt',
        title: 'city-night.png',
        additionalInfo: const {
          'seed': 12983122,
          'model': 'NAI Diffusion',
        },
      ),
      _record(
        id: 'missing-1',
        prompt: 'fallback prompt',
        title: 'fallback.png',
        imagePath: r'C:\outputs\fallback.png',
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: StudioTheme.build(),
        home: StudioGalleryPage(
          viewModel: GenerationPageViewmodel(),
          galleryService: _FakeGalleryService(records),
          payloadConfig: GetIt.I<PayloadConfig>(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('gallery-card-parsed-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('gallery-card-missing-1')), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('gallery-search')),
      'city',
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('gallery-card-parsed-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('gallery-card-missing-1')), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('gallery-search')),
      '',
    );
    await tester.tap(find.byKey(const ValueKey('gallery-filter-missing')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('gallery-card-parsed-1')), findsNothing);
    expect(find.byKey(const ValueKey('gallery-card-missing-1')), findsOneWidget);
  });

  testWidgets('gallery page shows detail drawer and fallback file info',
      (tester) async {
    final payload = GetIt.I<PayloadConfig>();
    final records = [
      _record(
        id: 'parsed-1',
        prompt: 'gallery prompt',
        title: 'city-night.png',
        additionalInfo: const {
          'seed': 12983122,
          'sampler': 'k_euler',
        },
      ),
      _record(
        id: 'missing-1',
        prompt: 'fallback prompt',
        title: 'fallback.png',
        imagePath: r'C:\outputs\fallback.png',
      ),
    ];
    final galleryService = _FakeGalleryService(records);

    await tester.pumpWidget(
      MaterialApp(
        theme: StudioTheme.build(),
        home: StudioGalleryPage(
          viewModel: GenerationPageViewmodel(),
          galleryService: galleryService,
          payloadConfig: payload,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('gallery-card-parsed-1')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('gallery-detail-drawer')),
      findsOneWidget,
    );
    expect(find.text('12983122'), findsOneWidget);
    expect(find.text('k_euler'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('gallery-card-missing-1')));
    await tester.pumpAndSettle();

    expect(find.text(r'C:\outputs\fallback.png'), findsWidgets);

    final restoreButton = find.byKey(const ValueKey('gallery-detail-restore'));
    await tester.ensureVisible(restoreButton);
    await tester.tap(restoreButton);
    await tester.pump();

    expect(galleryService.restoredIds, ['missing-1']);
    expect(payload.overridePrompt, 'fallback prompt');
  });
}
