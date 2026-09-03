#include "windows_proxy.h"

#include <shellapi.h>
#include <wininet.h>

#include <string>
#include <vector>

namespace {

constexpr wchar_t kInternetSettingsKey[] =
    L"Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings";
constexpr wchar_t kBackupKey[] =
    L"Software\\WildAlley\\SingBoxClient\\ProxyBackup";

constexpr wchar_t kActive[] = L"Active";
constexpr wchar_t kActiveServer[] = L"ActiveServer";
constexpr wchar_t kProxyEnable[] = L"ProxyEnable";
constexpr wchar_t kProxyServer[] = L"ProxyServer";
constexpr wchar_t kProxyOverride[] = L"ProxyOverride";
constexpr wchar_t kAutoConfigUrl[] = L"AutoConfigURL";
constexpr wchar_t kAutoDetect[] = L"AutoDetect";

constexpr wchar_t kProxyEnablePresent[] = L"ProxyEnablePresent";
constexpr wchar_t kProxyServerPresent[] = L"ProxyServerPresent";
constexpr wchar_t kProxyOverridePresent[] = L"ProxyOverridePresent";
constexpr wchar_t kAutoConfigUrlPresent[] = L"AutoConfigURLPresent";
constexpr wchar_t kAutoDetectPresent[] = L"AutoDetectPresent";

std::wstring Win32Error(const wchar_t* operation, LONG code) {
  wchar_t buffer[256] = {};
  const DWORD length = FormatMessageW(
      FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS, nullptr,
      static_cast<DWORD>(code), 0, buffer, sizeof(buffer) / sizeof(wchar_t),
      nullptr);
  std::wstring message(operation);
  message += L" failed (";
  message += std::to_wstring(code);
  message += L")";
  if (length != 0) {
    std::wstring details(buffer, length);
    while (!details.empty() &&
           (details.back() == L'\r' || details.back() == L'\n' ||
            details.back() == L' ')) {
      details.pop_back();
    }
    message += L": ";
    message += details;
  }
  return message;
}

bool ReadDword(HKEY key, const wchar_t* name, bool* present, DWORD* value,
               std::wstring* error) {
  DWORD type = 0;
  DWORD size = sizeof(DWORD);
  DWORD result = 0;
  const LONG status = RegQueryValueExW(
      key, name, nullptr, &type, reinterpret_cast<LPBYTE>(&result), &size);
  if (status == ERROR_FILE_NOT_FOUND) {
    *present = false;
    *value = 0;
    return true;
  }
  if (status != ERROR_SUCCESS || type != REG_DWORD || size != sizeof(DWORD)) {
    *error = Win32Error(L"read registry value", status);
    return false;
  }
  *present = true;
  *value = result;
  return true;
}

bool ReadString(HKEY key, const wchar_t* name, bool* present,
                std::wstring* value, std::wstring* error) {
  DWORD type = 0;
  DWORD size = 0;
  LONG status = RegQueryValueExW(key, name, nullptr, &type, nullptr, &size);
  if (status == ERROR_FILE_NOT_FOUND) {
    *present = false;
    value->clear();
    return true;
  }
  if (status != ERROR_SUCCESS || (type != REG_SZ && type != REG_EXPAND_SZ)) {
    *error = Win32Error(L"read registry value", status);
    return false;
  }

  std::vector<wchar_t> buffer(size / sizeof(wchar_t) + 1, L'\0');
  status = RegQueryValueExW(
      key, name, nullptr, &type, reinterpret_cast<LPBYTE>(buffer.data()),
      &size);
  if (status != ERROR_SUCCESS) {
    *error = Win32Error(L"read registry value", status);
    return false;
  }
  *present = true;
  *value = buffer.data();
  return true;
}

bool WriteDword(HKEY key, const wchar_t* name, DWORD value,
                std::wstring* error) {
  const LONG status = RegSetValueExW(
      key, name, 0, REG_DWORD, reinterpret_cast<const BYTE*>(&value),
      sizeof(value));
  if (status != ERROR_SUCCESS) {
    *error = Win32Error(L"write registry value", status);
    return false;
  }
  return true;
}

bool WriteString(HKEY key, const wchar_t* name, const std::wstring& value,
                 std::wstring* error) {
  const DWORD size = static_cast<DWORD>((value.size() + 1) * sizeof(wchar_t));
  const LONG status = RegSetValueExW(
      key, name, 0, REG_SZ, reinterpret_cast<const BYTE*>(value.c_str()),
      size);
  if (status != ERROR_SUCCESS) {
    *error = Win32Error(L"write registry value", status);
    return false;
  }
  return true;
}

bool DeleteValue(HKEY key, const wchar_t* name, std::wstring* error) {
  const LONG status = RegDeleteValueW(key, name);
  if (status != ERROR_SUCCESS && status != ERROR_FILE_NOT_FOUND) {
    *error = Win32Error(L"delete registry value", status);
    return false;
  }
  return true;
}

bool NotifyWinInet(std::wstring* error) {
  if (!InternetSetOptionW(nullptr, INTERNET_OPTION_SETTINGS_CHANGED, nullptr,
                          0)) {
    *error = Win32Error(L"notify WinINet settings change", GetLastError());
    return false;
  }
  if (!InternetSetOptionW(nullptr, INTERNET_OPTION_REFRESH, nullptr, 0)) {
    *error = Win32Error(L"refresh WinINet settings", GetLastError());
    return false;
  }
  return true;
}

bool WritePresenceAndValue(HKEY key, const wchar_t* presence_name,
                           const wchar_t* value_name, bool present,
                           DWORD value, std::wstring* error) {
  if (!WriteDword(key, presence_name, present ? 1 : 0, error)) return false;
  if (present) return WriteDword(key, value_name, value, error);
  return DeleteValue(key, value_name, error);
}

bool WritePresenceAndValue(HKEY key, const wchar_t* presence_name,
                           const wchar_t* value_name, bool present,
                           const std::wstring& value, std::wstring* error) {
  if (!WriteDword(key, presence_name, present ? 1 : 0, error)) return false;
  if (present) return WriteString(key, value_name, value, error);
  return DeleteValue(key, value_name, error);
}

bool ReadPresence(HKEY key, const wchar_t* presence_name, bool* present,
                  std::wstring* error) {
  bool marker_present = false;
  DWORD marker = 0;
  if (!ReadDword(key, presence_name, &marker_present, &marker, error)) {
    return false;
  }
  *present = marker_present && marker != 0;
  return true;
}

}  // namespace

