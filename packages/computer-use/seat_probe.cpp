// Read-only registry probe for live native/agent seat isolation checks.
#include <wayland-client.h>
#include <unistd.h>
#include <cstdio>
#include <cstring>
#include <vector>
struct Seat { wl_seat *resource; };
static std::vector<Seat> seats;
static void caps(void *, wl_seat *, uint32_t value) { std::printf("capabilities=%u\n", value); }
static void name(void *, wl_seat *, const char *value) { std::printf("seat=%s\n", value); }
static const wl_seat_listener seatListener{caps, name};
static void added(void *, wl_registry *registry, uint32_t id, const char *interface, uint32_t version) {
  if (std::strcmp(interface, "wl_seat")) return;
  auto *seat=static_cast<wl_seat *>(wl_registry_bind(registry,id,&wl_seat_interface,version < 7 ? version : 7));
  wl_seat_add_listener(seat,&seatListener,nullptr); seats.push_back({seat});
}
static void removed(void *, wl_registry *, uint32_t) {}
static const wl_registry_listener registryListener{added,removed};
int main() {
  alarm(5);
  auto *display=wl_display_connect(nullptr);
  if (!display) { std::fputs("Cannot connect to Wayland\n",stderr);return 1; }
  auto *registry=wl_display_get_registry(display);
  wl_registry_add_listener(registry,&registryListener,nullptr);
  if (wl_display_roundtrip(display)<0 || wl_display_roundtrip(display)<0) return 2;
  std::printf("seat_count=%zu\n",seats.size());
  for (auto seat:seats) wl_seat_destroy(seat.resource);
  wl_registry_destroy(registry);wl_display_disconnect(display);
  return seats.size()==1 ? 0 : 3;
}
