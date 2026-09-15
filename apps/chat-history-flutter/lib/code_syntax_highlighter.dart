import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:highlighting/highlighting.dart' as hl;

const codeLanguages = <String, String>{
  "bash": "bash",
  "c": "c",
  "cc": "cpp",
  "cpp": "cpp",
  "cs": "csharp",
  "csharp": "csharp",
  "css": "css",
  "cxx": "cpp",
  "go": "go",
  "golang": "go",
  "html": "xml",
  "java": "java",
  "javascript": "javascript",
  "js": "javascript",
  "json": "json",
  "jsx": "javascript",
  "markdown": "markdown",
  "md": "markdown",
  "php": "php",
  "py": "python",
  "python": "python",
  "rb": "ruby",
  "rs": "rust",
  "ruby": "ruby",
  "rust": "rust",
  "sh": "bash",
  "shell": "bash",
  "swift": "swift",
  "ts": "typescript",
  "tsx": "typescript",
  "typescript": "typescript",
  "yaml": "yaml",
  "yml": "yaml",
  "zsh": "bash",
};
const _colors = <String, Color>{
  'keyword': Color(0xffff7b72),
  'type': Color(0xffff7b72),
  'string': Color(0xffa5d6ff),
  'regexp': Color(0xffa5d6ff),
  'number': Color(0xff79c0ff),
  'literal': Color(0xff79c0ff),
  'attr': Color(0xff79c0ff),
  'attribute': Color(0xff79c0ff),
  'comment': Color(0xff8b949e),
  'title': Color(0xffd2a8ff),
  'built_in': Color(0xffffa657),
  'symbol': Color(0xffffa657),
  'section': Color(0xffd2a8ff),
  'code': Color(0xffa5d6ff),
  'name': Color(0xff7ee787),
  'selector-tag': Color(0xff7ee787),
};

TextSpan highlightCode(String source, String fence) {
  final language = codeLanguages[fence.toLowerCase()];
  if (language == null ||
      utf8.encode(source).length > 51200 ||
      '\n'.allMatches(source).length + 1 > 2000) {
    return TextSpan(text: source);
  }
  TextSpan span(hl.Node node) {
    // highlight.js scopes such as title.function inherit their base token color.
    final color = _colors[node.className?.split('.').first];
    return TextSpan(
      text: node.value,
      style: color == null ? null : TextStyle(color: color),
      children: node.children.map(span).toList(),
    );
  }
  return TextSpan(
    children: hl.highlight
        .parse(source, languageId: language)
        .nodes
        ?.map(span)
        .toList(),
  );
}

// Match RN without stripping significant spaces or tabs from code.
String codePaneSource(String source) => source.replaceFirst(RegExp(r'\n+$'), '');
