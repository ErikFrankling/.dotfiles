{ config, pkgs, inputs, ... }:

{
  imports = [
  ];

  environment.systemPackages = with pkgs; [
    syncthing
  ];


  services.syncthing = {
    enable = true;
    openDefaultPorts = true;

    user = "erikf";
    dataDir = "/home/erikf/";
    configDir = "/home/erikf/.config/syncthing";

    cert = config.sops.secrets.syncthing-cert.path;
    key = config.sops.secrets.syncthing-key.path;
    
    # Optional: GUI credentials (can be set in the browser instead if you don't want plaintext credentials in your configuration.nix file)
    # or the password hash can be generated with "syncthing generate --config <path> --gui-password=<password>"
    extraFlags = [
      # "-gui-user=erikf"
      # "-gui-password=$2a$10$37qLqbmVQzZdNUkYUeVOgeRuMKtXlJSQRwBouCvJvsXRoi53Ggc3."
      "-no-default-folder" # Don't create default ~/Sync folder
    ];

    settings = {
      devices = {
        "ubuntu-hp" = { id = "J6ZOL7B-OJY3YCW-FXJIFME-LTCOXSW-4VMXDWZ-ISUONNV-Z4W4ZMU-63YDKA2"; };
        "framework" = { id = "N3IDYYF-3ZANKMD-NIQN2ZJ-HKTS2OP-HVKYCZY-SF7XB6G-7U2DWTD-YIHHJQI"; };
        "SM-S901B" = { id = "6N4J2HT-JPZLVQF-RSHUGEA-G6YV2YP-CEPIAL2-Q2TTTUX-KUZ36BR-Z5RJEQY"; };
      };
      folders = {
        "obsidian" = {
          path = "~/obsidian";
          id = "obsidian";
          devices = [ "ubuntu-hp" "framework" "SM-S901B" ];
          versioning.type = "staggered";
          type = "sendreceive";
        };
        "sync" = {
          path = "~/sync";
          id = "sync";
          devices = [ "ubuntu-hp" "framework" ];
          versioning.type = "staggered";
          type = "sendreceive";
        };
        # "Camera" = {
        #   path = "~/Camera";
        #   id = "sm-s901b_ud9q-photos";
        #   devices = [ "ubuntu-hp" "framework" "SM-S901B" ];
        # };
      };
    };
  };
}
