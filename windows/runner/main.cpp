#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"
#include "window_record.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Size size(1280, 720);

  // What the window is created as is the record the app wrote in its last run,
  // or the default when there is nothing recorded. A recorded size is what the
  // window really was, in physical pixels, so it is used as it is and not
  // scaled to the monitor again — which is why Create is told not to scale
  // here.
  int recorded_width = 0;
  int recorded_height = 0;
  bool maximized = false;
  const bool recorded =
      ReadRecordedRecord(&recorded_width, &recorded_height, &maximized);

  if (recorded) {
    size = Win32Window::Size(static_cast<unsigned int>(recorded_width),
                             static_cast<unsigned int>(recorded_height));
  }

  // The last two arguments are Create's scale_size and the state. A
  // recorded size is not scaled, and a record that says maximized is the
  // state the window opens in — the size above is what it restores to when
  // the user un-maximizes. There is no position to pass: position is not
  // recorded, so Create places the window on the primary monitor's work area
  // (`ai/doc.md` §7).
  if (!window.Create(L"release_prepper", size, !recorded, maximized)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
