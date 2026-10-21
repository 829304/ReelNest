import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/media_source.dart';
import '../../../ui/widgets/app_feedback.dart';
import '../../sources/application/source_providers.dart';
import '../application/video_preferences_provider.dart';

class LocalVideoActions extends ConsumerStatefulWidget {
  const LocalVideoActions({required this.identity, super.key});
  final MediaIdentity identity;
  @override
  ConsumerState<LocalVideoActions> createState() => _LocalVideoActionsState();
}

class _LocalVideoActionsState extends ConsumerState<LocalVideoActions> {
  bool _busy = false;
  @override
  Widget build(BuildContext context) {
    final identity = widget.identity;
    final state = ref.watch(videoPreferencesProvider(identity));
    final value = state.value;
    Future<void> run(Future<void> Function() action) async {
      if (_busy) return;
      setState(() => _busy = true);
      try {
        await action();
      } catch (error) {
        if (context.mounted) {
          showAppToast(
            context,
            sourceErrorMessage(error),
            kind: AppFeedbackKind.error,
          );
        }
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: value?.watchlist == true ? '移出想看' : '加入想看',
          icon: Icon(
            value?.watchlist == true ? Icons.bookmark : Icons.bookmark_border,
            size: 20,
          ),
          onPressed: value == null || _busy
              ? null
              : () => run(
                  () => ref
                      .read(videoPreferencesRepositoryProvider)
                      .setWatchlist(identity, !value.watchlist),
                ),
        ),
        IconButton(
          tooltip: value?.favorite == true ? '取消喜欢' : '喜欢',
          icon: Icon(
            value?.favorite == true ? Icons.favorite : Icons.favorite_border,
            size: 20,
            color: value?.favorite == true ? Colors.red : null,
          ),
          onPressed: value == null || _busy
              ? null
              : () => run(
                  () => ref
                      .read(videoPreferencesRepositoryProvider)
                      .setLocalFavorite(identity, !value.favorite),
                ),
        ),
      ],
    );
  }
}
