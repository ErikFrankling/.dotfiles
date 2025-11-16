{ username, pkgs, ... }:
let
  # --- 1. Model Configuration ---
  #
  # This is the directory where the service will look for your model.
  modelDir = "/var/lib/llama-models";

  # *** CRITICAL: MANUAL DOWNLOAD REQUIRED ***
  #
  # The service needs the GGUF model file. Your vllm config used the
  # 'unsloth/Qwen3-30B-A3B-Thinking-2507-GGUF' repository, which pointed to
  # the 'unsloth/Qwen3-30B-A3B-GGUF' repo for the files.
  #
  # Based on your 20GB GPU, the Q4_K_M (18.6GB) quant is the perfect fit.
  #
  # Please download this *exact file* from Hugging Face:
  # https://huggingface.co/unsloth/Qwen3-30B-A3B-GGUF/blob/main/Qwen3-30B-A3B-Q4_K_M.gguf
  #
  # And place it at this exact path:
  # /var/lib/llama-models/Qwen3-30B-A3B-Q4_K_M.gguf
  #
  # You can use these commands:
  # sudo mkdir -p /var/lib/llama-models
  # sudo wget -O /var/lib/llama-models/Qwen3-30B-A3B-Q4_K_M.gguf https://huggingface.co/unsloth/Qwen3-30B-A3B-GGUF/resolve/main/Qwen3-30B-A3B-Q4_K_M.gguf
  # sudo chown llama:llama /var/lib/llama-models/Qwen3-30B-A3B-Q4_K_M.gguf
  #
  # modelFileName = "Qwen3-30B-A3B-Q4_K_M.gguf";
  modelFileName = "Qwen3-Coder-30B-A3B-Instruct-Q4_K_M.gguf";
  modelAlias = "qwen3-coder-30B-a3b";

  modelPath = "${modelDir}/${modelFileName}";

  # llama-cpp-vulkan-pkg = (pkgs.llama-cpp.override { vulkanSupport = true; });
