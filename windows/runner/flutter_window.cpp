#include "flutter_window.h"

#include <windows.h>
#include <dwmapi.h>
#include <tlhelp32.h>
#include <wincred.h>
#include <cstdlib>
#include <optional>
#include <string>
#include <vector>

#include "flutter/generated_plugin_registrant.h"
#include "flutter/standard_method_codec.h"
#include "utils.h"

namespace {

constexpr wchar_t kToolWindowReadyProperty[] =
    L"DevOrbitToolWindowReady";
constexpr UINT_PTR kPasteCaptureRetryTimer = 0xD30B;
constexpr UINT kPasteCaptureRetryDelayMs = 5;
// Clipboard providers such as QuickClipboard clear the clipboard and then
// publish several formats one after another. Keep polling long enough for the
// final text format to become available instead of treating each intermediate
// update as a different paste operation.
constexpr int kPasteCaptureMaxRetries = 32;

struct WindowActivationRequest {
  DWORD process_id;
  bool found;
};

bool IsCurrentExecutable(DWORD process_id) {
  HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE,
                               process_id);
  if (!process) {
    return false;
  }
  std::vector<wchar_t> process_path(32768);
  DWORD process_path_size = static_cast<DWORD>(process_path.size());
  const bool queried = QueryFullProcessImageNameW(
      process, 0, process_path.data(), &process_path_size);
  CloseHandle(process);
  if (!queried) {
    return false;
  }

  std::vector<wchar_t> current_path(32768);
  const DWORD current_path_size = GetModuleFileNameW(
      nullptr, current_path.data(), static_cast<DWORD>(current_path.size()));
  if (current_path_size == 0 || current_path_size >= current_path.size()) {
    return false;
  }
  return _wcsicmp(process_path.data(), current_path.data()) == 0;
}

BOOL CALLBACK ActivateProcessWindow(HWND window, LPARAM parameter) {
  auto* request = reinterpret_cast<WindowActivationRequest*>(parameter);
  DWORD window_process_id = 0;
  GetWindowThreadProcessId(window, &window_process_id);
  if (window_process_id != request->process_id ||
      GetWindow(window, GW_OWNER) != nullptr) {
    return TRUE;
  }
  if (!IsWindowVisible(window) &&
      GetPropW(window, kToolWindowReadyProperty) == nullptr) {
    return TRUE;
  }
  request->found = true;
  if (IsIconic(window)) {
    ShowWindow(window, SW_RESTORE);
  } else {
    ShowWindow(window, SW_SHOW);
  }
  BringWindowToTop(window);
  SetForegroundWindow(window);
  return FALSE;
}

void TerminateSiblingProcesses() {
  const DWORD current_process_id = GetCurrentProcessId();
  HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if (snapshot == INVALID_HANDLE_VALUE) {
    return;
  }

  PROCESSENTRY32W entry = {};
  entry.dwSize = sizeof(entry);
  if (Process32FirstW(snapshot, &entry)) {
    do {
      if (entry.th32ProcessID == current_process_id ||
          !IsCurrentExecutable(entry.th32ProcessID)) {
        continue;
      }
      HANDLE process = OpenProcess(PROCESS_TERMINATE, FALSE,
                                   entry.th32ProcessID);
      if (process) {
        TerminateProcess(process, EXIT_SUCCESS);
        CloseHandle(process);
      }
    } while (Process32NextW(snapshot, &entry));
  }
  CloseHandle(snapshot);
}

