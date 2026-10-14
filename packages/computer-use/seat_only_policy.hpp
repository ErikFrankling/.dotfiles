#pragma once
#include <stdexcept>
#include <string_view>

inline bool agentDesktopAllowed(std::string_view monitor, std::string_view workspace) {
  return monitor == "AGENT-1" && workspace == "agent";
}

// Called in the compositor immediately before any input operation. A visual
// agent cursor alone is insufficient: both native agent-seat resources must
// exist. Explicit focus would change the human's compositor focus even on Seat.
inline void requireIndependentInput(bool supported, std::string_view operation) {
  if (!supported)
    throw std::runtime_error("independent_seat_unsupported_by_client");
  if (operation == "focus")
    throw std::runtime_error("desktop_focus_forbidden_in_seat_only_mode");
}
