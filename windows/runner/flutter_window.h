#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <memory>
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
  void ArmPasteCapture();
  void DiscardPendingPasteText();
  bool CapturePendingPasteText(bool preserve_existing);
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
  std::optional<std::string> pending_paste_text_;
  bool paste_capture_armed_ = false;
  bool show_on_first_frame_ = true;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
