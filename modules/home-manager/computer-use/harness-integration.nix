# Add one MCP server at launch without taking ownership of mutable user configs.
{
  pkgs,
  lib,
  runtimePackage,
  codexPackage,
  claudePackage,
}:
let
  command = "${runtimePackage}/bin/agent-computer-use";
  mcpConfig = pkgs.writeText "agent-desktop-mcp.json" (
    builtins.toJSON {
      mcpServers.agent-desktop = {
        type = "stdio";
        inherit command;
        args = [ "mcp" ];
      };
    }
  );
  # Claude's --mcp-config takes variadic arguments. Put it after the user's
  # arguments (but before an explicit --), so it cannot consume their prompt.
  claudeLauncher = pkgs.writeShellScript "claude-agent-desktop" ''
    # Management subcommands do not accept the session-only MCP flag.
    case "''${1-}" in
      agents|attach|auth|auto-mode|doctor|gateway|import|install|logs|mcp|plugin|plugins|project|respawn|rm|setup-token|stop|kill|ultrareview|update|upgrade|help)
        exec ${claudePackage}/bin/claude "$@"
        ;;
    esac
    args=()
    inserted=false
    for arg in "$@"; do
      if [ "$arg" = -- ] && [ "$inserted" = false ]; then
        args+=("--mcp-config=${mcpConfig}")
        inserted=true
      fi
      args+=("$arg")
    done
    if [ "$inserted" = false ]; then
      args+=("--mcp-config=${mcpConfig}")
    fi
    exec ${claudePackage}/bin/claude "''${args[@]}"
  '';
in
{
  inherit mcpConfig command;

  codex = pkgs.symlinkJoin {
    name = "${codexPackage.name}-agent-desktop";
    paths = [ codexPackage ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      rm "$out/bin/codex"
      makeWrapper ${codexPackage}/bin/codex "$out/bin/codex" \
        --add-flags ${
          lib.escapeShellArg (
            lib.escapeShellArgs [
              "-c"
              "mcp_servers.agent-desktop.command=${builtins.toJSON command}"
              "-c"
              "mcp_servers.agent-desktop.args=[\"mcp\"]"
            ]
          )
        }
    '';
    meta = codexPackage.meta or { };
    passthru = codexPackage.passthru or { };
  };

  claude = pkgs.symlinkJoin {
    name = "${claudePackage.name}-agent-desktop";
    paths = [ claudePackage ];
    postBuild = ''
      rm "$out/bin/claude"
      ln -s ${claudeLauncher} "$out/bin/claude"
    '';
    meta = claudePackage.meta or { };
    passthru = claudePackage.passthru or { };
  };
}
