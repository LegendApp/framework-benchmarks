import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:url_launcher/url_launcher.dart';

import 'benchmark.dart';
import 'catalog.dart';
import 'model.dart';
import 'parser_worker.dart';
import 'row_loader.dart';
import 'markdown_style.dart';

import 'dart:ui' show ImageFilter;

import 'settings.dart';

CatalogResult _loadCatalog(({String home, int limit}) request) {
  return getRecentChats(request.limit, request.home);
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
  final String _home =
      (Platform.environment.containsKey('CHAT_HISTORY_BENCHMARK_CONFIG')
          ? Platform.environment['CHAT_HISTORY_BENCHMARK_HOME']
          : null) ??
      Platform.environment['HOME'] ??
      '';
  final GlobalKey<_TranscriptState> _transcriptKey =
      GlobalKey<_TranscriptState>();

  ChatBenchmark? _benchmark;
  double? _benchmarkDiscoveryMs;
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
        appearance: benchmark.config.appearance,
        loadImages: benchmark.config.loadImages,
        restoreSelection: false,
      );
      final home = _home;
      final discoveryStopwatch = Stopwatch()..start();
      final result = await compute(_loadCatalog, (
        home: home,
        limit: 0x7fffffff,
      ));
      discoveryStopwatch.stop();
      final targets = benchmark.config.targets
          .map(
            (target) => result.summaries
                .where(
                  (summary) =>
                      summary.id == target.id &&
                      summary.provider == target.provider,
                )
                .firstOrNull,
          )
          .toList(growable: false);
      if (targets.any((target) => target == null)) {
        throw StateError(
          'A pinned benchmark chat was not found during native history discovery',
        );
      }
      final resolvedTargets = targets.cast<ChatSummary>();
      final visible = result.summaries
          .take(benchmarkSettings.recentChatLimit)
          .toList();
      for (final target in resolvedTargets) {
        if (!visible.any((summary) => summary.id == target.id)) {
          visible.add(target);
        }
      }
      setState(() {
        _benchmark = benchmark;
        _benchmarkDiscoveryMs = discoveryStopwatch.elapsedMicroseconds / 1000;
        _settings = benchmarkSettings;
        _summaries = visible;
        _catalogMs = result.nativeTotalMs;
      });
      await _select(
        resolvedTargets.first,
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
    await _transcriptKey.currentState?.settleTail();
    if (!mounted || generation != _selectionGeneration) return;
    final durationMs = openedAt.elapsedMicroseconds / 1000;
    setState(() => _selection = selection.copyWith(firstPaintMs: durationMs));
    final phase = selection.phase;
    final benchmark = _benchmark;
    if (phase == null || benchmark == null) {
      return;
    }
    await benchmark.emit(<String, dynamic>{
      if (phase == 'initial') 'discoveryMs': _benchmarkDiscoveryMs,
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
      _parserWorker
          .getContentDigest(document.documentId!)
          .then(
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
        Duration(milliseconds: benchmark.config.topDelayMs),
      );
      if (mounted && generation == _selectionGeneration) {
        final topDurationMs = await _transcriptKey.currentState?.jumpToTop();
        if (topDurationMs == null) return;
        await benchmark.emit(<String, dynamic>{
          'durationMs': topDurationMs,
          'name': 'viewportReady',
          'path': document.path,
          'phase': 'top',
        });
        await Future<void>.delayed(
          Duration(milliseconds: benchmark.config.switchDelayMs),
        );
      }
      if (mounted && generation == _selectionGeneration) {
        final target = benchmark.config.targets[1];
        final summary = _summaries
            .where(
              (item) =>
                  item.id == target.id && item.provider == target.provider,
            )
            .firstOrNull;
        if (summary != null) {
          await _select(summary, settings: _settings, phase: 'switch');
        }
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
        backgroundColor: Colors.transparent,
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
            Expanded(
              child: _Content(
                worker: _parserWorker,
                catalogError: _catalogError,
                catalogMs: _catalogMs,
                onOpenSettings: _showSettings,
                selection: _selection,
                settings: _settings,
                summaries: _summaries,
                transcriptKey: _transcriptKey,
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
    colorScheme:
        ColorScheme.fromSeed(
          seedColor: const Color(0xff0878d1),
          brightness: brightness,
        ).copyWith(
          surface: isDark ? const Color(0xff242526) : Colors.white,
          surfaceContainerHighest: isDark
              ? const Color(0xff2d2e30)
              : const Color(0xfff3f4f6),
          surfaceContainerHigh: isDark
              ? const Color(0xff111213)
              : const Color(0xff111827),
          onSurface: isDark ? const Color(0xfff5f5f5) : const Color(0xff111827),
          onSurfaceVariant: isDark
              ? const Color(0xffa3a3a3)
              : const Color(0xff6b7280),
        ),
    dividerColor: isDark ? const Color(0xff3e4042) : const Color(0xffd1d5db),
    scaffoldBackgroundColor: isDark
        ? const Color(0xff191a1b)
        : const Color(0xfff5f6f8),
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
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 8, 0, 8),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: ColoredBox(
        color: (isDark ? const Color(0xff242526) : Colors.white).withValues(
          alpha: 0.7,
        ),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(8, 44, 8, 0),
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
      padding: EdgeInsets.zero,
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
    required this.worker,
    required this.catalogError,
    required this.catalogMs,
    required this.onOpenSettings,
    required this.selection,
    required this.settings,
    required this.summaries,
    required this.transcriptKey,
  });

  final ChatParserWorker worker;
  final String? catalogError;
  final double? catalogMs;
  final VoidCallback onOpenSettings;
  final _Selection? selection;
  final ChatHistorySettings settings;
  final List<ChatSummary> summaries;
  final GlobalKey<_TranscriptState> transcriptKey;

  @override
  Widget build(BuildContext context) {
    final selectedTitle = summaries
        .where((summary) => summary.id == selection?.id)
        .firstOrNull
        ?.title;
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        Positioned.fill(
          child: ColoredBox(
            color: Theme.of(context).scaffoldBackgroundColor,
            child: _body(context),
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: Container(
                height: 52,
                color: Theme.of(context).colorScheme.surface
                    .withValues(alpha: 0.8),
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
                      if (settings.showPerformanceMetrics)
                        Text(
                          catalogMs == null
                              ? 'Loading catalog…'
                              : 'catalog ${catalogMs!.toStringAsFixed(2)} ms',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
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
            ),
          ),
        ),
        Positioned(
          left: 20,
          right: 20,
          bottom: 20,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 860),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(26),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                  child: Container(
                    height: 60,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface
                          .withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(26),
                      border: Border.all(color: Theme.of(context).dividerColor),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            "Send a test message that doesn't actually do anything",
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                        ),
                        Container(
                          width: 36,
                          height: 36,
                          decoration: const BoxDecoration(
                            color: Color(0x4d60a5fa),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.arrow_upward,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
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
      worker: worker,
      key: transcriptKey,
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

class _Transcript extends StatefulWidget {
  const _Transcript({
    required this.worker,
    super.key,
    required this.document,
    required this.firstPaintMs,
    required this.settings,
  });

  final ChatParserWorker worker;
  final ChatDocument document;
  final double? firstPaintMs;
  final ChatHistorySettings settings;

  @override
  State<_Transcript> createState() => _TranscriptState();
}

class _TranscriptState extends State<_Transcript> {
  late RowLoader _loader = RowLoader(widget.document, widget.worker);
  Future<void> _waitRows() async {
    for (var attempt = 0; attempt < 1800; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 16));
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      if (_loader.error != null) {
        throw StateError('Viewport row load failed: ${_loader.error}');
      }
      if (_loader.outstanding == 0) return;
    }
    throw StateError('Viewport rows did not finish loading');
  }

  Future<void> settleTail() async {
    if (widget.document.rows.isEmpty) return;
    final target = widget.document.rows.length - 1;
    for (var attempt = 0; attempt < 120; attempt++) {
      await _waitRows();
      if (!mounted) return;
      final position = _positions.itemPositions.value
          .where((item) => item.index == target)
          .firstOrNull;
      if (position != null) {
        if ((position.itemTrailingEdge - 1).abs() < 0.005) {
          await _waitRows();
          return;
        }
        _scrollController.jumpTo(
          index: target,
          alignment: 1 - (position.itemTrailingEdge - position.itemLeadingEdge),
        );
      }
      await WidgetsBinding.instance.endOfFrame;
    }
    throw StateError('Flutter list did not settle at the transcript tail');
  }

  late ItemPositionsListener _positions = ItemPositionsListener.create();
  late ItemScrollController _scrollController = ItemScrollController();

  @override
  void didUpdateWidget(covariant _Transcript oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.document.path != widget.document.path) {
      _loader = RowLoader(widget.document, widget.worker);
      _positions = ItemPositionsListener.create();
      _scrollController = ItemScrollController();
    }
  }

  Future<double> jumpToTop() async {
    final startedAt = Stopwatch()..start();
    const target = 0;
    _scrollController.jumpTo(index: target);
    for (var attempt = 0; attempt < 120; attempt += 1) {
      await WidgetsBinding.instance.endOfFrame;
      if (_positions.itemPositions.value.any(
        (position) =>
            position.index == target && position.itemLeadingEdge.abs() < 0.01,
      )) {
        await _waitRows();
        return startedAt.elapsedMicroseconds / 1000;
      }
    }
    throw StateError('Flutter indexed list did not reach the first chat row');
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        if (widget.settings.showPerformanceMetrics)
          _Timing(document: widget.document, firstPaintMs: widget.firstPaintMs),
        Expanded(
          child: SelectionArea(
            child: ScrollablePositionedList.builder(
              initialScrollIndex: widget.document.rows.isEmpty
                  ? 0
                  : widget.document.rows.length - 1,
              itemPositionsListener: _positions,
              itemScrollController: _scrollController,
              key: ValueKey<String>(widget.document.path),
              itemCount: widget.document.rows.length,
              itemBuilder: (context, index) {
                final row = widget.document.rows[index];
                return Padding(
                  key: ValueKey<String>(row.id),
                  padding: EdgeInsets.only(
                    top: index == 0 ? 64 : 0,
                    bottom: index == widget.document.rows.length - 1 ? 112 : 0,
                  ),
                  child: FutureBuilder<ChatRow>(
                    future: _loader.get(index),
                    builder: (context, snapshot) => snapshot.hasError
                        ? Text('Could not load row: ${snapshot.error}')
                        : snapshot.hasData
                        ? _TranscriptRow(
                            loadImages: widget.settings.loadImages,
                            row: snapshot.data!,
                            loadPreview: () async =>
                                (await widget.worker.getRows(
                                  widget.document.documentId!,
                                  [index],
                                  includeToolPreview: true,
                                )).first.toolPreview,
                          )
                        : const SizedBox(height: 180),
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
                    style: const TextStyle(fontFamily: 'Menlo', fontSize: 11),
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
  const _TranscriptRow({
    required this.loadImages,
    required this.row,
    this.loadPreview,
  });
  final Future<String> Function()? loadPreview;

  final bool loadImages;
  final ChatRow row;

  @override
  Widget build(BuildContext context) {
    return switch (row.kind) {
      ChatRowKind.files => _FileChangesRow(row: row),
      ChatRowKind.tool => _ToolRow(row: row, loadPreview: loadPreview),
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
            builders: {'pre': CodePaneBuilder()},
            imageBuilder: (uri, title, alt) => loadImages
                ? _MessageImage(source: uri.toString())
                : const _Attachment('Image or attachment omitted'),
            onTapLink: (_, href, _) {
              if (href != null) {
                unawaited(launchUrl(Uri.parse(href)));
              }
            },
            styleSheet: transcriptMarkdownStyle(Theme.of(context)),
          ),
        if (row.hasImagePlaceholder ||
            (!loadImages && row.imageSources.isNotEmpty))
          const _Attachment('Image or attachment omitted'),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) => Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 20,
          vertical: isUser ? 8 : 12,
        ),
        child: Row(
          mainAxisAlignment: isUser
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          children: <Widget>[
            Flexible(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth:
                      (constraints.maxWidth - 40) * (isUser ? 0.82 : 0.92),
                ),
                child: isUser
                    ? DecoratedBox(
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          child: content,
                        ),
                      )
                    : SizedBox(
                        width: (constraints.maxWidth - 40) * 0.92,
                        child: content,
                      ),
              ),
            ),
          ],
        ),
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

class _ToolRow extends StatefulWidget {
  const _ToolRow({required this.row, this.loadPreview});
  final ChatRow row;
  final Future<String> Function()? loadPreview;
  @override
  State<_ToolRow> createState() => _ToolRowState();
}

class _ToolRowState extends State<_ToolRow> {
  bool _expanded = false;
  Future<String>? _preview;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
    child: Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() {
              _expanded = !_expanded;
              if (_expanded) {
                _preview ??=
                    widget.loadPreview?.call() ??
                    Future.value(widget.row.toolPreview);
              }
            }),
            child: Row(
              children: [
                Text(
                  widget.row.toolName,
                  style: TextStyle(
                    fontSize: 14,
                    height: 20 / 14,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _expanded ? '⌄' : '›',
                  style: const TextStyle(fontSize: 18, height: 20 / 18),
                ),
              ],
            ),
          ),
          if (_expanded)
            FutureBuilder<String>(
              future: _preview,
              builder: (context, snapshot) => Padding(
                padding: const EdgeInsets.only(top: 16),
                child: SelectableText(
                  snapshot.data ??
                      (snapshot.hasError ? 'Could not load preview' : ''),
                  style: const TextStyle(fontSize: 14, height: 24 / 14),
                ),
              ),
            ),
        ],
      ),
    ),
  );
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
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(16),
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
