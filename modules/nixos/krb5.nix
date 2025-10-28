{
  pkgs,
  lib,
  ...
}:
{
  programs.ssh.package = lib.mkForce pkgs.openssh_gssapi;

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
