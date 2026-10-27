import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/features/sources/presentation/local_media_artwork.dart';

void main() {
  final now = DateTime(2026, 10, 27);
  final source = MediaSource(
    id: 'visual-source',
    kind: MediaSourceKind.localFolder,
    name: '视觉测试',
    location: 'C:/visual-test',
    createdAt: now,
    updatedAt: now,
  );
  final item = IndexedMedia(
    identity: (sourceId: source.id, localId: 'poster-item'),
    title: '原版海报悬浮态',
    type: 'movie',
    bytes: 0,
    modified: now,
  );

  testWidgets('poster hover uses the original soft shadow tokens', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 180,
            height: 270,
            child: LocalMediaCard(
              source: source,
              item: item,
              rating: 7.6,
              onOpen: () {},
            ),
          ),
        ),
      ),
    );

    final surface = find.byKey(const ValueKey('media-card-hover-surface'));
    expect(surface, findsOneWidget);
    expect(
      find.byKey(const ValueKey('media-card-hover-overlay-shadow')),
      findsNothing,
    );

    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(pointer.removePointer);
    await pointer.addPointer(location: Offset.zero);
    await pointer.moveTo(tester.getTopLeft(surface) + const Offset(12, 12));
    await tester.pumpAndSettle();

    final hovered =
        tester
                .widget<DecoratedBox>(
                  find.byKey(const ValueKey('media-card-hover-overlay-shadow')),
                )
                .decoration
            as BoxDecoration;
    expect(hovered.boxShadow, hasLength(1));
    expect(hovered.boxShadow!.single.color.a, closeTo(.18, 1 / 255));
    expect(hovered.boxShadow!.single.color.r, 0);
    expect(hovered.boxShadow!.single.color.g, 0);
    expect(hovered.boxShadow!.single.color.b, 0);
    expect(hovered.boxShadow!.single.blurRadius, 22);
    expect(hovered.boxShadow!.single.offset, const Offset(0, 8));

    final rating = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('media-card-rating-badge')),
    );
    final ratingDecoration = rating.decoration as BoxDecoration;
    expect(ratingDecoration.color!.a, closeTo(.42, 1 / 255));
    expect(ratingDecoration.color!.r, 0);
    expect(ratingDecoration.color!.g, 0);
    expect(ratingDecoration.color!.b, 0);
    expect(ratingDecoration.border, isNull);

    final tilt = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey('pointer-inspect-tilt-transform')),
    );
    final identity = Matrix4.identity().storage;
    expect(
      tilt.transform!.storage.asMap().entries.any(
        (entry) => (entry.value - identity[entry.key]).abs() > .000001,
      ),
      isTrue,
    );
    expect(
      tester
          .widget<AnimatedOpacity>(
            find.byKey(const ValueKey('pointer-inspect-tilt-highlight')),
          )
          .opacity,
      1,
    );

    await pointer.moveTo(const Offset(20, 20));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      find.byKey(const ValueKey('media-card-hover-overlay-shadow')),
      findsNothing,
    );
  });

  testWidgets('poster tilt is disabled when reduced motion is enabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Center(
            child: SizedBox(
              width: 180,
              height: 270,
              child: LocalMediaCard(source: source, item: item, onOpen: () {}),
            ),
          ),
        ),
      ),
    );

    final tiltFinder = find.byKey(
      const ValueKey('pointer-inspect-tilt-transform'),
    );
    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(pointer.removePointer);
    await pointer.addPointer(location: Offset.zero);
    await pointer.moveTo(tester.getTopLeft(tiltFinder) + const Offset(12, 12));
    await tester.pumpAndSettle();

    final tilt = tester.widget<AnimatedContainer>(tiltFinder);
    expect(tilt.transform!.storage, Matrix4.identity().storage);
    expect(
      tester
          .widget<AnimatedOpacity>(
            find.byKey(const ValueKey('pointer-inspect-tilt-highlight')),
          )
          .opacity,
      0,
    );
  });
}
