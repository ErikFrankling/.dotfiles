# Factory-trusted shim -> MOK-signed systemd-boot -> Lanzaboote.
# Validated with this laptop's db/dbx in OVMF; see secure-boot-shim.md.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  signedShim = pkgs.stdenvNoCC.mkDerivation {
    pname = "samsung-signed-shim";
    version = "16.1-10";
    src = pkgs.fetchurl {
      url = "https://kojipkgs.fedoraproject.org/packages/shim/16.1/10/x86_64/shim-x64-16.1-10.x86_64.rpm";
      hash = "sha256-UMqK0PCJOptp0leyMsw4/lctfyyBS8muxN9eSSgAzcc=";
    };
    nativeBuildInputs = [ pkgs.rpmextract ];
    unpackPhase = ''rpmextract "$src"'';
    dontBuild = true;
    # Changing the PE binaries would invalidate their Microsoft signatures.
    dontFixup = true;
    installPhase = ''
      mkdir -p "$out"
      cp usr/lib/efi/shim/16.1-10/EFI/fedora/{shimx64,mmx64}.efi "$out/"
    '';
  };
  esp = config.boot.loader.efi.efiSysMountPoint;
  cert = toString config.boot.lanzaboote.publicKeyFile;
in
{
  environment.systemPackages = [
    pkgs.mokutil
    pkgs.efibootmgr
  ];

  # Lanzaboote 1.1 has no shim staging hook. Keep its installer unchanged,
  # then refresh the copy shim loads on EVERY rebuild boot/switch. A static
  # copy would silently leave an old systemd-boot behind after updates.
  system.build.installBootLoader = lib.mkForce (
    pkgs.writeShellScript "install-with-shim" ''
      set -euo pipefail
      export PATH=${
        lib.makeBinPath [
          pkgs.coreutils
          pkgs.gnutar
          pkgs.gnugrep
          pkgs.efibootmgr
          pkgs.openssl
          pkgs.sbsigntool
        ]
      }:$PATH
      backup=/var/lib/sbctl/pre-shim-backup
      if [ ! -e "$backup/esp.tar" ]; then
        install -d -m 0700 "$backup"
        efibootmgr -v > "$backup/boot-entries.txt"
        tar -C ${lib.escapeShellArg esp} -cf "$backup/esp.tar.new" .
        mv "$backup/esp.tar.new" "$backup/esp.tar"
      fi

      ${config.boot.loader.external.installHook} "$@"

      dest=${lib.escapeShellArg "${esp}/EFI/nixos-shim"}
      loader=${lib.escapeShellArg "${esp}/EFI/systemd/systemd-bootx64.efi"}
      sbverify --cert ${lib.escapeShellArg cert} "$loader"
      mkdir -p "$dest"
      # Only our separate directory is changed: no replacement of BOOT,
      # Microsoft or systemd paths, and no key enrollment or BootNext here.
      install -m 0644 ${signedShim}/shimx64.efi "$dest/shimx64.efi.new"
      install -m 0644 ${signedShim}/mmx64.efi "$dest/mmx64.efi.new"
      install -m 0644 "$loader" "$dest/grubx64.efi.new"
      openssl x509 -in ${lib.escapeShellArg cert} -outform DER -out "$dest/db.cer.new"
      for name in shimx64.efi mmx64.efi grubx64.efi db.cer; do
        mv "$dest/$name.new" "$dest/$name"
      done
      if ! efibootmgr -v | grep -Fqi '\EFI\nixos-shim\shimx64.efi'; then
        # --create-only registers a selectable entry without changing BootOrder.
        efibootmgr --create-only --disk /dev/nvme0n1 --part 1 \
          --label 'NixOS (shim)' --loader '\EFI\nixos-shim\shimx64.efi'
      fi
    ''
  );
}
