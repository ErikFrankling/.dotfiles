{
  lib,
  config,
  username,
  ...
}:
let
  package = import ../../tools/local-stt;
in
{
  options.services.local-stt.enable = lib.mkEnableOption "local streaming dictation and VibeVoice final transcription";
  config = lib.mkIf config.services.local-stt.enable {
    systemd.services.local-stt = {
      description = "Local GPU speech transcription";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      environment.STT_RECORDINGS = "/var/lib/local-stt";
      environment.XDG_CACHE_HOME = "/var/lib/local-stt/cache";
      serviceConfig = {
        ExecStart = "${package}/bin/local-stt-server";
        User = username;
        SupplementaryGroups = [
          "render"
          "video"
        ];
        StateDirectory = "local-stt";
        StateDirectoryMode = "0700";
        UMask = "0077";
        Restart = "on-failure";
        RestartSec = 5;
        TimeoutStopSec = 15;
        KillMode = "control-group";
        MemoryHigh = "8G";
        MemoryMax = "10G";
        MemorySwapMax = "256M";
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = "read-only";
        PrivateTmp = true;
      };
    };
  };
}
