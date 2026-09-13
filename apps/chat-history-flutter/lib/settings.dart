import 'package:shared_preferences/shared_preferences.dart';

import 'model.dart';

class SettingsStore {
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();

  Future<ChatHistorySettings> read() async {
    final appearanceName = await _preferences.getString('appearance');
    final recentChatLimit = await _preferences.getInt('recentChatLimit');
    return ChatHistorySettings(
      appearance:
          ChatAppearance.values
              .where((appearance) => appearance.name == appearanceName)
              .firstOrNull ??
          ChatAppearance.system,
      loadImages: await _preferences.getBool('loadImages') ?? true,
      recentChatLimit: const <int>[20, 50, 100].contains(recentChatLimit)
          ? recentChatLimit!
          : 20,
      restoreSelection: await _preferences.getBool('restoreSelection') ?? true,
      selectedId: await _preferences.getString('selectedId'),
      showPerformanceMetrics:
          await _preferences.getBool('showPerformanceMetrics') ?? false,
    );
  }

  Future<void> write(ChatHistorySettings settings) async {
    await Future.wait(<Future<void>>[
      _preferences.setString('appearance', settings.appearance.name),
      _preferences.setBool('loadImages', settings.loadImages),
      _preferences.setInt('recentChatLimit', settings.recentChatLimit),
      _preferences.setBool('restoreSelection', settings.restoreSelection),
      _preferences.setBool(
        'showPerformanceMetrics',
        settings.showPerformanceMetrics,
      ),
      settings.selectedId == null
          ? _preferences.remove('selectedId')
          : _preferences.setString('selectedId', settings.selectedId!),
    ]);
  }
}
