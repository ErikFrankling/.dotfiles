{ pkgs, ... }:

{
  hardware.keyboard.qmk.enable = true;

  environment.systemPackages = with pkgs; [ via qmk vial ];

  services.udev.packages = with pkgs; [ via vial ];
}
