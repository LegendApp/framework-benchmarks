import 'dart:async';
import 'dart:isolate';

import 'model.dart';
import 'parser.dart';

class ChatParserWorker {
  ChatParserWorker() {
    unawaited(_start());
  }

  final Completer<SendPort> _ready = Completer<SendPort>();
  Isolate? _isolate;
  var _disposed = false;

  Future<void> _start() async {
    final readyPort = ReceivePort();
    try {
      final isolate = await Isolate.spawn(_run, readyPort.sendPort);
      if (_disposed) {
        isolate.kill(priority: Isolate.immediate);
        return;
      }
      _isolate = isolate;
      _ready.complete(await readyPort.first as SendPort);
    } catch (error, stackTrace) {
      if (!_ready.isCompleted) {
        _ready.completeError(error, stackTrace);
      }
    } finally {
      readyPort.close();
    }
  }

  Future<T> _request<T>(Object request) async {
    final responsePort = ReceivePort();
    (await _ready.future).send((responsePort.sendPort, request));
    final response =
        await responsePort.first as ({Object? value, String? error});
    responsePort.close();
    if (response.error != null) throw FormatException(response.error!);
    return response.value as T;
  }

  Future<ChatDocument> parse(ChatProvider provider, String path) =>
      _request(('open', provider, path));
  Future<List<ChatRow>> getRows(
    String id,
    List<int> indices, {
    bool includeToolPreview = false,
  }) => _request(('rows', id, indices, includeToolPreview));
  Future<String> getContentDigest(String id) => _request(('digest', id));

  void dispose() {
    _disposed = true;
    _isolate?.kill(priority: Isolate.immediate);
  }

  static void _run(SendPort readyPort) {
    final requests = ReceivePort();
    readyPort.send(requests.sendPort);
    ChatDocument? active;
    var generation = 0;
    requests.listen((message) {
      final (SendPort reply, Object request) = message;
      try {
        Object value;
        switch (request) {
          case ('open', ChatProvider provider, String path):
            if (active != null) closeChatDocument(active!);
            active = null;
            generation++;
            final document = openChatFile(provider, path);
            active = document;
            value = ChatDocument(
              documentId: '$generation',
              path: document.path,
              provider: document.provider,
              recordCount: document.recordCount,
              rows: document.rows.map(_descriptor).toList(),
              sourceBytes: document.sourceBytes,
              timing: document.timing,
              warningCount: document.warningCount,
            );
          case ('rows', String id, List<int> indices, bool includeToolPreview):
            if (active == null || id != '$generation') {
              throw StateError('Document is no longer open');
            }
            if (indices.length > 256 ||
                indices.any(
                  (index) => index < 0 || index >= active!.rows.length,
                )) {
              throw RangeError('Invalid row request');
            }
            value = indices
                .map(
                  (index) =>
                      _materialize(active!.rows[index], includeToolPreview),
                )
                .toList();
          case ('digest', String id):
            if (active == null || id != '$generation') {
              throw StateError('Document is no longer open');
            }
            value = normalizedContentDigest(active!.rows);
          default:
            throw const FormatException('Unknown document request');
        }
        reply.send((value: value, error: null));
      } catch (error) {
        reply.send((value: null, error: error.toString()));
      }
    });
  }
}

ChatRow _descriptor(ChatRow row) => ChatRow(
  id: row.id,
  kind: row.kind,
  fileChanges: row.fileChanges,
  hasImagePlaceholder: row.hasImagePlaceholder,
  imageSources: row.imageSources,
  toolName: row.toolName,
  toolStatus: row.toolStatus,
  deferred: true,
);
ChatRow _materialize(ChatRow row, bool includeToolPreview) => ChatRow(
  id: row.id,
  kind: row.kind,
  fileChanges: row.fileChanges,
  hasImagePlaceholder: row.hasImagePlaceholder,
  imageSources: row.imageSources,
  toolName: row.toolName,
  toolStatus: row.toolStatus,
  rawMarkdown: row.markdown,
  rawToolPreview: includeToolPreview ? row.toolPreview : '',
);
