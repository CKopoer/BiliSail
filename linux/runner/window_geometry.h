#ifndef RUNNER_WINDOW_GEOMETRY_H_
#define RUNNER_WINDOW_GEOMETRY_H_

#include <gtk/gtk.h>

#include <algorithm>
#include <array>

// GTK owns the window; this adapter owns only its timer and machine-local
// presentation record. Wayland compositors may decline absolute positioning.
class WindowGeometry {
 public:
  explicit WindowGeometry(GtkWindow* window) : window_(window) {
    g_autofree gchar* directory =
        g_build_filename(g_get_user_config_dir(), APPLICATION_ID, nullptr);
    path_ = g_build_filename(directory, "window-geometry.ini", nullptr);
    Restore();
    g_signal_connect(window, "configure-event", G_CALLBACK(Configure), this);
    g_signal_connect(window, "window-state-event", G_CALLBACK(StateChanged), this);
    g_signal_connect(window, "delete-event", G_CALLBACK(Closing), this);
    g_signal_connect(window, "destroy", G_CALLBACK(Destroying), this);
  }

  ~WindowGeometry() {
    g_signal_handlers_disconnect_by_data(window_, this);
    if (timer_) g_source_remove(timer_);
    Save();
    g_free(path_);
  }
  WindowGeometry(const WindowGeometry&) = delete;
  WindowGeometry& operator=(const WindowGeometry&) = delete;

 private:
  void Restore() {
    g_autoptr(GKeyFile) file = g_key_file_new();
    if (!g_key_file_load_from_file(file, path_, G_KEY_FILE_NONE, nullptr)) return;
    if (g_key_file_get_integer(file, "main", "version", nullptr) != 1) return;
    gsize count = 0;
    g_autofree gint* record =
        g_key_file_get_integer_list(file, "main", "normal", &count, nullptr);
    g_autoptr(GError) error = nullptr;
    const gboolean maximized =
        g_key_file_get_boolean(file, "main", "maximized", &error);
    if (!record || count != 4 || error ||
        record[0] < -1000000 || record[0] > 1000000 ||
        record[1] < -1000000 || record[1] > 1000000 ||
        record[2] < 100 || record[2] > 100000 ||
        record[3] < 100 || record[3] > 100000) return;
    normal_ = {record[0], record[1], record[2], record[3]};
    GdkDisplay* display = gtk_widget_get_display(GTK_WIDGET(window_));
    GdkMonitor* monitor =
        gdk_display_get_monitor_at_point(display, normal_[0], normal_[1]);
    if (monitor) {
      GdkRectangle work{};
      gdk_monitor_get_workarea(monitor, &work);
      normal_[2] = std::min(normal_[2], work.width);
      normal_[3] = std::min(normal_[3], work.height);
      normal_[0] = std::max(work.x, std::min(normal_[0], work.x + work.width - normal_[2]));
      normal_[1] = std::max(work.y, std::min(normal_[1], work.y + work.height - normal_[3]));
    }
    valid_ = true;
    maximized_ = maximized;
    restoring_maximized_ = maximized;
    gtk_window_set_default_size(window_, normal_[2], normal_[3]);
    gtk_window_move(window_, normal_[0], normal_[1]);
    if (maximized) gtk_window_maximize(window_);
  }

  void Capture() {
    GdkWindow* native = gtk_widget_get_window(GTK_WIDGET(window_));
    if (!native || !gtk_widget_get_visible(GTK_WIDGET(window_))) return;
    const auto state = gdk_window_get_state(native);
    if (state & (GDK_WINDOW_STATE_FULLSCREEN | GDK_WINDOW_STATE_ICONIFIED)) return;
    if (restoring_maximized_ && !(state & GDK_WINDOW_STATE_MAXIMIZED)) return;
    restoring_maximized_ = false;
    maximized_ = (state & GDK_WINDOW_STATE_MAXIMIZED) != 0;
    if (!maximized_) {
      gtk_window_get_position(window_, &normal_[0], &normal_[1]);
      gtk_window_get_size(window_, &normal_[2], &normal_[3]);
      valid_ = normal_[2] >= 100 && normal_[3] >= 100;
    }
  }

  void Save() const {
    if (!valid_) return;
    g_autoptr(GKeyFile) file = g_key_file_new();
    g_key_file_set_integer(file, "main", "version", 1);
    // GLib's setter accepts a mutable pointer but does not change its elements.
    auto normal = normal_;
    g_key_file_set_integer_list(file, "main", "normal", normal.data(), normal.size());
    g_key_file_set_boolean(file, "main", "maximized", maximized_);
    g_autofree gchar* directory = g_path_get_dirname(path_);
    g_autoptr(GError) error = nullptr;
    if (g_mkdir_with_parents(directory, 0700) != 0 ||
        !g_key_file_save_to_file(file, path_, &error)) {
      g_warning("Cannot save BiliSail window geometry.");
    }
  }

  static gboolean Configure(GtkWidget*, GdkEventConfigure*, gpointer data) {
    auto& self = *static_cast<WindowGeometry*>(data);
    self.Capture();
    if (self.timer_) g_source_remove(self.timer_);
    self.timer_ = g_timeout_add(250, [](gpointer value) -> gboolean {
      auto& geometry = *static_cast<WindowGeometry*>(value);
      geometry.timer_ = 0;
      geometry.Save();
      return G_SOURCE_REMOVE;
    }, data);
    return FALSE;
  }

  static gboolean StateChanged(GtkWidget*, GdkEventWindowState*, gpointer data) {
    auto& self = *static_cast<WindowGeometry*>(data);
    self.Capture();
    self.Save();
    return FALSE;
  }

  static gboolean Closing(GtkWidget*, GdkEvent*, gpointer data) {
    auto& self = *static_cast<WindowGeometry*>(data);
    self.Capture();
    self.Save();
    return FALSE;
  }

  static void Destroying(GtkWidget*, gpointer data) {
    delete static_cast<WindowGeometry*>(data);
  }

  GtkWindow* window_;  // Borrowed until its destroy signal.
  gchar* path_ = nullptr;
  guint timer_ = 0;
  std::array<gint, 4> normal_{};
  bool valid_ = false;
  bool maximized_ = false;
  bool restoring_maximized_ = false;
};

#endif  // RUNNER_WINDOW_GEOMETRY_H_
