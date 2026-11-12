# Two tailnets on the work laptop (Erik, 2026-11-12).
#
# Host: Ablo's tailnet, through the ordinary services.tailscale. It owns DNS,
# so every lookup on the laptop goes to the resolver Ablo sets in its tailnet
# (the DNS blocking Ablo uses for SOC 2). Signed in once by hand as
# erik@abloatai.com with `sudo tailscale login`, which adds an Ablo profile
# next to the old home one (`tailscale switch --list`).
#
# Network namespace "home": Erik's own tailnet, a second tailscaled that
# cannot touch the host's routes, firewall chains or DNS. Two tailscaled in
# one namespace share routing table 52, the ts-* chains and 100.100.100.100,
# and the DNS of one leaks into the other (madflex.de/tailscale-two-tailnets).
# The host reaches the home LAN (192.168.50.0/24: Nix cache, logs, Grafana)
# over a veth pair into the namespace; the names are public DNS records, so
# no home resolver is needed. The phone reaches T3 Code through this tailnet,
# on the node samsung-ablo-home.
#
# Every agent on this laptop gets its model tokens from cliproxy on the home
# LAN. Never stop or log out a tailscaled here before the other path to
# 192.168.50.0/24 is up and cliproxy answers through it.
#
#   tailscale status                                   Ablo
#   tailscale --socket=/run/tailscale-home/tailscaled.sock status   home
{
  config,
  lib,
  pkgs,
  ...
}:
let
  tailscale = config.services.tailscale.package;
  socket = "/run/tailscale-home/tailscaled.sock";
  hostAddr = "10.200.0.1";
  nsAddr = "10.200.0.2";
  homeLan = "192.168.50.0/24";
  t3Port = 3773;
in
{
  # The shared module enrolls with the home tailnet's key (tailscale.nix);
  # that key now belongs to the namespaced daemon below.
  services.tailscale.authKeyFile = lib.mkForce null;

  systemd.services.netns-home = {
    description = "Network namespace for the home tailnet";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-pre.target" ];
    path = [
      pkgs.iproute2
      pkgs.iptables
      pkgs.procps
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ip netns del home 2> /dev/null || true
      ip netns add home
      ip link add veth-home type veth peer name veth0 netns home
      ip addr add ${hostAddr}/30 dev veth-home
      ip link set veth-home up
      ip -n home addr add ${nsAddr}/30 dev veth0
      ip -n home link set lo up
      ip -n home link set veth0 up
      ip -n home route add default via ${hostAddr}

      # The namespace reaches the internet (control plane, peers) through
      # the host.
      iptables -t nat -C POSTROUTING -s ${nsAddr} ! -o veth-home -j MASQUERADE 2> /dev/null \
        || iptables -t nat -A POSTROUTING -s ${nsAddr} ! -o veth-home -j MASQUERADE

      # Host traffic for the home LAN leaves the namespace as the tailnet
      # node. On the home Wi-Fi the directly connected route (metric 600)
      # wins over this one.
      ip netns exec home sysctl -qw net.ipv4.ip_forward=1
      ip netns exec home iptables -t nat -A POSTROUTING -s ${hostAddr} -o tailscale0 -j MASQUERADE
      ip route add ${homeLan} via ${nsAddr} metric 5000
    '';
    preStop = ''
      iptables -t nat -D POSTROUTING -s ${nsAddr} ! -o veth-home -j MASQUERADE || true
      ip netns del home || true
    '';
  };

  # The namespaced daemon resolves through the host's resolver, so its
  # lookups go to Ablo's DNS as well.
  services.resolved.settings.Resolve.DNSStubListenerExtra = hostAddr;
  environment.etc."netns/home/resolv.conf".text = "nameserver ${hostAddr}\n";
  networking.firewall.interfaces.veth-home = {
    allowedTCPPorts = [
      53
      t3Port
    ];
    allowedUDPPorts = [ 53 ];
  };

  systemd.services.tailscaled-home = {
    description = "Tailscale node agent (home tailnet, own network namespace)";
    wantedBy = [ "multi-user.target" ];
    after = [
      "netns-home.service"
      "network-online.target"
      "systemd-resolved.service"
    ];
    wants = [ "network-online.target" ];
    bindsTo = [ "netns-home.service" ];
    path = [
      pkgs.iproute2
      pkgs.iptables
      pkgs.procps
      pkgs.kmod
    ];
    # Like the upstream unit: a switch must not take the tailnet down.
    stopIfChanged = false;
    serviceConfig = {
      Type = "notify";
      NetworkNamespacePath = "/run/netns/home";
      BindReadOnlyPaths = "/etc/netns/home/resolv.conf:/etc/resolv.conf";
      # Without the system bus it cannot ask the host's systemd-resolved or
      # NetworkManager to change DNS.
      InaccessiblePaths = "/run/dbus";
      ExecStart = "${tailscale}/bin/tailscaled --statedir=/var/lib/tailscale-home --socket=${socket} --tun=tailscale0";
      Restart = "on-failure";
      RuntimeDirectory = "tailscale-home";
      RuntimeDirectoryMode = "0755";
      StateDirectory = "tailscale-home";
      StateDirectoryMode = "0700";
      CacheDirectory = "tailscale-home";
      CacheDirectoryMode = "0750";
    };
  };

  # Enrolls a node of its own (samsung-ablo-home) with the home tailnet's key
  # on the first start, and re-asserts the settings on every start.
  systemd.services.tailscaled-home-up = {
    description = "Home tailnet login and settings";
    wantedBy = [ "tailscaled-home.service" ];
    after = [ "tailscaled-home.service" ];
    partOf = [ "tailscaled-home.service" ];
    path = [
      tailscale
      pkgs.jq
      pkgs.coreutils
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ts() { tailscale --socket=${socket} "$@"; }
      state=NoState
      for _ in $(seq 60); do
        state=$(ts status --json --peers=false | jq -r .BackendState) || state=NoState
        case $state in NoState | Starting) sleep 1 ;; *) break ;; esac
      done
      if [ "$state" = NeedsLogin ]; then
        ts up --auth-key "$(cat ${config.sops.secrets.tailscale-authkey.path})?preauthorized=true&ephemeral=false" \
          --advertise-tags=tag:client --hostname=${config.networking.hostName}-home \
          --accept-routes --accept-dns=false
      else
        ts set --accept-routes --accept-dns=false
      fi
    '';
  };

  # T3 Code for the phone, on the home tailnet. T3 listens on the host's
  # loopback only; the namespace reaches it through systemd's socket proxy on
  # the veth address.
  systemd.sockets.t3code-home-proxy = {
    wantedBy = [ "sockets.target" ];
    listenStreams = [ "${hostAddr}:${toString t3Port}" ];
    socketConfig.FreeBind = true;
  };
  systemd.services.t3code-home-proxy = {
    description = "T3 Code for the home tailnet namespace";
    serviceConfig.ExecStart = "${config.systemd.package}/lib/systemd/systemd-socket-proxyd 127.0.0.1:${toString t3Port}";
  };
  systemd.services.t3code-tailnet = {
    description = "T3 Code access over the home tailnet";
    wantedBy = [ "multi-user.target" ];
    after = [ "tailscaled-home-up.service" ];
    requires = [ "tailscaled-home.service" ];
    serviceConfig = {
      ExecStart = "${tailscale}/bin/tailscale --socket=${socket} serve --tcp=${toString t3Port} tcp://${hostAddr}:${toString t3Port}";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };
}
