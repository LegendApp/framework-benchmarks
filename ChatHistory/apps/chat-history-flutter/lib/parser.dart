import 'file_source.dart';

import 'dart:convert';

import 'json_range.dart';

import 'model.dart';

typedef JsonObject = Map<String, dynamic>;

class _WorkingRow {
  _WorkingRow(this.kind, int timestampMs)
    : startedAtMs = timestampMs,
      endedAtMs = timestampMs;

  String callId = '';
  int endedAtMs;
  final List<ChatFileChange> fileChanges = <ChatFileChange>[];
  bool hasImagePlaceholder = false;
  final List<String> imageSources = <String>[];
  final ChatRowKind kind;
  DeferredText markdown = textSource('');
  int startedAtMs;
  String toolName = '';
  DeferredText toolPreview = textSource('');
  String toolStatus = '';
}

class _ClaudeRecord {
  const _ClaudeRecord({
    required this.isSidechain,
    required this.parentUuid,
    required this.root,
    required this.timestampMs,
    required this.type,
    required this.uuid,
  });

  final bool isSidechain;
  final String parentUuid;
  final JsonObject root;
  final int timestampMs;
  final String type;
  final String uuid;
}

class _ParseResult {
  const _ParseResult({required this.rows, required this.warningCount});

  final List<ChatRow> rows;
  final int warningCount;
}

JsonObject? _objectValue(Object? value) {
  return value is JsonRange
      ? value.object()
      : value is Map<String, dynamic>
      ? value
      : null;
}

List<dynamic>? _arrayValue(Object? value) {
  return value is JsonRange
      ? value.array()
      : value is List<dynamic>
      ? value
      : null;
}

String _stringValue(Object? value) => value is JsonRange
    ? value.string()
    : value is String
    ? value
    : '';

bool _booleanValue(Object? value) =>
    value is JsonRange ? value.source[value.start] == 116 : value == true;

int _timestampValue(Object? value) {
  final timestamp = DateTime.tryParse(_stringValue(value));
  return timestamp?.millisecondsSinceEpoch ?? 0;
}

double _elapsedMs(Stopwatch stopwatch) => stopwatch.elapsedMicroseconds / 1000;

DeferredText _joinText(Iterable<DeferredText> parts) {
  final values = parts.toList();
  return DeferredText(
    values.any((part) => part.isNotEmpty),
    () => values.where((part) => part.isNotEmpty).join('\n\n'),
  );
}

void _appendMessage(
  List<_WorkingRow> rows,
  ChatRowKind kind,
  List<DeferredText> markdownParts,
  List<String> imageSources,
  bool hasImagePlaceholder,
  int timestampMs,
) {
  final markdown = _joinText(markdownParts);
  if (markdown.isEmpty && imageSources.isEmpty && !hasImagePlaceholder) {
    return;
  }
  final row = _WorkingRow(kind, timestampMs)
    ..markdown = markdown
    ..imageSources.addAll(imageSources)
    ..hasImagePlaceholder = hasImagePlaceholder;
  rows.add(row);
}

int _appendTool(
  List<_WorkingRow> rows,
  Map<String, int> toolRows,
  String callId,
  String name,
  DeferredText preview,
  int timestampMs,
) {
  final row = _WorkingRow(ChatRowKind.tool, timestampMs)
    ..callId = callId
    ..toolName = name.isEmpty ? 'Tool' : name
    ..toolPreview = preview
    ..toolStatus = 'unknown';
  rows.add(row);
  final index = rows.length - 1;
  if (callId.isNotEmpty) {
    toolRows[callId] = index;
  }
  return index;
}

void _applyToolResult(
  List<_WorkingRow> rows,
  Map<String, int> toolRows,
  String callId,
  DeferredText preview,
  bool failed,
  int timestampMs,
) {
  final index =
      toolRows[callId] ??
      _appendTool(rows, toolRows, callId, 'Tool', textSource(''), timestampMs);
  final row = rows[index]..toolStatus = failed ? 'failed' : 'completed';
  if (timestampMs > row.endedAtMs) {
    row.endedAtMs = timestampMs;
  }
  if (preview.isNotEmpty) {
    row.toolPreview = preview;
  }
}

int _countLines(String content) {
  if (content.isEmpty) {
    return 0;
  }
  return '\n'.allMatches(content).length + (content.endsWith('\n') ? 0 : 1);
}

