{
  config,
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
    # Replaced by ./erikshell.nix — my own Quickshell shell draws the bar now.
    # The waybar config, style and scripts are still in ./waybar; re-import this
    # line and comment out ./erikshell.nix to go back.
    # ./waybar
    ./erikshell.nix
    # What the shell's keys overlay reads on its Neovim page. Here rather than
    # beside the editor because the file exists for the shell.
    ./nvim-keymaps.nix
    ./hyprland
    # ./eww
    # ./ags
    ./thunderbird.nix
    ./mime-apps.nix
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
    # otherPkgs.pkgsStable.google-chrome # 2026-10-14: release-25.05 is frozen on Chrome 143, whose .deb Google has deleted, so a store that lacks it cannot build this
    google-chrome
    # gparted
    # virtualbox
    syncthingtray-minimal
    obsidian
    # otherPkgs.pkgsStable.obsidian
    # otherPkgs.pkgsMaster.obsidian
    # (inputs.ags-shell.packages.${system}.my-shell)
    # The AGS shell — `my-shell`, and the old notification daemon. Superseded by
    # ./erikshell.nix; the flake input and the AGS repo are untouched, so
    # uncommenting this line is all it takes to have it back on PATH.
    # inputs.ags-shell.packages."x86_64-linux".default
    mattermost-desktop
    libreoffice # docx/xlsx/odf editing
    # inputs.claude-desktop.packages.${system}.claude-desktop-with-fhs
    ghostty
    code-cursor
    zed-editor
    # Grok Bot desktop agent. See the grok-bot input in flake.nix for why this
    # flake and not the other one. Needs a SuperGrok or Cursor plan to log in.
    # Its package.nix hardcodes electron_42, which nixpkgs marked insecure (EOL)
    # on 2026-11-03. Every bundled .node module is pure N-API (no v8/node C++
    # symbols), so it runs on the supported default electron.
    (inputs.grok-bot.packages.${pkgs.stdenv.hostPlatform.system}.default.override {
      electron_42 = pkgs.electron;
    })
  ];

  nixpkgs.config.permittedInsecurePackages = [
    "electron-36.9.5"
  ];

  services.syncthing.tray.enable = true;

  # Husk retired 2026-11-09; retained as a configuration reference.
  # # Chrome on Linux uses its NSS database for locally trusted authorities.
  # # Cloudflare WARP cannot manage that database on NixOS, so keep the account
  # # Gateway CA installed declaratively for both desktop machines.
  # home.activation.installHuskCloudflareGatewayCA = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
  #   cert_db="$HOME/.pki/nssdb"
  #   cert_name="Husk Cloudflare Gateway CA"

  #   $DRY_RUN_CMD mkdir -p "$cert_db"
  #   if [ ! -f "$cert_db/cert9.db" ]; then
  #     $DRY_RUN_CMD ${pkgs.nssTools}/bin/certutil -N --empty-password -d "sql:$cert_db"
  #   fi

  #   $DRY_RUN_CMD ${pkgs.nssTools}/bin/certutil -D -d "sql:$cert_db" -n "$cert_name" >/dev/null 2>&1 || true
  #   $DRY_RUN_CMD ${pkgs.nssTools}/bin/certutil -A \
  #     -d "sql:$cert_db" \
  #     -n "$cert_name" \
  #     -t "C,," \
  #     -i ${../../certificates/cloudflare-gateway-ca.pem}
  # '';
  # Retire the persisted NSS copies too; removing an install policy alone
  # does not remove certificates it previously imported into browser profiles.
  home.activation.removeHuskCloudflareGatewayCA = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    expected=$(${pkgs.openssl}/bin/openssl x509 -in ${../../certificates/cloudflare-gateway-ca.pem} -outform DER | ${pkgs.coreutils}/bin/sha256sum)
    for cert_db in "$HOME/.pki/nssdb" "$HOME"/.mozilla/firefox/*; do
      [ -f "$cert_db/cert9.db" ] || continue
      for cert_name in "Husk Cloudflare Gateway CA" "Gateway CA - Cloudflare Managed G2 30ce68fb6a2cf6dcf76d849cff087a97 - Cloudflare, Inc."; do
        actual=$(${pkgs.nssTools}/bin/certutil -L -d "sql:$cert_db" -n "$cert_name" -a 2>/dev/null | ${pkgs.openssl}/bin/openssl x509 -outform DER 2>/dev/null | ${pkgs.coreutils}/bin/sha256sum) || continue
        if [ "$actual" = "$expected" ]; then
          $DRY_RUN_CMD ${pkgs.nssTools}/bin/certutil -D -d "sql:$cert_db" -n "$cert_name"
        fi
      done
    done
  '';

  gtk = {
    enable = true;

    theme = {
      name = "adw-gtk3-dark";
      package = pkgs.adw-gtk3;
    };

    # The piece that was missing. adw-gtk3 6.5 selects its dark palette with
    # `@media (prefers-color-scheme: dark)`, and that query only matches once
    # gtk-application-prefer-dark-theme is actually set — dconf and the desktop
    # portal saying "prefer-dark" is not enough, because GTK 4 reads the theme
    # from ~/.config/gtk-4.0/gtk.css at user priority. Without this every GTK 4
    # app fell through to the light @define-colors.
    colorScheme = "dark";

    # Home Manager stopped applying gtk.theme to GTK 4 by default (stateVersion
    # 26.05). Keep the old behaviour so GTK 4 apps stay on adw-gtk3-dark.
    gtk4.theme = config.gtk.theme;
  };

  dconf.settings."org/gnome/desktop/interface" = {
    color-scheme = "prefer-dark";
    gtk-theme = "adw-gtk3-dark";
  };
}
