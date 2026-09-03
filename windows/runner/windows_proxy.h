#ifndef RUNNER_WINDOWS_PROXY_H_
#define RUNNER_WINDOWS_PROXY_H_

#include <windows.h>

#include <string>

/// Owns the per-user WinINet proxy setting while the Windows runtime is up.
///
/// The previous values are copied into a small HKCU backup key before the
/// first enable. That makes a normal close and a subsequent app launch after a
/// crash safe: user proxy/PAC settings are restored instead of being cleared or
/// silently replaced.
class WindowsProxyManager {
 public:
  WindowsProxyManager() = default;
  ~WindowsProxyManager();

  WindowsProxyManager(const WindowsProxyManager&) = delete;
  WindowsProxyManager& operator=(const WindowsProxyManager&) = delete;

  bool Enable(const std::wstring& proxy_server, std::wstring* error);
  bool Restore(std::wstring* error);
  bool TrackProcess(DWORD process_id, std::wstring* error);

 private:
  struct ProxySettings {
    bool proxy_enable_present = false;
    DWORD proxy_enable = 0;
    bool proxy_server_present = false;
    std::wstring proxy_server;
    bool proxy_override_present = false;
    std::wstring proxy_override;
    bool auto_config_url_present = false;
    std::wstring auto_config_url;
    bool auto_detect_present = false;
    DWORD auto_detect = 0;
  };

  static bool QuerySettings(ProxySettings* settings, std::wstring* error);
  static bool ApplySettings(const ProxySettings& settings, std::wstring* error);
  static bool SaveBackup(const ProxySettings& settings,
                         const std::wstring& active_server,
                         std::wstring* error);
  static bool LoadBackup(ProxySettings* settings,
                         std::wstring* active_server,
                         bool* found,
                         std::wstring* error);
  static bool ClearBackup(std::wstring* error);

  bool active_ = false;
  std::wstring active_server_;
  ProxySettings saved_settings_;
  HANDLE process_job_ = nullptr;
};

/// Checks if the current process is running with administrator privileges.
bool IsRunningElevated();

/// Requests administrator elevation by restarting the application with UAC.
///
/// Returns true if elevation was requested successfully (the current process
/// will exit). Returns false if the user declined or elevation is unavailable.
bool RequestElevation();

#endif  // RUNNER_WINDOWS_PROXY_H_
