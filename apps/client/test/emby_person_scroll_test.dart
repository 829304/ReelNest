import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/features/sources/presentation/emby_detail_extras.dart';
import 'package:reelnest/features/sources/presentation/local_media_artwork.dart';

void main() {
  final source = MediaSource(
    id: 'source',
    kind: MediaSourceKind.emby,
    name: 'Emby',
    location: 'emby://fixture/user',
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );
  final works = List.generate(
    20,
    (i) => IndexedMedia(
      identity: (sourceId: source.id, localId: i.toString()),
      title: 'Film $i',
      type: 'movie',
      bytes: 0,
      modified: DateTime.utc(2026),
    ),
  );
  for (final platform in [
    TargetPlatform.windows,
    TargetPlatform.macOS,
    TargetPlatform.linux,
  ]) {
    testWidgets(
      '${platform.name}: mouse can reach and open the last person work',
      (tester) async {
        final opened = <MediaIdentity>[];
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: platform),
            home: Scaffold(
              body: SizedBox(
                width: 500,
                child: EmbyPersonWorksStrip(
                  source: source,
                  works: works,
                  onOpen: (item) => opened.add(item.identity),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final scrollbar = tester.widget<Scrollbar>(
          find.byKey(const ValueKey('person-works-scrollbar')),
        );
        expect(scrollbar.thumbVisibility, isTrue);
        expect(scrollbar.interactive, isTrue);
        final scroll = scrollbar.controller!;
        final left = find.widgetWithIcon(IconButton, Icons.chevron_left);
        final right = find.widgetWithIcon(IconButton, Icons.chevron_right);
        expect(tester.widget<IconButton>(left).onPressed, isNull);
        await tester.tap(right);
        await tester.pumpAndSettle();
        expect(scroll.offset, greaterThan(0));
        await tester.tap(left);
        await tester.pumpAndSettle();
        expect(scroll.offset, 0);
        // Drag the actual thumb, rather than calling ScrollController directly.
        final bounds = tester.getRect(
          find.byKey(const ValueKey('person-works-scrollbar')),
        );
        final thumb = await tester.startGesture(
          Offset(bounds.left + 25, bounds.bottom - 4),
          kind: PointerDeviceKind.mouse,
        );
        await thumb.moveBy(Offset(bounds.width, 0));
        await thumb.up();
        await tester.pumpAndSettle();
        expect(
          scroll.offset,
          greaterThan(scroll.position.maxScrollExtent * .8),
        );
        await tester.tap(right);
        await tester.pumpAndSettle();
        expect(scroll.offset, closeTo(scroll.position.maxScrollExtent, 1));
        expect(tester.widget<IconButton>(right).onPressed, isNull);
        final last = find.byWidgetPredicate(
          (widget) =>
              widget is LocalMediaCard &&
              widget.item.identity == works.last.identity,
        );
        expect(last, findsOneWidget);
        await tester.tap(last);
        await tester.pump();
        expect(opened, [works.last.identity]);
        await tester.drag(
          find.byType(ListView),
          const Offset(300, 0),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pumpAndSettle();
        expect(scroll.offset, lessThan(scroll.position.maxScrollExtent));
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('a short work list needs no paging buttons', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 500,
            child: EmbyPersonWorksStrip(
              source: source,
              works: works.take(2).toList(),
              onOpen: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('向右浏览作品'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
}
