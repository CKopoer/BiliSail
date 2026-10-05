/// Public home destinations; unsupported services keep their own empty state.
enum HomeChannel {
  recommended('推荐'),
  popular('热门'),
  dynamic('动态'),
  videoDynamic('视频动态'),
  bangumi('番剧'),
  guochuang('国创'),
  live('直播'),
  cinema('放映厅'),
  categories('分区'),
  ranking('排行榜'),
  watchLater('稍后再看'),
  favorites('我的收藏');

  const HomeChannel(this.label);
  final String label;

  bool get hasVideoFeed => switch (this) {
    recommended || popular || categories || ranking => true,
    _ => false,
  };

  bool get requiresAccount => switch (this) {
    dynamic || videoDynamic || watchLater || favorites => true,
    _ => false,
  };

  List<String> get sections => switch (this) {
    popular => const ['综合热门'],
    dynamic => const ['全部', '视频', '图文'],
    videoDynamic => const ['最新视频'],
    bangumi => const ['推荐', '时间表', '番剧索引', '我的追番'],
    guochuang => const ['推荐', '时间表', '国创索引', '我的追番'],
    live => const ['推荐直播', '全部分区', '我的关注', '观看记录'],
    cinema => const ['推荐', '电影', '电视剧', '纪录片', '综艺'],
    watchLater => const ['全部', '未看完'],
    favorites => const ['我的收藏夹', '订阅收藏夹'],
    _ => const [],
  };
}
