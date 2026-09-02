cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

link_directories("../")

set(RUST_LIBRARY "${CMAKE_SOURCE_DIR}/rust.lib")
if(NOT EXISTS "${RUST_LIBRARY}")
  message(FATAL_ERROR
    "Missing ${RUST_LIBRARY}. Run scripts/build_windows_rust_lib.ps1 "
    "with the private jmcomic3-rust-backend checkout before configuring Windows.")
endif()

add_executable(${BINARY_NAME} WIN32
  "flutter_window.cpp"
  "main.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
  "methods_plugin.cpp"
)
apply_standard_settings(${BINARY_NAME})
target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")
target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app flutter_wrapper_plugin "${RUST_LIBRARY}"
        ntdll.lib advapi32.lib bcrypt.lib cfgmgr32.lib credui.lib crypt32.lib cryptnet.lib fwpuclnt.lib kernel32.lib mswsock.lib ncrypt.lib ntdll.lib secur32.lib synchronization.lib user32.lib ws2_32.lib kernel32.lib ws2_32.lib bcrypt.lib advapi32.lib userenv.lib kernel32.lib msvcrt.lib)
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")
add_dependencies(${BINARY_NAME} flutter_assemble)
