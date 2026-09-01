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

  Future<ChatDocument> parse(ChatProvider provider, String path) async {
    final responsePort = ReceivePort();
    (await _ready.future).send((responsePort.sendPort, provider, path));
    final response = await responsePort.first;
    responsePort.close();
    final result = response as ({ChatDocument? document, String? error});
    if (result.document case final document?) {
      return document;
    }
    throw FormatException(result.error ?? 'Transcript parsing failed');
  }

  void dispose() {
    _disposed = true;
    _isolate?.kill(priority: Isolate.immediate);
  }

  static void _run(SendPort readyPort) {
    final requests = ReceivePort();
    readyPort.send(requests.sendPort);
    requests.listen((message) {
      final request = message as (SendPort, ChatProvider, String);
      try {
        request.$1.send((
          document: openChatFile(request.$2, request.$3),
          error: null,
        ));
      } catch (error) {
        request.$1.send((document: null, error: error.toString()));
      }
    });
  }
}
