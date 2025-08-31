{ pkgs, pkgsMaster, ... }:

{
  environment.systemPackages = with pkgs; [
    nvtopPackages.amd
  ];

  services.open-webui = {
    enable = true;
    stateDir = "/var/lib/open-webui";
    environment = {
      # Disable authentication
      WEBUI_AUTH = "False";
      ENABLE_PERSISTENT_CONFIG = "False"; # force env vars to always win
    };
  };

  services.ollama = {
    package = pkgsMaster.ollama-rocm;
    enable = true;
    acceleration = "rocm";

    environmentVariables = {
      OLLAMA_DEBUG = "1";
      OLLAMA_LOG_LEVEL = "debug";
      HCC_AMDGPU_TARGET = "gfx1100"; # used to be necessary, but doesn't seem to anymore
    };
    rocmOverrideGfx = "11.0.0";
  };
}
