import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/presentation/app_image_provider.dart';
import '../features/settings/application/settings_controller.dart';
import '../shared/ui/app_network_image.dart';

/// The composition root translates feature settings into the core cache policy.
/// Pending settings keep caching off, so a saved opt-out applies from startup.
final class ImageCacheBinding extends ConsumerWidget {
  const ImageCacheBinding({
    super.key,
    required this.cache,
    required this.child,
  });
  final AppImageCache cache;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(settingsControllerProvider, (previous, next) {
      cache.enabled = next.value?.cacheImages ?? false;
    });
    cache.enabled =
        ref.watch(settingsControllerProvider).value?.cacheImages ?? false;
    return AppImageCacheScope(cache: cache, child: child);
  }
}
