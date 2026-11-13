{ pkgs, ... }:

# YubiKeys are for website logins only (Erik, 2026-11-13): security key as
# the second step on Google, GitHub, Microsoft, OpenAI and 1Password. No GPG,
# SSH, sudo or screen lock (see Obsidian Life/YubiKey.md). Browsers talk to
# the key directly; systemd's 60-fido-id udev rule already gives the logged-in
# user access. This only adds the management tools:
#   ykman             CLI: ykman info, ykman fido info, ykman fido access change-pin
#   Yubico Authenticator  GUI for the same (PIN, passkeys on the key, reset)
# pcscd lets both reach the smart-card interface too; without it ykman warns
# "PC/SC not available" and lists the key twice.
# The old GPG/SSH-on-YubiKey setup is kept, disabled, in ./yubikey-gpg.nix.
{
  environment.systemPackages = with pkgs; [
    yubikey-manager
    yubioath-flutter
  ];

  services.pcscd.enable = true;
}
