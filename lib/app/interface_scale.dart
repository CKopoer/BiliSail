import 'dart:ui' show DisplayFeature;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/settings/application/settings_controller.dart';

/// Each Flutter view has its own constraints, safe areas and keyboard insets.
class InterfaceScale extends ConsumerWidget {
  const InterfaceScale({
    super.key,
    this.automaticFactor = 1,
    required this.child,
  });

  final double automaticFactor;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final percent = ref.watch(
      settingsControllerProvider.select(
        (state) => state.value?.interfaceScale.percent,
      ),
    );
    final factor = percent == null ? automaticFactor : percent / 100;
    final media = MediaQuery.of(context);
    final radii = media.displayCornerRadii;
    // Keep the same widget tree even at 100% so changing the preference
    // retains the Navigator, focus, scroll positions and playback session.
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = constraints.constrain(
          constraints.hasBoundedWidth && constraints.hasBoundedHeight
              ? constraints.biggest
              : media.size,
        );
        final size = viewport / factor;
        return SizedBox.fromSize(
          size: viewport,
          child: FittedBox(
            fit: BoxFit.fill,
            alignment: Alignment.topLeft,
            child: SizedBox.fromSize(
              size: size,
              child: MediaQuery(
                data: factor == 1
                    ? media
                    : media
                          .copyWith(
                            size: size,
                            devicePixelRatio: media.devicePixelRatio * factor,
                            padding: media.padding / factor,
                            viewPadding: media.viewPadding / factor,
                            viewInsets: media.viewInsets / factor,
                            systemGestureInsets:
                                media.systemGestureInsets / factor,
                            displayFeatures: [
                              for (final feature in media.displayFeatures)
                                DisplayFeature(
                                  bounds: Rect.fromLTRB(
                                    feature.bounds.left / factor,
                                    feature.bounds.top / factor,
                                    feature.bounds.right / factor,
                                    feature.bounds.bottom / factor,
                                  ),
                                  type: feature.type,
                                  state: feature.state,
                                ),
                            ],
                          )
                          .applyDisplayCornerRadii(
                            radii == null ? null : radii * (1 / factor),
                          ),
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }
}
