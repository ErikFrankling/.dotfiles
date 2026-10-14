#include "agent_data_device.hpp"
#include <wayland-client.h>
#include <sys/wait.h>
#include <signal.h>
#include <cassert>
#include <chrono>
#include <cstring>
#include <filesystem>
#include <iostream>
#include <unistd.h>

struct Seen { wl_data_device_manager *manager = nullptr; wl_seat *seat = nullptr; wl_surface *surface = nullptr; int empty = 0; int cancelled = 0; };
static void added(void *p, wl_registry *r, uint32_t id, const char *iface, uint32_t) {
  auto &s = *static_cast<Seen *>(p);
  if (!strcmp(iface, "wl_data_device_manager")) s.manager = static_cast<wl_data_device_manager *>(wl_registry_bind(r, id, &wl_data_device_manager_interface, 3));
  if (!strcmp(iface, "wl_seat")) s.seat = static_cast<wl_seat *>(wl_registry_bind(r, id, &wl_seat_interface, 1));
  if (!strcmp(iface, "wl_surface")) s.surface = static_cast<wl_surface *>(wl_registry_bind(r, id, &wl_surface_interface, 1));
}
static void removed(void *, wl_registry *, uint32_t) {}
static const wl_registry_listener registryListener{added, removed};
static void dataOffer(void *, wl_data_device *, wl_data_offer *) { assert(false); }
static void enter(void *, wl_data_device *, uint32_t, wl_surface *, wl_fixed_t, wl_fixed_t, wl_data_offer *) { assert(false); }
static void leave(void *, wl_data_device *) { assert(false); }
static void motion(void *, wl_data_device *, uint32_t, wl_fixed_t, wl_fixed_t) { assert(false); }
static void drop(void *, wl_data_device *) { assert(false); }
static void selected(void *p, wl_data_device *, wl_data_offer *offer) { assert(!offer); ++static_cast<Seen *>(p)->empty; }
static const wl_data_device_listener deviceListener{dataOffer, enter, leave, motion, drop, selected};
static void target(void *, wl_data_source *, const char *) {}
static void send(void *, wl_data_source *, const char *, int32_t) { assert(false); }
static void cancelled(void *p, wl_data_source *) { ++static_cast<Seen *>(p)->cancelled; }
static void performed(void *, wl_data_source *) { assert(false); }
static void finished(void *, wl_data_source *) { assert(false); }
static void action(void *, wl_data_source *, uint32_t) {}
static const wl_data_source_listener sourceListener{target, send, cancelled, performed, finished, action};
static void bindSeat(wl_client *c, void *, uint32_t v, uint32_t id) { assert(wl_resource_create(c, &wl_seat_interface, v, id)); }
static void bindSurface(wl_client *c, void *, uint32_t v, uint32_t id) { assert(wl_resource_create(c, &wl_surface_interface, v, id)); }
int main(int argc, char **argv) {
  if (argc == 2) {
    auto *d = wl_display_connect(argv[1]); assert(d);
    auto *r = wl_display_get_registry(d); Seen s;
    wl_registry_add_listener(r, &registryListener, &s);
    assert(wl_display_roundtrip(d) >= 0 && s.manager && s.seat);
    auto *dev = wl_data_device_manager_get_data_device(s.manager, s.seat);
    wl_data_device_add_listener(dev, &deviceListener, &s);
    assert(wl_display_roundtrip(d) >= 0 && s.empty == 1);
    auto *src = wl_data_device_manager_create_data_source(s.manager);
    wl_data_source_add_listener(src, &sourceListener, &s);
    wl_data_source_offer(src, "text/plain;charset=utf-8");
    wl_data_device_set_selection(dev, src, 1);
    assert(wl_display_roundtrip(d) >= 0 && s.empty == 2 && s.cancelled == 1);
    wl_data_source_destroy(src);
    wl_data_device_set_selection(dev, nullptr, 2);
    assert(wl_display_roundtrip(d) >= 0 && s.empty == 3 && s.cancelled == 1);
    auto *dragSource = wl_data_device_manager_create_data_source(s.manager);
    wl_data_source_add_listener(dragSource, &sourceListener, &s);
    wl_data_source_offer(dragSource, "text/plain");
    wl_data_source_set_actions(dragSource, WL_DATA_DEVICE_MANAGER_DND_ACTION_COPY);
    wl_data_device_start_drag(dev, dragSource, s.surface, nullptr, 3);
    assert(wl_display_roundtrip(d) >= 0 && s.cancelled == 2 && s.empty == 3);
    wl_data_source_destroy(dragSource);
    wl_data_device_release(dev); wl_data_device_manager_destroy(s.manager);
    wl_seat_destroy(s.seat); wl_registry_destroy(r);
    assert(wl_display_roundtrip(d) >= 0);
    wl_display_disconnect(d); return 0;
  }
  auto runtime = std::filesystem::current_path() / ("data-device-test-" + std::to_string(getpid()));
  std::filesystem::create_directory(runtime);
  std::filesystem::permissions(runtime, std::filesystem::perms::owner_all);
  setenv("XDG_RUNTIME_DIR", runtime.c_str(), 1);
  auto *d = wl_display_create(); assert(d);
  const char *socket = wl_display_add_socket_auto(d); assert(socket);
  {
    AgentDataDevice data(d, nullptr);
    auto *seat = wl_global_create(d, &wl_seat_interface, 1, nullptr, bindSeat); assert(seat);
    // A synthetic surface global supplies a valid origin resource without a renderer.
    auto *surface = wl_global_create(d, &wl_surface_interface, 1, nullptr, bindSurface); assert(surface);
    auto pid = fork(); assert(pid >= 0);
    if (!pid) { execl(argv[0], argv[0], socket, nullptr); _exit(127); }
    auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(5);
    int status = 0;
    while (waitpid(pid, &status, WNOHANG) == 0) {
      if (std::chrono::steady_clock::now() > deadline) { kill(pid, SIGKILL); assert(false); }
      assert(wl_event_loop_dispatch(wl_display_get_event_loop(d), 10) >= 0);
      wl_display_flush_clients(d);
    }
    assert(WIFEXITED(status) && WEXITSTATUS(status) == 0);
    wl_display_destroy_clients(d); wl_global_destroy(seat); wl_global_destroy(surface);
  }
  wl_display_destroy(d); std::filesystem::remove_all(runtime);
  std::cout << "PASS: private data-device bind, empty selection, source cancellation, resource cleanup\n";
}
