{
  pkgs,
  inputs,
  username,
  ...
}:

{
  environment.systemPackages = with pkgs; [ sops ];

  imports = [ inputs.sops-nix.nixosModules.sops ];

  # sops.defaultSopsFile = ../../secrets/secrets.yaml;
  # sops.defaultSopsFormat = "yaml";

  sops.age.keyFile = "/home/user/.config/sops/age/keys.txt";
  sops.age.sshKeyPaths = [ "/home/${username}/.ssh/id_ed25519" ];
  sops.age.generateKey = true;

  # sops.secrets.example-key = { };
  # sops.secrets.syncthing.framework.cert = { };
  # sops.secrets.syncthing.framework.key = { };
}