({int additions, int deletions}) _countDiffLines(String diff) {
  var additions = 0;
  var deletions = 0;
  var inHunk = false;
  for (final line in const LineSplitter().convert(diff)) {
    if (line.startsWith('@@')) {
      inHunk = true;
    } else if (inHunk && line.startsWith('+')) {
      additions += 1;
    } else if (inHunk && line.startsWith('-')) {
      deletions += 1;
    }
  }
  return (additions: additions, deletions: deletions);
}

String _visibleUserMarkdown(String markdown, _WorkingRow row) {
  const filesHeading = '# Files mentioned by the user:';
  const requestHeading = '## My request for Codex:';
  final firstContent = markdown.indexOf(RegExp(r'[^\r\n]'));
  if (row.kind == ChatRowKind.user &&
      (row.imageSources.isNotEmpty || row.hasImagePlaceholder) &&
      firstContent >= 0 &&
      markdown.startsWith(filesHeading, firstContent)) {
    final requestIndex = markdown.indexOf(
      requestHeading,
      firstContent + filesHeading.length,
    );
    if (requestIndex >= 0) {
      var contentIndex = requestIndex + requestHeading.length;
      while (contentIndex < markdown.length &&
          (markdown[contentIndex] == '\r' || markdown[contentIndex] == '\n')) {
        contentIndex += 1;
      }
      return markdown.substring(contentIndex);
    }
  }
  return markdown;
}

String _visibleAssistantMarkdown(String markdown, ChatRowKind kind) {
  if (kind != ChatRowKind.assistant) {
    return markdown;
  }
  final directive = RegExp(
    r'^\s*::(?:git-stage|git-commit|git-create-branch|git-push|git-create-pr|created-thread|code-comment)\{',
  );
  final output = <String>[];
  var inCodeFence = false;
  var inMemoryCitation = false;
  for (final line in markdown.split('\n')) {
    final trimmed = line.trim();
    if (!inCodeFence && trimmed.startsWith('<oai-mem-citation>')) {
      inMemoryCitation = !trimmed.contains('</oai-mem-citation>');
    } else if (inMemoryCitation) {
      inMemoryCitation = !trimmed.contains('</oai-mem-citation>');
    } else if (inCodeFence || !directive.hasMatch(line)) {
      output.add(line);
    }
    if (!inMemoryCitation &&
        (trimmed.startsWith('```') || trimmed.startsWith('~~~'))) {
      inCodeFence = !inCodeFence;
    }
  }
  while (output.isNotEmpty && (output.last.isEmpty || output.last == '\r')) {
    output.removeLast();
  }
  return output.join('\n');
}

String _toolActivityLabel(_WorkingRow row) {
  final name = row.toolName.toLowerCase();
  var label = 'Used a tool';
  if (RegExp(r'exec|shell|command|bash').hasMatch(name)) {
    label = 'Ran a command';
  } else if (name.contains('agent')) {
    label = 'Worked with an agent';
  } else if (RegExp(r'patch|write|edit').hasMatch(name)) {
    label = 'Edited files';
  } else if (RegExp(r'read|open|find|glob|grep').hasMatch(name)) {
    label = 'Read files';
  } else if (RegExp(r'web|search|browser').hasMatch(name)) {
    label = 'Searched the web';
  } else if (name.contains('image')) {
    label = 'Created an image';
  } else if (name.isNotEmpty) {
    label = 'Used ${name.replaceAll(RegExp('[_-]'), ' ')}';
  }
  return row.toolStatus == 'failed' ? '$label (failed)' : label;
}

String _workLabel(List<_WorkingRow> rows) {
  final starts = rows
      .map((row) => row.startedAtMs)
      .where((value) => value > 0)
      .toList(growable: false);
  final ends = rows
      .map((row) => row.endedAtMs)
      .where((value) => value > 0)
      .toList(growable: false);
  if (starts.isEmpty || ends.isEmpty) {
    return 'Worked';
  }
  starts.sort();
  ends.sort();
  final elapsedSeconds = ((ends.last - starts.first) / 1000).round().clamp(
    1,
    1 << 31,
  );
  final hours = elapsedSeconds ~/ 3600;
  final minutes = (elapsedSeconds % 3600) ~/ 60;
  final seconds = elapsedSeconds % 60;
  var duration = '${seconds}s';
  if (hours > 0) {
    duration = minutes > 0 ? '${hours}h ${minutes}m' : '${hours}h';
  } else if (minutes > 0) {
    duration = seconds > 0 ? '${minutes}m ${seconds}s' : '${minutes}m';
  }
  return 'Worked for $duration';
}

