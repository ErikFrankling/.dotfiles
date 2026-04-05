# =============================================================================
# llama.cpp Server - Multi-Model Router Configuration
# =============================================================================
#
# This module configures llama-server in router mode to serve multiple models
# with per-model settings (context size, KV cache compression, etc.).
# Models are selected at runtime via the OpenAI-compatible API's "model" field.
#
# HOW TO ADD A NEW MODEL
# ──────────────────────
# 1. Download .gguf file to /var/lib/llama-cpp/models/
#    sudo -u llama-cpp huggingface-cli download ... --local-dir /var/lib/llama-cpp/models/
#
# 2. Add entry to modelsPreset below with model-specific settings
#
# 3. Rebuild: nh os switch (service auto-restarts)
#
# Clients then select model via API: { "model": "your-model-alias" }

{ pkgs, lib, ... }:

{
  services.llama-cpp = {
    enable = true;

    # Vulkan backend for AMD RX 7900 XT
    package = pkgs.llama-cpp-vulkan;

    # ── Router Mode Configuration ────────────────────────────────────────
    # Single-model mode: set `model` to a path, leave modelsDir/modelsPreset null
    # Multi-model mode (router): set modelsDir and optionally modelsPreset
    model = null;  # Disable single-model mode

    # Directory containing all .gguf files - router serves all of them
    modelsDir = "/var/lib/llama-cpp/models";

    # Per-model configuration presets (converted to INI file automatically)
    # Each key becomes a [section] in the INI, passed via --models-preset
    modelsPreset = {
      "qwen3.5-27b" = {
        # Path to model file (required)
        path = "/var/lib/llama-cpp/models/unsloth/Qwen3.5-27B-GGUF/Qwen3.5-27B-IQ4_NL.gguf";

        # API name clients use to request this model
        alias = "qwen3.5-27b";

        # ── Sampling Parameters (supported in preset) ───────────────────
        temp = "1.0";
        repeat-penalty = "1.1";
        repeat-last-n = "64";
      };

      # ── Add New Models Here ────────────────────────────────────────────
      # Example templates for models you want to test:

      # Gemma 4 31B (adjust path and settings after downloading)
      # "gemma4-31b" = {
      #   path = "/var/lib/llama-cpp/models/gemma4-31b-Q4_K_M.gguf";
      #   alias = "gemma4-31b";
      #   n_gpu_layers = "999";
      #   n_ctx = "65536";  # Smaller context for larger model
      #   flash_attn = "on";
      #   cache_type_k = "q4_0";  # More aggressive compression
      #   cache_type_v = "q4_0";
      #   jinja = "on";
      # };

      # Gemma 4 26B (adjust path and settings after downloading)
      # "gemma4-26b" = {
      #   path = "/var/lib/llama-cpp/models/gemma4-26b-Q5_K_M.gguf";
      #   alias = "gemma4-26b";
      #   n_gpu_layers = "999";
      #   n_ctx = "32768";
      #   flash_attn = "on";
      #   cache_type_k = "q4_0";
      #   cache_type_v = "q4_0";
      #   jinja = "on";
      # };

      # Qwen 3.5 MoE small variant (adjust for your specific model)
      # "qwen-moe-small" = {
      #   path = "/var/lib/llama-cpp/models/qwen-moe-small.gguf";
      #   alias = "qwen-moe-small";
      #   n_gpu_layers = "999";
      #   n_ctx = "32768";
      #   flash_attn = "on";
      #   cache_type_k = "q8_0";  # MoE benefits from higher quality cache
      #   cache_type_v = "q8_0";
      #   jinja = "on";
      #   cpu_moe = "off";  # Keep expert weights on GPU for speed
      # };
    };

    # ── Global Flags (Apply to All Models) ──────────────────────────────
    extraFlags = [
      # Router server: limit concurrent loaded models to save VRAM
      "--models-max" "1"  # Load 1 model at a time, auto-swap on demand

      # Enable automatic model loading/unloading based on requests
      "--models-autoload"

      # ── GPU ───────────────────────────────────────────────────────────
      # Offload ALL transformer layers to GPU. Never touch CPU.
      # 999 = "more than any model will ever have" = all layers.
      "--n-gpu-layers"
      "999"

      # ── Context window ────────────────────────────────────────────────
      # 131072 = 128k tokens.
      "-c"
      "131072"

      # ── Idle model unload ─────────────────────────────────────────────
      # Unload model weights from GPU VRAM after 3h of no requests.
      "--sleep-idle-seconds"
      "10800"  # 3h

      # ── Performance ───────────────────────────────────────────────────
      # FA must be forced on (not auto) for quantized cache to work
      "--flash-attn"
      "on"
      "--cache-type-k"
      "q8_0"
      "--cache-type-v"
      "q8_0"

      # ── API ───────────────────────────────────────────────────────────
      "--jinja"  # enable jinja2 chat template support

      # Enable reasoning/thinking mode
      "--reasoning"
      "on"

      # ── Prompt cache ──────────────────────────────────────────────────
      # Disabled: causes errors with this model but still consumes RAM
      "--cache-ram"
      "0"

      # ── Concurrency ───────────────────────────────────────────────────
      # Number of parallel request slots. 1 = sequential (safest for VRAM).
      "--parallel"
      "1"

      # Verbose prompt logging (helpful for debugging)
      "--verbose-prompt"
    ];

    # ── Network Configuration ────────────────────────────────────────────
    host = "0.0.0.0";  # Bind to all interfaces - accessible on LAN
    port = 8000;
    openFirewall = false;  # Firewall managed manually below
  };

  # Allow connections from LAN clients
  networking.firewall.allowedTCPPorts = [ 8000 ];

  # ── Vulkan-Specific Systemd Override ──────────────────────────────────
  # Required for AMD GPU access and shader compilation (W+X memory)
  systemd.services.llama-cpp = {
    environment = {
      GGML_VK_VISIBLE_DEVICES = "0";  # Select RX 7900 XT, not integrated GPU

      XDG_CACHE_HOME = "/var/lib/llama-cpp/.cache";  # Writable shader cache directory

      RADV_PERFTEST = "bfloat16,nogttspill";  # Vulkan performance optimizations

      # Debug options (uncomment for troubleshooting):
      # GGML_SCHED_DEBUG = "2";
      # LLAMA_LOG_LEVEL = "debug";
    };

    serviceConfig = {
      # Use static user instead of DynamicUser for stable directory ownership
      DynamicUser = lib.mkForce false;
      PrivateUsers = lib.mkForce false;
      User = "llama-cpp";
      Group = "llama-cpp";
      SupplementaryGroups = [
        "video"  # GPU device access
        "render" # DRM/render node access
      ];

      # Device access for Vulkan GPU
      DevicePolicy = lib.mkForce "closed";
      DeviceAllow = [
        "char-drm"  # Direct Rendering Infrastructure (Vulkan)
      ];

      # Memory settings
      LimitMEMLOCK = "infinity";  # Allow mlock() for keeping model in RAM

      # OOM killer: sacrifice this service before user session
      OOMScoreAdjust = 900;

      # Restart policy on failure
      Restart = lib.mkForce "on-failure";

      # CRITICAL: Vulkan shader JIT compilation requires W+X memory mappings
      MemoryDenyWriteExecute = lib.mkForce false;

      # Allow /proc/meminfo access for memory accounting
      ProcSubset = lib.mkForce "all";
      ProtectProc = lib.mkForce "default";
    };
  };

  # ── User/Group Configuration ──────────────────────────────────────────
  # System user to run llama-cpp service and own model files
  users.users.llama-cpp = {
    isSystemUser = true;
    group = "llama-cpp";
    extraGroups = [
      "video"  # GPU device access
      "render" # DRM/render node access
    ];
    home = "/var/lib/llama-cpp";
    createHome = true;
  };

  # Add your user to llama-cpp group for model directory read/write access
  users.groups.llama-cpp.members = [ "erikf" ];

  # ── Model Directory Permissions ───────────────────────────────────────
  # 0770: llama-cpp user + group members (including erikf) can read/write
  systemd.tmpfiles.rules = [
    "d /var/lib/llama-cpp/models 0770 llama-cpp llama-cpp -"
  ];
}
