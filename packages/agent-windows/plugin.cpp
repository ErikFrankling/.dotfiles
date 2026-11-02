// Agent windows open on AGENT-1 from the first frame, however they were launched.
//
// Every Wayland client is classified when it connects (origin.hpp says why then).
// A window of an agent client gets the tag `agent-window` when it is created,
// and the static rule `workspace = "name:agent silent", match = { tag = "agent-window" }`
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
//
// AGENT-1 always shows `agent`; see keepAgentShown for what switched it away.
#include <hyprland/src/animation/WorkspaceAnimationController.hpp>
#include <hyprland/src/layout/LayoutManager.hpp>
#include <hyprland/src/state/MonitorState.hpp>
#include <hyprland/src/state/WorkspaceState.hpp>
#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/plugins/HookSystem.hpp>
#include <hyprland/src/Compositor.hpp>
#include <hyprland/src/config/supplementary/executor/Executor.hpp>
#include <hyprland/src/desktop/rule/windowRule/WindowRuleApplicator.hpp>
#include <hyprland/src/desktop/view/window/Window.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/ipc/s1/S1.hpp>
#include <hyprland/src/ipc/s2/S2.hpp>
#include <hyprland/src/managers/eventLoop/EventLoopManager.hpp>
#include <hyprland/src/output/Monitor.hpp>
#include <hyprland/src/protocols/core/Compositor.hpp>
#include <hyprland/src/workspace/HLWorkspace.hpp>

#include <wayland-server-core.h>

#include <chrono>
#include <cstdlib>
#include <dlfcn.h>
#include <filesystem>
#include <format>
#include <fstream>
#include <unistd.h>
#include <unordered_map>
#include <utility>

#include "origin.hpp"

using namespace agentwindows;

#ifndef SYSTEMD_RUN
#error "SYSTEMD_RUN must be the store path of systemd-run"
#endif
#ifndef ENV_BIN
#error "ENV_BIN must be the store path of env"
#endif

inline HANDLE PHANDLE = nullptr;

static const std::string TAG = "agent-window";

using SpawnRawProcFn = std::optional<uint64_t> (*)(Config::Supplementary::CExecutor *, const std::string &, PHLWORKSPACE, const std::string &);
using SocketDispatchFn = IPC::Socket1::SResponse (*)(IPC::Socket1::CSocket1 *, std::string, pid_t);

namespace {

struct ClientEntry {
  wl_listener destroy{};
  wl_client *client = nullptr;
  Origin origin;
};

struct PluginState {
  wl_listener clientCreated{};
  std::unordered_map<wl_client *, ClientEntry *> clients;
  CFunctionHook *spawnHook = nullptr;
  CFunctionHook *dispatchHook = nullptr;
  // Who asked, while a request from the Hyprland socket is being answered. Zero
  // for keybinds, exec-once, rules and the compositor's own requests.
  pid_t peer = 0;
  std::vector<CHyprSignalListener> listeners;
  unsigned long execCount = 0;
  std::filesystem::path log;
};

PluginState *state = nullptr;

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
  if (window->backend().isX11())
    return nullptr;
  const auto surface = window->backend().surface();
  return surface ? surface->client() : nullptr;
}

Origin originOf(PHLWINDOW window) {
  if (auto *client = clientOf(window)) {
    if (!state->clients.contains(client))
      remember(client);  // connected before the plugin was loaded
    return state->clients.at(client)->origin;
  }
  // XWayland: the client is the X server, _NET_WM_PID names the real process.
  const auto pid = window->backend().pid();
  return pid > 1 ? classify(pid, getpid()) : Origin{};
}

bool isAgentWorkspace(const PHLWORKSPACE &workspace) { return workspace->displayName() == "agent" || workspace->displayName() == "agent-park"; }