String _workPreview(List<_WorkingRow> rows) {
  final output = <String>[];
  var activities = <String>[];
  void flushActivities() {
    if (activities.isEmpty) {
      return;
    }
    output.add(
      activities.indexed
          .map(
            (entry) => entry.$1 == 0
                ? entry.$2
                : '${entry.$2[0].toLowerCase()}${entry.$2.substring(1)}',
          )
          .join(', '),
    );
    activities = <String>[];
  }

  for (final row in rows) {
    if (row.kind == ChatRowKind.tool) {
      final activity = _toolActivityLabel(row);
      if (!activities.contains(activity)) {
        activities.add(activity);
      }
    } else {
      flushActivities();
      if (row.markdown.isNotEmpty) {
        output.add(
          row.markdown.toString().substring(
            0,
            row.markdown.toString().length.clamp(0, 4 * 1024),
          ),
        );
      }
      if (row.hasImagePlaceholder) {
        output.add('Image or attachment omitted');
      }
    }
  }
  flushActivities();
  final preview = output.join('\n\n');
  return preview.substring(0, preview.length.clamp(0, 64 * 1024));
}

ChatRow _finalizeRow(_WorkingRow row, int index) {
  return ChatRow(
    fileChanges: row.fileChanges,
    hasImagePlaceholder: row.hasImagePlaceholder,
    id: 'row:$index',
    imageSources: row.imageSources,
    kind: row.kind,
    markdownSource: () => _visibleAssistantMarkdown(
      _visibleUserMarkdown(row.markdown.toString(), row),
      row.kind,
    ),
    toolName: row.toolName,
    toolPreviewSource: row.toolPreview.decode,
    toolStatus: row.toolStatus,
  );
}

List<ChatRow> _displayRows(List<_WorkingRow> rows) {
  final result = <ChatRow>[];
  var sourceIndex = 0;
  while (sourceIndex < rows.length) {
    final row = rows[sourceIndex];
    if (row.kind == ChatRowKind.user) {
      result.add(_finalizeRow(row, result.length));
      sourceIndex += 1;
      continue;
    }
    var turnEnd = sourceIndex;
    var lastTool = -1;
    while (turnEnd < rows.length && rows[turnEnd].kind != ChatRowKind.user) {
      if (rows[turnEnd].kind == ChatRowKind.tool) {
        lastTool = turnEnd;
      }
      turnEnd += 1;
    }
    if (lastTool >= sourceIndex) {
      final grouped = rows.sublist(sourceIndex, lastTool + 1);
      final work = _WorkingRow(ChatRowKind.tool, 0)
        ..toolName = _workLabel(grouped)
        ..toolPreview = DeferredText(true, () => _workPreview(grouped))
        ..toolStatus =
            grouped.any(
              (item) =>
                  item.kind == ChatRowKind.tool && item.toolStatus == 'failed',
            )
            ? 'failed'
            : grouped.any(
                (item) =>
                    item.kind == ChatRowKind.tool &&
                    item.toolStatus != 'completed',
              )
            ? 'unknown'
            : 'completed';
      result.add(_finalizeRow(work, result.length));
      sourceIndex = lastTool + 1;
    } else {
      result.add(_finalizeRow(row, result.length));
      sourceIndex += 1;
    }
  }
  return result;
}

