{ config, pkgs, inputs, ... }:

{
  imports = [ ];

  services.udev.extraRules = ''
    # USB-Blaster
    SUBSYSTEM=="usb", ATTRS{idVendor}=="09fb", ATTRS{idProduct}=="6001", MODE="0666"
    SUBSYSTEM=="usb", ATTRS{idVendor}=="09fb", ATTRS{idProduct}=="6002", MODE="0666"
    SUBSYSTEM=="usb", ATTRS{idVendor}=="09fb", ATTRS{idProduct}=="6003", MODE="0666"
    # USB-Blaster II
    SUBSYSTEM=="usb", ATTRS{idVendor}=="09fb", ATTRS{idProduct}=="6010", MODE="0666"
    SUBSYSTEM=="usb", ATTRS{idVendor}=="09fb", ATTRS{idProduct}=="6810", MODE="0666"
  '';

  environment.systemPackages = with pkgs;
    [
      killall
      # TODO: Needs older version
      # quartus-prime-lite 
    ];
}
