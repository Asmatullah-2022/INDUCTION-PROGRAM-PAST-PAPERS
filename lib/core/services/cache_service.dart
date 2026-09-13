import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Lightweight offline cache for published content (phases, subjects,
/// papers, questions) plus user bookmarks/progress, backed by
/// SharedPreferences. Content here is small (text only — original PDFs
/// are cached separately by the PDF viewer's own disk cache), so a JSON
/// blob per key is sufficient and avoids pulling in a heavier database
/// dependency just for read-mostly cached lists.
class CacheService {
  static SharedPreferences? _prefs;

  static Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  static SharedPreferences get _instance {
    final p = _prefs;
    if (p == null) {
      throw StateError('CacheService.init() must be called before use.');
    }
    return p;
  }

  static Future<void> setJson(String key, Object value) async {
    await _instance.setString(key, jsonEncode(value));
  }

  static T? getJson<T>(String key, T Function(dynamic decoded) decoder) {
    final raw = _instance.getString(key);
    if (raw == null) return null;
    try {
      return decoder(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  static Future<void> remove(String key) => _instance.remove(key);

  static Future<void> setString(String key, String value) =>
      _instance.setString(key, value);

  static String? getString(String key) => _instance.getString(key);

  static Future<void> clearAll() => _instance.clear();
}
