# =============================================================================
# llama.cpp Server — AMD RX 7900 XT (gfx1100, 20GB VRAM)
# =============================================================================
#
# This module runs llama-server as a systemd service accessible on the LAN.
# It uses ROCm/HIP for full GPU acceleration (no CPU offloading ever).
# Key: --no-mmap is required to avoid ROCm page faults (mmap↔HIP address collision).
#
# HOW TO ADD A NEW MODEL
# ─────────────────────
# 1. Download a .gguf file into /var/lib/llama-cpp/models/
#
#    Example (single file):
#      sudo -u llama-cpp huggingface-cli download \
#        bartowski/SomeModel-GGUF \
#        --include "SomeModel-Q4_K_M.gguf" \
#        --local-dir /var/lib/llama-cpp/models/
#
#    Fix perms if needed:
#      sudo chown -R llama-cpp:llama-cpp /var/lib/llama-cpp/models/
#
# 2. Update the `model` option below to point to the new .gguf file path.
#    Or switch to `modelsDir` (comment out `model`, uncomment `modelsDir`)
#    to expose all .gguf files in the directory — clients then pick the
#    model by name via the API.
#
# 3. Run: nh os switch
#    The service auto-restarts and loads the new model.
#
# QUANTIZATION GUIDE (RX 7900 XT — 20GB VRAM)
# ────────────────────────────────────────────
# For a ~27B dense model:
#   Q5_K_M ≈ 20 GB  — max quality, very tight, may OOM with large context
#   Q4_K_M ≈ 17 GB  — recommended: good quality + headroom for KV cache
#   Q3_K_M ≈ 14 GB  — smaller, lower quality, lots of headroom
#
# For MoE models (e.g. 30B-A3B style, only 3B active):
#   Q4_K_M ≈ 18-19 GB — fits, much faster inference than dense 27B
#
# CURRENT MODEL: Qwen3.5-27B UD-Q4_K_XL (Unsloth Dynamic 2.0)
# ─────────────────────────────────────────────────────────────
# UD (Unsloth Dynamic) quants outperform standard K-quants at the same size
# by assigning more bits to important layers.
#
# Download:
#   sudo nix run nixpkgs#python3Packages.huggingface-hub -- download \
#     unsloth/Qwen3.5-27B-GGUF \
#     --include "Qwen3.5-27B-UD-Q4_K_XL.gguf" \
#     --local-dir /var/lib/llama-cpp/models/
#   sudo chown -R llama-cpp:llama-cpp /var/lib/llama-cpp/models/
#
# Use download command from here: https://unsloth.ai/docs/models/qwen3.5#qwen3.5-27b
#
# sudo nix run nixpkgs#python3Packages.huggingface-hub -- download \
#     unsloth/Qwen3.5-27B-GGUF \
#     --local-dir /var/lib/llama-cpp/models/unsloth/Qwen3.5-27B-GGUF \
#     --include "*mmproj-F16*" \
#     --include "*UD-Q4_K_XL*"
#
# IQ is not supported on ROCm yet
# sudo nix run nixpkgs#python3Packages.huggingface-hub -- download \
#     unsloth/Qwen3.5-27B-GGUF \
#     --local-dir /var/lib/llama-cpp/models/unsloth/Qwen3.5-27B-GGUF \
#     --include "*mmproj-F16*" \
#     --include "*IQ4_NL*"
#
# sudo nix run nixpkgs#python3Packages.huggingface-hub -- download \
#     unsloth/Qwen3.5-27B-GGUF \
#     --local-dir /var/lib/llama-cpp/models/unsloth/Qwen3.5-27B-GGUF \
#     --include "*mmproj-F16*" \
#     --include "*UD-Q3_K_XL*"
#
# sudo nix run nixpkgs#python3Packages.huggingface-hub -- download \
#     unsloth/Qwen3.5-27B-GGUF \
#     --local-dir /var/lib/llama-cpp/models/unsloth/Qwen3.5-27B-GGUF \
#     --include "*mmproj-F16*" \
#     --include "*Q4_K_M*"

{
  pkgs,
  lib,
  inputs,
  ...
}:

