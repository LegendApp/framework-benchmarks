import 'dart:convert';

enum ChatProvider { claude, codex }

extension ChatProviderName on ChatProvider {
  String get wireName => name;

  static ChatProvider parse(String value) {
    return value == 'claude' ? ChatProvider.claude : ChatProvider.codex;
  }
}

enum ChatRowKind { assistant, files, tool, user }

class ChatSummary {
  const ChatSummary({
    required this.id,
    required this.path,
    required this.provider,
    required this.title,
    required this.updatedAt,
  });

  final String id;
  final String path;
  final ChatProvider provider;
  final String title;
  final int updatedAt;

  factory ChatSummary.fromJson(Map<String, dynamic> json) {
    return ChatSummary(
      id: json['id'] as String,
      path: json['path'] as String,
      provider: ChatProviderName.parse(json['provider'] as String),
      title: json['title'] as String,
      updatedAt: (json['updatedAt'] as num).round(),
    );
  }
}

class ChatFileChange {
  ChatFileChange({
    required this.additions,
    required this.deletions,
    required this.path,
  });

  int additions;
  int deletions;
  final String path;
}

class ChatRow {
  const ChatRow({
    required this.fileChanges,
    required this.hasImagePlaceholder,
    required this.id,
    required this.imageSources,
    required this.kind,
    this.rawMarkdown = '',
    this.markdownSource,
    required this.toolName,
    this.rawToolPreview = '',
    this.toolPreviewSource,
    required this.toolStatus,
    this.deferred = false,
  });

  final List<ChatFileChange> fileChanges;
  final bool hasImagePlaceholder;
  final String id;
  final List<String> imageSources;
  final ChatRowKind kind;
  final String rawMarkdown;
  final String Function()? markdownSource;
  String get markdown => markdownSource?.call() ?? rawMarkdown;
  final bool deferred;
  final String toolName;
  final String rawToolPreview;
  final String Function()? toolPreviewSource;
  String get toolPreview => toolPreviewSource?.call() ?? rawToolPreview;
  final String toolStatus;
}

class NativeTiming {
  const NativeTiming({
    required this.loadMs,
    required this.nativeTotalMs,
    required this.parseMs,
    required this.scanMs,
  });

  final double loadMs;
  final double nativeTotalMs;
  final double parseMs;
  final double scanMs;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'loadMs': loadMs,
    'nativeTotalMs': nativeTotalMs,
    'parseMs': parseMs,
    'scanMs': scanMs,
  };
}

class ChatDocument {
  const ChatDocument({
    this.documentId,
    required this.path,
    required this.provider,
    required this.recordCount,
    required this.rows,
    required this.sourceBytes,
    required this.timing,
    required this.warningCount,
  });

  final String? documentId;
  final String path;
  final ChatProvider provider;
  final int recordCount;
  final List<ChatRow> rows;
  final int sourceBytes;
  final NativeTiming timing;
  final int warningCount;
}

String normalizedContentDigest(List<ChatRow> rows) {
  final mask = BigInt.parse('ffffffffffffffff', radix: 16);
  final prime = BigInt.parse('100000001b3', radix: 16);
  var digest = BigInt.parse('cbf29ce484222325', radix: 16);
  void updateBytes(List<int> bytes) {
    for (final byte in bytes) {
      digest = ((digest ^ BigInt.from(byte)) * prime) & mask;
    }
  }

  void field(Object value) {
    final bytes = utf8.encode(value.toString());
    updateBytes(utf8.encode(bytes.length.toString()));
    updateBytes(const [58]);
    updateBytes(bytes);
    updateBytes(const [59]);
  }

  field(rows.length);
  for (final row in rows) {
    field(row.kind.name);
    field(row.markdown);
    field(row.toolName);
    field(row.toolPreview);
    field(row.toolStatus);
    field(row.hasImagePlaceholder ? 1 : 0);
    field(row.imageSources.length);
    for (final source in row.imageSources) {
      field(source);
    }
    field(row.fileChanges.length);
    for (final change in row.fileChanges) {
      field(change.path);
      field(change.additions);
      field(change.deletions);
    }
  }
  return digest.toRadixString(16).padLeft(16, '0');
}

class CatalogResult {
  const CatalogResult({required this.nativeTotalMs, required this.summaries});

  final double nativeTotalMs;
  final List<ChatSummary> summaries;
}

class BenchmarkConfig {
  const BenchmarkConfig({
    this.appearance = ChatAppearance.system,
    required this.loadImages,
    required this.switchDelayMs,
    required this.topDelayMs,
    required this.targets,
  });

  final ChatAppearance appearance;
  final bool loadImages;
  final int switchDelayMs;
  final int topDelayMs;
  final List<BenchmarkTarget> targets;

  factory BenchmarkConfig.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 2 || json['targets'] is! List) {
      throw const FormatException(
        'Unsupported chat history benchmark manifest',
      );
    }
    final targets = (json['targets'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(BenchmarkTarget.fromJson)
        .toList(growable: false);
    if (targets.length != 2) {
      throw const FormatException('Benchmark requires exactly two targets');
    }
    return BenchmarkConfig(
      appearance:
          ChatAppearance.values
              .where((value) => value.name == json['appearance'])
              .firstOrNull ??
          ChatAppearance.system,
      loadImages: json['loadImages'] as bool? ?? false,
      switchDelayMs: (json['switchDelayMs'] as num).round(),
      topDelayMs: (json['topDelayMs'] as num).round(),
      targets: targets,
    );
  }
}

class BenchmarkTarget {
  const BenchmarkTarget({required this.id, required this.provider});

  final String id;
  final ChatProvider provider;

  factory BenchmarkTarget.fromJson(Map<String, dynamic> json) =>
      BenchmarkTarget(
        id: json['id'] as String,
        provider: ChatProviderName.parse(json['provider'] as String),
      );
}

enum ChatAppearance { dark, light, system }

class ChatHistorySettings {
  const ChatHistorySettings({
    this.appearance = ChatAppearance.system,
    this.loadImages = true,
    this.recentChatLimit = 20,
    this.restoreSelection = true,
    this.selectedId,
    this.showPerformanceMetrics = false,
  });

  final ChatAppearance appearance;
  final bool loadImages;
  final int recentChatLimit;
  final bool restoreSelection;
  final String? selectedId;
  final bool showPerformanceMetrics;

  ChatHistorySettings copyWith({
    ChatAppearance? appearance,
    bool? loadImages,
    int? recentChatLimit,
    bool? restoreSelection,
    String? selectedId,
    bool clearSelectedId = false,
    bool? showPerformanceMetrics,
  }) {
    return ChatHistorySettings(
      appearance: appearance ?? this.appearance,
      loadImages: loadImages ?? this.loadImages,
      recentChatLimit: recentChatLimit ?? this.recentChatLimit,
      restoreSelection: restoreSelection ?? this.restoreSelection,
      selectedId: clearSelectedId ? null : selectedId ?? this.selectedId,
      showPerformanceMetrics:
          showPerformanceMetrics ?? this.showPerformanceMetrics,
    );
  }
}
