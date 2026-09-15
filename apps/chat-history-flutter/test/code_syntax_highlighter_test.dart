import 'dart:convert';
import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chat_history_flutter/code_syntax_highlighter.dart';

bool colored(InlineSpan span) =>
    span.style?.color != null ||
    (span is TextSpan && (span.children?.any(colored) ?? false));
void main() {
  test('code panes match RN terminal-newline normalization', () {
    expect(codePaneSource('let x = 1;  \n\n'), 'let x = 1;  ');
    expect(codePaneSource('\n  \t\n'), '\n  \t');
    expect(codePaneSource('a\n\nb\n'), 'a\n\nb');
    expect(codePaneSource('\n\n'), '');
  });
  test('nested function scopes retain the function color', () {
    final result = highlightCode('function greet() { return 42; }', 'js');
    bool hasFunctionColor(InlineSpan span) => span.style?.color == const Color(0xffd2a8ff) ||
        (span is TextSpan && (span.children?.any(hasFunctionColor) ?? false));
    expect(hasFunctionColor(result), isTrue);
  });
  test('all RN languages preserve Unicode and emit tokens', () {
    final fixtures = jsonDecode(
      File('../../benchmarks/chat-history/syntax-highlighting-fixtures.json')
          .readAsStringSync(),
    ) as List;
    for (final fixture in fixtures) {
      final result = highlightCode(fixture['source'], fixture['language']);
      expect(
        result.toPlainText(),
        fixture['source'],
        reason: fixture['language'],
      );
      expect(colored(result), isTrue, reason: fixture['language']);
    }
  });
  test('plain fallback preserves complete code at the RN limits', () {
    for (final source in ['😀' * 12801, 'a' * 51201, '\n' * 2000]) {
      final result = highlightCode(source, 'js');
      expect(result.toPlainText(), source);
      expect(colored(result), isFalse);
    }
    expect(colored(highlightCode('const x = 42;', 'unknown')), isFalse);
  });
}