bool onAgentSeat(PHLWINDOW window) { return window->m_workspace && isAgentWorkspace(window->m_workspace); }

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
      now, jsonString(event), reinterpret_cast<uintptr_t>(window.get()), jsonString(window->metadata().appID()), window->backend().pid(), window->backend().isX11() ? "true" : "false",
      jsonString(window->m_monitor ? window->m_monitor->m_name : ""), jsonString(window->m_workspace ? window->m_workspace->displayName() : ""), origin.agent ? "true" : "false",
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
  IPC::Socket2::sock()->postEvent({.event = "agentwindowescape", .data = line});
  const PHLWINDOWREF ref = window;
  g_pEventLoopManager->doLater([ref] {
    if (const auto w = ref.lock())
      HyprlandAPI::invokeHyprctlCommand(
          "dispatch", std::format("hl.dsp.window.move({{ workspace = \"name:agent\", follow = false, window = \"address:0x{:x}\" }})", reinterpret_cast<uintptr_t>(w.get())));
  });
}

// Which windows are an agent's is kept on the window itself, as its tag. A map
// keyed by window address went stale: a window destroyed without ever mapping
// emits no close event (vulkaninfo makes one), the allocator hands its address to
// the next window, and on 2026-11-01 that sent Erik's WebCord dialogs to the agent
// seat as the vulkaninfo session's. originOf reads the live client every time.
void tagAgent(PHLWINDOW window) { window->m_ruleApplicator->m_tagKeeper.applyTag("+" + TAG, false); }

void onWindowCreate(PHLWINDOW window) {
  if (originOf(window).agent)
    tagAgent(window);
}

void onWindowOpenEarly(PHLWINDOW window) {
  const auto origin = originOf(window);
  if (origin.agent)
    tagAgent(window);  // XWayland: _NET_WM_PID arrives after the window is created.
  writeLog(record(window, origin, "open"));
  if (origin.agent && !onAgentSeat(window))
    sendBack(window, origin, "opened-outside");
}

void onWindowMove(PHLWINDOW window, PHLWORKSPACE workspace) {
  if (!window->m_ruleApplicator->m_tagKeeper.isTagged(TAG, true) || !workspace || isAgentWorkspace(workspace))
    return;
  const auto origin = originOf(window);
  if (state->peer > 0 && classify(state->peer, getpid()).agent) {
    sendBack(window, origin, "agent-moved-it");
    return;
  }
  // Erik took it with a keybind or from his terminal: it is his to keep.
  writeLog(record(window, origin, "moved-by-erik"));
  window->m_ruleApplicator->m_tagKeeper.applyTag("-" + TAG, false);
}

std::optional<uint64_t> hkSpawnRawProc(Config::Supplementary::CExecutor *self, const std::string &args, PHLWORKSPACE workspace, const std::string &token) {
  const auto original = reinterpret_cast<SpawnRawProcFn>(state->spawnHook->m_original);
  if (state->peer <= 0)
    return original(self, args, workspace, token);
  const auto origin = classify(state->peer, getpid());
  if (!origin.agent)
    return original(self, args, workspace, token);
  return original(self, rewriteExec(args, origin, ++state->execCount, SYSTEMD_RUN, ENV_BIN), workspace, token);
}

// Hyprland gives the peer's pid only to the command it runs, and `dispatch` and
// `eval` run Lua, which reaches spawnRawProc and moveToWorkspace with no way to
// pass it on. Every socket request comes through here, `plugin unload` too: then
// PLUGIN_EXIT runs inside the original and this frame has to return afterwards, which
// is why state can be gone below and why PLUGIN_INIT pins this library in memory.
IPC::Socket1::SResponse hkSocketDispatch(IPC::Socket1::CSocket1 *self, std::string request, pid_t pid) {
  const auto original = reinterpret_cast<SocketDispatchFn>(state->dispatchHook->m_original);
  const auto outer = std::exchange(state->peer, pid);
  auto response = original(self, std::move(request), pid);
  if (state)
    state->peer = outer;
  return response;
}