in
{
  # --- 3. Firewall ---
  # Open the port for the API server, as you had.
  networking.firewall.allowedTCPPorts = [ 8000 ];

  # --- 4. Host GPU Configuration ---
  # Ensures the host system has the necessary ROCm drivers
  # and kernel modules loaded. This is safer than the container.
  hardware.opengl.enable = true;

  boot.kernelModules = [ "amdgpu" ];
  environment.systemPackages = with pkgs; [
    rocmPackages.rocm-smi
    llama-cpp-vulkan
    # llama-cpp-vulkan-pkg
  ];

  # --- 5. Secure User for the Service ---
  # We create a dedicated, unprivileged user to run the server.
  # This is much safer than using root.
  users.users.llama = {
    isSystemUser = true;
    group = "llama";
    # Add user to the 'video' and 'render' groups for GPU access
    extraGroups = [
      "video"
      "render"
    ];
  };
  users.groups.llama = { };

  # --- 6. Model Directory Creation ---
  # Creates the /var/lib/llama-models directory via systemd.
  systemd.tmpfiles.rules = [
    "d ${modelDir} 0750 llama llama -"
  ];

  # --- 7. llama.cpp systemd Service ---
  # systemd.services.llama-cpp-server = {
  #   description = "llama.cpp OpenAI-compatible API server";
  #   wantedBy = [ "multi-user.target" ];
  #   after = [
  #     "network.target"
  #     "systemd-tmpfiles-setup.service"
  #   ];
  #
  #   # This ensures the model directory is created before starting
  #   requires = [ "systemd-tmpfiles-setup.service" ];
  #
  #   serviceConfig = {
  #     Type = "simple";
  #     User = "llama";
  #     Group = "llama";
  #
  #     # Only for rocm
  #     # Environment = "HSA_OVERRIDE_GFX_VERSION=11.0.0";
  #
  #     # ${llama-cpp-vulkan-pkg}/bin/llama-server \
  #     # max context 262144
  #     # min context  32768
  #     ExecStart = ''
  #       ${pkgs.llama-cpp-vulkan}/bin/llama-server \
  #         -m "${modelPath}" \
  #         --alias "${modelAlias}" \
  #         --host 0.0.0.0 \
  #         --port 8000 \
  #         -c 262144 \
  #         --n-gpu-layers 999 \
  #         --no-kv-offload \
  #         --jinja \
  #         # --hugging-face \
  #         # --verbose
  #     '';
  #
  #     # Restart policy
  #     Restart = "always";
  #     RestartSec = 10;
  #
  #     # Explicitly grant the service access to the AMD GPU devices for ROCm
  #     # DeviceAllow = [
  #     #   "/dev/kfd rw"
  #     #   "/dev/dri/ rw"
  #     # ];
  #     # DeviceAllow = [
  #     #   "/dev/dri/ rw"
  #     # ];
  #   };
  # };

  # 1. Enable OCI containers (Podman recommended for rootless)
  # virtualisation.oci-containers = {
  #   backend = "podman"; # or "docker" if you prefer
  #
  #   containers.qwen3-vllm = {
  #     # 2. Use ROCm-enabled vLLM image
  #     image = "rocm/vllm-dev:nightly";
  #
  #     # 3. Auto-start and persist
  #     autoStart = true;
  #     autoRemoveOnStop = false;
  #
  #     # 4. AMD GPU passthrough (CRITICAL for ROCm)
  #     devices = [
  #       "/dev/kfd:/dev/kfd" # ROCm kernel fusion driver
  #       "/dev/dri:/dev/dri" # Direct Rendering Infrastructure
  #     ];
  #
  #     # 5. Environment variables for AMD stability
  #     environment = {
  #       HSA_NO_SIMD_DISPATCH = "1";
  #       PYTORCH_ALLOC_CONF = "garbage_collection_threshold:0.8,max_split_size_mb:128";
  #       HSA_OVERRIDE_GFX_VERSION = "11.0.0"; # For 7900 XTX (gfx1100)
  #       HF_HOME = "/root/.cache/huggingface";
  #       # Optional: Enable flash attention if supported
  #       # VLLM_FLASH_ATTN_BACKEND = "ROCM_FLASH";
  #     };
  #
  #     # 6. vLLM command with OpenAI-compatible API
  #     cmd = [
  #       # Use the 'vllm' executable
  #       "vllm"
  #       "serve"
  #
  #       # 1. Use the GPTQ quantized model you found
  #       "unsloth/Qwen3-30B-A3B-Thinking-2507-GGUF"
  #
  #       # "--reasoning-parser deepseek_r1"
  #
  #       # 2. All other arguments come after
  #       "--host"
  #       "0.0.0.0"
  #       "--port"
  #       "8000"
  #       "--trust-remote-code"
  #
  #       # 3. Specify the correct quantization type
  #       "--quantization"
  #       "gptq"
  #
  #       # GPU CONFIG
  #       "--tensor-parallel-size"
  #       "1"
  #       "--gpu-memory-utilization"
  #       "0.85" # Lowered from 0.95 to leave headroom for torch.compile
  #
  #       # MAX CONTEXT:
  #       "--max-model-len"
  #       "32768"
  #       "--max-num-batched-tokens"
  #       "32768"
  #
  #       # PERFORMANCE:
  #       "--enable-chunked-prefill"
  #       "--distributed-executor-backend"
  #       "mp"
  #
  #       # Optional:
  #       "--swap-space"
  #       "4"
  #     ];
  #
  #     # 7. Local-only API access
  #     ports = [
  #       "127.0.0.1:8000:8000"
  #       # If you want to access it from other machines on your network, use:
  #       # "0.0.0.0:8000:8000"
  #       # But your firewall (8090) doesn't match this.
  #       # For now, 127.0.0.1 (localhost) is safest.
  #     ];
  #
  #     # 8. Model cache volume (avoids re-download)
  #     volumes = [
  #       "/var/lib/vllm-models:/root/.cache/huggingface"
  #       # Optional: Mount local model if downloaded manually
  #       # "/path/to/model:/model"
  #     ];
  #
  #     # 9. System settings
  #     extraOptions = [
  #       "--shm-size"
  #       "24g" # Increase shared memory for ROCm
  #       "--security-opt"
  #       "no-new-privileges:true"
  #     ];
  #
  #     # 10. Logging
  #     log-driver = "journald";
  #
  #     # 11. Run as root for GPU access (or configure rootless)
  #     podman = {
  #       user = "root";
  #     };
  #   };
  # };
  #
  # # 12. Create model cache directory
  # systemd.tmpfiles.rules = [
  #   "d /var/lib/vllm-models 0755 root root -"
  # ];
  #
  # # 13. Host system prerequisites
  # hardware = {
  #   opengl = {
  #     enable = true;
  #     driSupport32Bit = true;
  #   };
  #   # Optional: Enable ROCm on host for development
  #   # rocm.enable = true;
  # };
  #
  # # 14. Kernel modules for AMD GPU
  # boot.kernelModules = [
  #   "amdgpu"
  #   "kvm-amd"
  # ];

  # 15. Optional: Add ROCm utilities to environment
  # environment.systemPackages = with pkgs; [
  #   rocmPackages.rocm-smi # For GPU monitoring
  # ];

  # virtualisation.oci-containers = {
  #   backend = "docker"; # required because ROCm image uses Docker tooling
  #   containers.vllm-qwen = {
  #     autoStart = true;
  #     image = "rocm/vllm:latest";
  #     pull = "always";
  #     cmd = [
  #       "vllm"
  #       "serve"
  #       "QuantFactory/Qwen3-30B-AWQ" # replace with actual AWQ repo/model name
  #       "--quantization"
  #       "awq"
  #       "--dtype"
  #       "half"
  #       "--host"
  #       "0.0.0.0"
  #       "--port"
  #       "8000"
  #       "--gpu-memory-utilization"
  #       "0.95"
  #       "--max-model-len"
  #       "32768"
  #       "--max-num-seqs"
  #       "1"
  #       "--swap-space"
  #       "0"
  #       "--trust-remote-code"
  #     ];
  #     devices = [
  #       "/dev/kfd"
  #       "/dev/dri"
  #     ];
  #     environment = {
  #       VLLM_USE_TRITON_AWQ = "1"; # enables AWQ in ROCm build
  #       HUGGINGFACE_HUB_CACHE = "/root/.cache/huggingface";
  #     };
  #     volumes = [
  #       "/home/USERNAME/.cache/huggingface:/root/.cache/huggingface"
  #     ];
  #     ports = [ "8000:8000" ];
  #     extraOptions = [
  #       "--group-add=video"
  #       "--ipc=host"
  #       "--cap-add=SYS_PTRACE"
  #       "--security-opt=seccomp=unconfined"
  #     ];
  #     restart = "always";
  #   };
  # };
  #
  # # Ensure Docker service is active
  # virtualisation.docker.enable = true;
  # users.extraGroups.video.members = [ username ];
}
