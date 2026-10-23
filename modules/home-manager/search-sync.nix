# search-sync: keeps Onyx, the search over everything (homelab
# kubernetes/homelab/apps/onyx.yaml, https://search.erikfrankling.duckdns.org),
# up to date with what only exists on this PC: T3 threads, Claude Code and
# Codex transcripts, Thunderbird's mail caches, the Obsidian vault, the Canvas
# archive, x-graph and the company brain (~/projects/personal/search-sync,
# github.com/ErikFrankling/search-sync, private).
#
# Hourly, and only documents whose text changed are sent. The PC only reads
# and parses; embedding runs on the homelab GPU. The first run after a reset
# takes hours (about 170 M characters); later runs take minutes.
{
  config,
  osConfig,
  pkgs,
  ...
}:
let
  repo = "${config.home.homeDirectory}/projects/personal/search-sync";
  run = pkgs.writeShellScript "search-sync" ''
    set -eu
    ONYX_API_KEY="$(< ${osConfig.sops.secrets.search-sync-token.path})"
    BRAIN_TOKEN="$(< ${osConfig.sops.secrets.brain-token.path})"
    export ONYX_API_KEY BRAIN_TOKEN
    cd ${repo}
    [ -d node_modules ] || ${pkgs.bun}/bin/bun install --frozen-lockfile
    exec ${pkgs.bun}/bin/bun src/main.ts
  '';
in
{
  systemd.user.services.search-sync = {
    Unit.Description = "Push local sessions, mail and notes into Onyx (search.erikfrankling.duckdns.org)";
    Service = {
      Type = "oneshot";
      ExecStart = "${run}";
      Environment = [
        "PATH=${pkgs.poppler-utils}/bin:/run/current-system/sw/bin"
        "SEARCH_SYNC_CONCURRENCY=4"
      ];
      # Mostly waiting on the homelab; keep the parsing out of Erik's way.
      Nice = 15;
      CPUWeight = 10;
      IOSchedulingClass = "idle";
      MemoryMax = "3G";
      TimeoutStartSec = "12h";
    };
  };
  systemd.user.timers.search-sync = {
    Unit.Description = "Hourly search-sync";
    Timer = {
      OnBootSec = "10min";
      OnUnitInactiveSec = "1h";
      Persistent = true;
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
