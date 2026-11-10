# Secret Service for work apps without a second password prompt.
{ username, ... }:
let
  keyringDir = "/home/${username}/.local/share/keyrings";
in
{
  services.gnome.gnome-keyring.enable = true;
  home-manager.users.${username}.services.gnome-keyring = {
    enable = true;
    components = [ "secrets" ];
  };

  # Getty autologin and fingerprint unlock do not give PAM a password with
  # which to unlock an encrypted keyring. GNOME's supported passwordless
  # keyring format avoids prompts. Secrets are protected at rest by this
  # laptop's LUKS volume, NOT by independent keyring encryption; processes
  # running as this user can access them while the OS is running.
  # `f` seeds a missing keyring only; it never replaces saved app secrets.
  # Existing keyrings are retained. The default alias selects this one.
  systemd.tmpfiles.rules = [
    "d ${keyringDir} 0700 ${username} users -"
    "f ${keyringDir}/work-session.keyring 0600 ${username} users - [keyring]\\ndisplay-name=Work Session\\nctime=0\\nmtime=0\\nlock-on-idle=false\\nlock-after=false\\n"
    "f+ ${keyringDir}/default 0600 ${username} users - work-session"
  ];
}
