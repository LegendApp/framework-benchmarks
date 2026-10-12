import 'dart:convert';
import 'dart:io';

import 'package:chat_history_flutter/file_source.dart';
import 'package:chat_history_flutter/json_range.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('file ranges preserve Unicode across blocks and after eviction', () {
    final dir = Directory.systemTemp.createTempSync('chat-file-source-');
    final value = '${'x' * 65524}🌍\\\n${'z' * 700000}';
    final file = File('${dir.path}/source')
      ..writeAsStringSync(jsonEncode({'text': value}));
    final source = FileSource(file.path);
    try {
      final range =
          JsonRange.parse(source, 0, source.length).object()!['text']
              as JsonRange;
      expect(range.string(), value);
      expect(source[source.length - 1], 125);
      expect(range.string(), value);
      source.close();
      expect(() => range.string(), throwsStateError);
    } finally {
      source.close();
      dir.deleteSync(recursive: true);
    }
  });
  test('empty files and truncated unread ranges are handled', () {
    final dir = Directory.systemTemp.createTempSync('chat-file-source-');
    final file = File('${dir.path}/source')..writeAsStringSync('');
    final empty = FileSource(file.path);
    expect(empty.length, 0);
    empty.close();
    file.writeAsStringSync('x' * 70000);
    final source = FileSource(file.path);
    try {
      file.writeAsStringSync('');
      expect(() => source[65536], throwsA(isA<FileSystemException>()));
    } finally {
      source.close();
      dir.deleteSync(recursive: true);
    }
  });
}
