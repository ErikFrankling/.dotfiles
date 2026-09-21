// Offset generated from the exact Nix Hyprland executable during plugin build.
// The callback remains in the compositor when the plugin unloads or init fails.
#pragma once
#include "native_filter_build.hpp"
#include <link.h>
#include <unistd.h>
#include <limits.h>
#include <string>
#include <stdexcept>
#include <cstdint>
inline void *nativeGlobalFilterAddress() {
  char path[PATH_MAX + 1];
  const auto length = readlink("/proc/self/exe", path, PATH_MAX);
  if (length <= 0 || std::string(path, length) != nativeFilterExecutable)
    throw std::runtime_error("agent_native_filter_executable_mismatch");
  uintptr_t base = 0;
  const int found = dl_iterate_phdr([](dl_phdr_info *info, size_t, void *data) {
    if (!info->dlpi_name || !*info->dlpi_name) {
      *static_cast<uintptr_t *>(data) = info->dlpi_addr; return 1;
    }
    return 0;
  }, &base);
  if (found != 1) throw std::runtime_error("agent_native_filter_main_image_unavailable");
  return reinterpret_cast<void *>(base + nativeFilterOffset);
}