WindowsProxyManager::~WindowsProxyManager() {
  std::wstring ignored;
  Restore(&ignored);
  if (process_job_ != nullptr) {
    CloseHandle(process_job_);
    process_job_ = nullptr;
  }
}

bool WindowsProxyManager::TrackProcess(DWORD process_id,
                                       std::wstring* error) {
  if (process_id == 0) {
    *error = L"sing-box process id is invalid";
    return false;
  }

  HANDLE job = process_job_;
  bool created_job = false;
  if (job == nullptr) {
    job = CreateJobObjectW(nullptr, nullptr);
    if (job == nullptr) {
      *error = Win32Error(L"create sing-box process job", GetLastError());
      return false;
    }
    JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits = {};
    limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
    if (!SetInformationJobObject(job, JobObjectExtendedLimitInformation,
                                 &limits, sizeof(limits))) {
      *error = Win32Error(L"configure sing-box process job", GetLastError());
      CloseHandle(job);
      return false;
    }
    created_job = true;
  }

  HANDLE process = OpenProcess(PROCESS_SET_QUOTA | PROCESS_TERMINATE, FALSE,
                               process_id);
  if (process == nullptr) {
    *error = Win32Error(L"open sing-box process", GetLastError());
    if (created_job) CloseHandle(job);
    return false;
  }
  const BOOL assigned = AssignProcessToJobObject(job, process);
  const DWORD assign_error = assigned ? ERROR_SUCCESS : GetLastError();
  CloseHandle(process);
  if (!assigned) {
    *error = Win32Error(L"attach sing-box process job", assign_error);
    if (created_job) CloseHandle(job);
    return false;
  }

  if (created_job) process_job_ = job;
  return true;
}

bool WindowsProxyManager::QuerySettings(ProxySettings* settings,
                                        std::wstring* error) {
  HKEY key = nullptr;
  LONG status = RegOpenKeyExW(HKEY_CURRENT_USER, kInternetSettingsKey, 0,
                             KEY_READ, &key);
  if (status == ERROR_FILE_NOT_FOUND) {
    *settings = ProxySettings();
    return true;
  }
  if (status != ERROR_SUCCESS) {
    *error = Win32Error(L"open Internet Settings", status);
    return false;
  }

  const bool ok =
      ReadDword(key, kProxyEnable, &settings->proxy_enable_present,
                &settings->proxy_enable, error) &&
      ReadString(key, kProxyServer, &settings->proxy_server_present,
                 &settings->proxy_server, error) &&
      ReadString(key, kProxyOverride, &settings->proxy_override_present,
                 &settings->proxy_override, error) &&
      ReadString(key, kAutoConfigUrl, &settings->auto_config_url_present,
                 &settings->auto_config_url, error) &&
      ReadDword(key, kAutoDetect, &settings->auto_detect_present,
                &settings->auto_detect, error);
  RegCloseKey(key);
  return ok;
}

