# Closing the lid keeps the laptop awake while it is on AC power at home (the
# KVM desk), so it can be reached over SSH and take the nightly update; closing
# it anywhere else suspends as usual.
#
# logind already ignores the lid while an external display is attached
# (HandleLidSwitchDocked=ignore), but that stops when the KVM switches away and
# the display disappears. This holds a handle-lid-switch inhibitor instead,
# keyed on AC power plus the home router's MAC behind the default gateway.
{
  pkgs,
  lib,
  ...
}:
let
  # TP-Link Archer AX12, LAN side (homelab repo, docs/router.md).
  routerMac = "20:e1:5d:e4:2e:e0";

  check = pkgs.writeShellApplication {
    name = "dock-awake-check";
    runtimeInputs = with pkgs; [
      iproute2
      iputils
      systemd
      gawk
      gnugrep
      coreutils
    ];
    text = ''
      on_ac() { [ "$(cat /sys/class/power_supply/ACAD/online 2>/dev/null)" = 1 ]; }

      at_home() {
        gw=$(ip -4 route show default table main | awk '{print $3; exit}')
        [ -n "$gw" ] || return 1
        # Make sure the neighbour entry is fresh before reading its MAC.
        ping -c 1 -W 1 "$gw" > /dev/null 2>&1 || true
        [ "$(ip neigh show "$gw" | awk '{print $5; exit}')" = "${routerMac}" ]
      }

      lid_closed() { grep -q closed /proc/acpi/button/lid/*/state; }

      if on_ac && at_home; then
        systemctl start dock-awake.service
      elif systemctl is-active --quiet dock-awake.service; then
        systemctl stop dock-awake.service
        # Leaving with the lid already shut: suspend now instead of relying on
        # logind to re-check a lid that closed while the inhibitor was held.
        if lid_closed; then
          systemctl suspend
        fi
      fi
    '';
  };

  trigger = "${pkgs.systemd}/bin/systemctl start --no-block dock-awake-check.service";
in
{
  systemd.services.dock-awake = {
    description = "Keep the closed lid from suspending while on AC at home";
    serviceConfig.ExecStart = lib.concatStringsSep " " [
      "${pkgs.systemd}/bin/systemd-inhibit"
      "--what=handle-lid-switch"
      "--who=dock-awake"
      "--why='On AC power at home'"
      "--mode=block"
      "${pkgs.coreutils}/bin/sleep infinity"
    ];
  };

  systemd.services.dock-awake-check = {
    description = "Decide whether the closed lid should suspend";
    wantedBy = [ "multi-user.target" ];
    after = [ "NetworkManager.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = lib.getExe check;
    };
  };

  # Re-decide whenever AC power or the network changes.
  services.udev.extraRules = ''
    SUBSYSTEM=="power_supply", KERNEL=="ACAD", ACTION=="change", RUN+="${trigger}"
  '';

  networking.networkmanager.dispatcherScripts = [
    {
      source = pkgs.writeShellScript "dock-awake-trigger" ''
        case "''${2:-}" in
          up | down | dhcp4-change | connectivity-change) ${trigger} ;;
        esac
      '';
      type = "basic";
    }
  ];
}
