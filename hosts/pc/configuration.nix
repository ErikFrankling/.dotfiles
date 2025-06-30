{
  config,
  pkgs,
  inputs,
  hostName,
  username,
  ...
}:

{
<<<<<<< Updated upstream
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
    ../../modules/nixos
    # ../../modules/nixos/openvpn.nix
    # ../../modules/nixos/laptop.nix
    ../../modules/nixos/desktop.nix
    ../../modules/nixos/game.nix
    ../../modules/nixos/ollama.nix
    inputs.home-manager.nixosModules.default
  ];
=======
  imports =
    [
      # Include the results of the hardware scan.
      ./hardware-configuration.nix
      ../../modules/nixos
      # ../../modules/nixos/openvpn.nix
      # ../../modules/nixos/laptop.nix
      ../../modules/nixos/desktop.nix
      ../../modules/nixos/game.nix
      ../../modules/nixos/ollama.nix
      inputs.home-manager.nixosModules.default
    ];

  # fix for amdgpu kernel bug https://gitlab.freedesktop.org/drm/amd/-/issues/3388
  boot.kernelParams = [ "amdgpu.dcdebugmask=0x10" ];
>>>>>>> Stashed changes

  sops.defaultSopsFile = ./secrets.yaml;
  sops.defaultSopsFormat = "yaml";

  sops.secrets.syncthing-cert = { };
  sops.secrets.syncthing-key = { };

  networking.hostName = "pc"; # Define your hostname.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

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
    extraSpecialArgs = { inherit inputs hostName username; };
    users = {
      "${username}" = import ./home.nix;
    };
  };

  # Open ports in the firewall.
  networking.firewall.allowedTCPPorts = [
    8080
    8081
  ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    #  wget
  ];
}