std::optional<int64_t> ClipboardSessionId(
    const flutter::MethodCall<flutter::EncodableValue>& call) {
  if (!call.arguments() ||
      !std::holds_alternative<flutter::EncodableMap>(*call.arguments())) {
    return std::nullopt;
  }
  const auto& args = std::get<flutter::EncodableMap>(*call.arguments());
  const auto session_it = args.find(flutter::EncodableValue("sessionId"));
  if (session_it == args.end()) {
    return std::nullopt;
  }
  if (std::holds_alternative<int64_t>(session_it->second)) {
    return std::get<int64_t>(session_it->second);
  }
  if (std::holds_alternative<int32_t>(session_it->second)) {
    return static_cast<int64_t>(std::get<int32_t>(session_it->second));
  }
  return std::nullopt;
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

void FlutterWindow::SetShowOnFirstFrame(bool show) {
  show_on_first_frame_ = show;
}

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
          const auto session_id = ClipboardSessionId(call);
          if (!session_id) {
            result->Error("invalid_arguments", "Missing clipboard session ID");
            return;
          }
          const auto text = TakePendingPasteText(*session_id);
          if (text) {
            result->Success(flutter::EncodableValue(*text));
          } else {
            result->Success();
          }
          return;
        }
        if (call.method_name() == "armPasteCapture") {
          const auto session_id = ClipboardSessionId(call);
          if (!session_id) {
            result->Error("invalid_arguments", "Missing clipboard session ID");
            return;
          }
          ArmPasteCapture(*session_id);
          result->Success();
          return;
        }
        if (call.method_name() == "didPasteCaptureObserveChange") {
          const auto session_id = ClipboardSessionId(call);
          if (!session_id) {
            result->Error("invalid_arguments", "Missing clipboard session ID");
            return;
          }
          result->Success(flutter::EncodableValue(
              DidPasteCaptureObserveChange(*session_id)));
          return;
        }
        if (call.method_name() == "discardPendingPasteText") {
          const auto session_id = ClipboardSessionId(call);
          if (!session_id) {
            result->Error("invalid_arguments", "Missing clipboard session ID");
            return;
          }
          DiscardPendingPasteText(*session_id);
          result->Success();
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

void FlutterWindow::RegisterProcessWindowChannel() {
  process_window_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "dev_orbit/process_window",
          &flutter::StandardMethodCodec::GetInstance());
  process_window_channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        if (call.method_name() == "markReadyForActivation") {
          SetPropW(GetHandle(), kToolWindowReadyProperty,
                   reinterpret_cast<HANDLE>(static_cast<INT_PTR>(1)));
          result->Success();
          return;
        }
        if (call.method_name() != "activate" || !call.arguments() ||
            !std::holds_alternative<flutter::EncodableMap>(*call.arguments())) {
          result->NotImplemented();
          return;
        }
        const auto& args = std::get<flutter::EncodableMap>(*call.arguments());
        const auto process_id_it =
            args.find(flutter::EncodableValue("processId"));
        if (process_id_it == args.end()) {
          result->Error("invalid_arguments", "Missing process ID");
          return;
        }
        DWORD process_id = 0;
        if (std::holds_alternative<int32_t>(process_id_it->second)) {
          process_id = static_cast<DWORD>(
              std::get<int32_t>(process_id_it->second));
        } else if (std::holds_alternative<int64_t>(process_id_it->second)) {
          process_id = static_cast<DWORD>(
              std::get<int64_t>(process_id_it->second));
        } else {
          result->Error("invalid_arguments", "Invalid process ID");
          return;
        }
        if (!IsCurrentExecutable(process_id)) {
          result->Success(flutter::EncodableValue(false));
          return;
        }
        AllowSetForegroundWindow(process_id);
        WindowActivationRequest request = {process_id, false};
        EnumWindows(ActivateProcessWindow,
                    reinterpret_cast<LPARAM>(&request));
        result->Success(flutter::EncodableValue(request.found));
      });
}

void FlutterWindow::RegisterAppLifecycleChannel() {
  app_lifecycle_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "dev_orbit/app_lifecycle",
          &flutter::StandardMethodCodec::GetInstance());
  app_lifecycle_channel_->SetMethodCallHandler(
      [](const auto& call, auto result) {
        if (call.method_name() != "quit") {
          result->NotImplemented();
          return;
        }
        result->Success();
        TerminateSiblingProcesses();
        PostQuitMessage(0);
      });
}

