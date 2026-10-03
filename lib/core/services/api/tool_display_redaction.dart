import 'dart:async';

/// The display filter for the tool call's launch. Execution arguments are never
/// changed; approval requests and activity logs make their own filtered copies.
class ToolDisplayRedaction {
  const ToolDisplayRedaction({required this.text, required this.value});

  final String Function(String) text;
  final Object? Function(Object?) value;
  static final Object _key = Object();
  static ToolDisplayRedaction? get current =>
      Zone.current[_key] as ToolDisplayRedaction?;

  Future<T> run<T>(Future<T> Function() action) =>
      runZoned(action, zoneValues: {_key: this});
}
