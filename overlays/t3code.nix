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
  t3code =
    (t3codeBase.override {
      t3code-unwrapped =
        # Upstream moved to electron_44 itself, so no electron override is needed;
        # nixpkgs_master must carry the Electron that T3 pins (44.9.3 since v0.1.2,
        # which blocks the compromised eMudhra CA keys).
        # nixpkgs_master now builds with Node 26 and pnpm 12 itself, so no nodejs override.
        t3codeBase.passthru.unwrapped.overrideAttrs (
          finalAttrs: oldAttrs: {
            version = "0.1.6";
            src = inputs.t3code-src;
            # Thread config must extend, not replace, the harness's MCP overrides.
            # The fork carries this fix itself now (dotted "mcp_servers.t3-code" key),
            # so the patch no longer applies; kept for reference.
            # patches = (oldAttrs.patches or [ ]) ++ [ ./t3code-preserve-mcp.patch ];
            patches = oldAttrs.patches or [ ];
            # Upstream postPatch now copies the SPDX license data itself.
            # Upstream nightlies move past the nixpkgs release, so the lock differs.
            pnpmDeps = otherPkgs.pkgsMaster.fetchPnpmDeps {
              inherit (finalAttrs)
                pname
                version
                src
                pnpmWorkspaces
                ;
              pnpm = otherPkgs.pkgsMaster.pnpm_12;
              fetcherVersion = 4;
              hash = "sha256-XqdfHBKTB1QnlqLBAdm2lqzVSGpSW99V0aedDNl24eQ=";
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
    }).overrideAttrs
      (oldAttrs: {
        # The desktop app is only a client of the t3code service, and it keeps
        # that saved connection in Electron safeStorage. keyring.nix is disabled
        # on purpose, so without this flag the fork forces gnome-libsecret, finds
        # no Secret Service and refuses to save the connection at all.
        # symlinkJoin bakes postBuild into buildCommand, so append there.
        # T3CODE_DICTATION_HOOK: the app runs it with recording|stopped while a
        # dictation records; on the PC it binds plain Enter to "send" (speak
        # module). Elsewhere the command does not exist and the app only warns.
        buildCommand = oldAttrs.buildCommand + ''
          wrapProgram "$out/bin/t3code-desktop" --add-flags "--password-store=basic" \
            --set-default T3CODE_DICTATION_HOOK t3-dictation-hook
        '';
      });
}
