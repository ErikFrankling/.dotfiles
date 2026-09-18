let
  pkgs = import ./pkgs.nix;
in
pkgs.stdenv.mkDerivation {
  pname = "transcribe-cpp-vulkan";
  version = "2026-09-18";
  src = builtins.fetchTarball {
    url = "https://github.com/handy-computer/transcribe.cpp/archive/be7a8b35e9ba2df20298bd26e32d53407c3bcbcd.tar.gz";
    sha256 = "16r7lynqdkc61ycyychllvp4586ysggy0arn0slnma47m8yis4zh";
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
    "-DTRANSCRIBE_VULKAN=ON"
    "-DTRANSCRIBE_INSTALL=ON"
    "-DTRANSCRIBE_BUILD_TESTS=OFF"
    "-DTRANSCRIBE_USE_SYSTEM_BLAS=OFF"
    "-DGGML_NATIVE=OFF"
  ];
  postInstall = ''
    install -Dm755 bin/transcribe-cli "$out/bin/transcribe-cli"
  '';
}
