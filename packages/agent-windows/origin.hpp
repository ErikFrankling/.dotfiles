#pragma once
// Who started a process, from /proc alone. No Hyprland types, so the unit test
// runs it against a fake /proc tree.
//
// The cgroup is the real signal. Chromium and Electron blank /proc/PID/environ
// and flatten /proc/PID/cmdline at startup, then move themselves into their own
// app-*.scope, so the environment says nothing about them and the cgroup only
// says it early. That is why the compositor asks when the client connects, not
// when its window maps. T3CODE_THREAD_ID then names the thread.
#include <cctype>
#include <fstream>
#include <sstream>
#include <string>
#include <string_view>
#include <vector>

namespace agentwindows {

struct Origin {
  bool agent = false;
  std::string thread;
  std::string cgroup;              // of the process itself
  std::string agentCgroup;         // where the agent signal was found
  std::string via;                 // cgroup, ancestor-cgroup, ancestor-env, session
  std::vector<std::string> chain;  // comm:pid, the process first
};

inline std::string readAll(const std::string &path) {
  std::ifstream file(path, std::ios::binary);
  std::ostringstream out;
  out << file.rdbuf();
  return out.str();
}

inline bool agentCgroup(std::string_view cgroup) {
  // Erik's own apps, kitty and the T3 server (and its terminal panel) sit
  // outside these. The two services launch windows for agents (cua launch_app,
  // agent-seat launch_application).
  return cgroup.find("/app-t3code-agents.slice/") != std::string_view::npos ||
         cgroup.find("/app-t3code-jobs.slice/") != std::string_view::npos ||
         cgroup.find("/cua-driver.service") != std::string_view::npos ||
         cgroup.find("/agent-computer-use") != std::string_view::npos;
}

inline std::string cgroupOf(const std::string &proc, long pid) {
  std::ifstream file(proc + "/" + std::to_string(pid) + "/cgroup");
  std::string line;
  while (std::getline(file, line))
    if (line.rfind("0::", 0) == 0)
      return line.substr(3);
  return "";
}

inline std::string threadInEnv(const std::string &proc, long pid) {
  static constexpr std::string_view key = "T3CODE_THREAD_ID=";
  std::istringstream env(readAll(proc + "/" + std::to_string(pid) + "/environ"));
  std::string item;
  while (std::getline(env, item, '\0'))
    if (item.rfind(key, 0) == 0)
      return item.substr(key.size());
  return "";
}

// ppid and session from /proc/PID/stat. comm can hold spaces and parentheses.
inline bool statOf(const std::string &proc, long pid, std::string &comm, long &ppid, long &sid) {
  const auto stat = readAll(proc + "/" + std::to_string(pid) + "/stat");
  const auto open = stat.find('('), close = stat.rfind(')');
  if (open == std::string::npos || close == std::string::npos || close + 2 >= stat.size())
    return false;
  comm = stat.substr(open + 1, close - open - 1);
  std::istringstream rest(stat.substr(close + 2));
  char state = 0;
  long pgrp = 0;
  return bool(rest >> state >> ppid >> pgrp >> sid);
}

inline std::string threadInCgroup(const std::string &cgroupRoot, const std::string &proc, const std::string &cgroup) {
  std::ifstream procs(cgroupRoot + cgroup + "/cgroup.procs");
  long pid = 0;
  while (procs >> pid)
    if (auto thread = threadInEnv(proc, pid); !thread.empty())
      return thread;
  return "";
}

// exec from an agent runs in a scope named t3agent-<thread>-<n>.scope. Anything
// inside can be a lone Chromium with a blank environment, so the name carries it.
inline std::string threadInUnitName(std::string_view cgroup) {
  const auto start = cgroup.rfind("/t3agent-");
  if (start == std::string_view::npos)
    return "";
  auto name = cgroup.substr(start + 9);
  const auto end = name.rfind('-');
  if (end == std::string_view::npos)
    return "";
  auto thread = std::string(name.substr(0, end));
  // Unit names cannot hold the colon of an mcp:<uuid> thread (see unitSafe).
  if (thread.rfind("mcp_", 0) == 0)
    thread[3] = ':';
  return thread;
}

inline Origin classify(long pid, long stopAt = 0, const std::string &proc = "/proc",
                       const std::string &cgroupRoot = "/sys/fs/cgroup") {
  Origin origin;
  origin.cgroup = cgroupOf(proc, pid);
  long sid = 0;

  long current = pid;
  for (int depth = 0; depth < 32 && current > 1 && current != stopAt; depth++) {
    std::string comm;
    long ppid = 0, session = 0;
    if (!statOf(proc, current, comm, ppid, session))
      break;
    if (depth == 0)
      sid = session;
    origin.chain.push_back(comm + ":" + std::to_string(current));

    if (!origin.agent) {
      const auto cgroup = cgroupOf(proc, current);
      if (agentCgroup(cgroup)) {
        origin.agent = true;
        origin.via = depth == 0 ? "cgroup" : "ancestor-cgroup";
        origin.agentCgroup = cgroup;
      }
    }
    // Keep walking after the cgroup answered: a blank Chromium gets its thread
    // from the shell that started it.
    if (origin.thread.empty()) {
      if (auto thread = threadInEnv(proc, current); !thread.empty()) {
        origin.agent = true;
        if (origin.via.empty())
          origin.via = "ancestor-env";
        origin.thread = thread;
      }
    }
    current = ppid;
  }

  // Orphaned, and its parent shell is gone: the session leader may still be up.
  if (!origin.agent && sid > 1 && sid != pid && sid != stopAt) {
    if (const auto cgroup = cgroupOf(proc, sid); agentCgroup(cgroup)) {
      origin.agent = true;
      origin.via = "session";
      origin.agentCgroup = cgroup;
    }
    if (auto thread = threadInEnv(proc, sid); !thread.empty()) {
      origin.agent = true;
      if (origin.via.empty())
        origin.via = "session";
      origin.thread = thread;
    }
  }

  if (origin.agent && origin.thread.empty() && !origin.agentCgroup.empty()) {
    origin.thread = threadInUnitName(origin.agentCgroup);
    if (origin.thread.empty())
      origin.thread = threadInCgroup(cgroupRoot, proc, origin.agentCgroup);
  }
  return origin;
}

inline std::string shellQuote(std::string_view text) {
  std::string out = "'";
  for (const char c : text) {
    if (c == '\'')
      out += "'\\''";
    else
      out += c;
  }
  return out + "'";
}

inline std::string unitSafe(std::string_view text) {
  std::string out;
  for (const char c : text)
    out += (std::isalnum(static_cast<unsigned char>(c)) || c == '-' || c == '_') ? c : '_';
  return out;
}

// The slice holding this agent's scope, so the launch lands under the caps and
// cgroup of the session that asked for it.
inline std::string sliceOf(std::string_view cgroup) {
  const auto end = cgroup.rfind(".slice");
  if (end == std::string_view::npos)
    return "app-t3code-agents.slice";
  const auto start = cgroup.rfind('/', end);
  return std::string(cgroup.substr(start + 1, end + 6 - start - 1));
}

// `hyprctl dispatch exec` runs in Hyprland's own process tree, outside the agent
// cgroup. Rewrite it to run back inside.
inline std::string rewriteExec(std::string_view command, const Origin &origin, unsigned long sequence,
                               std::string_view systemdRun, std::string_view env) {
  std::ostringstream out;
  out << systemdRun << " --user --scope --quiet --collect --slice=" << sliceOf(origin.agentCgroup)
      << " --unit=t3agent-" << unitSafe(origin.thread) << "-" << sequence << ".scope -- " << env
      << " T3CODE_THREAD_ID=" << shellQuote(origin.thread) << " /bin/sh -c " << shellQuote(command);
  return out.str();
}

inline std::string jsonString(std::string_view text) {
  std::string out = "\"";
  for (const unsigned char c : text) {
    switch (c) {
      case '"': out += "\\\""; break;
      case '\\': out += "\\\\"; break;
      case '\n': out += "\\n"; break;
      case '\t': out += "\\t"; break;
      default:
        if (c < 0x20) {
          char escaped[8];
          std::snprintf(escaped, sizeof(escaped), "\\u%04x", c);
          out += escaped;
        } else {
          out += static_cast<char>(c);
        }
    }
  }
  return out + "\"";
}

}  // namespace agentwindows
