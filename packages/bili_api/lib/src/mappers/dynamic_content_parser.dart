part of 'dynamic_post_parser.dart';

ApiDynamicTopic? _topic(Map<String, Object?> value) {
  final name = _text(value['name']);
  if (name.isEmpty) return null;
  final id = _id(value['id']);
  return ApiDynamicTopic(
    name: name,
    id: id,
    url:
        _uri(value['jump_url']) ??
        (id == null
            ? Uri.https('search.bilibili.com', '/all', {'keyword': name})
            : _topicUrl(id)),
  );
}

Uri _topicUrl(String id) =>
    Uri.https('www.bilibili.com', '/v/topic/detail', {'topic_id': id});

Uri _voteUrl(String id) =>
    Uri.https('t.bilibili.com', '/vote/h5/index/', {'vote_id': id});

Uri? _richNodeUrl(Map<String, Object?> node, String dynamicId) {
  final rid = node['rid'];
  final numericId = _id(rid);
  if (node['type'] == 'RICH_TEXT_NODE_TYPE_TOPIC' && numericId != null) {
    return _topicUrl(numericId);
  }
  if (node['type'] == 'RICH_TEXT_NODE_TYPE_VOTE' && numericId != null) {
    return _voteUrl(numericId);
  }
  final direct = _uri(node['jump_url']);
  if (direct != null) return direct;
  return switch (node['type']) {
    'RICH_TEXT_NODE_TYPE_BV'
        when rid is String && RegExp(r'^BV[0-9A-Za-z]{10}$').hasMatch(rid) =>
      Uri.https('www.bilibili.com', '/video/$rid'),
    'RICH_TEXT_NODE_TYPE_AV' when numericId != null => Uri.https(
      'www.bilibili.com',
      '/video/av$numericId',
    ),
    'RICH_TEXT_NODE_TYPE_CV' when numericId != null => Uri.https(
      'www.bilibili.com',
      '/read/cv$numericId',
    ),
    'RICH_TEXT_NODE_TYPE_TOPIC' when numericId != null => _topicUrl(numericId),
    'RICH_TEXT_NODE_TYPE_TOPIC' => Uri.https('search.bilibili.com', '/all', {
      'keyword': _text(
        node['orig_text'],
        fallback: _text(node['text']),
      ).replaceAll('#', ''),
    }),
    'RICH_TEXT_NODE_TYPE_VOTE' when numericId != null => Uri.https(
      't.bilibili.com',
      '/vote/h5/index/',
      {'vote_id': numericId},
    ),
    'RICH_TEXT_NODE_TYPE_LOTTERY' => Uri.https(
      'www.bilibili.com',
      '/h5/lottery/result',
      {'business_id': dynamicId},
    ),
    'RICH_TEXT_NODE_TYPE_VIEW_PICTURE' => Uri.https(
      't.bilibili.com',
      '/$dynamicId',
    ),
    _ => null,
  };
}

