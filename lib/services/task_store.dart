import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/task/task.dart';

/// The current competition task and the pilot's progress through it.
class TaskStore extends ChangeNotifier {
  TaskStore._();
  static final instance = TaskStore._();

  static const _key = 'task';
  Task? task;
  TaskProgress? progress;
  String? error;

  Future<void> load() async {
    try {
      final saved = (await SharedPreferences.getInstance()).getString(_key);
      if (saved != null) _set(parseTask(saved));
    } catch (e) {
      debugPrint('task: $e');
    }
    notifyListeners();
  }

  /// Imports an `.xctsk` file or an XCTrack QR code text. Returns false on errors.
  Future<bool> import(String text) async {
    try {
      final t = parseTask(text);
      if (t.turnpoints.isEmpty) throw const FormatException('no turnpoints');
      _set(t);
      error = null;
      await (await SharedPreferences.getInstance()).setString(_key, jsonEncode(t.toJson()));
      notifyListeners();
      return true;
    } catch (e) {
      error = 'Not an XCTrack task: $e';
      notifyListeners();
      return false;
    }
  }

  void _set(Task t) {
    task = t;
    progress = TaskProgress(t);
  }

  /// Progress changed (a turnpoint was reached).
  void changed() => notifyListeners();

  /// Starts the task again (e.g. before a relaunch).
  void restart() {
    if (task != null) progress = TaskProgress(task!);
    notifyListeners();
  }

  Future<void> clear() async {
    task = null;
    progress = null;
    await (await SharedPreferences.getInstance()).remove(_key);
    notifyListeners();
  }
}
