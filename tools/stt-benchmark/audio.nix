let
  pkgs = import ./pkgs.nix;
in
pkgs.stdenv.mkDerivation {
  pname = "audio-cpp-asr-vulkan";
  version = "2026-09-19";
  src = builtins.fetchTarball {
    url = "https://github.com/0xShug0/audio.cpp/archive/456c8e780211132ac480dce25b54962baa70c523.tar.gz";
    sha256 = "1f542vnbsl6iikhi68im0rv35vrak0mfvlbvw52krrpxv87px49p";
  };
  nativeBuildInputs = with pkgs; [
    cmake
    ninja
    pkg-config
    shaderc
  ];
  buildInputs = with pkgs; [
    vulkan-headers
    vulkan-loader
    spirv-headers
  ];
  cmakeFlags = [
    "-DENGINE_ENABLE_VULKAN=ON"
    "-DENGINE_ENABLE_NATIVE_CPU=OFF"
    "-DAUDIOCPP_MODEL_SET=custom"
    "-DAUDIOCPP_MODELS=vibevoice_asr"
    "-DAUDIOCPP_BUILD_NATIVE_MODEL_MANAGER=OFF"
    "-DENGINE_BUILD_TESTS=OFF"
  ];
  installPhase = ''
    runHook preInstall
    install -Dm755 bin/audiocpp_cli "$out/bin/audiocpp_cli"
    runHook postInstall
  '';
}
