#include "window_size.h"

#include <shlobj.h>
#include <versionapi.h>
#include <windows.h>

#include <cwctype>
#include <filesystem>
#include <fstream>
#include <sstream>
#include <string>

namespace {

// The format version this reader understands, which must stay equal to
// `schemaVersion` in `lib/feature/release/release.dart` — that is what writes
// the file. A line of a version this does not write is not read (`ai/doc.md`
// §7).
const int kFormatVersion = 1;

const wchar_t* kFileName = L"window_size.txt";

// A token is a whole number, or the line is not one the app wrote: "1440.5" is
// not read as 1440. Written without exceptions, because the runner is built
// with `_HAS_EXCEPTIONS=0`.
bool parse_whole(const std::string& token, int* value) {
  size_t index = 0;
  bool negative = false;

  if (token.empty()) {
    return false;
  }

  if (token[0] == '-' || token[0] == '+') {
    negative = token[0] == '-';
    index = 1;
  }

  if (index == token.size()) {
    return false;
  }

  long long parsed = 0;

  for (; index < token.size(); index++) {
    const char character = token[index];

    if (character < '0' || character > '9') {
      return false;
    }

    parsed = parsed * 10 + (character - '0');
  }

  *value = negative ? static_cast<int>(-parsed) : static_cast<int>(parsed);

  return true;
}

// One value of the VERSIONINFO resource's string table, read the way the
// resource says it is encoded: the block names the language and the code page,
// and the key is that pair followed by the value name.
std::wstring version_info_value(const void* block, const wchar_t* name) {
  void* value = nullptr;
  unsigned int length = 0;

  if (!VerQueryValueW(block, L"\\", &value, &length)) {
    return std::wstring();
  }

  const VS_VERSIONINFO* info = static_cast<const VS_VERSIONINFO*>(value);
  const unsigned int block_id = (info->wLanguage << 12) | info->wCodePage;

  wchar_t key[64];
  swprintf(key, 64, L"%08x\\%s", block_id, name);

  if (!VerQueryValueW(block, key, &value, &length)) {
    return std::wstring();
  }

  return std::wstring(static_cast<wchar_t*>(value));
}

// The same rules path_provider_windows uses for a directory component, so the
// app and this reader name the same directory: the characters a name cannot
// have become "_", trailing whitespace and trailing dots are removed, and a
// component longer than 255 is cut to 255. What is left empty is not a
// directory.
std::wstring sanitize_directory_name(const std::wstring& raw) {
  std::wstring sanitized;

  for (const wchar_t character : raw) {
    switch (character) {
      case L'<':
      case L'>':
      case L':':
      case L'"':
      case L'/':
      case L'\\':
      case L'|':
      case L'?':
      case L'*':
        sanitized += L'_';
        break;
      default:
        sanitized += character;
        break;
    }
  }

  while (!sanitized.empty() &&
         (iswspace(sanitized.back()) || sanitized.back() == L'.')) {
    sanitized.pop_back();
  }

  if (sanitized.size() > 255) {
    sanitized.resize(255);
  }

  return sanitized;
}

// The name the file is read from, which is the directory path_provider resolves
// for the app's other files: Roaming AppData — the folder CSIDL_APPDATA names —
// plus company-name\product-name from the VERSIONINFO resource. The product
// falls back to the executable name without its extension, and the company
// component is dropped when the resource has no company name.
std::wstring recorded_size_path() {
  wchar_t base[MAX_PATH + 1];

  if (SHGetFolderPathW(nullptr, CSIDL_APPDATA, nullptr, 0, base) != S_OK) {
    return std::wstring();
  }

  wchar_t module[MAX_PATH + 1];

  if (GetModuleFileNameW(nullptr, module, MAX_PATH) == 0) {
    return std::wstring();
  }

  std::wstring company;
  std::wstring product;

  const unsigned int block_size = GetFileVersionInfoSizeW(module, nullptr);

  if (block_size > 0) {
    std::string block(block_size, '\0');

    if (GetFileVersionInfoW(module, 0, block_size, block.data())) {
      company = sanitize_directory_name(version_info_value(block.data(),
                                                           L"CompanyName"));
      product = sanitize_directory_name(version_info_value(block.data(),
                                                          L"ProductName"));
    }
  }

  const std::wstring name(module);

  if (product.empty()) {
    const size_t start = name.find_last_of(L'\\');
    const size_t dot = name.find_last_of(L'.');

    // The extension is only an extension when it is after the last separator.
    product = (dot != std::wstring::npos && dot > start)
                  ? name.substr(start + 1, dot - start - 1)
                  : name.substr(start + 1);
  }

  std::wstring directory(base);

  if (!company.empty()) {
    directory += L'\\';
    directory += company;
  }

  directory += L'\\';
  directory += product;
  directory += L'\\';
  directory += kFileName;

  return directory;
}

}  // namespace

bool ReadRecordedSize(int* width, int* height) {
  const std::wstring path = recorded_size_path();

  if (path.empty()) {
    return false;
  }

  std::ifstream file(std::filesystem::path(path), std::ios::binary);

  if (!file) {
    return false;
  }

  std::string line;

  if (!std::getline(file, line)) {
    return false;
  }

  // The line is "version width height", separated by whitespace.
  std::istringstream tokens(line);
  int values[3] = {0, 0, 0};
  int count = 0;

  std::string token;

  while (tokens >> token) {
    int value;

    if (!parse_whole(token, &value)) {
      return false;
    }

    if (count < 3) {
      values[count] = value;
    }

    count++;
  }

  if (count != 3 || values[0] != kFormatVersion) {
    return false;
  }

  // A window is never zero wide or zero tall, so a number outside that is not a
  // size the runner can use.
  if (values[1] <= 0 || values[2] <= 0) {
    return false;
  }

  *width = values[1];
  *height = values[2];

  return true;
}
