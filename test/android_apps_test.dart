import 'package:flutter_test/flutter_test.dart';
import 'package:singbox_client/platform/android_apps.dart';

void main() {
  test('normalizes, deduplicates, and sorts host app records', () {
    final apps = parseInstalledApps([
      {'packageName': 'com.zeta', 'label': ' Zeta '},
      {'packageName': 'com.alpha', 'label': 'Alpha'},
      {'packageName': 'com.zeta', 'label': 'Duplicate'},
      {'packageName': '', 'label': 'Invalid'},
      {'packageName': 'com.blank', 'label': ' '},
      'not an app',
    ]);

    expect(
      apps.map((app) => (app.packageName, app.label)),
      [
        ('com.alpha', 'Alpha'),
        ('com.blank', 'com.blank'),
        ('com.zeta', 'Zeta')
      ],
    );
  });

  test('non-list and malformed records produce an empty list', () {
    expect(parseInstalledApps(null), isEmpty);
    expect(parseInstalledApps({'packageName': 'com.example'}), isEmpty);
  });
}
