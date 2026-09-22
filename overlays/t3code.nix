# Build Erik's source fork; auth, protocol and dictation changes live there.
# Keep the historical bundle patch file for reference, but do not apply it.
{
  inputs,
  otherPkgs,
  codexPackage ? null,
  claudePackage ? null,
}:
final: prev:
let
  system = prev.stdenv.hostPlatform.system;
  t3codeBase = otherPkgs.pkgsMaster.t3code;
  # Match the license generator's pinned SPDX revision for offline builds.
  spdxLicenses = prev.fetchFromGitHub {
    owner = "spdx";
    repo = "license-list-data";
    rev = "c4a7237ec8f4654e867546f9f409749300f1bf4c";
    hash = "sha256-FbeeEBAg9ih6DkAsXdU6ruZwkC7A2u2zYBvblpl54q0=";
  };
in
{
  t3code = t3codeBase.override {
    t3code-unwrapped =
      (t3codeBase.passthru.unwrapped.override {
        electron_43 = otherPkgs.pkgsMaster.electron_44;
      }).overrideAttrs
        (
          finalAttrs: oldAttrs: {
            version = "0.0.42";
            src = inputs.t3code-src;
            postPatch = (oldAttrs.postPatch or "") + ''
              mkdir -p .generated/third-party-licenses/spdx/v3.28.0
              cp ${spdxLicenses}/json/details/*.json .generated/third-party-licenses/spdx/v3.28.0/
            '';
            # Upstream updates and Mermaid change the fork's dependency lock.
            pnpmDeps = otherPkgs.pkgsMaster.fetchPnpmDeps {
              inherit (finalAttrs)
                pname
                version
                src
                pnpmWorkspaces
                ;
              pnpm = otherPkgs.pkgsMaster.pnpm_11;
              fetcherVersion = 4;
              hash = "sha256-XibgRj37k63e/4OAZNgcD9ATwhX+0JvfI60aePn9BVU=";
            };
          }
        );
    t3code-resource-monitor = t3codeBase.passthru.resourceMonitor;

    # Agent CLIs come from llm-agents everywhere else in this config; hand T3
    # the same binaries instead of the nixpkgs ones it would otherwise use.
    codex = if codexPackage != null then codexPackage else inputs.llm-agents.packages.${system}.codex;
    claude-code =
      if claudePackage != null then claudePackage else inputs.llm-agents.packages.${system}.claude-code;
    enableClaude = true;
  };
}
