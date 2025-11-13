{
  pkgs,
  otherPkgs,
  lib,
  ...
}:

{
  imports = [
  ];

  nixpkgs.config.allowBroken = true;

  home.packages = with pkgs; [
    lmstudio
    otherPkgs.pkgsStable.local-ai

    # localai
    vulkan-loader
    vulkan-tools
  ];

  # FIX: this is not in unstable yet so just copied it
  # services.local-ai = {
  #   enable = true;
  #   package = otherPkgs.pkgsStable.local-ai;
  #   environment = {
  #     LOCALAI_ADDRESS = "0.0.0.0:8090";
  #     LOCALAI_FORCE_META_BACKEND_CAPABILITY = "amd";
  #     # PRIMARY_MODEL = "starcoder2-15b-Q4_K_M.gguf";
  #     # SECONDARY_MODEL=wizardcoder-15b-Q4_K_M.gguf
  #     # DOWNLOAD_URL_PRIMARY=https://huggingface.co/second-state/StarCoder2-15B-GGUF/raw/main/starcoder2-15b-Q4_K_M.gguf
  #     # DOWNLOAD_URL_SECONDARY=https://huggingface.co/mradermacher/WizardCoder-15B-V1.0-GGUF/raw/main/wizardcoder-15b-Q4_K_M.gguf
  #   };
  # };
  #   systemd.user.services.local-ai = {
  #   Unit = {
  #     Description = "Server for local large language models";
  #     After = [ "network.target" ];
  #   };
  #
  #   Service = {
  #     ExecStart = lib.getExe cfg.package;
  #     Environment = lib.mapAttrsToList (key: val: "${key}=${val}") cfg.environment;
  #   };
  #
  #   Install = {
  #     WantedBy = [ "default.target" ];
  #   };
  # };

  # users.users.localai = {
  #   isSystemUser = true;
  #   extraGroups = [
  #     "video"
  #     "render"
  #   ];
  #   createHome = false;
  # };

  # systemd.tmpfiles.rules = [
  #   "d /var/lib/localai 0755 root localai -"
  #   "d /var/lib/localai/models 0755 root localai -"
  # ];

  # systemd.services.localai = {
  #   description = "LocalAI inference server";
  #   after = [ "network.target" ];
  #   wantedBy = [ "multi-user.target" ];
  #   serviceConfig = {
  #     User = "localai";
  #     Restart = "on-failure";
  #     Environment = "LOCALAI_MODELS_PATH=/var/lib/localai/models";
  #     ExecStart = "${localai}/bin/local-ai run --models-path /var/lib/localai/models --host 0.0.0.0 --port 8090 --enable-gpu";
  #     LimitNOFILE = 65536;
  #     LimitMEMLOCK = "unlimited";
  #   };
  # };

  ## Optionally: system-wide environment variables for model paths
  # environment.etc."localai/env/model_downloads.env".text = ''
  #   MODELS_DIR=/var/lib/localai/models
  #   PRIMARY_MODEL=starcoder2-15b-Q4_K_M.gguf
  #   SECONDARY_MODEL=wizardcoder-15b-Q4_K_M.gguf
  #   DOWNLOAD_URL_PRIMARY=https://huggingface.co/second-state/StarCoder2-15B-GGUF/raw/main/starcoder2-15b-Q4_K_M.gguf
  #   DOWNLOAD_URL_SECONDARY=https://huggingface.co/mradermacher/WizardCoder-15B-V1.0-GGUF/raw/main/wizardcoder-15b-Q4_K_M.gguf
  # '';

  ## Model-download service + timer
  # systemd.services.localai-model-update = {
  #   description = "Model download/update for LocalAI";
  #   wantedBy = [ "multi-user.target" ];
  #   serviceConfig = {
  #     Type = "oneshot";
  #     ExecStart = "${pkgs.bash}/bin/bash -lc 'source /etc/localai/env/model_downloads.env && \
  #                  mkdir -p \"$MODELS_DIR\" && \
  #                  cd \"$MODELS_DIR\" && \
  #                  [ ! -f \"$PRIMARY_MODEL\" ] && wget \"$DOWNLOAD_URL_PRIMARY\" -O \"$PRIMARY_MODEL\" || true && \
  #                  [ ! -f \"$SECONDARY_MODEL\" ] && wget \"$DOWNLOAD_URL_SECONDARY\" -O \"$SECONDARY_MODEL\" || true'";
  #   };
  # };
  #
  # systemd.timers.localai-model-update = {
  #   wantedBy = [ "timers.target" ];
  #   timerConfig = {
  #     OnCalendar = "daily";
  #     Persistent = true;
  #   };
  # };
}
