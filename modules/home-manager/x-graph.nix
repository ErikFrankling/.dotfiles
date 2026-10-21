# x-graph: Erik's X/Twitter archive, people graph and "find that tweet" search
# (~/projects/personal/x-graph, github.com/ErikFrankling/x-graph, private).
#
# The web app listens on localhost:3047. The phone reaches it as
# https://x.erikfrankling.duckdns.org (LAN + tailnet only): homelab Traefik
# rewrites the Host to pc-3047 and the dev-preview Caddy forwards it
# (homelab repo, kubernetes/homelab/ingress/dev-preview.yaml).
#
# Only the light part runs here. Embeddings come from the homelab
# (192.168.50.100:8790, apps/x-graph-embed.yaml there): Erik, 2026-10-21,
# heavy compute goes to the homelab so the PC never lags. The daily
# bookmark/like import is a T3 scheduled task, not a unit, because it needs
# the signed-in agent Chromium.
{
  config,
  pkgs,
  ...
}:
let
  repo = "${config.home.homeDirectory}/projects/personal/x-graph";
in
{
  systemd.user.services.x-graph = {
    Unit.Description = "x-graph web app (localhost:3047, https://x.erikfrankling.duckdns.org)";
    Service = {
      WorkingDirectory = repo;
      ExecStart = "${pkgs.bun}/bin/bun server/index.ts";
      Environment = [
        "NODE_ENV=production"
        "PORT=3047"
      ];
      Restart = "always";
      RestartSec = 5;
      # A web server for one person: keep it out of Erik's way.
      Nice = 10;
      CPUWeight = 20;
      IOSchedulingClass = "idle";
      MemoryMax = "1G";
    };
    Install.WantedBy = [ "default.target" ];
  };
}
