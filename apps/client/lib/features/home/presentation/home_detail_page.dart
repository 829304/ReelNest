import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/media_source.dart';
import '../../sources/application/source_providers.dart';
import '../../sources/presentation/local_media_detail_page.dart';
import '../application/home_providers.dart';

final _publicMediaProvider = FutureProvider.autoDispose
    .family<void, MediaIdentity>((ref, id) {
      ref.watch(sourceChangesProvider);
      return ref.watch(homeRepositoryProvider).ensurePublic(id);
    });

class HomeDetailPage extends ConsumerWidget {
  const HomeDetailPage({required this.identity, super.key});
  final MediaIdentity identity;
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(_publicMediaProvider(identity))
      .when(
        skipLoadingOnReload: true,
        loading: () => const Center(child: Text('正在读取…')),
        data: (_) => LocalMediaDetailPage(identity: identity),
        error: (error, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(sourceErrorMessage(error)),
              TextButton(
                onPressed: () =>
                    context.canPop() ? context.pop() : context.go('/'),
                child: const Text('返回'),
              ),
            ],
          ),
        ),
      );
}
