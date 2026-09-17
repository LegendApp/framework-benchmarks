import 'dart:convert';
import 'dart:io';
import 'package:highlighting/languages/all.dart';
import 'package:highlighting/src/grammar_pack.dart';
import 'package:highlighting/src/language.dart';
import 'package:highlighting/src/mode.dart';

void main(List<String> args) {
  // Include dependencies such as XML/JS/CSS embedded in fenced HTML.
  // The same original definitions are serialized without compiling their regexes.
  final selected = <String, Language>{};
  final visited = Set<Mode>.identity();
  void addLanguage(String name) {
    if (selected.containsKey(name)) return;
    final language = builtinLanguages[name];
    if (language == null) throw StateError('Missing embedded grammar $name');
    selected[name] = language;
    void visit(Mode mode) {
      if (!visited.add(mode)) return;
      for (final sub in mode.subLanguage) { addLanguage(sub); }
      for (final child in mode.contains ?? <Mode>[]) { visit(child); }
      for (final child in mode.variants ?? <Mode?>[]) { if (child != null) visit(child); }
      if (mode.starts != null) visit(mode.starts!);
      if (mode is Language) { for (final child in mode.refs.values) { visit(child); } }
    }
    visit(language);
  }
  for (final name in ['bash','c','cpp','csharp','css','go','java','javascript','json','markdown','php','python','ruby','rust','swift','typescript','xml','yaml']) { addLanguage(name); }
  File(args.single).writeAsStringSync(jsonEncode(encodeLanguages(selected)));
}
