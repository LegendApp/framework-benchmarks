import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'benchmark.dart';
import 'catalog.dart';
import 'model.dart';
import 'parser_worker.dart';
import 'settings.dart';

CatalogResult _loadCatalog(({String home, int limit}) request) {
  return getRecentChats(request.limit, request.home);
}

void _computeContentDigest((List<ChatRow>, SendPort) request) {
  request.$2.send(normalizedContentDigest(request.$1));
}

Future<String> _contentDigestInBackground(List<ChatRow> rows) async {
  final result = ReceivePort();
  await Isolate.spawn(_computeContentDigest, (rows, result.sendPort));
  final digest = await result.first as String;
  result.close();
  return digest;
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ChatHistoryApp());
}

class ChatHistoryApp extends StatefulWidget {
  const ChatHistoryApp({super.key});

  @override
  State<ChatHistoryApp> createState() => _ChatHistoryAppState();
}

class _Selection {
  const _Selection({
    required this.id,
    this.document,
    this.error,
    this.firstPaintMs,
    this.openedAt,
    this.phase,
  });

  final ChatDocument? document;
  final String? error;
  final double? firstPaintMs;
  final String id;
  final Stopwatch? openedAt;
  final String? phase;

  bool get isLoading => document == null && error == null;

  _Selection copyWith({double? firstPaintMs}) {
    return _Selection(
      id: id,
      document: document,
      error: error,
      firstPaintMs: firstPaintMs ?? this.firstPaintMs,
      openedAt: openedAt,
      phase: phase,
    );
  }
}

class _ChatHistoryAppState extends State<ChatHistoryApp> {
  final ChatParserWorker _parserWorker = ChatParserWorker();
  final SettingsStore _settingsStore = SettingsStore();
  final String _home = Platform.environment['HOME'] ?? '';

