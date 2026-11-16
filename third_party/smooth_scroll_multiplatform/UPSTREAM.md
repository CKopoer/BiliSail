# smooth_scroll_multiplatform compatibility copy

Baseline: [smooth_scroll_multiplatform 1.0.8](https://pub.dev/packages/smooth_scroll_multiplatform/versions/1.0.8), [alesimula/dyn_mouse_scroll](https://github.com/alesimula/dyn_mouse_scroll).

Pub archive SHA-256: `c3b8998c3c70eaf480e8ce16608ffc80c0aac1722697a08992fde10e1c97a742`.

The original MIT LICENSE and DynMouseScroll/ScrollState implementation are retained. This repository-local version is `1.0.8+bilisail.2`; it is not published and does not modify the Pub cache.

Changes:

- Expose `SmoothScrollSimulation` and `SmoothScrollDefaults` through the public library. They use the same animateTo interpolation and defaults (380 ms, speed 2, easeOutQuart) as DynMouseScroll. Position/target accumulation, cancellation, boundary coordination and frame timing remain owned by BiliSail's scroll adapter.
- The application uses this public interpolation instead of replacing retained/NestedScrollView controllers or installing the package's provider and pointer listeners. Native touch and trackpad physics remain owned by Flutter.
- The local minimum SDK matches BiliSail (Flutter 3.50.0 / Dart 3.14.0+), and provider is pinned to 6.1.5+1. Package version, publication flag, public export and formatting/lint compatibility changes are maintained here. The original widget implementation is retained for comparison, with typed builder callbacks, a retained provider selector subscription, braces, removal of redundant null initialization/cascade, and modern library syntax.

Root widget tests compare this interpolation with DynMouseScroll on a real ListView. Other tests cover nested headers, retained tabs, cancellation, input bounds and all selectable modes. No compatibility with future Flutter releases is implied by the package's original platform list.

The Flutter 3.50 revision directly imports standalone material_ui 1.11.0; interpolation and wheel handling are unchanged.
