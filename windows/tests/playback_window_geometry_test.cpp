#include "../runner/playback_window_geometry.h"

#include <cassert>
#include <iostream>
#include <limits>

using playback_window::Bounds;
using playback_window::FitToWorkArea;
using playback_window::GeometrySession;
using playback_window::PlacementToScreen;

int main() {
  const Bounds monitor{-1920, 0, 1920, 1080};
  const Bounds work{-1880, 32, 1880, 1048};
  const Bounds placement{-1500, 100, 900, 700};
  const auto screen = PlacementToScreen(placement, monitor, work, false);
  assert(screen.left == -1460 && screen.top == 132);
  const auto tool = PlacementToScreen(placement, monitor, work, true);
  assert(tool.left == -1500 && tool.top == 100);
  const auto negative = FitToWorkArea(screen, work);
  assert(negative && negative->left == -1460 && negative->top == 132);
  assert(negative->width == 900 && negative->height == 700);

  const auto top_taskbar = PlacementToScreen(
      Bounds{100, 60, 900, 700}, Bounds{0, 0, 1920, 1080},
      Bounds{0, 40, 1920, 1040}, false);
  assert(top_taskbar.left == 100 && top_taskbar.top == 100);
  const auto removed_display = FitToWorkArea(screen, Bounds{0, 0, 1280, 720});
  assert(removed_display && removed_display->left == 0 && removed_display->top == 20);
  const auto oversized = FitToWorkArea(Bounds{-900, -900, 4000, 3000}, work);
  assert(oversized && oversized->left == work.left && oversized->top == work.top);
  assert(oversized->width == work.width && oversized->height == work.height);
  assert(!FitToWorkArea(Bounds{0, 0, 0, 700}, work));
  assert(!FitToWorkArea(Bounds{std::numeric_limits<double>::quiet_NaN(), 0, 900, 700}, work));
  assert(!FitToWorkArea(Bounds{0, 0, std::numeric_limits<double>::infinity(), 700}, work));

  GeometrySession session;
  assert(!session.normal());  // First app window keeps the SDK default.
  session.Begin(4, 1);
  session.Capture(4, 1, screen);
  session.Retire(4, 1);
  assert(session.normal() && session.normal()->left == -1460);
  session.Begin(4, 2);  // Even a reused view ID has a distinct owner lease.
  session.Capture(4, 2, Bounds{50, 70, 1000, 800});
  session.Capture(4, 1, placement);  // Late response from the retired window.
  session.Retire(4, 1);
  assert(session.Owns(4, 2) && session.normal()->left == 50);
  session.Capture(4, 2, Bounds{0, 0, -1, -1});
  assert(session.normal()->width == 1000);
  const auto restored = FitToWorkArea(*session.normal(), Bounds{0, 0, 1920, 1080});
  assert(restored && restored->left == 50 && restored->top == 70);
  assert(restored->width == 1000 && restored->height == 800);
  GeometrySession next_app;
  assert(!next_app.normal());  // Missing persisted state keeps the SDK default.
  assert(!next_app.maximized());
  next_app.Load(*session.normal(), true);
  assert(next_app.normal()->width == 1000 && next_app.maximized());
  next_app.Load(Bounds{0, 0, -1, -1}, false);
  assert(next_app.normal()->width == 1000 && next_app.maximized());

  GeometrySession zoom;
  zoom.Begin(6, 10);
  zoom.Capture(6, 10, screen, true);
  zoom.Retire(6, 10);
  zoom.Begin(7, 11);
  assert(zoom.maximized());  // Close/reopen retains zoom and the unzoom bounds.
  const auto unzoom = FitToWorkArea(*zoom.normal(), work);
  assert(unzoom && unzoom->left == screen.left && unzoom->top == screen.top);
  assert(unzoom->width == screen.width && unzoom->height == screen.height);
  zoom.Capture(6, 10, Bounds{0, 0, 1200, 900}, false);
  zoom.Retire(6, 10);
  assert(zoom.Owns(7, 11) && zoom.maximized());
  zoom.Capture(7, 11, Bounds{0, 0, -1, -1}, false);
  assert(zoom.maximized());  // Invalid geometry must not partially reset state.
  zoom.Capture(7, 11, *unzoom, false);  // User restores the ordinary window.
  zoom.Retire(7, 11);
  zoom.Begin(8, 12);
  assert(!zoom.maximized());
  assert(zoom.normal()->width == screen.width);
  std::cout << "PASS playback window geometry: coordinates, work areas, zoom restore, owner isolation, app lifetime\n";
}
