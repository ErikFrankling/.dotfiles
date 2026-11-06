{
  config,
  lib,
  pkgs,
  osConfig,
  ...
}:

# Claude Code and Codex use CLIProxyAPI on the homelab (homelab repo
# apps/cliproxy.yaml, docs/cliproxy.md) instead of their own logins. Every
# Claude and Codex subscription is signed in there once (`cliproxy-login`), and
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
  managementKey = osConfig.sops.secrets.cliproxy-management-key.path;
  python = pkgs.python3.withPackages (ps: [ ps.tomli-w ]);

  cliproxyLogin = pkgs.writeShellApplication {
    name = "cliproxy-login";
    runtimeInputs = [ pkgs.xdg-utils ];
    text = ''
      export CLIPROXY_URL="${hub}"
      export CLIPROXY_MANAGEMENT_KEY_FILE="${managementKey}"
      exec ${python}/bin/python3 -I ${./login.py} "$@"
    '';
  };

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
    default = false;
    description = "Point Claude Code and Codex on this host at the homelab CLIProxyAPI.";
  };

  config = {
    home.packages = [ cliproxyLogin ];

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
