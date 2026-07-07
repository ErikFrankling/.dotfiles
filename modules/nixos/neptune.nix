{ ... }:

# Neptune dev cluster trust.
#
# The Naiaclaw / Planet9 instance at https://naiaclaw.dev.neptune-software.cloud
# is served by the Dev-01 cluster's `letsencrypt-prod-gateway-api` ClusterIssuer,
# which (despite its name) issues Let's Encrypt *staging* certificates. Staging
# certs chain to LE's test root ("Pretend Pear X1" / "Yonder Yam Root YR"), which
# is not in any default trust store, so Node/curl/git reject it with
# UNABLE_TO_GET_ISSUER_CERT_LOCALLY.
#
# This is a local workaround so Claude Code's MCP client (and CLI tools) can reach
# the dev endpoint until the platform issuer is repointed at LE production. The
# bundle only adds LE *staging* anchors, so it does not weaken trust for real CAs.
#
# Bundle source (regen if the cluster reissues):
#   openssl s_client -connect naiaclaw.dev.neptune-software.cloud:443 \
#     -servername naiaclaw.dev.neptune-software.cloud -showcerts </dev/null 2>/dev/null \
#     | awk '/BEGIN CERTIFICATE/{c++} c>=2{print}' > neptune-le-staging-ca.pem

let
  neptuneStagingCA = ./neptune-le-staging-ca.pem;
in
{
  # System-wide trust (curl, git, openssl, ...).
  security.pki.certificateFiles = [ neptuneStagingCA ];

  # Node.js (Claude Code) uses its own bundled CA list, not the system store,
  # so it needs the extra CA pointed at explicitly.
  environment.variables.NODE_EXTRA_CA_CERTS = "${neptuneStagingCA}";
}
