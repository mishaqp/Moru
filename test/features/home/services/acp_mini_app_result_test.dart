import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/features/home/services/acp_moru_tools.dart';

void main() {
  for (final status in [
    'permission_required',
    'unsupported',
    'denied',
    'failed',
    'unknown_after_timeout',
  ]) {
    test('ACP reports device $status as an error', () async {
      final result = await AcpMoruTools.result(
        jsonEncode({
          'status': status,
          'message': 'The Android setting was not verified.',
        }),
      );
      expect(result['isError'], true);
    });
  }
  test(
    'opening Android settings is successful without claiming application',
    () async {
      final result = await AcpMoruTools.result(
        jsonEncode({
          'status': 'opened_settings',
          'message': 'Settings opened; no setting changed.',
        }),
      );
      expect(result['isError'], false);
      expect(result['content'], hasLength(1));
      expect(
        (result['content'] as List).single['text'],
        contains('opened_settings'),
      );
    },
  );
}
