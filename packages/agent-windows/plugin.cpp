// Agent windows open on AGENT-1 from the first frame, however they were launched.
//
// Every Wayland client is classified when it connects (origin.hpp says why then).
// A window of an agent client gets the tag `agent-window` when it is created,
// and the static rule `workspace name:agent silent, match:tag agent-window`
// (modules/home-manager/computer-use) places it during mapWindow, before the
// compositor has shown anything. This covers every window of the client, not
// just the first, which is all a `[workspace ...]` exec rule covers.
//
// `exec` from an agent over the Hyprland socket would run in Hyprland's own
// process tree, so it is rewritten to run inside the agent's slice. Then it is
// one case, the same as a plain launch.
//
// Every map is written to window-origin's log, without titles. An agent window
// that ends up on Erik's monitors anyway is moved back and reported on the event
// socket as `agentwindowescape`; agent-desktop watch-focus notifies him.
#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/plugins/HookSystem.hpp>
#include <hyprland/src/Compositor.hpp>
#include <hyprland/src/config/supplementary/executor/Executor.hpp>
#include <hyprland/src/debug/HyprCtl.hpp>
#include <hyprland/src/desktop/Workspace.hpp>
#include <hyprland/src/desktop/rule/windowRule/WindowRuleApplicator.hpp>
#include <hyprland/src/desktop/view/Window.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/managers/EventManager.hpp>
#include <hyprland/src/managers/eventLoop/EventLoopManager.hpp>
#include <hyprland/src/output/Monitor.hpp>
#include <hyprland/src/protocols/XDGShell.hpp>
#include <hyprland/src/protocols/core/Compositor.hpp>
#include <hyprland/src/xwayland/XSurface.hpp>

#include <wayland-server-core.h>

#include <chrono>
#include <cstdlib>
#include <filesystem>
#include <format>
#include <unistd.h>
#include <unordered_map>

#include "origin.hpp"

using namespace agentwindows;

#ifndef SYSTEMD_RUN
#error "SYSTEMD_RUN must be the store path of systemd-run"
#endif
#ifndef ENV_BIN
#error "ENV_BIN must be the store path of env"
#endif

inline HANDLE PHANDLE = nullptr;

static constexpr auto TAG = "agent-window";

using SpawnRawProcFn = std::optional<uint64_t> (*)(Config::Supplementary::CExecutor *, const std::string &, PHLWORKSPACE, const std::string &);

namespace {

struct ClientEntry {
  wl_listener destroy{};
  wl_client *client = nullptr;
  Origin origin;
};

struct State {
  wl_listener clientCreated{};
  std::unordered_map<wl_client *, ClientEntry *> clients;
  std::unordered_map<Desktop::View::CWindow *, Origin> windows;
  CFunctionHook *spawnHook = nullptr;
  std::vector<CHyprSignalListener> listeners;
  unsigned long execCount = 0;
  std::filesystem::path log;
};

State *state = nullptr;

void onClientDestroy(wl_listener *listener, void *) {
  auto *entry = wl_container_of(listener, static_cast<ClientEntry *>(nullptr), destroy);
  wl_list_remove(&entry->destroy.link);
  state->clients.erase(entry->client);
  delete entry;
}

void remember(wl_client *client) {
  pid_t pid = 0;
  wl_client_get_credentials(client, &pid, nullptr, nullptr);
  auto *entry = new ClientEntry;
  entry->client = client;
  entry->origin = classify(pid, getpid());
  entry->destroy.notify = onClientDestroy;
  wl_client_add_destroy_listener(client, &entry->destroy);
  state->clients[client] = entry;
}

void onClientCreated(wl_listener *, void *data) { remember(static_cast<wl_client *>(data)); }

wl_client *clientOf(PHLWINDOW window) {
  if (window->m_isX11 || !window->m_xdgSurface || !window->m_xdgSurface->m_owner)
    return nullptr;
  return window->m_xdgSurface->m_owner->client();
}

Origin originOf(PHLWINDOW window) {
  if (auto *client = clientOf(window)) {
    if (!state->clients.contains(client))
      remember(client);  // connected before the plugin was loaded
    return state->clients.at(client)->origin;
  }
  // XWayland: the client is the X server, _NET_WM_PID names the real process.
  const auto pid = window->getPID();
  return pid > 1 ? classify(pid, getpid()) : Origin{};
}

bool onAgentSeat(PHLWINDOW window) {
  return window->m_workspace && (window->m_workspace->m_name == "agent" || window->m_workspace->m_name == "agent-park");
}

std::string record(PHLWINDOW window, const Origin &origin, std::string_view event) {
  const auto now = std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::system_clock::now().time_since_epoch()).count();
  std::string chain = "[";
  for (const auto &link : origin.chain) {
    if (chain.size() > 1)
      chain += ",";
    chain += jsonString(link);
  }
  chain += "]";
  // Never the title: this log must stay safe to read and to paste.
  return std::format(
      "{{\"ts_ms\":{},\"event\":{},\"address\":\"0x{:x}\",\"class\":{},\"pid\":{},\"x11\":{},\"monitor\":{},\"workspace\":{},\"agent\":{},\"via\":{},\"thread\":{},\"cgroup\":{},"
      "\"chain\":{}}}",
      now, jsonString(event), reinterpret_cast<uintptr_t>(window.get()), jsonString(window->m_class), window->getPID(), window->m_isX11 ? "true" : "false",
      jsonString(window->m_monitor ? window->m_monitor->m_name : ""), jsonString(window->m_workspace ? window->m_workspace->m_name : ""), origin.agent ? "true" : "false",
      jsonString(origin.via), jsonString(origin.thread), jsonString(origin.cgroup), chain);
}

