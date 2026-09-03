import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'model.dart';

class _Metadata {
  const _Metadata({required this.title, required this.updatedAt});

  final String title;
  final int updatedAt;
}

class _Candidate {
  const _Candidate({required this.indexed, required this.summary});

  final bool indexed;
  final ChatSummary summary;
}

double _elapsedMs(Stopwatch stopwatch) => stopwatch.elapsedMicroseconds / 1000;

int _timestamp(Object? value) {
  if (value is num && value.isFinite) {
    return value.round();
  }
  return value is String
      ? DateTime.tryParse(value)?.millisecondsSinceEpoch ?? 0
      : 0;
}

Map<String, dynamic>? _readJson(String path) {
  try {
    final value = jsonDecode(File(path).readAsStringSync());
    return value is Map<String, dynamic> ? value : null;
  } on FileSystemException {
    return null;
  } on FormatException {
    return null;
  }
}

List<String> _walkJsonl(String root) {
  try {
    return Directory(root)
        .listSync(recursive: true, followLinks: false)
        .whereType<File>()
        .map((file) => file.path)
        .where((path) => p.extension(path) == '.jsonl')
        .toList(growable: false);
  } on FileSystemException {
    return const <String>[];
  }
}

String _sessionId(String path) {
  final stem = p.basenameWithoutExtension(path);
  return stem.length >= 36 ? stem.substring(stem.length - 36) : stem;
}

int _modifiedAt(String path) {
  try {
    return File(path).lastModifiedSync().millisecondsSinceEpoch;
  } on FileSystemException {
    return 0;
  }
}

String _fallbackTitle(ChatProvider provider, int updatedAt) {
  const months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final date = DateTime.fromMillisecondsSinceEpoch(updatedAt);
  final label = updatedAt > 0
      ? '${months[date.month - 1]} ${date.day}'
      : 'Unknown date';
  return '${provider == ChatProvider.codex ? 'Codex' : 'Claude'} chat — $label';
}

Map<String, _Metadata> _loadCodexMetadata(String home) {
  final metadata = <String, _Metadata>{};
  try {
    final content = File(p.join(home, '.codex', 'session_index.jsonl'))
        .readAsStringSync();
    for (final line in const LineSplitter().convert(content)) {
      try {
        final record = jsonDecode(line);
        if (record is Map<String, dynamic> && record['id'] is String) {
          metadata[record['id'] as String] = _Metadata(
            title: record['thread_name'] is String
                ? record['thread_name'] as String
                : '',
            updatedAt: _timestamp(record['updated_at']),
          );
        }
      } on FormatException {
        // The actively written final index record may be incomplete.
      }
    }
  } on FileSystemException {
    // Codex may not be installed.
  }
  return metadata;
}

Map<String, _Metadata> _loadClaudeMetadata(String root) {
  final metadata = <String, _Metadata>{};
  if (!Directory(root).existsSync()) {
    return metadata;
  }
  for (final entity in Directory(
    root,
  ).listSync(recursive: true, followLinks: false)) {
    if (entity is! File || p.basename(entity.path) != 'sessions-index.json') {
      continue;
    }
    final index = _readJson(entity.path);
    final entries = index?['entries'];
    if (entries is! List<dynamic>) {
      continue;
    }
    for (final item in entries) {
      if (item is! Map<String, dynamic>) {
        continue;
      }
      final fullPath = item['fullPath'] is String
          ? item['fullPath'] as String
          : '';
      final id = item['sessionId'] is String ? item['sessionId'] as String : '';
      final value = _Metadata(
        title: item['summary'] is String
            ? item['summary'] as String
            : item['firstPrompt'] is String
            ? item['firstPrompt'] as String
            : '',
        updatedAt: _timestamp(item['modified']) != 0
            ? _timestamp(item['modified'])
            : _timestamp(item['fileMtime']),
      );
      if (fullPath.isNotEmpty) {
        metadata[fullPath] = value;
      }
      if (id.isNotEmpty) {
        metadata[id] = value;
      }
    }
  }
  return metadata;
}