void FlutterWindow::BeginPasteCapture(std::optional<int64_t> session_id) {
  ResetPasteCapture();
  paste_capture_armed_ = true;
  paste_capture_session_id_ = session_id;
  paste_capture_baseline_sequence_ = GetClipboardSequenceNumber();
}

void FlutterWindow::ArmPasteCapture(int64_t session_id) {
  if (paste_capture_armed_) {
    if (!paste_capture_session_id_) {
      paste_capture_session_id_ = session_id;
      if (pending_paste_text_) {
        NotifyPendingPasteText();
      } else {
        HandleClipboardUpdate();
      }
      return;
    }
    if (*paste_capture_session_id_ == session_id) {
      NotifyPendingPasteText();
      return;
    }
  }
  BeginPasteCapture(session_id);
}

bool FlutterWindow::DidPasteCaptureObserveChange(int64_t session_id) {
  if (!paste_capture_armed_ || !paste_capture_session_id_ ||
      *paste_capture_session_id_ != session_id) {
    return false;
  }
  HandleClipboardUpdate();
  return paste_capture_invalidated_ ||
         paste_capture_observed_sequence_ != 0;
}

void FlutterWindow::DiscardPendingPasteText(int64_t session_id) {
  if (!paste_capture_session_id_ ||
      *paste_capture_session_id_ != session_id) {
    return;
  }
  ResetPasteCapture();
}

std::optional<std::string> FlutterWindow::TakePendingPasteText(
    int64_t session_id) {
  if (!paste_capture_armed_ || !paste_capture_session_id_ ||
      *paste_capture_session_id_ != session_id || !pending_paste_text_) {
    return std::nullopt;
  }
  auto text = pending_paste_text_;
  ResetPasteCapture();
  return text;
}

void FlutterWindow::HandleClipboardUpdate() {
  if (!paste_capture_armed_ || paste_capture_invalidated_ ||
      pending_paste_text_) {
    return;
  }
  const DWORD sequence = GetClipboardSequenceNumber();
  if (sequence == 0 || sequence == paste_capture_baseline_sequence_) {
    return;
  }

  // A single logical paste may produce multiple WM_CLIPBOARDUPDATE messages:
  // EmptyClipboard followed by CF_UNICODETEXT/HTML/etc. Do not require a
  // contiguous sequence number and do not invalidate when a newer format
  // arrives before the text handle is readable. The first readable text is
  // the item selected in the third-party clipboard and must be retained even
  // if that tool changes the clipboard again during paste.
  if (paste_capture_observed_sequence_ != sequence) {
    paste_capture_observed_sequence_ = sequence;
    paste_capture_retry_count_ = 0;
  }
  if (!CaptureObservedPasteText()) {
    RetryPendingPasteCapture();
  }
}

void FlutterWindow::RetryPendingPasteCapture() {
  if (!paste_capture_armed_ || paste_capture_invalidated_ ||
      pending_paste_text_) {
    return;
  }
  if (++paste_capture_retry_count_ > kPasteCaptureMaxRetries) {
    InvalidatePasteCapture();
    return;
  }
  SetTimer(GetHandle(), kPasteCaptureRetryTimer,
           kPasteCaptureRetryDelayMs, nullptr);
}