_ParseResult _parseCodex(Iterable<dynamic> lines) {
  final rows = <_WorkingRow>[];
  final toolRows = <String, int>{};
  var warningCount = 0;
  var cwd = '';
  var sawEventUserMessage = false;
  var pendingTurnId = '';
  var pendingFiles = <ChatFileChange>[];
  void appendFiles() {
    if (pendingFiles.isNotEmpty) {
      rows.add(
        _WorkingRow(ChatRowKind.files, 0)..fileChanges.addAll(pendingFiles),
      );
    }
    pendingTurnId = '';
    pendingFiles = <ChatFileChange>[];
  }

  for (final line in lines) {
    JsonObject? root;
    try {
      root = _objectValue(line is String ? jsonDecode(line) : line);
    } on FormatException {
      warningCount += 1;
      continue;
    }
    if (root == null) {
      warningCount += 1;
      continue;
    }
    final recordType = _stringValue(root['type']);
    final payload = _objectValue(root['payload']);
    final timestampMs = _timestampValue(root['timestamp']);
    if (recordType.isEmpty || !root.containsKey('payload')) {
      warningCount += 1;
      continue;
    }
    if (recordType == 'compacted') {
      continue;
    }
    if ((recordType == 'session_meta' || recordType == 'turn_context') &&
        payload != null) {
      cwd = _stringValue(payload['cwd']).isEmpty
          ? cwd
          : _stringValue(payload['cwd']);
      continue;
    }
    if (recordType == 'event_msg' && payload != null) {
      final eventType = _stringValue(payload['type']);
      if (eventType == 'user_message') {
        sawEventUserMessage = true;
        appendFiles();
        final message = textSource(payload['message']);
        if (message.isEmpty) {
          warningCount += 1;
        }
        final localImages = (_arrayValue(payload['local_images']) ?? const [])
            .map(_stringValue)
            .where((value) => value.isNotEmpty)
            .toList(growable: false);
        var hasImagePlaceholder = false;
        final remoteImages = <String>[];
        for (final value in _arrayValue(payload['images']) ?? const []) {
          final image = _stringValue(value);
          if (image.isEmpty || utf8.encode(image).length > 8 * 1024) {
            hasImagePlaceholder = true;
          } else {
            remoteImages.add(image);
          }
        }
        _appendMessage(
          rows,
          ChatRowKind.user,
          <DeferredText>[message],
          <String>[...localImages, ...remoteImages],
          hasImagePlaceholder,
          timestampMs,
        );
      } else if (eventType == 'patch_apply_end' &&
          _booleanValue(payload['success'])) {
        final turnId = _stringValue(payload['turn_id']);
        if (pendingTurnId.isNotEmpty &&
            turnId.isNotEmpty &&
            pendingTurnId != turnId) {
          appendFiles();
        }
        pendingTurnId = turnId;
        final changes = _objectValue(payload['changes']);
        if (changes != null) {
          for (final entry in changes.entries) {
            final change = _objectValue(entry.value);
            if (change == null) {
              warningCount += 1;
              continue;
            }
            final type = _stringValue(change['type']);
            var additions = 0;
            var deletions = 0;
            if (type == 'update' && isStringValue(change['unified_diff'])) {
              final counts = _countDiffLines(
                _stringValue(change['unified_diff']),
              );
              additions = counts.additions;
              deletions = counts.deletions;
            } else if ((type == 'add' || type == 'delete') &&
                isStringValue(change['content'])) {
              final count = _countLines(_stringValue(change['content']));
              additions = type == 'add' ? count : 0;
              deletions = type == 'delete' ? count : 0;
            } else {
              warningCount += 1;
              continue;
            }
            final relativePath = cwd.isNotEmpty && entry.key.startsWith('$cwd/')
                ? entry.key.substring(cwd.length + 1)
                : entry.key;
            final existingIndex = pendingFiles.indexWhere(
              (file) => file.path == relativePath,
            );
            if (existingIndex >= 0) {
              pendingFiles[existingIndex]
                ..additions += additions
                ..deletions += deletions;
            } else {
              pendingFiles.add(
                ChatFileChange(
                  additions: additions,
                  deletions: deletions,
                  path: relativePath,
                ),
              );
            }
          }
        }
      }
      continue;
    }
    if (recordType != 'response_item') {
      continue;
    }
    if (payload == null) {
      warningCount += 1;
      continue;
    }
    final payloadType = _stringValue(payload['type']);
    if (payloadType == 'message') {
      final role = _stringValue(payload['role']);
      if (role != 'assistant' && (role != 'user' || sawEventUserMessage)) {
        continue;
      }
      final content = payload['content'];
      final text = <DeferredText>[];
      var hasImage = false;
      if (isStringValue(content)) {
        text.add(textSource(content));
      } else if (_arrayValue(content) != null) {
        for (final rawBlock in _arrayValue(content)!) {
          final block = _objectValue(rawBlock);
          final blockType = _stringValue(block?['type']);
          if (block != null &&
              const ['input_text', 'output_text', 'text'].contains(blockType)) {
            text.add(textSource(block['text']));
          } else if (const ['input_image', 'image'].contains(blockType)) {
            hasImage = true;
          } else if (blockType.isNotEmpty) {
            warningCount += 1;
          }
        }
      } else if (content != null) {
        warningCount += 1;
      }
      _appendMessage(
        rows,
        role == 'user' ? ChatRowKind.user : ChatRowKind.assistant,
        text,
        const <String>[],
        hasImage,
        timestampMs,
      );
    } else if (const [
      'function_call',
      'custom_tool_call',
      'local_shell_call',
    ].contains(payloadType)) {
      _appendTool(
        rows,
        toolRows,
        _stringValue(payload['call_id']),
        _stringValue(payload['name']),
        textSource(
          payload[payloadType == 'custom_tool_call' ? 'input' : 'arguments'],
        ),
        timestampMs,
      );
    } else if (const [
      'function_call_output',
      'custom_tool_call_output',
    ].contains(payloadType)) {
      _applyToolResult(
        rows,
        toolRows,
        _stringValue(payload['call_id']),
        textSource(payload['output']),
        false,
        timestampMs,
      );
    } else if (payloadType == 'image_generation_call') {
      final callId = _stringValue(payload['id']);
      final index =
          toolRows[callId] ??
          _appendTool(
            rows,
            toolRows,
            callId,
            'Image generation',
            textSource(''),
            timestampMs,
          );
      final row = rows[index];
      final hasResult = _stringValue(payload['result']).isNotEmpty;
      row
        ..toolStatus = _stringValue(payload['status']) == 'failed'
            ? 'failed'
            : hasResult
            ? 'completed'
            : 'unknown'
        ..hasImagePlaceholder = row.hasImagePlaceholder || hasResult;
      if (timestampMs > row.endedAtMs) {
        row.endedAtMs = timestampMs;
      }
    } else if (payloadType != 'reasoning' && payloadType.isNotEmpty) {
      warningCount += 1;
    }
  }
  appendFiles();
  return _ParseResult(rows: _displayRows(rows), warningCount: warningCount);
}

