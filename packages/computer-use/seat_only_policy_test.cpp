#include "seat_only_policy.hpp"
#include <cassert>
#include <string_view>

int main() {
  assert(agentDesktopAllowed("AGENT-1", "agent"));
  assert(!agentDesktopAllowed("DP-3", "agent"));
  assert(!agentDesktopAllowed("AGENT-1", "1"));
  assert(!agentDesktopAllowed("", "agent"));
  assert(!agentDesktopAllowed("AGENT-1", ""));
  for (auto operation : {"key_transaction", "text_transaction", "pointer", "focus"}) {
    bool refused = false;
    try { requireIndependentInput(false, operation); }
    catch (const std::runtime_error &error) {
      refused = std::string_view(error.what()) == "independent_seat_unsupported_by_client";
    }
    assert(refused);
  }
  bool refused = false;
  try { requireIndependentInput(true, "focus"); }
  catch (const std::runtime_error &error) {
    refused = std::string_view(error.what()) == "desktop_focus_forbidden_in_seat_only_mode";
  }
  assert(refused);
  for (auto operation : {"key_transaction", "text_transaction", "pointer"})
    requireIndependentInput(true, operation);
}
