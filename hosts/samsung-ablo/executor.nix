{
  config,
  pkgs,
  username,
  ...
}:
let
  # Upstream ships a standalone Linux runtime; nixpkgs has no package for
  # Executor 2. Repack it unchanged and run through the host's nix-ld.
  executor = pkgs.stdenvNoCC.mkDerivation {
    pname = "executor-local";
    version = "2.0.0-beta.24";
    src = pkgs.fetchurl {
      url = "https://github.com/UsefulSoftwareCo/executor/releases/download/executor%402.0.0-beta.24/executor-2.0.0-beta.24-linux-x64.tgz";
      sha256 = "78451d349150c365cc44717d6d45329ba4026af4a52cfa5de7c494532ce825b6";
    };
    installPhase = ''
      mkdir -p $out/libexec/executor $out/bin
      cp -a . $out/libexec/executor/
      ln -s $out/libexec/executor/executor $out/bin/executor
    '';
    dontFixup = true;
  };
in
{
  # Local mode uses device pairing, not hosted administrator passwords.
  # The upstream server binds only to loopback. Machine credentials protect
  # API access; neither harness needs interactive approvals to connect.
  environment.systemPackages = [ executor ];
  users.groups.executor-work = { };
  users.users.executor-work = {
    isSystemUser = true;
    group = "executor-work";
    home = "/var/lib/executor-work-local";
  };
  sops.secrets.executor-work-api-key.owner = username;
  sops.secrets.executor-work-encryption-key = { };
  sops.templates.executor-work-env.content = ''
    EXECUTOR_API_KEY=${config.sops.placeholder.executor-work-api-key}
    EXECUTOR_ENCRYPTION_KEY=${config.sops.placeholder.executor-work-encryption-key}
  '';
  systemd.services.executor-work = {
    description = "Ablo local Executor";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    environment = {
      EXECUTOR_DATA_DIR = "/var/lib/executor-work-local";
      EXECUTOR_PORT = "4788";
      DO_NOT_TRACK = "1";
      # Bundled workerd defaults to /etc/ssl/cert.pem, absent on NixOS.
      SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
    };
    serviceConfig = {
      ExecStart = "${executor}/bin/executor serve";
      User = "executor-work";
      Group = "executor-work";
      StateDirectory = "executor-work-local";
      StateDirectoryMode = "0700";
      EnvironmentFile = config.sops.templates.executor-work-env.path;
      Restart = "on-failure";
      RestartSec = 5;
      MemoryMax = "3G";
      CPUQuota = "200%";
      UMask = "0077";
    };
  };
}
