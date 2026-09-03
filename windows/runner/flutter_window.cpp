#include "flutter_window.h"

#include <windows.h>

#include <cstdint>
#include <limits>
#include <optional>
#include <string>
#include <variant>
#include <vector>

#include "flutter/generated_plugin_registrant.h"

namespace {

std::wstring Utf8ToWide(const std::string& value) {
  if (value.empty()) return {};
  const int length = MultiByteToWideChar(
      CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
      static_cast<int>(value.size()), nullptr, 0);
  if (length <= 0) return {};
  std::wstring result(length, L'\0');
  MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
                      static_cast<int>(value.size()), result.data(), length);
  return result;
}

std::string WideToUtf8(const std::wstring& value) {
  if (value.empty()) return {};
  const int length = WideCharToMultiByte(
      CP_UTF8, WC_ERR_INVALID_CHARS, value.data(),
      static_cast<int>(value.size()), nullptr, 0, nullptr, nullptr);
  if (length <= 0) return {};
  std::string result(length, '\0');
  WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, value.data(),
                      static_cast<int>(value.size()), result.data(), length,
                      nullptr, nullptr);
  return result;
}

std::string LocalAppDataPath() {
  DWORD length = GetEnvironmentVariableW(L"LOCALAPPDATA", nullptr, 0);
  if (length == 0) return {};
  std::vector<wchar_t> buffer(length, L'\0');
  length = GetEnvironmentVariableW(L"LOCALAPPDATA", buffer.data(), length);
  if (length == 0) return {};
  std::wstring path(buffer.data(), length);
  path += L"\\SingBox Client";
  return WideToUtf8(path);
}

const flutter::EncodableValue* MapValue(
    const flutter::EncodableMap& map, const char* key) {
  const auto it = map.find(flutter::EncodableValue(key));
  return it == map.end() ? nullptr : &it->second;
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  RegisterControlChannel();
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (control_channel_) {
    control_channel_->SetMethodCallHandler(nullptr);
    control_channel_.reset();
  }
  std::wstring ignored;
  windows_proxy_manager_.Restore(&ignored);

  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

void FlutterWindow::RegisterControlChannel() {
  control_channel_ = std::make_unique<
      flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "singbox/control",
      &flutter::StandardMethodCodec::GetInstance());
  control_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "dataDir") {
          const auto path = LocalAppDataPath();
          if (path.empty()) {
            result->Error("data_dir", "LOCALAPPDATA is unavailable");
          } else {
            result->Success(flutter::EncodableValue(path));
          }
          return;
        }

        if (call.method_name() == "isRunningElevated") {
          result->Success(flutter::EncodableValue(IsRunningElevated()));
          return;
        }

        if (call.method_name() == "requestElevation") {
          if (RequestElevation()) {
            result->Success(flutter::EncodableValue(true));
          } else {
            result->Success(flutter::EncodableValue(false));
          }
          return;
        }

        if (call.method_name() == "restoreSystemProxy") {
          std::wstring error;
          if (windows_proxy_manager_.Restore(&error)) {
            result->Success();
          } else {
            result->Error("system_proxy", WideToUtf8(error));
          }
          return;
        }

        if (call.method_name() == "setSystemProxy") {
          const auto* arguments = call.arguments();
          const auto* map = arguments == nullptr
                                ? nullptr
                                : std::get_if<flutter::EncodableMap>(arguments);
          const auto* server = map == nullptr ? nullptr : MapValue(*map, "server");
          if (server == nullptr ||
              !std::holds_alternative<std::string>(*server)) {
            result->Error("system_proxy", "proxy server is missing");
            return;
          }
          const auto proxy_server =
              Utf8ToWide(std::get<std::string>(*server));
          std::wstring error;
          if (proxy_server.empty() ||
              !windows_proxy_manager_.Enable(proxy_server, &error)) {
            result->Error("system_proxy", WideToUtf8(error));
          } else {
            result->Success();
          }
          return;
        }

        if (call.method_name() == "trackProcess") {
          const auto* arguments = call.arguments();
          const auto* map = arguments == nullptr
                                ? nullptr
                                : std::get_if<flutter::EncodableMap>(arguments);
          const auto* pid = map == nullptr ? nullptr : MapValue(*map, "pid");
          const auto process_id =
              pid == nullptr ? std::optional<int64_t>()
                             : pid->TryGetLongValue();
          if (!process_id || *process_id <= 0 ||
              static_cast<uint64_t>(*process_id) >
                  static_cast<uint64_t>(std::numeric_limits<DWORD>::max())) {
            result->Error("process", "sing-box process id is missing");
            return;
          }
          std::wstring error;
          if (windows_proxy_manager_.TrackProcess(
                  static_cast<DWORD>(*process_id), &error)) {
            result->Success();
          } else {
            result->Error("process", WideToUtf8(error));
          }
          return;
        }

        result->NotImplemented();
      });
}
