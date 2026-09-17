import 'callbacks.dart';
import 'language.dart';
import 'mode.dart';

final _callbacks = {
  'endSameAsBeginOnBegin': endSameAsBeginOnBegin,
  'endSameAsBeginOnEnd': endSameAsBeginOnEnd,
  'shebangOnBegin': shebangOnBegin,
  'language_javascript_contains_0_contains_0_variants_0_onBegin': language_javascript_contains_0_contains_0_variants_0_onBegin,
  'language_undefined_contains_0_contains_0_contains_0_variants_0_onBegin': language_undefined_contains_0_contains_0_contains_0_variants_0_onBegin,
};

/// Serializes uncompiled definitions, preserving shared mode identity and references.
/// Regex compilation and highlighting remain runtime work.
Map<String, dynamic> encodeLanguages(Map<String, Language> languages) {
  final ids = Map<Mode, int>.identity();
  final nodes = <Map<String, dynamic>>[];
  dynamic encode(dynamic value) {
    if (value is Mode) {
      if (ids.containsKey(value)) return {'mode': ids[value]};
      final id = nodes.length;
      ids[value] = id;
      final node = <String, dynamic>{};
      nodes.add(node);
      if (value is ModeReference) { node['ref'] = value.ref; }
      else if (value is ModeSelfReference) { node['self'] = true; }
      else {
        if (value.isCompiled || value.compiled == true) throw StateError('Cannot export compiled grammar');
        node['keywords'] = encode(value.keywords);
        node['illegal'] = encode(value.illegal);
        node['begin'] = encode(value.begin);
        node['beginKeywords'] = encode(value.beginKeywords);
        node['end'] = encode(value.end);
        node['lexemes'] = encode(value.lexemes);
        node['endSameAsBegin'] = encode(value.endSameAsBegin);
        node['endsParent'] = encode(value.endsParent);
        node['endsWithParent'] = encode(value.endsWithParent);
        node['relevance'] = encode(value.relevance);
        node['data'] = encode(value.data);
        node['beforeBegin'] = encode(value.beforeBegin);
        node['excludeBegin'] = encode(value.excludeBegin);
        node['excludeEnd'] = encode(value.excludeEnd);
        node['skip'] = encode(value.skip);
        node['returnBegin'] = encode(value.returnBegin);
        node['returnEnd'] = encode(value.returnEnd);
        node['match'] = encode(value.match);
        node['beforeMatch'] = encode(value.beforeMatch);
        node['beginScope'] = encode(value.beginScope);
        node['label'] = encode(value.label);
        node['endScope'] = encode(value.endScope);
        node['binary'] = encode(value.binary);
        node['className'] = encode(value.getRawClassName());
        node['scope'] = encode(value.getRawScope());
        node['contains'] = encode(value.contains);
        node['variants'] = encode(value.variants);
        node['starts'] = encode(value.starts);
        node['subLanguage'] = value.subLanguage;
        for (final entry in {'onBegin': value.onBegin, 'onEnd': value.onEnd}.entries) {
          if (entry.value != null) node[entry.key] = _callbacks.entries.singleWhere((e) => e.value == entry.value).key;
        }
        if (value is Language) {
          if (value.compilerExtensions.isNotEmpty) throw StateError('Unsupported compiler extension');
          node['language'] = value.id;
          node['refs'] = encode(value.refs);
          node['aliases'] = value.aliases;
          node['caseInsensitive'] = value.case_insensitive;
          node['classNameAliases'] = encode(value.classNameAliases);
          node['disableAutodetect'] = value.disableAutodetect;
          node['name'] = value.name;
          node['supersetOf'] = value.supersetOf;
          node['unicodeRegex'] = value.unicodeRegex;
        }
      }
      return {'mode': id};
    }
    if (value is List) return value.map(encode).toList();
    if (value is Map) return value.map((key, v) => MapEntry(key as String, encode(v)));
    if (value == null || value is String || value is num || value is bool) return value;
    throw StateError('Unsupported grammar value: ${value.runtimeType}');
  }
  final roots = languages.map((key, value) => MapEntry(key, encode(value)));
  return {'version': 1, 'roots': roots, 'nodes': nodes};
}

Map<String, Language> decodeLanguages(Map<String, dynamic> pack) {
  if (pack['version'] != 1) throw FormatException('Unsupported grammar pack');
  final nodes = (pack['nodes'] as List).cast<Map<String, dynamic>>();
  final modes = <Mode>[];
  for (final n in nodes) {
    modes.add(n.containsKey('ref') ? ModeReference(n['ref']) : n['self'] == true ? ModeSelfReference() :
      n.containsKey('language') ? Language(id: n['language'], refs: {},
        aliases: (n['aliases'] as List).cast<String>(), case_insensitive: n['caseInsensitive'],
        disableAutodetect: n['disableAutodetect'], name: n['name'], supersetOf: n['supersetOf'], unicodeRegex: n['unicodeRegex']) : Mode());
  }
  dynamic decode(dynamic value) {
    if (value is Map<String, dynamic>) {
      if (value.length == 1 && value.containsKey('mode')) return modes[value['mode'] as int];
      return value.map((key, v) => MapEntry(key, decode(v)));
    }
    if (value is List) {
      if (value.every((v) => v is String)) return value.cast<String>();
      return value.map(decode).toList();
    }
    return value;
  }
  for (var i = 0; i < nodes.length; i++) {
    final n = nodes[i]; final m = modes[i];
    if (m is ModeReference || m is ModeSelfReference) continue;
    m.keywords = decode(n['keywords']);
    m.illegal = decode(n['illegal']);
    m.begin = decode(n['begin']);
    m.beginKeywords = decode(n['beginKeywords']);
    m.end = decode(n['end']);
    m.lexemes = decode(n['lexemes']);
    m.endSameAsBegin = decode(n['endSameAsBegin']);
    m.endsParent = decode(n['endsParent']);
    m.endsWithParent = decode(n['endsWithParent']);
    m.relevance = (decode(n['relevance']) as num?)?.toDouble();
    m.data = decode(n['data']);
    m.beforeBegin = decode(n['beforeBegin']);
    m.excludeBegin = decode(n['excludeBegin']);
    m.excludeEnd = decode(n['excludeEnd']);
    m.skip = decode(n['skip']);
    m.returnBegin = decode(n['returnBegin']);
    m.returnEnd = decode(n['returnEnd']);
    m.match = decode(n['match']);
    m.beforeMatch = decode(n['beforeMatch']);
    m.beginScope = decode(n['beginScope']);
    m.label = decode(n['label']);
    m.endScope = decode(n['endScope']);
    m.binary = decode(n['binary']);
    m.className = decode(n['className']); m.scope = decode(n['scope']);
    m.contains = (decode(n['contains']) as List?)?.cast<Mode>();
    m.variants = (decode(n['variants']) as List?)?.cast<Mode?>();
    m.starts = decode(n['starts']);
    m.subLanguage = (n['subLanguage'] as List).cast<String>();
    m.onBegin = n['onBegin'] == null ? null : _callbacks[n['onBegin']] ?? (throw FormatException('Unknown callback'));
    m.onEnd = n['onEnd'] == null ? null : _callbacks[n['onEnd']] ?? (throw FormatException('Unknown callback'));
    if (m is Language) {
      m.classNameAliases = decode(n['classNameAliases']);
      m.refs.addAll((decode(n['refs']) as Map).cast<String, Mode>());
    }
  }
  return (pack['roots'] as Map<String, dynamic>).map((key, value) => MapEntry(key, decode(value) as Language));
}
