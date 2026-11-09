# Anti-malware: ClamAV with daily signature updates, on-access scanning of
# downloads and /tmp, and a weekly full scan. Detections go to the journal,
# which Alloy ships to the homelab (modules/nixos/observability).
{ username, ... }:
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
  # A laptop is often off at scan time: run a missed scan at the next boot.
  systemd.timers.clamdscan.timerConfig.Persistent = true;
}
