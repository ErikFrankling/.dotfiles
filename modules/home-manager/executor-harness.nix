# Give every agent harness the one Executor MCP (homelab, see the homelab repo's
# kubernetes/homelab/apps/executor.yaml) at launch, without owning mutable
# user configs. Executor fronts every integration, including the PC's
# computer-use MCP, so this is the only MCP the harnesses need.
#
# The API key is read from the sops secret at launch and handed over as
# EXECUTOR_API_KEY. Without the key file the harness starts with no Executor
# rather than a broken server entry.
{
  pkgs,
  lib,
  keyFile,
  codexPackage,
  claudePackage,
  # Host-local stdio MCP servers ({ name = { command, args, env }; }), added
  # to every session whether or not Executor is reachable. Used for computer
  # use on the PC, where screenshots should not round-trip through Executor.
  localMcpServers ? { },
}:
let
  url = "https://executor.erikfrankling.duckdns.org/mcp";
  loadKey = ''
    if [ -r ${keyFile} ]; then
      EXECUTOR_API_KEY="$(< ${keyFile})"
      export EXECUTOR_API_KEY
    fi
  '';
  mcpConfig = pkgs.writeText "executor-mcp.json" (
    builtins.toJSON {
      mcpServers.executor = {
        type = "http";
        inherit url;
        # Expanded by Claude Code at load time.
        headers.Authorization = "Bearer \${EXECUTOR_API_KEY}";
      };
    }
  );
  localMcpConfig = pkgs.writeText "local-mcp.json" (
    builtins.toJSON {
      mcpServers = lib.mapAttrs (_: server: { type = "stdio"; } // server) localMcpServers;
    }
  );
  localClaudeArgs = lib.optionalString (localMcpServers != { }) "--mcp-config=${localMcpConfig}";
  localCodexArgs = lib.escapeShellArgs (
    lib.concatLists (
      lib.mapAttrsToList (name: server: [
        "-c"
        "mcp_servers.${name}.command=${builtins.toJSON server.command}"
        "-c"
        "mcp_servers.${name}.args=${builtins.toJSON server.args}"
        "-c"
        "mcp_servers.${name}.env=${
          "{"
          + lib.concatStringsSep "," (lib.mapAttrsToList (k: v: "${k}=${builtins.toJSON v}") server.env)
          + "}"
        }"
        "-c"
        "mcp_servers.${name}.tool_timeout_sec=300"
      ]) localMcpServers
    )
  );
  # Claude's --mcp-config takes variadic arguments. Put it after the user's
  # arguments (but before an explicit --), so it cannot consume their prompt.
  claudeLauncher = pkgs.writeShellScript "claude-executor" ''
    # Management subcommands do not accept the session-only MCP flag.
    case "''${1-}" in
      agents|attach|auth|auto-mode|doctor|gateway|import|install|logs|mcp|plugin|plugins|project|respawn|rm|setup-token|stop|kill|ultrareview|update|upgrade|help)
        exec ${claudePackage}/bin/claude "$@"
        ;;
    esac
    ${loadKey}
    configs=(${localClaudeArgs})
    if [ -n "''${EXECUTOR_API_KEY-}" ]; then
      configs+=("--mcp-config=${mcpConfig}")
    fi
    if [ ''${#configs[@]} -eq 0 ]; then
      exec ${claudePackage}/bin/claude "$@"
    fi
    args=()
    inserted=false
    for arg in "$@"; do
      if [ "$arg" = -- ] && [ "$inserted" = false ]; then
        args+=("''${configs[@]}")
        inserted=true
      fi
      args+=("$arg")
    done
    if [ "$inserted" = false ]; then
      args+=("''${configs[@]}")
    fi
    exec ${claudePackage}/bin/claude "''${args[@]}"
  '';
  codexLauncher = pkgs.writeShellScript "codex-executor" ''
    ${loadKey}
    if [ -z "''${EXECUTOR_API_KEY-}" ]; then
      exec ${codexPackage}/bin/codex ${localCodexArgs} "$@"
    fi
    exec ${codexPackage}/bin/codex ${localCodexArgs} \
      -c ${lib.escapeShellArg "mcp_servers.executor.url=${builtins.toJSON url}"} \
      -c 'mcp_servers.executor.bearer_token_env_var="EXECUTOR_API_KEY"' \
      -c 'mcp_servers.executor.tool_timeout_sec=300' \
      "$@"
  '';
in
{
  inherit url mcpConfig;

  codex = pkgs.symlinkJoin {
    name = "${codexPackage.name}-executor";
    paths = [ codexPackage ];
    postBuild = ''
      rm "$out/bin/codex"
      ln -s ${codexLauncher} "$out/bin/codex"
    '';
    meta = codexPackage.meta or { };
    passthru = codexPackage.passthru or { };
  };

  claude = pkgs.symlinkJoin {
    name = "${claudePackage.name}-executor";
    paths = [ claudePackage ];
    postBuild = ''
      rm "$out/bin/claude"
      ln -s ${claudeLauncher} "$out/bin/claude"
    '';
    meta = claudePackage.meta or { };
    passthru = claudePackage.passthru or { };
  };
}
