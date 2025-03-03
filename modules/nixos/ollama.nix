{ pkgs, ... }:

{
  services.open-webui.enable = true;
  services.ollama = {
    enable = true;
    acceleration = "rocm";

    environmentVariables = {
      HCC_AMDGPU_TARGET = "gfx1100"; # used to be necessary, but doesn't seem to anymore
    };
    rocmOverrideGfx = "11.0.0";
  };
}
