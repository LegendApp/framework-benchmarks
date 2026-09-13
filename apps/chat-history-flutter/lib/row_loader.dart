import 'dart:async';

import 'model.dart';
import 'parser_worker.dart';

class RowLoader {
  RowLoader(this.document, this.worker);
  final ChatDocument document;
  final ChatParserWorker worker;
  final _cache = <int, Future<ChatRow>>{};
  final _pending = <int, Completer<ChatRow>>{};
  var outstanding = 0;
  Object? error;
  Future<ChatRow> get(int index) => _cache.putIfAbsent(index, () {
    if (!document.rows[index].deferred) {
      return Future.value(document.rows[index]);
    }
    final completer = Completer<ChatRow>();
    _pending[index] = completer;
    outstanding++;
    if (_pending.length == 1) scheduleMicrotask(_flush);
    return completer.future;
  });
  void _flush() {
    final requests = _pending.entries.toList();
    _pending.clear();
    for (var start = 0; start < requests.length; start += 256) {
      final batch = requests.sublist(
        start,
        (start + 256).clamp(0, requests.length),
      );
      unawaited(
        worker
            .getRows(
              document.documentId!,
              batch.map((entry) => entry.key).toList(),
            )
            .then((rows) {
              if (rows.length != batch.length) {
                throw StateError('Incomplete viewport row response');
              }
              for (var i = 0; i < batch.length; i++) {
                batch[i].value.complete(rows[i]);
              }
            })
            .catchError((Object reason) {
              error = reason;
              for (final entry in batch) {
                entry.value.completeError(reason);
              }
            })
            .whenComplete(() => outstanding -= batch.length),
      );
    }
  }
}