bool _isCodexSubagent(String path) {
  RandomAccessFile? handle;
  try {
    handle = File(path).openSync();
    final bytes = handle.readSync(64 * 1024);
    final source = utf8.decode(bytes, allowMalformed: true);
    final lineEnd = source.indexOf('\n');
    final firstLine = lineEnd >= 0 ? source.substring(0, lineEnd) : source;
    final root = jsonDecode(firstLine);
    return root is Map<String, dynamic> &&
        root['payload'] is Map<String, dynamic> &&
        (root['payload'] as Map<String, dynamic>)['source']
            is Map<String, dynamic> &&
        ((root['payload'] as Map<String, dynamic>)['source']
                as Map<String, dynamic>)
            .containsKey('subagent');
  } on FileSystemException {
    return false;
  } on FormatException {
    return false;
  } finally {
    handle?.closeSync();
  }
}

CatalogResult getRecentChats(int limit, String home) {
  final stopwatch = Stopwatch()..start();
  final boundedLimit = limit.clamp(0, 100);
  if (boundedLimit == 0 || home.isEmpty) {
    return CatalogResult(
      nativeTotalMs: _elapsedMs(stopwatch),
      summaries: const <ChatSummary>[],
    );
  }
  final claudeRoot = p.join(home, '.claude', 'projects');
  final codexMetadata = _loadCodexMetadata(home);
  final claudeMetadata = _loadClaudeMetadata(claudeRoot);
  final candidates = <_Candidate>[];
  for (final path in <String>[
    ..._walkJsonl(p.join(home, '.codex', 'sessions')),
    ..._walkJsonl(p.join(home, '.codex', 'archived_sessions')),
  ]) {
    final id = _sessionId(path);
    final metadata = codexMetadata[id];
    final updatedAt = metadata?.updatedAt ?? _modifiedAt(path);
    candidates.add(
      _Candidate(
        indexed: metadata != null,
        summary: ChatSummary(
          id: 'codex:$id',
          path: path,
          provider: ChatProvider.codex,
          title: metadata?.title.isNotEmpty == true
              ? metadata!.title
              : _fallbackTitle(ChatProvider.codex, updatedAt),
          updatedAt: updatedAt,
        ),
      ),
    );
  }
  for (final path in _walkJsonl(claudeRoot)) {
    final segments = p.split(path);
    if (segments.contains('subagents') ||
        p.basename(path).startsWith('agent-')) {
      continue;
    }
    final id = _sessionId(path);
    final metadata = claudeMetadata[path] ?? claudeMetadata[id];
    final updatedAt = metadata?.updatedAt ?? _modifiedAt(path);
    candidates.add(
      _Candidate(
        indexed: true,
        summary: ChatSummary(
          id: 'claude:$id',
          path: path,
          provider: ChatProvider.claude,
          title: metadata?.title.isNotEmpty == true
              ? metadata!.title
              : _fallbackTitle(ChatProvider.claude, updatedAt),
          updatedAt: updatedAt,
        ),
      ),
    );
  }
  candidates.sort((left, right) {
    final date = right.summary.updatedAt.compareTo(left.summary.updatedAt);
    return date != 0 ? date : left.summary.id.compareTo(right.summary.id);
  });
  final summaries = <ChatSummary>[];
  final seenIds = <String>{};
  for (final candidate in candidates) {
    if (!seenIds.add(candidate.summary.id)) {
      continue;
    }
    if (!candidate.indexed && _isCodexSubagent(candidate.summary.path)) {
      continue;
    }
    summaries.add(candidate.summary);
    if (summaries.length == boundedLimit) {
      break;
    }
  }
  stopwatch.stop();
  return CatalogResult(
    nativeTotalMs: _elapsedMs(stopwatch),
    summaries: summaries,
  );
}
