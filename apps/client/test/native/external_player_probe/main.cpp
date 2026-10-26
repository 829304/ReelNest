#include <windows.h>
#include <shellapi.h>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <string>

// Test-only executable. Never registered as an association or shipped in Release.
int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR, int) {
  int count = 0;
  auto arguments = CommandLineToArgvW(GetCommandLineW(), &count);
  wchar_t executable[32768]{};
  GetModuleFileNameW(nullptr, executable, 32768);
  const auto output = std::filesystem::path(executable).parent_path() / L"capture.bin";
  std::ofstream file(output, std::ios::binary | std::ios::trunc);
  const std::uint32_t argument_count = count > 0 ? count - 1 : 0;
  file.write(reinterpret_cast<const char*>(&argument_count), sizeof(argument_count));
  for (int i = 1; i < count; ++i) {
    const std::uint32_t length = static_cast<std::uint32_t>(wcslen(arguments[i]));
    file.write(reinterpret_cast<const char*>(&length), sizeof(length));
    file.write(reinterpret_cast<const char*>(arguments[i]), length * sizeof(wchar_t));
  }
  const bool fail = count > 1 && std::wstring(arguments[1]).find(L"fail.mp4") != std::wstring::npos;
  LocalFree(arguments);
  return fail ? 5 : 0;
}