bool FlutterWindow::CaptureObservedPasteText() {
  if (!paste_capture_armed_ || paste_capture_invalidated_ ||
      paste_capture_observed_sequence_ == 0) {
    return false;
  }

  // The clipboard sequence can advance while a provider is publishing its
  // formats. Refresh the candidate sequence instead of rejecting the capture;
  // OpenClipboard/GetClipboardData below is the authoritative availability
  // check for the current update.
  const DWORD sequence = GetClipboardSequenceNumber();
  if (sequence == 0 || sequence == paste_capture_baseline_sequence_) {
    return false;
  }
  if (paste_capture_observed_sequence_ != sequence) {
    paste_capture_observed_sequence_ = sequence;
    paste_capture_retry_count_ = 0;
  }

  if (!OpenClipboard(GetHandle())) {
    return false;
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
  if (pending_paste_text_) {
    KillTimer(GetHandle(), kPasteCaptureRetryTimer);
    NotifyPendingPasteText();
  }
  return pending_paste_text_.has_value();
}

void FlutterWindow::NotifyPendingPasteText() {
  if (paste_capture_notification_sent_ || !clipboard_channel_ ||
      !paste_capture_session_id_ || !pending_paste_text_) {
    return;
  }

  flutter::EncodableMap arguments;
  arguments[flutter::EncodableValue("sessionId")] = flutter::EncodableValue(
      *paste_capture_session_id_);
  paste_capture_notification_sent_ = true;
  clipboard_channel_->InvokeMethod(
      "pasteTextCaptured",
      std::make_unique<flutter::EncodableValue>(arguments));
}

void FlutterWindow::InvalidatePasteCapture() {
  KillTimer(GetHandle(), kPasteCaptureRetryTimer);
  pending_paste_text_.reset();
  paste_capture_retry_count_ = 0;
  paste_capture_invalidated_ = true;
}

void FlutterWindow::ResetPasteCapture() {
  KillTimer(GetHandle(), kPasteCaptureRetryTimer);
  paste_capture_armed_ = false;
  pending_paste_text_.reset();
  paste_capture_session_id_.reset();
  paste_capture_baseline_sequence_ = 0;
  paste_capture_observed_sequence_ = 0;
  paste_capture_retry_count_ = 0;
  paste_capture_invalidated_ = false;
  paste_capture_notification_sent_ = false;
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
  RegisterProcessWindowChannel();
  RegisterAppLifecycleChannel();
  AddClipboardFormatListener(GetHandle());

  if (show_on_first_frame_) {
    flutter_controller_->engine()->SetNextFrameCallback([this]() {
      Show();
    });
  }

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  ResetPasteCapture();
  RemovePropW(GetHandle(), kToolWindowReadyProperty);
  RemoveClipboardFormatListener(GetHandle());
  if (window_effects_channel_) {
    window_effects_channel_ = nullptr;
  }
  if (clipboard_channel_) {
    clipboard_channel_ = nullptr;
  }
  if (credentials_channel_) {
    credentials_channel_ = nullptr;
  }
  if (process_window_channel_) {
    process_window_channel_ = nullptr;
  }
  if (app_lifecycle_channel_) {
    app_lifecycle_channel_ = nullptr;
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
  const bool is_paste_key =
      (message == WM_KEYDOWN || message == WM_SYSKEYDOWN) &&
      ((wparam == 'V' && (GetKeyState(VK_CONTROL) & 0x8000) != 0) ||
       (wparam == VK_INSERT && (GetKeyState(VK_SHIFT) & 0x8000) != 0));
  if (is_paste_key && paste_capture_armed_ && !pending_paste_text_) {
    // Clipboard update messages and injected keyboard messages originate on
    // different threads. Re-check synchronously at the actual paste boundary
    // so a queued WM_CLIPBOARDUPDATE cannot make Flutter read stale content.
    HandleClipboardUpdate();
  }
  if (message == WM_CLIPBOARDUPDATE && paste_capture_armed_) {
    HandleClipboardUpdate();
  }
  if (message == WM_ACTIVATE && LOWORD(wparam) == WA_INACTIVE) {
    if (!paste_capture_armed_ || !paste_capture_session_id_) {
      BeginPasteCapture(std::nullopt);
    }
  }
  if (message == WM_TIMER && wparam == kPasteCaptureRetryTimer) {
    KillTimer(GetHandle(), kPasteCaptureRetryTimer);
    if (!CaptureObservedPasteText()) {
      RetryPendingPasteCapture();
    }
    return 0;
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
