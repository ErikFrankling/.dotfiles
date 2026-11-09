# SOC 2 endpoint controls for the samsung-ablo laptop. Only this host imports
# it. Each control says how it is met and how to show it (README.md has the
# evidence commands).
#
# Background: Vanta's Device Monitor does not support NixOS. On Linux it only
# checks disk encryption anyway; screen lock, antivirus and password manager
# are shown with manual evidence (help.vanta.com 11345596). Research notes:
# ~/projects/ablo/research/.
{
  config,
  lib,
  pkgs,
  username,
  ...
}:
let
  # Lock after this long without input. 5 minutes is at or below what common
  # SOC 2 policies ask for (5-15 min); use the company's policy value.
  lockAfterSeconds = 300;
in
{
  imports = [
    ./vanta.nix
    # Password manager: the 1Password app and CLI (same module as the other
    # laptops).
    ../../modules/nixos/1password.nix
  ];

  # --- Disk encryption: LUKS2 on everything but /boot (disko.nix). ---
  assertions = [
    {
      assertion = config.boot.initrd.luks.devices ? cryptroot;
      message = "soc2.nix: the root file system must be on LUKS (disko.nix).";
    }
    {
      assertion = config.networking.firewall.enable;
      message = "soc2.nix: the firewall must stay on.";
    }
  ];

  # --- Screen lock: hypridle locks with hyprlock after idle and before sleep. ---
  # The NixOS module adds hyprlock's PAM service, so it checks the login
  # password. Locking uses ext-session-lock: if hyprlock dies the session
  # stays locked.
  programs.hyprlock.enable = true;
  home-manager.users.${username} = {
    services.hypridle = {
      enable = true;
      settings = {
        general = {
          lock_cmd = "pidof hyprlock || hyprlock";
          before_sleep_cmd = "loginctl lock-session";
          # Hold sleep until the lock screen is actually up.
          inhibit_sleep = 3;
        };
        listener = [
          {
            timeout = lockAfterSeconds;
            on-timeout = "loginctl lock-session";
          }
        ];
      };
    };
    programs.hyprlock = {
      enable = true;
      # The NixOS module installs it (with PAM); this only writes the config.
      package = null;
      settings = {
        general = {
          # Unlock always needs the password, even right after locking.
          grace = 0;
          hide_cursor = true;
        };
        # Black: the screen is OLED and has no idle blanking here.
        background = [ { color = "rgb(000000)"; } ];
        input-field = [
          {
            size = "300, 50";
            position = "0, -80";
            halign = "center";
            valign = "center";
            outline_thickness = 2;
            placeholder_text = "Password";
          }
        ];
      };
    };
  };

  # --- Anti-malware: ClamAV with fresh signatures, on-access scanning of
  # downloads, and a weekly scan. Detections go to the journal, which Alloy
  # ships to the homelab (modules/nixos/observability). ---
  services.clamav = {
    updater.enable = true;
    daemon = {
      enable = true;
      settings = {
        OnAccessIncludePath = [
          "/home/${username}/Downloads"
          "/tmp"
        ];
        # Report, do not block: blocking on-access stalls browsers mid-download.
        OnAccessPrevention = false;
        OnAccessExtraScanning = true;
        # clamd reads the files itself; never scan its own reads.
        OnAccessExcludeUname = "clamav";
      };
    };
    clamonacc.enable = true;
    scanner = {
      enable = true;
      # Weekly, at lunch: a laptop is asleep at the module's default 04:00.
      interval = "Mon *-*-* 12:00:00";
    };
  };
  systemd.timers.clamdscan.timerConfig.Persistent = true;
  systemd.services.clamdscan.serviceConfig = {
    Nice = 19;
    IOSchedulingClass = "idle";
  };

  # --- Patching: the daily auto-update (configuration.nix, autoUpdate). ---
  # --- Firewall: NixOS default (on, asserted above). ---
}
