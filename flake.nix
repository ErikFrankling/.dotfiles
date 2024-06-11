{
  description = "Nixos config flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    nixvim = {
      url = "github:nix-community/nixvim";

      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, ... }@inputs:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {

      nixosConfigurations.default = nixpkgs.lib.nixosSystem {
          specialArgs = {inherit inputs;};
          modules = [ 
            ./hosts/default/configuration.nix
            inputs.sops-nix.nixosModules.sops
          ];
        };
    
      nixosConfigurations.vm = nixpkgs.lib.nixosSystem {
          specialArgs = {inherit inputs;};
          modules = [ 
<<<<<<< HEAD
            ./hosts/pc/configuration.nix
            inputs.sops-nix.nixosModules.sops
=======
            ./hosts/vm/configuration.nix
>>>>>>> 5c0c1c11b87a5d3ae28644b51cfe58270f43f7fb
          ];
        };

      nixosConfigurations.framework = nixpkgs.lib.nixosSystem {
          specialArgs = {inherit inputs;};
          modules = [ 
            ./hosts/framework/configuration.nix
            inputs.sops-nix.nixosModules.sops
          ];
        };
    };
}
