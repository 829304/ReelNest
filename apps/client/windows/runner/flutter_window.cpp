#include "flutter_window.h"

#include <optional>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <powrprof.h>

#include "flutter/generated_plugin_registrant.h"
#include "desktop_multi_window/desktop_multi_window_plugin.h"

namespace {
class PlaybackSleepPlugin : public flutter::Plugin {
 public:
  explicit PlaybackSleepPlugin(flutter::BinaryMessenger* messenger) {
    channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
        messenger, "reelnest/playback_sleep", &flutter::StandardMethodCodec::GetInstance());
    channel_->SetMethodCallHandler([this](const auto& call, auto result) {
      if (call.method_name() != "setActive") { result->NotImplemented(); return; }
      const auto* active = call.arguments() ? std::get_if<bool>(call.arguments()) : nullptr;
      if (!active) { result->Error("invalid_argument", "Expected boolean"); return; }
      if (*active && request_ == nullptr) {
        REASON_CONTEXT reason{};
        reason.Version = POWER_REQUEST_CONTEXT_VERSION;
        reason.Flags = POWER_REQUEST_CONTEXT_SIMPLE_STRING;
        wchar_t message[] = L"ReelNest video playback";
        reason.Reason.SimpleReasonString = message;
        request_ = PowerCreateRequest(&reason);
        if (request_ == INVALID_HANDLE_VALUE) request_ = nullptr;
        if (!request_ || !PowerSetRequest(request_, PowerRequestDisplayRequired) ||
            !PowerSetRequest(request_, PowerRequestSystemRequired)) {
          Release(); result->Error("power_request_failed", "Cannot inhibit sleep"); return;
        }
      } else if (!*active) { Release(); }
      result->Success();
    });
  }
  ~PlaybackSleepPlugin() override { Release(); }
 private:
  void Release() {
    if (!request_) return;
    PowerClearRequest(request_, PowerRequestDisplayRequired);
    PowerClearRequest(request_, PowerRequestSystemRequired);
    CloseHandle(request_); request_ = nullptr;
  }
  HANDLE request_ = nullptr;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};
void RegisterPlaybackSleep(flutter::PluginRegistry* registry) {
  auto* registrar = flutter::PluginRegistrarManager::GetInstance()
      ->GetRegistrar<flutter::PluginRegistrarWindows>(
          registry->GetRegistrarForPlugin("ReelNestPlaybackSleep"));
  registrar->AddPlugin(std::make_unique<PlaybackSleepPlugin>(registrar->messenger()));
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
  RegisterPlaybackSleep(flutter_controller_->engine());
  DesktopMultiWindowSetWindowCreatedCallback([](void* controller) {
    auto* window = reinterpret_cast<flutter::FlutterViewController*>(controller);
    RegisterPlugins(window->engine());
    RegisterPlaybackSleep(window->engine());
  });
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
