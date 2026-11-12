import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/dynamic_post.dart';
import '../../auth/application/auth_controller.dart';
import 'dynamic_actions_controller.dart';

final dynamicContentProvider =
    NotifierProvider<DynamicContentController, DynamicContentState>(
      DynamicContentController.new,
    );

final class DynamicContentState {
  const DynamicContentState({
    this.removed = const {},
    this.hiddenAuthors = const {},
    this.posts = const {},
    this.locked = const {},
    this.reservations = const {},
  });
  final Set<String> removed;
  final Map<String, String> hiddenAuthors;
  final Map<String, DynamicPost> posts;
  final Map<String, Set<String>> locked;
  final Map<String, DynamicReservation> reservations;
  bool hidden(DynamicPost post) =>
      removed.contains(post.id) ||
      hiddenAuthors.containsKey(post.authorId?.value);
}

class DynamicContentController extends Notifier<DynamicContentState> {
  @override
  DynamicContentState build() {
    final repo = ref.watch(dynamicRepositoryProvider);
    if (repo != null) {
      ref.watch(
        authControllerProvider.select(
          (a) => (a.status, a.mid, repo.sessionEpoch),
        ),
      );
    }
    return const DynamicContentState();
  }

  void _set({
    Set<String>? removed,
    Map<String, String>? authors,
    Map<String, DynamicPost>? posts,
    Map<String, Set<String>>? locked,
    Map<String, DynamicReservation>? reservations,
  }) => state = DynamicContentState(
    removed: Set.unmodifiable(removed ?? state.removed),
    hiddenAuthors: Map.unmodifiable(authors ?? state.hiddenAuthors),
    posts: Map.unmodifiable(posts ?? state.posts),
    locked: Map.unmodifiable(locked ?? state.locked),
    reservations: Map.unmodifiable(reservations ?? state.reservations),
  );
  void remove(String id) {
    final values = {...state.removed, id};
    if (values.length > 512) values.remove(values.first);
    _set(removed: values);
  }

  void hideAuthor(String id, String name) {
    final values = {...state.hiddenAuthors, id: name};
    if (values.length > 128) values.remove(values.keys.first);
    _set(authors: values);
  }

  void restoreAuthor(String id) =>
      _set(authors: {...state.hiddenAuthors}..remove(id));
  void update(DynamicPost post) {
    final values = {...state.posts}..remove(post.id);
    values[post.id] = post;
    if (values.length > 512) values.remove(values.keys.first);
    _set(posts: values);
  }

  void lock(String id, String action) {
    final values = {...state.locked};
    values[id] = Set.unmodifiable({...?values[id], action});
    if (values.length > 512) values.remove(values.keys.first);
    _set(locked: values);
  }

  void updateReservation(DynamicReservation reservation) {
    final values = {...state.reservations}..remove(reservation.id);
    values[reservation.id] = reservation;
    if (values.length > 512) values.remove(values.keys.first);
    _set(reservations: values);
  }

  void unlock(String id, Set<String> actions) {
    final values = {...state.locked};
    final remaining = {...?values[id]}..removeAll(actions);
    if (remaining.isEmpty) {
      values.remove(id);
    } else {
      values[id] = Set.unmodifiable(remaining);
    }
    _set(locked: values);
  }
}