  ChatBenchmark? _benchmark;
  double? _catalogMs;
  String? _catalogError;
  var _selectionGeneration = 0;
  _Selection? _selection;
  ChatHistorySettings _settings = const ChatHistorySettings();
  List<ChatSummary> _summaries = const <ChatSummary>[];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(ChatBenchmark.emitWindowShown());
    });
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    _parserWorker.dispose();
    super.dispose();
  }

  ThemeMode get _themeMode => switch (_settings.appearance) {
    ChatAppearance.dark => ThemeMode.dark,
    ChatAppearance.light => ThemeMode.light,
    ChatAppearance.system => ThemeMode.system,
  };

  Future<void> _bootstrap() async {
    final settingsFuture = _settingsStore.read();
    final benchmarkFuture = ChatBenchmark.load();
    final loadedSettings = await settingsFuture;
    final benchmark = await benchmarkFuture;
    if (!mounted) {
      return;
    }
    if (benchmark != null) {
      final benchmarkSettings = ChatHistorySettings(
        loadImages: benchmark.config.loadImages,
        restoreSelection: false,
      );
      setState(() {
        _benchmark = benchmark;
        _settings = benchmarkSettings;
        _summaries = benchmark.config.fixtures;
        _catalogMs = 0;
      });
      await _select(
        benchmark.config.fixtures.first,
        settings: benchmarkSettings,
        phase: 'initial',
      );
      return;
    }
    setState(() => _settings = loadedSettings);
    await _refreshCatalog(loadedSettings);
  }

  Future<void> _refreshCatalog(
    ChatHistorySettings settings, {
    String? preferredId,
  }) async {
    try {
      final limit = settings.recentChatLimit;
      final home = _home;
      final result = await compute(_loadCatalog, (home: home, limit: limit));
      if (!mounted) {
        return;
      }
      final initialId = settings.restoreSelection
          ? preferredId ?? settings.selectedId
          : null;
      ChatSummary? initial;
      for (final summary in result.summaries) {
        if (summary.id == initialId) {
          initial = summary;
          break;
        }
      }
      initial ??= result.summaries.firstOrNull;
      if (initial == null) {
        _selectionGeneration += 1;
      }
      setState(() {
        _catalogError = null;
        _catalogMs = result.nativeTotalMs;
        if (initial == null) {
          _selection = null;
        }
        _summaries = result.summaries;
      });
      if (initial != null) {
        await _select(initial, settings: settings);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _catalogError = error.toString());
      }
    }
  }

  Future<void> _select(
    ChatSummary summary, {
    ChatHistorySettings? settings,
    String? phase,
  }) async {
    final generation = ++_selectionGeneration;
    final openedAt = Stopwatch()..start();
    final activeSettings = settings ?? _settings;
    final nextSettings = activeSettings.copyWith(
      selectedId: summary.id,
      clearSelectedId: !activeSettings.restoreSelection,
    );
    setState(() {
      _selection = _Selection(id: summary.id, openedAt: openedAt, phase: phase);
      _settings = nextSettings;
    });
    if (phase == null) {
      unawaited(_settingsStore.write(nextSettings));
    }
    try {
      final provider = summary.provider;
      final path = summary.path;
      final document = await _parserWorker.parse(provider, path);
      if (!mounted || generation != _selectionGeneration) {
        return;
      }
      setState(() {
        _selection = _Selection(
          id: summary.id,
          document: document,
          openedAt: openedAt,
          phase: phase,
        );
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_reportContentReady(generation));
      });
    } catch (error) {
      stderr.writeln('Chat load failed for ${summary.path}: $error');
      final benchmark = _benchmark;
      if (benchmark != null) {
        unawaited(
          benchmark.emit(<String, dynamic>{
            'message': error.toString(),
            'name': 'contentError',
            'path': summary.path,
            'phase': phase,
          }),
        );
      }
      if (mounted && generation == _selectionGeneration) {
        setState(() {
          _selection = _Selection(id: summary.id, error: error.toString());
        });
      }
    }
  }

  Future<void> _reportContentReady(int generation) async {
    await WidgetsBinding.instance.endOfFrame;
    final selection = _selection;
    final document = selection?.document;
    final openedAt = selection?.openedAt;
    if (!mounted ||
        generation != _selectionGeneration ||
        selection == null ||
        document == null ||
        openedAt == null) {
      return;
    }
    final durationMs = openedAt.elapsedMicroseconds / 1000;
    setState(() => _selection = selection.copyWith(firstPaintMs: durationMs));
    final phase = selection.phase;
    final benchmark = _benchmark;
    if (phase == null || benchmark == null) {
      return;
    }
    await benchmark.emit(<String, dynamic>{
      'durationMs': durationMs,
      'name': 'contentReady',
      'path': document.path,
      'phase': phase,
      'recordCount': document.recordCount,
      'rowCount': document.rows.length,
      'sourceBytes': document.sourceBytes,
      'timing': document.timing.toJson(),
    });
    unawaited(
      _contentDigestInBackground(document.rows).then(
        (digest) => benchmark.emit(<String, dynamic>{
          'contentDigest': digest,
          'name': 'contentDigest',
          'path': document.path,
          'phase': phase,
        }),
      ),
    );
    if (phase == 'initial') {
      await Future<void>.delayed(
        Duration(milliseconds: benchmark.config.switchDelayMs),
      );
      if (mounted && generation == _selectionGeneration) {
        await _select(
          benchmark.config.fixtures[1],
          settings: _settings,
          phase: 'switch',
        );
      }
    }
  }

  Future<void> _showSettings() async {
    var draft = _settings;
    final result = await showDialog<ChatHistorySettings>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Settings'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _SettingsChoice<ChatAppearance>(
                  label: 'Appearance',
                  value: draft.appearance,
                  values: ChatAppearance.values,
                  labelFor: (value) => switch (value) {
                    ChatAppearance.dark => 'Dark',
                    ChatAppearance.light => 'Light',
                    ChatAppearance.system => 'System',
                  },
                  onChanged: (value) => setDialogState(
                    () => draft = draft.copyWith(appearance: value),
                  ),
                ),
                _SettingsChoice<int>(
                  label: 'Recent chats',
                  value: draft.recentChatLimit,
                  values: const <int>[20, 50, 100],
                  labelFor: (value) => '$value',
                  onChanged: (value) => setDialogState(
                    () => draft = draft.copyWith(recentChatLimit: value),
                  ),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Restore the last selected chat'),
                  value: draft.restoreSelection,
                  onChanged: (value) => setDialogState(
                    () => draft = draft.copyWith(restoreSelection: value),
                  ),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Load attached images'),
                  value: draft.loadImages,
                  onChanged: (value) => setDialogState(
                    () => draft = draft.copyWith(loadImages: value),
                  ),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Show performance metrics'),
                  value: draft.showPerformanceMetrics,
                  onChanged: (value) => setDialogState(
                    () => draft = draft.copyWith(showPerformanceMetrics: value),
                  ),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, draft),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (result == null || !mounted) {
      return;
    }
    final limitChanged = result.recentChatLimit != _settings.recentChatLimit;
    setState(() => _settings = result);
    await _settingsStore.write(result);
    if (limitChanged) {
      await _refreshCatalog(result, preferredId: _selection?.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: _themeMode,
      home: Scaffold(
        body: Row(
          children: <Widget>[
            SizedBox(
              width: 260,
              child: _Sidebar(
                onSelect: (summary) => unawaited(_select(summary)),
                selectedId: _selection?.id,
                summaries: _summaries,
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: _Content(
                catalogError: _catalogError,
                catalogMs: _catalogMs,
                onOpenSettings: _showSettings,
                selection: _selection,
                settings: _settings,
                summaries: _summaries,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

ThemeData _theme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  return ThemeData(
    brightness: brightness,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xff0878d1),
      brightness: brightness,
    ),
    dividerColor: isDark ? const Color(0xff3a3a3c) : const Color(0xffd2d2d7),
    scaffoldBackgroundColor: isDark ? const Color(0xff1c1c1e) : Colors.white,
    fontFamily: '.AppleSystemUIFont',
    useMaterial3: true,
  );
}

class _SettingsChoice<T> extends StatelessWidget {
  const _SettingsChoice({
    required this.label,
    required this.labelFor,
    required this.onChanged,
    required this.value,
    required this.values,
  });

  final String label;
  final String Function(T value) labelFor;
  final ValueChanged<T> onChanged;
  final T value;
  final List<T> values;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label)),
          DropdownButton<T>(
            value: value,
            items: values
                .map(
                  (item) => DropdownMenuItem<T>(
                    value: item,
                    child: Text(labelFor(item)),
                  ),
                )
                .toList(growable: false),
            onChanged: (next) {
              if (next != null) {
                onChanged(next);
              }
            },
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.onSelect,
    required this.selectedId,
    required this.summaries,
  });

  final ValueChanged<ChatSummary> onSelect;
  final String? selectedId;
  final List<ChatSummary> summaries;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ColoredBox(
      color: isDark ? const Color(0xff252528) : const Color(0xffececef),
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: <Widget>[
          for (final provider in <ChatProvider>[
            ChatProvider.codex,
            ChatProvider.claude,
          ]) ...<Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 14, 8, 8),
              child: Text(
                provider == ChatProvider.codex ? 'Codex' : 'Claude',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            for (final summary in summaries.where(
              (summary) => summary.provider == provider,
            ))
              _SidebarRow(
                onTap: () => onSelect(summary),
                selected: selectedId == summary.id,
                summary: summary,
              ),
          ],
        ],
      ),
    );
  }
}

