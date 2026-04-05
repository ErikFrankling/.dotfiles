{ pkgs, lib, llama-cpp-vulkan, ... }:

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
        "qwen3.5-27b" = {
          name = "Qwen3.5 27B IQ4_NL";
          description = "Qwen3.5 27B with Unsloth IQ4_NL quantization";

          cmd = ''
            ${pkgs.llama-cpp-vulkan}/bin/llama-server \
            --port 5800 \
            --model /var/lib/llama-cpp/models/unsloth/Qwen3.5-27B-GGUF/Qwen3.5-27B-IQ4_NL.gguf \
            --n-gpu-layers 999 \
            -c 4096 \
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
          aliases = [ "qwen" "qwen3.5" ];
        };

        "gemma4-26b" = {
          name = "Gemma 4 26B A4B IT IQ2_XXS";
          description = "Gemma 4 26B with Unsloth 2-bit IQ2_XXS quantization (9.3GB)";

          cmd = ''
            ${llama-cpp-vulkan}/bin/llama-server \
            --port 5802 \
            --model /var/lib/llama-cpp/models/unsloth/gemma-4-26B-A4B-it-GGUF/gemma-4-26B-A4B-it-UD-IQ2_XXS.gguf \
            --n-gpu-layers 999 \
            -c 4096 \
            --fit off \
            --flash-attn on \
            --cache-type-k q8_0 \
            --cache-type-v q8_0 \
            --alias gemma4-26b \
            --jinja \
            --parallel 1 \
            --repeat-penalty 1.1 \
            --repeat-last-n 64
          '';

          # env vars for custom llama-cpp with gemma4 support
          proxy = "http://127.0.0.1:5802";
          ttl = 10800;
          aliases = [ "gemma" "gemma4" ];

          env = [
            "LD_LIBRARY_PATH=${llama-cpp-vulkan}/lib"
            "GGML_VK_VISIBLE_DEVICES=0"
            "XDG_CACHE_HOME=/var/lib/llama-cpp/.cache"
            "RADV_PERFTEST=bfloat16,nogttspill"
          ];
        };
      };
    };
  };

  systemd.services.llama-swap = {
    environment = {
      LD_LIBRARY_PATH = "${llama-cpp-vulkan}/lib";
      GGML_VK_VISIBLE_DEVICES = "0";
      XDG_CACHE_HOME = "/var/lib/llama-cpp/.cache";
      RADV_PERFTEST = "bfloat16,nogttspill";
    };

    serviceConfig = {
      DynamicUser = lib.mkForce false;
      PrivateUsers = lib.mkForce false;
      User = "llama-cpp";
      Group = "llama-cpp";
      WorkingDirectory = lib.mkForce "/var/lib/llama-cpp";
      SupplementaryGroups = [ "video" "render" ];
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
    "d /var/lib/llama-cpp/models 0770 llama-cpp llama-cpp -"
    "d /var/lib/llama-cpp/.cache 0770 llama-cpp llama-cpp -"
  ];

  users.users.llama-cpp = {
    isSystemUser = true;
    group = "llama-cpp";
    extraGroups = [ "video" "render" ];
    home = "/var/lib/llama-cpp";
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