#ifndef RUNNER_WINDOW_GEOMETRY_STORE_H_
#define RUNNER_WINDOW_GEOMETRY_STORE_H_

#include <windows.h>

#include <array>
#include <string>
#include <utility>

#include "playback_window_geometry.h"

namespace playback_window {

// Machine-local presentation state, independent of accounts and user settings.
// Each role is one versioned registry value, so a write cannot mix rectangles
// and zoom flags from different captures. No credentials are stored here.
class WindowGeometryStore {
 public:
  explicit WindowGeometryStore(
      std::wstring role = {},
      std::wstring key = L"Software\\BiliSail\\WindowGeometry")
      : role_(std::move(role)), key_(std::move(key)) {}

  bool enabled() const { return !role_.empty(); }

  void Load(GeometrySession& session) const {
    if (!enabled()) return;
    Record record{};
    DWORD bytes = sizeof(record);
    if (RegGetValueW(HKEY_CURRENT_USER, key_.c_str(), role_.c_str(),
                     RRF_RT_REG_BINARY, nullptr, record.data(), &bytes) !=
            ERROR_SUCCESS ||
        bytes != sizeof(record) || record[0] != kVersion ||
        (record[5] != 0 && record[5] != 1)) return;
    session.Load({static_cast<double>(record[1]), static_cast<double>(record[2]),
                  static_cast<double>(record[3]), static_cast<double>(record[4])},
                 record[5] != 0);
  }

  bool Save(const GeometrySession& session) const {
    if (!enabled() || !session.normal()) return true;
    const auto& bounds = *session.normal();
    const Record record{kVersion, static_cast<int32_t>(std::lround(bounds.left)),
                        static_cast<int32_t>(std::lround(bounds.top)),
                        static_cast<int32_t>(std::lround(bounds.width)),
                        static_cast<int32_t>(std::lround(bounds.height)),
                        session.maximized() ? 1 : 0};
    // Avoid rewriting unchanged state (including fullscreen/minimized captures).
    Record previous{};
    DWORD bytes = sizeof(previous);
    if (RegGetValueW(HKEY_CURRENT_USER, key_.c_str(), role_.c_str(),
                     RRF_RT_REG_BINARY, nullptr, previous.data(), &bytes) ==
            ERROR_SUCCESS && bytes == sizeof(previous) && previous == record) {
      return true;
    }
    RegistryKey key;
    if (RegCreateKeyExW(HKEY_CURRENT_USER, key_.c_str(), 0, nullptr, 0,
                        KEY_SET_VALUE, nullptr, &key.handle, nullptr) !=
        ERROR_SUCCESS) return false;
    return RegSetValueExW(key.handle, role_.c_str(), 0, REG_BINARY,
                          reinterpret_cast<const BYTE*>(record.data()),
                          sizeof(record)) == ERROR_SUCCESS;
  }

 private:
  struct RegistryKey {
    HKEY handle = nullptr;
    ~RegistryKey() { if (handle) RegCloseKey(handle); }
    RegistryKey() = default;
    RegistryKey(const RegistryKey&) = delete;
    RegistryKey& operator=(const RegistryKey&) = delete;
  };
  using Record = std::array<int32_t, 6>;
  static constexpr int32_t kVersion = 1;
  std::wstring role_;
  std::wstring key_;
};

}  // namespace playback_window

#endif  // RUNNER_WINDOW_GEOMETRY_STORE_H_
