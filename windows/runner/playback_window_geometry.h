#ifndef RUNNER_PLAYBACK_WINDOW_GEOMETRY_H_
#define RUNNER_PLAYBACK_WINDOW_GEOMETRY_H_

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <optional>

namespace playback_window {

// Native desktop coordinates: physical screen pixels on Windows. Negative
// origins are valid for displays left of or above the primary monitor.
struct Bounds {
  double left;
  double top;
  double width;
  double height;
};

inline bool IsValid(const Bounds& value) {
  return std::isfinite(value.left) && std::isfinite(value.top) &&
         std::isfinite(value.width) && std::isfinite(value.height) &&
         std::abs(value.left) <= 1000000 && std::abs(value.top) <= 1000000 &&
         value.width >= 100 && value.height >= 100 &&
         value.width <= 100000 && value.height <= 100000;
}

inline Bounds PlacementToScreen(Bounds placement, const Bounds& monitor,
                                const Bounds& work_area, bool tool_window) {
  if (!tool_window) {
    placement.left += work_area.left - monitor.left;
    placement.top += work_area.top - monitor.top;
  }
  return placement;
}

inline std::optional<Bounds> FitToWorkArea(const Bounds& saved,
                                         const Bounds& work_area) {
  if (!IsValid(saved) || !IsValid(work_area)) return std::nullopt;
  const double width = std::min(saved.width, work_area.width);
  const double height = std::min(saved.height, work_area.height);
  return Bounds{std::clamp(saved.left, work_area.left,
                            work_area.left + work_area.width - width),
                std::clamp(saved.top, work_area.top,
                            work_area.top + work_area.height - height),
                width, height};
}

// The engine's desktop channel owns this finite session. A late
// close from an old view/owner cannot overwrite or retire a newly opened view.
class GeometrySession {
 public:
  void Load(const Bounds& normal, bool maximized) {
    if (IsValid(normal)) {
      normal_ = normal;
      maximized_ = maximized;
    }
  }
  void Begin(int64_t view, int64_t owner) {
    view_ = view;
    owner_ = owner;
  }
  bool Owns(int64_t view, int64_t owner) const {
    return view_ == view && owner_ == owner;
  }
  void Capture(int64_t view, int64_t owner, const Bounds& normal,
               bool maximized = false) {
    if (Owns(view, owner) && IsValid(normal)) {
      normal_ = normal;
      maximized_ = maximized;
    }
  }
  void Retire(int64_t view, int64_t owner) {
    if (Owns(view, owner)) {
      view_ = -1;
      owner_ = -1;
    }
  }
  const std::optional<Bounds>& normal() const { return normal_; }
  bool maximized() const { return maximized_; }

 private:
  int64_t view_ = -1;
  int64_t owner_ = -1;
  std::optional<Bounds> normal_;
  bool maximized_ = false;
};

}  // namespace playback_window

#endif  // RUNNER_PLAYBACK_WINDOW_GEOMETRY_H_
