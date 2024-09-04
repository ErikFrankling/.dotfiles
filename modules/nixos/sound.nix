{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    qpwgraph
  ];
  # Enable sound with pipewire.
  # sound.enable = true; # not ment to be used with pipwire
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
  };
}
