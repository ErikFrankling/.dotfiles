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
in
{
  t3code = t3codeBase.override {
    t3code-unwrapped =
      # Upstream moved to electron_44 itself, so no electron override is needed.
      t3codeBase.passthru.unwrapped.overrideAttrs (
        finalAttrs: oldAttrs: {
          version = "0.0.42";
          src = inputs.t3code-src;
          # Upstream postPatch now copies the SPDX license data itself.
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
            hash = "sha256-S8LAyBlmZMS/DGVV8EjRHqBlOHqe+N4eaKBSwPO3Uks=";
          };

          # node-pty ships a prebuilt pty.node that needs libstdc++ but has no
          # rpath for it. Node already has libstdc++ loaded, so `t3 serve`
          # works; Electron links libc++ statically, so the desktop app's
          # backend died on startup and no window ever opened.
          postFixup = (oldAttrs.postFixup or "") + ''
            find "$out"/libexec/t3code \
              -path '*/node-pty/prebuilds/linux-${prev.stdenv.hostPlatform.node.arch}/pty.node' \
              -exec ${otherPkgs.pkgsMaster.patchelf}/bin/patchelf \
                --add-rpath ${prev.lib.getLib otherPkgs.pkgsMaster.stdenv.cc.cc}/lib {} +
          '';
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
