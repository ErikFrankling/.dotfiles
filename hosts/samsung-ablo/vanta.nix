# Vanta Device Monitor: Vanta's own Linux agent, run the way its Debian
# package runs it (/var/vanta, vanta.service, /etc/vanta.conf).
#
# Vanta does not support NixOS and its installer refuses it, so this unpacks
# the official .deb. The binaries run unpatched through nix-ld (enabled for
# every host in modules/nixos/default.nix), so the agent's own updates, which
# it downloads into /var/vanta, keep working. Tested locally 2026-11-02
# (~/projects/ablo/research/vanta-nixos/README.md).
#
# Registration: the per-company secret key from
# https://app.vanta.com/computers?tab=unmonitored goes into this host's sops
# file as `vanta-key`; the service writes /etc/vanta.conf from it once, as the
# package's postinst does. Status: `sudo /var/vanta/vanta-cli status`.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  ownerEmail = "erik@abloatai.com";
  region = "us";
  hasKey = config.sops.secrets ? vanta-key;

  vanta = pkgs.stdenvNoCC.mkDerivation rec {
    pname = "vanta-device-monitor";
    version = "2.21.0";
    src = pkgs.fetchurl {
      url = "https://agent-downloads.vanta.com/targets/versions/${version}/vanta-amd64.deb";
      sha256 = "ffd83ef40351e701346e440e20be74f6850a2a6d4b7ed13c3a7069a46c8041d1";
    };
    nativeBuildInputs = [ pkgs.dpkg ];
    unpackPhase = "dpkg-deb -x $src .";
    installPhase = "cp -a var/vanta $out";
    # Runs through nix-ld as shipped; patching would only be undone by the
    # agent's self-update.
    dontFixup = true;
    meta.platforms = [ "x86_64-linux" ];
  };
in
{
  programs.nix-ld.enable = true;

  systemd.services.vanta = {
    description = "Vanta monitoring software";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    # What the agent and its osquery shell out to on a Debian system.
    path = with pkgs; [
      coreutils
      util-linux
      cryptsetup
      lvm2
      systemd
      gnugrep
      gawk
      procps
    ];
    preStart = ''
      install -d -m 0755 /var/vanta
      # The packaged files, without touching what the agent has downloaded.
      cp -a --no-preserve=ownership ${vanta}/. /var/vanta/
      chmod -R u+w /var/vanta

      if ! grep -q '"AGENT_KEY": *"[^"]' /etc/vanta.conf 2>/dev/null; then
        ${
          if hasKey then
            ''
              printf '{"ACTIVATION_REQUESTED_NONCE":%s000,"AGENT_KEY":"%s","OWNER_EMAIL":"%s","REGION":"%s","NEEDS_OWNER":true}\n' \
                "$(date +%s)" "$(cat ${config.sops.secrets.vanta-key.path})" ${lib.escapeShellArg ownerEmail} ${lib.escapeShellArg region} \
                > /etc/vanta.conf
            ''
          else
            ''
              echo "vanta: no vanta-key in sops yet; running unregistered"
              printf '{"AGENT_KEY":"","OWNER_EMAIL":"","NEEDS_OWNER":true}\n' > /etc/vanta.conf
            ''
        }
        chmod 600 /etc/vanta.conf
      fi
    '';
    serviceConfig = {
      ExecStart = "/var/vanta/metalauncher";
      Restart = "on-failure";
      KillMode = "control-group";
      TimeoutStartSec = 0;
    };
  };
}