bool WindowsProxyManager::ApplySettings(const ProxySettings& settings,
                                        std::wstring* error) {
  HKEY key = nullptr;
  DWORD disposition = 0;
  LONG status = RegCreateKeyExW(HKEY_CURRENT_USER, kInternetSettingsKey, 0,
                                nullptr, 0, KEY_SET_VALUE, nullptr, &key,
                                &disposition);
  if (status != ERROR_SUCCESS) {
    *error = Win32Error(L"open Internet Settings for writing", status);
    return false;
  }

  const bool ok =
      (settings.proxy_enable_present
           ? WriteDword(key, kProxyEnable, settings.proxy_enable, error)
           : DeleteValue(key, kProxyEnable, error)) &&
      (settings.proxy_server_present
           ? WriteString(key, kProxyServer, settings.proxy_server, error)
           : DeleteValue(key, kProxyServer, error)) &&
      (settings.proxy_override_present
           ? WriteString(key, kProxyOverride, settings.proxy_override, error)
           : DeleteValue(key, kProxyOverride, error)) &&
      (settings.auto_config_url_present
           ? WriteString(key, kAutoConfigUrl, settings.auto_config_url, error)
           : DeleteValue(key, kAutoConfigUrl, error)) &&
      (settings.auto_detect_present
           ? WriteDword(key, kAutoDetect, settings.auto_detect, error)
           : DeleteValue(key, kAutoDetect, error));
  RegCloseKey(key);
  if (!ok) return false;
  return NotifyWinInet(error);
}

bool WindowsProxyManager::SaveBackup(const ProxySettings& settings,
                                     const std::wstring& active_server,
                                     std::wstring* error) {
  HKEY key = nullptr;
  DWORD disposition = 0;
  LONG status = RegCreateKeyExW(HKEY_CURRENT_USER, kBackupKey, 0, nullptr, 0,
                                KEY_SET_VALUE, nullptr, &key, &disposition);
  if (status != ERROR_SUCCESS) {
    *error = Win32Error(L"create proxy backup", status);
    return false;
  }

  bool ok = WriteDword(key, kActive, 1, error) &&
            WriteString(key, kActiveServer, active_server, error) &&
            WritePresenceAndValue(key, kProxyEnablePresent, kProxyEnable,
                                  settings.proxy_enable_present,
                                  settings.proxy_enable, error) &&
            WritePresenceAndValue(key, kProxyServerPresent, kProxyServer,
                                  settings.proxy_server_present,
                                  settings.proxy_server, error) &&
            WritePresenceAndValue(key, kProxyOverridePresent, kProxyOverride,
                                  settings.proxy_override_present,
                                  settings.proxy_override, error) &&
            WritePresenceAndValue(key, kAutoConfigUrlPresent, kAutoConfigUrl,
                                  settings.auto_config_url_present,
                                  settings.auto_config_url, error) &&
            WritePresenceAndValue(key, kAutoDetectPresent, kAutoDetect,
                                  settings.auto_detect_present,
                                  settings.auto_detect, error);
  RegCloseKey(key);
  return ok;
}

bool WindowsProxyManager::LoadBackup(ProxySettings* settings,
                                     std::wstring* active_server, bool* found,
                                     std::wstring* error) {
  *found = false;
  HKEY key = nullptr;
  const LONG status =
      RegOpenKeyExW(HKEY_CURRENT_USER, kBackupKey, 0, KEY_READ, &key);
  if (status == ERROR_FILE_NOT_FOUND) return true;
  if (status != ERROR_SUCCESS) {
    *error = Win32Error(L"open proxy backup", status);
    return false;
  }

  bool active_present = false;
  DWORD active = 0;
  bool ok = ReadDword(key, kActive, &active_present, &active, error);
  if (!ok || !active_present || active == 0) {
    RegCloseKey(key);
    return ok;
  }
  bool server_present = false;
  ok = ReadString(key, kActiveServer, &server_present, active_server, error);
  if (!ok || !server_present || active_server->empty()) {
    RegCloseKey(key);
    return ok;
  }

  ok = ReadPresence(key, kProxyEnablePresent,
                   &settings->proxy_enable_present, error) &&
       ReadPresence(key, kProxyServerPresent, &settings->proxy_server_present,
                    error) &&
       ReadPresence(key, kProxyOverridePresent,
                    &settings->proxy_override_present, error) &&
       ReadPresence(key, kAutoConfigUrlPresent,
                    &settings->auto_config_url_present, error) &&
       ReadPresence(key, kAutoDetectPresent, &settings->auto_detect_present,
                    error);
  if (ok && settings->proxy_enable_present) {
    bool ignored = false;
    ok = ReadDword(key, kProxyEnable, &ignored, &settings->proxy_enable,
                   error);
  }
  if (ok && settings->proxy_server_present) {
    bool ignored = false;
    ok = ReadString(key, kProxyServer, &ignored, &settings->proxy_server,
                    error);
  }
  if (ok && settings->proxy_override_present) {
    bool ignored = false;
    ok = ReadString(key, kProxyOverride, &ignored, &settings->proxy_override,
                    error);
  }
  if (ok && settings->auto_config_url_present) {
    bool ignored = false;
    ok = ReadString(key, kAutoConfigUrl, &ignored,
                    &settings->auto_config_url, error);
  }
  if (ok && settings->auto_detect_present) {
    bool ignored = false;
    ok = ReadDword(key, kAutoDetect, &ignored, &settings->auto_detect, error);
  }
  RegCloseKey(key);
  *found = ok;
  return ok;
}

