/// Wall-clock marks the stream controller stamps into a tool call's metadata,
/// so a finished reply can tell how long its steps took. Providers read only
/// their own metadata keys, so these never reach a request.
const String kToolStartedAtMsKey = 'moruStartedAtMs';
const String kToolFinishedAtMsKey = 'moruFinishedAtMs';

DateTime? toolTimeOf(Map<String, dynamic>? metadata, String key) {
  final value = metadata?[key];
  return value is int ? DateTime.fromMillisecondsSinceEpoch(value) : null;
}

/// [metadata] with the call's start mark added.
Map<String, dynamic> withToolStart(
  Map<String, dynamic>? metadata,
  DateTime now,
) => <String, dynamic>{
  ...?metadata,
  kToolStartedAtMsKey: now.millisecondsSinceEpoch,
};

/// Result [metadata] carrying over the start mark of [started] and adding
/// the finish mark.
Map<String, dynamic> withToolFinish(
  Map<String, dynamic>? metadata, {
  required Map<String, dynamic>? started,
  required DateTime now,
}) {
  final start = started?[kToolStartedAtMsKey];
  return <String, dynamic>{
    ...?metadata,
    if (start is int) kToolStartedAtMsKey: start,
    kToolFinishedAtMsKey: now.millisecondsSinceEpoch,
  };
}
