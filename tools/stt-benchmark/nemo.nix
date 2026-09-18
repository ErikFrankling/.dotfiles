let
  pkgs = import ./pkgs.nix;
  ggml = builtins.fetchTarball {
    url = "https://github.com/ggml-org/ggml/archive/c03b4e2bcece5134827881af90242086daf75be5.tar.gz";
    sha256 = "1cb3ji3smqkfmx41khg77ijkfv572wj054nfmxvd4b2r8p22wccd";
  };
in
pkgs.stdenv.mkDerivation {
  pname = "nemo-speech-asr-vulkan";
  version = "2026-09-18";
  src = builtins.fetchTarball {
    url = "https://github.com/NVIDIA/NeMo-Speech.cpp/archive/07003daa7eefea542076310722ccaa89709ee3c3.tar.gz";
    sha256 = "0ylsmisbmnzasalg7cvpppc4yjn3xqxc3n8m4vdcabwdivm0sahf";
  };
  nativeBuildInputs = with pkgs; [
    cmake
    ninja
    pkg-config
    shaderc
  ];
  buildInputs = with pkgs; [
    sentencepiece
    abseil-cpp
    vulkan-headers
    vulkan-loader
    spirv-headers
    curl
  ];
  postUnpack = ''
    cp -r ${ggml}/. "$sourceRoot/ggml/"
    chmod -R u+w "$sourceRoot/ggml"
  '';
  cmakeFlags = [
    "-DGGML_VULKAN=ON"
    "-DGGML_NATIVE=OFF"
    "-DNEMO_SPEECH_GGML_PATCHED=OFF"
    "-DNEMO_SPEECH_BUILD_TTS=OFF"
    "-DNEMO_SPEECH_BUILD_DIAR=OFF"
    "-DNEMO_SPEECH_BUILD_MIC_CAPTURE=OFF"
    "-DNEMO_SPEECH_BUILD_HTTP=OFF"
  ];
}