bool WindowsProxyManager::ClearBackup(std::wstring* error) {
  const LONG status = RegDeleteTreeW(HKEY_CURRENT_USER, kBackupKey);
  if (status != ERROR_SUCCESS && status != ERROR_FILE_NOT_FOUND) {
    *error = Win32Error(L"clear proxy backup", status);
    return false;
  }
  return true;
}

bool WindowsProxyManager::Enable(const std::wstring& proxy_server,
                                 std::wstring* error) {
  if (proxy_server.empty()) {
    *error = L"proxy server is empty";
    return false;
  }
  if (active_) return active_server_ == proxy_server;

  // Recover a backup left by a crashed/forcibly terminated previous process
  // before taking a fresh snapshot.
  ProxySettings stale;
  std::wstring stale_server;
  bool stale_found = false;
  if (!LoadBackup(&stale, &stale_server, &stale_found, error)) return false;
  if (stale_found) {
    ProxySettings current;
    if (!QuerySettings(&current, error)) return false;
    const bool still_owned = current.proxy_enable_present &&
                             current.proxy_enable != 0 &&
                             current.proxy_server_present &&
                             current.proxy_server == stale_server;
    if (still_owned && !ApplySettings(stale, error)) return false;
    if (!ClearBackup(error)) return false;
  }

  ProxySettings backup;
  if (!QuerySettings(&backup, error)) return false;
  if (!SaveBackup(backup, proxy_server, error)) return false;

  ProxySettings active;
  active.proxy_enable_present = true;
  active.proxy_enable = 1;
  active.proxy_server_present = true;
  active.proxy_server = proxy_server;
  active.proxy_override_present = true;
  active.proxy_override = L"<local>";
  active.auto_config_url_present = false;
  active.auto_detect_present = true;
  active.auto_detect = 0;
  if (!ApplySettings(active, error)) {
    std::wstring ignored;
    ApplySettings(backup, &ignored);
    ClearBackup(&ignored);
    return false;
  }

  saved_settings_ = backup;
  active_server_ = proxy_server;
  active_ = true;
  return true;
}

bool WindowsProxyManager::Restore(std::wstring* error) {
  ProxySettings backup = saved_settings_;
  std::wstring expected_server = active_server_;
  bool found = active_;
  if (!found &&
      !LoadBackup(&backup, &expected_server, &found, error)) {
    return false;
  }
  if (!found) return true;

  ProxySettings current;
  if (!QuerySettings(&current, error)) return false;
  const bool still_owned = current.proxy_enable_present &&
                           current.proxy_enable != 0 &&
                           current.proxy_server_present &&
                           current.proxy_server == expected_server;
  if (still_owned && !ApplySettings(backup, error)) return false;

  const bool cleared = ClearBackup(error);
  active_ = false;
  active_server_.clear();
  saved_settings_ = ProxySettings();
  return cleared;
}

bool IsRunningElevated() {
  HANDLE token = nullptr;
  if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token)) {
    return false;
  }

  TOKEN_ELEVATION elevation;
  DWORD size = sizeof(TOKEN_ELEVATION);
  bool elevated = false;

  if (GetTokenInformation(token, TokenElevation, &elevation, size, &size)) {
    elevated = elevation.TokenIsElevated != 0;
  }

  CloseHandle(token);
  return elevated;
}

bool RequestElevation() {
  wchar_t exe_path[MAX_PATH];
  if (GetModuleFileNameW(nullptr, exe_path, MAX_PATH) == 0) {
    return false;
  }

  SHELLEXECUTEINFOW info = {};
  info.cbSize = sizeof(SHELLEXECUTEINFOW);
  info.fMask = SEE_MASK_NOCLOSEPROCESS;
  info.lpVerb = L"runas";
  info.lpFile = exe_path;
  info.lpParameters = L"--elevated-restart";
  info.nShow = SW_SHOWNORMAL;

  if (!ShellExecuteExW(&info)) {
    return false;
  }

  if (info.hProcess != nullptr) {
    CloseHandle(info.hProcess);
  }

  return true;
}
