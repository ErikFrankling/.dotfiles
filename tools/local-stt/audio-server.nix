(import ../stt-benchmark/audio.nix).overrideAttrs (_: {
  pname = "vibevoice-server-vulkan";
  installPhase = ''
    runHook preInstall
    install -Dm755 bin/audiocpp_server "$out/bin/audiocpp_server"
    runHook postInstall
  '';
})