int _parseClaudeMessage(
  _ClaudeRecord record,
  List<_WorkingRow> rows,
  Map<String, int> toolRows,
) {
  final message = _objectValue(record.root['message']);
  if (message == null || !message.containsKey('content')) {
    return 1;
  }
  final messageContent = message['content'];
  final rowKind = record.type == 'user'
      ? ChatRowKind.user
      : ChatRowKind.assistant;
  if (isStringValue(messageContent)) {
    _appendMessage(
      rows,
      rowKind,
      <DeferredText>[textSource(messageContent)],
      const <String>[],
      false,
      record.timestampMs,
    );
    return 0;
  }
  final content = _arrayValue(messageContent);
  if (content == null) {
    return 1;
  }
  final text = <DeferredText>[];
  var hasImage = false;
  var warningCount = 0;
  final deferredTools = <void Function()>[];
  for (final rawBlock in _arrayValue(content)!) {
    final block = _objectValue(rawBlock);
    if (block == null) {
      warningCount += 1;
      continue;
    }
    final blockType = _stringValue(block['type']);
    if (blockType == 'text') {
      text.add(textSource(block['text']));
    } else if (blockType == 'image' || blockType == 'document') {
      hasImage = true;
    } else if (blockType == 'tool_use') {
      final callId = _stringValue(block['id']);
      final name = _stringValue(block['name']);
      deferredTools.add(
        () => _appendTool(
          rows,
          toolRows,
          callId,
          name,
          textSource(''),
          record.timestampMs,
        ),
      );
    } else if (blockType == 'tool_result') {
      final callId = _stringValue(block['tool_use_id']);
      final resultContent = block['content'];
      final previews = <DeferredText>[];
      var resultImage = false;
      if (isStringValue(resultContent)) {
        previews.add(textSource(resultContent));
      } else if (_arrayValue(resultContent) != null) {
        for (final rawResult in _arrayValue(resultContent)!) {
          if (isStringValue(rawResult)) {
            previews.add(textSource(rawResult));
          } else {
            final result = _objectValue(rawResult);
            final resultType = _stringValue(result?['type']);
            if (resultType == 'text') {
              previews.add(textSource(result?['text']));
            } else if (resultType == 'image') {
              resultImage = true;
            } else {
              warningCount += 1;
            }
          }
        }
      }
      deferredTools.add(() {
        _applyToolResult(
          rows,
          toolRows,
          callId,
          _joinText(previews),
          _booleanValue(block['is_error']),
          record.timestampMs,
        );
        final index = toolRows[callId];
        if (resultImage && index != null) {
          rows[index].hasImagePlaceholder = true;
        }
      });
    } else if (blockType != 'thinking') {
      warningCount += 1;
    }
  }
  _appendMessage(
    rows,
    rowKind,
    text,
    const <String>[],
    hasImage,
    record.timestampMs,
  );
  for (final append in deferredTools) {
    append();
  }
  return warningCount;
}

