// GTK requires a data-device manager even when clipboard/DnD are unavailable.
// This private implementation never calls the compositor's native seat APIs.
#pragma once
#include <wayland-server-core.h>
#include <wayland-server-protocol.h>
#include <algorithm>
#include <stdexcept>
#include <vector>

class AgentDataDevice {
  inline static AgentDataDevice *self = nullptr;
  wl_global *global = nullptr;
  std::vector<wl_resource *> resources;
  static void gone(wl_resource *r) { std::erase(self->resources, r); }
  static void destroy(wl_client *, wl_resource *r) { wl_resource_destroy(r); }
  static void offer(wl_client *, wl_resource *, const char *) {}
  static void actions(wl_client *, wl_resource *, uint32_t) {}
  inline static const struct wl_data_source_interface sourceImpl = {
      offer, destroy, actions};
  static wl_resource *create(wl_client *c, const wl_interface *iface,
                             uint32_t version, uint32_t id, const void *impl) {
    auto *r = wl_resource_create(c, iface, version, id);
    if (!r) { wl_client_post_no_memory(c); return nullptr; }
    wl_resource_set_implementation(r, impl, nullptr, gone);
    self->resources.push_back(r);
    return r;
  }
  static void source(wl_client *c, wl_resource *r, uint32_t id) {
    create(c, &wl_data_source_interface, wl_resource_get_version(r), id, &sourceImpl);
  }
  static void cancel(wl_resource *source) {
    if (source) wl_data_source_send_cancelled(source);
  }
  static void drag(wl_client *, wl_resource *, wl_resource *source,
                   wl_resource *, wl_resource *, uint32_t) { cancel(source); }
  static void selection(wl_client *, wl_resource *r, wl_resource *source, uint32_t) {
    // Explicitly report an empty private clipboard rather than changing the
    // user's selection. Clipboard transfer is not supported by this backend.
    wl_data_device_send_selection(r, nullptr);
    cancel(source);
  }
  inline static const struct wl_data_device_interface deviceImpl = {
      drag, selection, destroy};
  static void device(wl_client *c, wl_resource *r, uint32_t id, wl_resource *) {
    auto *d = create(c, &wl_data_device_interface, wl_resource_get_version(r), id, &deviceImpl);
    if (d) wl_data_device_send_selection(d, nullptr);
  }
  inline static const struct wl_data_device_manager_interface managerImpl = {source, device, destroy};
  static void bind(wl_client *c, void *, uint32_t version, uint32_t id) {
    create(c, &wl_data_device_manager_interface, std::min(version, 3u), id, &managerImpl);
  }
public:
  AgentDataDevice(wl_display *display, void *visibilityTag) {
    if (self) throw std::runtime_error("agent_data_device_duplicate");
    self = this;
    global = wl_global_create(display, &wl_data_device_manager_interface, 3, visibilityTag, bind);
    if (!global) { self = nullptr; throw std::runtime_error("agent_data_device_failed"); }
  }
  ~AgentDataDevice() {
    while (!resources.empty()) wl_resource_destroy(resources.back());
    wl_global_destroy(global);
    self = nullptr;
  }
};
