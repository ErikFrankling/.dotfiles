{
  lib,
  config,
  pkgs,
  username,
  ...
}:
let
  package = import ../../tools/local-stt;
  workers = import ../../tools/local-stt/workers.nix;
  sttPkgs = import ../../tools/stt-benchmark/pkgs.nix;
  # llama-swap's service points LD_LIBRARY_PATH at llama.cpp's libggml; the
  # live recogniser links its own libggml.so.0 and would load the wrong one.
  # RADV_PERFTEST cleared too: the recognisers were measured without it.
  workerEnv = [
    "LD_LIBRARY_PATH="
    "RADV_PERFTEST="
  ];
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
      {
        assertion = config.services.llama-swap.enable;
        message = "local-stt runs its recognisers in llama-swap (modules/nixos/llama-swap.nix)";
      }
    ];

    # The two recognisers are llama-swap models, so one scheduler owns the
    # whole GPU (Erik, 2026-11-09; research/llama-swap/2026-11-07). Budgets
    # are in the vram pool of modules/nixos/llama-swap.nix (MiB).
    services.llama-swap.settings = {
      models = {
        # Nemotron streaming, the live draft: 1.16 GiB resident. Fits beside
        # every other model, so it stays loaded; an open recording's
        # WebSocket counts as an active request.
        "dictation-preview" = {
          name = "Nemotron streaming (dictation live draft)";
          unlisted = true;
          cmd = workers.previewCommand;
          proxy = "http://127.0.0.1:${toString workers.previewPort}";
          checkEndpoint = "/v1/models";
          env = workerEnv;
          capacities.vram = 1280;
          evict_cost = 100;
        };
        # VibeVoice ASR Q8, the final transcript: 9.2 GiB loaded, ~11 GiB
        # at the peak of a seven-minute window. Unloads after 30 minutes
        # idle; the gateway then lends the GPU to read-aloud's big voice.
        "dictation-final" = {
          name = "VibeVoice ASR (dictation final transcript)";
          unlisted = true;
          cmd = workers.finalCommand;
          proxy = "http://127.0.0.1:${toString workers.finalPort}";
          checkEndpoint = "/v1/models";
          env = workerEnv;
          capacities.vram = 11264;
          evict_cost = 20;
          ttl = 1800;
        };
      };
      # Speech jumps the queue when its model has to wait for room.
      routing.scheduler.settings.fifo.priority = {
        "dictation-preview" = 100;
        "dictation-final" = 100;
      };
      hooks.on_startup.preload = [ "dictation-preview" ];
    };

    # The recording coordinator: stores audio, streams drafts, produces final
    # transcripts and retries them. It runs no model itself and needs no GPU.
    systemd.services.local-stt = {
      description = "Local dictation recording coordinator";
      wantedBy = [ "multi-user.target" ];
      after = [
        "network.target"
        "llama-swap.service"
      ];
      environment.STT_RECORDINGS = "/var/lib/local-stt";
      environment.STT_LLAMA_SWAP_URL = "http://127.0.0.1:${toString config.services.llama-swap.port}";
      # After 30 minutes without dictation, lend the GPU to read-aloud's big
      # voice (Higgs), unless llama-swap runs something besides the small
      # read-aloud summary model (Erik, 2026-10-18).
      environment.STT_FINAL_IDLE_SECONDS = "1800";
      environment.STT_LLAMA_SWAP_KEEP = "read-aloud-summary";
      environment.STT_IDLE_WARM_MODEL = "higgs-tts";
      serviceConfig = {
        ExecStart = "${package}/bin/local-stt-server";
        User = username;
        StateDirectory = "local-stt";
        StateDirectoryMode = "0700";
        UMask = "0077";
        Restart = "on-failure";
        RestartSec = 5;
        TimeoutStopSec = 15;
        KillMode = "control-group";
        MemoryHigh = "1G";
        MemoryMax = "2G";
        MemorySwapMax = "256M";
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = "read-only";
        PrivateTmp = true;
      };
    };
  };
}
