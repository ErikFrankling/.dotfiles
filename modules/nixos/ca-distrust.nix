{ ... }:

# Roots distrusted ahead of nixpkgs.
#
# 2026-10-21, eMudhra/emSign: eight intermediates under emSign ECC Root CA - G3
# had keys generated with almost no entropy (one was the integer 4), so anyone
# could recover them and sign a certificate for any site. Mozilla removed the
# root in NSS 3.131.1 (bug 2084101); nixos-unstable still ships cacert 3.126.
#   https://bugzilla.mozilla.org/show_bug.cgi?id=2083449
#   G3 SHA-256 86:A1:EC:BA:08:9C:4A:8D:3B:BE:27:34:C6:12:BA:34:1D:81:3E:04:3C:F9:E8:A8:62:CD:5C:57:A3:6B:BE:6B
# Drop the entry once `nix eval --raw nixpkgs#cacert.version` is >= 3.131.1.
# Mozilla kept emSign Root CA - G1, so it stays trusted here as well.
{
  security.pki.caCertificateBlacklist = [ "emSign ECC Root CA - G3" ];

  # Node.js compiles in its own copy of the Mozilla roots and ignores the list
  # above; 24.21.0 still trusts G3. --use-openssl-ca makes it read the system
  # bundle instead (NODE_EXTRA_CA_CERTS still applies). Electron logs that it
  # does not support the flag and carries on; Chromium has its own CRLSet fix.
  # Drop this together with the blacklist once nodejs ships the removal.
  environment.variables.NODE_OPTIONS = "--use-openssl-ca";
}
