import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:highlighting/languages/all.dart';
import 'package:highlighting/src/grammar_pack.dart';
import 'package:highlighting/src/highlightv2.dart' show HighlightV2;

void main() {
  test('External rules preserve original token trees for every fixture', () {
    final fixtures = jsonDecode(File('../../benchmarks/chat-history/syntax-highlighting-fixtures.json').readAsStringSync()) as List;
    final original = HighlightV2();
    for (final language in builtinLanguages.values) { original.registerLanguage(language); }
    final external = HighlightV2();
    final pack = jsonDecode(File('../../.build/chat-history-benchmarks/grammar-packs/v1/dart-highlighting/grammars.json').readAsStringSync()) as Map<String, dynamic>;
    for (final language in decodeLanguages(pack).values) { external.registerLanguage(language); }
    final policy = jsonDecode(File('../../benchmarks/chat-history/syntax-highlighting-policy.json').readAsStringSync());
    dynamic tree(dynamic node) => [node.className, node.value, node.children.map(tree).toList()];
    for (final fixture in fixtures) {
      final language = policy['languages'][fixture['language']];
      final source = fixture['source'] as String;
      expect(external.parse(source, languageId: language).nodes?.map(tree).toList(), original.parse(source, languageId: language).nodes?.map(tree).toList(), reason: fixture['language']);
    }
  });
}
