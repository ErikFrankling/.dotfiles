// Real libwayland server/client registry exchange, no compositor or live desktop.
#include "seat_visibility.hpp"
#include <wayland-client.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <signal.h>
#include <cassert>
#include <chrono>
#include <cstdlib>
#include <iostream>
#include <vector>
#include <filesystem>

static bool base(const wl_client *, const wl_global *g, void *) {
  // Exercise preservation of the compositor's preexisting privilege decision.
  return wl_global_get_interface(g) != &wl_compositor_interface;
}
static void bindSeat(wl_client *c, void *, uint32_t v, uint32_t id) {
  assert(wl_resource_create(c, &wl_seat_interface, v, id));
}
struct Seen { std::vector<std::pair<uint32_t,uint32_t>> seats; bool forbidden = false; bool textInput = false; };
static void added(void *data, wl_registry *, uint32_t name, const char *iface, uint32_t version) {
  auto &s = *static_cast<Seen *>(data);
  if (!strcmp(iface, "wl_seat")) s.seats.emplace_back(name, version);
  if (!strcmp(iface, "wl_compositor")) s.forbidden = true;
  if (!strcmp(iface, "zwp_text_input_manager_v3")) s.textInput = true;
}
static void removed(void *, wl_registry *, uint32_t) {}
static const wl_registry_listener listener{added, removed};

int main(int argc, char **argv) {
  if (argc == 3) {
    auto *d = wl_display_connect(argv[1]); assert(d);
    auto *r = wl_display_get_registry(d); Seen seen;
    wl_registry_add_listener(r, &listener, &seen);
    assert(wl_display_roundtrip(d) >= 0);
    assert(seen.seats.size() == 1 && !seen.forbidden);
    assert(seen.textInput == (std::atoi(argv[2]) == 8));
    assert(seen.seats[0].second == static_cast<uint32_t>(std::atoi(argv[2])));
    auto *s = static_cast<wl_seat *>(wl_registry_bind(r, seen.seats[0].first, &wl_seat_interface, 1));
    assert(wl_display_roundtrip(d) >= 0);
    wl_seat_destroy(s); wl_registry_destroy(r); wl_display_disconnect(d);
    return 0;
  }
  const auto runtime = std::filesystem::current_path() / ("seat-test-" + std::to_string(getpid()));
  std::filesystem::create_directory(runtime);
  std::filesystem::permissions(runtime, std::filesystem::perms::owner_all);
  setenv("XDG_RUNTIME_DIR", runtime.c_str(), 1);
  auto *d = wl_display_create(); assert(d);
  const char *socket = wl_display_add_socket_auto(d); assert(socket);
  {
    SeatVisibility visibility(d, base);
    auto *native = wl_global_create(d, &wl_seat_interface, 8, nullptr, bindSeat);
    auto *agent = wl_global_create(d, &wl_seat_interface, 7, &visibility, bindSeat);
    auto *privileged = wl_global_create(d, &wl_compositor_interface, 1, nullptr, bindSeat);
    const wl_interface textInputInterface{"zwp_text_input_manager_v3", 1, 0, nullptr, 0, nullptr};
    auto *textInput = wl_global_create(d, &textInputInterface, 1, nullptr, bindSeat);
    assert(native && agent && privileged && textInput);
    // Repeated reconnects also exercise client-cache destruction/address reuse.
    for (int i = 0; i < 8; ++i) {
      auto pid = fork(); assert(pid >= 0);
      if (pid == 0) {
        if (i % 2) setenv("HYPRLAND_AGENT_SEAT", "1", 1);
        else unsetenv("HYPRLAND_AGENT_SEAT");
        execl(argv[0], argv[0], socket, i % 2 ? "7" : "8", nullptr);
        _exit(127);
      }
      const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(5);
      int status = 0;
      while (waitpid(pid, &status, WNOHANG) == 0) {
        if (std::chrono::steady_clock::now() > deadline) { kill(pid, SIGKILL); assert(false); }
        assert(wl_event_loop_dispatch(wl_display_get_event_loop(d), 10) >= 0);
        wl_display_flush_clients(d);
      }
      assert(WIFEXITED(status) && WEXITSTATUS(status) == 0);
      wl_event_loop_dispatch(wl_display_get_event_loop(d), 0);
    }
    wl_global_destroy(textInput); wl_global_destroy(privileged); wl_global_destroy(agent); wl_global_destroy(native);
    wl_display_destroy_clients(d);
  }
  wl_display_destroy(d);
  std::filesystem::remove_all(runtime);
  std::cout << "PASS: native/agent seat filtering, binds, upstream privilege filter, agent native-IME exclusion, reconnect cleanup\n";
}
