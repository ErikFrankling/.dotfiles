// Single-seat views for a single native Hyprland session. Not a security boundary:
// same-uid clients may opt in, but cannot accidentally inherit the human seat.
#pragma once
#include <wayland-server-core.h>
#include <wayland-server-protocol.h>
#include <unistd.h>
#include <fstream>
#include <map>
#include <memory>
#include <string>
#include <cstring>

class SeatVisibility {
public:
  using BaseFilter = bool (*)(const wl_client *, const wl_global *, void *);
private:
  struct Client {
    wl_listener destroy; // first member, used by destroy callback
    SeatVisibility *owner;
    const wl_client *client;
    bool agent;
  };
  wl_display *display;
  BaseFilter base;
  std::map<const wl_client *, std::unique_ptr<Client>> clients;
  static void gone(wl_listener *listener, void *) {
    auto *entry = reinterpret_cast<Client *>(listener);
    wl_list_remove(&entry->destroy.link);
    entry->owner->clients.erase(entry->client);
  }
  static bool marked(const wl_client *client) {
    pid_t pid; uid_t uid; gid_t gid;
    wl_client_get_credentials(client, &pid, &uid, &gid);
    if (uid != getuid() || pid <= 0) return false;
    std::ifstream env("/proc/" + std::to_string(pid) + "/environ", std::ios::binary);
    std::string item;
    while (std::getline(env, item, '\0'))
      if (item == "HYPRLAND_AGENT_SEAT=1") return true;
    return false;
  }
  static bool filter(const wl_client *client, const wl_global *global, void *data) {
    auto &self = *static_cast<SeatVisibility *>(data);
    if (!self.base(client, global, nullptr)) return false;
    if (wl_global_get_interface(global) == &wl_data_device_manager_interface)
      return self.isAgent(client) == (wl_global_get_user_data(global) == &self);
    // These native protocol implementations use compositor-wide keyboard,
    // clipboard or pointer state and cannot safely serve the private seat.
    if (self.isAgent(client)) {
      const char *name = wl_global_get_interface(global)->name;
      constexpr const char *nativeOnly[] = {
        "zwp_primary_selection_device_manager_v1",
        "zwlr_data_control_manager_v1", "ext_data_control_manager_v1",
        "zwp_text_input_manager_v1", "zwp_text_input_manager_v2", "zwp_text_input_manager_v3",
        "zwp_input_method_manager_v2", "zwp_input_method_v1",
        "zwp_virtual_keyboard_manager_v1", "zwlr_virtual_pointer_manager_v1",
        "zwp_pointer_constraints_v1", "zwp_relative_pointer_manager_v1",
        "wp_cursor_shape_manager_v1", "zwp_pointer_gestures_v1",
        "zwp_tablet_manager_v2", "zwp_keyboard_shortcuts_inhibit_manager_v1",
        "hyprland_input_capture_manager_v1", "hyprland_focus_grab_manager_v1",
        "hyprland_global_shortcuts_manager_v1", "vicinae_hotkey_manager_v1",
        "ext_data_device_manager_v1", "wp_pointer_warp_v1"
      };
      for (const char *blocked : nativeOnly) if (!std::strcmp(name, blocked)) return false;
    }
    if (wl_global_get_interface(global) != &wl_seat_interface) return true;
    return self.isAgent(client) == (wl_global_get_user_data(global) == &self);
  }
public:
  SeatVisibility(wl_display *d, BaseFilter b): display(d), base(b) {
    wl_display_set_global_filter(display, filter, this);
  }
  ~SeatVisibility() {
    wl_display_set_global_filter(display, base, nullptr);
    for (auto &[_, entry] : clients) wl_list_remove(&entry->destroy.link);
  }
  bool isAgent(const wl_client *client) {
    if (auto it = clients.find(client); it != clients.end()) return it->second->agent;
    auto entry = std::make_unique<Client>();
    entry->owner = this; entry->client = client; entry->agent = marked(client);
    entry->destroy.notify = gone;
    wl_client_add_destroy_listener(const_cast<wl_client *>(client), &entry->destroy);
    bool agent = entry->agent;
    clients.emplace(client, std::move(entry));
    return agent;
  }
};
