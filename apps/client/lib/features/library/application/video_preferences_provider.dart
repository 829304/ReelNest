import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/media_source.dart';
import '../../sources/application/source_providers.dart';
import '../data/video_preferences_repository.dart';

final videoPreferencesRepositoryProvider = Provider<VideoPreferencesRepository>(
  (ref) => VideoPreferencesRepository(ref.watch(sourceRepositoryProvider)),
);
final videoPreferencesProvider = FutureProvider.autoDispose
    .family<VideoPreferences, MediaIdentity>((ref, id) {
      ref.watch(sourceChangesProvider);
      return ref.watch(videoPreferencesRepositoryProvider).read(id);
    });
