/// The hero/sidebar silk is driven by the tunnel's throughput rather than a
/// free-running decorative animation.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:singbox_client/ui/brand.dart';
import 'package:singbox_client/ui/theme.dart';

Widget _alone({
  List<int> downlink = const [],
  List<int> uplink = const [],
  bool reduceMotion = false,
}) {
  return MediaQuery(
    data: MediaQueryData(disableAnimations: reduceMotion),
    child: MaterialApp(
      theme: buildAppTheme(Brightness.light),
      home: Scaffold(
        body: SizedBox(
          width: 400,
          height: 300,
          child: SignalArtwork(
            animate: true,
            downlink: downlink,
            uplink: uplink,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('silk starts moving when throughput arrives', (tester) async {
    await tester.pumpWidget(_alone(downlink: const [0]));
    await tester.pump();
    expect(tester.hasRunningAnimations, isFalse);

    await tester.pumpWidget(_alone(downlink: const [32 * 1024]));
    await tester.pump();
    expect(tester.hasRunningAnimations, isTrue);

    await tester.pumpAndSettle();
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('reduced motion keeps the silk still', (tester) async {
    await tester.pumpWidget(
      _alone(downlink: const [32 * 1024], reduceMotion: true),
    );
    await tester.pump();

    expect(tester.hasRunningAnimations, isFalse);
  });
}
