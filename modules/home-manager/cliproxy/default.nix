{
  config,
  lib,
  pkgs,
  osConfig,
  inputs,
  ...
}:

# Claude Code and Codex use CLIProxyAPI on the homelab (homelab repo
# apps/cliproxy.yaml, docs/cliproxy.md) instead of their own logins. Every
# Claude and Codex subscription is signed in there once (its own panel, /management.html), and
# the hub pools them: a session sticks to one account and moves when that
# account hits its limit. This replaces the per-account T3 Code instances.
#
# With cliproxy.clients.enable the activation merges into the files the CLIs
# also write themselves:
#   ~/.claude/settings.json  env.ANTHROPIC_BASE_URL + apiKeyHelper (reads sops)
#   ~/.codex/config.toml     model_provider = "cliproxy" + its provider table
# Turning it off removes exactly those keys again, so the local logins
# (~/.claude/.credentials.json, ~/.codex/auth.json) take over.
let
  cfg = config.cliproxy;
  hub = "https://cliproxy.erikfrankling.duckdns.org";
  clientKey = osConfig.sops.secrets.cliproxy-client-key.path;
  python = pkgs.python3.withPackages (ps: [ ps.tomli-w ]);

  # Google's Antigravity agent (`agy`, also what T3 Code's Antigravity provider
  # runs) uses its built-in LLM gateway mode against the hub: Gemini API wire
  # format with the client key, so no Google sign-in on this host. The hub's
  # Antigravity login (erik.frankling@gmail.com) carries per-login model aliases
  # for the bare names agy sends (gemini-4-neon -> gemini-4-neon-xhigh, ...;
  # homelab docs/cliproxy.md). The allowlist keeps the hub's Claude, GPT and
  # Grok models out of agy's picker.
  agyModels = lib.concatStringsSep "," [
    "gemini-4-neon-xhigh"
    "gemini-4-hydrogen-xhigh"
    "gemini-4-argon-high"
    "gemini-4-carbon-high"
    "gemini-3.8-flash-high"
    "gemini-3-flash"
    "gemini-3.5-flash-lite"
    "gemini-3.1-flash-lite"
  ];
  agyCliproxy = pkgs.writeShellScriptBin "agy" ''
    export AGY_LLM_GATEWAY_URL=${hub}
    AGY_LLM_GATEWAY_API_KEY="$(cat ${clientKey})"
    export AGY_LLM_GATEWAY_API_KEY
    export AGY_LLM_GATEWAY_WIRE_PROTOCOL=genai
    export AGY_LLM_GATEWAY_MODELS=${agyModels}
    exec ${
      inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.antigravity-cli
    }/bin/agy "$@"
  '';

  codexConfig = pkgs.writeText "cliproxy-codex.py" ''
    import os, sys, tomllib, tomli_w
    path, enable, key_file, base = sys.argv[1], sys.argv[2] == "1", sys.argv[3], sys.argv[4]
    cfg = {}
    if os.path.exists(path):
        with open(path, "rb") as f:
            cfg = tomllib.load(f)
    import copy
    before = copy.deepcopy(cfg)
    providers = cfg.setdefault("model_providers", {})
    if enable:
        cfg["model_provider"] = "cliproxy"
        providers["cliproxy"] = {
            "name": "CLIProxyAPI (homelab)",
            "base_url": base + "/v1",
            "wire_api": "responses",
            "requires_openai_auth": False,
            "supports_websockets": True,
            "experimental_bearer_token": open(key_file).read().strip(),
        }
    else:
        if cfg.get("model_provider") == "cliproxy":
            del cfg["model_provider"]
        providers.pop("cliproxy", None)
    if not providers:
        cfg.pop("model_providers", None)
    if cfg == before:
        sys.exit(0)
    tmp = path + ".cliproxy-tmp"
    with open(tmp, "wb") as f:
        tomli_w.dump(cfg, f)
    os.chmod(tmp, 0o600)
    os.replace(tmp, path)
  '';
in
{
  options.cliproxy.clients.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Point Claude Code, Codex and Antigravity (agy) on this host at the homelab CLIProxyAPI.";
  };

  config = {
    # Wins over the plain antigravity-cli from ai.nix.
    home.packages = lib.mkIf cfg.clients.enable [ (lib.hiPrio agyCliproxy) ];

    home.activation.cliproxyClients = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      settings="$HOME/.claude/settings.json"
      mkdir -p "$HOME/.claude" "$HOME/.codex"
      [ -f "$settings" ] || echo '{}' > "$settings"
      tmp="$(mktemp)"
      ${
        if cfg.clients.enable then
          ''
            ${pkgs.jq}/bin/jq --arg url "${hub}" --arg helper "cat ${clientKey}" \
              '.env = ((.env // {}) + {ANTHROPIC_BASE_URL: $url}) | .apiKeyHelper = $helper' \
              "$settings" > "$tmp" && install -m 644 "$tmp" "$settings"
          ''
        else
          ''
            ${pkgs.jq}/bin/jq --arg url "${hub}" \
              'if .env.ANTHROPIC_BASE_URL == $url then del(.env.ANTHROPIC_BASE_URL) | del(.apiKeyHelper) else . end
               | if .env == {} then del(.env) else . end' \
              "$settings" > "$tmp" && install -m 644 "$tmp" "$settings"
          ''
      }
      rm -f "$tmp"
      ${python}/bin/python3 -I ${codexConfig} "$HOME/.codex/config.toml" \
        ${if cfg.clients.enable then "1" else "0"} "${clientKey}" "${hub}"
    '';
  };
}
