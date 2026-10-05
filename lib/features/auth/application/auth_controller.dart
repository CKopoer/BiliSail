import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/auth_repository.dart';

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => throw UnimplementedError('AuthRepository'),
);
final authControllerProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    final repository = ref.watch(authRepositoryProvider);
    final subscription = repository.changes.listen((value) => state = value);
    ref.onDispose(subscription.cancel);
    return repository.current;
  }

  void signIn() => unawaited(ref.read(authRepositoryProvider).signIn());
  void cancelSignIn() => ref.read(authRepositoryProvider).cancelSignIn();
  Future<void> signOut() => ref.read(authRepositoryProvider).signOut();
}
