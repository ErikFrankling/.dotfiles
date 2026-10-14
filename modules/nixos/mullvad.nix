{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.mullvad-vpn;
in
{
  # Mullvad, off by default and switched on by hand: `mullvad connect`, the
  # desktop app, or the row in the shell's network panel
  # (~/projects/personal/quickshell/panels/Network.qml). Autoconnect and
  # lockdown stay off on purpose -- this machine also runs Cloudflare WARP for
  # work, and Mullvad's firewall drops everything outside its own tunnel while
  # it is connected.
  services.mullvad-vpn = {
    enable = true;
    # The Electron app: login screen, map and the full relay list. The daemon
    # and the `mullvad` CLI come from the default package either way.
    gui.enable = true;
  };

  # The daemon keeps its login (a device key) in /var/lib/mullvad-vpn, which
  # survives rebuilds but not a reinstall, and Mullvad revokes devices from the
  # account side. So the login is re-asserted on every boot and every rebuild:
  # a no-op while the device is valid, a fresh login the moment it is not.
  #
  # Each login registers a new device and an account holds five, which is why
  # this tests first and never logs in blind.
  systemd.services.mullvad-login = {
    description = "Log the Mullvad daemon in to the account from sops";
    wantedBy = [ "multi-user.target" ];
    requires = [ "mullvad-daemon.service" ];
    after = [
      "mullvad-daemon.service"
      "network-online.target"
    ];
    wants = [ "network-online.target" ];
    path = [
      cfg.package
      pkgs.gnugrep
    ];
    serviceConfig = {
      Type = "oneshot";
      # The daemon's socket appears a moment after its unit counts as started,
      # and the login itself needs Mullvad's API to be reachable.
      Restart = "on-failure";
      RestartSec = 10;
    };
    script = ''
      # "Device name" is printed only for a device the account still accepts;
      # a revoked one still prints the account number.
      if mullvad account get | grep -q '^Device name'; then
        exit 0
      fi
      # Quietly: the CLI echoes the account number, and stdout is the journal.
      mullvad account login "$(cat ${config.sops.secrets.mullvad-account.path})" > /dev/null
    '';
  };

  # Mullvad's firewall (table `inet mullvad`, policy drop) admits nothing but
  # its own tunnel while connected. Out of the box that cuts off the two other
  # networks this machine lives on, so both are let back in here and all three
  # work at once.
  #
  # 1. The LAN. Local network sharing is a daemon setting kept in
  #    /var/lib/mullvad-vpn and defaults to "block", which drops every inbound
  #    LAN connection: SSH, the T3 Code server, wayvnc -- and with them the
  #    tailnet, whose devices arrive here through the subnet router as LAN
  #    traffic. Re-asserted on every boot and rebuild like the login above.
  systemd.services.mullvad-lan = {
    description = "Keep Mullvad's local network sharing allowed";
    wantedBy = [ "multi-user.target" ];
    requires = [ "mullvad-daemon.service" ];
    after = [ "mullvad-daemon.service" ];
    path = [ cfg.package ];
    serviceConfig = {
      Type = "oneshot";
      # The daemon's socket appears a moment after its unit counts as started.
      Restart = "on-failure";
      RestartSec = 5;
    };
    script = ''
      mullvad lan set allow
    '';
  };

  # 2. Cloudflare WARP (./desktop.nix). Its include-only routes sit in their
  #    own table ahead of Mullvad's, so work traffic is already routed into
  #    the CloudflareWARP interface -- and then rejected by Mullvad's output
  #    chain. That also kills DNS for everything that reads /etc/resolv.conf,
  #    because WARP's local resolver (127.0.2.2) sends its DoH queries out
  #    through that interface.
  #
  #    0xf41 is the conntrack mark Mullvad puts on split-tunnelled processes
  #    and accepts in every chain; setting it in mangle (priority -150) gets
  #    it there before Mullvad's filter (priority 0) looks. WARP's own tunnel
  #    to the Cloudflare edge is not marked, so it still rides inside Mullvad.
  #    Deleted before added because the firewall re-runs these on every reload
  #    without flushing mangle.
  networking.firewall.extraCommands = ''
    iptables -t mangle -D OUTPUT -o CloudflareWARP -j CONNMARK --set-mark 0xf41 2>/dev/null || true
    iptables -t mangle -A OUTPUT -o CloudflareWARP -j CONNMARK --set-mark 0xf41
    ip6tables -t mangle -D OUTPUT -o CloudflareWARP -j CONNMARK --set-mark 0xf41 2>/dev/null || true
    ip6tables -t mangle -A OUTPUT -o CloudflareWARP -j CONNMARK --set-mark 0xf41
  '';
  networking.firewall.extraStopCommands = ''
    iptables -t mangle -D OUTPUT -o CloudflareWARP -j CONNMARK --set-mark 0xf41 2>/dev/null || true
    ip6tables -t mangle -D OUTPUT -o CloudflareWARP -j CONNMARK --set-mark 0xf41 2>/dev/null || true
  '';

  # Each importing host must carry a `mullvad-account` entry in its default
  # sops file, i.e.:  sops hosts/<host>/secrets/secrets.yaml
  #   mullvad-account: "1234567890123456"
  # Rebuilds fail at activation until the entry exists.
  sops.secrets.mullvad-account = { };
}
