import 'package:Kelivo/core/services/browser/browser_site_permissions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<Set<String>> runtimeAsked;
  late BrowserSitePermissions permissions;
  var runtimeGrants = true;

  setUp(() {
    runtimeAsked = [];
    runtimeGrants = true;
    permissions = BrowserSitePermissions(
      requestRuntime: (kinds) async {
        runtimeAsked.add(kinds);
        return runtimeGrants;
      },
    );
  });

  test('nothing is granted while no browser page can ask the user', () async {
    expect(await permissions.decide('https://meet.example', {'camera'}), false);
    expect(runtimeAsked, isEmpty);
  });

  test('the user decides once per site and kind', () async {
    final asked = <(String, Set<String>)>[];
    var answer = true;
    permissions.presenter = (host, kinds) async {
      asked.add((host, kinds));
      return answer;
    };

    expect(
      await permissions.decide('https://www.meet.example/room', {
        'camera',
        'microphone',
      }),
      isTrue,
    );
    expect(asked.single.$1, 'meet.example');
    expect(asked.single.$2, {'camera', 'microphone'});
    expect(runtimeAsked.single, {'camera', 'microphone'});

    // Remembered: no second question for the same site.
    expect(
      await permissions.decide('https://meet.example/other', {'camera'}),
      isTrue,
    );
    expect(asked, hasLength(1));

    // Another site asks on its own; a refusal sticks.
    answer = false;
    expect(
      await permissions.decide('https://ads.example', {'location'}),
      isFalse,
    );
    answer = true;
    expect(
      await permissions.decide('https://ads.example', {'location'}),
      isFalse,
    );
    expect(asked, hasLength(2));

    // A refused kind refuses the whole request.
    expect(
      await permissions.decide('https://ads.example', {'location', 'camera'}),
      isFalse,
    );
  });

  test('Android refusing the app refuses the site', () async {
    permissions.presenter = (_, _) async => true;
    runtimeGrants = false;
    expect(
      await permissions.decide('https://meet.example', {'camera'}),
      isFalse,
    );
  });

  test('pages without a host get nothing', () async {
    permissions.presenter = (_, _) async => true;
    expect(await permissions.decide('about:blank', {'camera'}), isFalse);
    expect(await permissions.decide(null, {'camera'}), isFalse);
  });
}
