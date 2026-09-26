import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../database/business_preferences.dart';
import '../../utils/token_estimator.dart';

/// Today's background memory calls (gatekeeper, extract, smart add,
/// profile), counted so the settings can show what memory costs. Counting
/// only: it never changes what is sent. Tokens are estimates.
class MemoryUsageMeter extends ChangeNotifier {
  MemoryUsageMeter({required this._preferences, DateTime Function()? now})
    : _now = now ?? DateTime.now {
    try {
      final raw = _preferences.getString(storageKey);
      if (raw != null) {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        _day = json['day'] as String? ?? '';
        _calls = json['calls'] as int? ?? 0;
        _input = json['input'] as int? ?? 0;
        _output = json['output'] as int? ?? 0;
      }
    } catch (_) {
      // A damaged value starts today's count over.
    }
  }

  static const String storageKey = 'memory_usage_today_v1';

  final BusinessPreferences _preferences;
  final DateTime Function() _now;
  String _day = '';
  int _calls = 0;
  int _input = 0;
  int _output = 0;

  String get _today {
    final d = _now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }

  /// Calls and estimated tokens sent and received today.
  ({int calls, int input, int output}) get today => _day == _today
      ? (calls: _calls, input: _input, output: _output)
      : (calls: 0, input: 0, output: 0);

  void record({required String prompt, required String response}) {
    final day = _today;
    if (_day != day) {
      _day = day;
      _calls = 0;
      _input = 0;
      _output = 0;
    }
    _calls++;
    _input += estimateTokens(prompt);
    _output += estimateTokens(response);
    unawaited(
      _preferences.setString(
        storageKey,
        jsonEncode({
          'day': _day,
          'calls': _calls,
          'input': _input,
          'output': _output,
        }),
      ),
    );
    notifyListeners();
  }
}
