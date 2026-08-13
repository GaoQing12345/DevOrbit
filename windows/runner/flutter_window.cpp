#include "flutter_window.h"

#include <dwmapi.h>
#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include "flutter/standard_method_codec.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

void FlutterWindow::RegisterWindowEffectsChannel() {
  window_effects_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "dev_orbit/window_effects",
          &flutter::StandardMethodCodec::GetInstance());
  window_effects_channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        if (call.method_name() != "setRadialMode") {
          result->NotImplemented();
          return;
        }
        const auto& args =
            std::get<flutter::EncodableMap>(*call.arguments());
        const auto enabled = std::get<bool>(
            args.at(flutter::EncodableValue("enabled")));
        SetRadialMode(enabled);
        result->Success();
      });
}

void FlutterWindow::RegisterClipboardChannel() {
  clipboard_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "dev_orbit/clipboard",
          &flutter::StandardMethodCodec::GetInstance());
  clipboard_channel_->SetMethodCallHandler(
      [](const auto& call, auto result) {
        if (call.method_name() != "getChangeCount") {
          result->NotImplemented();
          return;
        }
        result->Success(flutter::EncodableValue(
            static_cast<int64_t>(GetClipboardSequenceNumber())));
      });
}

void FlutterWindow::SetRadialMode(bool enabled) {
  constexpr auto kWindowCornerPreference =
      static_cast<DWMWINDOWATTRIBUTE>(33);
  constexpr auto kWindowBorderColor = static_cast<DWMWINDOWATTRIBUTE>(34);
  constexpr int kDoNotRound = 1;
  constexpr int kDefaultCornerPreference = 0;
  constexpr COLORREF kNoBorderColor = 0xFFFFFFFE;
  constexpr COLORREF kDefaultBorderColor = 0xFFFFFFFF;

  const int corner_preference =
      enabled ? kDoNotRound : kDefaultCornerPreference;
  const COLORREF border_color =
      enabled ? kNoBorderColor : kDefaultBorderColor;
  DwmSetWindowAttribute(GetHandle(), kWindowCornerPreference,
                        &corner_preference, sizeof(corner_preference));
  DwmSetWindowAttribute(GetHandle(), kWindowBorderColor, &border_color,
                        sizeof(border_color));
  SetWindowPos(GetHandle(), nullptr, 0, 0, 0, 0,
               SWP_NOACTIVATE | SWP_NOZORDER | SWP_NOMOVE | SWP_NOSIZE |
                   SWP_FRAMECHANGED);
}

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
  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  RegisterWindowEffectsChannel();
  RegisterClipboardChannel();

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
  if (window_effects_channel_) {
    window_effects_channel_ = nullptr;
  }
  if (clipboard_channel_) {
    clipboard_channel_ = nullptr;
  }
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
