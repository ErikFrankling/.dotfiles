{
  pkgs,
  lib,
  # llama-cpp-vulkan,
  otherPkgs,
  ...
}:

let
  llama-cpp = pkgs.llama-cpp-vulkan;
  # llama-cpp = otherPkgs.pkgsStable.llama-cpp-vulkan;
  # llama-cpp = pkgs.llama-cpp-rocm;
  # llama-cpp = llama-cpp-vulkan;
in
{
  services.llama-swap = {
    enable = true;
    package = pkgs.llama-swap;
    listenAddress = "0.0.0.0";
    port = 8000;
    openFirewall = true;

    settings = {
      healthCheckTimeout = 300;
      logLevel = "debug";
      startPort = 5800;

      models = {
        "qwen3.8-27b" = {
          name = "Qwen3.8 27B UD-Q3_K_XL (vision)";
          description = "Qwen3.8-27B, Unsloth dynamic 3-bit + mmproj — native vision, fully on GPU, used by the time tracker";

          # Vision model: --mmproj loads the F16 vision encoder (~0.9GB VRAM).
          # Sampling per Qwen3.8 thinking-mode recommendation (temp 1.0, top-p
          # 0.95, top-k 20, min-p 0) — NOT the repeat-penalty settings the
          # older text models use.
          # Never run this family with --no-kv-offload on Vulkan
          # (ggml-org/llama.cpp#24519, immediate-EOS bug).
          #
          # UD-Q3_K_XL (13.4G) instead of IQ4_XS (15.7G) by Erik's explicit
          # call 2026-08-17: 4-bit + mmproj forced 5-7 layers onto the CPU,
          # which halves decode speed — dynamic 3-bit fully on GPU won over
          # 4-bit at half speed (exception recorded in AGENTS.md). KV is cheap
          # on this arch (16/64 layers hold KV, ~32KB/tok q8_0): 65536 ctx =
          # two 32k slots, so a 60-minute screenshot batch fits one slot.
          # IQ4_XS full offload @ 4096 measured 19.9GB (crash band).
          cmd = ''
            ${llama-cpp}/bin/llama-server \
            --port 5806 \
            --model /mnt/data/ai-models/llama-cpp/models/unsloth/Qwen3.8-27B-GGUF/Qwen3.8-27B-UD-Q3_K_XL.gguf \
            --mmproj /mnt/data/ai-models/llama-cpp/models/unsloth/Qwen3.8-27B-GGUF/mmproj-F16.gguf \
            --n-gpu-layers 999 \
            -ub 256 \
            -c 65536 \
            --sleep-idle-seconds 10800 \
            --flash-attn on \
            --cache-type-k q8_0 \
            --cache-type-v q8_0 \
            --alias qwen3.8-27b \
            --jinja \
            --reasoning on \
            --reasoning-budget 3072 \
            --cache-ram 0 \
            --parallel 2 \
            --temp 1.0 \
            --top-p 0.95 \
            --top-k 20 \
            --min-p 0
          '';

          proxy = "http://127.0.0.1:5806";
          ttl = 10800;
          # Server-side sampling enforcement. llama-server lets request-body
          # params silently override CLI flags, and greedy decoding
          # (temperature 0) is a documented endless-repetition failure mode
          # for Qwen thinking models — one client doing that burned a whole
          # completion budget inside <think>. Strip the sampling params so the
          # official thinking-mode values above always win.
          filters = {
            stripParams = "temperature, top_p, top_k, min_p";
          };
          aliases = [
            "qwen3.8"
            # Stable names the time server's config points at. Both resolve to
            # this one model on purpose: llama-swap would otherwise thrash
            # loading two 15GB models as text and vision batches alternate.
            "time-vision"
            "time-text"
          ];
        };

        "qwen3.5-27b" = {
          name = "Qwen3.5 27B IQ4_NL";
          description = "Qwen3.5 27B with Unsloth IQ4_NL quantization";

          cmd = ''
            ${llama-cpp}/bin/llama-server \
            --port 5800 \
            --model /mnt/data/ai-models/llama-cpp/models/unsloth/Qwen3.5-27B-GGUF/Qwen3.5-27B-IQ4_NL.gguf \
            --n-gpu-layers 999 \
            -c 131072 \
            --sleep-idle-seconds 10800 \
            --flash-attn on \
            --cache-type-k q8_0 \
            --cache-type-v q8_0 \
            --alias qwen3.5-27b \
            --jinja \
            --reasoning on \
            --cache-ram 0 \
            --parallel 1 \
            --repeat-penalty 1.1 \
            --repeat-last-n 64
          '';

          proxy = "http://127.0.0.1:5800";
          ttl = 10800;
          aliases = [
            "qwen"
            "qwen3.5"
          ];
        };

        "qwen3.5-opus" = {
          name = "Qwen3.5 27B Claude 4.6 Opus Reasoning Distilled";
          description = "Qwen3.5-27B distilled from Claude 4.6 Opus - Q4_K_S imatrix quant";

          # --model /mnt/data/ai-models/llama-cpp/models/mradermacher/Qwen3.5-27B-Claude-4.6-Opus-Reasoning-Distilled-i1-GGUF/Qwen3.5-27B-Claude-4.6-Opus-Reasoning-Distilled.i1-IQ4_XS.gguf \
          cmd = ''
            ${llama-cpp}/bin/llama-server \
            --port 5802 \
            --model /mnt/data/ai-models/llama-cpp/models/mradermacher/Qwen3.5-27B-Claude-4.6-Opus-Reasoning-Distilled-i1-GGUF/Qwen3.5-27B-Claude-4.6-Opus-Reasoning-Distilled-heretic-v2.i1-Q4_K_S.gguf \
            --n-gpu-layers 999 \
            -c 131072 \
            --sleep-idle-seconds 10800 \
            --flash-attn on \
            --cache-type-k q8_0 \
            --cache-type-v q8_0 \
            --alias qwen3.5-opus \
            --jinja \
            --reasoning on \
            --cache-ram 0 \
            --parallel 1 \
            --repeat-penalty 1.1 \
            --repeat-last-n 64
          '';

          proxy = "http://127.0.0.1:5802";
          ttl = 10800;
          aliases = [
            "opus"
            "qwopus"
          ];
        };

        "qwen3.5-a3b" = {
          name = "Qwen3.5 35B A3B MoE UD-IQ4_NL";
          description = "Qwen3.5-35B-A3B MoE with Unsloth UD-IQ4_NL (17.8GB) - 3B active params";

          cmd = ''
            ${llama-cpp}/bin/llama-server \
            --port 5803 \
            --model /mnt/data/ai-models/llama-cpp/models/unsloth/Qwen3.5-35B-A3B-GGUF/Qwen3.5-35B-A3B-UD-IQ4_NL.gguf \
            --n-gpu-layers 999 \
            -c 131072 \
            --fit off \
            --sleep-idle-seconds 10800 \
            --flash-attn on \
            --cache-type-k q8_0 \
            --cache-type-v q8_0 \
            --alias qwen3.5-a3b \
            --jinja \
            --reasoning on \
            --cache-ram 0 \
            --parallel 1 \
            --repeat-penalty 1.1 \
            --repeat-last-n 64
          '';

          proxy = "http://127.0.0.1:5803";
          ttl = 10800;
          aliases = [
            "a3b"
            "moe"
            "qwen-moe"
          ];
        };
      };
    };
  };

  systemd.services.llama-swap = {
    after = [ "mnt-data.mount" ];
    requires = [ "mnt-data.mount" ];

    environment = {
      LD_LIBRARY_PATH = "${llama-cpp}/lib";
      GGML_VK_VISIBLE_DEVICES = "0";
      RADV_PERFTEST = "bfloat16,nogttspill";
    };

    serviceConfig = {
      DynamicUser = lib.mkForce false;
      PrivateUsers = lib.mkForce false;
      User = "llama-cpp";
      Group = "llama-cpp";
      WorkingDirectory = lib.mkForce "/mnt/data/ai-models/llama-cpp";
      SupplementaryGroups = [
        "video"
        "render"
      ];
      DevicePolicy = lib.mkForce "closed";
      DeviceAllow = [ "char-drm" ];
      LimitMEMLOCK = "infinity";
      OOMScoreAdjust = 900;
      MemoryDenyWriteExecute = lib.mkForce false;
      ProcSubset = lib.mkForce "all";
      ProtectProc = lib.mkForce "default";
    };
  };

  systemd.tmpfiles.rules = [
    "d /mnt/data/ai-models/llama-cpp/models 0770 llama-cpp llama-cpp -"
    "d /mnt/data/ai-models/llama-cpp/.cache 0770 llama-cpp llama-cpp -"
  ];

  users.users.llama-cpp = {
    isSystemUser = true;
    group = "llama-cpp";
    extraGroups = [
      "video"
      "render"
      "users"
    ];
    home = "/mnt/data/ai-models/llama-cpp";
    createHome = true;
  };

  users.groups.llama-cpp.members = [ "erikf" ];

  environment.systemPackages = with pkgs; [
    rocmPackages.rocm-smi
    nvtopPackages.amd
    python3Packages.huggingface-hub
  ];

  hardware.graphics.enable = true;
  boot.kernelModules = [ "amdgpu" ];
}
