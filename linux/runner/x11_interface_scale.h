#ifndef RUNNER_X11_INTERFACE_SCALE_H_
#define RUNNER_X11_INTERFACE_SCALE_H_

#include <gdk/gdkx.h>
#include <gtk/gtk.h>

namespace {

int ReadX11Setting(GdkScreen* screen, const char* name) {
  GValue value = G_VALUE_INIT;
  g_value_init(&value, G_TYPE_INT);
  const int setting = gdk_screen_get_setting(screen, name, &value)
                          ? g_value_get_int(&value)
                          : 0;
  g_value_unset(&value);
  return setting;
}

bool IsKdeDesktop() {
  const char* desktop = g_getenv("XDG_CURRENT_DESKTOP");
  g_auto(GStrv) names = g_strsplit(desktop ? desktop : "", ":", -1);
  for (char** name = names; *name; ++name) {
    if (g_ascii_strcasecmp(*name, "KDE") == 0) return true;
  }
  return g_strcmp0(g_getenv("KDE_FULL_SESSION"), "true") == 0;
}

// Plasma X11 also saves its global scale when the GTK settings daemon isn't
// running. Its KScreen value belongs to the X11 session, not to XWayland.
double ReadPlasmaX11Scale() {
  const char* session = g_getenv("XDG_SESSION_TYPE");
  if (session ? g_ascii_strcasecmp(session, "x11") != 0
              : g_getenv("WAYLAND_DISPLAY") != nullptr) {
    return 0.0;
  }
  g_autofree gchar* path =
      g_build_filename(g_get_user_config_dir(), "kdeglobals", nullptr);
  g_autoptr(GKeyFile) config = g_key_file_new();
  if (!g_key_file_load_from_file(config, path, G_KEY_FILE_NONE, nullptr)) {
    return 0.0;
  }
  const double scale =
      g_key_file_get_double(config, "KScreen", "ScaleFactor", nullptr);
  return scale >= 1.0 && scale <= 4.0 ? scale : 0.0;
}

// Return only the part of desktop scaling missing from GTK's window metrics.
// XSETTINGS is visible over the X socket, including inside Flatpak.
double X11InterfaceScale(GtkWidget* window) {
  if (!GDK_IS_X11_DISPLAY(gtk_widget_get_display(window))) return 1.0;
  const char* override_scale = g_getenv("GDK_SCALE");
  if (override_scale && g_ascii_strtoll(override_scale, nullptr, 10) > 0) {
    return 1.0;
  }

  GdkScreen* screen = gtk_widget_get_screen(window);
  constexpr double kDefaultDpi = 96.0;
  constexpr double kXSettingsDpiUnit = 1024.0;
  const int gtk_scale = gtk_widget_get_scale_factor(window);
  const int unscaled_dpi = ReadX11Setting(screen, "gdk-unscaled-dpi");
  double correction;
  if (unscaled_dpi > 0) {
    // Plasma publishes the fractional remainder here. GNOME uses the same
    // field for its independent accessibility text size.
    if (!IsKdeDesktop()) return 1.0;
    const int desktop_integer =
        ReadX11Setting(screen, "gdk-window-scaling-factor");
    if (desktop_integer <= 0) return 1.0;
    correction = unscaled_dpi / (kXSettingsDpiUnit * kDefaultDpi) *
                 desktop_integer / gtk_scale;
  } else {
    if (IsKdeDesktop()) {
      const double desktop_scale = ReadPlasmaX11Scale();
      if (desktop_scale > 0.0) return desktop_scale / gtk_scale;
    }
    // Older X11 desktops and standalone WMs commonly publish Xft/DPI or
    // Xft.dpi in RESOURCE_MANAGER. GDK reads both through this setting.
    const int dpi = ReadX11Setting(screen, "gtk-xft-dpi");
    correction = dpi / (kXSettingsDpiUnit * kDefaultDpi * gtk_scale);
    if (gtk_scale > 1 && correction < 1.0) return 1.0;
  }
  return correction >= 0.5 && correction <= 4.0 ? correction : 1.0;
}

}  // namespace

#endif  // RUNNER_X11_INTERFACE_SCALE_H_
