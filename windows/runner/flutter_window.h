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
  void ActivateToolWindow();
  static LRESULT CALLBACK PasteKeyboardHook(int code, WPARAM wparam,
                                             LPARAM lparam);
  void EnsurePasteKeyboardHook();
  void RemovePasteKeyboardHook();
  void HandleInjectedPasteKey(DWORD key, bool targets_owner);
  void HandlePasteCaptureActivation(HWND activated_window, bool active);
  void ProbePasteCaptureActivation();
  void TryCompletePasteCaptureAfterTransientReturn();
  void CaptureReturnPasteCandidate();
  void EnsureClipboardListener();
  void BeginPasteCapture(std::optional<int64_t> session_id);
  bool ArmPasteCapture(std::optional<int64_t> session_id);
  bool DidPasteCaptureObserveChange(int64_t session_id);
  void DiscardPendingPasteText(int64_t session_id);
  std::optional<std::string> TakePendingPasteText(int64_t session_id);
  void HandleClipboardUpdate(bool capture_text = false,
                             bool capture_return_candidate = true);
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
  std::optional<std::string> paste_capture_baseline_text_;
  std::optional<std::string> return_paste_candidate_text_;
  std::optional<int64_t> paste_capture_session_id_;
  DWORD paste_capture_baseline_sequence_ = 0;
  DWORD paste_capture_observed_sequence_ = 0;
  int paste_capture_update_count_ = 0;
  int return_paste_candidate_retry_count_ = 0;
  bool return_paste_candidate_differs_from_baseline_ = false;
  int paste_capture_activation_probe_count_ = 0;
  int paste_capture_retry_count_ = 0;
  bool paste_capture_armed_ = false;
  bool paste_capture_invalidated_ = false;
  bool paste_key_pressed_ = false;
  bool paste_request_notification_sent_ = false;
  bool clipboard_listener_registered_ = false;
  bool paste_hook_control_pressed_ = false;
  bool paste_hook_shift_pressed_ = false;
  bool paste_capture_left_for_transient_window_ = false;
  bool paste_capture_focus_returned_ = false;
  bool paste_capture_external_clipboard_owner_ = false;
  ULONGLONG paste_capture_return_tick_ = 0;
  int paste_target_client_count_ = 0;
  bool show_on_first_frame_ = true;
  bool tool_window_activation_pending_ = false;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