void writeLog(const std::string &line) {
  std::error_code error;
  std::filesystem::create_directories(state->log.parent_path(), error);
  if (std::filesystem::file_size(state->log, error) > 32 * 1024 * 1024 && !error)
    std::filesystem::rename(state->log, std::filesystem::path(state->log).concat(".1"), error);
  std::ofstream(state->log, std::ios::app) << line << '\n';
}

void sendBack(PHLWINDOW window, const Origin &origin, std::string_view event) {
  const auto line = record(window, origin, event);
  writeLog(line);
  g_pEventManager->postEvent(SHyprIPCEvent{.event = "agentwindowescape", .data = line});
  const PHLWINDOWREF ref = window;
  g_pEventLoopManager->doLater([ref] {
    if (const auto w = ref.lock())
      HyprlandAPI::invokeHyprctlCommand("dispatch", std::format("movetoworkspacesilent name:agent,address:0x{:x}", reinterpret_cast<uintptr_t>(w.get())));
  });
}

void onWindowCreate(PHLWINDOW window) {
  const auto origin = originOf(window);
  if (origin.agent) {
    window->m_ruleApplicator->m_tagKeeper.applyTag(TAG, false);
    state->windows[window.get()] = origin;
  }
}

void onWindowOpenEarly(PHLWINDOW window) {
  auto it = state->windows.find(window.get());
  auto origin = it != state->windows.end() ? it->second : originOf(window);
  if (origin.agent && it == state->windows.end()) {
    // XWayland only: _NET_WM_PID arrives after the window is created.
    window->m_ruleApplicator->m_tagKeeper.applyTag(TAG, false);
    state->windows[window.get()] = origin;
  }
  writeLog(record(window, origin, "open"));
  if (origin.agent && !onAgentSeat(window))
    sendBack(window, origin, "opened-outside");
}

void onWindowMove(PHLWINDOW window, PHLWORKSPACE workspace) {
  const auto it = state->windows.find(window.get());
  if (it == state->windows.end() || !workspace || workspace->m_name == "agent" || workspace->m_name == "agent-park")
    return;
  const auto peer = g_pHyprCtl ? g_pHyprCtl->m_currentRequestParams.pid : 0;
  if (peer > 0 && classify(peer, getpid()).agent) {
    sendBack(window, it->second, "agent-moved-it");
    return;
  }
  // Erik took it with a keybind or from his terminal: it is his to keep.
  writeLog(record(window, it->second, "moved-by-erik"));
  state->windows.erase(it);
}

std::optional<uint64_t> hkSpawnRawProc(Config::Supplementary::CExecutor *self, const std::string &args, PHLWORKSPACE workspace, const std::string &token) {
  const auto original = reinterpret_cast<SpawnRawProcFn>(state->spawnHook->m_original);
  // pid is non-zero only while a request from the Hyprland socket is being
  // answered. Keybinds, exec-once and rules go through here with 0.
  const auto peer = g_pHyprCtl ? g_pHyprCtl->m_currentRequestParams.pid : 0;
  if (peer <= 0)
    return original(self, args, workspace, token);
  const auto origin = classify(peer, getpid());
  if (!origin.agent)
    return original(self, args, workspace, token);
  return original(self, rewriteExec(args, origin, ++state->execCount, SYSTEMD_RUN, ENV_BIN), workspace, token);
}

}  // namespace

APICALL EXPORT std::string PLUGIN_API_VERSION() { return HYPRLAND_API_VERSION; }

APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
  PHANDLE = handle;
  if (std::string{__hyprland_api_get_hash()} != __hyprland_api_get_client_hash())
    throw std::runtime_error("agent-windows: built for a different Hyprland");

  state = new State;
  const auto *home = std::getenv("HOME");
  state->log = std::filesystem::path(home ? home : "/tmp") / ".local/state/window-origin/windows.jsonl";

  const auto found = HyprlandAPI::findFunctionsByName(handle, "_ZN6Config13Supplementary9CExecutor12spawnRawProc");
  if (found.size() != 1)
    throw std::runtime_error("agent-windows: spawnRawProc not found exactly once");
  state->spawnHook = HyprlandAPI::createFunctionHook(handle, found[0].address, reinterpret_cast<void *>(hkSpawnRawProc));
  if (!state->spawnHook || !state->spawnHook->hook())
    throw std::runtime_error("agent-windows: could not hook spawnRawProc");

  auto &events = Event::bus()->m_events.window;
  state->listeners.emplace_back(events.create.listen([](PHLWINDOW window) { onWindowCreate(window); }));
  state->listeners.emplace_back(events.openEarly.listen([](PHLWINDOW window) { onWindowOpenEarly(window); }));
  state->listeners.emplace_back(events.moveToWorkspace.listen([](PHLWINDOW window, PHLWORKSPACE workspace) { onWindowMove(window, workspace); }));
  state->listeners.emplace_back(events.close.listen([](PHLWINDOW window) { state->windows.erase(window.get()); }));

  state->clientCreated.notify = onClientCreated;
  wl_display_add_client_created_listener(g_pCompositor->m_wlDisplay, &state->clientCreated);

  return {"agent-windows", "Places agent windows on AGENT-1 before they map, and records who opened every window", "Erik Frankling", "0.1.0"};
}

APICALL EXPORT void PLUGIN_EXIT() {
  wl_list_remove(&state->clientCreated.link);
  for (auto &[client, entry] : state->clients) {
    wl_list_remove(&entry->destroy.link);
    delete entry;
  }
  state->listeners.clear();
  if (state->spawnHook)
    HyprlandAPI::removeFunctionHook(PHANDLE, state->spawnHook);
  delete state;
  state = nullptr;
}
