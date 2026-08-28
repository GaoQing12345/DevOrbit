#include "flutter_window.h"

#include <windows.h>
#include <dwmapi.h>
#include <tlhelp32.h>
#include <wincred.h>
#include <cstdlib>
#include <cstdio>
#include <cstring>
#include <optional>
#include <string>
#include <utility>
#include <vector>

#include "flutter/generated_plugin_registrant.h"
#include "flutter/standard_method_codec.h"
#include "utils.h"

namespace {

constexpr wchar_t kToolWindowReadyProperty[] =
    L"DevOrbitToolWindowReady";
constexpr UINT kActivateToolWindowMessage = WM_APP + 0x30B;
constexpr UINT kInjectedPasteKeyMessage = WM_APP + 0x30C;
constexpr UINT_PTR kPasteCaptureRetryTimer = 0xD30B;
constexpr UINT_PTR kPasteCaptureActivationProbeTimer = 0xD30C;
constexpr UINT kPasteCaptureRetryDelayMs = 10;
constexpr UINT kPasteCaptureActivationProbeDelayMs = 10;
constexpr int kPasteCaptureActivationProbeLimit = 25;
constexpr ULONGLONG kTransientPasteReturnLimitMs = 1500;
// Clipboard providers such as QuickClipboard clear the clipboard and then
// publish several formats one after another. Keep polling long enough for the
// final text format to become available instead of treating each intermediate
// update as a different paste operation.
constexpr int kPasteCaptureMaxRetries = 250;
bool g_clipboard_trace_enabled = true;

void AppendClipboardTraceLine(const std::string& line) noexcept {
  try {
    char* disabled = nullptr;
    size_t disabled_size = 0;
    if (_dupenv_s(&disabled, &disabled_size, "DEV_ORBIT_CLIPBOARD_TRACE") ==
            0 &&
        disabled != nullptr) {
      const bool trace_disabled = std::strcmp(disabled, "0") == 0;
      std::free(disabled);
      if (trace_disabled) return;
    }

    HANDLE mutex = CreateMutexW(nullptr, FALSE, L"Local\\DevOrbitClipboardTrace");
    if (mutex == nullptr) return;
    const DWORD wait = WaitForSingleObject(mutex, 1000);
    const bool locked = wait == WAIT_OBJECT_0 || wait == WAIT_ABANDONED;
    if (!locked) {
      CloseHandle(mutex);
      return;
    }

    wchar_t temp_path[MAX_PATH] = {};
    const DWORD length = GetTempPathW(MAX_PATH, temp_path);
    if (length == 0 || length >= MAX_PATH) {
      ReleaseMutex(mutex);
      CloseHandle(mutex);
      return;
    }
    std::wstring path(temp_path, length);
    path += L"dev_orbit_clipboard_trace.log";

    HANDLE file = CreateFileW(path.c_str(), FILE_APPEND_DATA,
                              FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr,
                              OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file != INVALID_HANDLE_VALUE) {
      DWORD written = 0;
      WriteFile(file, line.data(), static_cast<DWORD>(line.size()), &written,
                nullptr);
      CloseHandle(file);
    }
    ReleaseMutex(mutex);
    CloseHandle(mutex);
  } catch (...) {
    // Diagnostics must never affect clipboard behavior.
  }
}

void ClipboardTrace(const std::string& event,
                    const std::string& details = std::string()) noexcept {
  try {
    if (!g_clipboard_trace_enabled) return;

    SYSTEMTIME now = {};
    GetLocalTime(&now);
    char prefix[192] = {};
    sprintf_s(
        prefix, sizeof(prefix),
        "%04u-%02u-%02uT%02u:%02u:%02u.%03u pid=%lu tid=%lu platform=windows ",
        now.wYear, now.wMonth, now.wDay, now.wHour, now.wMinute,
        now.wSecond, now.wMilliseconds, GetCurrentProcessId(),
        GetCurrentThreadId());
    std::string line = std::string(prefix) + "event=" + event;
    if (!details.empty()) line += " " + details;
    line += "\r\n";
    AppendClipboardTraceLine(line);
  } catch (...) {
    // Diagnostics must never affect clipboard behavior.
  }
}

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

void ShowAndFocusProcessWindow(HWND window) {
  if (!IsWindow(window)) {
    return;
  }

  const DWORD current_thread_id = GetCurrentThreadId();
  const DWORD target_thread_id = GetWindowThreadProcessId(window, nullptr);
  const HWND foreground_window = GetForegroundWindow();
  const DWORD foreground_thread_id = foreground_window
                                         ? GetWindowThreadProcessId(
                                               foreground_window, nullptr)
                                         : 0;

  // SetForegroundWindow is allowed to fail when the launcher and the prewarmed
  // tool own different input queues. Temporarily join the queues so the shown
  // window becomes the real keyboard foreground window, not merely the topmost
  // visible window that still needs a mouse click before receiving Escape.
  const bool attached_to_foreground =
      foreground_thread_id != 0 &&
      foreground_thread_id != current_thread_id &&
      AttachThreadInput(current_thread_id, foreground_thread_id, TRUE);
  const bool attached_to_target =
      target_thread_id != 0 && target_thread_id != current_thread_id &&
      target_thread_id != foreground_thread_id &&
      AttachThreadInput(current_thread_id, target_thread_id, TRUE);

  const int show_command = IsIconic(window) ? SW_RESTORE : SW_SHOW;
  if (target_thread_id == current_thread_id) {
    ShowWindow(window, show_command);
  } else {
    // Do not synchronously block on a target thread that already failed the
    // bounded activation message above.
    ShowWindowAsync(window, show_command);
  }
  BringWindowToTop(window);
  SetForegroundWindow(window);
  SetActiveWindow(window);

  // The Flutter view is a child HWND. Explicitly move keyboard focus to it as
  // the target can already be foreground, in which case WM_ACTIVATE may not be
  // emitted again and the generated runner cannot restore child focus for us.
  HWND child = FindWindowExW(window, nullptr, L"FLUTTERVIEW", nullptr);
  if (!child) {
    child = GetWindow(window, GW_CHILD);
  }
  if (child && IsWindowEnabled(child)) {
    SetFocus(child);
  }

  if (attached_to_target) {
    AttachThreadInput(current_thread_id, target_thread_id, FALSE);
  }
  if (attached_to_foreground) {
    AttachThreadInput(current_thread_id, foreground_thread_id, FALSE);
  }
}

HWND FindChildWindowByClass(HWND parent, const wchar_t* class_name) {
  if (!parent || !class_name) return nullptr;
  for (HWND child = GetWindow(parent, GW_CHILD); child != nullptr;
       child = GetWindow(child, GW_HWNDNEXT)) {
    wchar_t current_class[128] = {};
    GetClassNameW(child, current_class,
                  static_cast<int>(sizeof(current_class) /
                                   sizeof(current_class[0])));
    if (_wcsicmp(current_class, class_name) == 0) return child;
    if (HWND nested = FindChildWindowByClass(child, class_name)) return nested;
  }
  return nullptr;
}

HWND FindAncestorWindowByClass(HWND window, HWND root,
                               const wchar_t* class_name) {
  for (HWND current = window; current && current != root;
       current = GetParent(current)) {
    wchar_t current_class[128] = {};
    GetClassNameW(current, current_class,
                  static_cast<int>(sizeof(current_class) /
                                   sizeof(current_class[0])));
    if (_wcsicmp(current_class, class_name) == 0 &&
        GetAncestor(current, GA_ROOT) == root) {
      return current;
    }
  }
  return nullptr;
}

HWND FindPlatformViewUnderCursor(HWND root) {
  POINT cursor = {};
  if (!GetCursorPos(&cursor)) return nullptr;
  return FindAncestorWindowByClass(WindowFromPoint(cursor), root,
                                   L"CustomPlatformView");
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
  DWORD_PTR activation_result = 0;
  if (!SendMessageTimeoutW(window, kActivateToolWindowMessage, 0, 0,
                           SMTO_ABORTIFHUNG, 1000,
                           &activation_result)) {
    // Fall back to cross-thread activation if the target has not started
    // processing native messages yet.
    ShowAndFocusProcessWindow(window);
  }
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

FlutterWindow* FlutterWindow::paste_keyboard_hook_owner_ = nullptr;

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
        if (call.method_name() == "writeDiagnosticLine") {
          if (call.arguments() &&
              std::holds_alternative<flutter::EncodableMap>(*call.arguments())) {
            const auto& args = std::get<flutter::EncodableMap>(*call.arguments());
            const auto line_it = args.find(flutter::EncodableValue("line"));
            if (line_it != args.end() &&
                std::holds_alternative<std::string>(line_it->second)) {
              if (g_clipboard_trace_enabled) {
                AppendClipboardTraceLine(
                    std::get<std::string>(line_it->second));
              }
            }
          }
          result->Success();
          return;
        }
        ClipboardTrace("channel_call", "method=" + call.method_name());
        if (call.method_name() == "setDiagnosticsEnabled") {
          if (call.arguments() &&
              std::holds_alternative<flutter::EncodableMap>(*call.arguments())) {
            const auto& args = std::get<flutter::EncodableMap>(*call.arguments());
            const auto enabled_it =
                args.find(flutter::EncodableValue("enabled"));
            if (enabled_it != args.end() &&
                std::holds_alternative<bool>(enabled_it->second)) {
              g_clipboard_trace_enabled =
                  std::get<bool>(enabled_it->second);
            }
          }
          result->Success();
          return;
        }
        if (call.method_name() == "getChangeCount") {
          ClipboardTrace("change_count",
                         "sequence=" +
                             std::to_string(GetClipboardSequenceNumber()));
          result->Success(flutter::EncodableValue(
              static_cast<int64_t>(GetClipboardSequenceNumber())));
          return;
        }
        if (call.method_name() == "supportsPasteCapture") {
          ClipboardTrace("supports_capture", "supported=true");
          result->Success(flutter::EncodableValue(true));
          return;
        }
        if (call.method_name() == "requestEditorFocus") {
          // Re-activate the top-level HWND first, then focus the composition
          // platform view itself. Focusing only FLUTTERVIEW leaves Flutter's
          // outer shortcut node active and WebView2 receives no keyboard input
          // after a clipboard picker returns.
          ShowAndFocusProcessWindow(GetHandle());
          HWND platform_view = last_editor_platform_view_;
          if (!IsWindow(platform_view) ||
              GetAncestor(platform_view, GA_ROOT) != GetHandle()) {
            platform_view = FindPlatformViewUnderCursor(GetHandle());
          }
          if (!platform_view) {
            platform_view =
                FindChildWindowByClass(GetHandle(), L"CustomPlatformView");
          }
          if (platform_view && IsWindowEnabled(platform_view)) {
            last_editor_platform_view_ = platform_view;
            SetFocus(platform_view);
          }
          result->Success();
          return;
        }
        if (call.method_name() == "claimEditorFocus") {
          // A DOM focus event is not emitted for a second click inside the
          // same editor. Resolve the platform view from the live pointer so
          // repeated clicks and side-by-side editors keep the correct HWND.
          HWND platform_view = FindPlatformViewUnderCursor(GetHandle());
          if (platform_view && IsWindowEnabled(platform_view)) {
            last_editor_platform_view_ = platform_view;
            SetFocus(platform_view);
          }
          result->Success();
          return;
        }
        if (call.method_name() == "registerPasteTarget") {
          ++paste_target_client_count_;
          ClipboardTrace(
              "target_register",
              "count=" + std::to_string(paste_target_client_count_));
          result->Success();
          return;
        }
        if (call.method_name() == "unregisterPasteTarget") {
          if (paste_target_client_count_ > 0) {
            --paste_target_client_count_;
          }
          ClipboardTrace(
              "target_unregister",
              "count=" + std::to_string(paste_target_client_count_));
          if (paste_target_client_count_ == 0) {
            ResetPasteCapture();
          }
          result->Success();
          return;
        }
        if (call.method_name() == "takePendingPasteText") {
          const auto session_id = ClipboardSessionId(call);
          if (!session_id) {
            ClipboardTrace("take_pending_error", "reason=missing_session");
            result->Error("invalid_arguments", "Missing clipboard session ID");
            return;
          }
          const auto text = TakePendingPasteText(*session_id);
          ClipboardTrace(
              "take_pending",
              "session=" + std::to_string(*session_id) +
                  " available=" + (text ? "true" : "false") +
                  " length=" + (text ? std::to_string(text->size()) : "0"));
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
            ClipboardTrace("arm_error", "reason=missing_session");
            result->Error("invalid_arguments", "Missing clipboard session ID");
            return;
          }
          ClipboardTrace("arm_call", "session=" + std::to_string(*session_id));
          const bool prearmed = ArmPasteCapture(*session_id);
          result->Success(flutter::EncodableValue(prearmed));
          return;
        }
        if (call.method_name() == "didPasteCaptureObserveChange") {
          const auto session_id = ClipboardSessionId(call);
          if (!session_id) {
            ClipboardTrace("observe_error", "reason=missing_session");
            result->Error("invalid_arguments", "Missing clipboard session ID");
            return;
          }
          const bool observed = DidPasteCaptureObserveChange(*session_id);
          ClipboardTrace("observe_call", "session=" +
                                             std::to_string(*session_id) +
                                             " observed=" +
                                             (observed ? "true" : "false"));
          result->Success(flutter::EncodableValue(observed));
          return;
        }
        if (call.method_name() == "discardPendingPasteText") {
          const auto session_id = ClipboardSessionId(call);
          if (!session_id) {
            ClipboardTrace("discard_error", "reason=missing_session");
            result->Error("invalid_arguments", "Missing clipboard session ID");
            return;
          }
          ClipboardTrace("discard_call", "session=" +
                                             std::to_string(*session_id));
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

void FlutterWindow::ActivateToolWindow() {
  if (IsWindowVisible(GetHandle()) || !process_window_channel_ ||
      !flutter_controller_ || !flutter_controller_->engine()) {
    ShowAndFocusProcessWindow(GetHandle());
    return;
  }
  if (tool_window_activation_pending_) {
    return;
  }

  // Most prewarmed tools render an empty first frame while hidden; heavier
  // tools may already have rendered their platform views. In either case,
  // ask Dart for a fresh frame and reveal the HWND only after it completes.
  tool_window_activation_pending_ = true;
  flutter_controller_->engine()->SetNextFrameCallback([this]() {
    tool_window_activation_pending_ = false;
    ShowAndFocusProcessWindow(GetHandle());
    if (process_window_channel_) {
      process_window_channel_->InvokeMethod(
          "activationComplete", std::make_unique<flutter::EncodableValue>());
    }
  });
  process_window_channel_->InvokeMethod(
      "prepareForActivation", std::make_unique<flutter::EncodableValue>());
}

void FlutterWindow::BeginPasteCapture(std::optional<int64_t> session_id) {
  ResetPasteCapture();
  paste_capture_armed_ = true;
  paste_capture_session_id_ = session_id;
  paste_capture_baseline_sequence_ = GetClipboardSequenceNumber();
  if (OpenClipboard(GetHandle())) {
    HANDLE data = ::GetClipboardData(CF_UNICODETEXT);
    if (data) {
      const wchar_t* text = static_cast<const wchar_t*>(GlobalLock(data));
      if (text) {
        paste_capture_baseline_text_ = Utf8FromUtf16(text);
        GlobalUnlock(data);
      }
    }
    CloseClipboard();
  }
  EnsurePasteKeyboardHook();
  ClipboardTrace(
      "capture_begin",
      "session=" +
          (session_id ? std::to_string(*session_id) : std::string("none")) +
          " baseline=" + std::to_string(paste_capture_baseline_sequence_));
}

void FlutterWindow::EnsureClipboardListener() {
  if (clipboard_listener_registered_) return;
  const BOOL registered = AddClipboardFormatListener(GetHandle());
  const DWORD error = registered ? ERROR_SUCCESS : GetLastError();
  ClipboardTrace("clipboard_listener", std::string("registered=") +
                                               (registered ? "true" : "false") +
                                               " error=" + std::to_string(error));
  clipboard_listener_registered_ = registered == TRUE;
}

LRESULT CALLBACK FlutterWindow::PasteKeyboardHook(int code, WPARAM wparam,
                                                   LPARAM lparam) {
  FlutterWindow* owner = paste_keyboard_hook_owner_;
  if (code == HC_ACTION && owner != nullptr) {
    const auto* event = reinterpret_cast<const KBDLLHOOKSTRUCT*>(lparam);
    const bool key_down = wparam == WM_KEYDOWN || wparam == WM_SYSKEYDOWN;
    const bool key_up = wparam == WM_KEYUP || wparam == WM_SYSKEYUP;
    const DWORD key = event->vkCode;

    if (key == VK_CONTROL || key == VK_LCONTROL || key == VK_RCONTROL) {
      if (key_down) owner->paste_hook_control_pressed_ = true;
      if (key_up) owner->paste_hook_control_pressed_ = false;
    }
    if (key == VK_SHIFT || key == VK_LSHIFT || key == VK_RSHIFT) {
      if (key_down) owner->paste_hook_shift_pressed_ = true;
      if (key_up) owner->paste_hook_shift_pressed_ = false;
    }

    const bool injected = (event->flags & LLKHF_INJECTED) != 0;
    const bool control_pressed =
        owner->paste_hook_control_pressed_ ||
        (GetAsyncKeyState(VK_CONTROL) & 0x8000) != 0;
    const bool shift_pressed =
        owner->paste_hook_shift_pressed_ ||
        (GetAsyncKeyState(VK_SHIFT) & 0x8000) != 0;
    const bool is_injected_paste_key =
        key_down && injected &&
        ((key == 'V' && control_pressed) ||
         (key == VK_INSERT && shift_pressed));
    if (is_injected_paste_key) {
      const HWND foreground = GetForegroundWindow();
      const HWND foreground_root =
          foreground ? GetAncestor(foreground, GA_ROOT) : nullptr;
      const bool targets_owner = foreground_root == owner->GetHandle();
      PostMessageW(owner->GetHandle(), kInjectedPasteKeyMessage, key,
                   targets_owner ? 1 : 0);
    }
  }
  return CallNextHookEx(owner ? owner->paste_keyboard_hook_ : nullptr, code,
                        wparam, lparam);
}

void FlutterWindow::EnsurePasteKeyboardHook() {
  if (paste_keyboard_hook_) return;
  paste_keyboard_hook_owner_ = this;
  paste_keyboard_hook_ = SetWindowsHookExW(
      WH_KEYBOARD_LL, PasteKeyboardHook, GetModuleHandleW(nullptr), 0);
  const DWORD error = paste_keyboard_hook_ ? ERROR_SUCCESS : GetLastError();
  ClipboardTrace("paste_keyboard_hook",
                 std::string("installed=") +
                     (paste_keyboard_hook_ ? "true" : "false") +
                     " error=" + std::to_string(error));
  if (!paste_keyboard_hook_ && paste_keyboard_hook_owner_ == this) {
    paste_keyboard_hook_owner_ = nullptr;
  }
}

void FlutterWindow::RemovePasteKeyboardHook() {
  if (paste_keyboard_hook_) {
    UnhookWindowsHookEx(paste_keyboard_hook_);
    paste_keyboard_hook_ = nullptr;
    ClipboardTrace("paste_keyboard_hook", "installed=false error=0");
  }
  if (paste_keyboard_hook_owner_ == this) {
    paste_keyboard_hook_owner_ = nullptr;
  }
  paste_hook_control_pressed_ = false;
  paste_hook_shift_pressed_ = false;
}

void FlutterWindow::HandleInjectedPasteKey(DWORD key, bool targets_owner) {
  ClipboardTrace(
      "injected_paste_key",
      "key=" + std::to_string(key) +
          " target_match=" + (targets_owner ? "true" : "false") +
          " targets=" + std::to_string(paste_target_client_count_) +
          " armed=" + (paste_capture_armed_ ? "true" : "false") +
          " session=" +
          (paste_capture_session_id_
               ? std::to_string(*paste_capture_session_id_)
               : std::string("none")) +
          " pending=" + (pending_paste_text_ ? "true" : "false"));
  if (!targets_owner || paste_target_client_count_ <= 0 ||
      !paste_capture_armed_) {
    return;
  }
  paste_key_pressed_ = true;
  HandleClipboardUpdate(true);
  NotifyPasteRequested();
}

void FlutterWindow::HandlePasteCaptureActivation(HWND activated_window,
                                                  bool active) {
  if (!paste_capture_armed_) {
    KillTimer(GetHandle(), kPasteCaptureActivationProbeTimer);
    return;
  }
  if (!active) {
    paste_capture_focus_returned_ = false;
    paste_capture_return_tick_ = 0;
    paste_capture_activation_probe_count_ = 0;
    HWND target = activated_window;
    if (!target || GetAncestor(target, GA_ROOT) == GetHandle()) {
      target = GetForegroundWindow();
    }
    const HWND activated_root =
        target ? GetAncestor(target, GA_ROOT) : nullptr;
    const LONG_PTR ex_style = activated_root
                                  ? GetWindowLongPtrW(activated_root, GWL_EXSTYLE)
                                  : 0;
    const LONG_PTR style = activated_root
                               ? GetWindowLongPtrW(activated_root, GWL_STYLE)
                               : 0;
    const bool owned =
        activated_root && GetWindow(activated_root, GW_OWNER) != nullptr;
    DWORD activated_process_id = 0;
    if (activated_root) {
      GetWindowThreadProcessId(activated_root, &activated_process_id);
    }
    const bool external_process =
        activated_process_id != 0 &&
        activated_process_id != GetCurrentProcessId();
    paste_capture_left_for_transient_window_ =
        activated_root && activated_root != GetHandle() &&
        external_process &&
        (owned || (ex_style & WS_EX_TOOLWINDOW) != 0 ||
         (ex_style & WS_EX_TOPMOST) != 0 || (style & WS_POPUP) != 0);
    ClipboardTrace(
        "paste_activation_target",
        "source=immediate window=" +
            std::to_string(reinterpret_cast<std::uintptr_t>(activated_root)) +
            " process=" + std::to_string(activated_process_id) +
            " style=" + std::to_string(style) +
            " ex_style=" + std::to_string(ex_style) +
            " owned=" + (owned ? "true" : "false") +
            " transient=" +
            (paste_capture_left_for_transient_window_ ? "true" : "false"));
    if (!paste_capture_left_for_transient_window_) {
      SetTimer(GetHandle(), kPasteCaptureActivationProbeTimer,
               kPasteCaptureActivationProbeDelayMs, nullptr);
    }
    return;
  }

  KillTimer(GetHandle(), kPasteCaptureActivationProbeTimer);
  // WM_CLIPBOARDUPDATE can still be queued behind WM_ACTIVATE. Sample the
  // sequence synchronously before deciding whether a transient clipboard
  // window completed a selection without sending Ctrl+V. Do not read text
  // here: the popup may already have restored the previous clipboard value.
  if (paste_capture_armed_) {
    HandleClipboardUpdate(false, false);
  }
  paste_capture_focus_returned_ = true;
  paste_capture_return_tick_ = GetTickCount64();
  ClipboardTrace(
      "paste_activation_return",
      std::string("armed=") + (paste_capture_armed_ ? "true" : "false") +
          " transient=" +
          (paste_capture_left_for_transient_window_ ? "true" : "false") +
          " changed=" +
          (return_paste_candidate_text_ ? "true" : "false") +
          " updates=" + std::to_string(paste_capture_update_count_) +
          " external_owner=" +
          (paste_capture_external_clipboard_owner_ ? "true" : "false"));
  TryCompletePasteCaptureAfterTransientReturn();
  if (paste_capture_armed_ && paste_capture_left_for_transient_window_ &&
      !paste_key_pressed_) {
    SetTimer(GetHandle(), kPasteCaptureRetryTimer,
             kPasteCaptureRetryDelayMs, nullptr);
  }
}

void FlutterWindow::ProbePasteCaptureActivation() {
  if (!paste_capture_armed_ || paste_capture_focus_returned_ ||
      paste_capture_left_for_transient_window_) {
    return;
  }

  const HWND foreground = GetForegroundWindow();
  const HWND foreground_root =
      foreground ? GetAncestor(foreground, GA_ROOT) : nullptr;
  const LONG_PTR ex_style =
      foreground_root
          ? GetWindowLongPtrW(foreground_root, GWL_EXSTYLE)
          : 0;
  const LONG_PTR style =
      foreground_root ? GetWindowLongPtrW(foreground_root, GWL_STYLE) : 0;
  const bool owned =
      foreground_root && GetWindow(foreground_root, GW_OWNER) != nullptr;
  DWORD foreground_process_id = 0;
  if (foreground_root) {
    GetWindowThreadProcessId(foreground_root, &foreground_process_id);
  }
  const bool external_process =
      foreground_process_id != 0 &&
      foreground_process_id != GetCurrentProcessId();
  paste_capture_left_for_transient_window_ =
      foreground_root && foreground_root != GetHandle() &&
      external_process &&
      (owned || (ex_style & WS_EX_TOOLWINDOW) != 0 ||
       (ex_style & WS_EX_TOPMOST) != 0 || (style & WS_POPUP) != 0);
  ClipboardTrace(
      "paste_activation_target",
      "source=probe window=" +
          std::to_string(reinterpret_cast<std::uintptr_t>(foreground_root)) +
          " process=" + std::to_string(foreground_process_id) +
          " style=" + std::to_string(style) +
          " ex_style=" + std::to_string(ex_style) +
          " owned=" + (owned ? "true" : "false") +
          " transient=" +
          (paste_capture_left_for_transient_window_ ? "true" : "false"));
  if (!paste_capture_left_for_transient_window_ &&
      ++paste_capture_activation_probe_count_ <
          kPasteCaptureActivationProbeLimit) {
    SetTimer(GetHandle(), kPasteCaptureActivationProbeTimer,
             kPasteCaptureActivationProbeDelayMs, nullptr);
  }
}

void FlutterWindow::TryCompletePasteCaptureAfterTransientReturn() {
  const bool transient_signal = paste_capture_left_for_transient_window_;
  const bool owner_signal = paste_capture_external_clipboard_owner_;
  const bool multi_update_signal = paste_capture_update_count_ >= 2;
  if (!paste_capture_armed_ || paste_key_pressed_ ||
      (!transient_signal && !owner_signal && !multi_update_signal) ||
      !paste_capture_focus_returned_ || paste_capture_return_tick_ == 0 ||
      !return_paste_candidate_text_ ||
      !return_paste_candidate_differs_from_baseline_) {
    return;
  }

  const ULONGLONG elapsed = GetTickCount64() - paste_capture_return_tick_;
  if (elapsed > kTransientPasteReturnLimitMs) {
    ClipboardTrace("paste_activation_expired",
                   "elapsed_ms=" + std::to_string(elapsed));
    paste_capture_left_for_transient_window_ = false;
    return_paste_candidate_text_.reset();
    return;
  }

  // Some clipboard popups restore the target window after changing the
  // clipboard but intermittently omit their synthetic Ctrl+V. Treat a prompt
  // clipboard update after returning from that popup as the paste boundary.
  // The normal key path remains authoritative whenever a key is delivered.
  paste_key_pressed_ = true;
  paste_capture_left_for_transient_window_ = false;
  pending_paste_text_ = std::move(return_paste_candidate_text_);
  return_paste_candidate_retry_count_ = 0;
  KillTimer(GetHandle(), kPasteCaptureRetryTimer);
  KillTimer(GetHandle(), kPasteCaptureActivationProbeTimer);
  ClipboardTrace("paste_activation_complete",
                 "elapsed_ms=" + std::to_string(elapsed) +
                     " signal=" +
                     (transient_signal
                          ? std::string("transient")
                          : owner_signal ? std::string("external_owner")
                                         : std::string("multi_update")) +
                     " length=" +
                     std::to_string(pending_paste_text_->size()));
  NotifyPasteRequested();
}

void FlutterWindow::CaptureReturnPasteCandidate() {
  if (!paste_capture_armed_ || paste_capture_invalidated_ ||
      (!paste_capture_left_for_transient_window_ &&
       !paste_capture_focus_returned_) ||
      (return_paste_candidate_text_ &&
       return_paste_candidate_differs_from_baseline_) ||
      pending_paste_text_ ||
      paste_capture_observed_sequence_ == 0) {
    return;
  }
  if (++return_paste_candidate_retry_count_ > kPasteCaptureMaxRetries) {
    ClipboardTrace("return_candidate_retry_exhausted",
                   "sequence=" +
                       std::to_string(paste_capture_observed_sequence_));
    KillTimer(GetHandle(), kPasteCaptureRetryTimer);
    return;
  }

  if (!OpenClipboard(GetHandle())) {
    ClipboardTrace("return_candidate_open_failed",
                   "error=" + std::to_string(GetLastError()) +
                       " retry=" +
                       std::to_string(return_paste_candidate_retry_count_));
    SetTimer(GetHandle(), kPasteCaptureRetryTimer,
             kPasteCaptureRetryDelayMs, nullptr);
    return;
  }

  bool resolved_current_sequence = false;
  HANDLE data = ::GetClipboardData(CF_UNICODETEXT);
  if (data) {
    const wchar_t* text = static_cast<const wchar_t*>(GlobalLock(data));
    if (text) {
      const std::string candidate = Utf8FromUtf16(text);
      if (!candidate.empty()) {
        return_paste_candidate_text_ = candidate;
        return_paste_candidate_differs_from_baseline_ =
            !paste_capture_baseline_text_ ||
            candidate != *paste_capture_baseline_text_;
        ClipboardTrace(
            "return_candidate_ready",
            "sequence=" + std::to_string(paste_capture_observed_sequence_) +
                " length=" + std::to_string(candidate.size()));
        resolved_current_sequence = true;
      }
      GlobalUnlock(data);
    }
  }
  CloseClipboard();

  if (resolved_current_sequence) {
    KillTimer(GetHandle(), kPasteCaptureRetryTimer);
    TryCompletePasteCaptureAfterTransientReturn();
  } else {
    ClipboardTrace("return_candidate_unavailable",
                   "sequence=" +
                       std::to_string(paste_capture_observed_sequence_) +
                       " retry=" +
                       std::to_string(return_paste_candidate_retry_count_));
    SetTimer(GetHandle(), kPasteCaptureRetryTimer,
             kPasteCaptureRetryDelayMs, nullptr);
  }
}

bool FlutterWindow::ArmPasteCapture(std::optional<int64_t> session_id) {
  ClipboardTrace(
      "capture_arm",
      "session=" +
          (session_id ? std::to_string(*session_id) : std::string("none")));
  if (paste_target_client_count_ <= 0) {
    ClipboardTrace("capture_arm_reject", "reason=no_target");
    ResetPasteCapture();
    return false;
  }
  if (paste_capture_armed_) {
    if (!paste_capture_session_id_ && session_id) {
      paste_capture_session_id_ = *session_id;
      HandleClipboardUpdate(true);
      if (paste_key_pressed_) {
        NotifyPasteRequested();
      }
      ClipboardTrace("capture_arm_reuse", "session=" +
                                             std::to_string(*session_id));
      EnsureClipboardListener();
      return true;
    }
    if (!session_id ||
        (paste_capture_session_id_ &&
         *paste_capture_session_id_ == *session_id)) {
      ClipboardTrace(
          "capture_arm_duplicate",
          "session=" +
              (session_id ? std::to_string(*session_id) : std::string("none")));
      EnsureClipboardListener();
      return true;
    }
  }
  BeginPasteCapture(session_id);
  EnsureClipboardListener();
  return false;
}

bool FlutterWindow::DidPasteCaptureObserveChange(int64_t session_id) {
  if (!paste_capture_armed_ || !paste_capture_session_id_ ||
      *paste_capture_session_id_ != session_id) {
    ClipboardTrace("capture_observe_reject", "session=" +
                                                  std::to_string(session_id));
    return false;
  }
  HandleClipboardUpdate(paste_key_pressed_);
  return paste_capture_invalidated_ || pending_paste_text_.has_value();
}

void FlutterWindow::DiscardPendingPasteText(int64_t session_id) {
  if (!paste_capture_session_id_ ||
      *paste_capture_session_id_ != session_id) {
    ClipboardTrace("capture_discard_reject", "session=" +
                                                   std::to_string(session_id));
    return;
  }
  ClipboardTrace("capture_discard", "session=" + std::to_string(session_id));
  ResetPasteCapture();
}

std::optional<std::string> FlutterWindow::TakePendingPasteText(
    int64_t session_id) {
  if (!paste_capture_armed_ || !paste_capture_session_id_ ||
      *paste_capture_session_id_ != session_id || !pending_paste_text_) {
    ClipboardTrace("capture_take_empty", "session=" +
                                               std::to_string(session_id));
    return std::nullopt;
  }
  auto text = pending_paste_text_;
  ResetPasteCapture();
  return text;
}

void FlutterWindow::HandleClipboardUpdate(bool capture_text,
                                          bool capture_return_candidate) {
  if (!paste_capture_armed_ || paste_capture_invalidated_ ||
      pending_paste_text_) {
    ClipboardTrace("clipboard_update_skip", std::string("armed=") +
                                                   (paste_capture_armed_ ?
                                                        "true" : "false") +
                                                   " invalidated=" +
                                                   (paste_capture_invalidated_ ?
                                                        "true" : "false") +
                                                   " pending=" +
                                                   (pending_paste_text_ ?
                                                        "true" : "false"));
    return;
  }
  const DWORD sequence = GetClipboardSequenceNumber();
  if (sequence == 0 || sequence == paste_capture_baseline_sequence_) {
    ClipboardTrace("clipboard_update_unchanged", "sequence=" +
                                                       std::to_string(sequence));
    if (capture_text) RetryPendingPasteCapture();
    return;
  }
  ClipboardTrace("clipboard_update", "sequence=" +
                                         std::to_string(sequence));

  // A single logical paste may produce multiple WM_CLIPBOARDUPDATE messages:
  // EmptyClipboard followed by CF_UNICODETEXT/HTML/etc. Do not require a
  // contiguous sequence number and do not invalidate when a newer format
  // arrives before the text handle is readable. The first readable text is
  // the item selected in the third-party clipboard and must be retained even
  // if that tool changes the clipboard again during paste.
  if (paste_capture_observed_sequence_ != sequence) {
    paste_capture_observed_sequence_ = sequence;
    ++paste_capture_update_count_;
    const HWND clipboard_owner = GetClipboardOwner();
    DWORD clipboard_owner_process_id = 0;
    if (clipboard_owner) {
      GetWindowThreadProcessId(clipboard_owner,
                               &clipboard_owner_process_id);
    }
    if (clipboard_owner_process_id != 0 &&
        clipboard_owner_process_id != GetCurrentProcessId()) {
      paste_capture_external_clipboard_owner_ = true;
    }
    ClipboardTrace(
        "clipboard_update_owner",
        "window=" +
            std::to_string(
                reinterpret_cast<std::uintptr_t>(clipboard_owner)) +
            " process=" + std::to_string(clipboard_owner_process_id) +
            " external=" +
            (paste_capture_external_clipboard_owner_ ? "true" : "false"));
    return_paste_candidate_retry_count_ = 0;
    paste_capture_retry_count_ = 0;
  }
  if (!capture_text || !paste_key_pressed_) {
    ClipboardTrace("clipboard_update_deferred", "sequence=" +
                                                     std::to_string(sequence));
    if (capture_return_candidate &&
        (paste_capture_left_for_transient_window_ ||
         paste_capture_focus_returned_)) {
      if (return_paste_candidate_text_ &&
          return_paste_candidate_differs_from_baseline_) {
        ClipboardTrace(
            "return_candidate_activity",
            "sequence=" + std::to_string(paste_capture_observed_sequence_));
        TryCompletePasteCaptureAfterTransientReturn();
      } else {
        CaptureReturnPasteCandidate();
      }
    }
    return;
  }
  if (!CaptureObservedPasteText()) {
    RetryPendingPasteCapture();
  }
}

void FlutterWindow::RetryPendingPasteCapture() {
  if (!paste_capture_armed_ || paste_capture_invalidated_ ||
      pending_paste_text_ || !paste_key_pressed_) {
    return;
  }
  if (++paste_capture_retry_count_ > kPasteCaptureMaxRetries) {
    ClipboardTrace("capture_retry_exhausted", "sequence=" +
                                                      std::to_string(
                                                          paste_capture_observed_sequence_));
    InvalidatePasteCapture();
    return;
  }
  SetTimer(GetHandle(), kPasteCaptureRetryTimer,
           kPasteCaptureRetryDelayMs, nullptr);
}

bool FlutterWindow::CaptureObservedPasteText() {
  if (!paste_capture_armed_ || paste_capture_invalidated_ ||
      paste_capture_observed_sequence_ == 0 || !paste_key_pressed_) {
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
    ClipboardTrace("capture_open_failed", "error=" +
                                                   std::to_string(GetLastError()) +
                                                   " retry=" +
                                                   std::to_string(
                                                       paste_capture_retry_count_));
    return false;
  }

  HANDLE data = ::GetClipboardData(CF_UNICODETEXT);
  if (data) {
    const wchar_t* text = static_cast<const wchar_t*>(GlobalLock(data));
    if (text) {
      pending_paste_text_ = Utf8FromUtf16(text);
      ClipboardTrace("capture_text_ready", "sequence=" +
                                                  std::to_string(
                                                      paste_capture_observed_sequence_) +
                                                  " length=" +
                                                  std::to_string(
                                                      pending_paste_text_->size()));
      GlobalUnlock(data);
    }
  } else {
    ClipboardTrace("capture_text_missing", "error=" +
                                                  std::to_string(GetLastError()));
  }
  CloseClipboard();
  const bool captured = pending_paste_text_.has_value();
  if (captured) {
    KillTimer(GetHandle(), kPasteCaptureRetryTimer);
    if (paste_key_pressed_) {
      NotifyPasteRequested();
    }
  }
  // A sessionless notification resets the capture after InvokeMethod. Preserve
  // the result from before that reset so callers do not schedule another retry.
  return captured;
}

void FlutterWindow::NotifyPasteRequested() {
  if (paste_request_notification_sent_ || !clipboard_channel_ ||
      !pending_paste_text_) {
    ClipboardTrace("notify_skip", std::string("sent=") +
                                     (paste_request_notification_sent_ ? "true" :
                                                                          "false") +
                                     " channel=" +
                                     (clipboard_channel_ ? "true" : "false") +
                                     " session=" +
                                     (paste_capture_session_id_ ? "true" : "false") +
                                     " pending=" +
                                     (pending_paste_text_ ? "true" : "false"));
    return;
  }

  flutter::EncodableMap arguments;
  if (paste_capture_session_id_) {
    arguments[flutter::EncodableValue("sessionId")] = flutter::EncodableValue(
        *paste_capture_session_id_);
  } else {
    // The injected paste key can arrive before Flutter receives the matching
    // blur event and assigns a session. Send the text with the request so the
    // active editor can consume this exact clipboard item without waiting for
    // a later window transition or reading a restored clipboard value.
    arguments[flutter::EncodableValue("text")] = flutter::EncodableValue(
        *pending_paste_text_);
  }
  paste_request_notification_sent_ = true;
  ClipboardTrace(
      "notify_paste_requested",
      "session=" +
          (paste_capture_session_id_
               ? std::to_string(*paste_capture_session_id_)
               : std::string("none")) +
          " includes_text=" +
          (paste_capture_session_id_ ? std::string("false")
                                     : std::string("true")) +
          " length=" + std::to_string(pending_paste_text_->size()));
  clipboard_channel_->InvokeMethod(
      "pasteRequested",
      std::make_unique<flutter::EncodableValue>(arguments));
  if (!paste_capture_session_id_) {
    ResetPasteCapture();
  }
}

void FlutterWindow::InvalidatePasteCapture() {
  ClipboardTrace("capture_invalidated", "session=" +
                                             (paste_capture_session_id_
                                                  ? std::to_string(
                                                        *paste_capture_session_id_)
                                                  : std::string("none")));
  KillTimer(GetHandle(), kPasteCaptureRetryTimer);
  KillTimer(GetHandle(), kPasteCaptureActivationProbeTimer);
  pending_paste_text_.reset();
  paste_capture_retry_count_ = 0;
  paste_capture_invalidated_ = true;
}

void FlutterWindow::ResetPasteCapture() {
  if (paste_capture_armed_ || paste_capture_session_id_) {
    ClipboardTrace("capture_reset", "session=" +
                                         (paste_capture_session_id_
                                              ? std::to_string(
                                                    *paste_capture_session_id_)
                                              : std::string("none")));
  }
  KillTimer(GetHandle(), kPasteCaptureRetryTimer);
  KillTimer(GetHandle(), kPasteCaptureActivationProbeTimer);
  paste_capture_armed_ = false;
  pending_paste_text_.reset();
  paste_capture_baseline_text_.reset();
  paste_capture_session_id_.reset();
  paste_capture_baseline_sequence_ = 0;
  paste_capture_observed_sequence_ = 0;
  paste_capture_update_count_ = 0;
  return_paste_candidate_text_.reset();
  return_paste_candidate_retry_count_ = 0;
  return_paste_candidate_differs_from_baseline_ = false;
  paste_capture_activation_probe_count_ = 0;
  paste_capture_retry_count_ = 0;
  paste_capture_invalidated_ = false;
  paste_key_pressed_ = false;
  paste_request_notification_sent_ = false;
  paste_capture_left_for_transient_window_ = false;
  paste_capture_focus_returned_ = false;
  paste_capture_external_clipboard_owner_ = false;
  paste_capture_return_tick_ = 0;
  if (clipboard_listener_registered_) {
    RemoveClipboardFormatListener(GetHandle());
    clipboard_listener_registered_ = false;
  }
  RemovePasteKeyboardHook();
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
  last_editor_platform_view_ = nullptr;
  RemovePropW(GetHandle(), kToolWindowReadyProperty);
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
  if (message == kActivateToolWindowMessage) {
    // AllowSetForegroundWindow grants the target process permission to take
    // focus, so perform the final activation on the target UI thread.
    ActivateToolWindow();
    return 0;
  }
  if (message == kInjectedPasteKeyMessage) {
    HandleInjectedPasteKey(static_cast<DWORD>(wparam), lparam != 0);
    return 0;
  }

  const bool is_paste_key =
      (message == WM_KEYDOWN || message == WM_SYSKEYDOWN) &&
      ((wparam == 'V' && (GetKeyState(VK_CONTROL) & 0x8000) != 0) ||
       (wparam == VK_INSERT && (GetKeyState(VK_SHIFT) & 0x8000) != 0));
  if (is_paste_key) {
    ClipboardTrace("native_paste_key", std::string("armed=") +
                                           (paste_capture_armed_ ? "true" :
                                                                    "false") +
                                           " pending=" +
                                           (pending_paste_text_ ? "true" :
                                                                  "false"));
  }
  if (is_paste_key && paste_capture_armed_) {
    paste_key_pressed_ = true;
  }
  if (is_paste_key && paste_capture_armed_ && !pending_paste_text_) {
    // Clipboard update messages and injected keyboard messages originate on
    // different threads. Re-check synchronously at the actual paste boundary
    // so a queued WM_CLIPBOARDUPDATE cannot make Flutter read stale content.
    HandleClipboardUpdate(true);
  }
  if (is_paste_key && paste_capture_armed_) {
    // QuickClipboard can finish publishing CF_UNICODETEXT slightly after the
    // injected Ctrl+V/Shift+Insert reaches this window. Remember that the
    // paste key was already observed so CaptureObservedPasteText can notify
    // Flutter when the text becomes readable on a later retry.
    NotifyPasteRequested();
  }
  if (message == WM_CLIPBOARDUPDATE && paste_capture_armed_) {
    ClipboardTrace("native_clipboard_update_message");
    HandleClipboardUpdate();
  }
  if (message == WM_ACTIVATE && LOWORD(wparam) == WA_INACTIVE) {
    ClipboardTrace(
        "native_window_inactive",
        std::string("armed=") + (paste_capture_armed_ ? "true" : "false") +
            " targets=" + std::to_string(paste_target_client_count_));
    if (paste_target_client_count_ > 0 && !paste_capture_armed_) {
      // Match macOS resignKey: arm before the clipboard manager takes focus,
      // then bind the native session when Flutter records the focused target.
      ArmPasteCapture(std::nullopt);
    }
    HandlePasteCaptureActivation(reinterpret_cast<HWND>(lparam), false);
  } else if (message == WM_ACTIVATE) {
    HandlePasteCaptureActivation(hwnd, true);
  }
  if (message == WM_TIMER &&
      wparam == kPasteCaptureActivationProbeTimer) {
    KillTimer(GetHandle(), kPasteCaptureActivationProbeTimer);
    ProbePasteCaptureActivation();
    return 0;
  }
  if (message == WM_TIMER && wparam == kPasteCaptureRetryTimer) {
    KillTimer(GetHandle(), kPasteCaptureRetryTimer);
    if (paste_capture_focus_returned_ &&
        paste_capture_return_tick_ != 0 &&
        GetTickCount64() - paste_capture_return_tick_ >
            kTransientPasteReturnLimitMs) {
      ClipboardTrace(
          "paste_activation_expired",
          "elapsed_ms=" +
              std::to_string(GetTickCount64() - paste_capture_return_tick_));
      paste_capture_left_for_transient_window_ = false;
      return_paste_candidate_text_.reset();
      return 0;
    }
    if (!paste_key_pressed_ && paste_capture_focus_returned_) {
      CaptureReturnPasteCandidate();
    } else if (!CaptureObservedPasteText()) {
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
