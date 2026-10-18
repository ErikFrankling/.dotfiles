{
  lib,
  config,
  pkgs,
  username,
  ...
}:
let
  package = import ../../tools/local-stt;
  sttPkgs = import ../../tools/stt-benchmark/pkgs.nix;
in
{
  options.services.local-stt.enable = lib.mkEnableOption "local streaming dictation and VibeVoice final transcription";
  config = lib.mkIf config.services.local-stt.enable {
    # The workers dlopen the system Vulkan driver. Built against another glibc
    # they find no GPU and dictation silently dies (2026-10-11).
    assertions = [
      {
        assertion = sttPkgs.stdenv.cc.libc.outPath == pkgs.stdenv.cc.libc.outPath;
        message = "local-stt is built against a different glibc than the system; fix tools/stt-benchmark/pkgs.nix";
      }
    ];
    systemd.services.local-stt = {
      description = "Local GPU speech transcription";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      environment.STT_RECORDINGS = "/var/lib/local-stt";
      environment.XDG_CACHE_HOME = "/var/lib/local-stt/cache";
      # GPU sharing with llama-swap: unload the 10 GB final recogniser after
      # 30 min idle and lend the GPU to read-aloud's big voice (Higgs); when
      # dictation needs it back, evict llama-swap's models except the small
      # read-aloud summary model, which fits beside dictation (Erik, 2026-10-18;
      # was 5 h idle with no lending).
      environment.STT_FINAL_IDLE_SECONDS = "1800";
      environment.STT_LLAMA_SWAP_URL = "http://127.0.0.1:8000";
      environment.STT_LLAMA_SWAP_KEEP = "read-aloud-summary";
      environment.STT_IDLE_WARM_MODEL = "higgs-tts";
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
