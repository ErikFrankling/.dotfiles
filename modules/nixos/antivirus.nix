# Anti-malware: ClamAV with hourly update checks, recursive on-access
# scanning of the home folder and a weekly scan. Detections go to the journal,
# which Alloy ships to the homelab (modules/nixos/observability), and pop up
# as a desktop notification. ClamTk is the GUI (scans, history, quarantine).
{
  pkgs,
  otherPkgs,
  username,
  lib,
  ...
}:
{
  services.clamav = {
    updater.enable = true;
    daemon = {
      enable = true;
      settings = {
        # /tmp is not watched (2026-11-11): agent sessions create and delete
        # thousands of throwaway git repos there, the watcher's queue jammed at
        # its file-descriptor limit and nothing was scanned on access any
        # more. The weekly scan below still covers /tmp.
        OnAccessIncludePath = [
          "/home/${username}"
          # "/tmp"
        ];
        # Hot application databases/caches are covered by scheduled scans.
        # Keep ordinary dotfiles, projects, downloads and documents watched.
        OnAccessExcludePath = [
          "/home/${username}/.cache"
          "/home/${username}/.codex"
          "/home/${username}/.t3"
          "/home/${username}/.mozilla"
          "/home/${username}/.config/mozilla"
          "/home/${username}/.config/1Password"
          "/home/${username}/.config/chromium"
          # The 1.4 client matches exclusion child names by prefix: remove
          # longer sibling names first so the parent retains the right links.
          "/home/${username}/.config/google-chrome-beta"
          "/home/${username}/.config/google-chrome-unstable"
          "/home/${username}/.config/google-chrome"
          "/home/${username}/.config/BraveSoftware"
          # Obsidian (Electron) makes and removes blob_storage/<uuid> at
          # login; when the watch setup at boot hits a vanished one, clamonacc
          # drops the watch on the whole home folder (boots of 2026-11-10 and
          # 2026-11-13). The notes themselves are in the vault, still watched.
          "/home/${username}/.config/obsidian"
        ];
        OnAccessExtraScanning = true;
        # clamonacc refuses to watch the directory clamd keeps its own temp
        # files in, which is /tmp by default.
        TemporaryDirectory = "/var/lib/clamav/tmp";
        # Quarantine using clamonacc's native --move option below. Keep
        # synchronous prevention off so scans do not stall desktop I/O.
        OnAccessPrevention = false;
        # Service database churn is scanned by the scheduled scan instead.
        OnAccessExcludeUname = lib.mkForce [
          "clamav"
          "executor-work"
        ];
        # Avoid duplicate events from the root-run baseline scan client.
        # User-origin accesses stay monitored; root-only accesses rely on
        # the explicit scheduled scan rather than on-access detection.
        OnAccessExcludeRootUID = true;
        # ClamAV's default; 1 could not keep up with the event queue.
        OnAccessMaxThreads = 5;
        OnAccessMaxFileSize = "100M";
        ExcludePath = "^/var/lib/clamav/quarantine(/|$)";
        MaxThreads = 2;
      };
    };
    clamonacc.enable = true;
    scanner = {
      enable = true;
      interval = "Mon *-*-* 12:00:00";
    };
  };
  systemd.tmpfiles.rules = [
    "d /var/lib/clamav/tmp 0700 clamav clamav -"
    "d /var/lib/clamav/quarantine 0700 root root -"
  ];

  # The upstream module exposes no scanner argument option. Use the tools'
  # own quarantine support, without a custom detection/removal script.
  # fanotify holds one descriptor per queued event; leave headroom for
  # scanner sockets during startup bursts (the default soft limit is 1024).
  systemd.services.clamav-clamonacc.serviceConfig.LimitNOFILE = 16384;
  # The 1.5.4 client with this system's libc silently watches only the root
  # of a three-directory test tree. The cached stable 1.4.3 client watches
  # all three and speaks fd-passing to the current 1.5.4 daemon successfully.
  # Keep the current scanning engine/signatures; only use the working client.
  systemd.services.clamav-clamonacc.serviceConfig.ExecStart =
    lib.mkForce "${otherPkgs.pkgsStable.clamav}/bin/clamonacc -F --fdpass --move=/var/lib/clamav/quarantine";
  # Let activation finish when the scan starts, not when the full scan ends.
  # The timer cannot start another instance while this one is running.
  systemd.services.clamdscan.serviceConfig.Type = lib.mkForce "exec";
  systemd.services.clamdscan.serviceConfig.ExecStart =
    lib.mkForce "${pkgs.clamav}/bin/clamdscan --fdpass --infected --move=/var/lib/clamav/quarantine /home /var/lib /tmp /etc /var/tmp";
  systemd.slices.system-clamav.sliceConfig = {
    CPUQuota = "100%";
    IOWeight = 10;
  };

  # A laptop is often off at scan time: run a missed scan at the next boot.
  systemd.timers.clamdscan.timerConfig.Persistent = true;
  # Establish a baseline after activation, then keep the weekly schedule.
  systemd.timers.clamdscan.timerConfig.OnActiveSec = "2min";

  environment.systemPackages = [ pkgs.clamtk ];

  # Popup on a detection. ClamAV's own hook (VirusEvent) runs as the clamav
  # user, which cannot reach the desktop session, so this follows the scanners'
  # journal from the session instead (wheel can read the system journal).
  home-manager.users.${username}.systemd.user.services.clamav-notify = {
    Unit = {
      Description = "Desktop notification when ClamAV finds malware";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Install.WantedBy = [ "graphical-session.target" ];
    Service = {
      Restart = "always";
      ExecStart = pkgs.writeShellScript "clamav-notify" ''
        ${pkgs.systemd}/bin/journalctl --follow --lines=0 --output=cat \
            --unit=clamav-clamonacc.service --unit=clamdscan.service \
          | ${pkgs.gnugrep}/bin/grep --line-buffered ' FOUND$' \
          | while IFS= read -r line; do
              ${pkgs.libnotify}/bin/notify-send --urgency=critical \
                --app-name=ClamAV "Malware found" "$line"
            done
      '';
    };
  };
}
