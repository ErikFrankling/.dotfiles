{
  description = "Nixos config flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    # nixpkgs.url = "github:nixos/nixpkgs?rev=77b584d61ff80b4cef9245829a6f1dfad5afdfa3";
    # nixpkgs.url = "git+ssh://git@github.com/nixos/nixpkgs?ref=nixos-unstable&shallow=1";
    # nixpkgs.url = "git+ssh://git@github.com/NixOS/nixpkgs?ref=nixos-unstable";
    # nixpkgs.url = "git+ssh://git@github.com/NixOS/nixpkgs/refs/tags/nixos-unstable";
    # nixpkgs.url = "git+ssh://git@github.com/NixOS/nixpkgs.git";
    # nixpkgs.url = "github:nixos/nixpkgs/release-25.05";
    # nixpkgs.url = "github:nixos/nixpkgs/release-24.11";
    # nixpkgs.url = "git+ssh://git@github.com/NixOS/nixpkgs.git?ref=refs/heads/nixos-unstable";
    #nixpkgs.url = "git+ssh://git@github.com/NixOS/nixpkgs.git";

    # nixpkgs = {
    #   type = "git+ssh";
    #   owner = "NixOS";
    #   repo = "nixpkgs";
    #   # ref = "nixos-unstable";
    # };

    nixvim.url = "github:nix-community/nixvim";
    nixvim.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager";
    # home-manager.url = "github:nix-community/home-manager/release-24.11";
    # home-manager.url = "github:nix-community/home-manager/release-25.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    hyprland.url = "github:hyprwm/Hyprland";
    hyprland.inputs.nixpkgs.follows = "nixpkgs";

    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";

    xremap-flake.url = "github:xremap/nix-flake";
    xremap-flake.inputs.nixpkgs.follows = "nixpkgs";

    fw-fanctrl.url = "github:TamtamHero/fw-fanctrl/packaging/nix";
    fw-fanctrl.inputs.nixpkgs.follows = "nixpkgs";

    nix-matlab.url = "gitlab:doronbehar/nix-matlab";
    nix-matlab.inputs.nixpkgs.follows = "nixpkgs";

    # nvim.url = "github:ErikFrankling/nvim";
    nvim.url = "git+ssh://git@github.com/ErikFrankling/nvim.git";
    nvim.inputs.nixpkgs.follows = "nixpkgs";

    ags.url = "github:Aylur/ags";
    ags.inputs.nixpkgs.follows = "nixpkgs";

    nixos-wsl.url = "github:nix-community/NixOS-WSL/main";
    nixos-wsl.inputs.nixpkgs.follows = "nixpkgs";

    # ericsson-tools.url = "git+file:/home/erikf/work/ericsson-tools/";
    ericsson-tools.url = "git+ssh://git@github.com/ErikFrankling/ericsson-tools.git";
    # ericsson-tools.url = "git+https://github.com/ErikFrankling/ericsson-tools.git";
    ericsson-tools.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      # utils,
      ...
    }@inputs:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      nixosConfigurations = nixpkgs.lib.genAttrs [ "vm" "pc" "framework" "wsl" ] (
        hostName:
        let
          username = "erikf";
        in
        nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs hostName username; };
          modules = [
            ./hosts/${hostName}/configuration.nix
            # inputs.sops-nix.nixosModules.sops
          ] ++ (if hostName == "wsl" then [ inputs.nixos-wsl.nixosModules.default ] else [ ]);
        }
      );

      homeConfigurations = nixpkgs.lib.genAttrs [ "erikf" "efeirar" ] (
        username:

        let
          homeDirectory = "/home/${username}";
          configHome = "${homeDirectory}/.config";

          # pkgs = import nixpkgs {
          #   inherit system;
          #   config.allowUnfree = true;
          #   # config.xdg.configHome = configHome;
          #   # overlays = [ ];
          # };

        in
        inputs.home-manager.lib.homeManagerConfiguration {
          inherit
            pkgs
            # system
            # username
            # homeDirectory
            ;
          extraSpecialArgs = {
            inherit inputs username;
            hostName = "hm";
          };

          # stateVersion = "25.05";
          # configuration = import ./host/hm/home.nix;
          modules = [ ./hosts/hm/home.nix ];
        }
      );

    };

}