// `agent-park` must never be what AGENT-1 displays: windows on `agent` then get no
// frame callbacks and agent-seat input is refused everywhere. Hyprland puts it there
// by itself. With Erik's monitors off, his workspaces move to AGENT-1; on reconnect
// the one it was showing goes home and moveWorkspaceToMonitor plugs the gap with the
// first other workspace on AGENT-1, which is `agent-park` (2026-10-31, unnoticed for
// two days). A `focuswindow` on a parked window does the same.
//
// internal=true is the point: the normal path unconstrains the pointer and releases
// mouse buttons globally, which would reach Erik's game or drag. It also sends no
// focus, warp or `workspace` event, so nothing on his monitors can tell. It skips the
// animation and layout steps, done here. Any other workspace on AGENT-1 is left alone:
// it is one of Erik's, there because his monitors are off.
void keepAgentShown() {
  for (const auto &monitor : State::monitorState()->monitors()) {
    if (monitor->m_name != "AGENT-1" || !monitor->m_activeWorkspace || monitor->m_activeWorkspace->displayName() != "agent-park")
      continue;
    for (const auto &candidate : State::workspaceState()->workspaces()) {
      const auto agent = candidate.lock();
      if (!agent || agent->displayName() != "agent" || agent->monitor() != monitor)
        continue;
      const auto parked = monitor->m_activeWorkspace;
      monitor->changeWorkspace(agent, true, true, true);
      Animation::Workspace::startAnimation(parked, Animation::Workspace::ANIMATION_TYPE_OUT, true, true);
      Animation::Workspace::startAnimation(agent, Animation::Workspace::ANIMATION_TYPE_IN, true, true);
      g_layoutManager->recalculateMonitor(monitor, Layout::CLayoutManager::RECALCULATE_MONITOR_REASON_WORKSPACE_CHANGE);
      return;
    }
  }
}

// Later, not now: these events fire halfway through moveWorkspaceToMonitor.
void keepAgentShownLater() {
  g_pEventLoopManager->doLater([] {
    if (state)
      keepAgentShown();
  });
}

CFunctionHook *hookOnly(HANDLE handle, const std::string &symbol, void *destination) {
  const auto found = HyprlandAPI::findFunctionsByName(handle, symbol);
  if (found.size() != 1)
    throw std::runtime_error("agent-windows: " + symbol + " not found exactly once");
  auto *hook = HyprlandAPI::createFunctionHook(handle, found[0].address, destination);
  if (!hook || !hook->hook())
    throw std::runtime_error("agent-windows: could not hook " + symbol);
  return hook;
}

}  // namespace

APICALL EXPORT std::string PLUGIN_API_VERSION() { return HYPRLAND_API_VERSION; }

APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
  PHANDLE = handle;
  if (std::string{__hyprland_api_get_hash()} != __hyprland_api_get_client_hash())
    throw std::runtime_error("agent-windows: built for a different Hyprland");

  Dl_info self{};
  if (!dladdr(reinterpret_cast<void *>(hkSocketDispatch), &self) || !dlopen(self.dli_fname, RTLD_NOW | RTLD_NOLOAD | RTLD_NODELETE))
    throw std::runtime_error("agent-windows: could not pin the library in memory");

  state = new PluginState;
  const auto *home = std::getenv("HOME");
  state->log = std::filesystem::path(home ? home : "/tmp") / ".local/state/window-origin/windows.jsonl";

  state->spawnHook = hookOnly(handle, "_ZN6Config13Supplementary9CExecutor12spawnRawProc", reinterpret_cast<void *>(hkSpawnRawProc));
  state->dispatchHook = hookOnly(handle, "_ZN3IPC7Socket18CSocket18dispatch", reinterpret_cast<void *>(hkSocketDispatch));

  auto &events = Event::bus()->m_events.window;
  state->listeners.emplace_back(events.create.listen([](PHLWINDOW window) { onWindowCreate(window); }));
  state->listeners.emplace_back(events.openEarly.listen([](PHLWINDOW window) { onWindowOpenEarly(window); }));
  state->listeners.emplace_back(events.moveToWorkspace.listen([](PHLWINDOW window, PHLWORKSPACE workspace) { onWindowMove(window, workspace); }));

  auto &bus = Event::bus()->m_events;
  state->listeners.emplace_back(bus.workspace.active.listen([](PHLWORKSPACE) { keepAgentShownLater(); }));
  state->listeners.emplace_back(bus.workspace.moveToMonitor.listen([](PHLWORKSPACE, PHLMONITOR) { keepAgentShownLater(); }));
  state->listeners.emplace_back(bus.monitor.added.listen([](PHLMONITOR) { keepAgentShownLater(); }));

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
  if (state->dispatchHook)
    HyprlandAPI::removeFunctionHook(PHANDLE, state->dispatchHook);
  delete state;
  state = nullptr;
}
