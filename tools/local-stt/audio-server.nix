(import ../stt-benchmark/audio.nix).overrideAttrs (old: {
  patches = (old.patches or [ ]) ++ [ ./release-prefill.patch ];
  pname = "vibevoice-server-vulkan";
  installPhase = ''
    runHook preInstall
    install -Dm755 bin/audiocpp_server "$out/bin/audiocpp_server"
    runHook postInstall
  '';
})
