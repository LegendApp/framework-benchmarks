import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

/// Positional reads in the parser isolate, retaining at most 512 KiB of bytes.
class FileSource extends ListBase<int> {
  FileSource(String path) : _file = File(path).openSync() {
    try {
      _length = _file.lengthSync();
    } catch (_) {
      _file.closeSync();
      rethrow;
    }
  }
  final RandomAccessFile _file;
  late final int _length;
  static const _blockSize = 64 * 1024;
  final _blocks = <int, Uint8List>{};
  var _start = -1;
  var _current = Uint8List(0);
  var _closed = false;
  @override
  int get length => _length;
  @override
  set length(int value) => throw UnsupportedError('Read-only source');
  @override
  void operator []=(int index, int value) =>
      throw UnsupportedError('Read-only source');
  @override
  int operator [](int index) {
    RangeError.checkValidIndex(index, this, 'index', _length);
    if (_closed) throw StateError('Document source is closed');
    if (index < _start || index >= _start + _current.length) {
      final start = index ~/ _blockSize * _blockSize;
      var block = _blocks[start];
      if (block == null) {
        block = Uint8List((_length - start).clamp(0, _blockSize));
        _file.setPositionSync(start);
        var count = 0;
        while (count < block.length) {
          final n = _file.readIntoSync(block, count, block.length);
          if (n == 0)
            throw FileSystemException(
              'Transcript changed or was truncated while open',
            );
          count += n;
        }
        if (_blocks.length == 8) _blocks.remove(_blocks.keys.first);
        _blocks[start] = block;
      }
      _start = start;
      _current = block;
    }
    return _current[index - _start];
  }

  @override
  Uint8List sublist(int start, [int? end]) {
    final stop = RangeError.checkValidRange(start, end, _length);
    if (_closed) throw StateError('Document source is closed');
    if (start >= _start && stop <= _start + _current.length) {
      return Uint8List.sublistView(_current, start - _start, stop - _start);
    }
    final result = Uint8List(stop - start);
    _file.setPositionSync(start);
    var count = 0;
    while (count < result.length) {
      final n = _file.readIntoSync(result, count, result.length);
      if (n == 0)
        throw FileSystemException(
          'Transcript changed or was truncated while open',
        );
      count += n;
    }
    return result;
  }

  List<int> lineRanges() {
    final ranges = <int>[];
    var start = 0;
    var previous = -1;
    for (var position = 0; position < _length; position += _blockSize) {
      final block = sublist(
        position,
        (position + _blockSize).clamp(0, _length),
      );
      for (var i = 0; i < block.length; i++) {
        final byte = block[i];
        if (byte == 10) {
          final end = position + i - (previous == 13 ? 1 : 0);
          if (end > start) ranges.addAll([start, end]);
          start = position + i + 1;
        }
        previous = byte;
      }
    }
    final end = _length - (previous == 13 ? 1 : 0);
    if (end > start) ranges.addAll([start, end]);
    return ranges;
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _file.closeSync();
    _blocks.clear();
    _current = Uint8List(0);
  }
}
