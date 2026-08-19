#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <memory>
#include <cstdint>
#include <optional>
#include <string>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

  void SetShowOnFirstFrame(bool show);

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  void RegisterWindowEffectsChannel();
  void RegisterClipboardChannel();
  void RegisterCredentialsChannel();
  void RegisterProcessWindowChannel();
  void RegisterAppLifecycleChannel();
  static LRESULT CALLBACK PasteKeyboardHook(int code, WPARAM wparam,
                                             LPARAM lparam);
  void EnsurePasteKeyboardHook();
  void RemovePasteKeyboardHook();
  void HandleInjectedPasteKey(DWORD key, bool targets_owner);
  void EnsureClipboardListener();
  void BeginPasteCapture(std::optional<int64_t> session_id);
  bool ArmPasteCapture(std::optional<int64_t> session_id);
  bool DidPasteCaptureObserveChange(int64_t session_id);
  void DiscardPendingPasteText(int64_t session_id);
  std::optional<std::string> TakePendingPasteText(int64_t session_id);
  void HandleClipboardUpdate();
  void RetryPendingPasteCapture();
  bool CaptureObservedPasteText();
  void NotifyPasteRequested();
  void InvalidatePasteCapture();
  void ResetPasteCapture();
  void SetRadialMode(bool enabled);

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      window_effects_channel_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      clipboard_channel_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      credentials_channel_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      process_window_channel_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      app_lifecycle_channel_;
  static FlutterWindow* paste_keyboard_hook_owner_;
  HHOOK paste_keyboard_hook_ = nullptr;
  std::optional<std::string> pending_paste_text_;
  std::optional<int64_t> paste_capture_session_id_;
  DWORD paste_capture_baseline_sequence_ = 0;
  DWORD paste_capture_observed_sequence_ = 0;
  int paste_capture_retry_count_ = 0;
  bool paste_capture_armed_ = false;
  bool paste_capture_invalidated_ = false;
  bool paste_key_pressed_ = false;
  bool paste_request_notification_sent_ = false;
  bool clipboard_listener_registered_ = false;
  bool paste_hook_control_pressed_ = false;
  bool paste_hook_shift_pressed_ = false;
  int paste_target_client_count_ = 0;
  bool show_on_first_frame_ = true;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
