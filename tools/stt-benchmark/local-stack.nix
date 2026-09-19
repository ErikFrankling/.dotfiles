let
  pkgs = import ./pkgs.nix;
  runtime = import ./contextual-audio.nix;
  model = import ./default.nix { model = "vibevoice-asr-q8"; };
in pkgs.writeShellApplication {
  name = "local-stt";
  runtimeInputs = [ pkgs.python3 ];
  text = ''
    export LOCAL_STT_BINARY=${runtime}/bin/audiocpp_cli
    export LOCAL_STT_MODEL=${model}
    exec python3 ${./local_stack.py} "$@"
  '';
}
