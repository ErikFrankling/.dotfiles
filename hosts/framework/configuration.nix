{ config, pkgs, inputs, hostName, ... }:

{
  imports =
    [
      # Include the results of the hardware scan.
      ./hardware-configuration.nix
      ../../modules/nixos
      ../../modules/nixos/openvpn.nix
      ../../modules/nixos/laptop.nix
      ../../modules/nixos/desktop.nix
      ../../modules/nixos/game.nix
      inputs.home-manager.nixosModules.default
      inputs.fw-fanctrl.nixosModules.default
    ];


  sops.defaultSopsFile = ./secrets.yaml;
  sops.defaultSopsFormat = "yaml";

  sops.secrets.syncthing-cert = { };
  sops.secrets.syncthing-key = { };


  # Open ports in the firewall.
  networking.firewall.allowedTCPPorts = [ 8080 ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  networking.hostName = "framework"; # Define your hostname.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Enable fw-fanctrl
  programs.fw-fanctrl.enable = true;

  # Add a custom config
  programs.fw-fanctrl.config = {
    defaultStrategy = "very-agile";
    strategies = {
      "very-agile" = {
        fanSpeedUpdateFrequency = 5;
        movingAverageInterval = 30;
        speedCurve = [
          { temp = 0; speed = 15; }
          { temp = 50; speed = 15; }
          { temp = 65; speed = 35; }
          { temp = 70; speed = 40; }
          { temp = 75; speed = 50; }
          { temp = 80; speed = 80; }
          { temp = 85; speed = 100; }
        ];
      };
    };
  };
  # enables updating firmware without booting to bios
  services.fwupd.enable = true;

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # fix for amdgpu kernel bug https://gitlab.freedesktop.org/drm/amd/-/issues/3388
  boot.kernelParams = [ "amdgpu.dcdebugmask=0x10" ];

  # Configure keymap in X11
  services.xserver = {
    xkb = {
      variant = "";
      layout = "us";
    };
  };

  # Configure console keymap
  # console.keyMap = "sv-latin1";

  home-manager = {
    # also pass inputs to home-manager modules
    extraSpecialArgs = { inherit inputs hostName; };
    users = {
      "erikf" = import ./home.nix;
    };
  };

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    #  wget
    swiPrologWithGui
    fw-ectool
  ];
}
