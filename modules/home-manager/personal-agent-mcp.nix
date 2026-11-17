# MCP servers only the personal agent gets: a project-level .mcp.json in its
# folder (~/.t3/personal), so no other session sees them. Project servers need
# approval; the project's .claude/settings.json gives it for exactly these.
# Modules add to `personalAgent.mcpServers` (speak, time, ...).
{ config, lib, ... }:

let
  servers = config.personalAgent.mcpServers;
in
{
  options.personalAgent.mcpServers = lib.mkOption {
    type = lib.types.attrsOf lib.types.attrs;
    default = { };
    description = "MCP servers for the personal agent's folder only (.mcp.json entries).";
  };

  config = lib.mkIf (servers != { }) {
    home.file.".t3/personal/.mcp.json".text = builtins.toJSON { mcpServers = servers; };
    home.file.".t3/personal/.claude/settings.json".text = builtins.toJSON {
      enabledMcpjsonServers = lib.attrNames servers;
      # Erik's front door: the domain skills that every other session lists
      # only in their own projects (ai.nix, claudeManagedSettings).
      skillOverrides = lib.genAttrs [
        "systems-check"
        "nix-update-doctor"
        "dotfiles-sync"
        "math-video"
        "basecamp"
      ] (_: "on");
    };
  };
}
