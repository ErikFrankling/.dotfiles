{
  pkgs,
  lib,
  ...
}:
{
  programs.ssh = {
    package = lib.mkForce pkgs.openssh_gssapi;
    extraConfig = "IgnoreUnknown gssapikexalgorithms,gssapiauthentication,gssapidelegatecredentials";
  };

  # Kerberos is for kinit and GSSAPI SSH to KTH, not for local passwords.
  # The PAM modules it adds by default (pam_krb5, pam_ccreds) put every password
  # check through KTH; in hyprlock the ccreds helper hung, hyprlock never
  # exited after unlocking and `pidof hyprlock || hyprlock` then ignored every
  # lock request (samsung-ablo, 2026-11-10).
  security.pam.krb5.enable = false;

  security.krb5 = {
    enable = true;
    settings = {
      libdefaults = {
        default_realm = "KTH.SE";
        rdns = false;
        dns_lookup_kdc = true; # Let DNS find the KDC
        dns_lookup_realm = true;
      };
      realms = {
        "KTH.SE" = {
          kdc = [
            "kerberos.kth.se"
            "kerberos-1.kth.se"
            "kerberos-2.kth.se"
          ];
          admin_server = "kerberos.kth.se";
        };
      };
      domain_realm = {
        ".kth.se" = "KTH.SE";
        "kth.se" = "KTH.SE";
      };
    };
  };
}
