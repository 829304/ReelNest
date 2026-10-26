import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../sources/application/source_providers.dart';
import '../data/player_preferences_repository.dart';
import '../data/online_subtitle_settings_repository.dart';

final onlineSubtitleSettingsRepositoryProvider =
    Provider<OnlineSubtitleSettingsRepository>(
      (ref) => OnlineSubtitleSettingsRepository(
        PlayerPreferencesRepository(
          ref.watch(sourceRepositoryProvider).database,
        ),
      ),
    );
