{ pkgs, otherPkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    nvtopPackages.amd
  ];

  networking.firewall.allowedTCPPorts = [ 11434 ];

  services.open-webui = {
    enable = true;
    package = otherPkgs.pkgsStable.open-webui;
    stateDir = "/var/lib/open-webui";
    environment = {
      # Disable authentication
      WEBUI_AUTH = "False";
      ENABLE_PERSISTENT_CONFIG = "False"; # force env vars to always win
    };
  };

  services.ollama = {
    # package = otherPkgs.pkgsMaster.ollama-rocm;
    # package = otherPkgs.pkgsStable.ollama-rocm;
    package = pkgs.ollama-rocm;
    enable = true;
    host = "0.0.0.0";

    environmentVariables = {
      OLLAMA_CONTEXT_LENGTH = "4194304";
      OLLAMA_DEBUG = "1";
      OLLAMA_LOG_LEVEL = "debug";
      HCC_AMDGPU_TARGET = "gfx1100"; # used to be necessary, but doesn't seem to anymore
      # Optional: ensure ROCm is initialized before Ollama
      ROC_ENABLE_PRE_VEGA = "1";
      OLLAMA_NO_CPU_FALLBACK = "1";
      # OLLAMA_HOST = "0.0.0.0:11434";
    };
    rocmOverrideGfx = "11.0.0";
  };
}
