import 'dart:convert';
import 'dart:io';

import 'package:chat_history_flutter/catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('benchmark samples are listed alongside machine history', () {
    final home = Directory.systemTemp.createTempSync('sample-catalog-');
    try {
      final sessions = Directory('${home.path}/.codex/sessions')
        ..createSync(recursive: true);
      File('${sessions.path}/local.jsonl').writeAsStringSync('{}\n');
      final config = File('${home.path}/benchmark.json')
        ..writeAsStringSync(
          jsonEncode({
            'samples': [
              {
                'id': 'codex:sample',
                'path': '${home.path}/sample.jsonl',
                'provider': 'codex',
                'title': 'Synthetic sample',
                'updatedAt': 4000000000000,
              },
            ],
          }),
        );
      final result = getRecentChats(
        20,
        home.path,
        benchmarkConfigPath: config.path,
      );
      expect(result.summaries.map((summary) => summary.id), [
        'codex:sample',
        'codex:local',
      ]);
      expect(result.summaries.first.title, 'Synthetic sample');
    } finally {
      home.deleteSync(recursive: true);
    }
  });
}
