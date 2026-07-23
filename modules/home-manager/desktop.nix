{
  lib,
  pkgs,
  otherPkgs,
  inputs,
  # system,
  ...
}:

{
  imports = [
    # ./firefox.nix
    ./waybar
    ./hyprland
    # ./eww
    # ./ags
    ./thunderbird.nix
    ./zen.nix
    ./kitty.nix
    ./ai.nix
    ./voxtype.nix
  ];

  home.packages = with pkgs; [
    webcord
    # otherPkgs.pkgsStable.webcord
    # otherPkgs.pkgsMaster.spotifywm
    spotifywm
    # spotify-qt
    pavucontrol
    otherPkgs.pkgsStable.google-chrome
    # gparted
    # virtualbox
    syncthingtray-minimal
    obsidian
    # otherPkgs.pkgsStable.obsidian
    # otherPkgs.pkgsMaster.obsidian
    # (inputs.ags-shell.packages.${system}.my-shell)
    inputs.ags-shell.packages."x86_64-linux".default
    mattermost-desktop
    # inputs.claude-desktop.packages.${system}.claude-desktop-with-fhs
    ghostty
    code-cursor
    zed-editor
  ];

  nixpkgs.config.permittedInsecurePackages = [
    "electron-36.9.5"
  ];

  services.syncthing.tray.enable = true;

  # Chrome on Linux uses its NSS database for locally trusted authorities.
  # Cloudflare WARP cannot manage that database on NixOS, so keep the account
  # Gateway CA installed declaratively for both desktop machines.
  home.activation.installHuskCloudflareGatewayCA = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    cert_db="$HOME/.pki/nssdb"
    cert_name="Husk Cloudflare Gateway CA"

    $DRY_RUN_CMD mkdir -p "$cert_db"
    if [ ! -f "$cert_db/cert9.db" ]; then
      $DRY_RUN_CMD ${pkgs.nssTools}/bin/certutil -N --empty-password -d "sql:$cert_db"
    fi

    $DRY_RUN_CMD ${pkgs.nssTools}/bin/certutil -D -d "sql:$cert_db" -n "$cert_name" >/dev/null 2>&1 || true
    $DRY_RUN_CMD ${pkgs.nssTools}/bin/certutil -A \
      -d "sql:$cert_db" \
      -n "$cert_name" \
      -t "C,," \
      -i ${../../certificates/cloudflare-gateway-ca.pem}
  '';
  gtk = {
    enable = true;
    theme = {
      name = "adw-gtk3-dark";
      package = pkgs.adw-gtk3;
    };
  };

  dconf.settings."org/gnome/desktop/interface" = {
    color-scheme = "prefer-dark";
    gtk-theme = "adw-gtk3-dark";
  };
}
