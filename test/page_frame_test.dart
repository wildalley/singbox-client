/// [PageFrame]'s two shapes, and the one that must not scroll.
///
/// The filling shape exists for the log pane: the last child is already a
/// scroller, so it takes the room the header leaves. That makes the header chrome
/// — and chrome that scrolls away from the pane it labels is in the wrong place.
///
/// It did scroll away. A SliverFillRemaining sized to the viewport plus a
/// SliverPadding on top of it gave the outer view exactly the padding's worth of
/// scroll extent: just enough to drag the title out of sight above a log that was
/// scrolling itself underneath.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:singbox_client/ui/theme.dart';
import 'package:singbox_client/ui/widgets.dart';

Widget host(Widget child) => MaterialApp(
      theme: buildAppTheme(Brightness.dark),
      home: Scaffold(body: child),
    );

/// A long inner scroller, so the pane has somewhere to scroll to.
Widget logPane() => ListView.builder(
      itemCount: 400,
      itemBuilder: (context, index) => SizedBox(
        height: 20,
        child: Text('line $index'),
      ),
    );

void main() {
  testWidgets('the filling shape does not scroll its header away',
      (tester) async {
    tester.view.physicalSize = const Size(760, 580);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(
      PageFrame(
        title: 'Logs',
        subtitle: '385 entries',
        fill: true,
        children: [logPane()],
      ),
    ));
    await tester.pumpAndSettle();

    final before = tester.getTopLeft(find.text('Logs'));

    // Drag on the header itself, which is what a user does when reaching for the
    // pane and missing. Nothing above the pane should move.
    await tester.drag(find.text('Logs'), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Logs')), before, reason: 'header moved');

    // And dragging the pane scrolls the pane, not the page.
    await tester.drag(find.text('line 5'), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('Logs')),
      before,
      reason: 'the header followed the pane',
    );
  });

  testWidgets('the filling shape gives the pane the remaining height',
      (tester) async {
    // The reason fill exists at all: the alternative was a hard-coded pixel
    // height, too short on a desktop window and leaving dead space on a phone.
    tester.view.physicalSize = const Size(760, 580);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(
      PageFrame(
        title: 'Logs',
        fill: true,
        children: [logPane()],
      ),
    ));
    await tester.pumpAndSettle();

    final pane = tester.getRect(find.byType(ListView));
    final header = tester.getRect(find.text('Logs'));

    expect(pane.top, greaterThan(header.bottom), reason: 'pane above header');
    // Reaches the bottom padding rather than stopping short.
    expect(pane.bottom, greaterThan(500));
  });

  testWidgets('the normal shape still scrolls everything together',
      (tester) async {
    // The other half: without fill the page owns the scroll and the header goes
    // with it, which is right for a list of cards.
    tester.view.physicalSize = const Size(760, 580);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(
      PageFrame(
        title: 'Settings',
        children: [
          for (var i = 0; i < 40; i++)
            SizedBox(height: 40, child: Text('row $i')),
        ],
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);

    await tester.drag(find.text('row 2'), const Offset(0, -200));
    await tester.pumpAndSettle();

    // Gone from the viewport entirely, rather than measured: a sliver that has
    // scrolled out is no longer in the tree, so there is no position to read.
    expect(
      find.text('Settings'),
      findsNothing,
      reason: 'the header should scroll with the list here',
    );
  });

  testWidgets('a short body is not stretched', (tester) async {
    // fill is only passed when the last child wants the room; the empty state is
    // a short card, and stretching it to the viewport looks like a bug.
    tester.view.physicalSize = const Size(760, 580);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(
      PageFrame(
        title: 'Logs',
        children: [
          SizedBox(height: 90, child: Container(color: const Color(0xFF112233))),
        ],
      ),
    ));
    await tester.pumpAndSettle();

    expect(tester.getRect(find.byType(Container).last).height, 90);
  });
}
