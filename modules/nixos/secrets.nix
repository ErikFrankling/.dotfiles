{ pkgs, inputs, ... }:

{
  environment.systemPackages = with pkgs; [
    sops
  ];

  imports = [ inputs.sops-nix.nixosModules.sops ];

  sops.defaultSopsFile = ./secrets/secrets.yaml;
  sops.defaultSopsFormat = "yaml";

  sops.age.keyFile = "/home/user/.config/sops/age/keys.txt";
  sops.age.sshKeyPaths = [ "/home/erikf/.ssh/id_ed25519" ];
  sops.age.generateKey = true;

  sops.secrets.example-key = { };
}
