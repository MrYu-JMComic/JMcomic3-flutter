#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <cstdlib>
#include <filesystem>
#include <string>
#include <vector>

#include "flutter_window.h"
#include "utils.h"
#include "../rust.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {

    std::vector<wchar_t> module_path(32768);
    const DWORD module_len = GetModuleFileNameW(
        nullptr, module_path.data(), static_cast<DWORD>(module_path.size()));
    if (module_len == 0 || module_len >= module_path.size() - 1) {
        return EXIT_FAILURE;
    }
    const std::filesystem::path data_path =
        std::filesystem::path(module_path.data(), module_path.data() + module_len)
            .parent_path() /
        L"data" / L"application";
    const std::wstring data_path_string = data_path.wstring();
    const int utf8_size = WideCharToMultiByte(
        CP_UTF8, WC_ERR_INVALID_CHARS, data_path_string.data(),
        static_cast<int>(data_path_string.size()), nullptr, 0, nullptr, nullptr);
    if (utf8_size <= 0) {
        return EXIT_FAILURE;
    }
    std::string data_path_utf8(static_cast<size_t>(utf8_size), '\0');
    if (WideCharToMultiByte(
            CP_UTF8, WC_ERR_INVALID_CHARS, data_path_string.data(),
            static_cast<int>(data_path_string.size()), data_path_utf8.data(),
            utf8_size, nullptr, nullptr) <= 0) {
        return EXIT_FAILURE;
    }
    init_ffi(data_path_utf8.c_str());

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
  if (!window.CreateAndShow(L"JMcomic3", origin, size)) {
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
