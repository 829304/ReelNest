import 'dart:async';

import 'package:file_selector/file_selector.dart' as file_selector;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../domain/media_source.dart';
import '../features/playback/application/transient_playback_providers.dart';
import '../features/playback/domain/transient_playback_target.dart';
import '../features/playback/presentation/transient_playback_controls.dart';
import '../ui/widgets/app_feedback.dart';
import 'desktop_shell.dart';
import 'mobile_shell.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  bool _dropEnabled = true;

  Future<void> _openSelectedFile() async {
    setState(() => _dropEnabled = false);
    try {
      final file = await file_selector.openFile(
        acceptedTypeGroups: [
          file_selector.XTypeGroup(
            label: '视频文件',
            extensions: TransientPlaybackTarget.videoExtensions,
          ),
        ],
      );
      if (file == null) return;
      await _openFile(file.path);
    } finally {
      if (mounted) setState(() => _dropEnabled = true);
    }
  }

  Future<void> _openFile(String path, {Uint8List? securityBookmark}) => ref
      .read(transientPlaybackLauncherProvider)
      .openFile(path, securityBookmark: securityBookmark);

  void _showOpenError(Object error) {
    if (!mounted) return;
    showAppToast(
      context,
      error is SourceFailure ? error.message : '无法打开视频文件，请重试。',
      kind: AppFeedbackKind.error,
    );
  }

  void _chooseFile() {
    unawaited(_openSelectedFile().catchError(_showOpenError));
  }

  Future<void> _showStreamDialog() async {
    if (!_dropEnabled) return;
    setState(() => _dropEnabled = false);
    try {
      await showTransientStreamDialog(
        context,
        onOpen: ref.read(transientPlaybackLauncherProvider).openStream,
      );
    } finally {
      if (mounted) setState(() => _dropEnabled = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final selectedIndex = widget.navigationShell.currentIndex;
        // Top-level labels select their entry page, not a remembered library
        // or detail route inside the branch (ContentView.setSidebarSelection).
        void select(int index) =>
            widget.navigationShell.goBranch(index, initialLocation: true);
        // Desktop window constraints live in the native runners, as in the
        // original MainWindowToolbarVisibilityGuard. Width is not a platform.
        final desktop = switch (defaultTargetPlatform) {
          TargetPlatform.windows ||
          TargetPlatform.macOS ||
          TargetPlatform.linux => true,
          _ => false,
        };
        if (!desktop) {
          return MobileShell(
            selectedIndex: selectedIndex,
            onSelected: select,
            child: widget.navigationShell,
          );
        }
        return TransientPlaybackShortcuts(
          onOpenStream: () => unawaited(_showStreamDialog()),
          child: TransientMediaDropTarget(
            enabled: _dropEnabled,
            openFile: _openFile,
            onError: _showOpenError,
            child: DesktopShell(
              selectedIndex: selectedIndex,
              onSelected: select,
              onOpenFile: _chooseFile,
              onOpenStream: () => unawaited(_showStreamDialog()),
              child: widget.navigationShell,
            ),
          ),
        );
      },
    );
  }
}
