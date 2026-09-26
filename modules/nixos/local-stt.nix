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
      # GPU sharing with llama-swap: unload the 10 GB final recogniser after 5 h
      # idle, and ask llama-swap to evict its idle model before loading it.
      environment.STT_FINAL_IDLE_SECONDS = "18000";
      environment.STT_LLAMA_SWAP_URL = "http://127.0.0.1:8000";
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
