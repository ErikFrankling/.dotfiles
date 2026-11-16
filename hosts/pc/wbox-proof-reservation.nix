{ pkgs, ... }:
{
  # Assigned by the host account/subordinate-ID allocator on 2026-11-16 for
  # MACHINE's reviewed no-VMM blocked/fence/reap experiment. These are observed
  # assignments, not a default range: /var/lib/wbox-setup-proof/assigned-pool.json.
  # Preserve them across activation so the quarantined lease is never recycled.
  # This creates no service, cgroup delegation, execution permit or cleanup right.
  users.groups.wbox-proof-pool.gid = 989;
  users.users.wbox-proof-pool = {
    isSystemUser = true;
    uid = 989;
    group = "wbox-proof-pool";
    home = "/var/empty";
    createHome = false;
    shell = "${pkgs.shadow}/bin/nologin";
    hashedPassword = "!";
    autoSubUidGidRange = false;
    subUidRanges = [
      {
        startUid = 165536;
        count = 65536;
      }
    ];
    subGidRanges = [
      {
        startGid = 165536;
        count = 65536;
      }
    ];
  };
}
