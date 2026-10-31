// classify() against a fake /proc and cgroup tree. Each case is a real situation
// from the 2026-10-31 investigation.
#include "origin.hpp"

#include <cassert>
#include <cstdio>
#include <filesystem>
#include <unistd.h>

using namespace agentwindows;
namespace fs = std::filesystem;

static const char *AGENT = "/user.slice/user-1000.slice/user@1000.service/app.slice/app-t3code.slice/app-t3code-agents.slice/app-t3code-agents-abc.slice/t3code-claude-1.scope";
static const char *ERIK_SCOPE = "/user.slice/user-1000.slice/session-2.scope";
static const char *CHROME_SCOPE = "/user.slice/user-1000.slice/user@1000.service/app.slice/app-com.google.Chrome-40.scope";
static const char *T3_SERVER = "/user.slice/user-1000.slice/user@1000.service/app.slice/t3code.service";

static fs::path root;

static void proc(long pid, const std::string &comm, long ppid, long sid, const std::string &cgroup, const std::string &env = "") {
  const auto dir = root / "proc" / std::to_string(pid);
  fs::create_directories(dir);
  std::ofstream(dir / "stat") << pid << " (" << comm << ") S " << ppid << " 0 " << sid << " 0 0";
  std::ofstream(dir / "cgroup") << "1:net_cls:/\n0::" << cgroup << "\n";
  std::ofstream(dir / "environ", std::ios::binary) << env;
}

static Origin run(long pid) { return classify(pid, 0, (root / "proc").string(), (root / "cg").string()); }

int main() {
  root = fs::temp_directory_path() / ("origin-test-" + std::to_string(getpid()));
  fs::create_directories(root);
  const char rawEnv[] = "A=1\0T3CODE_THREAD_ID=t-1\0B=2\0";
  const std::string threadEnv(rawEnv, sizeof(rawEnv) - 1);

  // A plain agent process, thread from its own environment.
  proc(10, "bash", 1, 10, AGENT, threadEnv);
  auto o = run(10);
  assert(o.agent && o.via == "cgroup" && o.thread == "t-1");

  // Chromium at connect: still in the agent cgroup, environment blanked. The
  // thread comes from a parent.
  proc(11, "chrome", 10, 10, AGENT, std::string(64, '\0'));
  o = run(11);
  assert(o.agent && o.via == "cgroup" && o.thread == "t-1");

  // Chromium already in its own scope, parent shell alive.
  proc(12, "chrome", 10, 10, CHROME_SCOPE, std::string(64, '\0'));
  o = run(12);
  assert(o.agent && o.via == "ancestor-cgroup" && o.thread == "t-1");

  // Chromium in its own scope, orphaned to init, session leader still running.
  proc(13, "chrome", 1, 10, CHROME_SCOPE, std::string(64, '\0'));
  o = run(13);
  assert(o.agent && o.via == "session" && o.thread == "t-1");

  // Thread found through the cgroup's process list when nothing inherited it.
  fs::create_directories(root / "cg" / fs::path(AGENT).relative_path());
  std::ofstream(root / "cg" / fs::path(AGENT).relative_path() / "cgroup.procs") << "10\n";
  proc(14, "app", 1, 14, AGENT);
  o = run(14);
  assert(o.agent && o.thread == "t-1");

  // Erik's kitty and what he runs in it, by hand too: no thread id, his scope.
  proc(20, "kitty", 1, 20, ERIK_SCOPE, "PATH=/bin");
  proc(21, "fish", 20, 21, ERIK_SCOPE, "PATH=/bin");
  proc(22, "claude", 21, 21, ERIK_SCOPE, "PATH=/bin");
  proc(23, "chrome", 22, 21, CHROME_SCOPE, std::string(64, '\0'));
  assert(!run(21).agent);
  assert(!run(22).agent);
  assert(!run(23).agent);

  // The T3 server and its terminal panel are not agent sessions.
  proc(30, "node", 1, 30, T3_SERVER, "PATH=/bin");
  proc(31, "fish", 30, 31, T3_SERVER, "PATH=/bin");
  assert(!run(31).agent);

  // exec from an agent runs in a t3agent scope; the name carries the thread.
  const std::string execScope = "/user.slice/x/app-t3code-agents.slice/app-t3code-agents-abc.slice/t3agent-5264c1c5-2da4-3.scope";
  proc(40, "chrome", 1, 40, execScope, std::string(64, '\0'));
  o = run(40);
  assert(o.agent && o.thread == "5264c1c5-2da4");

  // Walking stops at the compositor: what it spawned for Erik stays his.
  proc(50, "Hyprland", 1, 50, ERIK_SCOPE);
  proc(51, "kitty", 50, 51, ERIK_SCOPE);
  assert(!classify(51, 50, (root / "proc").string(), (root / "cg").string()).agent);

  assert(sliceOf(AGENT) == "app-t3code-agents-abc.slice");
  assert(shellQuote("it's") == "'it'\\''s'");
  assert(unitSafe("mcp:ab-c") == "mcp_ab-c");

  Origin exec;
  exec.thread = "mcp:ab";
  exec.agentCgroup = AGENT;
  const auto rewritten = rewriteExec("chrome 'x&y'", exec, 7, "SR", "ENV");
  assert(rewritten == "SR --user --scope --quiet --collect --slice=app-t3code-agents-abc.slice --unit=t3agent-mcp_ab-7.scope -- ENV T3CODE_THREAD_ID='mcp:ab' /bin/sh -c 'chrome '\\''x&y'\\'''");

  assert(jsonString("a\"b\n") == "\"a\\\"b\\n\"");

  fs::remove_all(root);
  std::puts("origin tests passed");
}
