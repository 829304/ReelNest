import 'home_snapshot.dart';

/// HomeView.HomeModuleKind, excluding photos per the user's scope decision.
/// Deferred music IDs remain in the stored order.
enum HomeModule {
  hero('每日推荐'),
  stats('媒体总览'),
  seriesRecommendations('剧集推荐'),
  continueWatching('继续观看'),
  recentlyPlayed('最近播放'),
  watchlist('想看'),
  favorites('收藏'),
  musicRecommendations('音乐推荐'),
  continueListening('继续听'),
  recentSeries('最近添加'),
  highRated('高分精选'),
  dashboard('运行状态');

  const HomeModule(this.title);
  final String title;
  bool get implemented =>
      this != musicRecommendations && this != continueListening;
  HomeCollection? get collection =>
      HomeCollection.values.where((value) => value.name == name).firstOrNull;
}

class HomeLayout {
  HomeLayout({
    Iterable<HomeModule> order = HomeModule.values,
    Iterable<HomeModule> hidden = const [],
    this.hasStoredOrder = false,
  }) : order = List.unmodifiable(_normalize(order)),
       hidden = Set.unmodifiable(hidden);

  factory HomeLayout.decode(String order, String hidden) {
    final byId = {for (final module in HomeModule.values) module.name: module};
    return HomeLayout(
      order: order.split(',').map((id) => byId[id]).nonNulls,
      hidden: hidden.split(',').map((id) => byId[id]).nonNulls,
      hasStoredOrder: order.isNotEmpty,
    );
  }

  final List<HomeModule> order;
  final Set<HomeModule> hidden;
  final bool hasStoredOrder;
  bool get canReset => hasStoredOrder || hidden.isNotEmpty;
  List<HomeModule> get added {
    final visible = order
        .where((m) => m.implemented && !hidden.contains(m))
        .toList();
    return visible.isEmpty ? [HomeModule.hero] : visible;
  }

  List<HomeModule> get addable => HomeModule.values
      .where((m) => m.implemented && hidden.contains(m))
      .toList();

  static List<HomeModule> _normalize(Iterable<HomeModule> order) =>
      {...order, ...HomeModule.values}.toList();

  HomeLayout move(HomeModule module, HomeModule destination) {
    if (module == destination) return this;
    final result = order.where((value) => value != module).toList();
    result.insert(result.indexOf(destination), module);
    return HomeLayout(order: result, hidden: hidden, hasStoredOrder: true);
  }

  HomeLayout hide(HomeModule module) =>
      !module.implemented || hidden.contains(module) || added.length <= 1
      ? this
      : HomeLayout(
          order: order,
          hidden: {...hidden, module},
          hasStoredOrder: hasStoredOrder,
        );

  HomeLayout restore(HomeModule module) => !hidden.contains(module)
      ? this
      : HomeLayout(
          order: [...order.where((m) => m != module), module],
          hidden: hidden.where((m) => m != module),
          hasStoredOrder: true,
        );

  String get encodedOrder =>
      hasStoredOrder ? order.map((m) => m.name).join(',') : '';
  String get encodedHidden =>
      HomeModule.values.where(hidden.contains).map((m) => m.name).join(',');
  bool sameAs(HomeLayout other) =>
      encodedOrder == other.encodedOrder &&
      encodedHidden == other.encodedHidden;
}
