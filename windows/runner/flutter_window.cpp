#include "flutter_window.h"

#include <windows.h>
#include <dwmapi.h>
#include <wincred.h>
#include <optional>
#include <string>
#include <vector>

#include "flutter/generated_plugin_registrant.h"
#include "flutter/standard_method_codec.h"
#include "utils.h"

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
      [this](const auto& call, auto result) {
        if (call.method_name() == "getChangeCount") {
          result->Success(flutter::EncodableValue(
              static_cast<int64_t>(GetClipboardSequenceNumber())));
          return;
        }
        if (call.method_name() == "takePendingPasteText") {
          if (pending_paste_text_) {
            result->Success(flutter::EncodableValue(*pending_paste_text_));
            pending_paste_text_.reset();
          } else {
            result->Success();
          }
          return;
        }
        result->NotImplemented();
      });
}

void FlutterWindow::RegisterCredentialsChannel() {
  credentials_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "dev_orbit/credentials",
          &flutter::StandardMethodCodec::GetInstance());
  credentials_channel_->SetMethodCallHandler(
      [](const auto& call, auto result) {
        if (!call.arguments() ||
            !std::holds_alternative<flutter::EncodableMap>(*call.arguments())) {
          result->Error("invalid_arguments", "Missing credential arguments");
          return;
        }
        const auto& args = std::get<flutter::EncodableMap>(*call.arguments());
        const auto key_it = args.find(flutter::EncodableValue("key"));
        if (key_it == args.end() ||
            !std::holds_alternative<std::string>(key_it->second)) {
          result->Error("invalid_arguments", "Missing credential key");
          return;
        }

        const auto key = std::get<std::string>(key_it->second);
        const auto target = L"DevOrbit/" + Utf16FromUtf8(key);
        if (call.method_name() == "read") {
          PCREDENTIALW credential = nullptr;
          if (!CredReadW(target.c_str(), CRED_TYPE_GENERIC, 0, &credential)) {
            if (GetLastError() == ERROR_NOT_FOUND) {
              result->Success();
            } else {
              result->Error("credential_read_failed", "Windows credential read failed");
            }
            return;
          }
          std::string value(
              reinterpret_cast<const char*>(credential->CredentialBlob),
              credential->CredentialBlobSize);
          if (credential->CredentialBlobSize > 0) {
            SecureZeroMemory(credential->CredentialBlob,
                             credential->CredentialBlobSize);
          }
          CredFree(credential);
          result->Success(flutter::EncodableValue(value));
          return;
        }

        if (call.method_name() == "write") {
          const auto value_it = args.find(flutter::EncodableValue("value"));
          if (value_it == args.end() ||
              !std::holds_alternative<std::string>(value_it->second)) {
            result->Error("invalid_arguments", "Missing credential value");
            return;
          }
          const auto& value = std::get<std::string>(value_it->second);
          std::vector<BYTE> blob(value.begin(), value.end());
          CREDENTIALW credential = {};
          credential.Type = CRED_TYPE_GENERIC;
          credential.TargetName = const_cast<LPWSTR>(target.c_str());
          credential.CredentialBlobSize = static_cast<DWORD>(blob.size());
          credential.CredentialBlob = blob.data();
          credential.Persist = CRED_PERSIST_LOCAL_MACHINE;
          credential.UserName = const_cast<LPWSTR>(L"DevOrbit");
          const auto success = CredWriteW(&credential, 0);
          if (!blob.empty()) SecureZeroMemory(blob.data(), blob.size());
          if (!success) {
            result->Error("credential_write_failed", "Windows credential write failed");
            return;
          }
          result->Success();
          return;
        }

        if (call.method_name() == "delete") {
          if (!CredDeleteW(target.c_str(), CRED_TYPE_GENERIC, 0) &&
              GetLastError() != ERROR_NOT_FOUND) {
            result->Error("credential_delete_failed", "Windows credential delete failed");
            return;
          }
          result->Success();
          return;
        }

        result->NotImplemented();
      });
}

void FlutterWindow::CapturePendingPasteText() {
  if (!OpenClipboard(GetHandle())) {
    return;
  }
  HANDLE data = ::GetClipboardData(CF_UNICODETEXT);
  if (data) {
    const wchar_t* text = static_cast<const wchar_t*>(GlobalLock(data));
    if (text) {
      pending_paste_text_ = Utf8FromUtf16(text);
      GlobalUnlock(data);
    }
  }
  CloseClipboard();
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
  RegisterCredentialsChannel();

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
  if (credentials_channel_) {
    credentials_channel_ = nullptr;
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
  if (message == WM_KEYDOWN && wparam == 'V' &&
      (GetKeyState(VK_CONTROL) & 0x8000) != 0) {
    CapturePendingPasteText();
  }

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