class _SidebarRow extends StatelessWidget {
  const _SidebarRow({
    required this.onTap,
    required this.selected,
    required this.summary,
  });

  final VoidCallback onTap;
  final bool selected;
  final ChatSummary summary;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected ? const Color(0xff5e9fec) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: SizedBox(
            height: 34,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      summary.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selected ? Colors.white : null,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _relativeDate(summary.updatedAt),
                    style: TextStyle(
                      color: selected
                          ? Colors.white.withValues(alpha: 0.68)
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _relativeDate(int timestamp) {
  final minutes = DateTime.now()
      .difference(DateTime.fromMillisecondsSinceEpoch(timestamp))
      .inMinutes
      .clamp(0, 1 << 31);
  if (minutes < 1) return 'now';
  if (minutes < 60) return '${minutes}m';
  final hours = minutes ~/ 60;
  if (hours < 24) return '${hours}h';
  final days = hours ~/ 24;
  if (days < 7) return '${days}d';
  final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
  return '${date.month}/${date.day}';
}

class _Content extends StatelessWidget {
  const _Content({
    required this.catalogError,
    required this.catalogMs,
    required this.onOpenSettings,
    required this.selection,
    required this.settings,
    required this.summaries,
  });

  final String? catalogError;
  final double? catalogMs;
  final VoidCallback onOpenSettings;
  final _Selection? selection;
  final ChatHistorySettings settings;
  final List<ChatSummary> summaries;

  @override
  Widget build(BuildContext context) {
    final selectedTitle = summaries
        .where((summary) => summary.id == selection?.id)
        .firstOrNull
        ?.title;
    return Column(
      children: <Widget>[
        SizedBox(
          height: 46,
          child: Padding(
            padding: const EdgeInsets.only(left: 18, right: 10),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    selectedTitle ?? 'Legend Chat History',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  catalogMs == null
                      ? 'Loading catalog…'
                      : 'catalog ${catalogMs!.toStringAsFixed(2)} ms',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'Settings',
                  onPressed: onOpenSettings,
                  icon: const Icon(Icons.settings_outlined, size: 19),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(child: _body(context)),
      ],
    );
  }

  Widget _body(BuildContext context) {
    if (catalogError != null) {
      return _CenteredStatus(catalogError!, error: true);
    }
    final current = selection;
    if (current == null) {
      if (catalogMs == null) {
        return const _CenteredStatus('Scanning recent chats…');
      }
      if (summaries.isEmpty) {
        return const _CenteredStatus(
          'No local Codex or Claude transcripts found.',
        );
      }
      return const _CenteredStatus('Select a conversation');
    }
    if (current.isLoading) {
      return const _CenteredStatus('Loading and parsing in a Dart isolate…');
    }
    if (current.error != null) {
      return _CenteredStatus(current.error!, error: true);
    }
    return _Transcript(
      document: current.document!,
      firstPaintMs: current.firstPaintMs,
      settings: settings,
    );
  }
}

class _CenteredStatus extends StatelessWidget {
  const _CenteredStatus(this.message, {this.error = false});

  final bool error;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        message,
        style: TextStyle(
          color: error
              ? Theme.of(context).colorScheme.error
              : Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _Transcript extends StatelessWidget {
  const _Transcript({
    required this.document,
    required this.firstPaintMs,
    required this.settings,
  });

  final ChatDocument document;
  final double? firstPaintMs;
  final ChatHistorySettings settings;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        if (settings.showPerformanceMetrics)
          _Timing(document: document, firstPaintMs: firstPaintMs),
        Expanded(
          child: SelectionArea(
            child: ListView.builder(
              key: ValueKey<String>(document.path),
              scrollCacheExtent: const ScrollCacheExtent.pixels(500),
              reverse: true,
              itemCount: document.rows.length,
              itemBuilder: (context, index) {
                final row = document.rows[document.rows.length - 1 - index];
                return Center(
                  key: ValueKey<String>(row.id),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 860),
                    child: _TranscriptRow(
                      loadImages: settings.loadImages,
                      row: row,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _Timing extends StatelessWidget {
  const _Timing({required this.document, required this.firstPaintMs});

  final ChatDocument document;
  final double? firstPaintMs;

  @override
  Widget build(BuildContext context) {
    final timing = document.timing;
    final values = <String>[
      '${(document.sourceBytes / 1024).toStringAsFixed(1)} KB',
      '${document.recordCount} records',
      '${document.rows.length} rows',
      'load ${timing.loadMs.toStringAsFixed(2)} ms',
      'scan ${timing.scanMs.toStringAsFixed(2)} ms',
      'parse ${timing.parseMs.toStringAsFixed(2)} ms',
      'bridge 0.00 ms',
      firstPaintMs == null
          ? 'paint pending'
          : 'paint ${firstPaintMs!.toStringAsFixed(2)} ms',
    ];
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: SizedBox(
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          child: Wrap(
            spacing: 14,
            runSpacing: 5,
            children: values
                .map(
                  (value) => Text(
                    value,
                    style: const TextStyle(fontFamily: 'SF Mono', fontSize: 11),
                  ),
                )
                .toList(growable: false),
          ),
        ),
      ),
    );
  }
}

class _TranscriptRow extends StatelessWidget {
  const _TranscriptRow({required this.loadImages, required this.row});

  final bool loadImages;
  final ChatRow row;

  @override
  Widget build(BuildContext context) {
    return switch (row.kind) {
      ChatRowKind.files => _FileChangesRow(row: row),
      ChatRowKind.tool => _ToolRow(row: row),
      ChatRowKind.assistant ||
      ChatRowKind.user => _MessageRow(loadImages: loadImages, row: row),
    };
  }
}

class _MessageRow extends StatelessWidget {
  const _MessageRow({required this.loadImages, required this.row});

  final bool loadImages;
  final ChatRow row;

  @override
  Widget build(BuildContext context) {
    final isUser = row.kind == ChatRowKind.user;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (loadImages)
          for (final source in row.imageSources)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _MessageImage(source: source),
            ),
        if (row.markdown.isNotEmpty)
          MarkdownBody(
            data: row.markdown,
            imageBuilder: (uri, title, alt) => loadImages
                ? _MessageImage(source: uri.toString())
                : const _Attachment('Image or attachment omitted'),
            onTapLink: (_, href, _) {
              if (href != null) {
                unawaited(launchUrl(Uri.parse(href)));
              }
            },
            styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context))
                .copyWith(
                  p: const TextStyle(height: 1.55),
                  code: TextStyle(
                    backgroundColor: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                    fontFamily: 'SF Mono',
                    fontSize: 13,
                  ),
                  codeblockDecoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(7),
                  ),
                ),
          ),
        if (row.hasImagePlaceholder ||
            (!loadImages && row.imageSources.isNotEmpty))
          const _Attachment('Image or attachment omitted'),
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
      child: Row(
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: <Widget>[
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: isUser ? 705 : 790),
              child: isUser
                  ? DecoratedBox(
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        child: content,
                      ),
                    )
                  : content,
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageImage extends StatelessWidget {
  const _MessageImage({required this.source});

  final String source;

  @override
  Widget build(BuildContext context) {
    Widget image;
    final uri = Uri.tryParse(source);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      image = Image.network(source, errorBuilder: _imageError);
    } else if (uri != null && uri.scheme == 'data') {
      try {
        final comma = source.indexOf(',');
        image = Image.memory(
          base64Decode(source.substring(comma + 1)),
          errorBuilder: _imageError,
        );
      } on FormatException {
        image = const _Attachment('Image or attachment unavailable');
      }
    } else {
      final path = uri?.scheme == 'file' ? uri!.toFilePath() : source;
      image = Image.file(File(path), errorBuilder: _imageError);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 440, maxWidth: 560),
        child: image,
      ),
    );
  }

  Widget _imageError(BuildContext context, Object error, StackTrace? stack) {
    return const _Attachment('Image or attachment unavailable');
  }
}

class _Attachment extends StatelessWidget {
  const _Attachment(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );
  }
}

class _ToolRow extends StatelessWidget {
  const _ToolRow({required this.row});

  final ChatRow row;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
      child: ExpansionTile(
        key: PageStorageKey<String>(row.id),
        dense: true,
        shape: const Border(),
        title: Text(
          row.toolName,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        children: row.toolPreview.isEmpty
            ? const <Widget>[]
            : <Widget>[
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: SelectableText(
                    row.toolPreview,
                    style: const TextStyle(fontFamily: 'SF Mono', fontSize: 12),
                  ),
                ),
              ],
      ),
    );
  }
}

class _FileChangesRow extends StatefulWidget {
  const _FileChangesRow({required this.row});

  final ChatRow row;

  @override
  State<_FileChangesRow> createState() => _FileChangesRowState();
}

class _FileChangesRowState extends State<_FileChangesRow> {
  var _expanded = false;

  @override
  Widget build(BuildContext context) {
    final files = widget.row.fileChanges;
    final visible = _expanded ? files : files.take(3).toList(growable: false);
    final additions = files.fold<int>(0, (sum, file) => sum + file.additions);
    final deletions = files.fold<int>(0, (sum, file) => sum + file.deletions);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: <Widget>[
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('+', style: TextStyle(fontSize: 22)),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Edited ${files.length} ${files.length == 1 ? 'file' : 'files'}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text.rich(
                      TextSpan(
                        children: <InlineSpan>[
                          TextSpan(
                            text: '+$additions',
                            style: const TextStyle(color: Color(0xff16843c)),
                          ),
                          const TextSpan(text: '  '),
                          TextSpan(
                            text: '−$deletions',
                            style: const TextStyle(color: Color(0xffc22f2f)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          for (final file in visible)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      file.path,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '+${file.additions}',
                    style: const TextStyle(color: Color(0xff16843c)),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '−${file.deletions}',
                    style: const TextStyle(color: Color(0xffc22f2f)),
                  ),
                ],
              ),
            ),
          if (files.length > 3)
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => setState(() => _expanded = !_expanded),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _expanded
                        ? 'Show less'
                        : 'Show ${files.length - 3} more files',
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
