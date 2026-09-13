import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:chat_history_flutter/json_range.dart';

import 'package:chat_history_flutter/catalog.dart';
import 'package:chat_history_flutter/model.dart';
import 'package:chat_history_flutter/parser.dart';
import 'package:chat_history_flutter/parser_worker.dart';
import 'package:flutter_test/flutter_test.dart';

String fixture(String name) {
  return File(
    '${Directory.current.path}/../../packages/chat-history/tests/fixtures/$name',
  ).absolute.path;
}

void main() {
  test('validates ignored JSON values and decodes selected strings', () {
    for (final source in [r'{"skip":[1,]}', r'{"skip":"\q"}', r'{"skip":01}']) {
      final bytes = Uint8List.fromList(utf8.encode(source));
      expect(
        () => JsonRange.parse(bytes, 0, bytes.length),
        throwsFormatException,
      );
    }
    final bytes = Uint8List.fromList(
      utf8.encode(r'{"text":"a\nb","skip":[null,true]}'),
    );
    final value = JsonRange.parse(bytes, 0, bytes.length);
    expect((value.object()!['text'] as JsonRange).string(), 'a\nb');
  });

  test('subagent filtering survives a later UTF-8 boundary', () {
    final home = Directory.systemTemp.createTempSync(
      'legend-catalog-boundary-',
    );
    addTearDown(() => home.deleteSync(recursive: true));
    final root = Directory('${home.path}/.codex/sessions')
      ..createSync(recursive: true);
    final header = utf8.encode('{"payload":{"source":{"subagent":{}}}}\n');
    final source = [
      ...header,
      ...List.filled(65535 - header.length, 120),
      ...utf8.encode('é'),
    ];
    File(
      '${root.path}/rollout-2026-01-01-22222222-2222-2222-2222-222222222222.jsonl',
    ).writeAsBytesSync(source);
    expect(getRecentChats(20, home.path).summaries, isEmpty);
  });

  test('returns an empty catalog when neither provider is installed', () {
    final home = Directory.systemTemp.createTempSync(
      'legend-flutter-empty-catalog-',
    );
    addTearDown(() => home.deleteSync(recursive: true));

    expect(getRecentChats(20, home.path).summaries, isEmpty);
    expect(getRecentChats(20, '').summaries, isEmpty);
  });

  test('normalizes Codex history', () {
    final result = openChatFile(ChatProvider.codex, fixture('codex.jsonl'));

    expect(result.recordCount, 14);
    expect(result.warningCount, 2);
    expect(result.rows.map((row) => row.kind), <ChatRowKind>[
      ChatRowKind.user,
      ChatRowKind.tool,
      ChatRowKind.assistant,
      ChatRowKind.files,
    ]);
    expect(result.rows[0].markdown, 'Hello ☺\nworld\n');
    expect(result.rows[1].toolName, 'Worked for 4s');
    expect(result.rows[1].toolPreview, 'Read files, created an image');
    expect(
      result.rows[2].markdown,
      'Done **quickly**.\n\n```text\n::git-commit{example}\n```',
    );
    expect(
      result.rows[3].fileChanges.map(
        (file) => '${file.path}:${file.additions}:${file.deletions}',
      ),
      <String>[
        'apps/demo.ts:3:2',
        'packages/helper.ts:1:0',
        'packages/old.ts:0:2',
      ],
    );
    expect(normalizedContentDigest(result.rows), 'ea203684aeae72fb');
  });

  test("selects Claude's latest main chain", () {
    final result = openChatFile(ChatProvider.claude, fixture('claude.jsonl'));

    expect(result.recordCount, 8);
    expect(result.warningCount, 1);
    expect(result.rows.map((row) => row.kind), <ChatRowKind>[
      ChatRowKind.user,
      ChatRowKind.tool,
      ChatRowKind.assistant,
    ]);
    expect(result.rows[0].markdown, 'Start here');
    expect(result.rows[1].toolName, 'Worked for 3s');
    expect(result.rows[1].toolPreview, 'I will check.\n\nRead files');
    expect(result.rows[2].markdown, 'Latest answer');
    expect(result.rows[2].hasImagePlaceholder, isTrue);
    expect(normalizedContentDigest(result.rows), '4cb20d4c68d78408');
  });

  test('reads response-item user turns', () {
    final result = openChatFile(
      ChatProvider.codex,
      fixture('codex-response-user.jsonl'),
    );

    expect(
      result.rows.map((row) => <Object>[row.kind, row.markdown]),
      <List<Object>>[
        <Object>[ChatRowKind.user, 'Current-format request'],
        <Object>[ChatRowKind.assistant, 'Current-format answer'],
      ],
    );
  });

  test('reuses the parser isolate across chats', () async {
    final worker = ChatParserWorker();
    addTearDown(worker.dispose);

    final codex = await worker.parse(
      ChatProvider.codex,
      fixture('codex.jsonl'),
    );
    expect(
      codex.rows.every(
        (row) =>
            row.deferred && row.markdown.isEmpty && row.toolPreview.isEmpty,
      ),
      isTrue,
    );
    final visible = await worker.getRows(codex.documentId!, [0, 1]);
    expect(visible[0].markdown, 'Hello ☺\nworld\n');
    expect(visible[1].toolPreview, isEmpty);
    final expanded = await worker.getRows(codex.documentId!, [
      1,
    ], includeToolPreview: true);
    expect(expanded.first.toolPreview, 'Read files, created an image');
    expect(
      await worker.getContentDigest(codex.documentId!),
      'ea203684aeae72fb',
    );
    final claude = await worker.parse(
      ChatProvider.claude,
      fixture('claude.jsonl'),
    );

    await expectLater(
      worker.getRows(codex.documentId!, [0]),
      throwsFormatException,
    );
    expect(codex.rows.length, 4);
    expect(claude.rows.length, 3);
  });
}
