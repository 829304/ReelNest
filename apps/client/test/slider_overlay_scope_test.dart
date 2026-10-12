import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelnest/ui/widgets/slider_overlay_scope.dart';
import 'package:reelnest/domain/media_source.dart';
import 'package:reelnest/features/playback/application/playback_session.dart';
import 'package:reelnest/features/playback/data/playback_repository.dart';
import 'package:reelnest/features/playback/presentation/video_player_page.dart';
import 'package:reelnest/features/sources/data/source_repository.dart';
import 'package:reelnest/storage/library_database.dart';
import 'package:reelnest/player/video_engine.dart';

import 'support/fake_video_engine.dart';

class _SemanticsBinding extends AutomatedTestWidgetsFlutterBinding {
  final nodes = <int, List<int>>{};
  final orphans = <int>[];
  final missingChildren = <int>[];
  final descriptions = <int, String>{};

  @override
  ui.SemanticsUpdateBuilder createSemanticsUpdateBuilder() => _RecordingBuilder(
    super.createSemanticsUpdateBuilder(),
    descriptions,
    (updates) {
      nodes.addAll(updates);
      final reachable = <int>{};
      void visit(int id) {
        if (!reachable.add(id)) return;
        for (final child in nodes[id] ?? <int>[]) {
          visit(child);
        }
      }

      visit(0);
      missingChildren.addAll(reachable.where((id) => !nodes.containsKey(id)));
      orphans.addAll(updates.keys.where((id) => !reachable.contains(id)));
      nodes.removeWhere((id, _) => !reachable.contains(id));
    },
  );
}

/// Inspect the actual serialized updates, including incremental portal nodes;
/// inspecting only the widget's SemanticsNode misses the native AXTree failure.
class _RecordingBuilder implements ui.SemanticsUpdateBuilder {
  _RecordingBuilder(this.delegate, this.descriptions, this.record);
  final ui.SemanticsUpdateBuilder delegate;
  final Map<int, String> descriptions;
  final void Function(Map<int, List<int>>) record;
  final updates = <int, List<int>>{};

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #updateNode) {
      descriptions[invocation.namedArguments[#id] as int] =
          '${invocation.namedArguments[#label]} / ${invocation.namedArguments[#value]} / ${invocation.namedArguments[#childrenInTraversalOrder]} / parent=${invocation.namedArguments[#traversalParent]}';
      updates[invocation.namedArguments[#id] as int] = List<int>.from(
        invocation.namedArguments[#childrenInTraversalOrder] as Iterable,
      );
      return Function.apply(delegate.updateNode, [], invocation.namedArguments);
    }
    if (invocation.memberName == #updateCustomAction) {
      return Function.apply(
        delegate.updateCustomAction,
        [],
        invocation.namedArguments,
      );
    }
    return super.noSuchMethod(invocation);
  }

  @override
  ui.SemanticsUpdate build() {
    record(updates);
    return delegate.build();
  }
}

class _LayoutSession extends PlaybackSession {
  _LayoutSession(SourceRepository repository)
    : super(
        sources: repository,
        records: PlaybackRepository(repository.database),
        createEngine: FakeVideoEngine.new,
      );
  @override
  Future<void> open(MediaIdentity identity) async {
    loading = true;
  }

  void ready() {
    loading = false;
    engine = FakeVideoEngine();
    clock = const VideoClock(duration: Duration(seconds: 100), playing: true);
    timeline.value = clock;
    notifyListeners();
  }
}

void main() {
  final binding = _SemanticsBinding();
  testWidgets(
    'player loading and controls serialize a connected semantics tree',
    (tester) async {
      binding.nodes.clear();
      binding.orphans.clear();
      binding.missingChildren.clear();
      final semantics = tester.ensureSemantics();
      final sources = SourceRepository(
        database: LibraryDatabase(NativeDatabase.memory()),
        adapters: {},
      );
      const identity = (sourceId: 'fixture', localId: 'Film.mkv');
      final session = _LayoutSession(sources);
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: VideoPlayerPage(
              identity: identity,
              session: session,
              closeWindow: () async {},
              setFullscreen: (_) async {},
            ),
          ),
        );
        await tester.pump();
        session.ready();
        await tester.pump();
        final mouse = await tester.createGesture(
          kind: ui.PointerDeviceKind.mouse,
        );
        await mouse.addPointer(location: Offset.zero);
        final tooltips = tester
            .widgetList<Tooltip>(find.byType(Tooltip))
            .map((tooltip) => tooltip.message)
            .whereType<String>()
            .toList();
        for (final message in tooltips) {
          final target = find.byTooltip(message);
          if (target.evaluate().isEmpty) continue;
          await mouse.moveTo(tester.getCenter(target.first));
          await tester.pump(const Duration(milliseconds: 800));
          await mouse.moveTo(Offset.zero);
          await tester.pump(const Duration(milliseconds: 250));
        }
        await mouse.removePointer();
        expect(session.error, isNull);
        expect(session.engine, isNotNull);
        expect(binding.missingChildren, isEmpty);
        expect(
          binding.orphans,
          isEmpty,
          reason:
              '${binding.orphans.map((id) => '$id: ${binding.descriptions[id]}')}',
        );
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await session.engine?.dispose();
        await sources.close();
        session.dispose();
        semantics.dispose();
      }
    },
  );
  for (final dialog in [false, true]) {
    testWidgets(
      'slider serializes a connected tree in ${dialog ? 'dialog' : 'route'}',
      (tester) async {
        binding.nodes.clear();
        binding.orphans.clear();
        binding.missingChildren.clear();
        final semantics = tester.ensureSemantics();
        var value = .3;
        final focus = FocusNode();
        addTearDown(focus.dispose);
        Widget content() => StatefulBuilder(
          builder: (context, update) => Center(
            child: SizedBox(
              width: 240,
              height: 48,
              child: SliderOverlayScope(
                child: Slider(
                  value: value,
                  label: '${(value * 100).round()}%',
                  focusNode: focus,
                  onChanged: (next) => update(() => value = next),
                ),
              ),
            ),
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () {
                    if (dialog) {
                      showDialog<void>(
                        context: context,
                        builder: (_) => Dialog(child: content()),
                      );
                    } else {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => Scaffold(body: content()),
                        ),
                      );
                    }
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(
          tester.getSize(find.byType(SliderOverlayScope)),
          const Size(240, 48),
        );
        final gesture = await tester.startGesture(
          tester.getCenter(find.byType(Slider)),
        );
        await tester.pump();
        await gesture.moveBy(const Offset(30, 0));
        await tester.pump(const Duration(milliseconds: 150));
        await gesture.up();
        await tester.pumpAndSettle();
        final afterDrag = value;
        expect(afterDrag, greaterThan(.3));
        focus.requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
        expect(value, greaterThan(afterDrag));
        expect(binding.orphans, isEmpty);
        expect(binding.missingChildren, isEmpty);
        await tester.pumpWidget(const SizedBox.shrink());
        semantics.dispose();
      },
    );
  }
}