List<ApiDynamicContentCard> _contentCards(
  Map<String, Object?> major,
  Map<String, Object?> content,
  Map<String, Object?> live,
  String id,
) {
  final fallback = Uri.https('t.bilibili.com', '/$id');
  final result = <ApiDynamicContentCard>[];
  const majors = {
    'article': ApiDynamicCardKind.article,
    'pgc': ApiDynamicCardKind.pgc,
    'courses': ApiDynamicCardKind.course,
    'ugc_season': ApiDynamicCardKind.season,
    'music': ApiDynamicCardKind.music,
    'medialist': ApiDynamicCardKind.medialist,
    'common': ApiDynamicCardKind.common,
    'upower_common': ApiDynamicCardKind.common,
  };
  for (final entry in majors.entries) {
    final value = _map(major[entry.key]);
    if (value.isEmpty) continue;
    final musicId = _id(value['id']);
    final episodeId = _id(value['epid']);
    final seasonId = _id(value['season_id']);
    final articleId = _id(value['id']);
    final target =
        _officialUri(value['jump_url']) ??
        switch (entry.value) {
          ApiDynamicCardKind.music when musicId != null => Uri.https(
            'www.bilibili.com',
            '/audio/au$musicId',
          ),
          ApiDynamicCardKind.pgc when episodeId != null => Uri.https(
            'www.bilibili.com',
            '/bangumi/play/ep$episodeId',
          ),
          ApiDynamicCardKind.pgc when seasonId != null => Uri.https(
            'www.bilibili.com',
            '/bangumi/play/ss$seasonId',
          ),
          ApiDynamicCardKind.article when articleId != null => Uri.https(
            'www.bilibili.com',
            '/read/cv$articleId',
          ),
          _ => fallback,
        };
    result.add(
      ApiDynamicContentCard(
        kind: entry.value,
        title:
            '${_text(value['title_prefix'])}${_text(value['title'], fallback: '查看内容')}',
        description: _join([value['desc'], value['label'], value['sub_title']]),
        detail: _join([
          if (_map(value['stat'])['play'] case final count?)
            '${_display(count)}播放',
          if (_map(value['stat'])['danmaku'] case final count?)
            '${_display(count)}弹幕',
        ]),
        badge: _text(_map(value['badge'])['text']),
        coverUrl:
            _uri(value['cover']) ?? _uri(_list(value['covers']).firstOrNull),
        url: target,
      ),
    );
    break;
  }
  if (live.isNotEmpty) {
    result.add(
      ApiDynamicContentCard(
        kind: ApiDynamicCardKind.live,
        title: _text(live['title'], fallback: '直播间'),
        description: _join([
          live['desc_first'],
          live['desc_second'],
          live['area_name'],
        ]),
        badge: live['live_status'] == 0 ? '未开播' : '直播',
        coverUrl: _uri(live['cover']),
        url: _officialUri(live['jump_url']) ?? fallback,
      ),
    );
  }
  final archive = _map(major['archive']);
  if (archive.isNotEmpty &&
      !RegExp(r'^BV[0-9A-Za-z]{10}$').hasMatch(_text(archive['bvid']))) {
    result.add(
      ApiDynamicContentCard(
        kind: ApiDynamicCardKind.ugc,
        title: _text(archive['title'], fallback: '视频'),
        coverUrl: _uri(archive['cover']),
        url: _officialUri(archive['jump_url']) ?? fallback,
      ),
    );
  }
  if (result.isEmpty &&
      major.isNotEmpty &&
      ![
        'archive',
        'draw',
        'opus',
        'none',
      ].any((key) => _map(major[key]).isNotEmpty)) {
    result.add(
      ApiDynamicContentCard(
        kind: ApiDynamicCardKind.unknown,
        title: '暂不支持的动态内容',
        description: '在官方页面查看完整内容',
        url: fallback,
      ),
    );
  }
  final additional = _map(content['additional']);
  final type = _text(additional['type']);
  if (type == 'ADDITIONAL_TYPE_GOODS') {
    final goods = _map(additional['goods']);
    for (final raw in _list(goods['items']).take(10)) {
      final value = _map(raw);
      if (value.isEmpty) continue;
      final url = _uri(value['jump_url']);
      result.add(
        ApiDynamicContentCard(
          kind: ApiDynamicCardKind.goods,
          title: _text(value['name'], fallback: '商品'),
          description: _display(value['price']),
          detail: _text(goods['head_text']),
          coverUrl: _uri(value['cover']),
          url: url,
          actionLabel: _text(value['jump_desc'], fallback: '查看商品'),
          actionUrl: url,
        ),
      );
    }
  } else if (additional.isNotEmpty) {
    final (key, kind, label) = switch (type) {
      'ADDITIONAL_TYPE_UGC' => ('ugc', ApiDynamicCardKind.ugc, '相关视频'),
      'ADDITIONAL_TYPE_RESERVE' => (
        'reserve',
        ApiDynamicCardKind.reservation,
        '预约',
      ),
      'ADDITIONAL_TYPE_VOTE' => ('vote', ApiDynamicCardKind.vote, '投票'),
      'ADDITIONAL_TYPE_UPOWER_LOTTERY' => (
        'upower_lottery',
        ApiDynamicCardKind.lottery,
        '抽奖',
      ),
      'ADDITIONAL_TYPE_MATCH' => ('match', ApiDynamicCardKind.match, '赛事'),
      'ADDITIONAL_TYPE_COMMON' => ('common', ApiDynamicCardKind.common, '相关内容'),
      _ => ('', ApiDynamicCardKind.unknown, '更多附加内容'),
    };
    final value = _map(additional[key]);
    final button = _map(value['button']);
    final actionUrl = _uri(button['jump_url']);
    final voteId = _id(value['vote_id']);
    final target = kind == ApiDynamicCardKind.vote && voteId != null
        ? _voteUrl(voteId)
        : _uri(value['jump_url']) ??
              actionUrl ??
              (voteId == null
                  ? fallback
                  : Uri.https('t.bilibili.com', '/vote/h5/index/', {
                      'vote_id': voteId,
                    }));
    final match = _map(value['match_info']);
    final left = _map(match['left_team']);
    final right = _map(match['right_team']);
    final ended = value['state'] == -1;
    final status = _buttonNumber(button['status']);
    final buttonType = _buttonNumber(button['type']);
    final reservation = kind == ApiDynamicCardKind.reservation;
    final knownReservation =
        status != null && buttonType != null && buttonType > 0;
    // Reservation status is relative to this button's type. A status of 1
    // alone does not establish that this account has reserved the content.
    final checked = reservation
        ? knownReservation && status == buttonType
        : status == 1;
    final stateLabel = reservation && !knownReservation
        ? '查看详情'
        : _text(
            _map(button[checked ? 'check' : 'uncheck'])['text'],
            fallback: reservation
                ? checked
                      ? '已预约'
                      : '预约'
                : '',
          );
    final actionLabel = _text(
      _map(button['jump_style'])['text'],
      fallback: stateLabel,
    );
    result.add(
      ApiDynamicContentCard(
        kind: kind,
        title: _text(
          value['title'],
          fallback: kind == ApiDynamicCardKind.vote
              ? _text(value['desc'], fallback: label)
              : _text(match['title'], fallback: label),
        ),
        description: kind == ApiDynamicCardKind.vote
            ? '${_number(value['join_num']) ?? 0}人参与'
            : _join([
                value['desc_first'],
                value['desc_second'],
                value['desc1'],
                value['desc2'],
                value['hint'],
                match['sub_title'],
              ]),
        detail: kind == ApiDynamicCardKind.match
            ? _join([
                left['name'],
                ..._list(match['center_top']).take(4),
                right['name'],
                match['center_bottom'],
              ])
            : _join([
                value['desc3'],
                value['desc'],
                if (_number(value['reserve_total']) case final total?)
                  '$total人预约',
              ]),
        badge: ended ? '已结束' : label,
        coverUrl: _uri(value['cover']),
        url: target,
        actionLabel: ended
            ? '查看详情'
            : actionLabel.isEmpty
            ? '查看详情'
            : actionLabel,
        actionUrl: kind == ApiDynamicCardKind.vote
            ? target
            : actionUrl ?? target,
      ),
    );
  }
  return result;
}

String _join(Iterable<Object?> values) => values
    .map(
      (value) => value is Map<String, Object?>
          ? _text(value['text'])
          : _display(value),
    )
    .where((value) => value.isNotEmpty)
    .join(' · ');

String _display(Object? value) => value is int
    ? '$value'
    : value is double && value.isFinite
    ? '$value'
    : _text(value);

int? _buttonNumber(Object? value) {
  final number = value is int
      ? value
      : value is String &&
            value.length <= 20 &&
            RegExp(r'^[0-9]+$').hasMatch(value)
      ? int.tryParse(value)
      : null;
  return number != null && number >= 0 ? number : null;
}
