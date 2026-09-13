import 'dart:convert';
import 'dart:typed_data';

/// Validated byte ranges; only requested keys, arrays and strings are materialized.
class JsonRange {
  JsonRange(this.source, this.start, this.end);
  final Uint8List source;
  final int start, end;
  Map<String, dynamic>? _fields;
  List<dynamic>? _elements;
  bool get isString => source[start] == 34;
  String string() => isString
      ? jsonDecode(utf8.decode(Uint8List.sublistView(source, start, end)))
            as String
      : '';
  Map<String, dynamic>? object() {
    if (source[start] != 123) return null;
    if (_fields != null) return _fields;
    final fields = <String, dynamic>{};
    var cursor = _space(source, start + 1, end);
    while (source[cursor] != 125) {
      final keyEnd = _scan(source, cursor, end, 0);
      final key = JsonRange(source, cursor, keyEnd).string();
      cursor = _space(source, keyEnd, end) + 1;
      cursor = _space(source, cursor, end);
      final valueEnd = _scan(source, cursor, end, 0);
      fields[key] = JsonRange(source, cursor, valueEnd);
      cursor = _space(source, valueEnd, end);
      if (source[cursor] == 44) cursor = _space(source, cursor + 1, end);
    }
    return _fields = fields;
  }

  List<dynamic>? array() {
    if (source[start] != 91) return null;
    if (_elements != null) return _elements;
    final elements = <dynamic>[];
    var cursor = _space(source, start + 1, end);
    while (source[cursor] != 93) {
      final valueEnd = _scan(source, cursor, end, 0);
      elements.add(JsonRange(source, cursor, valueEnd));
      cursor = _space(source, valueEnd, end);
      if (source[cursor] == 44) cursor = _space(source, cursor + 1, end);
    }
    return _elements = elements;
  }

  static JsonRange parse(Uint8List source, int start, int end) {
    start = _space(source, start, end);
    final valueEnd = _scan(source, start, end, 0);
    if (_space(source, valueEnd, end) != end) {
      throw const FormatException('Trailing JSON input');
    }
    return JsonRange(source, start, valueEnd);
  }
}

int _space(Uint8List s, int i, int end) {
  while (i < end && (s[i] == 32 || s[i] == 9 || s[i] == 10 || s[i] == 13)) {
    i++;
  }
  return i;
}

Never _invalid() => throw const FormatException('Invalid JSON');
int _scan(Uint8List s, int i, int end, int depth) {
  if (i >= end || depth > 512) _invalid();
  final first = s[i++];
  if (first == 34) {
    while (i < end) {
      final c = s[i++];
      if (c == 34) return i;
      if (c < 32) _invalid();
      if (c == 92) {
        if (i >= end) _invalid();
        final escape = s[i++];
        if (escape == 117) {
          for (var k = 0; k < 4; k++) {
            if (i >= end) _invalid();
            final h = s[i++];
            if (!((h >= 48 && h <= 57) ||
                (h >= 65 && h <= 70) ||
                (h >= 97 && h <= 102))) {
              _invalid();
            }
          }
        } else if (![34, 92, 47, 98, 102, 110, 114, 116].contains(escape)) {
          _invalid();
        }
      }
    }
    _invalid();
  }
  if (first == 123 || first == 91) {
    final close = first == 123 ? 125 : 93;
    i = _space(s, i, end);
    if (i < end && s[i] == close) return i + 1;
    while (true) {
      if (first == 123) {
        if (i >= end || s[i] != 34) _invalid();
        i = _space(s, _scan(s, i, end, depth + 1), end);
        if (i >= end || s[i++] != 58) _invalid();
        i = _space(s, i, end);
      }
      i = _space(s, _scan(s, i, end, depth + 1), end);
      if (i >= end) _invalid();
      if (s[i] == close) return i + 1;
      if (s[i++] != 44) _invalid();
      i = _space(s, i, end);
    }
  }
  for (final literal in ['true', 'false', 'null']) {
    if (first == literal.codeUnitAt(0)) {
      for (var k = 1; k < literal.length; k++) {
        if (i >= end || s[i++] != literal.codeUnitAt(k)) _invalid();
      }
      return i;
    }
  }
  i--;
  if (s[i] == 45) i++;
  if (i >= end) _invalid();
  if (s[i] == 48) {
    i++;
  } else {
    if (s[i] < 49 || s[i] > 57) _invalid();
    while (i < end && s[i] >= 48 && s[i] <= 57) {
      i++;
    }
  }
  if (i < end && s[i] == 46) {
    i++;
    final start = i;
    while (i < end && s[i] >= 48 && s[i] <= 57) {
      i++;
    }
    if (i == start) _invalid();
  }
  if (i < end && (s[i] == 101 || s[i] == 69)) {
    i++;
    if (i < end && (s[i] == 43 || s[i] == 45)) i++;
    final start = i;
    while (i < end && s[i] >= 48 && s[i] <= 57) {
      i++;
    }
    if (i == start) _invalid();
  }
  return i;
}

class DeferredText {
  DeferredText(this.nonempty, this.decode);
  final bool nonempty;
  final String Function() decode;
  bool get isEmpty => !nonempty;
  bool get isNotEmpty => nonempty;
  @override
  String toString() => decode();
}

DeferredText textSource(Object? value) {
  if (value is DeferredText) return value;
  if (value is JsonRange && value.isString) {
    return DeferredText(value.end - value.start > 2, value.string);
  }
  final text = value is String ? value : '';
  return DeferredText(text.isNotEmpty, () => text);
}

bool isStringValue(Object? value) =>
    value is String || value is JsonRange && value.isString;
