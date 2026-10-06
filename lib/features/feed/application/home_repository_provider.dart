import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/home_repository.dart';

final homeRepositoryProvider = Provider<HomeRepository>(
  (ref) => throw UnimplementedError('HomeRepository must be provided by app'),
);