_ParseResult _parseClaude(Iterable<dynamic> lines) {
  final records = <_ClaudeRecord>[];
  final recordById = <String, _ClaudeRecord>{};
  var warningCount = 0;
  var leafId = '';
  for (final line in lines) {
    JsonObject? root;
    try {
      root = _objectValue(line is String ? jsonDecode(line) : line);
    } on FormatException {
      warningCount += 1;
      continue;
    }
    if (root == null) {
      warningCount += 1;
      continue;
    }
    final record = _ClaudeRecord(
      isSidechain: _booleanValue(root['isSidechain']),
      parentUuid: _stringValue(root['parentUuid']),
      root: root,
      timestampMs: _timestampValue(root['timestamp']),
      type: _stringValue(root['type']),
      uuid: _stringValue(root['uuid']),
    );
    records.add(record);
    if (record.uuid.isNotEmpty && !record.isSidechain) {
      recordById[record.uuid] = record;
      leafId = record.uuid;
    }
  }
  final mainChain = <String>{};
  var cursor = leafId;
  while (cursor.isNotEmpty && !mainChain.contains(cursor)) {
    mainChain.add(cursor);
    final record = recordById[cursor];
    if (record == null) {
      warningCount += 1;
      break;
    }
    cursor = record.parentUuid;
  }
  final rows = <_WorkingRow>[];
  final toolRows = <String, int>{};
  for (final record in records) {
    if (!record.isSidechain &&
        record.uuid.isNotEmpty &&
        mainChain.contains(record.uuid) &&
        (record.type == 'user' || record.type == 'assistant')) {
      warningCount += _parseClaudeMessage(record, rows, toolRows);
    }
  }
  return _ParseResult(rows: _displayRows(rows), warningCount: warningCount);
}

ChatDocument openChatFile(ChatProvider provider, String path) {
  final total = Stopwatch()..start();
  final load = Stopwatch()..start();
  final source = FileSource(path);
  try {
    load.stop();

    final scan = Stopwatch()..start();
    final ranges = source.lineRanges();
    scan.stop();

    final parse = Stopwatch()..start();
    final lines = _DecodedLines(source, ranges);
    final parsed = provider == ChatProvider.codex
        ? _parseCodex(lines)
        : _parseClaude(lines);
    parse.stop();
    total.stop();

    final document = ChatDocument(
      path: path,
      provider: provider,
      recordCount: ranges.length ~/ 2,
      rows: parsed.rows,
      sourceBytes: source.length,
      timing: NativeTiming(
        loadMs: _elapsedMs(load),
        nativeTotalMs: _elapsedMs(total),
        parseMs: _elapsedMs(parse),
        scanMs: _elapsedMs(scan),
      ),
      warningCount: parsed.warningCount,
    );
    _sources[document] = source;
    return document;
  } catch (_) {
    source.close();
    rethrow;
  }
}

class _DecodedLines extends Iterable<dynamic> {
  const _DecodedLines(this.source, this.ranges);

  final List<int> ranges;
  final List<int> source;

  @override
  Iterator<dynamic> get iterator => _DecodedLineIterator(source, ranges);
}

class _DecodedLineIterator implements Iterator<dynamic> {
  _DecodedLineIterator(this.source, this.ranges);

  final List<int> ranges;
  final List<int> source;
  var _rangeIndex = 0;
  dynamic _value;

  @override
  dynamic get current => _value;

  @override
  bool moveNext() {
    if (_rangeIndex >= ranges.length) {
      return false;
    }
    try {
      _value = JsonRange.parse(
        source,
        ranges[_rangeIndex],
        ranges[_rangeIndex + 1],
      );
    } on FormatException {
      _value = '!invalid';
    }
    _rangeIndex += 2;
    return true;
  }
}

final _sources = Expando<FileSource>();
void closeChatDocument(ChatDocument document) {
  _sources[document]?.close();
  _sources[document] = null;
}