{
  networking.firewall.allowedTCPPorts = [ 8000 ];

  hardware.graphics.enable = true;
  boot.kernelModules = [ "amdgpu" ];

  environment.systemPackages = with pkgs; [
    rocmPackages.rocm-smi # GPU monitoring: rocm-smi
    nvtopPackages.amd # GPU usage: nvtop
    python3Packages.huggingface-hub # model download: huggingface-cli download ...
  ];

  # nixpkgs.overlays = [ inputs.llamacpp-rocm.overlays.default ];

  services.llama-cpp =
    # let
    #   llama-cpp-rocm-wmma = pkgs.llama-cpp-rocm.overrideAttrs (prev: {
    #     buildInputs = prev.buildInputs ++ [ pkgs.rocmPackages.rocwmma ];
    #     cmakeFlags = prev.cmakeFlags ++ [
    #       "-DGGML_HIP_ROCWMMA_FATTN=ON"
    #       "-DCMAKE_HIP_FLAGS=-I${pkgs.rocmPackages.rocwmma}/include"
    #       "-DGGML_CUDA_FA_ALL_QUANTS=ON"
    #     ];
    #   });
    # in
    {
      enable = true;
      # llama-cpp-rocm: ROCm/HIP GPU acceleration for AMD RDNA3
      # package = pkgs.llama-cpp-rocm;

      # For Vulkan backend
      package = pkgs.llama-cpp-vulkan;

      # Adds rocwmma flag when compiling for better fa stuff. no worky
      # package = pkgs.llamacpp-rocm."gfx1151-rocwmma";
      # package = llama-cpp-rocm-wmma;

      # Single-model mode: point directly to a .gguf file
      # To serve multiple models, comment out `model` and use:
      #   modelsDir = "/var/lib/llama-cpp/models";
      # model = "/var/lib/llama-cpp/models/unsloth/Qwen3.5-27B-GGUF/Qwen3.5-27B-UD-Q3_K_XL.gguf";
      # model = "/var/lib/llama-cpp/models/unsloth/Qwen3.5-27B-GGUF/Qwen3.5-27B-Q4_K_M.gguf";
      # model = "/var/lib/llama-cpp/models/unsloth/Qwen3.5-27B-GGUF/Qwen3.5-27B-UD-Q4_K_XL.gguf";
      model = "/var/lib/llama-cpp/models/unsloth/Qwen3.5-27B-GGUF/Qwen3.5-27B-IQ4_NL.gguf";
      # model = "/var/lib/llama-cpp/models/Qwen3.5-27B-UD-Q4_K_XL.gguf";

      host = "0.0.0.0"; # bind to all interfaces — accessible on LAN
      port = 8000;
      openFirewall = false; # managed manually above

      extraFlags = [
        # ── GPU ──────────────────────────────────────────────────────────────
        # Offload ALL transformer layers to GPU. Never touch CPU.
        # 999 = "more than any model will ever have" = all layers.
        "--n-gpu-layers"
        "999"

        # forces only gpu vram
        # "-fit"
        # "off"

        # ── Context window ────────────────────────────────────────────────────
        # 65536 = 64k tokens. Increase to 131072 for 128k (needs more VRAM).
        # Reduce if you hit OOM errors on load.
        "-c"
        # "262144"
        "131072"
        # "65536"
        # "32768"
        # "4096"

        # ── Idle model unload ─────────────────────────────────────────────────
        # Unload model weights from GPU VRAM after 1 hour (3600s) of no requests.
        # The model reloads automatically on the next request.
        # This frees the GPU for gaming/other use when the server is idle.
        "--sleep-idle-seconds"
        # "3600"
        "600"

        # ── Performance ───────────────────────────────────────────────────────
        # FA must be forced on (not auto) for quantized cache to work
        "--flash-attn"
        "on"
        # "off"
        "--cache-type-k"
        "q8_0"
        "--cache-type-v"
        # "q4_0"
        "q8_0"

        # ── API ───────────────────────────────────────────────────────────────
        "--alias"
        "qwen3.5-27b" # model name clients use in API requests
        "--jinja" # enable jinja2 chat template support

        # Thinking: enable for faster token generation (all fast runs had thinking=1)
        # Old method (deprecated but used in fast runs):
        # "--chat-template-kwargs"
        # ''{"enable_thinking":true}''
        # New method:
        # "--reasoning"
        # "off"
        # Enable thinking:
        "--reasoning"
        "on"

        # ── Prompt cache ──────────────────────────────────────────────────────────
        # does not work with this model currently fails with a error but still uses the ram space
        # Disable prompt cache:
        "--cache-ram"
        "0"

        # ── Vison ─────────────────────────────────────────────────────────────
        # "--mmproj"
        # "/var/lib/llama-cpp/models/unsloth/Qwen3.5-27B-GGUF/mmproj-F16.gguf"

        # ── Memory mapping ────────────────────────────────────────────────────
        # --no-mmap: disable mmap() for model weights.
        # Required for ROCm: mmap address space collides with HIP/GPU memory,
        # causing "Memory access fault by GPU node" page faults on model load.
        # "--no-mmap"

        # ── Concurrency ───────────────────────────────────────────────────────
        # Number of parallel request slots. 1 = sequential (safest for VRAM).
        # Increase to 2-4 if you have VRAM headroom.
        "--parallel"
        "1"

        # if you want parallel subagents
        # "--parallel"
        # "2"
        # "--kv-unified"
        # "--cache-reuse"
        # "256"

        "--verbose-prompt"
      ];
    };

  # Override the nixpkgs module's hardening settings for ROCm GPU access.
  # DynamicUser + PrivateUsers breaks stable model directory ownership.
  # systemd.services.llama-cpp = {
  #   # Wait for /dev/kfd (ROCm compute device) to be ready before starting.
  #   after = [ "dev-kfd.device" ];
  #   wants = [ "dev-kfd.device" ];
  #   environment = {
  #     # Required for gfx1100 (RX 7900 XT) — ROCm doesn't auto-detect RDNA3
  #     HSA_OVERRIDE_GFX_VERSION = "11.0.0";
  #     ROC_ENABLE_PRE_VEGA = "1";
  #     # Use only the dedicated GPU (device 0 = RX 7900 XT).
  #     HIP_VISIBLE_DEVICES = "0";
  #     CUDA_VISIBLE_DEVICES = "0";
  #
  #     ROCBLAS_USE_HIPBLASLT = "1";
  #
  #     # GGML_SCHED_DEBUG = "2";
  #     # LLAMA_LOG_LEVEL = "debug";
  #   };
  #   serviceConfig = {
  #     DynamicUser = lib.mkForce false;
  #     PrivateUsers = lib.mkForce false;
  #     User = "llama-cpp";
  #     Group = "llama-cpp";
  #     SupplementaryGroups = [
  #       "video"
  #       "render"
  #     ];
  #     # ROCm GPU access: KFD (compute) + DRM (display/render)
  #     DevicePolicy = lib.mkForce "closed";
  #     DeviceAllow = [
  #       "char-kfd" # ROCm Kernel Fusion Driver (HIP/compute)
  #       "char-drm" # Direct Rendering Infrastructure
  #     ];
  #     LimitMEMLOCK = "infinity";
  #
  #     # Highest OOM score = killed first if system runs out of RAM.
  #     # Hyprland and user session survive; llama-cpp is sacrificed.
  #     OOMScoreAdjust = 900;
  #
  #     # Restart on random failures, but stop looping after 3 crashes in 5 minutes.
  #     # To manually reset and retry: systemctl reset-failed llama-cpp && systemctl start llama-cpp
  #     Restart = lib.mkForce "on-failure";
  #     # Restart = lib.mkForce "no";
  #     # StartLimitBurst = 3;
  #
  #     # ROCm/HIP JIT-compiles GPU kernels at runtime — requires W+X memory mappings.
  #     # The nixpkgs module sets this to true which crashes HIP.
  #     MemoryDenyWriteExecute = lib.mkForce false;
  #
  #     # Allow ROCm to read /proc/meminfo for memory accounting.
  #     # nixpkgs module sets ProcSubset=pid which hides /proc/meminfo.
  #     ProcSubset = lib.mkForce "all";
  #     ProtectProc = lib.mkForce "default";
  #   };
  # };

  # For Vulkan
  systemd.services.llama-cpp = {
    environment = {
      GGML_VK_VISIBLE_DEVICES = "0"; # select the 7900 XT, not the iGPU

      XDG_CACHE_HOME = "/var/lib/llama-cpp/.cache"; # writable shader cache dir

      RADV_PERFTEST = "bfloat16,nogttspill";

      # GGML_SCHED_DEBUG = "2";
      # LLAMA_LOG_LEVEL = "debug";
    };
    serviceConfig = {
      DynamicUser = lib.mkForce false;
      PrivateUsers = lib.mkForce false;
      User = "llama-cpp";
      Group = "llama-cpp";
      SupplementaryGroups = [
        "video"
        "render"
      ];
      # ROCm GPU access: KFD (compute) + DRM (display/render)
      DevicePolicy = lib.mkForce "closed";
      DeviceAllow = [
        "char-drm" # Direct Rendering Infrastructure
      ];
      LimitMEMLOCK = "infinity";

      # Highest OOM score = killed first if system runs out of RAM.
      # Hyprland and user session survive; llama-cpp is sacrificed.
      OOMScoreAdjust = 900;

      # Restart on random failures, but stop looping after 3 crashes in 5 minutes.
      # To manually reset and retry: systemctl reset-failed llama-cpp && systemctl start llama-cpp
      Restart = lib.mkForce "on-failure";
      # Restart = lib.mkForce "no";
      # StartLimitBurst = 3;

      # ROCm/HIP JIT-compiles GPU kernels at runtime — requires W+X memory mappings.
      # The nixpkgs module sets this to true which crashes HIP.
      MemoryDenyWriteExecute = lib.mkForce false;

      # Allow ROCm to read /proc/meminfo for memory accounting.
      # nixpkgs module sets ProcSubset=pid which hides /proc/meminfo.
      ProcSubset = lib.mkForce "all";
      ProtectProc = lib.mkForce "default";
    };
  };

  users.users.llama-cpp = {
    isSystemUser = true;
    group = "llama-cpp";
    extraGroups = [
      "video"
      "render"
    ];
    home = "/var/lib/llama-cpp";
    createHome = true;
  };
  # llama-cpp group is shared — add your desktop user here so LM Studio
  # (and any other tool running as you) can read/write the models dir.
  users.groups.llama-cpp.members = [ "erikf" ];

  # 0770: llama-cpp user + group (erikf) can read/write, others cannot
  systemd.tmpfiles.rules = [
    "d /var/lib/llama-cpp/models 0770 llama-cpp llama-cpp -"
  ];
}
