#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"
#include "window_size.h"

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
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);

  // The size the window is created with is the one the app recorded in its last
  // run, or the default when there is nothing recorded. A recorded size is what
  // the window really was, in physical pixels, so it is used as it is and not
  // scaled to the monitor again — which is why Create is told not to scale
  // here.
  int recorded_width = 0;
  int recorded_height = 0;
  const bool recorded = ReadRecordedSize(&recorded_width, &recorded_height);

  if (recorded) {
    size = Win32Window::Size(static_cast<unsigned int>(recorded_width),
                             static_cast<unsigned int>(recorded_height));
  }

  // The last argument is Create's scale_size, and a recorded size is not
  // scaled.
  if (!window.Create(L"release_prepper", origin, size, !recorded)) {
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
