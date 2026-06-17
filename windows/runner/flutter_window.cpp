#include "flutter_window.h"

#include <flutter/standard_method_codec.h>

#include <optional>

#include "flutter/generated_plugin_registrant.h"

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
  SetupWindowMethodChannel();
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
  ExitImagePreviewFullscreen();
  window_method_channel_ = nullptr;

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

void FlutterWindow::SetupWindowMethodChannel() {
  if (!flutter_controller_ || !flutter_controller_->engine()) {
    return;
  }
  window_method_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "novel_studio/window",
          &flutter::StandardMethodCodec::GetInstance());
  window_method_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "enterImagePreviewFullscreen") {
          result->Success(
              flutter::EncodableValue(EnterImagePreviewFullscreen()));
          return;
        }
        if (call.method_name() == "exitImagePreviewFullscreen") {
          result->Success(
              flutter::EncodableValue(ExitImagePreviewFullscreen()));
          return;
        }
        result->NotImplemented();
      });
}

bool FlutterWindow::EnterImagePreviewFullscreen() {
  HWND hwnd = GetHandle();
  if (!hwnd) {
    return false;
  }
  if (image_preview_fullscreen_) {
    return true;
  }

  image_preview_window_style_ = GetWindowLongPtr(hwnd, GWL_STYLE);
  image_preview_window_ex_style_ = GetWindowLongPtr(hwnd, GWL_EXSTYLE);
  image_preview_window_placement_.length = sizeof(WINDOWPLACEMENT);
  GetWindowPlacement(hwnd, &image_preview_window_placement_);
  GetWindowRect(hwnd, &image_preview_window_rect_);

  HMONITOR monitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
  MONITORINFO monitor_info{};
  monitor_info.cbSize = sizeof(monitor_info);
  if (!GetMonitorInfo(monitor, &monitor_info)) {
    return false;
  }

  const LONG_PTR fullscreen_style =
      image_preview_window_style_ &
      ~(WS_CAPTION | WS_THICKFRAME | WS_MINIMIZE | WS_MAXIMIZEBOX | WS_SYSMENU);
  const LONG_PTR fullscreen_ex_style =
      image_preview_window_ex_style_ &
      ~(WS_EX_DLGMODALFRAME | WS_EX_WINDOWEDGE | WS_EX_CLIENTEDGE |
        WS_EX_STATICEDGE);
  SetWindowLongPtr(hwnd, GWL_STYLE, fullscreen_style);
  SetWindowLongPtr(hwnd, GWL_EXSTYLE, fullscreen_ex_style);

  const RECT& bounds = monitor_info.rcMonitor;
  SetWindowPos(hwnd, HWND_TOP, bounds.left, bounds.top,
               bounds.right - bounds.left, bounds.bottom - bounds.top,
               SWP_NOOWNERZORDER | SWP_FRAMECHANGED | SWP_SHOWWINDOW);
  image_preview_fullscreen_ = true;
  return true;
}

bool FlutterWindow::ExitImagePreviewFullscreen() {
  HWND hwnd = GetHandle();
  if (!hwnd) {
    return false;
  }
  if (!image_preview_fullscreen_) {
    return true;
  }

  SetWindowLongPtr(hwnd, GWL_STYLE, image_preview_window_style_);
  SetWindowLongPtr(hwnd, GWL_EXSTYLE, image_preview_window_ex_style_);
  SetWindowPlacement(hwnd, &image_preview_window_placement_);
  SetWindowPos(hwnd, nullptr, image_preview_window_rect_.left,
               image_preview_window_rect_.top,
               image_preview_window_rect_.right - image_preview_window_rect_.left,
               image_preview_window_rect_.bottom -
                   image_preview_window_rect_.top,
               SWP_NOZORDER | SWP_NOOWNERZORDER | SWP_FRAMECHANGED |
                   SWP_SHOWWINDOW);
  image_preview_fullscreen_ = false;
  return true;
}
