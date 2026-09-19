# Research runner: contextual shallow fusion inside the GPU speech decoder.
let
  pkgs = import ./pkgs.nix;
  base = import ./audio.nix;
in
base.overrideAttrs (old: {
  pname = "audio-cpp-contextual-asr-vulkan";
  nativeBuildInputs = old.nativeBuildInputs ++ [ pkgs.python3 ];
  postPatch = ''
    cp ${./contextual/phrase_bias.h} src/models/vibevoice_asr/phrase_bias.h
    python3 ${./contextual/patch_runtime.py}
  '';
  doCheck = true;
  checkPhase = ''
    $CXX -std=c++17 -I${./contextual} ${./contextual/test_phrase_bias.cpp} -o test-phrase-bias
    ./test-phrase-bias
  '';
})
