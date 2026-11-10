# Anti-malware: ClamAV with daily signature updates, on-access scanning of
# downloads and /tmp, and a weekly full scan. Detections go to the journal,
# which Alloy ships to the homelab (modules/nixos/observability), and pop up
# as a desktop notification. ClamTk is the GUI (scans, history, quarantine).
{ pkgs, username, ... }:
{
  services.clamav = {
    updater.enable = true;
    daemon = {
      enable = true;
      settings = {
        OnAccessIncludePath = [
          "/home/${username}/Downloads"
          "/tmp"
        ];
        # clamonacc refuses to watch the directory clamd keeps its own temp
        # files in, which is /tmp by default.
        TemporaryDirectory = "/var/lib/clamav/tmp";
        # Report, do not block: blocking stalls browsers mid-download.
        OnAccessPrevention = false;
        OnAccessExcludeUname = "clamav";
      };
    };
    clamonacc.enable = true;
    scanner = {
      enable = true;
      interval = "Mon *-*-* 12:00:00";
    };
  };
  systemd.tmpfiles.rules = [ "d /var/lib/clamav/tmp 0700 clamav clamav -" ];

  # A laptop is often off at scan time: run a missed scan at the next boot.
  systemd.timers.clamdscan.timerConfig.Persistent = true;

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
