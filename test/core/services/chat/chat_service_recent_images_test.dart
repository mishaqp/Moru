import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:Kelivo/core/models/message_part.dart';
import 'package:Kelivo/core/services/chat/chat_service.dart';
import 'package:Kelivo/utils/sandbox_path_resolver.dart';

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this.path);

  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;

  @override
  Future<String?> getApplicationSupportPath() async => path;

  @override
  Future<String?> getApplicationCachePath() async => '$path/cache';

  @override
  Future<String?> getTemporaryPath() async => '$path/tmp';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late ChatService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('kelivo_recent_images_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
    SandboxPathResolver.debugSetDirs(
      docsDir: tempDir.path,
      supportDir: tempDir.path,
    );
    service = ChatService();
  });

  tearDown(() async {
    await service.close();
    await Hive.close();
    SandboxPathResolver.debugSetDirs(docsDir: null, supportDir: null);
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  Future<String> image(String name) async {
    final file = File('${tempDir.path}/upload/$name');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(const [1, 2, 3]);
    return file.path;
  }

  test('the newest images of one chat, newest first, capped', () async {
    await service.init();
    final chat = await service.createConversation(title: 'Photos');
    final other = await service.createConversation(title: 'Other');
    final a = await image('a.png');
    final b = await image('b.png');
    final c = await image('c.png');
    final d = await image('d.png');
    for (final path in [a, b, c, d]) {
      await service.addMessage(
        conversationId: chat.id,
        role: 'user',
        parts: [
          const TextPart('look'),
          ImagePart(uri: path, mime: 'image/png'),
        ],
      );
    }
    await service.addMessage(
      conversationId: other.id,
      role: 'user',
      parts: [ImagePart(uri: await image('z.png'), mime: 'image/png')],
    );
    await service.addMessage(
      conversationId: chat.id,
      role: 'assistant',
      content: 'no image here',
    );

    final uris = await service.recentImageUris(chat.id);
    expect(uris.length, 3);
    expect(uris.map((u) => u.split('/').last), ['d.png', 'c.png', 'b.png']);
    expect(await service.recentImageUris(other.id), hasLength(1));
    expect(await service.recentImageUris('missing'), isEmpty);
  });

  test('a chat without images, and unavailable images, give nothing', () async {
    await service.init();
    final chat = await service.createConversation(title: 'Text only');
    await service.addMessage(
      conversationId: chat.id,
      role: 'user',
      content: 'hello',
    );
    expect(await service.recentImageUris(chat.id), isEmpty);
    await service.addMessage(
      conversationId: chat.id,
      role: 'user',
      parts: [
        ImagePart(
          uri: '${tempDir.path}/upload/gone.png',
          mime: 'image/png',
          unavailable: true,
        ),
      ],
    );
    expect(await service.recentImageUris(chat.id), isEmpty);
  });

  test('the answer is kept until the chat changes, then refreshed', () async {
    await service.init();
    final chat = await service.createConversation(title: 'Photos');
    await service.addMessage(
      conversationId: chat.id,
      role: 'user',
      parts: [ImagePart(uri: await image('one.png'), mime: 'image/png')],
    );
    final first = service.recentImageUris(chat.id);
    // Asked again meanwhile, the same lookup answers.
    expect(identical(service.recentImageUris(chat.id), first), isTrue);
    expect(await first, hasLength(1));

    // A new message moves the chat's updatedAt: the answer is redone.
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await service.addMessage(
      conversationId: chat.id,
      role: 'user',
      parts: [ImagePart(uri: await image('two.png'), mime: 'image/png')],
    );
    final second = service.recentImageUris(chat.id);
    expect(identical(second, first), isFalse);
    expect((await second).map((u) => u.split('/').last), [
      'two.png',
      'one.png',
    ]);
  });
}
