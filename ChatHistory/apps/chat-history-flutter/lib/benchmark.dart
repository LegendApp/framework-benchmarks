import 'dart:convert';
import 'dart:io';

import 'model.dart';

class ChatBenchmark {
  ChatBenchmark._(this.config, this._eventsPath);

  final BenchmarkConfig config;
  final String? _eventsPath;

  static Future<ChatBenchmark?> load() async {
    final configPath = Platform.environment['CHAT_HISTORY_BENCHMARK_CONFIG'];
    if (configPath == null) {
      return null;
    }
    final source = await File(configPath).readAsString();
    return ChatBenchmark._(
      BenchmarkConfig.fromJson(jsonDecode(source) as Map<String, dynamic>),
      Platform.environment['CHAT_HISTORY_BENCHMARK_EVENTS'],
    );
  }

  static Future<void> emitWindowShown() async {
    final eventsPath = Platform.environment['CHAT_HISTORY_BENCHMARK_EVENTS'];
    if (eventsPath == null) {
      return;
    }
    await File(eventsPath).writeAsString(
      '${jsonEncode(<String, dynamic>{'name': 'windowShown', 'timestampMs': DateTime.now().millisecondsSinceEpoch})}\n',
      mode: FileMode.append,
      flush: true,
    );
  }

  Future<void> emit(Map<String, dynamic> event) async {
    final eventsPath = _eventsPath;
    if (eventsPath == null) {
      return;
    }
    await File(eventsPath).writeAsString(
      '${jsonEncode(<String, dynamic>{...event, 'timestampMs': DateTime.now().millisecondsSinceEpoch})}\n',
      mode: FileMode.append,
      flush: true,
    );
  }
}
