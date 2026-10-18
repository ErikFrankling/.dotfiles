{ ... }:
let
  # Ports that may be previewed. Dev-server defaults, nothing more: loopback on
  # this box also holds things that must never reach the LAN (Chromium's
  # DevTools on 9222, the computer-use bridge on 4790, Syncthing's GUI on 8384,
  # llama-swap on 8000, the time tracker on 5600). Keep any new range clear of
  # those. The phone-preview skill (../home-manager/dev-preview) lists the
  # same ports for agents -- change both together.
  ports = builtins.concatStringsSep "|" [
    "1234" # Parcel
    "1313" # Hugo
    "30[0-9][0-9]" # 3000-3099: Next, Remix, Rails, Express, ...
    "40[0-9][0-9]" # 4000-4099: Phoenix, Jekyll, opencode's own 4096
    "4173" # vite preview
    "4200" # Angular
    "4321" # Astro
    "5[01][0-9][0-9]" # 5000-5199: Flask, Vite 5173...
    "6006" # Storybook
    "808[0-9]" # 8080-8089: webpack, Expo, generic
  ];
  domain = "erikfrankling\\.duckdns\\.org";
in
{
  # Phone previews of dev servers that listen on loopback.
  #
  #   https://pc-5173.erikfrankling.duckdns.org
  #     -> homelab Traefik (wildcard cert, lan-only: LAN + tailnet)
  #     -> this Caddy on :3999, which reads the port out of the hostname
  #     -> localhost:5173
  #
  # The Traefik half is one HostRegexp route in the homelab repo
  # (kubernetes/homelab/ingress/dev-preview.yaml). A single label like
  # `pc-5173` keeps the name under the existing *.erikfrankling.duckdns.org
  # cert; `5173.pc.erikfrankling...` would need a second wildcard.
  services.caddy = {
    enable = true;
    # Plain HTTP behind Traefik, which terminates TLS. No admin API either.
    globalConfig = ''
      auto_https off
      admin off
      servers {
        trusted_proxies static 192.168.50.100/32
      }
    '';
    virtualHosts."http://:3999".extraConfig = ''
      @dev header_regexp dev Host ^pc-(${ports})\.${domain}$
      handle @dev {
        reverse_proxy localhost:{re.dev.1} {
          # Dev servers trust localhost and reject other hosts (Vite's
          # allowedHosts, Next's allowedDevOrigins, websocket origin checks),
          # so they are shown the address they think they are on...
          header_up Host localhost:{re.dev.1}
          header_up Origin ^https://pc-[0-9]+\.${domain}$ http://localhost:{re.dev.1}
          # ...and redirects back to it are pointed at the phone's address.
          header_down Location ^https?://(localhost|127\.0\.0\.1):[0-9]+ https://pc-{re.dev.1}.erikfrankling.duckdns.org
        }
      }
      handle {
        respond "pc-<port>: port not allowed or not a dev preview host" 404
      }
    '';
  };

  # Only Traefik may connect, and k3s masquerades it to the node address
  # (192.168.50.100) -- same arrangement as the computer-use bridge in
  # ../../hosts/pc/configuration.nix.
  networking.firewall.extraCommands = ''
    iptables -A nixos-fw -i eno1 -p tcp --dport 3999 -s 192.168.50.100 -j nixos-fw-accept
  '';
}
